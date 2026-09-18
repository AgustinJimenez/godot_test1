class_name ProceduralWalkStairSourceReport
extends RefCounted
## Measures whether imported stair poses fit the lab's actual tread layout.


func run(lab: Node3D, character: Node3D, skeleton: Skeleton3D,
		modifier: ProceduralWalkLabModifier, source_character: Node3D,
		source_skeleton: Skeleton3D) -> void:
	await lab.get_tree().physics_frame
	var source_check := ProceduralWalkMeshClearance.new()
	source_check.prepare(source_character, source_skeleton)
	var output_check := ProceduralWalkMeshClearance.new()
	output_check.prepare(character, skeleton)
	for mode_index in [4, 5]:
		lab.call("_select_reference_mode", mode_index + 1)
		var source_min := INF
		var source_max := -INF
		var output_min := INF
		var output_max := -INF
		var source_contact := 0
		var output_contact := 0
		var active := 0
		var worst_frame := -1
		var worst_root_z := 0.0
		var worst_foot := Vector3.ZERO
		for frame in 240:
			await lab.get_tree().physics_frame
			if character.global_position.z > 1.1 or character.global_position.z < -0.5:
				continue
			active += 1
			var source_poses: Array[Transform3D] = []
			for bone in source_skeleton.get_bone_count():
				source_poses.append(source_skeleton.get_bone_global_pose(bone))
			var source_feet := source_check.sample(source_skeleton, source_poses,
					modifier.stair_support_height)
			var output_feet := output_check.sample(skeleton, modifier.debug_bone_poses,
					modifier.stair_support_height)
			var source_low := minf(source_feet[0], source_feet[1])
			var output_low := minf(output_feet[0], output_feet[1])
			if source_low < source_min:
				source_min = source_low
				worst_frame = frame
				worst_root_z = character.global_position.z
				worst_foot = source_check.last_low_positions[
						0 if source_feet[0] < source_feet[1] else 1]
			source_max = maxf(source_max, source_low)
			output_min = minf(output_min, output_low)
			output_max = maxf(output_max, output_low)
			if source_low >= -0.01 and source_low <= 0.03:
				source_contact += 1
			if output_low >= -0.01 and output_low <= 0.03:
				output_contact += 1
		print(("STAIR_SOURCE %s frames=%d source_min=%.3fm@f%d "
				+ "root_z=%.2f foot=(%.2f,%.2f,%.2f) source_max=%.3fm "
				+ "source_contact=%d output_min=%.3fm output_max=%.3fm output_contact=%d") % [
				"up" if mode_index == 4 else "down", active, source_min, worst_frame,
				worst_root_z, worst_foot.x, worst_foot.y, worst_foot.z,
				source_max, source_contact, output_min, output_max, output_contact])
