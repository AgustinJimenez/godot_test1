class_name FootIkEdgeLandingSweepCheck
extends Node3D
## Deterministic randomized coverage for straight-up landings whose platform
## edge passes anywhere between the character's two feet.

const STAIR_SURFACES := preload("res://tests/manual/foot_ik/foot_ik_stair_surfaces.gd")
const CASE_COUNT := 25
const STAIR_WIDTH := 3.0
const STAIR_TREAD_DEPTH := 0.6
const STAIR_COUNT := 6
const STAIR_HEIGHT := 0.2
const TOP_Y := STAIR_COUNT * STAIR_HEIGHT
const TOP_EDGE_Z := (STAIR_COUNT - 1) * STAIR_TREAD_DEPTH \
		+ STAIR_SURFACES.TRANSITION_LENGTH + STAIR_SURFACES.LANDING_LENGTH
const LAUNCH_FRAME := 20
const HARD_CASE_FRAMES := 360
const SETTLE_AFTER_LANDING_FRAMES := 150
const FINAL_SAMPLE_FRAMES := 60
const TARGET_SPLIT_LIMIT := 0.35
const CONFIRMED_TARGET_DRIFT_LIMIT := 0.08
const COMMON_SUPPORT_CONFIRM_FRAMES := 8
const ROOT_STEP_LIMIT := 0.05
const FINAL_WEIGHT_MIN := 0.90

var _player: Player
var _ik: PlayerFootIKModifier
var _cases: Array[Dictionary] = []
var _case_index := 0
var _case_frame := 0
var _launched := false
var _airborne := false
var _landing_position_applied := false
var _landing_frame := -1
var _previous_root_y := 0.0
var _max_settled_root_step := 0.0
var _max_target_split := 0.0
var _min_final_weight := 1.0
var _common_support_streak := 0
var _confirmed_surface_y := INF
var _max_confirmed_target_drift := 0.0
var _max_confirmed_root_step := 0.0
var _failures: Array[String] = []


func _ready() -> void:
	_build_floor_and_stairs()
	var player_scene: PackedScene = load("res://actors/player/player.tscn")
	_player = player_scene.instantiate() as Player
	add_child(_player)
	STAIR_SURFACES.configure_player(_player)
	for child in _player.skeleton.get_children():
		if child is PlayerFootIKModifier:
			_ik = child
			break
	_build_cases()
	_select_requested_case()
	_reset_case()


func _build_cases() -> void:
	# The first case is the exact root/yaw from the escaped live capture.
	_cases.append({
		"label": "live_exact", "x": -1.18878, "z": 3.787432,
		"yaw": deg_to_rad(102.352351807122), "edge_offset": 0.238,
	})
	var rng := RandomNumberGenerator.new()
	rng.seed = 0xED6E_1A7D
	for index in CASE_COUNT - 1:
		var band_ratio := (float(index) + 0.5) / float(CASE_COUNT - 1)
		var edge_offset := lerpf(-0.24, 0.24, band_ratio)
		edge_offset += rng.randf_range(-0.008, 0.008)
		var yaw_deg := rng.randf_range(70.0, 110.0) if index % 2 == 0 \
				else rng.randf_range(250.0, 290.0)
		var yaw := deg_to_rad(yaw_deg)
		var lateral := Basis(Vector3.UP, yaw).x
		var root_z := TOP_EDGE_Z - edge_offset / lateral.z
		_cases.append({
			"label": "random_%02d" % index,
			"x": rng.randf_range(-0.9, 0.9), "z": root_z,
			"yaw": yaw, "edge_offset": edge_offset,
		})


func _select_requested_case() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if not argument.begins_with("case="):
			continue
		var selected := argument.trim_prefix("case=").to_int()
		if selected >= 0 and selected < _cases.size():
			_cases = [_cases[selected]]
		return


func _physics_process(_delta: float) -> void:
	_case_frame += 1
	if _case_frame == LAUNCH_FRAME:
		if not _player.is_on_floor():
			_fail_case("not grounded before jump")
			_advance_case()
			return
		Input.action_press(&"jump")
	elif _case_frame == LAUNCH_FRAME + 1:
		Input.action_release(&"jump")
	if _player.velocity.y > 0.5:
		_launched = true
	if _launched and not _player.is_on_floor():
		_airborne = true
	if (_airborne and not _landing_position_applied
			and not _player.is_on_floor() and _player.velocity.y <= 0.0):
		var landing: Dictionary = _cases[_case_index]
		_player.global_position.x = float(landing["x"])
		_player.global_position.z = float(landing["z"])
		_player.velocity.x = 0.0
		_player.velocity.z = 0.0
		_landing_position_applied = true
	if _airborne and _player.is_on_floor() and _landing_frame < 0:
		_landing_frame = _case_frame
		_previous_root_y = _player.global_position.y
	if _landing_frame >= 0:
		_sample_landing()
		if _case_frame >= _landing_frame + SETTLE_AFTER_LANDING_FRAMES:
			_evaluate_case()
			_advance_case()
			return
	if _case_frame >= HARD_CASE_FRAMES:
		_fail_case("did not complete a jump and landing")
		_advance_case()


func _sample_landing() -> void:
	var settled_frame := _case_frame - _landing_frame
	var left: Vector3 = _ik._smoothed_target.get(&"left", Vector3.ZERO)
	var right: Vector3 = _ik._smoothed_target.get(&"right", Vector3.ZERO)
	var same_known_surface := (absf(left.y - right.y) <= 0.06
			and (absf(left.y) <= 0.06 or absf(left.y - TOP_Y) <= 0.06))
	if is_finite(_confirmed_surface_y):
		_max_confirmed_target_drift = maxf(_max_confirmed_target_drift,
				maxf(absf(left.y - _confirmed_surface_y),
				absf(right.y - _confirmed_surface_y)))
		_max_confirmed_root_step = maxf(_max_confirmed_root_step,
				absf(_player.global_position.y - _previous_root_y))
	elif same_known_surface:
		_common_support_streak += 1
		if _common_support_streak >= COMMON_SUPPORT_CONFIRM_FRAMES:
			_confirmed_surface_y = (left.y + right.y) * 0.5
	else:
		_common_support_streak = 0
	if settled_frame >= SETTLE_AFTER_LANDING_FRAMES - FINAL_SAMPLE_FRAMES:
		_max_settled_root_step = maxf(
				_max_settled_root_step, absf(_player.global_position.y - _previous_root_y))
		_max_target_split = maxf(_max_target_split, absf(left.y - right.y))
		_min_final_weight = minf(_min_final_weight,
				minf(float(_ik._smoothed_ground_weight.get(&"left", 0.0)),
				float(_ik._smoothed_ground_weight.get(&"right", 0.0))))
	_previous_root_y = _player.global_position.y


func _evaluate_case() -> void:
	var left: Vector3 = _ik._smoothed_target.get(&"left", Vector3.ZERO)
	var right: Vector3 = _ik._smoothed_target.get(&"right", Vector3.ZERO)
	if not _landing_position_applied:
		_fail_case("landing position was not applied")
	if _max_settled_root_step > ROOT_STEP_LIMIT:
		_fail_case("settled root step %.3fm" % _max_settled_root_step)
	if _max_target_split > TARGET_SPLIT_LIMIT:
		_fail_case("settled target split %.3fm" % _max_target_split)
	if _max_confirmed_target_drift > CONFIRMED_TARGET_DRIFT_LIMIT:
		_fail_case("post-confirm target drift %.3fm" % _max_confirmed_target_drift)
	if _max_confirmed_root_step > ROOT_STEP_LIMIT:
		_fail_case("post-confirm root step %.3fm" % _max_confirmed_root_step)
	if _min_final_weight < FINAL_WEIGHT_MIN:
		_fail_case("settled minimum foot weight %.2f" % _min_final_weight)
	var on_known_surface := (absf(left.y) <= 0.06 or absf(left.y - TOP_Y) <= 0.06)
	if not on_known_surface or absf(left.y - right.y) > 0.06:
		_fail_case("final targets %.3f/%.3f" % [left.y, right.y])


func _fail_case(reason: String) -> void:
	var data: Dictionary = _cases[_case_index]
	var left: Vector3 = _ik._smoothed_target.get(&"left", Vector3.ZERO)
	var right: Vector3 = _ik._smoothed_target.get(&"right", Vector3.ZERO)
	var sampler := _ik._ground_sampler
	_failures.append(("%s offset=%.3f yaw=%.1f start=(%.3f,%.3f) %s "
			+ "root=%s targets=%.3f/%.3f safe_y=%.3f safe_root=%s contact=%.3f/%.3f") % [
			data["label"], float(data["edge_offset"]), rad_to_deg(float(data["yaw"])),
			float(data["x"]), float(data["z"]), reason, str(_player.global_position),
			left.y, right.y, sampler.split_safe_surface_y, str(sampler.split_safe_root_target),
			float(_ik.debug_contact_distance.get(&"left", -1.0)),
			float(_ik.debug_contact_distance.get(&"right", -1.0))])


func _advance_case() -> void:
	Input.action_release(&"jump")
	_case_index += 1
	if _case_index >= _cases.size():
		_finish_check()
		return
	_reset_case()


func _reset_case() -> void:
	var data: Dictionary = _cases[_case_index]
	_case_frame = 0
	_launched = false
	_airborne = false
	_landing_position_applied = false
	_landing_frame = -1
	_max_settled_root_step = 0.0
	_max_target_split = 0.0
	_min_final_weight = 1.0
	_common_support_streak = 0
	_confirmed_surface_y = INF
	_max_confirmed_target_drift = 0.0
	_max_confirmed_root_step = 0.0
	_player.ledge_safety_enabled = true
	_player.movement_input_override = Vector2.ZERO
	_player.global_position = Vector3(float(data["x"]), TOP_Y + 0.001, 3.7)
	_player.rotation = Vector3(0.0, float(data["yaw"]), 0.0)
	_player._look_yaw = 0.0
	_player.head.rotation.y = 0.0
	_player.third_person_arm.rotation.y = 0.0
	_player.velocity = Vector3.ZERO
	_player._reset_stair_hover()
	_player.body.anim_player.play(&"moves/unarmed_idle", 0.0)
	_ik.reset_runtime_state()
	_previous_root_y = _player.global_position.y


func _finish_check() -> void:
	var result := "PASS" if _failures.is_empty() else "FAIL"
	print("FOOT_IK_EDGE_LANDING_SWEEP_CHECK %s cases=%d offset_range=-0.240..0.240 failures=%d%s" % [
			result, _cases.size(), _failures.size(),
			"" if _failures.is_empty() else " details=" + "; ".join(_failures)])
	get_tree().quit(0 if _failures.is_empty() else 1)


func _build_floor_and_stairs() -> void:
	var floor_body := StaticBody3D.new()
	var floor_collision := CollisionShape3D.new()
	var floor_shape := BoxShape3D.new()
	floor_shape.size = Vector3(12.0, 1.0, 12.0)
	floor_collision.shape = floor_shape
	floor_body.position = Vector3(0.0, -0.5, 3.0)
	floor_body.add_child(floor_collision)
	add_child(floor_body)
	for step in STAIR_COUNT:
		var rise := STAIR_HEIGHT * (step + 1)
		var box := CSGBox3D.new()
		box.size = Vector3(STAIR_WIDTH, rise, STAIR_TREAD_DEPTH)
		box.use_collision = true
		STAIR_SURFACES.configure_authored_stair(box)
		box.position = Vector3(0.0, rise * 0.5, (step + 0.5) * STAIR_TREAD_DEPTH)
		add_child(box)
	STAIR_SURFACES.build_traversal_ramp(
			self, Vector3.ZERO, STAIR_WIDTH, 0.3,
			STAIR_TREAD_DEPTH, STAIR_COUNT, STAIR_HEIGHT)
	STAIR_SURFACES.build_top_landing(
			self, Vector3.ZERO, STAIR_WIDTH, STAIR_TREAD_DEPTH, STAIR_COUNT, STAIR_HEIGHT)
