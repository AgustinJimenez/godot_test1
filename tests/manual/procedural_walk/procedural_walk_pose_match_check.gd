class_name ProceduralWalkPoseMatchCheck
extends RefCounted
## Exhaustive per-frame comparison for the lab's flat source-derived modes.

const MODES := [&"walk", &"walk_aim", &"sprint", &"crouch"]
const CYCLE_FRAMES := 120


func run(lab: Node3D, skeleton: Skeleton3D, modifier: ProceduralWalkLabModifier,
		reference: Skeleton3D) -> bool:
	await lab.get_tree().physics_frame
	var passed_all := true
	for mode: StringName in MODES:
		var index := ProceduralWalkReferenceBank.MODE_ORDER.find(mode) + 1
		lab.call("_select_reference_mode", index)
		for moving in [false, true]:
			lab.call("_set_moving_mode", moving)
			lab.set("_playing", moving)
			var max_rotation := 0.0
			var max_relative_position := 0.0
			var max_clearance_step := 0.0
			var max_upper_rotation := 0.0
			var max_upper_position := 0.0
			var max_contact_error := 0.0
			var worst_contact_frame := -1
			var worst_contact_side := ""
			var worst_contact_root_z := 0.0
			var worst_contact_target_z := 0.0
			var worst_contact_target_y := 0.0
			var max_leg_step := 0.0
			var worst_step_frame := -1
			var worst_step_name := &""
			var max_source_leg_step := 0.0
			var full_contact_frames := 0
			var source_airborne_weighted := 0
			var source_airborne_frames := 0
			var previous_clearance := NAN
			var previous_poses: Array[Transform3D] = []
			var previous_source_poses: Array[Transform3D] = []
			var worst_name := &""
			var worst_frame := -1
			for frame in CYCLE_FRAMES:
				if not moving:
					lab.call("_set_frame", float(frame))
				await lab.get_tree().physics_frame
				var poses := modifier.debug_bone_poses
				var hips := skeleton.find_bone(&"Hips")
				var technical_root := skeleton.find_bone(&"Root")
				var procedural_hips: Vector3 = poses[hips].origin
				var source_hips := reference.get_bone_global_pose(hips).origin
				var source_poses: Array[Transform3D] = []
				var clearance := modifier.reference_bank.floor_clearance(
						mode, modifier.phase)
				if not is_nan(previous_clearance):
					max_clearance_step = maxf(max_clearance_step,
							absf(clearance - previous_clearance))
				previous_clearance = clearance
				for bone in skeleton.get_bone_count():
					var bone_name := String(skeleton.get_bone_name(bone))
					var source := reference.get_bone_global_pose(bone)
					source_poses.append(source)
					var rotation := rad_to_deg(poses[bone].basis.get_rotation_quaternion()
							.angle_to(source.basis.get_rotation_quaternion()))
					var relative_position := ((poses[bone].origin - procedural_hips)
							- (source.origin - source_hips)).length()
					if rotation > max_rotation:
						max_rotation = rotation
						worst_name = skeleton.get_bone_name(bone)
						worst_frame = frame
					if bone != technical_root:
						max_relative_position = maxf(max_relative_position,
								relative_position)
					if not _is_leg_bone(bone_name):
						max_upper_rotation = maxf(max_upper_rotation, rotation)
						if bone != technical_root:
							max_upper_position = maxf(max_upper_position, relative_position)
					elif not previous_poses.is_empty():
						var leg_step := rad_to_deg(
								poses[bone].basis.get_rotation_quaternion().angle_to(
								previous_poses[bone].basis.get_rotation_quaternion()))
						if leg_step > max_leg_step:
							max_leg_step = leg_step
							worst_step_frame = frame
							worst_step_name = skeleton.get_bone_name(bone)
						max_source_leg_step = maxf(max_source_leg_step, rad_to_deg(
								source.basis.get_rotation_quaternion().angle_to(
								previous_source_poses[bone].basis.get_rotation_quaternion())))
				for side: String in ["Left", "Right"]:
					var side_index := 0 if side == "Left" else 1
					var source_low := modifier.reference_bank.foot_mesh_min_y(
							mode, modifier.phase, side_index) + clearance
					if source_low > (0.12 if mode == &"sprint" else 0.04):
						source_airborne_frames += 1
						if modifier.reference_bank.contact_weight(
								mode, side_index, fposmod(modifier.phase / TAU, 1.0)) > 0.001:
							source_airborne_weighted += 1
					# Acquisition/release intentionally interpolates from the source pose.
					# Measure plant accuracy only once that interpolation is complete;
					# max_leg_step independently bounds the transition itself.
					if float(modifier.debug_contact_weight.get(side, 0.0)) >= 0.999:
						full_contact_frames += 1
						var error := float(modifier.debug_target_error.get(side, 0.0))
						if error > max_contact_error:
							max_contact_error = error
							worst_contact_frame = frame
							worst_contact_side = side
							worst_contact_root_z = skeleton.global_position.z
							var active_target: Vector3 = modifier.get(
									"_source_contact_targets")[side_index]
							worst_contact_target_z = active_target.z
							worst_contact_target_y = active_target.y
				previous_poses = poses.duplicate()
				previous_source_poses = source_poses
			var contact_driven: bool = moving
			var step_budget := (max_source_leg_step + 5.0 if mode == &"sprint" else 20.0)
			var minimum_planted := (8 if mode == &"sprint" else CYCLE_FRAMES / 2)
			var passed: bool = ((max_upper_rotation < 2.0 and max_upper_position < 0.02
					and max_contact_error < 0.025 and max_leg_step < step_budget
					and full_contact_frames >= minimum_planted
					and (mode != &"sprint" or source_airborne_weighted == 0))
					if contact_driven else
					(max_rotation < 2.0 and max_relative_position < 0.02)) \
					and max_clearance_step < 0.04
			passed_all = passed_all and passed
			print(("POSE_MATCH %s %s %s bones=%d frames=%d "
					+ "rotation=%.3fdeg %s@f%d position=%.4fm clearance_step=%.4fm "
					+ "upper=%.3fdeg/%.4fm contact=%.4fm leg_step=%.2fdeg "
					+ "source_leg_step=%.2fdeg step_at=%s@f%d planted=%d "
					+ "airborne_weighted=%d/%d worst_contact=f%d/%s "
					+ "root_z=%.3fm target_z=%.3fm target_y=%.3fm") % [
					mode, "moving" if moving else "in_place", "PASS" if passed else "FAIL",
					skeleton.get_bone_count(), CYCLE_FRAMES, max_rotation,
					worst_name, worst_frame, max_relative_position, max_clearance_step,
					max_upper_rotation, max_upper_position, max_contact_error, max_leg_step,
					max_source_leg_step, worst_step_name, worst_step_frame,
					full_contact_frames, source_airborne_weighted, source_airborne_frames,
					worst_contact_frame, worst_contact_side, worst_contact_root_z,
					worst_contact_target_z, worst_contact_target_y])
	return (await _check_contact_off(lab, skeleton, modifier, reference)) and passed_all


func _check_contact_off(lab: Node3D, skeleton: Skeleton3D,
		modifier: ProceduralWalkLabModifier, reference: Skeleton3D) -> bool:
	var saved_weight := modifier.contact_ik
	modifier.contact_ik = 0.0
	lab.call("_select_reference_mode", ProceduralWalkReferenceBank.MODE_ORDER.find(&"walk") + 1)
	lab.set("_playing", true)
	var max_rotation := 0.0
	var max_position := 0.0
	var max_contact_weight := 0.0
	var worst_frame := -1
	var worst_bone := &""
	var hips := skeleton.find_bone(&"Hips")
	var technical_root := skeleton.find_bone(&"Root")
	for frame in 60:
		await lab.get_tree().physics_frame
		var poses := modifier.debug_bone_poses
		var procedural_hips: Vector3 = poses[hips].origin
		var source_hips := reference.get_bone_global_pose(hips).origin
		for bone in skeleton.get_bone_count():
			var source := reference.get_bone_global_pose(bone)
			var rotation := rad_to_deg(
					poses[bone].basis.get_rotation_quaternion().angle_to(
					source.basis.get_rotation_quaternion()))
			if rotation > max_rotation:
				max_rotation = rotation
				worst_frame = frame
				worst_bone = skeleton.get_bone_name(bone)
			if bone != technical_root:
				max_position = maxf(max_position, ((poses[bone].origin - procedural_hips)
						- (source.origin - source_hips)).length())
		for side: String in ["Left", "Right"]:
			max_contact_weight = maxf(max_contact_weight,
					float(modifier.debug_contact_weight.get(side, 0.0)))
	modifier.contact_ik = saved_weight
	var passed := max_rotation < 2.0 and max_position < 0.02 and max_contact_weight < 0.001
	print(("CONTACT_IK_OFF %s frames=60 rotation=%.3fdeg %s@f%d "
			+ "position=%.4fm weight=%.3f") % [
			"PASS" if passed else "FAIL", max_rotation, worst_bone, worst_frame,
			max_position, max_contact_weight])
	return passed


func _is_leg_bone(name: String) -> bool:
	return (name.contains("Leg") or name.contains("Foot") or name.contains("Toe"))
