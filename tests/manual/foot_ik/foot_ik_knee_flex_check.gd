class_name FootIkKneeFlexCheck
extends Node3D
## Recreates live over-height split idles where one raised leg deforms. A
## 0.60m split exceeds Player.step_height, so safe-zone recovery must finish
## with both soles on one exposed support and both legs inside standing limits.

const JOINT_LIMIT_CHECK := preload("res://tests/manual/foot_ik/foot_ik_joint_limit_check.gd")

const START := Vector3(9.253448, 0.600954, 4.017386)
const YAW_DEGREES := -21.9108694894493
const UPPER_Y := 0.6
const LOWER_Y := 0.0
const TARGET_TOLERANCE := 0.05
const SETTLE_STREAK_REQUIRED := 20
const FRAME_LIMIT := 360
const MAX_KNEE_FLEXION_DEGREES := 120.0
const SOLE_CLEARANCE_LIMIT := 0.08
const MAX_JOINT_STEP := 0.25

var _player: Player
var _ik: PlayerFootIKModifier
var _frame := 0
var _settle_streak := 0
var _start := START
var _yaw_degrees := YAW_DEGREES
var _animation_time := -1.0
var _turn_from_degrees := INF
var _turn_frames := 60
var _initial_velocity := Vector3.ZERO
var _require_prelanding_move := false
var _prelanding_move_seen := false
var _first_prelanding_target := Vector3(INF, INF, INF)
var _replay_prelanding_jump := false
var _replay_late_landing_input := false
var _replay_landing_clearance_jump := false
var _replay_edge_push := false
var _replay_unreachable_acquisition := false
var _unreachable_acquisition_cleared := false
var _replay_negative_knee := false
var _negative_knee_clamped := false
var _replay_idle_loop := false
var _replay_weight_oscillation := false
var _replay_delayed_lower_snap := false
var _upper_y := UPPER_Y
var _lower_y := LOWER_Y
var _minimum_planted_weight := 1.0
var _lower_stable_root_y := INF
var _max_post_latch_root_rise := 0.0
var _post_latch_upper_target_seen := false
var _require_lowest_support := false
var _airborne_seen := false
var _landing_root := Vector3(INF, INF, INF)
var _landing_frame := -1
var _post_landing_split_seen := false
var _max_shin_swing := 0.0
var _max_shin_swing_frame := -1
var _previous_joints: Dictionary = {}
var _max_joint_step := 0.0
var _max_joint_step_frame := 0
var _max_joint_step_key := ""
var _previous_root := Vector3.ZERO
var _max_root_step := 0.0
var _previous_target_y: Dictionary = {}
var _descent_min_y: Dictionary = {}
var _max_target_reversal := 0.0
var _minimum_signed_knee_flexion := 0.0
var _minimum_signed_knee_frame := -1
var _minimum_signed_knee_side := ""
var _previous_signed_knee: Dictionary = {}
var _max_signed_knee_step := 0.0
var _max_signed_knee_step_frame := -1
var _max_signed_knee_step_side := ""


func _ready() -> void:
	_parse_arguments()
	_build_surfaces()
	var player_scene: PackedScene = load("res://actors/player/player.tscn")
	_player = player_scene.instantiate() as Player
	add_child(_player)
	for child in _player.skeleton.get_children():
		if child is PlayerFootIKModifier:
			_ik = child
			break
	_player.global_position = _start
	_player.rotation.y = deg_to_rad(
			_turn_from_degrees if is_finite(_turn_from_degrees) else _yaw_degrees)
	_player._look_yaw = 0.0
	_player.head.rotation.y = 0.0
	_player.third_person_arm.rotation.y = 0.0
	_player.velocity = _initial_velocity
	_player.movement_input_override = Vector2.ZERO
	_player.ledge_safety_enabled = true
	_ik.reset_runtime_state()
	if _animation_time >= 0.0:
		_player.body.anim_player.seek(_animation_time, true)


func _parse_arguments() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("start="):
			var values := argument.trim_prefix("start=").split(",")
			if values.size() == 3:
				_start = Vector3(float(values[0]), float(values[1]), float(values[2]))
		elif argument.begins_with("yaw="):
			_yaw_degrees = float(argument.trim_prefix("yaw="))
		elif argument.begins_with("time="):
			_animation_time = float(argument.trim_prefix("time="))
		elif argument.begins_with("turn_from="):
			_turn_from_degrees = float(argument.trim_prefix("turn_from="))
		elif argument.begins_with("velocity="):
			var values := argument.trim_prefix("velocity=").split(",")
			if values.size() == 3:
				_initial_velocity = Vector3(float(values[0]), float(values[1]), float(values[2]))
		elif argument == "require_prelanding_move=true":
			_require_prelanding_move = true
		elif argument == "replay_prelanding_jump=true":
			_replay_prelanding_jump = true
		elif argument == "replay_late_landing_input=true":
			_replay_late_landing_input = true
		elif argument == "replay_landing_clearance_jump=true":
			_replay_landing_clearance_jump = true
		elif argument == "replay_edge_push=true":
			_replay_edge_push = true
		elif argument == "replay_unreachable_acquisition=true":
			_replay_unreachable_acquisition = true
		elif argument == "replay_negative_knee=true":
			_replay_negative_knee = true
		elif argument == "replay_idle_loop=true":
			_replay_idle_loop = true
		elif argument == "replay_weight_oscillation=true":
			_replay_weight_oscillation = true
			_start = Vector3(13.66617, 1.17263, 1.2658)
			_yaw_degrees = -166.981404903724
			_upper_y = 1.05
			_lower_y = 0.40
		elif argument == "replay_delayed_lower_snap=true":
			_replay_delayed_lower_snap = true
			_start = Vector3(8.340155, 0.560004, 3.917477)
			_yaw_degrees = 3.80492464367709
		elif argument == "require_lowest_support=true":
			_require_lowest_support = true


func _physics_process(_delta: float) -> void:
	_frame += 1
	if _replay_unreachable_acquisition and _frame == 10:
		var side := &"right"
		var target := _player.global_position + Vector3(0.2, -2.1, 0.0)
		_ik._ground_sampler.idle_lower_acquiring[side] = target
		_ik._ground_sampler._update_idle_lower_transition(
				side, target, Vector3.UP, 1.0 / 60.0, _player)
		_unreachable_acquisition_cleared = not _ik._ground_sampler.idle_lower_acquiring.has(side)
	if _replay_negative_knee and _frame == 10:
		_negative_knee_clamped = _inject_negative_knee_pose()
	if _replay_landing_clearance_jump:
		if _frame == 20:
			Input.action_press(&"jump")
		elif _frame == 21:
			Input.action_release(&"jump")
		_player.movement_input_override = Vector2.ZERO
	elif _replay_late_landing_input:
		if _frame == 20:
			Input.action_press(&"jump")
		elif _frame == 21:
			Input.action_release(&"jump")
		var initial_approach := _frame >= 48 and _frame <= 58
		var late_adjustment := _frame >= 68 and _frame <= 76
		_player.movement_input_override = Vector2(0.35, 0.0) \
				if initial_approach or late_adjustment else Vector2.ZERO
	elif _replay_prelanding_jump:
		if _frame == 20:
			Input.action_press(&"jump")
		elif _frame == 21:
			Input.action_release(&"jump")
		_player.movement_input_override = Vector2(0.35, 0.0) \
				if _frame >= 48 and _frame <= 58 else Vector2.ZERO
	elif _replay_edge_push:
		_player.movement_input_override = Vector2(-1.0, 0.0) \
				if _frame >= 20 and _frame <= 23 else Vector2.ZERO
	_measure_joint_step()
	_measure_signed_knee_flexion()
	if _replay_weight_oscillation and _frame > 120:
		var frame_min_weight := minf(
				float(_ik._smoothed_ground_weight.get(&"left", 0.0)),
				float(_ik._smoothed_ground_weight.get(&"right", 0.0)))
		_minimum_planted_weight = minf(_minimum_planted_weight, frame_min_weight)
	_measure_target_reversal()
	var replaying_jump := (_replay_prelanding_jump or _replay_late_landing_input
			or _replay_landing_clearance_jump)
	if not _player.is_on_floor() and (not replaying_jump or _frame >= 20):
		_airborne_seen = true
	if (not _player.is_on_floor()
			and _ik._ground_sampler.airborne_safe_root_target.is_finite()):
		_prelanding_move_seen = true
		if not _first_prelanding_target.is_finite():
			_first_prelanding_target = _ik._ground_sampler.airborne_safe_root_target
	if _airborne_seen and _player.is_on_floor() and not _landing_root.is_finite():
		_landing_root = _player.global_position
		_landing_frame = _frame
	if _landing_root.is_finite() and _player.is_on_floor():
		var live_left: Vector3 = _ik._smoothed_target.get(
				&"left", Vector3(INF, INF, INF))
		var live_right: Vector3 = _ik._smoothed_target.get(
				&"right", Vector3(INF, INF, INF))
		if (live_left.is_finite() and live_right.is_finite()
				and absf(live_left.y - live_right.y) > _player.step_height):
			_post_landing_split_seen = true
	if is_finite(_turn_from_degrees) and _frame <= _turn_frames:
		var turn_weight := float(_frame) / float(_turn_frames)
		_player.rotation.y = lerp_angle(
				deg_to_rad(_turn_from_degrees), deg_to_rad(_yaw_degrees), turn_weight)
	if _animation_time >= 0.0:
		_player.body.anim_player.seek(_animation_time, true)
	var left_target: Vector3 = _ik._smoothed_target.get(&"left", Vector3.ZERO)
	var right_target: Vector3 = _ik._smoothed_target.get(&"right", Vector3.ZERO)
	var both_upper := (absf(left_target.y - _upper_y) <= TARGET_TOLERANCE
			and absf(right_target.y - _upper_y) <= TARGET_TOLERANCE)
	var both_lower := (absf(left_target.y - _lower_y) <= TARGET_TOLERANCE
			and absf(right_target.y - _lower_y) <= TARGET_TOLERANCE)
	if (_replay_delayed_lower_snap
			and _ik._ground_sampler.idle_lower_latched_target.size() == 2):
		if not is_finite(_lower_stable_root_y):
			_lower_stable_root_y = _player.global_position.y
		_max_post_latch_root_rise = maxf(
				_max_post_latch_root_rise, _player.global_position.y - _lower_stable_root_y)
		_post_latch_upper_target_seen = (_post_latch_upper_target_seen
				or left_target.y > _lower_y + 0.1 or right_target.y > _lower_y + 0.1)
	var safely_settled := (_player.is_on_floor() and (both_upper or both_lower)
			and float(_ik._smoothed_ground_weight.get(&"left", 0.0)) >= 0.99
			and float(_ik._smoothed_ground_weight.get(&"right", 0.0)) >= 0.99
			and _compressed_targets_settled())
	_settle_streak = _settle_streak + 1 if safely_settled else 0
	if ((_settle_streak >= SETTLE_STREAK_REQUIRED
			and not (_replay_idle_loop or _replay_weight_oscillation
					or _replay_delayed_lower_snap))
			or ((_replay_idle_loop or _replay_weight_oscillation
					or _replay_delayed_lower_snap) and _frame >= 330)
			or _frame >= FRAME_LIMIT):
		_finish_check()


func _finish_check() -> void:
	var failures: Array[String] = []
	failures.append_array(JOINT_LIMIT_CHECK.failures(_ik, _player.skeleton, "knee_flex"))
	if _settle_streak < SETTLE_STREAK_REQUIRED:
		failures.append("never moved both feet onto one safe support level")
	if _require_prelanding_move and not _prelanding_move_seen:
		failures.append("safe-zone correction did not begin before landing")
	if (_require_prelanding_move and _landing_root.is_finite()
			and Vector2(_player.global_position.x - _landing_root.x,
					_player.global_position.z - _landing_root.z).length() > 0.08):
		failures.append("safe-zone correction continued after landing")
	if _replay_late_landing_input and _post_landing_split_seen:
		failures.append("landing exposed an over-height split stance after contact")
	if _replay_landing_clearance_jump and _post_landing_split_seen:
		failures.append("edge-clearance landing exposed a split stance after contact")
	if _replay_unreachable_acquisition and not _unreachable_acquisition_cleared:
		failures.append("unreachable lower-support acquisition retained ownership")
	if _replay_negative_knee and not _negative_knee_clamped:
		failures.append("final-pose limiter retained an injected negative knee bend")
	if _replay_weight_oscillation and _minimum_planted_weight < 0.99:
		failures.append("settled planted weight oscillated down to %.2f" % _minimum_planted_weight)
	if _replay_delayed_lower_snap and not is_finite(_lower_stable_root_y):
		failures.append("never established common lower support")
	if _replay_delayed_lower_snap and _post_latch_upper_target_seen:
		failures.append("idle probe replaced established common lower support")
	if _replay_delayed_lower_snap and _max_post_latch_root_rise > 0.02:
		failures.append("root rose %.3fm after lower support latched" % _max_post_latch_root_rise)
	if _minimum_signed_knee_flexion < -0.5:
		failures.append("%s knee bent backward %.2f degrees at frame %d" % [
				_minimum_signed_knee_side, _minimum_signed_knee_flexion,
				_minimum_signed_knee_frame])
	if _replay_idle_loop and _max_signed_knee_step > 3.5:
		failures.append("%s knee changed %.2f degrees in one idle frame at frame %d" % [
				_max_signed_knee_step_side, _max_signed_knee_step,
				_max_signed_knee_step_frame])
	var left_flexion := _rendered_knee_flexion(&"left")
	var right_flexion := _rendered_knee_flexion(&"right")
	var left_knee_above_ankle := (_final_joint_world(&"left", &"knee").y
			- _final_joint_world(&"left", &"foot").y)
	var right_knee_above_ankle := (_final_joint_world(&"right", &"knee").y
			- _final_joint_world(&"right", &"foot").y)
	var left_target: Vector3 = _ik._smoothed_target.get(&"left", Vector3.ZERO)
	var right_target: Vector3 = _ik._smoothed_target.get(&"right", Vector3.ZERO)
	var safe_y := (_upper_y if (left_target.y + right_target.y) * 0.5
			> (_upper_y + _lower_y) * 0.5 else _lower_y)
	var left_clearance := _rendered_sole_y(&"left") - safe_y
	var right_clearance := _rendered_sole_y(&"right") - safe_y
	for side: StringName in [&"left", &"right"]:
		var flexion := left_flexion if side == &"left" else right_flexion
		var knee_above := left_knee_above_ankle if side == &"left" else right_knee_above_ankle
		if flexion > MAX_KNEE_FLEXION_DEGREES + 0.5:
			failures.append("%s knee bent %.2f degrees (limit %.2f)" % [
					side, flexion, MAX_KNEE_FLEXION_DEGREES])
		if knee_above < -0.01:
			failures.append("%s knee folded %.3fm below its ankle" % [side, -knee_above])
		if (_require_lowest_support and not _ik._ground_sampler.has_support_patch(
				_player.get_world_3d().direct_space_state,
				_ik._smoothed_target.get(side, Vector3.ZERO),
				_ik._ground_sampler.COMPRESSED_UPPER_SUPPORT_RADIUS)):
			failures.append("%s target has no complete upper support patch" % side)
	if absf(left_clearance) > SOLE_CLEARANCE_LIMIT:
		failures.append("left sole clearance %.3fm (limit %.3fm)" % [
				left_clearance, SOLE_CLEARANCE_LIMIT])
	if absf(right_clearance) > SOLE_CLEARANCE_LIMIT:
		failures.append("right sole clearance %.3fm (limit %.3fm)" % [
				right_clearance, SOLE_CLEARANCE_LIMIT])
	if not _require_prelanding_move and _max_joint_step > MAX_JOINT_STEP:
		failures.append("one-frame joint movement %.3fm (limit %.3fm)" % [
				_max_joint_step, MAX_JOINT_STEP])
	if _max_shin_swing > _ik._leg_solver.MAX_UPRIGHT_SHIN_SWING_DEGREES + 1.0:
		failures.append("standing shin reached %.2f degrees at frame %d (limit %.2f)" % [
				_max_shin_swing, _max_shin_swing_frame,
				_ik._leg_solver.MAX_UPRIGHT_SHIN_SWING_DEGREES])
	if _replay_edge_push and _max_target_reversal > 0.2:
		failures.append("a foot target lowered then rose %.3fm during one recovery" %
				_max_target_reversal)
	if _replay_landing_clearance_jump and _max_target_reversal > 0.2:
		failures.append("landing target lowered then rose %.3fm after contact" %
				_max_target_reversal)
	var details := ("left_flex=%.2f right_flex=%.2f clearances=%.3f/%.3f root=%s "
			+ "targets=%s swing=%s error=%s") % [
			left_flexion, right_flexion, left_clearance, right_clearance,
			str(_player.global_position), str(_ik._smoothed_target),
			str(_ik._leg_solver.debug_swing_degrees),
			str(_ik._leg_solver.debug_target_error)]
	details += " safe_y=%.1f knee_above_ankle=%.3f/%.3f max_joint_step=%.3f@%d:%s root_step=%.3f" % [
			safe_y, left_knee_above_ankle, right_knee_above_ankle,
			_max_joint_step, _max_joint_step_frame, _max_joint_step_key, _max_root_step]
	details += " compressed=%s" % str(_ik._ground_sampler.compressed_upper_target)
	details += " lower_latched=%s acquiring=%s" % [
			str(_ik._ground_sampler.idle_lower_latched_target),
			str(_ik._ground_sampler.idle_lower_acquiring)]
	details += " riser_y=%s" % str(_ik._ground_sampler.lower_riser_away_surface_y)
	details += " root_nudge=%s" % str(_ik._ground_sampler.preferred_root_nudge)
	details += " stance_limited=%s swing_clamped=%s" % [
			str(_ik._leg_solver.debug_stance_limited),
			str(_ik._leg_solver.debug_swing_clamped)]
	details += " prelanding=%s prelanding_target=%s landing_root=%s@%d" % [
			str(_prelanding_move_seen), str(_first_prelanding_target),
			str(_landing_root), _landing_frame]
	details += " post_landing_split=%s" % str(_post_landing_split_seen)
	details += " max_shin=%.2f@%d" % [_max_shin_swing, _max_shin_swing_frame]
	details += " target_reversal=%.3f" % _max_target_reversal
	details += " min_signed_knee=%.2f@%d:%s" % [
			_minimum_signed_knee_flexion, _minimum_signed_knee_frame,
			_minimum_signed_knee_side]
	details += " max_signed_knee_step=%.2f@%d:%s" % [
			_max_signed_knee_step, _max_signed_knee_step_frame,
			_max_signed_knee_step_side]
	details += " min_planted_weight=%.2f" % _minimum_planted_weight
	details += " post_latch_root_rise=%.3f upper_reopened=%s" % [
			_max_post_latch_root_rise, str(_post_latch_upper_target_seen)]
	if not failures.is_empty():
		Input.action_release(&"jump")
		print("FOOT_IK_KNEE_FLEX_CHECK FAIL %s details=%s" % [
				"; ".join(failures), details])
		get_tree().quit(1)
		return
	Input.action_release(&"jump")
	print("FOOT_IK_KNEE_FLEX_CHECK PASS %s" % details)
	get_tree().quit(0)


func _rendered_knee_flexion(side: StringName) -> float:
	var hip := _final_joint_world(side, &"hip")
	var knee := _final_joint_world(side, &"knee")
	var foot := _final_joint_world(side, &"foot")
	var knee_to_hip := (hip - knee).normalized()
	var knee_to_foot := (foot - knee).normalized()
	return 180.0 - rad_to_deg(knee_to_hip.angle_to(knee_to_foot))


func _measure_signed_knee_flexion() -> void:
	if _ik == null or _ik._bone_indices.is_empty():
		return
	var animation_name := String(_player.body.anim_player.current_animation.get_file())
	if (not _player.is_on_floor()
			or not (animation_name.contains("idle") or animation_name.contains("walk"))):
		return
	for side: StringName in [&"left", &"right"]:
		var hip := _final_joint_world(side, &"hip")
		var knee := _final_joint_world(side, &"knee")
		var foot := _final_joint_world(side, &"foot")
		var upper := knee - hip
		var lower := foot - knee
		var line := foot - hip
		if upper.length_squared() < 0.000001 or lower.length_squared() < 0.000001 \
				or line.length_squared() < 0.000001:
			continue
		var flexion := rad_to_deg(upper.angle_to(lower))
		var signed_flexion: float = _ik._leg_solver.debug_signed_knee_flexion.get(
				side, 0.0)
		if signed_flexion < _minimum_signed_knee_flexion:
			_minimum_signed_knee_flexion = signed_flexion
			_minimum_signed_knee_frame = _frame
			_minimum_signed_knee_side = String(side)
		if (_replay_idle_loop and _frame > 120
				and float(_ik._smoothed_ground_weight.get(side, 0.0)) >= 0.99
				and _previous_signed_knee.has(side)):
			var step := absf(flexion - float(_previous_signed_knee[side]))
			if step > _max_signed_knee_step:
				_max_signed_knee_step = step
				_max_signed_knee_step_frame = _frame
				_max_signed_knee_step_side = String(side)
		_previous_signed_knee[side] = flexion


func _inject_negative_knee_pose() -> bool:
	var side := &"right"
	var forward := _player.body.global_transform.basis.z.normalized()
	var hip := _player.global_position + Vector3.UP
	var foot := hip + Vector3.DOWN * 0.8
	var animated_knee := hip + Vector3.DOWN * 0.4 + forward * 0.1
	var negative_knee := hip + Vector3.DOWN * 0.4 - forward * 0.1
	var result: Dictionary = _ik._leg_solver._limit_negative_rendered_knee(
			side, hip, hip, animated_knee, foot, negative_knee, foot)
	if result.is_empty():
		return false
	return float(_ik._leg_solver.debug_signed_knee_flexion.get(side, -INF)) >= 0.0 \
			and bool(_ik._leg_solver.debug_negative_knee_clamped.get(side, false))


func _measure_joint_step() -> void:
	if _ik == null or _ik._bone_indices.is_empty():
		return
	for side: StringName in [&"left", &"right"]:
		for joint: StringName in [&"hip", &"knee", &"foot"]:
			var key := "%s:%s" % [side, joint]
			var position := _final_joint_world(side, joint)
			if (_frame > 5 and _previous_joints.has(key)
					and (not _replay_weight_oscillation or _frame > 120)):
				var movement: float = position.distance_to(_previous_joints[key])
				if movement > _max_joint_step:
					_max_joint_step = movement
					_max_joint_step_frame = _frame
					_max_joint_step_key = key
			_previous_joints[key] = position
		var knee := _final_joint_world(side, &"knee")
		var foot := _final_joint_world(side, &"foot")
		var shin_swing := rad_to_deg(Vector3.DOWN.angle_to((foot - knee).normalized()))
		var animation_name := String(_player.body.anim_player.current_animation.get_file())
		var normal: Vector3 = _ik._smoothed_normal.get(side, Vector3.UP)
		if (_frame > 15 and not animation_name.contains("crouch")
				and not animation_name.contains("jump") and _ik._landing_grace_time <= 0.0
				and normal.dot(Vector3.UP) >= 0.999
				and shin_swing > _max_shin_swing):
			_max_shin_swing = shin_swing
			_max_shin_swing_frame = _frame
	if _frame > 5:
		_max_root_step = maxf(_max_root_step, _player.global_position.distance_to(_previous_root))
	_previous_root = _player.global_position


func _measure_target_reversal() -> void:
	for side: StringName in [&"left", &"right"]:
		if not _ik._smoothed_target.has(side):
			continue
		var target_y: float = (_ik._smoothed_target[side] as Vector3).y
		if (_previous_target_y.has(side)
				and float(_previous_target_y[side]) >= _upper_y - TARGET_TOLERANCE
				and target_y < float(_previous_target_y[side]) - TARGET_TOLERANCE):
			_descent_min_y[side] = target_y
		if _descent_min_y.has(side):
			_descent_min_y[side] = minf(float(_descent_min_y[side]), target_y)
			_max_target_reversal = maxf(
					_max_target_reversal, target_y - float(_descent_min_y[side]))
		_previous_target_y[side] = target_y


func _compressed_targets_settled() -> bool:
	for side: StringName in _ik._ground_sampler.compressed_upper_target:
		var desired: Vector3 = _ik._ground_sampler.compressed_upper_target[side]
		var current: Vector3 = _ik._smoothed_target.get(side, desired)
		if current.distance_to(desired) > 0.04:
			return false
	return true


func _rendered_sole_y(side: StringName) -> float:
	var foot_idx: int = _ik._bone_indices[side][&"foot"]
	var pose: Transform3D = _ik._final_bone_poses.get(
			foot_idx, _player.skeleton.get_bone_global_pose(foot_idx))
	var to_world := _player.skeleton.global_transform
	var sole_down: Vector3 = (to_world.basis * pose.basis
			* (_ik._sole_down_local[side] as Vector3)).normalized()
	var sole_depth: float = _ik._sole_depth_below_foot.get(side, _ik.ankle_offset)
	return (to_world * pose.origin).y + sole_down.y * sole_depth


func _final_joint_world(side: StringName, joint: StringName) -> Vector3:
	var index: int = _ik._bone_indices[side][joint]
	var pose: Transform3D = _ik._final_bone_poses.get(
			index, _player.skeleton.get_bone_global_pose(index))
	return _player.skeleton.global_transform * pose.origin


func _build_surfaces() -> void:
	if _replay_weight_oscillation:
		_add_box(Vector3(14.67, _upper_y * 0.5, 1.25), Vector3(2.0, _upper_y, 3.0))
		_add_box(Vector3(12.67, _lower_y * 0.5, 1.25), Vector3(2.0, _lower_y, 3.0))
		return
	_add_box(Vector3(10.0, 0.3, 3.85), Vector3(3.0, 0.6, 0.5))
	_add_box(Vector3(10.0, -0.5, 3.85), Vector3(7.0, 1.0, 5.0))


func _add_box(position: Vector3, size: Vector3) -> void:
	var body := StaticBody3D.new()
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collision.shape = shape
	body.add_child(collision)
	body.position = position
	add_child(body)
