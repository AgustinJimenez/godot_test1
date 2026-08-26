class_name FootIkRampLocomotionCheck
extends Node3D
## Physical ramp regression: verifies travel, floor contact, stopped-body
## drift, and planted-foot clearance instead of only teleporting idle poses.

const PLAYER_SCENE := preload("res://actors/player/player.tscn")
const STAIR_SURFACES := preload("res://tests/manual/foot_ik/foot_ik_stair_surfaces.gd")
const RAMP_ANGLES: Array[float] = [15.0, 30.0, 45.0]
const RAMP_WIDTH := 3.0
const RAMP_LENGTH := 6.0
const RAMP_THICKNESS := 0.3
const RAMP_SPACING := 7.0
const SETTLE_FRAMES := 24
const MOVE_FRAMES := 36
const STOP_GRACE_FRAMES := 24
const HOLD_FRAMES := 60
const SPIN_STEPS := 180
const SPIN_FRAMES := SPIN_STEPS * 2 # rotate, then hold one physics tick before sampling
const MIN_TRAVEL := 0.75
const MAX_STOPPED_DRIFT := 0.05
const MAX_AIRBORNE_MOVE_FRAMES := 2
const MAX_PLANTED_FLOAT := 0.04
const MAX_PLANTED_PENETRATION := 0.03
const MAX_SPIN_UNPLANTED_SAMPLES := 2
const MAX_SPIN_FOOT_STEP := 0.04

var _player: Player
var _ik: PlayerFootIKModifier
var _cases: Array[Dictionary] = []
var _case_index := 0
var _frame := 0
var _move_start := Vector3.ZERO
var _move_end := Vector3.ZERO
var _hold_start := Vector3.ZERO
var _airborne_move_frames := 0
var _maximum_float := -INF
var _maximum_penetration := 0.0
var _move_maximum_float := -INF
var _hold_maximum_float := -INF
var _move_maximum_penetration := 0.0
var _hold_maximum_penetration := 0.0
var _spin_maximum_float := -INF
var _spin_maximum_penetration := 0.0
var _spin_unplanted_samples := 0
var _spin_foot_samples := 0
var _spin_previous_sole: Dictionary = {}
var _spin_maximum_foot_step := 0.0
var _worst_spin_step_detail := ""
var _first_unplanted_detail := ""
var _foot_samples := 0
var _worst_float_detail := ""
var _worst_penetration_detail := ""
var _failures: Array[String] = []
var _results: Array[String] = []


func _ready() -> void:
	_build_ramps_and_cases()
	_build_player()
	_start_case()


func _build_ramps_and_cases() -> void:
	for angle_index in RAMP_ANGLES.size():
		var angle := RAMP_ANGLES[angle_index]
		var origin := Vector3(angle_index * RAMP_SPACING, 0.0, 0.0)
		_build_ramp(origin, angle)
		_cases.append(_make_case("ramp_%02d_uphill" % roundi(angle), origin, angle, 0.15, PI))
		_cases.append(_make_case("ramp_%02d_downhill" % roundi(angle), origin, angle, 0.78, 0.0))


func _build_ramp(origin: Vector3, angle_degrees: float) -> void:
	var angle := deg_to_rad(angle_degrees)
	var rise := tan(angle) * RAMP_LENGTH
	var authored := CSGBox3D.new()
	authored.size = Vector3(RAMP_WIDTH, RAMP_THICKNESS, RAMP_LENGTH)
	authored.use_collision = true
	STAIR_SURFACES.configure_authored_stair(authored)
	authored.rotation = Vector3(-angle, 0.0, 0.0)
	var half_length := authored.basis * Vector3(0.0, 0.0, RAMP_LENGTH * 0.5)
	var half_thickness := authored.basis * Vector3(0.0, -RAMP_THICKNESS * 0.5, 0.0)
	authored.position = origin + half_length + half_thickness
	add_child(authored)
	STAIR_SURFACES.build_traversal_slope(self, origin, RAMP_WIDTH, RAMP_LENGTH, rise)


func _make_case(case_name: String, origin: Vector3, angle_degrees: float,
		fraction: float, yaw: float) -> Dictionary:
	var angle := deg_to_rad(angle_degrees)
	var along := RAMP_LENGTH * fraction
	return {
		"name": case_name,
		"spawn": origin + Vector3(0.0, sin(angle) * along + 0.08, cos(angle) * along),
		"yaw": yaw,
		"direction": Basis(Vector3.UP, yaw) * Vector3.FORWARD,
	}


func _build_player() -> void:
	_player = PLAYER_SCENE.instantiate() as Player
	_player.gameplay_action_input_enabled = false
	add_child(_player)
	STAIR_SURFACES.configure_player(_player)
	for camera: Node in _player.find_children("*", "Camera3D", true, false):
		(camera as Camera3D).current = false
	for child in _player.skeleton.get_children():
		if child is PlayerFootIKModifier:
			_ik = child
			break


func _start_case() -> void:
	var data: Dictionary = _cases[_case_index]
	_player.movement_input_override = Vector2.ZERO
	_player.global_position = data["spawn"]
	_player.rotation = Vector3(0.0, data["yaw"], 0.0)
	_player._look_yaw = 0.0
	_player.head.rotation.y = 0.0
	_player.third_person_arm.rotation.y = 0.0
	_player.velocity = Vector3.ZERO
	_ik.reset_runtime_state()
	_frame = 0
	_airborne_move_frames = 0
	_maximum_float = -INF
	_maximum_penetration = 0.0
	_move_maximum_float = -INF
	_hold_maximum_float = -INF
	_move_maximum_penetration = 0.0
	_hold_maximum_penetration = 0.0
	_spin_maximum_float = -INF
	_spin_maximum_penetration = 0.0
	_spin_unplanted_samples = 0
	_spin_foot_samples = 0
	_spin_previous_sole.clear()
	_spin_maximum_foot_step = 0.0
	_worst_spin_step_detail = ""
	_first_unplanted_detail = ""
	_foot_samples = 0
	_worst_float_detail = ""
	_worst_penetration_detail = ""


func _physics_process(_delta: float) -> void:
	_frame += 1
	if _frame == SETTLE_FRAMES:
		_move_start = _player.global_position
		_player.movement_input_override = Vector2(0.0, -1.0)
	if _frame > SETTLE_FRAMES and _frame <= SETTLE_FRAMES + MOVE_FRAMES:
		if not _player.is_on_floor():
			_airborne_move_frames += 1
		_sample_feet(&"move")
		return
	if _frame == SETTLE_FRAMES + MOVE_FRAMES + 1:
		_move_end = _player.global_position
		_player.movement_input_override = Vector2.ZERO
	if _frame == SETTLE_FRAMES + MOVE_FRAMES + STOP_GRACE_FRAMES:
		_hold_start = _player.global_position
	var spin_start := SETTLE_FRAMES + MOVE_FRAMES + STOP_GRACE_FRAMES + HOLD_FRAMES
	if (_frame > SETTLE_FRAMES + MOVE_FRAMES + STOP_GRACE_FRAMES
			and _frame <= spin_start):
		_sample_feet(&"hold")
	if _frame <= spin_start:
		return
	if _frame <= spin_start + SPIN_FRAMES:
		var data: Dictionary = _cases[_case_index]
		var spin_frame := _frame - spin_start
		if spin_frame % 2 == 1:
			var step := (spin_frame + 1) / 2
			_player.rotation.y = float(data["yaw"]) + TAU * float(step) / SPIN_STEPS
			_player._look_yaw = 0.0
		else:
			_sample_feet(&"spin")
		if _frame < spin_start + SPIN_FRAMES:
			return
	_finish_case()
	_case_index += 1
	if _case_index >= _cases.size():
		_finish_check()
	else:
		_start_case()


func _sample_feet(phase: StringName) -> void:
	var to_world := _player.skeleton.global_transform
	for side: StringName in [&"left", &"right"]:
		var weight := float(_ik._smoothed_ground_weight.get(side, 0.0))
		var contact_hit := bool(_ik.debug_contact_hit.get(side, false))
		if phase == &"spin":
			_spin_foot_samples += 1
			if weight < 0.99 or bool(_ik.debug_contact_lost.get(side, false)):
				_spin_unplanted_samples += 1
				if _first_unplanted_detail.is_empty():
					_first_unplanted_detail = ("frame=%d side=%s yaw=%.1f weight=%.3f " + \
							"contact_hit=%s contact_lost=%s target=%s raw=%s") % [
							_frame, side, rad_to_deg(_player.rotation.y), weight, str(contact_hit),
							str(_ik.debug_contact_lost.get(side, false)),
							str(_ik._smoothed_target.get(side, Vector3.ZERO)),
							str(_ik._ground_sampler.debug_raw_target.get(side, Vector3.ZERO))]
		if (not contact_hit or not _ik._smoothed_target.has(side)
				or (phase != &"spin" and weight < 0.99)):
			continue
		var foot_idx: int = _ik._bone_indices[side]["foot"]
		var foot_pose: Transform3D = _ik._final_bone_poses.get(
				foot_idx, _player.skeleton.get_bone_global_pose(foot_idx))
		var foot_world := to_world * foot_pose
		var sole_direction := (foot_world.basis * (_ik._sole_down_local[side] as Vector3)).normalized()
		var sole_depth: float = _ik._sole_depth_below_foot.get(side, 0.0)
		var sole_point := foot_world.origin + sole_direction * sole_depth
		if phase == &"spin":
			if _spin_previous_sole.has(side):
				var foot_step: float = sole_point.distance_to(_spin_previous_sole[side])
				if foot_step > _spin_maximum_foot_step:
					_spin_maximum_foot_step = foot_step
					_worst_spin_step_detail = "frame=%d side=%s yaw=%.1f step=%.3f" % [
							_frame, side, rad_to_deg(_player.rotation.y), foot_step]
			_spin_previous_sole[side] = sole_point
		var target: Vector3 = _ik._smoothed_target[side]
		var normal: Vector3 = _ik._smoothed_normal.get(side, Vector3.UP)
		var clearance := (sole_point - target).dot(normal)
		var hip_idx: int = _ik._bone_indices[side]["hip"]
		var hip_pose: Transform3D = _ik._final_bone_poses.get(
				hip_idx, _player.skeleton.get_bone_global_pose(hip_idx))
		var hip_world: Vector3 = to_world * hip_pose.origin
		var raw_target: Vector3 = _ik._ground_sampler.debug_raw_target.get(side, target)
		var solved_target: Vector3 = _ik._solved_target_smoothed.get(side, target)
		var effective_offset: float = _ik._ground_sampler.debug_effective_offset.get(side, 0.0)
		var sole_alignment := sole_direction.dot(-normal)
		var detail := ("frame=%d side=%s phase=%s anim=%s yaw=%.1f weight=%.3f contact_dist=%.3f " + \
				"contact_lost=%s body_speed=%.3f step_down=%s " + \
				"stance_limited=%s swing_clamped=%s swing_deg=%.1f solve_error=%.3f pelvis_shift=%s " + \
				"shared_drop=%.3f offset=%.3f sole_depth=%.3f sole_align=%.3f hip_target=%.3f " + \
				"hip_raw=%.3f reach=%.3f clearance=%.3f normal=%s surface=%s " + \
				"solve_target=%s solver_foot=%s raw=%s sole=%s") % [
				_frame, side, phase, _ik.player_body.anim_player.current_animation.get_file(),
				rad_to_deg(_player.rotation.y), weight,
				float(_ik.debug_contact_distance.get(side, -1.0)),
				str(_ik.debug_contact_lost.get(side, false)),
				Vector2(_player.velocity.x, _player.velocity.z).length(),
				str(_ik.debug_step_down.get(side, false)),
				str(_ik._leg_solver.debug_stance_limited.get(side, false)),
				str(_ik._leg_solver.debug_swing_clamped.get(side, false)),
				float(_ik._leg_solver.debug_swing_degrees.get(side, -1.0)),
				float(_ik._leg_solver.debug_target_error.get(side, -1.0)),
				str(_ik._pelvis_lateral_shift), _ik._smoothed_shared_drop,
				effective_offset, sole_depth, sole_alignment,
				hip_world.distance_to(target), hip_world.distance_to(raw_target),
				float(_ik._leg_lengths[side]["upper"]) + float(_ik._leg_lengths[side]["lower"]),
				clearance, normal, target, solved_target,
				_ik._leg_solver.debug_final_foot_position.get(side, Vector3.ZERO),
				raw_target, sole_point]
		if clearance > _maximum_float:
			_maximum_float = clearance
			_worst_float_detail = detail
		if -clearance > _maximum_penetration:
			_maximum_penetration = -clearance
			_worst_penetration_detail = detail
		if phase == &"move":
			_move_maximum_float = maxf(_move_maximum_float, clearance)
			_move_maximum_penetration = maxf(_move_maximum_penetration, -clearance)
		elif phase == &"spin":
			_spin_maximum_float = maxf(_spin_maximum_float, clearance)
			_spin_maximum_penetration = maxf(_spin_maximum_penetration, -clearance)
		else:
			_hold_maximum_float = maxf(_hold_maximum_float, clearance)
			_hold_maximum_penetration = maxf(_hold_maximum_penetration, -clearance)
		_foot_samples += 1


func _finish_case() -> void:
	var data: Dictionary = _cases[_case_index]
	var expected: Vector3 = data["direction"]
	expected.y = 0.0
	expected = expected.normalized()
	var travel := Vector3(_move_end.x - _move_start.x, 0.0,
			_move_end.z - _move_start.z).dot(expected)
	var drift := Vector2(_player.global_position.x - _hold_start.x,
			_player.global_position.z - _hold_start.z).length()
	var case_errors: Array[String] = []
	if travel < MIN_TRAVEL:
		case_errors.append("travel=%.3f<%.3f" % [travel, MIN_TRAVEL])
	if _airborne_move_frames > MAX_AIRBORNE_MOVE_FRAMES:
		case_errors.append("airborne_frames=%d>%d" % [
				_airborne_move_frames, MAX_AIRBORNE_MOVE_FRAMES])
	if drift > MAX_STOPPED_DRIFT:
		case_errors.append("stopped_drift=%.3f>%.3f" % [drift, MAX_STOPPED_DRIFT])
	if _foot_samples == 0:
		case_errors.append("no_planted_foot_samples")
	if _maximum_float > MAX_PLANTED_FLOAT:
		case_errors.append("foot_float=%.3f>%.3f" % [_maximum_float, MAX_PLANTED_FLOAT])
	if _maximum_penetration > MAX_PLANTED_PENETRATION:
		case_errors.append("foot_penetration=%.3f>%.3f" % [
				_maximum_penetration, MAX_PLANTED_PENETRATION])
	if _spin_unplanted_samples > MAX_SPIN_UNPLANTED_SAMPLES:
		case_errors.append("spin_unplanted=%d>%d" % [
				_spin_unplanted_samples, MAX_SPIN_UNPLANTED_SAMPLES])
	if _spin_foot_samples != SPIN_STEPS * 2:
		case_errors.append("spin_samples=%d!=%d" % [_spin_foot_samples, SPIN_STEPS * 2])
	if _spin_maximum_foot_step > MAX_SPIN_FOOT_STEP:
		case_errors.append("spin_foot_step=%.3f>%.3f" % [
				_spin_maximum_foot_step, MAX_SPIN_FOOT_STEP])
	var result := "%s travel=%.3f drift=%.3f floor_misses=%d foot_samples=%d " + \
			"spin_unplanted=%d spin_foot_step=%.3f max_float=%.3f move/hold/spin=(%.3f/%.3f/%.3f) " + \
			"max_penetration=%.3f move/hold/spin=(%.3f/%.3f/%.3f)"
	_results.append(result % [data["name"], travel, drift, _airborne_move_frames,
			_foot_samples, _spin_unplanted_samples, _spin_maximum_foot_step,
			_maximum_float, _move_maximum_float,
			_hold_maximum_float, _spin_maximum_float, _maximum_penetration,
			_move_maximum_penetration, _hold_maximum_penetration, _spin_maximum_penetration])
	if not case_errors.is_empty():
		_failures.append(("%s: %s; unplanted_at=(%s); spin_step_at=(%s); " + \
				"float_at=(%s); penetration_at=(%s)") % [
				data["name"], ", ".join(case_errors), _first_unplanted_detail,
				_worst_spin_step_detail, _worst_float_detail, _worst_penetration_detail])


func _finish_check() -> void:
	print("FOOT_IK_RAMP_LOCOMOTION_CASES %s" % "; ".join(_results))
	if not _failures.is_empty():
		print("FOOT_IK_RAMP_LOCOMOTION_CHECK FAIL failures=%d details=%s" % [
				_failures.size(), "; ".join(_failures)])
		get_tree().quit(1)
		return
	print("FOOT_IK_RAMP_LOCOMOTION_CHECK PASS cases=%d" % _cases.size())
	get_tree().quit(0)
