extends RefCounted
## Adapter around Godot 4.6's native TwoBoneIK3D. Contact sampling, gait,
## stair prediction, and target construction remain owned by
## PlayerFootIKModifier so Custom/Native comparisons use identical inputs.

var _owner
var _modifier: TwoBoneIK3D
var _targets: Dictionary = {} # side -> Node3D
var _poles: Dictionary = {} # side -> Node3D
var _setting_by_side: Dictionary = {}


func _init(owner) -> void:
	_owner = owner


func setup(skeleton: Skeleton3D, bone_indices: Dictionary) -> void:
	if is_instance_valid(_modifier):
		return
	_modifier = TwoBoneIK3D.new()
	_modifier.name = &"NativeFootTwoBoneIK"
	_modifier.active = false
	_modifier.setting_count = bone_indices.size()
	_modifier.mutable_bone_axes = true
	skeleton.add_child(_modifier)
	var setting := 0
	for side: StringName in bone_indices:
		var indices: Dictionary = bone_indices[side]
		var target := _make_target_node("NativeFootTarget_" + String(side))
		var pole := _make_target_node("NativeKneePole_" + String(side))
		_targets[side] = target
		_poles[side] = pole
		_setting_by_side[side] = setting
		_modifier.set_root_bone(setting, int(indices["hip"]))
		_modifier.set_middle_bone(setting, int(indices["knee"]))
		_modifier.set_end_bone(setting, int(indices["foot"]))
		_modifier.set_target_node(setting, _modifier.get_path_to(target))
		_modifier.set_pole_direction(
				setting, SkeletonModifier3D.SECONDARY_DIRECTION_CUSTOM)
		_modifier.set_pole_node(setting, _modifier.get_path_to(pole))
		_modifier.set_use_virtual_end(setting, false)
		_modifier.set_extend_end_bone(setting, false)
		setting += 1


func set_enabled(enabled: bool) -> void:
	if is_instance_valid(_modifier):
		_modifier.active = enabled


var _smoothed_bases: Dictionary = {}


func update_targets(skeleton: Skeleton3D, per_leg: Dictionary) -> void:
	if not is_instance_valid(_modifier):
		return
	var to_world := skeleton.global_transform
	for side: StringName in _setting_by_side:
		var indices: Dictionary = _owner._bone_indices[side]
		var foot_pose := skeleton.get_bone_global_pose(int(indices["foot"]))
		var animated_position: Vector3 = to_world * foot_pose.origin
		var animated_basis := to_world.basis * foot_pose.basis
		var leg: Dictionary = per_leg.get(side, {})
		var preserve_idle: bool = leg.get("preserve_idle_pose", false)
		if preserve_idle:
			(_targets[side] as Node3D).global_transform = Transform3D(
					animated_basis.orthonormalized(), animated_position)
			_smoothed_bases[side] = animated_basis
			var hip_position: Vector3 = to_world * skeleton.get_bone_global_pose(
					int(indices["hip"])).origin
			var pole_direction: Vector3 = (
					to_world.basis * (_owner._knee_pole_local[side] as Vector3)).normalized()
			(_poles[side] as Node3D).global_position = hip_position + pole_direction
			continue
		var target_position: Vector3 = leg.get("target", animated_position)
		var first_leg: Dictionary = _owner._bone_indices.values()[0]
		var pelvis_idx := skeleton.get_bone_parent(int(first_leg["hip"]))
		var pelvis_world: Vector3 = (to_world * skeleton.get_bone_global_pose(pelvis_idx).origin
				if pelvis_idx >= 0 else to_world.origin)
		var rel_to_pelvis := to_world.basis.inverse() * (target_position - pelvis_world)
		if target_position.distance_squared_to(animated_position) > 0.0001:
			if side == &"left" and rel_to_pelvis.x < 0.01:
				rel_to_pelvis.x = 0.01
				target_position = pelvis_world + to_world.basis * rel_to_pelvis
			elif side == &"right" and rel_to_pelvis.x > -0.01:
				rel_to_pelvis.x = -0.01
				target_position = pelvis_world + to_world.basis * rel_to_pelvis
		var weight: float = leg.get("ground_weight", 0.0)
		var target_basis := animated_basis
		if leg.get("hit", false):
			var raw_norm: Vector3 = leg.get("raw_normal", Vector3.UP)
			if raw_norm.dot(Vector3.UP) < 0.999:
				var ground_basis: Basis = _owner._compute_new_foot_basis_world(
						skeleton, side, -raw_norm, foot_pose)
				target_basis = Basis(animated_basis.get_rotation_quaternion().slerp(
						ground_basis.get_rotation_quaternion(), weight))
		if _smoothed_bases.has(side):
			var prev_b: Basis = _smoothed_bases[side]
			target_basis = Basis(prev_b.get_rotation_quaternion().slerp(
					target_basis.get_rotation_quaternion(), 0.35))
		(_targets[side] as Node3D).global_transform = Transform3D(
				target_basis.orthonormalized(), target_position)
		var hip_pose := skeleton.get_bone_global_pose(int(indices["hip"]))
		var knee_pose := skeleton.get_bone_global_pose(int(indices["knee"]))
		var hip_pos: Vector3 = to_world * hip_pose.origin
		var knee_pos: Vector3 = to_world * knee_pose.origin
		var hip_to_tgt := (target_position - hip_pos).normalized()
		var hip_to_knee := knee_pos - hip_pos
		var bend_vec := hip_to_knee - hip_to_tgt * hip_to_knee.dot(hip_to_tgt)
		var pole_dir: Vector3 = (to_world.basis * (_owner._knee_pole_local[side] as Vector3)).normalized()
		var pole_pos := hip_pos + pole_dir
		if bend_vec.length_squared() > 0.0001:
			pole_pos = knee_pos + bend_vec.normalized() * 0.5
		var rel_pole := to_world.basis.inverse() * (pole_pos - pelvis_world)
		if side == &"left" and rel_pole.x > -0.05:
			rel_pole.x = -0.05
			pole_pos = pelvis_world + to_world.basis * rel_pole
		elif side == &"right" and rel_pole.x < 0.05:
			rel_pole.x = 0.05
			pole_pos = pelvis_world + to_world.basis * rel_pole
		(_poles[side] as Node3D).global_position = pole_pos


func _make_target_node(node_name: String) -> Node3D:
	var node := Node3D.new()
	node.name = node_name
	node.top_level = true
	_owner.add_child(node)
	return node
