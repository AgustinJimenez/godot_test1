extends Node3D
## Deterministic IK-off/IK-on comparison for flat-ground locomotion.
##
## Both players receive the same input on the same physics frames. The check
## records each leg joint's largest frame-to-frame angular change and rejects
## IK only when it adds a discontinuity beyond the authored animation's own
## largest change. This preserves intentional fast motion while catching the
## one-frame snaps that previously appeared at animation-loop/contact seams.

const PLAYER_SCENE := preload("res://actors/player/player.tscn")
const CASES: Array[Dictionary] = [
	{"name": &"walk", "animation": &"moves/unarmed_walk", "sprint": false},
	{"name": &"sprint", "animation": &"moves/unarmed_sprint", "sprint": true},
]
const JOINTS: Array[StringName] = [
	&"LeftUpLeg", &"LeftLeg", &"LeftFoot", &"LeftToeBase",
	&"RightUpLeg", &"RightLeg", &"RightFoot", &"RightToeBase",
]
const FLOOR_SIZE := Vector3(200.0, 0.2, 200.0)
const SPAWN_Z := 70.0
const SETTLE_FRAMES := 45
const SAMPLE_FRAMES := 240
const MOVING_LANDING_WARMUP_FRAMES := 30
const MOVING_LANDING_SAMPLE_FRAMES := 50
const LANDING_REACH_MARGIN := 0.01
const TURN_SETTLE_FRAMES := 45
const TURN_SAMPLE_FRAMES := 180
const TURN_RATE := TAU / 3.0
const TURN_TARGET_GAP_LIMIT := 0.08
## The fixed-fps walk baseline is ~8.2 degrees/frame and IK is ~8.8. This
## allowance catches the old 23-26 degree snap while leaving modest numerical
## headroom for import/platform variation.
const IK_ADDED_JUMP_ALLOWANCE_DEGREES := 2.0

var _players: Dictionary = {}
var _ik_modifiers: Dictionary = {}
var _joint_indices: Dictionary = {}
var _rendered_poses: Dictionary = {}
var _previous_rotations: Dictionary = {}
var _maximum_jumps: Dictionary = {}
var _case_index := 0
var _settle_frames := 0
var _sample_frames := 0
var _sample_scheduled := false
var _failed := false
var _moving_landing_phase := &""
var _moving_landing_frames := 0
var _moving_landing_samples := 0
var _moving_landing_max_distance := 0.0
var _moving_landing_limit := 0.0
var _moving_landing_static_clip_seen := false
var _turn_frames := 0
var _turn_samples := 0
var _turn_max_target_gap := 0.0


func _ready() -> void:
	_build_floor()
	_spawn_player(&"authored", -1.5, false)
	_spawn_player(&"ik", 1.5, true)
	_start_case()


func _physics_process(delta: float) -> void:
	if _case_index >= CASES.size():
		if _moving_landing_phase == &"turn_settle" or _moving_landing_phase == &"turn":
			_process_turn(delta)
			return
		_process_moving_landing()
		return
	var data: Dictionary = CASES[_case_index]
	var expected_animation := data["animation"] as StringName
	if not _players_in_animation(expected_animation):
		_settle_frames = 0
		return
	if _settle_frames < SETTLE_FRAMES:
		_settle_frames += 1
		return
	if not _sample_scheduled:
		_sample_scheduled = true
		call_deferred(&"_sample_frame")


func _exit_tree() -> void:
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
	if bool(data["sprint"]):
		Input.action_press(&"sprint")
	else:
		Input.action_release(&"sprint")
	for key: StringName in _players:
		var player := _players[key] as Player
		player.global_position = Vector3(
				-1.5 if key == &"authored" else 1.5, 0.05, SPAWN_Z)
		player.velocity = Vector3.ZERO
		player.movement_input_override = Vector2(0.0, -1.0)
		player.body.anim_player.stop()
		var modifier := _ik_modifiers[key] as PlayerFootIKModifier
		modifier.reset_runtime_state()
	_settle_frames = 0
	_sample_frames = 0
	_previous_rotations.clear()
	_maximum_jumps = {&"authored": {}, &"ik": {}}


func _players_in_animation(expected: StringName) -> bool:
	for player: Player in _players.values():
		if StringName(player.body.anim_player.current_animation) != expected:
			return false
	return true


func _sample_frame() -> void:
	_sample_scheduled = false
	if _case_index >= CASES.size():
		return
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
			_previous_rotations[sample_key] = rotation
	_sample_frames += 1
	if _sample_frames < SAMPLE_FRAMES:
		return
	_finish_case()


func _capture_rendered_pose(key: StringName) -> void:
	var player := _players[key] as Player
	var poses := _rendered_poses[key] as Dictionary
	for joint: StringName in JOINTS:
		var bone_index: int = (_joint_indices[key] as Dictionary)[joint]
		poses[bone_index] = player.skeleton.get_bone_global_pose(bone_index)


func _final_pose(player: Player, modifier: PlayerFootIKModifier,
		bone_index: int, key: StringName) -> Transform3D:
	var poses := _rendered_poses[key] as Dictionary
	if poses.has(bone_index):
		return poses[bone_index] as Transform3D
	if key == &"ik" and modifier._final_bone_poses.has(bone_index):
		return modifier._final_bone_poses[bone_index] as Transform3D
	return player.skeleton.get_bone_global_pose(bone_index)


func _finish_case() -> void:
	var case_failed := false
	var worst_added := -INF
	var worst_joint := StringName()
	var authored_max := 0.0
	var ik_max := 0.0
	var authored := _maximum_jumps[&"authored"] as Dictionary
	var corrected := _maximum_jumps[&"ik"] as Dictionary
	for joint: StringName in JOINTS:
		var source_jump := float(authored.get(joint, 0.0))
		var ik_jump := float(corrected.get(joint, 0.0))
		var added := ik_jump - source_jump
		authored_max = maxf(authored_max, source_jump)
		ik_max = maxf(ik_max, ik_jump)
		if added > worst_added:
			worst_added = added
			worst_joint = joint
		if added > IK_ADDED_JUMP_ALLOWANCE_DEGREES:
			case_failed = true
	_failed = _failed or case_failed
	var case_name := String(CASES[_case_index]["name"])
	if authored_max < 0.1:
		case_failed = true # A motion-blind harness must never report a pass.
		_failed = true
	print("FOOT_IK_LOCOMOTION_CHECK ", "FAIL" if case_failed else "PASS",
			" case=", case_name,
			" samples=", _sample_frames,
			" authored_max_deg=", snappedf(authored_max, 0.001),
			" ik_max_deg=", snappedf(ik_max, 0.001),
			" worst_added_deg=", snappedf(worst_added, 0.001),
			" worst_joint=", worst_joint,
			" allowance_deg=", IK_ADDED_JUMP_ALLOWANCE_DEGREES)
	_case_index += 1
	if _case_index < CASES.size():
		_start_case()
		return
	_start_moving_landing()


func _start_moving_landing() -> void:
	Input.action_release(&"sprint")
	var player := _players[&"ik"] as Player
	player.global_position = Vector3(1.5, 0.05, SPAWN_Z)
	player.velocity = Vector3.ZERO
	player.movement_input_override = Vector2(0.0, -1.0)
	(_ik_modifiers[&"ik"] as PlayerFootIKModifier).reset_runtime_state()
	_moving_landing_phase = &"warmup"
	_moving_landing_frames = 0
	_moving_landing_samples = 0
	_moving_landing_max_distance = 0.0
	_moving_landing_limit = 0.0
	_moving_landing_static_clip_seen = false


func _process_moving_landing() -> void:
	var player := _players[&"ik"] as Player
	if _moving_landing_phase == &"warmup":
		if (player.is_on_floor()
				and player.body.anim_player.current_animation == "moves/unarmed_walk"):
			_moving_landing_frames += 1
		if _moving_landing_frames >= MOVING_LANDING_WARMUP_FRAMES:
			player.velocity.y = player.jump_velocity
			_moving_landing_phase = &"airborne"
		return
	if _moving_landing_phase == &"airborne":
		if not player.is_on_floor():
			_moving_landing_phase = &"falling"
		return
	if _moving_landing_phase == &"falling":
		if player.is_on_floor():
			_moving_landing_phase = &"landed"
		return
	if _moving_landing_phase == &"landed" and not _sample_scheduled:
		_moving_landing_static_clip_seen = (_moving_landing_static_clip_seen
				or player.body.anim_player.current_animation == "moves/unarmed_jump_land")
		_sample_scheduled = true
		call_deferred(&"_sample_moving_landing")


func _sample_moving_landing() -> void:
	_sample_scheduled = false
	var player := _players[&"ik"] as Player
	var modifier := _ik_modifiers[&"ik"] as PlayerFootIKModifier
	for side: StringName in [&"left", &"right"]:
		if (not modifier._smoothed_target.has(side)
				or float(modifier._smoothed_ground_weight.get(side, 0.0)) < 0.95):
			continue
		var hip_index: int = (modifier._bone_indices[side] as Dictionary)["hip"]
		var hip_pose: Transform3D = modifier._final_bone_poses.get(
				hip_index, player.skeleton.get_bone_global_pose(hip_index))
		var hip_world: Vector3 = player.skeleton.global_transform * hip_pose.origin
		var target := modifier._smoothed_target[side] as Vector3
		var horizontal_distance := Vector2(
				hip_world.x - target.x, hip_world.z - target.z).length()
		_moving_landing_max_distance = maxf(
				_moving_landing_max_distance, horizontal_distance)
		var lengths := modifier._leg_lengths[side] as Dictionary
		_moving_landing_limit = maxf(
				_moving_landing_limit, float(lengths["upper"]) + float(lengths["lower"])
				+ LANDING_REACH_MARGIN)
	_moving_landing_samples += 1
	if _moving_landing_samples < MOVING_LANDING_SAMPLE_FRAMES:
		return
	var landing_failed := (_moving_landing_samples == 0
			or _moving_landing_max_distance > _moving_landing_limit
			or _moving_landing_static_clip_seen)
	_failed = _failed or landing_failed
	print("FOOT_IK_MOVING_LANDING_CHECK ", "FAIL" if landing_failed else "PASS",
			" samples=", _moving_landing_samples,
			" max_horizontal_target_distance_m=",
			snappedf(_moving_landing_max_distance, 0.000001),
			" reachable_limit_m=", snappedf(_moving_landing_limit, 0.000001),
			" static_landing_clip_seen=", _moving_landing_static_clip_seen)
	_start_turn()


func _start_turn() -> void:
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
		if (not modifier._smoothed_target.has(side)
				or not modifier._leg_fresh_pose_cache.has(side)
				or float(modifier._smoothed_ground_weight.get(side, 0.0)) < 0.95):
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
	print("FOOT_IK_TURN_TARGET_CHECK ", "FAIL" if turn_failed else "PASS",
			" samples=", _turn_samples,
			" max_target_gap_m=", snappedf(_turn_max_target_gap, 0.000001),
			" limit_m=", TURN_TARGET_GAP_LIMIT,
			" authored_max_deg=", snappedf(authored_max, 0.001),
			" ik_max_deg=", snappedf(ik_max, 0.001),
			" worst_added_deg=", snappedf(worst_added, 0.001),
			" worst_joint=", worst_joint)
	print("FOOT_IK_LOCOMOTION_SUITE ", "FAIL" if _failed else "PASS")
	get_tree().quit(1 if _failed else 0)


func _find_foot_ik(player: Player) -> PlayerFootIKModifier:
	for child: Node in player.skeleton.get_children():
		if child is PlayerFootIKModifier:
			return child
	assert(false, "Player scene must contain PlayerFootIKModifier")
	return null
