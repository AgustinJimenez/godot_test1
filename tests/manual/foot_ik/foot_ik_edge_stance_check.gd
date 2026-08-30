class_name FootIkEdgeStanceCheck
extends Node3D
const JOINT_LIMIT_CHECK := preload("res://tests/manual/foot_ik/foot_ik_joint_limit_check.gd")
## Regression check that tests 100 randomized positions and rotations along
## the perimeter edges and corners of a tall platform to verify that the feet
## never cross the body centerline under any placement or orientation.

const PLATFORM_HEIGHT := 3.0
const PLATFORM_SIZE := Vector3(4.0, PLATFORM_HEIGHT, 4.0)
const FRAMES_PER_CASE := 60
const TOTAL_CASES := 100
const MIN_STANCE_WIDTH := 0.18
const MIN_SIDE_CLEARANCE := 0.04

var _player: Player
var _skel: Skeleton3D
var _ik: PlayerFootIKModifier
var _current_case := 0
var _frame_in_case := 0
var _cases: Array[Dictionary] = []
var _failures: Array[String] = []
var _worst_left_clearance := 999.0
var _worst_right_clearance := 999.0
var _min_stance_width := 999.0


func _ready() -> void:
	_build_platform()
	_generate_random_edge_cases()
	_setup_player()


func _build_platform() -> void:
	var static_body := StaticBody3D.new()
	var collision := CollisionShape3D.new()
	var box_shape := BoxShape3D.new()
	box_shape.size = PLATFORM_SIZE
	collision.shape = box_shape
	static_body.add_child(collision)
	static_body.position = Vector3(0.0, PLATFORM_HEIGHT * 0.5, 0.0)
	add_child(static_body)

	var mesh_inst := MeshInstance3D.new()
	var box_mesh := BoxMesh.new()
	box_mesh.size = PLATFORM_SIZE
	mesh_inst.mesh = box_mesh
	mesh_inst.position = static_body.position
	add_child(mesh_inst)


func _generate_random_edge_cases() -> void:
	var surface_y := PLATFORM_HEIGHT
	var rng := RandomNumberGenerator.new()
	rng.seed = 42 # Deterministic pseudo-random sequence

	_cases.clear()
	for i in TOTAL_CASES:
		var edge_type := i % 5
		var pos := Vector3.ZERO
		match edge_type:
			0: # North edge
				pos = Vector3(rng.randf_range(-1.95, 1.95), surface_y, rng.randf_range(-1.98, -1.90))
			1: # South edge
				pos = Vector3(rng.randf_range(-1.95, 1.95), surface_y, rng.randf_range(1.90, 1.98))
			2: # East edge
				pos = Vector3(rng.randf_range(1.90, 1.98), surface_y, rng.randf_range(-1.95, 1.95))
			3: # West edge
				pos = Vector3(rng.randf_range(-1.98, -1.90), surface_y, rng.randf_range(-1.95, 1.95))
			4: # Corners
				var sx := 1.0 if rng.randf() > 0.5 else -1.0
				var sz := 1.0 if rng.randf() > 0.5 else -1.0
				pos = Vector3(sx * rng.randf_range(1.88, 1.96), surface_y, sz * rng.randf_range(1.88, 1.96))

		var rot_y := rng.randf_range(0.0, 360.0)
		_cases.append({
			"name": "case_%03d" % i,
			"pos": pos,
			"rot_y": rot_y,
		})


func _setup_player() -> void:
	var player_scene: PackedScene = load("res://actors/player/player.tscn")
	_player = player_scene.instantiate() as Player
	_player.ledge_safety_enabled = false
	add_child(_player)
	_skel = _player.body.skeleton
	for child in _skel.get_children():
		if child is PlayerFootIKModifier:
			_ik = child
			break
	_apply_case(_current_case)


func _apply_case(case_idx: int) -> void:
	if case_idx >= _cases.size():
		return
	var c: Dictionary = _cases[case_idx]
	_player.global_position = c["pos"]
	_player.rotation = Vector3(0.0, deg_to_rad(c["rot_y"]), 0.0)
	_player.velocity = Vector3.ZERO
	_player.movement_input_override = Vector2.ZERO
	_ik.reset_runtime_state()
	_frame_in_case = 0


func _physics_process(_delta: float) -> void:
	if _current_case >= _cases.size():
		return
	_frame_in_case += 1
	if _frame_in_case >= FRAMES_PER_CASE:
		_evaluate_case(_current_case)
		_current_case += 1
		if _current_case < _cases.size():
			_apply_case(_current_case)
		else:
			_finish_check()


func _evaluate_case(case_idx: int) -> void:
	var c: Dictionary = _cases[case_idx]
	var case_name: String = c["name"]
	_failures.append_array(JOINT_LIMIT_CHECK.failures(_ik, _skel, case_name))
	var left_hip_idx: int = _ik._bone_indices[&"left"]["hip"]
	var right_hip_idx: int = _ik._bone_indices[&"right"]["hip"]
	var left_foot_idx: int = _ik._bone_indices[&"left"]["foot"]
	var right_foot_idx: int = _ik._bone_indices[&"right"]["foot"]

	# SkeletonModifier3D restores the base animation pose after its update. Read
	# the modifier's cached final pose so this check measures the same solved
	# feet that the live overlay, trace, and rendered skin use.
	var hip_l_w: Vector3 = _skel.global_transform * _final_pose(left_hip_idx).origin
	var hip_r_w: Vector3 = _skel.global_transform * _final_pose(right_hip_idx).origin
	var foot_l_w: Vector3 = _skel.global_transform * _final_pose(left_foot_idx).origin
	var foot_r_w: Vector3 = _skel.global_transform * _final_pose(right_foot_idx).origin

	var root_pos := _player.global_position
	var hip_axis := hip_l_w - hip_r_w
	hip_axis.y = 0.0
	var hip_lat_dir := hip_axis.normalized() if hip_axis.length_squared() > 0.0001 else Vector3.RIGHT

	var left_offset := (foot_l_w - root_pos).dot(hip_lat_dir)
	var right_offset := (foot_r_w - root_pos).dot(hip_lat_dir)
	var stance_width := (foot_l_w - foot_r_w).dot(hip_lat_dir)
	var left_target: Vector3 = _ik._solved_target_smoothed.get(&"left", foot_l_w)
	var right_target: Vector3 = _ik._solved_target_smoothed.get(&"right", foot_r_w)
	var left_target_offset := (left_target - root_pos).dot(hip_lat_dir)
	var right_target_offset := (right_target - root_pos).dot(hip_lat_dir)

	_worst_left_clearance = minf(_worst_left_clearance, left_offset)
	_worst_right_clearance = minf(_worst_right_clearance, -right_offset)
	_min_stance_width = minf(_min_stance_width, stance_width)

	if left_offset < MIN_SIDE_CLEARANCE:
		_failures.append("%s: left foot crossed line (offset=%.3f, target=%.3f, min=%.3f)" % [
				case_name, left_offset, left_target_offset, MIN_SIDE_CLEARANCE])
	if right_offset > -MIN_SIDE_CLEARANCE:
		_failures.append("%s: right foot crossed line (offset=%.3f, target=%.3f, max=%.3f)" % [
				case_name, right_offset, right_target_offset, -MIN_SIDE_CLEARANCE])
	if stance_width < MIN_STANCE_WIDTH:
		_failures.append("%s: stance width too narrow (width=%.3f, min=%.3f)" % [
				case_name, stance_width, MIN_STANCE_WIDTH])


func _final_pose(bone_idx: int) -> Transform3D:
	return _ik._final_bone_poses.get(bone_idx, _skel.get_bone_global_pose(bone_idx))


func _finish_check() -> void:
	if not _failures.is_empty():
		print("FOOT_IK_EDGE_STANCE_CHECK FAIL failures=%d details=%s" % [
				_failures.size(), "; ".join(_failures.slice(0, 5))])
		get_tree().quit(1)
	else:
		var summary := "FOOT_IK_EDGE_STANCE_CHECK PASS cases=%d min_stance_width=%.3f " + \
				"worst_left_clearance=%.3f worst_right_clearance=%.3f"
		print(summary % [
				_cases.size(), _min_stance_width, _worst_left_clearance, _worst_right_clearance])
		get_tree().quit(0)
