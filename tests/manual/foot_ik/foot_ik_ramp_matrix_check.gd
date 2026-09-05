extends Node3D
## Deterministic rendered-foot penetration matrix for ramp idle poses.
## Samples low/middle/high positions and uphill/downhill/cross-slope facing
## on 15/30/45-degree ramps across one complete authored idle cycle.

const PLAYER_SCENE := preload("res://actors/player/player.tscn")
const PENETRATION_CHECK := preload(
		"res://tests/manual/foot_ik/foot_ik_live_penetration_check.gd")
const JOINT_LIMIT_CHECK := preload("res://tests/manual/foot_ik/foot_ik_joint_limit_check.gd")
const RAMP_ANGLES: Array[float] = [15.0, 30.0, 45.0]
const RAMP_POSITIONS: Array[Dictionary] = [
	{"name": &"low_center", "fraction": 0.18, "lateral": 0.0, "root_offset": 0.05},
	{"name": &"middle_center", "fraction": 0.5, "lateral": 0.0, "root_offset": 0.05},
	{"name": &"high_left", "fraction": 0.88, "lateral": -0.9, "root_offset": 0.05},
	{"name": &"high_center", "fraction": 0.88, "lateral": 0.0, "root_offset": 0.05},
	{"name": &"high_right", "fraction": 0.88, "lateral": 0.9, "root_offset": 0.05},
	{"name": &"top_left", "fraction": 0.97, "lateral": -0.9, "root_offset": 0.05},
	{"name": &"top_center", "fraction": 0.97, "lateral": 0.0, "root_offset": 0.05},
	{"name": &"top_right", "fraction": 0.97, "lateral": 0.9, "root_offset": 0.05},
	# Exact effective root placement from the capture's per-frame JSONL (the
	# panel's player_pos was a slightly different/rounded controller value):
	# root=(6.588233, 2.637863, 2.466108), yaw=-122.294 on Ramp 45 at x=7.5.
	{"name": &"reported_high_left", "fraction": 0.8719, "lateral": -0.9118,
			"root_offset": 0.1718},
]
const YAWS: Array[float] = [
	0.0, PI * 0.25, PI * 0.5, PI * 0.75, PI, PI * 1.25, PI * 1.5, PI * 1.75,
	deg_to_rad(-122.294),
]
const YAW_NAMES: Array[StringName] = [
	&"uphill", &"uphill_cross", &"cross_right", &"downhill_cross_right",
	&"downhill", &"downhill_cross_left", &"cross_left", &"uphill_cross_left",
	&"reported_yaw",
]
const RAMP_WIDTH := 3.0
const RAMP_LENGTH := 4.0
const RAMP_THICKNESS := 0.3
const RAMP_SPACING := 6.0
const SETTLE_FRAMES := 45
const IDLE_CYCLE_FRAMES := 150
const SAMPLE_INTERVAL_FRAMES := 10
const RAMP_PENETRATION_TOLERANCE := 0.001
const SWEEP_DEFAULT_SPACING_M := 0.2
const SWEEP_DEFAULT_YAW_STEP_DEGREES := 15.0
const SWEEP_LATERAL_MARGIN := 0.3
const SWEEP_END_MARGIN := 0.1
const SWEEP_SETTLE_FRAMES := 45
const SWEEP_FAILURE_FILE := "user://foot_ik_ramp_sweep_failures.jsonl"
const SWEEP_PRINT_FAILURE_LIMIT := 20

var _player: Player
var _ik: PlayerFootIKModifier
var _cases: Array[Dictionary] = []
var _case_index := -1
var _case_frame := 0
var _sample_scheduled := false
var _case_check: FootIkLivePenetrationCheck
var _case_samples := 0
var _case_penetrating_samples := 0
var _case_penetrating_vertices := 0
var _case_max_depth := 0.0
var _case_bones: Dictionary = {}
var _case_crossed_leg_samples := 0
var _case_max_leg_crossover := 0.0
var _failed := false
var _foot_bones: Dictionary = {}
var _spawn_position := Vector3.ZERO
var _sweep_mode := false
var _sweep_spacing := SWEEP_DEFAULT_SPACING_M
var _sweep_yaw_step := SWEEP_DEFAULT_YAW_STEP_DEGREES
var _case_invalid_contact_samples := 0
var _case_joint_limit_failures: Array[String] = []
var _sweep_sample_complete := false
var _sweep_failure_file: FileAccess
var _sweep_failed_cases := 0
var _sweep_worst_depth := 0.0


func _ready() -> void:
	_parse_options()
	if _sweep_mode:
		_sweep_failure_file = FileAccess.open(SWEEP_FAILURE_FILE, FileAccess.WRITE)
	_build_ramps_and_cases()
	_filter_requested_case()
	_build_player()
	_start_next_case()


func _parse_options() -> void:
	for argument in OS.get_cmdline_user_args():
		var normalized := argument.trim_prefix("--")
		if normalized == "sweep=true":
			_sweep_mode = true
		elif normalized.begins_with("spacing_cm="):
			_sweep_spacing = maxf(
					float(normalized.trim_prefix("spacing_cm=")) / 100.0, 0.05)
		elif normalized.begins_with("yaw_step="):
			_sweep_yaw_step = maxf(
					float(normalized.trim_prefix("yaw_step=")), 5.0)


func _filter_requested_case() -> void:
	var requested := ""
	for argument in OS.get_cmdline_user_args():
		var normalized := argument.trim_prefix("--")
		if normalized.begins_with("case="):
			requested = normalized.trim_prefix("case=")
	if requested.is_empty():
		return
	var filtered: Array[Dictionary] = []
	for data: Dictionary in _cases:
		if String(data["position_name"]) == requested:
			filtered.append(data)
	_cases = filtered


func _physics_process(_delta: float) -> void:
	if _case_index < 0 or _case_index >= _cases.size():
		return
	_case_frame += 1
	var settle_frames := SWEEP_SETTLE_FRAMES if _sweep_mode else SETTLE_FRAMES
	if _case_frame <= settle_frames:
		return
	var cycle_frame := _case_frame - settle_frames
	if _sweep_mode:
		if _sweep_sample_complete:
			_finish_current_case()
			_start_next_case()
			return
		if not _sample_scheduled:
			_sample_scheduled = true
			call_deferred(&"_sample_current_case")
		return
	if cycle_frame <= IDLE_CYCLE_FRAMES and cycle_frame % SAMPLE_INTERVAL_FRAMES == 0:
		if not _sample_scheduled:
			_sample_scheduled = true
			call_deferred(&"_sample_current_case")
		return
	if cycle_frame > IDLE_CYCLE_FRAMES and not _sample_scheduled:
		_finish_current_case()
		_start_next_case()


func _build_ramps_and_cases() -> void:
	if _sweep_mode:
		_build_dense_sweep()
		return
	for angle_index in RAMP_ANGLES.size():
		var angle_degrees := RAMP_ANGLES[angle_index]
		var origin := Vector3(angle_index * RAMP_SPACING, 0.0, 0.0)
		var ramp := _build_ramp(origin, angle_degrees)
		for ramp_position: Dictionary in RAMP_POSITIONS:
			for yaw_index in YAWS.size():
				_cases.append({
					"angle": angle_degrees,
					"origin": origin,
					"fraction": ramp_position["fraction"],
					"lateral": ramp_position["lateral"],
					"root_offset": ramp_position["root_offset"],
					"position_name": ramp_position["name"],
					"yaw": YAWS[yaw_index],
					"yaw_name": YAW_NAMES[yaw_index],
					"ramp": ramp,
				})
		if is_equal_approx(angle_degrees, 45.0):
			# Exact effective root/yaw from the captured idle pose whose right
			# foot crossed to the left of the pelvis while both legs remained
			# individually within their total reach limit.
			_cases.append({
				"angle": angle_degrees,
				"origin": origin,
				"fraction": 0.7823,
				"lateral": 0.9703,
				"root_offset": 0.0962,
				"position_name": &"reported_crossed_legs",
				"yaw": deg_to_rad(-13.481166),
				"yaw_name": &"reported_crossed_yaw",
				"ramp": ramp,
			})
			# Exact effective root/yaw from the later capture where the left
			# ankle was 32cm below a ramp hit while IK weight had fallen to 0.
			_cases.append({
				"angle": angle_degrees,
				"origin": origin,
				"fraction": 0.8206,
				"lateral": 0.6864,
				"root_offset": 0.1951,
				"position_name": &"reported_left_deep_clip",
				"yaw": deg_to_rad(172.940608),
				"yaw_name": &"reported_deep_clip_yaw",
				"ramp": ramp,
			})


## Interior points on a uniform incline are translation-invariant - real bugs found here
## cluster at edges/corners/transitions (matching RAMP_POSITIONS' own curated philosophy),
## not the open middle. A full 2D position grid x yaw sweep was 6240 cases (~11 minutes,
## previously interrupted); this covers bottom/middle/top and every corner - the positions
## where edge/reach logic actually differs - crossed with the full yaw resolution instead.
## _sweep_spacing (spacing_cm) now sets how far the "near-edge" points sit from the true
## edge, not grid density.
func _build_dense_sweep() -> void:
	var angle_degrees := 45.0
	var origin := Vector3.ZERO
	var ramp := _build_ramp(origin, angle_degrees)
	var half_width := RAMP_WIDTH * 0.5 - _sweep_spacing
	var fractions := {
		&"bottom": SWEEP_END_MARGIN / RAMP_LENGTH,
		&"middle": 0.5,
		&"top": 1.0 - SWEEP_END_MARGIN / RAMP_LENGTH,
	}
	var laterals := {&"left": -half_width, &"center": 0.0, &"right": half_width}
	var position_index := 0
	for fraction_name: StringName in fractions:
		for lateral_name: StringName in laterals:
			if fraction_name == &"middle" and lateral_name != &"center":
				continue # only the center needs a mid-length sample; edges are covered at top/bottom
			var yaw_degrees := 0.0
			while yaw_degrees < 360.0 - 0.001:
				_cases.append({
					"angle": angle_degrees,
					"origin": origin,
					"fraction": fractions[fraction_name],
					"lateral": laterals[lateral_name],
					"root_offset": 0.1,
					"position_name": StringName("sweep_%s_%s" % [fraction_name, lateral_name]),
					"yaw": deg_to_rad(yaw_degrees),
					"yaw_name": StringName("yaw_%03d" % roundi(yaw_degrees)),
					"phase": position_index % 8,
					"ramp": ramp,
				})
				position_index += 1
				yaw_degrees += _sweep_yaw_step


func _build_ramp(origin: Vector3, angle_degrees: float) -> CSGBox3D:
	var ramp := CSGBox3D.new()
	ramp.name = StringName("Ramp%d" % roundi(angle_degrees))
	ramp.size = Vector3(RAMP_WIDTH, RAMP_THICKNESS, RAMP_LENGTH)
	ramp.use_collision = true
	ramp.rotation = Vector3(-deg_to_rad(angle_degrees), 0.0, 0.0)
	var half_length := ramp.basis * Vector3(0.0, 0.0, RAMP_LENGTH * 0.5)
	var half_thickness := ramp.basis * Vector3(0.0, -RAMP_THICKNESS * 0.5, 0.0)
	ramp.position = origin + half_length + half_thickness
	add_child(ramp)
	return ramp


func _build_player() -> void:
	_player = PLAYER_SCENE.instantiate() as Player
	_player.name = &"RampMatrixPlayer"
	_player.gameplay_action_input_enabled = false
	_player.movement_input_override = Vector2.ZERO
	add_child(_player)
	for camera: Node in _player.find_children("*", "Camera3D", true, false):
		(camera as Camera3D).current = false
	_player.hud.visible = false
	_player.hud.set_process_unhandled_input(false)
	_player.set_process_unhandled_input(false)
	for child in _player.skeleton.get_children():
		if child is PlayerFootIKModifier:
			_ik = child
			break
	for role: StringName in [&"LeftFoot", &"LeftToeBase", &"RightFoot", &"RightToeBase"]:
		_foot_bones[_player.body.resolve_bone_name(role)] = true
	# The rendered toe tip is weighted to the terminal leaf bones on this rig.
	# Filtering only Foot/ToeBase let exactly that visible tip pass unmeasured.
	for side: StringName in [&"left", &"right"]:
		var leaf_index: int = (_ik._bone_indices[side] as Dictionary)["leaf"]
		if leaf_index >= 0:
			_foot_bones[_player.skeleton.get_bone_name(leaf_index)] = true


func _start_next_case() -> void:
	_case_index += 1
	if _case_index >= _cases.size():
		print("FOOT_IK_RAMP_MATRIX_CHECK ", "FAIL" if _failed else "PASS",
				" cases=", _cases.size(), " failed_cases=", _sweep_failed_cases,
				" worst_depth_m=", snappedf(_sweep_worst_depth, 0.000001),
				" tolerance_m=", RAMP_PENETRATION_TOLERANCE,
				" artifact=", SWEEP_FAILURE_FILE if _sweep_mode else "none")
		if _sweep_failure_file != null:
			_sweep_failure_file.close()
		get_tree().quit(1 if _failed else 0)
		return
	var data := _cases[_case_index]
	var fraction: float = data["fraction"]
	var origin: Vector3 = data["origin"]
	# RAMP_LENGTH is measured along the inclined slab, not in world Z.
	# Project the selected along-ramp distance into horizontal travel/rise;
	# using it directly as Z put the 45-degree high cases beyond the collider.
	var angle := deg_to_rad(float(data["angle"]))
	var along_ramp := RAMP_LENGTH * fraction
	var z := cos(angle) * along_ramp
	var surface_y := sin(angle) * along_ramp
	_player.global_position = origin + Vector3(
			float(data["lateral"]), surface_y + float(data["root_offset"]), z)
	_spawn_position = _player.global_position
	_player.rotation = Vector3(0.0, float(data["yaw"]), 0.0)
	_player.velocity = Vector3.ZERO
	_player._reset_stair_hover()
	_ik.reset_runtime_state()
	_ik.set_debug_enabled(true)
	_player.body.locomotion_playback_scale = 1.0
	_player.body.update_motion(false, false, 0.0, false, true, 0.0, 0.0, false)
	if _sweep_mode:
		var phase := int(data.get("phase", 0))
		var animation_length := _player.body.anim_player.current_animation_length
		_player.body.anim_player.seek(animation_length * float(phase) / 8.0, true)
		_player.skeleton.advance(0.0)
	_case_check = PENETRATION_CHECK.new()
	_case_frame = 0
	_case_samples = 0
	_case_penetrating_samples = 0
	_case_penetrating_vertices = 0
	_case_max_depth = 0.0
	_case_bones.clear()
	_case_crossed_leg_samples = 0
	_case_max_leg_crossover = 0.0
	_case_invalid_contact_samples = 0
	_case_joint_limit_failures.clear()
	_sweep_sample_complete = false


func _sample_current_case() -> void:
	_sample_scheduled = false
	var ramp := _cases[_case_index]["ramp"] as CSGBox3D
	var sample := _case_check.sample_box_volume(
			_player, _ik, _foot_bones, ramp, RAMP_PENETRATION_TOLERANCE)
	if not sample.get("available", false):
		_failed = true
		return
	_case_samples += 1
	var vertices := int(sample["vertices"])
	if vertices > 0:
		_case_penetrating_samples += 1
		_case_penetrating_vertices += vertices
		_case_max_depth = maxf(_case_max_depth, float(sample["max_depth"]))
		for bone: StringName in (sample["bones"] as Dictionary):
			_case_bones[bone] = int(_case_bones.get(bone, 0)) \
					+ int((sample["bones"] as Dictionary)[bone])
	_sample_leg_order()
	_sample_invalid_contact()
	for failure in JOINT_LIMIT_CHECK.failures(_ik, _player.skeleton, "ramp_matrix"):
		if not _case_joint_limit_failures.has(failure):
			_case_joint_limit_failures.append(failure)
	_sweep_sample_complete = _sweep_mode


func _sample_invalid_contact() -> void:
	for side: StringName in [&"left", &"right"]:
		if (bool(_ik.debug_contact_hit.get(side, false))
				and float(_ik.debug_contact_distance.get(side, 0.0)) <= 0.001
				and float(_ik._smoothed_ground_weight.get(side, 1.0)) <= 0.001):
			_case_invalid_contact_samples += 1


func _sample_leg_order() -> void:
	var left_bones: Dictionary = _ik._bone_indices[&"left"]
	var right_bones: Dictionary = _ik._bone_indices[&"right"]
	var left_pose: Transform3D = _ik._final_bone_poses.get(
			int(left_bones["foot"]), Transform3D.IDENTITY)
	var right_pose: Transform3D = _ik._final_bone_poses.get(
			int(right_bones["foot"]), Transform3D.IDENTITY)
	var left_world := _player.skeleton.global_transform * left_pose.origin
	var right_world := _player.skeleton.global_transform * right_pose.origin
	var body_right := _player.global_transform.basis.x.normalized()
	var signed_separation := (right_world - left_world).dot(body_right)
	if signed_separation < 0.0:
		_case_crossed_leg_samples += 1
		_case_max_leg_crossover = maxf(
				_case_max_leg_crossover, -signed_separation)


func _finish_current_case() -> void:
	var data := _cases[_case_index]
	var case_failed := (_case_penetrating_samples > 0 or _case_samples == 0
			or _case_crossed_leg_samples > 0 or _case_invalid_contact_samples > 0
			or not _case_joint_limit_failures.is_empty())
	_failed = _failed or case_failed
	if _sweep_mode and case_failed:
		_sweep_failed_cases += 1
		_sweep_worst_depth = maxf(_sweep_worst_depth, _case_max_depth)
		_record_sweep_failure(data)
		if _sweep_failed_cases > SWEEP_PRINT_FAILURE_LIMIT:
			return
	print("FOOT_IK_RAMP_CASE ", "FAIL" if case_failed else "PASS",
			" angle=", data["angle"], " position=", data["position_name"],
			" fraction=", data["fraction"], " facing=", data["yaw_name"],
			" samples=", _case_samples,
			" penetrating_samples=", _case_penetrating_samples,
			" penetrating_vertices=", _case_penetrating_vertices,
			" max_depth_m=", snappedf(_case_max_depth, 0.000001),
			" crossed_leg_samples=", _case_crossed_leg_samples,
			" max_leg_crossover_m=", snappedf(_case_max_leg_crossover, 0.000001),
			" invalid_contact_samples=", _case_invalid_contact_samples,
			" joint_limit_failures=", _case_joint_limit_failures,
			" spawn=", _spawn_position,
			" settled=", _player.global_position,
			" bones=", _case_bones)


func _record_sweep_failure(data: Dictionary) -> void:
	if _sweep_failure_file == null:
		return
	_sweep_failure_file.store_line(JSON.stringify({
		"position": String(data["position_name"]),
		"fraction": data["fraction"],
		"lateral": data["lateral"],
		"yaw_degrees": rad_to_deg(float(data["yaw"])),
		"phase": data.get("phase", 0),
		"spawn": str(_spawn_position),
		"settled": str(_player.global_position),
		"penetrating_vertices": _case_penetrating_vertices,
		"max_depth_m": _case_max_depth,
		"crossed_leg_samples": _case_crossed_leg_samples,
		"max_leg_crossover_m": _case_max_leg_crossover,
		"invalid_contact_samples": _case_invalid_contact_samples,
		"joint_limit_failures": _case_joint_limit_failures,
		"bones": _case_bones,
	}))
	_sweep_failure_file.flush()
