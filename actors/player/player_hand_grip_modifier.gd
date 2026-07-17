class_name PlayerHandGripModifier
extends SkeletonModifier3D
## Applies temporary bone-local rotation offsets after animation evaluation.

var bone_rotations_degrees: Dictionary = {}


func set_bone_rotation(bone_name: StringName, rotation_degrees: Vector3) -> void:
	bone_rotations_degrees[bone_name] = rotation_degrees


func get_bone_rotation(bone_name: StringName) -> Vector3:
	return bone_rotations_degrees.get(bone_name, Vector3.ZERO)


func reset_bone(bone_name: StringName) -> void:
	bone_rotations_degrees.erase(bone_name)


func reset_all() -> void:
	bone_rotations_degrees.clear()


func _process_modification_with_delta(_delta: float) -> void:
	var skel := get_skeleton()
	if skel == null:
		return
	for bone_name: StringName in bone_rotations_degrees:
		var bone_index := skel.find_bone(bone_name)
		if bone_index < 0:
			continue
		var rotation_degrees: Vector3 = bone_rotations_degrees[bone_name]
		if rotation_degrees.is_zero_approx():
			continue
		var pose := skel.get_bone_global_pose(bone_index)
		pose.basis *= Basis.from_euler(Vector3(
				deg_to_rad(rotation_degrees.x),
				deg_to_rad(rotation_degrees.y),
				deg_to_rad(rotation_degrees.z)))
		skel.set_bone_global_pose(bone_index, pose)


func get_serializable_values() -> Dictionary:
	var values := {}
	for bone_name: StringName in bone_rotations_degrees:
		var rotation: Vector3 = bone_rotations_degrees[bone_name]
		if not rotation.is_zero_approx():
			values[String(bone_name)] = [rotation.x, rotation.y, rotation.z]
	return values
