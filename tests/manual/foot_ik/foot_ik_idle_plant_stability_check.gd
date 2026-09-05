class_name FootIkIdlePlantStabilityCheck
extends Node3D
## Replays the live 0.35m stair-top pose where the left idle animation kept
## cancelling its plant latch and visibly swept the corrected foot every loop.

const JOINT_LIMIT_CHECK := preload("res://tests/manual/foot_ik/foot_ik_joint_limit_check.gd")

const LIVE_POSITION := Vector3(14.30828, 2.101, 3.989683)
const LIVE_YAW_DEG := 67.7457025658242
const WARMUP_FRAMES := 240
const SAMPLE_FRAMES := 120
const MAX_PLANTED_DRIFT := 0.01
const LIVE_TURN_POSITION := Vector3(11.57876, 0.968951, 2.218947)
const LIVE_TURN_YAWS_DEG: Array[float] = [
	-128.2985, -128.5277, -131.0487, -136.3199, -146.6332,
	-152.8211, -156.4880, -159.0091, -160.1550, -160.3842,
	-161.3009, -164.0511, -170.4682, -178.0313, 174.1765,
	169.1345, 164.5508, 162.7174, 162.2590, 162.0298,
]
const TURN_WARMUP_FRAMES := 180
const TURN_HOLD_FRAMES := 30
const MAX_TURN_FOOT_STEP := 0.12
const LIVE_REHOME_POSITION := Vector3(11.99987, 0.966643, 2.196849)
const LIVE_REHOME_YAW_DEG := 151.304891324494
const LIVE_REHOME_RIGHT_TARGET := Vector3(11.88078, 1.0, 2.55805)
const LIVE_REHOME_ANIMATION_TIME := 0.70
const REHOME_WARMUP_FRAMES := 120
const REHOME_SAMPLE_FRAMES := 90
const MAX_REHOME_FOOT_STEP := 0.045
const LIVE_KNEE_POSITION := Vector3(11.46174, 1.108369, 2.669042)
const LIVE_KNEE_YAW_DEG := 86.9044309990342
const LIVE_KNEE_LEFT_TARGET := Vector3(11.38333, 1.0, 2.905785)
const KNEE_GUARD_WARMUP_FRAMES := 120
const KNEE_GUARD_SAMPLE_FRAMES := 180
const MAX_GUARDED_KNEE_STEP := 0.02
const LIVE_POSE_POSITION := Vector3(14.39513, 2.093347, 2.998612)
const LIVE_POSE_YAW_DEG := 92.2223206641577
const LIVE_POSE_LEFT_TARGET := Vector3(14.57049, 2.1, 3.358953)
const LIVE_POSE_RIGHT_TARGET := Vector3(13.97629, 1.75, 2.808539)
const LIVE_POSE_WARMUP_FRAMES := 120
const LIVE_POSE_SETTLE_FRAMES := 60
const LIVE_POSE_SAMPLE_FRAMES := 360
const MAX_LIVE_POSE_TARGET_ERROR := 0.02
const MAX_LIVE_POSE_JOINT_STEP := 0.045
const RIGHT_STALE_POSITION := Vector3(11.85303, 0.857089, 1.865879)
const RIGHT_STALE_YAW_DEG := 162.029831944166
const RIGHT_STALE_TARGET := Vector3(12.23006, 0.8, 2.050356)
const RIGHT_STALE_WARMUP_FRAMES := 120
const RIGHT_STALE_SAMPLE_FRAMES := 120
const MAX_RIGHT_STALE_FOOT_STEP := 0.055
const LEFT_STALE_POSITION := Vector3(12.40712, 1.037015, 2.500223)
const LEFT_STALE_YAW_DEG := 11.9615386849404
const LEFT_STALE_TARGET := Vector3(12.70302, 1.0, 2.477624)
const COORDINATOR_POSITION := Vector3(12.13534, 0.777293, 1.701067)
const COORDINATOR_START_YAW_DEG := 57.3398342332289
const COORDINATOR_END_YAW_DEG := -33.1875066864984
const COORDINATOR_STALE_LEFT_TARGET := Vector3(12.30323, 0.8, 1.899687)
const COORDINATOR_WARMUP_FRAMES := 120
const COORDINATOR_SAMPLE_FRAMES := 240
const MAX_COORDINATOR_FOOT_STEP := 0.055
const MIN_COORDINATOR_SOLE_CLEARANCE := -0.015
const STRAIGHT_KNEE_POSITION := Vector3(9.254115, 0.595856, 4.193318)
const STRAIGHT_KNEE_YAW_DEG := 40.5153775903842
const STRAIGHT_KNEE_LEFT_TARGET := Vector3(8.87081, 0.0, 4.431192)
const STRAIGHT_KNEE_RIGHT_TARGET := Vector3(9.522064, 0.0, 4.333933)
const STRAIGHT_KNEE_WARMUP_FRAMES := 60
const STRAIGHT_KNEE_SAMPLE_FRAMES := 180
const MIN_SETTLED_KNEE_FLEXION_DEG := 8.0
const MAX_STRAIGHT_KNEE_FOOT_STEP := 0.035
const MAX_STRAIGHT_KNEE_LATE_CONSTRAINT_FRAMES := 20

var _player: Player
var _ik: PlayerFootIKModifier
var _frame := 0
var _sample_count := 0
var _frozen_samples := {&"left": 0, &"right": 0}
var _anchors: Dictionary = {}
var _max_drift := {&"left": 0.0, &"right": 0.0}
var _checking_turn := false
var _turn_frame := 0
var _turn_previous_feet: Dictionary = {}
var _turn_max_foot_step := 0.0
var _turn_max_foot_step_side := &""
var _turn_max_foot_step_frame := -1
var _stance_cache_aligned := false
var _timed_idle_handoff_smooth := false
var _checking_rehome := false
var _rehome_frame := 0
var _rehome_observed := false
var _rehome_previous_foot := Vector3.ZERO
var _rehome_max_foot_step := 0.0
var _rehome_stance_limit_frames := 0
var _checking_knee_guard := false
var _knee_guard_frame := 0
var _knee_guard_previous := Vector3.ZERO
var _knee_guard_max_step := 0.0
var _knee_guard_constrained_frames := 0
var _checking_live_pose := false
var _live_pose_frame := 0
var _live_pose_constrained_frames := 0
var _live_pose_max_target_error := 0.0
var _live_pose_max_shin_swing := 0.0
var _live_pose_joint_failure := ""
var _live_pose_previous_joints: Dictionary = {}
var _live_pose_max_joint_step := 0.0
var _live_pose_max_joint_step_at := ""
var _checking_right_stale := false
var _right_stale_frame := 0
var _right_stale_rehome_observed := false
var _right_stale_stance_limit_frames := 0
var _right_stale_previous_foot := Vector3.ZERO
var _right_stale_max_foot_step := 0.0
var _checking_left_stale := false
var _left_stale_frame := 0
var _left_stale_rehome_observed := false
var _left_stale_stance_limit_frames := 0
var _left_stale_previous_foot := Vector3.ZERO
var _left_stale_max_foot_step := 0.0
var _checking_coordinator := false
var _coordinator_frame := 0
var _coordinator_recovery_observed := false
var _coordinator_invalid_frames := 0
var _coordinator_stance_limit_frames := 0
var _coordinator_previous_foot := Vector3.ZERO
var _coordinator_max_foot_step := 0.0
var _coordinator_min_sole_clearance := INF
var _coordinator_generations: Dictionary = {}
var _checking_straight_knee := false
var _straight_knee_frame := 0
var _straight_knee_previous_foot := Vector3.ZERO
var _straight_knee_max_foot_step := 0.0
var _straight_knee_final_flexion := 0.0
var _straight_knee_final_target_error := INF
var _straight_knee_late_constraints := 0
var _straight_knee_plan_valid := true


func _ready() -> void:
	_player = $FootIkPreview/Player
	_player.global_position = LIVE_POSITION
	_player.rotation = Vector3(0.0, deg_to_rad(LIVE_YAW_DEG), 0.0)
	_player.velocity = Vector3.ZERO
	_player.movement_input_override = Vector2.ZERO
	for child: Node in _player.body.skeleton.get_children():
		if child is PlayerFootIKModifier:
			_ik = child
			break
	_ik.reset_runtime_state()


func _physics_process(_delta: float) -> void:
	if _checking_straight_knee:
		_process_straight_knee_check()
	elif _checking_coordinator:
		_process_coordinator_check()
	elif _checking_left_stale:
		_process_left_stale_check()
	elif _checking_right_stale:
		_process_right_stale_check()
	elif _checking_live_pose:
		_process_live_pose_check()
	elif _checking_knee_guard:
		_process_knee_guard_check()
	elif _checking_rehome:
		_process_rehome_check()
	elif _checking_turn:
		_process_turn_check()
	else:
		_process_initial_check()


func _process_initial_check() -> void:
	_frame += 1
	if _frame < WARMUP_FRAMES:
		return
	_sample_count += 1
	for side: StringName in [&"left", &"right"]:
		var foot_position := _final_foot_position(side)
		if not _anchors.has(side):
			_anchors[side] = foot_position
		_max_drift[side] = maxf(float(_max_drift[side]),
				foot_position.distance_to(_anchors[side] as Vector3))
		if bool(_ik._idle_frozen.get(side, false)):
			_frozen_samples[side] = int(_frozen_samples[side]) + 1
	if _sample_count >= SAMPLE_FRAMES:
		_begin_turn_check()


func _begin_turn_check() -> void:
	_stance_cache_aligned = _check_stance_limit_cache_alignment()
	_timed_idle_handoff_smooth = _check_timed_idle_support_handoff()
	_checking_turn = true
	_turn_frame = 0
	_player.global_position = LIVE_TURN_POSITION
	_player.rotation = Vector3(0.0, deg_to_rad(LIVE_TURN_YAWS_DEG[0]), 0.0)
	_player.velocity = Vector3.ZERO
	_player.movement_input_override = Vector2.ZERO
	_player.body.anim_player.play(&"moves/unarmed_idle", 0.0)
	_ik.reset_runtime_state()


func _process_turn_check() -> void:
	_turn_frame += 1
	if _turn_frame <= TURN_WARMUP_FRAMES:
		return
	var turn_index := _turn_frame - TURN_WARMUP_FRAMES - 1
	if turn_index < LIVE_TURN_YAWS_DEG.size():
		_player.rotation.y = deg_to_rad(LIVE_TURN_YAWS_DEG[turn_index])
	for side: StringName in [&"left", &"right"]:
		var foot_position := _final_foot_position(side)
		if _turn_previous_feet.has(side):
			var step := foot_position.distance_to(_turn_previous_feet[side] as Vector3)
			if step > _turn_max_foot_step:
				_turn_max_foot_step = step
				_turn_max_foot_step_side = side
				_turn_max_foot_step_frame = turn_index
		_turn_previous_feet[side] = foot_position
	if turn_index >= LIVE_TURN_YAWS_DEG.size() + TURN_HOLD_FRAMES:
		_begin_rehome_check()


func _begin_rehome_check() -> void:
	_checking_turn = false
	_checking_rehome = true
	_rehome_frame = 0
	_player.global_position = LIVE_REHOME_POSITION
	_player.rotation = Vector3(0.0, deg_to_rad(LIVE_REHOME_YAW_DEG), 0.0)
	_player.velocity = Vector3.ZERO
	_player.movement_input_override = Vector2.ZERO
	_player.body.anim_player.play(&"moves/unarmed_idle", 0.0)
	_ik.reset_runtime_state()


func _process_rehome_check() -> void:
	_rehome_frame += 1
	if _rehome_frame < REHOME_WARMUP_FRAMES:
		return
	if _rehome_frame == REHOME_WARMUP_FRAMES:
		_player.body.anim_player.seek(LIVE_REHOME_ANIMATION_TIME, true)
		_player.body.skeleton.advance(0.0)
		_ik._ground_sampler.smoothed_target[&"right"] = LIVE_REHOME_RIGHT_TARGET
		_ik._ground_sampler.smoothed_normal[&"right"] = Vector3.UP
		_ik._gait_tracker.invalidate_idle_freeze(&"right")
		_rehome_previous_foot = _final_foot_position(&"right")
		_rehome_observed = _ik._ground_sampler._rehome_idle_stance_target(
				get_world_3d().direct_space_state, &"right",
				_rehome_previous_foot, LIVE_REHOME_RIGHT_TARGET, Vector3.UP, 1.0 / 60.0)
		return
	var foot := _final_foot_position(&"right")
	_rehome_max_foot_step = maxf(_rehome_max_foot_step,
			foot.distance_to(_rehome_previous_foot))
	_rehome_previous_foot = foot
	_rehome_observed = (_rehome_observed
			or _ik._ground_sampler.idle_stance_rehoming.has(&"right"))
	if bool(_ik._leg_solver.debug_stance_limited.get(&"right", false)):
		_rehome_stance_limit_frames += 1
	if _rehome_frame >= REHOME_WARMUP_FRAMES + REHOME_SAMPLE_FRAMES:
		_begin_knee_guard_check()


func _begin_knee_guard_check() -> void:
	_checking_rehome = false
	_checking_knee_guard = true
	_knee_guard_frame = 0
	_player.global_position = LIVE_KNEE_POSITION
	_player.rotation = Vector3(0.0, deg_to_rad(LIVE_KNEE_YAW_DEG), 0.0)
	_player.velocity = Vector3.ZERO
	_player.movement_input_override = Vector2.ZERO
	_player.body.anim_player.play(&"moves/unarmed_idle", 0.0)
	_ik.reset_runtime_state()


func _process_knee_guard_check() -> void:
	_knee_guard_frame += 1
	if _knee_guard_frame < KNEE_GUARD_WARMUP_FRAMES:
		return
	if _knee_guard_frame == KNEE_GUARD_WARMUP_FRAMES:
		_player.body.anim_player.seek(0.0, true)
		_player.body.skeleton.advance(0.0)
		_ik._ground_sampler.smoothed_target[&"left"] = LIVE_KNEE_LEFT_TARGET
		_ik._ground_sampler.smoothed_normal[&"left"] = Vector3.UP
		_ik._ground_sampler.idle_lower_latched_target[&"left"] = LIVE_KNEE_LEFT_TARGET
		_ik._ground_sampler.lower_riser_cleared_target[&"left"] = LIVE_KNEE_LEFT_TARGET
		_knee_guard_previous = _final_joint_position(&"left", &"knee")
		return
	var knee := _final_joint_position(&"left", &"knee")
	_knee_guard_max_step = maxf(
			_knee_guard_max_step, knee.distance_to(_knee_guard_previous))
	_knee_guard_previous = knee
	if bool(_ik._leg_solver.debug_knee_direction_constrained.get(&"left", false)):
		_knee_guard_constrained_frames += 1
	if _knee_guard_frame >= KNEE_GUARD_WARMUP_FRAMES + KNEE_GUARD_SAMPLE_FRAMES:
		_begin_live_pose_check()


func _begin_live_pose_check() -> void:
	_checking_knee_guard = false
	_checking_live_pose = true
	_live_pose_frame = 0
	_player.global_position = LIVE_POSE_POSITION
	_player.rotation = Vector3(0.0, deg_to_rad(LIVE_POSE_YAW_DEG), 0.0)
	_player.velocity = Vector3.ZERO
	_player.movement_input_override = Vector2.ZERO
	_player.body.anim_player.play(&"moves/unarmed_idle", 0.0)
	_ik.reset_runtime_state()


func _process_live_pose_check() -> void:
	_live_pose_frame += 1
	if _live_pose_frame < LIVE_POSE_WARMUP_FRAMES:
		return
	if _live_pose_frame == LIVE_POSE_WARMUP_FRAMES:
		_player.body.anim_player.seek(0.0, true)
		_player.body.skeleton.advance(0.0)
		_ik._ground_sampler.smoothed_target[&"left"] = LIVE_POSE_LEFT_TARGET
		_ik._ground_sampler.smoothed_normal[&"left"] = Vector3.UP
		_ik._ground_sampler.smoothed_target[&"right"] = LIVE_POSE_RIGHT_TARGET
		_ik._ground_sampler.smoothed_normal[&"right"] = Vector3.UP
		_ik._ground_sampler.idle_lower_latched_target[&"right"] = LIVE_POSE_RIGHT_TARGET
		return
	if _live_pose_frame < LIVE_POSE_WARMUP_FRAMES + LIVE_POSE_SETTLE_FRAMES:
		return
	if _live_pose_frame == LIVE_POSE_WARMUP_FRAMES + LIVE_POSE_SETTLE_FRAMES:
		if bool(_ik._leg_solver.debug_knee_direction_constrained.get(&"left", false)):
			_live_pose_constrained_frames = 1
		_live_pose_max_target_error = float(
				_ik._leg_solver.debug_target_error.get(&"left", 0.0))
		var fixed_knee := _final_joint_position(&"left", &"knee")
		var fixed_foot := _final_joint_position(&"left", &"foot")
		_live_pose_max_shin_swing = rad_to_deg(
				Vector3.DOWN.angle_to((fixed_foot - fixed_knee).normalized()))
		return
	var sample_index := _live_pose_frame - LIVE_POSE_WARMUP_FRAMES - LIVE_POSE_SETTLE_FRAMES
	_player.rotation.y = deg_to_rad(LIVE_POSE_YAW_DEG) \
			+ TAU * float(sample_index) / float(LIVE_POSE_SAMPLE_FRAMES)
	for side: StringName in [&"left", &"right"]:
		for joint: StringName in [&"hip", &"knee", &"foot"]:
			var key := "%s:%s" % [side, joint]
			var position := _final_joint_position(side, joint)
			if _live_pose_previous_joints.has(key):
				var step := position.distance_to(_live_pose_previous_joints[key])
				if step > _live_pose_max_joint_step:
					_live_pose_max_joint_step = step
					_live_pose_max_joint_step_at = "%d:%s" % [sample_index, key]
			_live_pose_previous_joints[key] = position
	if _live_pose_joint_failure.is_empty():
		var failures: Array[String] = JOINT_LIMIT_CHECK.failures(
				_ik, _player.body.skeleton, "stair_rotation")
		if not failures.is_empty():
			_live_pose_joint_failure = failures[0]
	if (_live_pose_frame >= LIVE_POSE_WARMUP_FRAMES + LIVE_POSE_SETTLE_FRAMES
			+ LIVE_POSE_SAMPLE_FRAMES):
		_begin_right_stale_check()


func _begin_right_stale_check() -> void:
	_checking_live_pose = false
	_checking_right_stale = true
	_player.global_position = RIGHT_STALE_POSITION
	_player.rotation = Vector3(0.0, deg_to_rad(RIGHT_STALE_YAW_DEG), 0.0)
	_player.velocity = Vector3.ZERO
	_player.movement_input_override = Vector2.ZERO
	_player.body.anim_player.play(&"moves/unarmed_idle", 0.0)
	_ik.reset_runtime_state()


func _process_right_stale_check() -> void:
	_right_stale_frame += 1
	if _right_stale_frame < RIGHT_STALE_WARMUP_FRAMES:
		return
	if _right_stale_frame == RIGHT_STALE_WARMUP_FRAMES:
		_player.global_position = RIGHT_STALE_POSITION
		_ik._ground_sampler.smoothed_target[&"right"] = RIGHT_STALE_TARGET
		_ik._ground_sampler.smoothed_normal[&"right"] = Vector3.UP
		_ik._ground_sampler.idle_lower_latched_target.erase(&"right")
		_ik._ground_sampler.idle_lower_acquiring.erase(&"right")
		_ik._gait_tracker.invalidate_idle_freeze(&"right")
		_right_stale_previous_foot = _final_foot_position(&"right")
		return
	var foot := _final_foot_position(&"right")
	_right_stale_max_foot_step = maxf(
			_right_stale_max_foot_step, foot.distance_to(_right_stale_previous_foot))
	_right_stale_previous_foot = foot
	_right_stale_rehome_observed = (_right_stale_rehome_observed
			or _ik._ground_sampler.idle_stance_rehoming.has(&"right")
			or _ik._ground_sampler.idle_lower_acquiring.has(&"right"))
	if bool(_ik._leg_solver.debug_stance_limited.get(&"right", false)):
		_right_stale_stance_limit_frames += 1
	if _right_stale_frame >= RIGHT_STALE_WARMUP_FRAMES + RIGHT_STALE_SAMPLE_FRAMES:
		_begin_left_stale_check()


func _begin_left_stale_check() -> void:
	_checking_right_stale = false
	_checking_left_stale = true
	_player.global_position = LEFT_STALE_POSITION
	_player.rotation = Vector3(0.0, deg_to_rad(LEFT_STALE_YAW_DEG), 0.0)
	_player.velocity = Vector3.ZERO
	_player.movement_input_override = Vector2.ZERO
	_player.body.anim_player.play(&"moves/unarmed_idle", 0.0)
	_ik.reset_runtime_state()


func _process_left_stale_check() -> void:
	_left_stale_frame += 1
	if _left_stale_frame < RIGHT_STALE_WARMUP_FRAMES:
		return
	if _left_stale_frame == RIGHT_STALE_WARMUP_FRAMES:
		_player.global_position = LEFT_STALE_POSITION
		_ik._ground_sampler.smoothed_target[&"left"] = LEFT_STALE_TARGET
		_ik._ground_sampler.smoothed_normal[&"left"] = Vector3.UP
		_ik._ground_sampler.idle_lower_latched_target.erase(&"left")
		_ik._ground_sampler.idle_lower_acquiring.erase(&"left")
		_ik._gait_tracker.invalidate_idle_freeze(&"left")
		_left_stale_previous_foot = _final_foot_position(&"left")
		return
	var foot := _final_foot_position(&"left")
	_left_stale_max_foot_step = maxf(
			_left_stale_max_foot_step, foot.distance_to(_left_stale_previous_foot))
	_left_stale_previous_foot = foot
	_left_stale_rehome_observed = (_left_stale_rehome_observed
			or _ik._ground_sampler.idle_stance_rehoming.has(&"left")
			or _ik._ground_sampler.idle_lower_acquiring.has(&"left"))
	if bool(_ik._leg_solver.debug_stance_limited.get(&"left", false)):
		_left_stale_stance_limit_frames += 1
	if _left_stale_frame >= RIGHT_STALE_WARMUP_FRAMES + RIGHT_STALE_SAMPLE_FRAMES:
		_begin_coordinator_check()


func _begin_coordinator_check() -> void:
	_checking_left_stale = false
	_checking_coordinator = true
	_coordinator_frame = 0
	_player.global_position = COORDINATOR_POSITION
	_player.rotation = Vector3(0.0, deg_to_rad(COORDINATOR_START_YAW_DEG), 0.0)
	_player.velocity = Vector3.ZERO
	_player.movement_input_override = Vector2.ZERO
	_player.body.anim_player.play(&"moves/unarmed_idle", 0.0)
	_ik.reset_runtime_state()


func _process_coordinator_check() -> void:
	_coordinator_frame += 1
	if _coordinator_frame < COORDINATOR_WARMUP_FRAMES:
		return
	if _coordinator_frame == COORDINATOR_WARMUP_FRAMES:
		_ik._ground_sampler.smoothed_target[&"left"] = COORDINATOR_STALE_LEFT_TARGET
		_ik._ground_sampler.smoothed_normal[&"left"] = Vector3.UP
		_ik._ground_sampler.idle_lower_latched_target.erase(&"left")
		_ik._ground_sampler.idle_lower_acquiring.erase(&"left")
		_ik._gait_tracker.invalidate_idle_freeze(&"left")
		_coordinator_previous_foot = _final_foot_position(&"left")
		return
	var sample := _coordinator_frame - COORDINATOR_WARMUP_FRAMES - 1
	_player.rotation.y = lerpf(deg_to_rad(COORDINATOR_START_YAW_DEG),
			deg_to_rad(COORDINATOR_END_YAW_DEG),
			clampf(float(sample) / float(COORDINATOR_SAMPLE_FRAMES - 1), 0.0, 1.0))
	var plan: FootIKTargetPlan = _ik._target_coordinator.get_plan(&"left")
	if plan == null or not plan.valid:
		_coordinator_invalid_frames += 1
	else:
		_coordinator_generations[plan.generation] = true
		_coordinator_recovery_observed = (_coordinator_recovery_observed
				or plan.reason == "replace_invalid_with_raw_support")
	var foot := _final_foot_position(&"left")
	_coordinator_max_foot_step = maxf(_coordinator_max_foot_step,
			foot.distance_to(_coordinator_previous_foot))
	_coordinator_previous_foot = foot
	var surface: Vector3 = _ik._ground_sampler.smoothed_target.get(&"left", foot)
	var offset: float = float(_ik._ground_sampler.debug_effective_offset.get(&"left", 0.0))
	_coordinator_min_sole_clearance = minf(
			_coordinator_min_sole_clearance, foot.y - surface.y - offset)
	if bool(_ik._leg_solver.debug_stance_limited.get(&"left", false)):
		_coordinator_stance_limit_frames += 1
	if sample >= COORDINATOR_SAMPLE_FRAMES:
		_begin_straight_knee_check()


func _begin_straight_knee_check() -> void:
	_checking_coordinator = false
	_checking_straight_knee = true
	_straight_knee_frame = 0
	_player.global_position = STRAIGHT_KNEE_POSITION
	_player.rotation = Vector3(0.0, deg_to_rad(STRAIGHT_KNEE_YAW_DEG), 0.0)
	_player.velocity = Vector3.ZERO
	_player.movement_input_override = Vector2.ZERO
	_player.body.anim_player.play(&"moves/unarmed_idle", 0.0)
	_ik.reset_runtime_state()


func _process_straight_knee_check() -> void:
	_straight_knee_frame += 1
	if _straight_knee_frame < STRAIGHT_KNEE_WARMUP_FRAMES:
		return
	if _straight_knee_frame == STRAIGHT_KNEE_WARMUP_FRAMES:
		for side: StringName in [&"left", &"right"]:
			var target := (STRAIGHT_KNEE_LEFT_TARGET
					if side == &"left" else STRAIGHT_KNEE_RIGHT_TARGET)
			_ik._ground_sampler.smoothed_target[side] = target
			_ik._ground_sampler.smoothed_normal[side] = Vector3.UP
			_ik._ground_sampler.idle_lower_latched_target[side] = target
		_straight_knee_previous_foot = _final_foot_position(&"right")
		return
	var sample := _straight_knee_frame - STRAIGHT_KNEE_WARMUP_FRAMES
	var foot := _final_foot_position(&"right")
	_straight_knee_max_foot_step = maxf(_straight_knee_max_foot_step,
			foot.distance_to(_straight_knee_previous_foot))
	_straight_knee_previous_foot = foot
	var plan: FootIKTargetPlan = _ik._target_coordinator.get_plan(&"right")
	_straight_knee_plan_valid = (_straight_knee_plan_valid and plan != null
			and plan.valid and plan.owner == FootIKTargetPlan.Owner.IDLE_LOWER_LATCH
			and plan.reason == "validated_lower_support")
	if sample > STRAIGHT_KNEE_SAMPLE_FRAMES - 60:
		_straight_knee_final_flexion = float(
				_ik._leg_solver.debug_signed_knee_flexion.get(&"right", 0.0))
		_straight_knee_final_target_error = float(
				_ik._leg_solver.debug_target_error.get(&"right", INF))
		if bool(_ik._leg_solver.debug_knee_direction_constrained.get(&"right", false)):
			_straight_knee_late_constraints += 1
	if sample >= STRAIGHT_KNEE_SAMPLE_FRAMES:
		_finish_check()


func _final_foot_position(side: StringName) -> Vector3:
	return _final_joint_position(side, &"foot")


func _final_joint_position(side: StringName, joint: StringName) -> Vector3:
	var bone_index: int = _ik._bone_indices[side][joint]
	var pose: Transform3D = _ik._final_bone_poses.get(
			bone_index, _player.body.skeleton.get_bone_global_pose(bone_index))
	return _player.body.skeleton.global_transform * pose.origin


func _finish_check() -> void:
	var passed := true
	for side: StringName in [&"left", &"right"]:
		passed = passed and int(_frozen_samples[side]) == SAMPLE_FRAMES
		passed = passed and float(_max_drift[side]) <= MAX_PLANTED_DRIFT
	passed = passed and _turn_max_foot_step <= MAX_TURN_FOOT_STEP
	passed = passed and _stance_cache_aligned
	passed = passed and _timed_idle_handoff_smooth
	var rehome_target: Vector3 = _ik._ground_sampler.smoothed_target.get(
			&"right", Vector3(INF, INF, INF))
	var rehome_inside: bool = _ik._ground_sampler.is_target_inside_stance_zone(
			&"right", rehome_target)
	passed = passed and _rehome_observed and rehome_inside
	passed = passed and _rehome_max_foot_step <= MAX_REHOME_FOOT_STEP
	passed = passed and _rehome_stance_limit_frames <= 2
	passed = passed and _knee_guard_constrained_frames > 0
	passed = passed and _knee_guard_max_step <= MAX_GUARDED_KNEE_STEP
	passed = passed and _live_pose_constrained_frames == 0
	passed = passed and _live_pose_max_target_error <= MAX_LIVE_POSE_TARGET_ERROR
	passed = passed and _live_pose_max_shin_swing \
			<= _ik._ground_sampler._settings.max_upright_shin_swing_degrees + 1.0
	passed = passed and _live_pose_joint_failure.is_empty()
	passed = passed and _live_pose_max_joint_step <= MAX_LIVE_POSE_JOINT_STEP
	passed = passed and _right_stale_rehome_observed
	passed = passed and _right_stale_stance_limit_frames <= 2
	passed = passed and _right_stale_max_foot_step <= MAX_RIGHT_STALE_FOOT_STEP
	passed = passed and _ik._ground_sampler.is_target_inside_stance_zone(
			&"right", _ik._ground_sampler.smoothed_target.get(
					&"right", Vector3(INF, INF, INF)))
	passed = passed and _left_stale_rehome_observed
	passed = passed and _left_stale_stance_limit_frames <= 2
	passed = passed and _left_stale_max_foot_step <= MAX_RIGHT_STALE_FOOT_STEP
	passed = passed and _ik._ground_sampler.is_target_inside_stance_zone(
			&"left", _ik._ground_sampler.smoothed_target.get(
					&"left", Vector3(INF, INF, INF)))
	passed = passed and _straight_knee_plan_valid
	passed = passed and _straight_knee_final_flexion >= MIN_SETTLED_KNEE_FLEXION_DEG
	passed = passed and _straight_knee_final_target_error <= MAX_LIVE_POSE_TARGET_ERROR
	passed = passed and _straight_knee_late_constraints \
			<= MAX_STRAIGHT_KNEE_LATE_CONSTRAINT_FRAMES
	passed = passed and _straight_knee_max_foot_step <= MAX_STRAIGHT_KNEE_FOOT_STEP
	passed = passed and _coordinator_recovery_observed
	passed = passed and _coordinator_invalid_frames == 0
	passed = passed and _coordinator_stance_limit_frames == 0
	passed = passed and _coordinator_max_foot_step <= MAX_COORDINATOR_FOOT_STEP
	passed = passed and _coordinator_min_sole_clearance >= MIN_COORDINATOR_SOLE_CLEARANCE
	passed = passed and _coordinator_generations.size() <= 3
	passed = passed and _ik._ground_sampler.is_target_inside_stance_zone(
			&"left", _ik._ground_sampler.smoothed_target.get(
					&"left", Vector3(INF, INF, INF)))
	var template := ("FOOT_IK_IDLE_PLANT_STABILITY_CHECK %s samples=%d "
			+ "frozen_left=%d frozen_right=%d drift_left_m=%.6f drift_right_m=%.6f "
			+ "limit_m=%.3f turn_step_m=%.6f turn_side=%s turn_frame=%d turn_limit_m=%.3f "
			+ "stance_cache_aligned=%s timed_idle_handoff_smooth=%s "
			+ "rehome_observed=%s rehome_inside=%s rehome_step_m=%.6f rehome_limit_m=%.3f "
			+ "rehome_stance_limit_frames=%d knee_guard_frames=%d "
			+ "knee_guard_step_m=%.6f knee_guard_limit_m=%.3f "
			+ "live_pose_constrained=%d live_pose_target_error_m=%.6f "
			+ "live_pose_shin_deg=%.2f live_pose_joint_step_m=%.6f "
			+ "live_pose_joint_step_at=%s live_pose_joint_failure=%s "
			+ "right_stale_rehome=%s right_stale_limit_frames=%d right_stale_step_m=%.6f "
			+ "left_stale_rehome=%s left_stale_limit_frames=%d left_stale_step_m=%.6f "
			+ "coordinator_recovery=%s invalid_frames=%d stance_limit_frames=%d "
			+ "coordinator_step_m=%.6f min_sole_clearance_m=%.6f generations=%d "
			+ "straight_plan_valid=%s straight_flex_deg=%.2f straight_target_error_m=%.6f "
			+ "straight_late_constraints=%d straight_foot_step_m=%.6f")
	print(template % ["PASS" if passed else "FAIL", _sample_count,
			_frozen_samples[&"left"], _frozen_samples[&"right"],
			_max_drift[&"left"], _max_drift[&"right"], MAX_PLANTED_DRIFT,
			_turn_max_foot_step, String(_turn_max_foot_step_side),
			_turn_max_foot_step_frame, MAX_TURN_FOOT_STEP, str(_stance_cache_aligned),
			str(_timed_idle_handoff_smooth), str(_rehome_observed), str(rehome_inside),
			_rehome_max_foot_step, MAX_REHOME_FOOT_STEP, _rehome_stance_limit_frames,
			_knee_guard_constrained_frames, _knee_guard_max_step, MAX_GUARDED_KNEE_STEP,
			_live_pose_constrained_frames, _live_pose_max_target_error,
			_live_pose_max_shin_swing, _live_pose_max_joint_step,
			_live_pose_max_joint_step_at,
			_live_pose_joint_failure if not _live_pose_joint_failure.is_empty() else "none",
			str(_right_stale_rehome_observed), _right_stale_stance_limit_frames,
			_right_stale_max_foot_step, str(_left_stale_rehome_observed),
			_left_stale_stance_limit_frames, _left_stale_max_foot_step,
			str(_coordinator_recovery_observed), _coordinator_invalid_frames,
			_coordinator_stance_limit_frames, _coordinator_max_foot_step,
			_coordinator_min_sole_clearance, _coordinator_generations.size(),
			str(_straight_knee_plan_valid), _straight_knee_final_flexion,
			_straight_knee_final_target_error, _straight_knee_late_constraints,
			_straight_knee_max_foot_step])
	get_tree().quit(0 if passed else 1)


func _check_stance_limit_cache_alignment() -> bool:
	# Reproduce the state boundary behind the live alternating pose directly:
	# the rate limiter caches an unrestricted correction, then the idle stance
	# guard reduces it before rendering. The cache must retain that reduced pose.
	var side := &"right"
	var poses: Dictionary = _ik._leg_fresh_pose_cache.get(side, {})
	if poses.is_empty():
		return false
	var to_world := _player.skeleton.global_transform
	var animated_hip: Vector3 = to_world * (poses[&"hip"] as Transform3D).origin
	var knee: Vector3 = to_world * (poses[&"knee"] as Transform3D).origin
	var foot: Vector3 = to_world * (poses[&"foot"] as Transform3D).origin
	var left_poses: Dictionary = _ik._leg_fresh_pose_cache.get(&"left", {})
	if left_poses.is_empty():
		return false
	var left_hip: Vector3 = to_world * (left_poses[&"hip"] as Transform3D).origin
	var lateral := left_hip - animated_hip
	lateral.y = 0.0
	if lateral.length_squared() <= 0.0001:
		return false
	var forward_axis := Vector3.UP.cross(lateral.normalized()).normalized()
	for angle_deg: float in [30.0, -30.0, 60.0, -60.0, 90.0, -90.0]:
		var hip_delta := Quaternion(forward_axis, deg_to_rad(angle_deg))
		var knee_delta := Quaternion.IDENTITY
		var rendered_knee := animated_hip + hip_delta * (knee - animated_hip)
		var rendered_foot := rendered_knee + knee_delta * (foot - knee)
		var hip_key := "%s:hip" % side
		var knee_key := "%s:knee" % side
		_ik._leg_solver._previous_corrections[hip_key] = hip_delta
		_ik._leg_solver._previous_corrections[knee_key] = knee_delta
		var limited: Dictionary = _ik._leg_solver._limit_idle_stance_crossing(
				side, to_world, animated_hip, animated_hip, knee, foot,
				hip_delta, knee_delta, rendered_foot)
		if limited.is_empty():
			continue
		var cached_hip: Quaternion = _ik._leg_solver._previous_corrections[hip_key]
		var cached_knee: Quaternion = _ik._leg_solver._previous_corrections[knee_key]
		return (cached_hip.angle_to(limited["hip_delta"] as Quaternion) < 0.0001
				and cached_knee.angle_to(limited["knee_delta"] as Quaternion) < 0.0001)
	return false


func _check_timed_idle_support_handoff() -> bool:
	# A real 60 Hz walk-to-idle handoff must retain the configured weight ramp.
	# Only SkeletonModifier3D's extra delta=0 refresh needs immediate repair.
	var side := &"left"
	var foot_idx: int = _ik._bone_indices[side][&"foot"]
	var foot_pose := _player.skeleton.get_bone_global_pose(foot_idx)
	var to_world := _player.skeleton.global_transform
	var foot_world := to_world * foot_pose.origin
	var previous_weight := 0.347222222222222
	var delta := 1.0 / 60.0
	_player.velocity = Vector3.ZERO
	_player.body.anim_player.play(&"moves/unarmed_idle", 0.0)
	_ik._grounded = true
	_ik._smoothed_ground_weight[side] = previous_weight
	_ik._prev_animated_foot_pos.erase(side)
	var gait: Dictionary = _ik._gait_tracker.update(
			side, foot_pose.origin, foot_world, foot_world,
			true, 0.0, to_world, delta)
	var recovered_weight := float(gait["ground_weight"])
	var expected_max := previous_weight + delta / _ik.ground_weight_rise_time + 0.001
	return recovered_weight <= expected_max
