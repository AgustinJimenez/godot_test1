class_name FootIkLedgeSafetyCheck
extends Node3D
## Verifies that ledge safety rejects a complete movement request when it
## points into a void, including diagonals, without blocking movement that is
## genuinely parallel to the supported platform edge.

const PLATFORM_HEIGHT := 3.0
const PLATFORM_SIZE := Vector3(4.0, PLATFORM_HEIGHT, 4.0)
const START_POSITION := Vector3(0.0, PLATFORM_HEIGHT, -1.80)
const STAIR_SURFACES := preload("res://tests/manual/foot_ik/foot_ik_stair_surfaces.gd")
const STAIR_ORIGIN := Vector3(8.0, 0.0, 0.0)
const STAIR_WIDTH := 3.0
const STAIR_TREAD_DEPTH := 0.6
const STAIR_COUNT := 6
const STAIR_HEIGHT := 0.35
const SETTLE_FRAMES := 12
const MOVE_FRAMES := 20
const LONG_MOVE_FRAMES := 400
const RECOVERY_FRAMES := 180
const BLOCKED_DISTANCE_LIMIT := 0.02
const PARALLEL_DISTANCE_MIN := 0.30
const ZONE_MIN_LATERAL := 0.06
const ZONE_MAX_LATERAL := 0.56
const ZONE_MAX_LONGITUDINAL := 0.40

var _player: Player
var _ik: PlayerFootIKModifier
var _cases: Array[Dictionary] = [
	{"name": "straight_into_void", "input": Vector2(0.0, -1.0), "blocked": true},
	{"name": "diagonal_left_into_void", "input": Vector2(-1.0, -1.0), "blocked": true},
	{"name": "diagonal_right_into_void", "input": Vector2(1.0, -1.0), "blocked": true},
	{"name": "parallel_to_edge", "input": Vector2(1.0, 0.0), "blocked": false},
	{
		"name": "held_diagonal_stair_landing_edge",
		"input": Vector2(0.707107, 0.707107),
		"blocked": true,
		"start": STAIR_ORIGIN + Vector3(-1.2914, 2.101, 3.840638),
		"yaw": deg_to_rad(-61.0552),
		"move_frames": LONG_MOVE_FRAMES,
		"recovery_frames": RECOVERY_FRAMES,
		"check_feet": true,
	},
	{
		"name": "held_lateral_stair_landing_turn",
		"input": Vector2(-1.0, 0.0),
		"blocked": true,
		"blocked_limit": 0.05,
		"start": STAIR_ORIGIN + Vector3(-1.21045, 2.101, 3.923219),
		"yaw": deg_to_rad(109.69),
		"turn_yaw": deg_to_rad(68.43),
		"turn_hold_frames": 60,
		"turn_steps": 12,
		"move_frames": 114,
		"recovery_frames": 30,
		"check_feet": true,
		"check_zones_during_turn": true,
	},
	{
		"name": "jump_land_middle_of_landing_edge",
		"input": Vector2.ZERO,
		"blocked": true,
		"skip_movement_check": true,
		"start": STAIR_ORIGIN + Vector3(-0.67397, 3.413661, 4.220969),
		"yaw": deg_to_rad(89.06),
		"initial_velocity": Vector3(0.0, -0.226668, 0.0),
		"move_frames": 180,
		"recovery_frames": 60,
		"check_feet": true,
	},
]
var _case_index := 0
var _frame_in_case := 0
var _start_position := Vector3.ZERO
var _blocked_end_position := Vector3.ZERO
var _failures: Array[String] = []
var _results: Array[String] = []


func _ready() -> void:
	_build_platform()
	_build_stair_landing()
	var player_scene: PackedScene = load("res://actors/player/player.tscn")
	_player = player_scene.instantiate() as Player
	add_child(_player)
	STAIR_SURFACES.configure_player(_player)
	for child in _player.skeleton.get_children():
		if child is PlayerFootIKModifier:
			_ik = child
			break
	_reset_case()


func _build_platform() -> void:
	var static_body := StaticBody3D.new()
	var collision := CollisionShape3D.new()
	var box_shape := BoxShape3D.new()
	box_shape.size = PLATFORM_SIZE
	collision.shape = box_shape
	static_body.add_child(collision)
	static_body.position = Vector3(0.0, PLATFORM_HEIGHT * 0.5, 0.0)
	add_child(static_body)


func _build_stair_landing() -> void:
	for step in STAIR_COUNT:
		var rise := STAIR_HEIGHT * (step + 1)
		var box := CSGBox3D.new()
		box.size = Vector3(STAIR_WIDTH, rise, STAIR_TREAD_DEPTH)
		box.use_collision = true
		STAIR_SURFACES.configure_authored_stair(box)
		box.position = STAIR_ORIGIN + Vector3(
				0.0, rise * 0.5, (step + 0.5) * STAIR_TREAD_DEPTH)
		add_child(box)
	STAIR_SURFACES.build_traversal_ramp(self, STAIR_ORIGIN, STAIR_WIDTH, 0.3,
			STAIR_TREAD_DEPTH, STAIR_COUNT, STAIR_HEIGHT)
	STAIR_SURFACES.build_top_landing(self, STAIR_ORIGIN, STAIR_WIDTH,
			STAIR_TREAD_DEPTH, STAIR_COUNT, STAIR_HEIGHT)


func _physics_process(_delta: float) -> void:
	if _case_index >= _cases.size():
		return
	_frame_in_case += 1
	if _frame_in_case == SETTLE_FRAMES:
		_start_position = _player.global_position
		_player.velocity = Vector3.ZERO
		_player.ledge_safety_enabled = true
		_player.movement_input_override = _cases[_case_index]["input"]
	var data: Dictionary = _cases[_case_index]
	var move_frames: int = data.get("move_frames", MOVE_FRAMES)
	var recovery_frames: int = data.get("recovery_frames", 0)
	_update_turn_case(data)
	if recovery_frames > 0 and _frame_in_case == SETTLE_FRAMES + move_frames:
		_blocked_end_position = _player.global_position
		_player.movement_input_override = Vector2.ZERO
	elif _frame_in_case >= SETTLE_FRAMES + move_frames + recovery_frames:
		if recovery_frames == 0:
			_blocked_end_position = _player.global_position
		_evaluate_case()
		_case_index += 1
		if _case_index < _cases.size():
			_reset_case()
		else:
			_finish_check()


func _update_turn_case(data: Dictionary) -> void:
	if not data.get("check_zones_during_turn", false):
		return
	var turn_tick := _frame_in_case - SETTLE_FRAMES - int(data["turn_hold_frames"])
	var turn_steps := int(data["turn_steps"])
	if turn_tick < 1 or turn_tick > turn_steps * 2:
		return
	if turn_tick % 2 == 1:
		var step := (turn_tick + 1) / 2
		_player.rotation.y = lerp_angle(float(data["yaw"]), float(data["turn_yaw"]),
				float(step) / float(turn_steps))
		_player._look_yaw = 0.0
		_player.head.rotation.y = 0.0
		_player.third_person_arm.rotation.y = 0.0
	else:
		_sample_safe_zones(String(data["name"]), turn_tick)


func _sample_safe_zones(case_name: String, turn_tick: int) -> void:
	var left_hip := _final_bone_world(&"left", &"hip")
	var right_hip := _final_bone_world(&"right", &"hip")
	var left_dir := left_hip - right_hip
	left_dir.y = 0.0
	if left_dir.length_squared() <= 0.0001:
		return
	left_dir = left_dir.normalized()
	var forward_dir := Vector3.UP.cross(left_dir).normalized()
	for side: StringName in [&"left", &"right"]:
		var foot := _final_bone_world(side, &"foot")
		var from_root := foot - _player.global_position
		var side_sign := 1.0 if side == &"left" else -1.0
		var lateral := from_root.dot(left_dir) * side_sign
		var longitudinal := from_root.dot(forward_dir)
		if (lateral < ZONE_MIN_LATERAL or lateral > ZONE_MAX_LATERAL
				or absf(longitudinal) > ZONE_MAX_LONGITUDINAL):
			_failures.append(("%s turn_tick=%d side=%s safe zone " + \
					"lateral=%.3f longitudinal=%.3f") % [
					case_name, turn_tick, side, lateral, longitudinal])


func _final_bone_world(side: StringName, joint: StringName) -> Vector3:
	var bone_idx: int = _ik._bone_indices[side][joint]
	var pose: Transform3D = _ik._final_bone_poses.get(
			bone_idx, _player.skeleton.get_bone_global_pose(bone_idx))
	return _player.skeleton.global_transform * pose.origin


func _reset_case() -> void:
	_player.ledge_safety_enabled = false
	_player.movement_input_override = Vector2.ZERO
	var data: Dictionary = _cases[_case_index]
	_player.global_position = data.get("start", START_POSITION)
	_player.rotation = Vector3(0.0, data.get("yaw", 0.0), 0.0)
	_player._look_yaw = 0.0
	_player.head.rotation.y = 0.0
	_player.third_person_arm.rotation.y = 0.0
	_player.velocity = data.get("initial_velocity", Vector3.ZERO)
	_blocked_end_position = _player.global_position
	if _ik != null:
		_ik.reset_runtime_state()
	_frame_in_case = 0


func _evaluate_case() -> void:
	var data: Dictionary = _cases[_case_index]
	var displacement := Vector2(
			_blocked_end_position.x - _start_position.x,
			_blocked_end_position.z - _start_position.z).length()
	var recovery := Vector2(_player.global_position.x - _blocked_end_position.x,
			_player.global_position.z - _blocked_end_position.z).length()
	var left_weight := float(_ik._smoothed_ground_weight.get(&"left", 0.0))
	var right_weight := float(_ik._smoothed_ground_weight.get(&"right", 0.0))
	var contacts := "%s/%s" % [_ik.debug_contact_hit.get(&"left", false),
			_ik.debug_contact_hit.get(&"right", false)]
	_results.append(("%s start=%s blocked_end=%s end=%s moved=%.3f recovery=%.3f " + \
			"floor=%s normal=%s contacts=%s weights=%.2f/%.2f retracted=%s targets=%s/%s") % [
			data["name"], _start_position,
			_blocked_end_position, _player.global_position, displacement, recovery,
			str(_player.is_on_floor()), str(_player.get_floor_normal()), contacts, left_weight, right_weight,
			str(_ik.debug_retracted), str(_ik._smoothed_target.get(&"left", Vector3.ZERO)),
			str(_ik._smoothed_target.get(&"right", Vector3.ZERO))])
	if data.get("skip_movement_check", false):
		pass
	elif bool(data["blocked"]):
		var blocked_limit: float = data.get("blocked_limit", BLOCKED_DISTANCE_LIMIT)
		if displacement > blocked_limit:
			_failures.append("%s moved %.3fm (limit %.3fm)" % [
					data["name"], displacement, blocked_limit])
	elif displacement < PARALLEL_DISTANCE_MIN:
		_failures.append("%s moved only %.3fm (minimum %.3fm)" % [
				data["name"], displacement, PARALLEL_DISTANCE_MIN])
	if data.get("check_feet", false):
		if (_player.global_position.x < _blocked_end_position.x - 0.005
				or _player.global_position.z > _blocked_end_position.z + 0.005):
			_failures.append("%s recovery moved toward an unsupported landing edge" % data["name"])
		var left_hit := bool(_ik.debug_contact_hit.get(&"left", false))
		var right_hit := bool(_ik.debug_contact_hit.get(&"right", false))
		if not left_hit or not right_hit or left_weight < 0.99 or right_weight < 0.99:
			_failures.append("%s final feet contacts=%s weights=%.2f/%.2f" % [
					data["name"], contacts, left_weight, right_weight])


func _finish_check() -> void:
	_player.movement_input_override = Vector2.ZERO
	print("FOOT_IK_LEDGE_SAFETY_CASES %s" % "; ".join(_results))
	if not _failures.is_empty():
		print("FOOT_IK_LEDGE_SAFETY_CHECK FAIL failures=%d details=%s" % [
				_failures.size(), "; ".join(_failures)])
		get_tree().quit(1)
		return
	print("FOOT_IK_LEDGE_SAFETY_CHECK PASS cases=%d" % _cases.size())
	get_tree().quit(0)
