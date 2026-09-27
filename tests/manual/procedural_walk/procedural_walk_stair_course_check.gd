class_name ProceduralWalkStairCourseCheck
extends RefCounted
## Verifies the button route begins ahead of the current actor and traverses up then down.

const MAX_FRAMES := 1500


func run(lab: Node3D, character: Node3D, skeleton: Skeleton3D,
		modifier: ProceduralWalkLabModifier) -> bool:
	await lab.get_tree().physics_frame
	var mesh_check := ProceduralWalkMeshClearance.new()
	mesh_check.prepare(character, skeleton)
	var course_button: Button
	for node: Node in lab.find_children("*", "Button", true, false):
		if (node as Button).text == "Spawn up + down stairs (3 m ahead)":
			course_button = node as Button
			break
	if course_button == null:
		push_error("Stair course button is missing")
		return false
	var all_passed := true
	var modes: Array[StringName] = [
		&"walk", &"walk_aim", &"sprint", &"crouch", &"stair_up", &""]
	if "--course-walk-only" in OS.get_cmdline_user_args():
		modes = [&"walk"]
	elif "--course-original-only" in OS.get_cmdline_user_args():
		modes = [&""]
	for mode: StringName in modes:
		lab.call("_select_reference_mode",
				ProceduralWalkReferenceBank.MODE_ORDER.find(mode) + 1)
		var before_z := character.global_position.z
		course_button.pressed.emit()
		var course := modifier.stair_course
		var ahead := before_z - course.start_z
		var peak := -INF
		var descended := false
		var frames := 0
		var shoe_min := INF
		var planted_gap_max := -INF
		var shoe_worst_frame := -1
		var shoe_worst_detail := ""
		var gap_detail := ""
		var previous_ankles: Array[Vector3] = []
		var previous_rotations: Dictionary = {}
		var ankle_step_max := 0.0
		var joint_step_max := 0.0
		for frame in MAX_FRAMES:
			await lab.get_tree().physics_frame
			skeleton.advance(0.0)
			frames = frame + 1
			peak = maxf(peak, character.global_position.y)
			if character.global_position.z < course.start_z:
				var ankles: Array[Vector3] = [
					modifier.debug_joint_positions[&"LeftFoot"],
					modifier.debug_joint_positions[&"RightFoot"],
				]
				if previous_ankles.size() == 2:
					for side in 2:
						ankle_step_max = maxf(ankle_step_max,
								ankles[side].distance_to(previous_ankles[side]))
				previous_ankles = ankles
				for joint: StringName in modifier.debug_joint_rotations:
					var rotation: Quaternion = modifier.debug_joint_rotations[joint]
					if previous_rotations.has(joint):
						joint_step_max = maxf(joint_step_max,
								rad_to_deg((previous_rotations[joint] as Quaternion).angle_to(rotation)))
					previous_rotations[joint] = rotation
				var feet := mesh_check.sample(skeleton, modifier.debug_bone_poses,
						course.support_height, ankles)
				for side in 2:
					if feet[side] < shoe_min:
						shoe_min = feet[side]
						shoe_worst_frame = frame
						var ankle: Vector3 = modifier.debug_joint_positions[
								&"LeftFoot" if side == 0 else &"RightFoot"]
						var targets: Array[Vector3] = modifier.get("_source_contact_targets")
						var plan_target: Vector3 = targets[side]
						var hip: Vector3 = modifier.debug_joint_positions[
								&"LeftUpLeg" if side == 0 else &"RightUpLeg"]
						var knee: Vector3 = modifier.debug_joint_positions[
								&"LeftLeg" if side == 0 else &"RightLeg"]
						var low: Vector3 = mesh_check.last_low_positions[side]
						var low_bin := roundi((ankle.z - low.z) * 1000.0)
						var sample_index := roundi(fposmod(modifier.phase / TAU, 1.0)
								* float(ProceduralWalkReferenceBank.SAMPLE_COUNT)) \
								% ProceduralWalkReferenceBank.SAMPLE_COUNT
						var source_profile: Dictionary = (
								modifier.reference_bank.mesh_profile_frames[mode][sample_index][side])
						var prior_profile: Dictionary = (
								modifier.reference_bank.mesh_profile_frames[mode][
								(sample_index + ProceduralWalkReferenceBank.SAMPLE_COUNT - 1)
								% ProceduralWalkReferenceBank.SAMPLE_COUNT][side])
						var next_profile: Dictionary = (
								modifier.reference_bank.mesh_profile_frames[mode][
								(sample_index + 1) % ProceduralWalkReferenceBank.SAMPLE_COUNT][side])
						shoe_worst_detail = ("side%d root=%s pose_root=%s foot=%s ankle=%s phase=%.2f "
								+ "required=%.3f contact=%.2f error=%.3f hip=%s plan=%s "
								+ "distance=%.3f reach=%.3f low_bin=%d actual_drop=%.3f "
								+ "source_drop=%.3f adjacent=%.3f/%.3f") % [
							side, str(character.global_position),
							str(modifier.debug_root_position),
							str(mesh_check.last_low_positions[side]),
							str(ankle), fposmod(modifier.phase / TAU, 1.0),
							modifier.reference_bank.shoe_clearance_ankle_y(
								mode, modifier.phase, side, ankle.z, course.support_height),
							float(modifier.debug_contact_weight.get(
								"Left" if side == 0 else "Right", 0.0)),
							float(modifier.debug_target_error.get(
								"Left" if side == 0 else "Right", 0.0)),
							str(hip), str(plan_target), hip.distance_to(plan_target),
							hip.distance_to(knee) + knee.distance_to(ankle), low_bin,
							ankle.y - low.y, float(source_profile.get(low_bin, -1.0)),
							float(prior_profile.get(low_bin, -1.0)),
							float(next_profile.get(low_bin, -1.0))]
					var contact := (modifier.has_plant(side) if mode in [&"stair_up", &""]
							else float(modifier.debug_contact_weight.get(
							"Left" if side == 0 else "Right", 0.0)) >= 0.8)
					if contact:
						if feet[side] > planted_gap_max:
							planted_gap_max = feet[side]
							var front_bin := 999
							for bin: int in mesh_check.last_profiles[side]:
								front_bin = mini(front_bin, bin)
							var source_bin := -999
							var sample_index := int(floorf(fposmod(modifier.phase / TAU, 1.0)
									* float(ProceduralWalkReferenceBank.SAMPLE_COUNT)))
							if modifier.reference_bank.mesh_profile_frames.has(mode):
								for bin: int in modifier.reference_bank.mesh_profile_frames[mode][sample_index][side]:
									source_bin = maxi(source_bin, bin)
							gap_detail = ("f%d side%d root=%s foot=%s ankle=%s phase=%.2f "
								+ "weight=%.2f required=%.3f front=%.2f source_front=%.2f") % [
								frame, side, str(character.global_position),
								str(mesh_check.last_low_positions[side]),
								str(modifier.debug_joint_positions[
								&"LeftFoot" if side == 0 else &"RightFoot"]),
								fposmod(modifier.phase / TAU, 1.0),
								float(modifier.debug_contact_weight.get(
								"Left" if side == 0 else "Right", 0.0)),
								modifier.reference_bank.shoe_clearance_ankle_y(
									mode, modifier.phase, side,
									(modifier.debug_joint_positions[
									&"LeftFoot" if side == 0 else &"RightFoot"] as Vector3).z,
									course.support_height), float(-front_bin) * 0.001,
								float(source_bin) * 0.001]
			if peak > 1.8 and character.global_position.y < 0.15:
				descended = true
			if course.is_finished(character.global_position.z):
				break
		var route_passed := absf(ahead - ProceduralWalkStairCourse.APPROACH) < 0.001 \
				and peak > 1.8 and descended \
				and course.is_finished(character.global_position.z)
		var pose_passed := shoe_min >= -0.01 and planted_gap_max <= 0.03
		var smooth_graded := mode == &"walk"
		var smooth_passed := not smooth_graded or (
				ankle_step_max < 0.08 and joint_step_max < 30.0)
		var smooth_label := ("PASS" if smooth_passed else "FAIL") if smooth_graded else "UNTESTED"
		var passed := route_passed and pose_passed and smooth_passed
		all_passed = all_passed and passed
		print(("STAIR_COURSE %s route=%s shoe=%s smooth=%s ahead=%.2fm peak=%.2fm "
				+ "down=%s frames=%d finished=%s shoe_min=%.3fm@f%d "
				+ "contact_gap_max=%.3fm ankle_step_max=%.3fm joint_step_max=%.1fdeg") % [
				mode, "PASS" if route_passed else "FAIL",
				"PASS" if pose_passed else "FAIL", smooth_label,
				ahead, peak, str(descended),
				frames, str(course.is_finished(character.global_position.z)),
				shoe_min, shoe_worst_frame, planted_gap_max, ankle_step_max, joint_step_max])
		print("STAIR_COURSE_DETAIL clip=%s gap=%s" % [shoe_worst_detail, gap_detail])
	return all_passed
