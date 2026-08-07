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
		var target_position: Vector3 = leg.get("target", animated_position)
		var weight: float = leg.get("ground_weight", 0.0)
		var target_basis := animated_basis
		if leg.get("hit", false):
			var ground_basis: Basis = _owner._compute_new_foot_basis_world(
					skeleton, side, -(leg.get("raw_normal", Vector3.UP) as Vector3), foot_pose)
			target_basis = Basis(animated_basis.get_rotation_quaternion().slerp(
					ground_basis.get_rotation_quaternion(), weight))
		(_targets[side] as Node3D).global_transform = Transform3D(
				target_basis.orthonormalized(), target_position)
		var hip_position: Vector3 = to_world * skeleton.get_bone_global_pose(
				int(indices["hip"])).origin
		var pole_direction: Vector3 = (
				to_world.basis * (_owner._knee_pole_local[side] as Vector3)).normalized()
		(_poles[side] as Node3D).global_position = hip_position + pole_direction


func _make_target_node(node_name: String) -> Node3D:
	var node := Node3D.new()
	node.name = node_name
	node.top_level = true
	_owner.add_child(node)
	return node
