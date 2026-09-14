extends Node3D
## 025's exact recurring clip is startup idle, not walking. Do not skip the first 120 frames.
const MONITOR := preload("res://tools/foot_ik/foot_ik_live_penetration_monitor.gd")
const PRECISE := preload("res://tests/manual/foot_ik/foot_ik_live_penetration_check.gd")
const MAX_DEPTH_M := 0.005
var _player: Player
var _ik: PlayerFootIKModifier
var _frame := 0
var _samples := 0
var _max_depth := 0.0
var _mesh_depth := 0.0
var _mesh_samples := 0
var _precise := PRECISE.new()
var _bone_filter: Dictionary = {}
var _boxes: Array[CollisionShape3D] = []


func _ready() -> void:
	_player = $FootIkPreview/Player
	_player.global_position = Vector3(15.52282, 1.422718, 1.734463)
	_player.rotation.y = deg_to_rad(100.977250312091)
	_ik = _player.body._foot_ik_modifier
	_player.movement_input_override = Vector2.ZERO
	for side: StringName in [&"left", &"right"]:
		for joint: String in ["foot", "toe", "leaf"]:
			var index: int = _ik._bone_indices[side].get(joint, -1)
			if index >= 0:
				_bone_filter[_player.skeleton.get_bone_name(index)] = true


func _physics_process(_delta: float) -> void:
	_frame += 1
	# First frame precedes the rendered modifier output; subsequent frames include startup.
	if _frame < 3:
		return
	_samples += 1
	if _boxes.is_empty():
		_find_boxes()
	for side: StringName in [&"left", &"right"]:
		var indices: Dictionary = _ik._bone_indices[side]
		var ankle := _world_position(indices["foot"])
		var toe := _world_position(indices["toe"])
		var tip := toe + (toe - ankle).normalized() * 0.035
		var result := MONITOR.check(get_world_3d().direct_space_state,
				PackedVector3Array([ankle, tip]), FootIKGroundSampler.GROUND_COLLISION_MASK)
		_max_depth = maxf(_max_depth, result["depth_m"])
	# Expensive mesh oracle is confined to this headless fixture, never a persistent marker.
	if _frame <= 40:
		for box in _boxes:
			var result := _precise.sample_box_transform(_player, _ik, _bone_filter,
					box.global_transform, (box.shape as BoxShape3D).size)
			if result.get("available", false):
				_mesh_samples += 1
				_mesh_depth = maxf(_mesh_depth, result["max_depth"])
	if _frame < 120:
		return
	var held := _ik._smoothed_shared_drop
	var zero_delta_ok := (_ik._shape_shared_drop(held + 0.2, 0.0, true) == held
			and _ik._shape_shared_drop(held + 0.2, 0.0, false) == held)
	var passed := (_samples == 118 and _mesh_samples > 0 and zero_delta_ok
			and _max_depth <= MAX_DEPTH_M and _mesh_depth <= MAX_DEPTH_M)
	print("FOOT_IK_SPAWN_CONTACT_CHECK %s samples=%d depth_m=%.6f mesh_depth_m=%.6f "
			% ["PASS" if passed else "FAIL", _samples, _max_depth, _mesh_depth]
			+ "mesh_samples=%d zero_delta_ok=%s" % [_mesh_samples, zero_delta_ok])
	get_tree().quit(0 if passed else 1)


func _world_position(index: int) -> Vector3:
	return _player.skeleton.global_transform * _ik.get_final_bone_global_pose(index).origin


func _find_boxes() -> void:
	var sphere := SphereShape3D.new()
	sphere.radius = 1.0
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = sphere
	query.transform.origin = _player.global_position
	query.collision_mask = FootIKGroundSampler.GROUND_COLLISION_MASK
	query.collide_with_areas = false
	for hit in get_world_3d().direct_space_state.intersect_shape(query, 32):
		var body: Object = hit.get("collider")
		if not body is StaticBody3D:
			continue
		for child in (body as StaticBody3D).get_children():
			if child is CollisionShape3D and child.shape is BoxShape3D and child not in _boxes:
				_boxes.append(child)
