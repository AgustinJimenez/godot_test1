extends Node3D
## Deterministic IK-off/IK-on comparison for flat-ground locomotion.
##
## Both players receive the same input on the same physics frames. The check
## records each leg joint's largest frame-to-frame angular change and rejects
## IK only when it adds a discontinuity beyond the authored animation's own
## largest change. This preserves intentional fast motion while catching the
## one-frame snaps that previously appeared at animation-loop/contact seams.

const PLAYER_SCENE := preload("res://actors/player/player.tscn")
const REGRESSION_AUDIT := preload("res://tests/manual/foot_ik/foot_ik_regression_audit.gd")
const LOCOMOTION_CASES := preload("res://tests/manual/foot_ik/foot_ik_locomotion_cases.gd")
const CASES: Array[Dictionary] = LOCOMOTION_CASES.CASES
const JOINTS: Array[StringName] = [
	&"LeftUpLeg",
	&"LeftLeg",
	&"LeftFoot",
	&"LeftToeBase",
	&"RightUpLeg",
	&"RightLeg",
	&"RightFoot",
	&"RightToeBase",
]
const FLOOR_SIZE := Vector3(200.0, 0.2, 200.0)
const SPAWN_Z := 70.0
const SETTLE_FRAMES := 45
const SAMPLE_FRAMES := 240
const MOVING_LANDING_WARMUP_FRAMES := 30
const MOVING_LANDING_SAMPLE_FRAMES := 50
const LANDING_REACH_MARGIN := 0.01
const LANDING_INITIAL_WEIGHT_LIMIT := 0.95
const LANDING_INITIAL_FOOT_JUMP_LIMIT_DEGREES := 50.0
const LANDING_BODY_ADDED_JUMP_ALLOWANCE_DEGREES := 2.0
const LANDING_BODY_ADDED_PEAK_ALLOWANCE_DEGREES := 12.0
const LANDING_BODY_ADDED_POSITION_ALLOWANCE := 0.05
const TURN_SETTLE_FRAMES := 45
const TURN_SAMPLE_FRAMES := 180
const TURN_RATE := TAU / 3.0
const TURN_TARGET_GAP_LIMIT := 0.08
## The fixed-fps walk baseline is ~8.2 degrees/frame and IK is ~8.8. This
## allowance catches the old 23-26 degree snap while leaving modest numerical
## headroom for import/platform variation.
const IK_ADDED_JUMP_ALLOWANCE_DEGREES := 2.0
const IK_FRAME_ADDED_JUMP_ALLOWANCE_DEGREES := 4.0
const FULL_PLANT_TARGET_JUMP_LIMIT := 0.2
const BONE_LENGTH_ERROR_LIMIT := 0.001
const IDLE_POSE_ROTATION_LIMIT_DEGREES := 0.1
const IDLE_POSE_POSITION_LIMIT := 0.001

var _players: Dictionary = {}
var _ik_modifiers: Dictionary = {}
var _joint_indices: Dictionary = {}
var _rendered_poses: Dictionary = {}
var _previous_rotations: Dictionary = {}
var _maximum_jumps: Dictionary = {}
var _current_jumps: Dictionary = {}
var _previous_authored_jumps: Dictionary = {}
var _worst_frame_added := -INF
var _worst_frame_joint := StringName()
var _maximum_planted_target_distance := 0.0
var _planted_target_reach_limit := 0.0
var _maximum_locked_foot_error := 0.0
var _locomotion_lock_samples := 0
var _maximum_ground_weight: Dictionary = {}
var _maximum_raw_weight: Dictionary = {}
var _contact_samples: Dictionary = {}
var _minimum_contact_distance: Dictionary = {}
var _velocity_range: Dictionary = {}
var _minimum_stance_target_distance := INF
var _previous_ground_targets: Dictionary = {}
var _previous_ground_weights: Dictionary = {}
var _maximum_full_plant_target_jump := 0.0
var _maximum_bone_length_error := 0.0
var _maximum_thigh_swing: Dictionary = {}
var _maximum_pose_rotation_difference := 0.0
var _maximum_pose_position_difference := 0.0
var _maximum_pose_difference_joint := StringName()
var _case_index := 0
var _settle_frames := 0
var _sample_frames := 0
var _sample_scheduled := false
var _pre_transition_frames := 0
var _pre_transition_complete := false
var _failed := false
var _moving_landing_phase := &""
var _moving_landing_frames := 0
var _moving_landing_samples := 0
var _moving_landing_max_distance := 0.0
var _moving_landing_limit := 0.0
var _moving_landing_static_clip_seen := false
var _moving_landing_initial_weight := 0.0
var _moving_landing_previous_rotations: Dictionary = {}
var _moving_landing_max_foot_jumps: Dictionary = {}
var _moving_landing_initial_foot_jumps: Dictionary = {}
var _moving_landing_initial_joint_jumps: Dictionary = {}
var _moving_landing_max_joint_jumps: Dictionary = {}
var _moving_landing_current_joint_jumps: Dictionary = {}
var _moving_landing_previous_authored_jumps: Dictionary = {}
var _moving_landing_initial_added_body_jump := 0.0
var _moving_landing_max_added_body_jump := 0.0
var _moving_landing_previous_positions: Dictionary = {}
var _moving_landing_current_position_jumps: Dictionary = {}
var _moving_landing_previous_authored_position_jumps: Dictionary = {}
var _moving_landing_max_added_position_jump := 0.0
var _turn_frames := 0
var _turn_samples := 0
var _turn_max_target_gap := 0.0
var _regression_audit: FootIkRegressionAudit


func _ready() -> void:
	_build_floor()
	_spawn_player(&"authored", -1.5, false)
	_spawn_player(&"ik", 1.5, true)
	_regression_audit = REGRESSION_AUDIT.new(_players, _ik_modifiers, _rendered_poses)
	_failed = LOCOMOTION_CASES.verify_directional_clips((_players[&"authored"] as Player).body)
	_start_case()


func _physics_process(delta: float) -> void:
	if _case_index >= CASES.size():
		if _moving_landing_phase == &"turn_settle" or _moving_landing_phase == &"turn":
			_process_turn(delta)
			return
		_process_moving_landing()
		return
	var data: Dictionary = CASES[_case_index]
	if _process_pre_transition(data):
		return
	var expected_animation := data["animation"] as StringName
	if not _players_in_animation(expected_animation):
		_settle_frames = 0
		return
	if _settle_frames < int(data.get("settle_frames", SETTLE_FRAMES)):
		_settle_frames += 1
		return
	if not _sample_scheduled:
		_sample_scheduled = true
		call_deferred(&"_sample_frame")


func _process_pre_transition(data: Dictionary) -> bool:
	var pre_animation := data.get("pre_animation", &"") as StringName
	if _pre_transition_complete or pre_animation == &"":
		return false
	if not _players_in_animation(pre_animation):
		_pre_transition_frames = 0
		return true
	_pre_transition_frames += 1
	if _pre_transition_frames < int(data.get("pre_frames", 0)):
		return true
	for player: Player in _players.values():
		player._crouched = bool(data.get("crouched", false))
		player.movement_input_override = data.get("movement", Vector2(0.0, -1.0)) as Vector2
	_pre_transition_complete = true
	return true


func _exit_tree() -> void:
	Engine.time_scale = 1.0
	Input.action_release(&"sprint")


func _build_floor() -> void:
	var floor := StaticBody3D.new()
	floor.name = &"RegressionFloor"
	add_child(floor)
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = FLOOR_SIZE
	collision.shape = shape
	collision.position.y = -FLOOR_SIZE.y * 0.5
	floor.add_child(collision)


func _spawn_player(key: StringName, lane_x: float, ik_enabled: bool) -> void:
	var player := PLAYER_SCENE.instantiate() as Player
	player.name = StringName("%sPlayer" % String(key).capitalize())
	player.position = Vector3(lane_x, 0.05, SPAWN_Z)
	player.movement_input_override = Vector2(0.0, -1.0)
	add_child(player)
	for camera: Node in player.find_children("*", "Camera3D", true, false):
		(camera as Camera3D).current = false
	var modifier := _find_foot_ik(player)
	modifier.set_debug_enabled(ik_enabled)
	_players[key] = player
	_ik_modifiers[key] = modifier
	var indices: Dictionary = {}
	for joint: StringName in JOINTS:
		indices[joint] = player.skeleton.find_bone(player.body.resolve_bone_name(joint))
	_joint_indices[key] = indices
	_rendered_poses[key] = {}
	player.skeleton.skeleton_updated.connect(_capture_rendered_pose.bind(key))


func _start_case() -> void:
	var data: Dictionary = CASES[_case_index]
	Engine.time_scale = float(data.get("time_scale", 1.0))
	if bool(data["sprint"]):
		Input.action_press(&"sprint")
	else:
		Input.action_release(&"sprint")
	for key: StringName in _players:
		var player := _players[key] as Player
		player.global_position = Vector3(-1.5 if key == &"authored" else 1.5, 0.05, SPAWN_Z)
		player.velocity = Vector3.ZERO
		player.stamina = player.sprint_duration
		player._sprint_locked = false
		player.movement_input_override = (
			data.get(
				"pre_movement" if data.has("pre_animation") else "movement", Vector2(0.0, -1.0)
			)
			as Vector2
		)
		player._crouched = (
			bool(data.get("pre_crouched", false))
			if data.has("pre_animation")
			else bool(data.get("crouched", false))
		)
		player.body.anim_player.stop()
		var modifier := _ik_modifiers[key] as PlayerFootIKModifier
		modifier.reset_runtime_state()
	_settle_frames = 0
	_pre_transition_frames = 0
	_pre_transition_complete = not data.has("pre_animation")
	_sample_frames = 0
	_previous_rotations.clear()
	_maximum_jumps = {&"authored": {}, &"ik": {}}
	_current_jumps.clear()
	_previous_authored_jumps.clear()
	_worst_frame_added = -INF
	_worst_frame_joint = StringName()
	_maximum_planted_target_distance = 0.0
	_planted_target_reach_limit = 0.0
	_maximum_locked_foot_error = 0.0
	_locomotion_lock_samples = 0
	_maximum_ground_weight.clear()
	_maximum_raw_weight.clear()
	_contact_samples.clear()
	_minimum_contact_distance.clear()
	_velocity_range.clear()
	_minimum_stance_target_distance = INF
	_previous_ground_targets.clear()
	_previous_ground_weights.clear()
	_maximum_full_plant_target_jump = 0.0
	_maximum_bone_length_error = 0.0
	_maximum_thigh_swing.clear()
	_maximum_pose_rotation_difference = 0.0
	_maximum_pose_position_difference = 0.0
	_maximum_pose_difference_joint = &""
	_regression_audit.start_case(String(data["name"]))


func _players_in_animation(expected: StringName) -> bool:
	for player: Player in _players.values():
		if StringName(player.body.anim_player.current_animation) != expected:
			return false
	return true


func _sample_frame() -> void:
	_sample_scheduled = false
	if _case_index >= CASES.size():
		return
	_current_jumps.clear()
	for key: StringName in _players:
		var player := _players[key] as Player
		var modifier := _ik_modifiers[key] as PlayerFootIKModifier
		var indices := _joint_indices[key] as Dictionary
		for joint: StringName in JOINTS:
			var bone_index: int = indices[joint]
			var pose := _final_pose(player, modifier, bone_index, key)
			var sample_key := "%s:%s" % [key, joint]
			var rotation := pose.basis.get_rotation_quaternion().normalized()
			if _previous_rotations.has(sample_key):
				var previous := _previous_rotations[sample_key] as Quaternion
				var jump_degrees := rad_to_deg(previous.angle_to(rotation))
				var maxima := _maximum_jumps[key] as Dictionary
				maxima[joint] = maxf(float(maxima.get(joint, 0.0)), jump_degrees)
				_current_jumps[sample_key] = jump_degrees
			_previous_rotations[sample_key] = rotation
	_record_frame_added_motion()
	_record_planted_target_reach()
	_record_locomotion_lock_error()
	_record_leg_geometry()
	_record_pose_difference()
	var animation_time := (_players[&"ik"] as Player).body.anim_player.current_animation_position
	_regression_audit.sample(_sample_frames, animation_time)
	_sample_frames += 1
	var required_frames: int = int(CASES[_case_index].get("sample_frames", SAMPLE_FRAMES))
	if _sample_frames < required_frames:
		return
	_finish_case()


func _record_pose_difference() -> void:
	if not bool(CASES[_case_index].get("expect_same_pose", false)):
		return
	var authored_player := _players[&"authored"] as Player
	var authored_modifier := _ik_modifiers[&"authored"] as PlayerFootIKModifier
	var ik_player := _players[&"ik"] as Player
	var ik_modifier := _ik_modifiers[&"ik"] as PlayerFootIKModifier
	for joint: StringName in JOINTS:
		var authored_index: int = (_joint_indices[&"authored"] as Dictionary)[joint]
		var ik_index: int = (_joint_indices[&"ik"] as Dictionary)[joint]
		var authored := _final_pose(authored_player, authored_modifier, authored_index, &"authored")
		var corrected := _final_pose(ik_player, ik_modifier, ik_index, &"ik")
		var rotation_difference := rad_to_deg(
			authored.basis.get_rotation_quaternion().angle_to(
				corrected.basis.get_rotation_quaternion()
			)
		)
		var position_difference := authored.origin.distance_to(corrected.origin)
		if (
			rotation_difference > _maximum_pose_rotation_difference
			or position_difference > _maximum_pose_position_difference
		):
			_maximum_pose_difference_joint = joint
		_maximum_pose_rotation_difference = maxf(
			_maximum_pose_rotation_difference, rotation_difference
		)
		_maximum_pose_position_difference = maxf(
			_maximum_pose_position_difference, position_difference
		)


func _record_frame_added_motion() -> void:
	var checked_joints: Array = CASES[_case_index].get("joints", JOINTS)
	for joint: StringName in checked_joints:
		var authored_current := float(_current_jumps.get("authored:%s" % joint, 0.0))
		var authored_reference := maxf(
			authored_current, float(_previous_authored_jumps.get(joint, 0.0))
		)
		var added := float(_current_jumps.get("ik:%s" % joint, 0.0)) - authored_reference
		if added > _worst_frame_added:
			_worst_frame_added = added
			_worst_frame_joint = joint
		_previous_authored_jumps[joint] = authored_current


func _record_planted_target_reach() -> void:
	if not bool(CASES[_case_index].get("check_reach", false)):
		return
	var player := _players[&"ik"] as Player
	var modifier := _ik_modifiers[&"ik"] as PlayerFootIKModifier
	for side: StringName in [&"left", &"right"]:
		if modifier._gait_tracker.is_locomotion_stance_active(side):
			var hip := (modifier._leg_fresh_pose_cache[side] as Dictionary)["hip"] as Transform3D
			var hip_world: Vector3 = player.skeleton.global_transform * hip.origin
			var offset := maxf(
				modifier.ankle_offset, float(modifier._sole_depth_below_foot.get(side, 0.0))
			)
			var target: Vector3 = (
				(modifier._smoothed_target[side] as Vector3)
				+ (modifier._smoothed_normal[side] as Vector3) * offset
			)
			_minimum_stance_target_distance = minf(
				_minimum_stance_target_distance, hip_world.distance_to(target)
			)
		if not modifier._gait_tracker.is_locomotion_target_locked(side):
			continue
		var hip_pose: Transform3D = (modifier._leg_fresh_pose_cache[side] as Dictionary)["hip"]
		var hip_world: Vector3 = player.skeleton.global_transform * hip_pose.origin
		var offset := maxf(
			modifier.ankle_offset, float(modifier._sole_depth_below_foot.get(side, 0.0))
		)
		var target: Vector3 = (
			(modifier._smoothed_target[side] as Vector3)
			+ (modifier._smoothed_normal[side] as Vector3) * offset
		)
		_maximum_planted_target_distance = maxf(
			_maximum_planted_target_distance, hip_world.distance_to(target)
		)
		var lengths := modifier._leg_lengths[side] as Dictionary
		_planted_target_reach_limit = float(lengths["upper"]) + float(lengths["lower"]) + 0.01


func _record_locomotion_lock_error() -> void:
	var player := _players[&"ik"] as Player
	var modifier := _ik_modifiers[&"ik"] as PlayerFootIKModifier
	for side: StringName in [&"left", &"right"]:
		var current_weight: float = modifier._smoothed_ground_weight.get(side, 0.0)
		if modifier._gait_tracker.is_locomotion_target_locked(side):
			if modifier._smoothed_target.has(side):
				var current_target := modifier._smoothed_target[side] as Vector3
				if _previous_ground_targets.has(side):
					_maximum_full_plant_target_jump = maxf(
						_maximum_full_plant_target_jump,
						current_target.distance_to(_previous_ground_targets[side] as Vector3)
					)
				_previous_ground_targets[side] = current_target
		else:
			_previous_ground_targets.erase(side)
		_previous_ground_weights[side] = current_weight
		_maximum_ground_weight[side] = maxf(
			float(_maximum_ground_weight.get(side, 0.0)), current_weight
		)
		_maximum_raw_weight[side] = maxf(
			float(_maximum_raw_weight.get(side, 0.0)),
			float(modifier.debug_raw_weight.get(side, 0.0))
		)
		var velocity: float = modifier.debug_vertical_velocity.get(side, 0.0)
		var velocity_limits: Vector2 = _velocity_range.get(side, Vector2(INF, -INF))
		_velocity_range[side] = Vector2(
			minf(velocity_limits.x, velocity), maxf(velocity_limits.y, velocity)
		)
		if bool(modifier.debug_contact_hit.get(side, false)):
			_contact_samples[side] = int(_contact_samples.get(side, 0)) + 1
			_minimum_contact_distance[side] = minf(
				float(_minimum_contact_distance.get(side, INF)),
				float(modifier.debug_contact_distance.get(side, INF))
			)
		if not modifier._gait_tracker.is_locomotion_target_locked(side):
			continue
		var foot_index: int = (modifier._bone_indices[side] as Dictionary)["foot"]
		var foot_world: Vector3 = (
			player.skeleton.global_transform
			* _final_pose(player, modifier, foot_index, &"ik").origin
		)
		var target := modifier._smoothed_target[side] as Vector3
		_maximum_locked_foot_error = maxf(
			_maximum_locked_foot_error,
			Vector2(foot_world.x - target.x, foot_world.z - target.z).length()
		)
		_locomotion_lock_samples += 1


func _record_leg_geometry() -> void:
	for key: StringName in _players:
		var player := _players[key] as Player
		var modifier := _ik_modifiers[key] as PlayerFootIKModifier
		for side: StringName in [&"left", &"right"]:
			var indices := modifier._bone_indices[side] as Dictionary
			var hip := _final_pose(player, modifier, indices["hip"], key).origin
			var knee := _final_pose(player, modifier, indices["knee"], key).origin
			var foot := _final_pose(player, modifier, indices["foot"], key).origin
			var lengths := modifier._leg_lengths[side] as Dictionary
			var upper_error := absf(hip.distance_to(knee) - float(lengths["upper"]))
			var lower_error := absf(knee.distance_to(foot) - float(lengths["lower"]))
			_maximum_bone_length_error = maxf(
				_maximum_bone_length_error, maxf(upper_error, lower_error)
			)
			var world_direction := player.skeleton.global_transform.basis * (knee - hip)
			var sample := "%s:%s" % [key, side]
			_maximum_thigh_swing[sample] = maxf(
				float(_maximum_thigh_swing.get(sample, 0.0)),
				rad_to_deg(world_direction.angle_to(Vector3.DOWN))
			)


func _capture_rendered_pose(key: StringName) -> void:
	var player := _players[key] as Player
	var poses := _rendered_poses[key] as Dictionary
	for bone_index in player.skeleton.get_bone_count():
		poses[bone_index] = player.skeleton.get_bone_global_pose(bone_index)


func _final_pose(
	player: Player, modifier: PlayerFootIKModifier, bone_index: int, key: StringName
) -> Transform3D:
	var poses := _rendered_poses[key] as Dictionary
	if poses.has(bone_index):
		return poses[bone_index] as Transform3D
	if key == &"ik" and modifier._final_bone_poses.has(bone_index):
		return modifier._final_bone_poses[bone_index] as Transform3D
	return player.skeleton.get_bone_global_pose(bone_index)


func _finish_case() -> void:
	var case_failed := false
	var audit: Dictionary = _regression_audit.finish_case()
	case_failed = bool(audit["failed"])
	var worst_added := -INF
	var worst_joint := StringName()
	var authored_max := 0.0
	var ik_max := 0.0
	var authored := _maximum_jumps[&"authored"] as Dictionary
	var corrected := _maximum_jumps[&"ik"] as Dictionary
	var checked_joints: Array = CASES[_case_index].get("joints", JOINTS)
	var peak_allowance := float(
		CASES[_case_index].get("peak_allowance", IK_ADDED_JUMP_ALLOWANCE_DEGREES)
	)
	for joint: StringName in checked_joints:
		var source_jump := float(authored.get(joint, 0.0))
		var ik_jump := float(corrected.get(joint, 0.0))
		var added := ik_jump - source_jump
		authored_max = maxf(authored_max, source_jump)
		ik_max = maxf(ik_max, ik_jump)
		if added > worst_added:
			worst_added = added
			worst_joint = joint
		if added > peak_allowance:
			case_failed = true
	var frame_allowance := float(
		CASES[_case_index].get("frame_allowance", IK_FRAME_ADDED_JUMP_ALLOWANCE_DEGREES)
	)
	if _worst_frame_added > frame_allowance:
		case_failed = true
	if (
		_planted_target_reach_limit > 0.0
		and _maximum_planted_target_distance > _planted_target_reach_limit
	):
		case_failed = true
	if bool(CASES[_case_index].get("check_reach", false)) and _locomotion_lock_samples == 0:
		case_failed = true
	if (
		_maximum_full_plant_target_jump > FULL_PLANT_TARGET_JUMP_LIMIT
		and bool(CASES[_case_index].get("check_reach", false))
	):
		case_failed = true
	if _maximum_bone_length_error > BONE_LENGTH_ERROR_LIMIT:
		case_failed = true
	if bool(CASES[_case_index].get("expect_same_pose", false)):
		case_failed = (
			case_failed
			or _maximum_pose_rotation_difference > IDLE_POSE_ROTATION_LIMIT_DEGREES
			or _maximum_pose_position_difference > IDLE_POSE_POSITION_LIMIT
		)
	_failed = _failed or case_failed
	var case_name := String(CASES[_case_index]["name"])
	if authored_max < 0.1 and not bool(CASES[_case_index].get("expect_same_pose", false)):
		case_failed = true  # A motion-blind harness must never report a pass.
		_failed = true
	print(
		"FOOT_IK_LOCOMOTION_CHECK ",
		"FAIL" if case_failed else "PASS",
		" case=",
		case_name,
		" samples=",
		_sample_frames,
		" authored_max_deg=",
		snappedf(authored_max, 0.001),
		" ik_max_deg=",
		snappedf(ik_max, 0.001),
		" worst_added_deg=",
		snappedf(worst_added, 0.001),
		" worst_joint=",
		worst_joint,
		" worst_frame_added_deg=",
		snappedf(_worst_frame_added, 0.001),
		" worst_frame_joint=",
		_worst_frame_joint,
		" frame_allowance_deg=",
		frame_allowance,
		" planted_target_distance_m=",
		snappedf(_maximum_planted_target_distance, 0.000001),
		" planted_reach_limit_m=",
		snappedf(_planted_target_reach_limit, 0.000001),
		" lock_samples=",
		_locomotion_lock_samples,
		" locked_foot_error_m=",
		snappedf(_maximum_locked_foot_error, 0.000001),
		" max_weight_l=",
		snappedf(float(_maximum_ground_weight.get(&"left", 0.0)), 0.001),
		" max_weight_r=",
		snappedf(float(_maximum_ground_weight.get(&"right", 0.0)), 0.001),
		" raw_l=",
		snappedf(float(_maximum_raw_weight.get(&"left", 0.0)), 0.001),
		" raw_r=",
		snappedf(float(_maximum_raw_weight.get(&"right", 0.0)), 0.001),
		" hits_l=",
		int(_contact_samples.get(&"left", 0)),
		" hits_r=",
		int(_contact_samples.get(&"right", 0)),
		" min_contact_l=",
		snappedf(float(_minimum_contact_distance.get(&"left", INF)), 0.0001),
		" min_contact_r=",
		snappedf(float(_minimum_contact_distance.get(&"right", INF)), 0.0001),
		" velocity_l=",
		_velocity_range.get(&"left", Vector2.ZERO),
		" velocity_r=",
		_velocity_range.get(&"right", Vector2.ZERO),
		" min_stance_target=",
		snappedf(_minimum_stance_target_distance, 0.0001),
		" full_plant_target_jump_m=",
		snappedf(_maximum_full_plant_target_jump, 0.000001),
		" bone_length_error_m=",
		snappedf(_maximum_bone_length_error, 0.000001),
		" pose_rotation_difference_deg=",
		snappedf(_maximum_pose_rotation_difference, 0.001),
		" pose_position_difference_m=",
		snappedf(_maximum_pose_position_difference, 0.000001),
		" pose_difference_joint=",
		_maximum_pose_difference_joint,
		" thigh_swing_auth_l=",
		snappedf(float(_maximum_thigh_swing.get("authored:left", 0.0)), 0.01),
		" thigh_swing_auth_r=",
		snappedf(float(_maximum_thigh_swing.get("authored:right", 0.0)), 0.01),
		" thigh_swing_ik_l=",
		snappedf(float(_maximum_thigh_swing.get("ik:left", 0.0)), 0.01),
		" thigh_swing_ik_r=",
		snappedf(float(_maximum_thigh_swing.get("ik:right", 0.0)), 0.01),
		" allowance_deg=",
		peak_allowance
	)
	print(
		"FOOT_IK_MATRIX_CHECK ",
		"FAIL" if audit["failed"] else "PASS",
		" case=",
		case_name,
		" metrics=",
		audit
	)
	_case_index += 1
	if _case_index < CASES.size():
		_start_case()
		return
	_start_moving_landing()


func _start_moving_landing() -> void:
	# The full skin matrix currently covers the declarative flat-locomotion
	# catalog. Landing and turning below retain their focused paired metrics;
	# add them to the matrix only with explicit phase start/finish ownership.
	Engine.time_scale = 1.0
	Input.action_press(&"sprint")
	for key: StringName in _players:
		var player := _players[key] as Player
		player.global_position = Vector3(-1.5 if key == &"authored" else 1.5, 0.05, SPAWN_Z)
		player.velocity = Vector3.ZERO
		player.movement_input_override = Vector2(0.0, -1.0)
		(_ik_modifiers[key] as PlayerFootIKModifier).reset_runtime_state()
	_moving_landing_phase = &"warmup"
	_moving_landing_frames = 0
	_moving_landing_samples = 0
	_moving_landing_max_distance = 0.0
	_moving_landing_limit = 0.0
	_moving_landing_static_clip_seen = false
	_moving_landing_initial_weight = 0.0
	_moving_landing_previous_rotations.clear()
	_moving_landing_max_foot_jumps.clear()
	_moving_landing_initial_foot_jumps.clear()
	_moving_landing_initial_joint_jumps.clear()
	_moving_landing_max_joint_jumps.clear()
	_moving_landing_current_joint_jumps.clear()
	_moving_landing_previous_authored_jumps.clear()
	_moving_landing_initial_added_body_jump = 0.0
	_moving_landing_max_added_body_jump = 0.0
	_moving_landing_previous_positions.clear()
	_moving_landing_current_position_jumps.clear()
	_moving_landing_previous_authored_position_jumps.clear()
	_moving_landing_max_added_position_jump = 0.0


func _process_moving_landing() -> void:
	var player := _players[&"ik"] as Player
	if _moving_landing_phase == &"warmup":
		if (
			player.is_on_floor()
			and player.body.anim_player.current_animation == "moves/unarmed_sprint"
		):
			_moving_landing_frames += 1
		if _moving_landing_frames >= MOVING_LANDING_WARMUP_FRAMES:
			for sample_player: Player in _players.values():
				sample_player.velocity.y = sample_player.jump_velocity
			_moving_landing_phase = &"airborne"
		return
	if _moving_landing_phase == &"airborne":
		if not player.is_on_floor():
			_moving_landing_phase = &"falling"
		return
	if _moving_landing_phase == &"falling":
		if player.is_on_floor():
			_moving_landing_phase = &"landed"
		else:
			var ik_mod := _ik_modifiers[&"ik"] as PlayerFootIKModifier
			_moving_landing_initial_weight = maxf(
				float(ik_mod._smoothed_ground_weight.get(&"left", 0.0)),
				float(ik_mod._smoothed_ground_weight.get(&"right", 0.0))
			)
			_capture_landing_rotations(false)
		return
	if _moving_landing_phase == &"landed" and not _sample_scheduled:
		_moving_landing_static_clip_seen = (
			_moving_landing_static_clip_seen
			or player.body.anim_player.current_animation == "moves/unarmed_jump_land"
		)
		_sample_scheduled = true
		call_deferred(&"_sample_moving_landing")


func _sample_moving_landing() -> void:
	_sample_scheduled = false
	var player := _players[&"ik"] as Player
	var modifier := _ik_modifiers[&"ik"] as PlayerFootIKModifier
	_capture_landing_rotations(true)
	for side: StringName in [&"left", &"right"]:
		if (
			not modifier._smoothed_target.has(side)
			or float(modifier._smoothed_ground_weight.get(side, 0.0)) < 0.95
		):
			continue
		var hip_index: int = (modifier._bone_indices[side] as Dictionary)["hip"]
		var hip_pose: Transform3D = modifier._final_bone_poses.get(
			hip_index, player.skeleton.get_bone_global_pose(hip_index)
		)
		var hip_world: Vector3 = player.skeleton.global_transform * hip_pose.origin
		var target := modifier._smoothed_target[side] as Vector3
		var horizontal_distance := Vector2(hip_world.x - target.x, hip_world.z - target.z).length()
		_moving_landing_max_distance = maxf(_moving_landing_max_distance, horizontal_distance)
		var lengths := modifier._leg_lengths[side] as Dictionary
		_moving_landing_limit = maxf(
			_moving_landing_limit,
			float(lengths["upper"]) + float(lengths["lower"]) + LANDING_REACH_MARGIN
		)
	_moving_landing_samples += 1
	if _moving_landing_samples < MOVING_LANDING_SAMPLE_FRAMES:
		return
	var landing_failed := (
		_moving_landing_samples == 0
		or _moving_landing_max_distance > _moving_landing_limit
		or _moving_landing_static_clip_seen
		or _moving_landing_initial_weight > LANDING_INITIAL_WEIGHT_LIMIT
		or (
			float(_moving_landing_initial_foot_jumps.get(&"left", 0.0))
			> LANDING_INITIAL_FOOT_JUMP_LIMIT_DEGREES
		)
		or (
			float(_moving_landing_initial_foot_jumps.get(&"right", 0.0))
			> LANDING_INITIAL_FOOT_JUMP_LIMIT_DEGREES
		)
	)
	var authored_body_jump := _landing_body_jump(&"authored", _moving_landing_initial_joint_jumps)
	var ik_body_jump := _landing_body_jump(&"ik", _moving_landing_initial_joint_jumps)
	var authored_body_peak := _landing_body_jump(&"authored", _moving_landing_max_joint_jumps)
	var ik_body_peak := _landing_body_jump(&"ik", _moving_landing_max_joint_jumps)
	landing_failed = (
		landing_failed
		or _moving_landing_initial_added_body_jump > LANDING_BODY_ADDED_JUMP_ALLOWANCE_DEGREES
		or _moving_landing_max_added_body_jump > LANDING_BODY_ADDED_PEAK_ALLOWANCE_DEGREES
		or _moving_landing_max_added_position_jump > LANDING_BODY_ADDED_POSITION_ALLOWANCE
	)
	_failed = _failed or landing_failed
	print(
		"FOOT_IK_MOVING_LANDING_CHECK ",
		"FAIL" if landing_failed else "PASS",
		" samples=",
		_moving_landing_samples,
		" max_horizontal_target_distance_m=",
		snappedf(_moving_landing_max_distance, 0.000001),
		" reachable_limit_m=",
		snappedf(_moving_landing_limit, 0.000001),
		" static_landing_clip_seen=",
		_moving_landing_static_clip_seen,
		" initial_weight=",
		snappedf(_moving_landing_initial_weight, 0.001),
		" left_foot_jump_deg=",
		snappedf(float(_moving_landing_max_foot_jumps.get(&"left", 0.0)), 0.001),
		" right_foot_jump_deg=",
		snappedf(float(_moving_landing_max_foot_jumps.get(&"right", 0.0)), 0.001),
		" initial_left_foot_jump_deg=",
		snappedf(float(_moving_landing_initial_foot_jumps.get(&"left", 0.0)), 0.001),
		" initial_right_foot_jump_deg=",
		snappedf(float(_moving_landing_initial_foot_jumps.get(&"right", 0.0)), 0.001),
		" authored_body_jump_deg=",
		snappedf(authored_body_jump, 0.001),
		" ik_body_jump_deg=",
		snappedf(ik_body_jump, 0.001),
		" added_body_jump_deg=",
		snappedf(_moving_landing_initial_added_body_jump, 0.001),
		" authored_body_peak_deg=",
		snappedf(authored_body_peak, 0.001),
		" ik_body_peak_deg=",
		snappedf(ik_body_peak, 0.001),
		" added_body_peak_deg=",
		snappedf(_moving_landing_max_added_body_jump, 0.001),
		" added_body_position_peak_m=",
		snappedf(_moving_landing_max_added_position_jump, 0.000001)
	)
	_start_turn()


func _capture_landing_rotations(measure_jump: bool) -> void:
	_moving_landing_current_joint_jumps.clear()
	_moving_landing_current_position_jumps.clear()
	for key: StringName in _players:
		var player := _players[key] as Player
		var modifier := _ik_modifiers[key] as PlayerFootIKModifier
		for side: StringName in [&"left", &"right"]:
			for joint: StringName in [&"hip", &"knee", &"foot", &"toe", &"leaf"]:
				var bone_index: int = (modifier._bone_indices[side] as Dictionary)[joint]
				if bone_index < 0:
					continue
				var pose := _final_pose(player, modifier, bone_index, key)
				var rotation := pose.basis.get_rotation_quaternion().normalized()
				var sample_id := "%s:%s:%s" % [key, side, joint]
				if measure_jump and _moving_landing_previous_rotations.has(sample_id):
					var previous := _moving_landing_previous_rotations[sample_id] as Quaternion
					var jump := rad_to_deg(previous.angle_to(rotation))
					if _moving_landing_samples == 0:
						_moving_landing_initial_joint_jumps[sample_id] = jump
						if key == &"ik" and joint == &"foot":
							_moving_landing_initial_foot_jumps[side] = jump
					if key == &"ik" and joint == &"foot":
						_moving_landing_max_foot_jumps[side] = maxf(
							float(_moving_landing_max_foot_jumps.get(side, 0.0)), jump
						)
					_moving_landing_max_joint_jumps[sample_id] = maxf(
						float(_moving_landing_max_joint_jumps.get(sample_id, 0.0)), jump
					)
					_moving_landing_current_joint_jumps[sample_id] = jump
				if (
					joint == &"hip"
					and measure_jump
					and _moving_landing_previous_positions.has(sample_id)
				):
					_moving_landing_current_position_jumps[sample_id] = pose.origin.distance_to(
						_moving_landing_previous_positions[sample_id] as Vector3
					)
				_moving_landing_previous_rotations[sample_id] = rotation
				if joint == &"hip":
					_moving_landing_previous_positions[sample_id] = pose.origin
	if measure_jump:
		_record_landing_added_body_jump()


func _record_landing_added_body_jump() -> void:
	var frame_added := 0.0
	var frame_position_added := 0.0
	for side: StringName in [&"left", &"right"]:
		for joint: StringName in [&"hip", &"knee"]:
			var suffix := "%s:%s" % [side, joint]
			var authored_current := float(
				_moving_landing_current_joint_jumps.get("authored:%s" % suffix, 0.0)
			)
			# The modifier intentionally holds one pose across an animation-loop
			# seam. At low fixed FPS that shifts an authored joint motion forward
			# by one sample; compare the IK result with either authored sample so
			# the check still rejects newly injected motion, not the known hold.
			var authored := maxf(
				authored_current, float(_moving_landing_previous_authored_jumps.get(suffix, 0.0))
			)
			var ik := float(_moving_landing_current_joint_jumps.get("ik:%s" % suffix, 0.0))
			frame_added = maxf(frame_added, ik - authored)
			_moving_landing_previous_authored_jumps[suffix] = authored_current
		var authored_position_current := float(
			_moving_landing_current_position_jumps.get("authored:%s:hip" % side, 0.0)
		)
		var authored_position := maxf(
			authored_position_current,
			float(_moving_landing_previous_authored_position_jumps.get(side, 0.0))
		)
		var ik_position := float(
			_moving_landing_current_position_jumps.get("ik:%s:hip" % side, 0.0)
		)
		frame_position_added = maxf(frame_position_added, ik_position - authored_position)
		_moving_landing_previous_authored_position_jumps[side] = authored_position_current
	if _moving_landing_samples == 0:
		_moving_landing_initial_added_body_jump = frame_added
	_moving_landing_max_added_body_jump = maxf(_moving_landing_max_added_body_jump, frame_added)
	_moving_landing_max_added_position_jump = maxf(
		_moving_landing_max_added_position_jump, frame_position_added
	)


func _landing_body_jump(key: StringName, jumps: Dictionary) -> float:
	var result := 0.0
	for side: StringName in [&"left", &"right"]:
		for joint: StringName in [&"hip", &"knee"]:
			result = maxf(result, float(jumps.get("%s:%s:%s" % [key, side, joint], 0.0)))
	return result


func _start_turn() -> void:
	Input.action_release(&"sprint")
	for key: StringName in _players:
		var player := _players[key] as Player
		player.global_position = Vector3(-1.5 if key == &"authored" else 1.5, 0.05, SPAWN_Z)
		player.rotation.y = 0.0
		player.velocity = Vector3.ZERO
		player.movement_input_override = Vector2.ZERO
		(_ik_modifiers[key] as PlayerFootIKModifier).reset_runtime_state()
	_moving_landing_phase = &"turn_settle"
	_turn_frames = 0
	_turn_samples = 0
	_turn_max_target_gap = 0.0
	_previous_rotations.clear()
	_maximum_jumps = {&"authored": {}, &"ik": {}}


func _process_turn(delta: float) -> void:
	if _moving_landing_phase == &"turn_settle":
		if _players_in_animation(&"moves/unarmed_idle"):
			_turn_frames += 1
		if _turn_frames >= TURN_SETTLE_FRAMES:
			_moving_landing_phase = &"turn"
			_turn_frames = 0
		return
	for player: Player in _players.values():
		player.rotation.y += TURN_RATE * delta
	_turn_frames += 1
	if not _sample_scheduled:
		_sample_scheduled = true
		call_deferred(&"_sample_turn")


func _sample_turn() -> void:
	_sample_scheduled = false
	var player := _players[&"ik"] as Player
	var modifier := _ik_modifiers[&"ik"] as PlayerFootIKModifier
	for side: StringName in [&"left", &"right"]:
		if (
			not modifier._smoothed_target.has(side)
			or not modifier._leg_fresh_pose_cache.has(side)
			or float(modifier._smoothed_ground_weight.get(side, 0.0)) < 0.95
		):
			continue
		var animated_pose: Transform3D = (modifier._leg_fresh_pose_cache[side] as Dictionary)["foot"]
		var animated_world: Vector3 = player.skeleton.global_transform * animated_pose.origin
		var target := modifier._smoothed_target[side] as Vector3
		var gap := Vector2(animated_world.x - target.x, animated_world.z - target.z).length()
		_turn_max_target_gap = maxf(_turn_max_target_gap, gap)
	for key: StringName in _players:
		var sample_player := _players[key] as Player
		var sample_modifier := _ik_modifiers[key] as PlayerFootIKModifier
		for joint: StringName in JOINTS:
			var bone_index: int = (_joint_indices[key] as Dictionary)[joint]
			var pose := _final_pose(sample_player, sample_modifier, bone_index, key)
			var sample_key := "turn:%s:%s" % [key, joint]
			var rotation := pose.basis.get_rotation_quaternion().normalized()
			if _previous_rotations.has(sample_key):
				var previous := _previous_rotations[sample_key] as Quaternion
				var jump_degrees := rad_to_deg(previous.angle_to(rotation))
				var maxima := _maximum_jumps[key] as Dictionary
				maxima[joint] = maxf(float(maxima.get(joint, 0.0)), jump_degrees)
			_previous_rotations[sample_key] = rotation
	_turn_samples += 1
	if _turn_frames < TURN_SAMPLE_FRAMES:
		return
	var turn_failed := _turn_samples == 0 or _turn_max_target_gap > TURN_TARGET_GAP_LIMIT
	var worst_added := -INF
	var worst_joint := StringName()
	var authored_max := 0.0
	var ik_max := 0.0
	for joint: StringName in JOINTS:
		var source_jump := float((_maximum_jumps[&"authored"] as Dictionary).get(joint, 0.0))
		var ik_jump := float((_maximum_jumps[&"ik"] as Dictionary).get(joint, 0.0))
		var added := ik_jump - source_jump
		authored_max = maxf(authored_max, source_jump)
		ik_max = maxf(ik_max, ik_jump)
		if added > worst_added:
			worst_added = added
			worst_joint = joint
	turn_failed = turn_failed or worst_added > IK_ADDED_JUMP_ALLOWANCE_DEGREES
	_failed = _failed or turn_failed
	print(
		"FOOT_IK_TURN_TARGET_CHECK ",
		"FAIL" if turn_failed else "PASS",
		" samples=",
		_turn_samples,
		" max_target_gap_m=",
		snappedf(_turn_max_target_gap, 0.000001),
		" limit_m=",
		TURN_TARGET_GAP_LIMIT,
		" authored_max_deg=",
		snappedf(authored_max, 0.001),
		" ik_max_deg=",
		snappedf(ik_max, 0.001),
		" worst_added_deg=",
		snappedf(worst_added, 0.001),
		" worst_joint=",
		worst_joint
	)
	print("FOOT_IK_LOCOMOTION_SUITE ", "FAIL" if _failed else "PASS")
	get_tree().quit(1 if _failed else 0)


func _find_foot_ik(player: Player) -> PlayerFootIKModifier:
	for child: Node in player.skeleton.get_children():
		if child is PlayerFootIKModifier:
			return child
	assert(false, "Player scene must contain PlayerFootIKModifier")
	return null
