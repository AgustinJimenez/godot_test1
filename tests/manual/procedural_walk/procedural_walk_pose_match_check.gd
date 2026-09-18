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
			var previous_clearance := NAN
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
				var clearance := modifier.reference_bank.floor_clearance(
						mode, modifier.phase)
				if not is_nan(previous_clearance):
					max_clearance_step = maxf(max_clearance_step,
							absf(clearance - previous_clearance))
				previous_clearance = clearance
				for bone in skeleton.get_bone_count():
					var source := reference.get_bone_global_pose(bone)
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
			var passed := (max_rotation < 2.0 and max_relative_position < 0.02
					and max_clearance_step < 0.04)
			passed_all = passed_all and passed
			print(("POSE_MATCH %s %s %s bones=%d frames=%d "
					+ "rotation=%.3fdeg %s@f%d position=%.4fm clearance_step=%.4fm") % [
					mode, "moving" if moving else "in_place", "PASS" if passed else "FAIL",
					skeleton.get_bone_count(), CYCLE_FRAMES, max_rotation,
					worst_name, worst_frame, max_relative_position, max_clearance_step])
	return passed_all
