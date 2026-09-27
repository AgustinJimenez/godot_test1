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
	for mode_index in [4]:
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
		var output_worst_frame := -1
		var output_worst_root_z := 0.0
		var output_worst_foot := Vector3.ZERO
		var output_worst_side := -1
		var output_worst_planted := false
		var output_worst_plant := Vector3.ZERO
		var output_worst_ankle := Vector3.ZERO
		var output_worst_phase := 0.0
		var planted_min := INF
		var swing_min := INF
		var planted_worst := ""
		var swing_worst := ""
		for frame in 480:
			await lab.get_tree().physics_frame
			if character.global_position.z > 1.1 or character.global_position.z < -3.2:
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
			for side in 2:
				if modifier.has_plant(side):
					if output_feet[side] < planted_min:
						planted_min = output_feet[side]
						planted_worst = "f%d side%d foot=%s plant=%s" % [frame, side,
								str(output_check.last_low_positions[side]),
								str(modifier.plant_world(side))]
				else:
					if output_feet[side] < swing_min:
						swing_min = output_feet[side]
						swing_worst = "f%d side%d foot=%s" % [frame, side,
								str(output_check.last_low_positions[side])]
			if source_low < source_min:
				source_min = source_low
				worst_frame = frame
				worst_root_z = character.global_position.z
				worst_foot = source_check.last_low_positions[
						0 if source_feet[0] < source_feet[1] else 1]
			source_max = maxf(source_max, source_low)
			if output_low < output_min:
				output_min = output_low
				output_worst_frame = frame
				output_worst_root_z = character.global_position.z
				output_worst_side = 0 if output_feet[0] < output_feet[1] else 1
				output_worst_foot = output_check.last_low_positions[output_worst_side]
				output_worst_planted = modifier.has_plant(output_worst_side)
				output_worst_plant = modifier.plant_world(output_worst_side)
				output_worst_ankle = modifier.debug_joint_positions[
						&"LeftFoot" if output_worst_side == 0 else &"RightFoot"]
				output_worst_phase = fposmod(modifier.phase / TAU, 1.0)
			output_max = maxf(output_max, output_low)
			if source_low >= -0.01 and source_low <= 0.03:
				source_contact += 1
			if output_low >= -0.01 and output_low <= 0.03:
				output_contact += 1
		print(("STAIR_SOURCE %s frames=%d source_min=%.3fm@f%d "
				+ "root_z=%.2f foot=(%.2f,%.2f,%.2f) source_max=%.3fm "
				+ "source_contact=%d output_min=%.3fm@f%d root_z=%.2f "
				+ "foot=(%.2f,%.2f,%.2f) side=%d planted=%s plant=%s ankle=%s "
				+ "phase=%.2f planted_min=%.3f swing_min=%.3f "
				+ "output_max=%.3fm output_contact=%d") % [
				"up" if mode_index == 4 else "down", active, source_min, worst_frame,
				worst_root_z, worst_foot.x, worst_foot.y, worst_foot.z,
				source_max, source_contact, output_min, output_worst_frame,
				output_worst_root_z, output_worst_foot.x, output_worst_foot.y,
				output_worst_foot.z, output_worst_side, str(output_worst_planted),
				str(output_worst_plant), str(output_worst_ankle),
				output_worst_phase, planted_min, swing_min,
				output_max, output_contact])
		print("STAIR_OUTPUT_DETAIL plant=%s swing=%s" % [planted_worst, swing_worst])
