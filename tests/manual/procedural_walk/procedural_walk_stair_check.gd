class_name ProceduralWalkStairCheck
extends RefCounted
## Replays the stair gait and checks the visible shoe, not only the ankle target.

const FRAMES := 480
const MIN_SHOE_CLEARANCE := 0.001
const MAX_PLANTED_SHOE_GAP := 0.03


func run(lab: Node3D, character: Node3D, skeleton: Skeleton3D,
		modifier: ProceduralWalkLabModifier, raw_actor: ProceduralWalkRawActor) -> bool:
	await lab.get_tree().physics_frame
	var mesh_check := ProceduralWalkMeshClearance.new()
	mesh_check.prepare(character, skeleton)
	lab.call("_select_reference_mode",
			ProceduralWalkReferenceBank.MODE_ORDER.find(&"stair_up") + 1)
	var start_y := character.global_position.y
	var worst_plant_error := 0.0
	var worst_plant_frame := -1
	var worst_plant_side := -1
	var planted_samples := 0
	var worst_step := 0.0
	var worst_shoe := INF
	var worst_shoe_frame := -1
	var worst_shoe_side := -1
	var highest_planted_shoe := -INF
	var highest_planted_frame := -1
	var highest_planted_side := -1
	var unsafe_plan_frames := 0
	var previous: Dictionary = {}
	for frame in FRAMES:
		await lab.get_tree().physics_frame
		var feet := mesh_check.sample(skeleton, modifier.debug_bone_poses,
				modifier.stair_support_height)
		for side in 2:
			if feet[side] < worst_shoe:
				worst_shoe = feet[side]
				worst_shoe_frame = frame
				worst_shoe_side = side
			if not modifier.has_plant(side):
				continue
			if feet[side] > highest_planted_shoe:
				highest_planted_shoe = feet[side]
				highest_planted_frame = frame
				highest_planted_side = side
			var name := &"LeftFoot" if side == 0 else &"RightFoot"
			var error := (modifier.debug_joint_positions[name] as Vector3).distance_to(
					modifier.plant_world(side))
			if error > worst_plant_error:
				worst_plant_error = error
				worst_plant_frame = frame
				worst_plant_side = side
			planted_samples += 1
		var plan := modifier.footstep_plan()
		for index in plan.size():
			var target: Vector3 = plan.target(index)
			if target.distance_to(modifier.stair_safe_ankle(target)) > 0.0001:
				unsafe_plan_frames += 1
				break
		var rotations: Dictionary = modifier.debug_joint_rotations
		if not previous.is_empty():
			for name: StringName in rotations:
				worst_step = maxf(worst_step, rad_to_deg(
						(rotations[name] as Quaternion).angle_to(previous[name])))
		previous = rotations.duplicate()
	var climbed := absf(character.global_position.y - start_y)
	var passed := climbed > 0.6 and planted_samples > 100 \
			and worst_plant_error < 0.03 and worst_step < 30.0 \
			and worst_shoe >= MIN_SHOE_CLEARANCE \
			and highest_planted_shoe <= MAX_PLANTED_SHOE_GAP \
			and unsafe_plan_frames == 0 \
			and raw_actor.step_plan_is_stable() and mesh_check.vertex_count > 100
	print(("PROCEDURAL_STAIR stair_up %s elevation=%.2fm planted=%d "
			+ "plant_error=%.3fm@f%d/side%d max_joint_step=%.1fdeg "
			+ "shoe_min=%.3fm@f%d/side%d planted_gap_max=%.3fm@f%d/side%d "
			+ "vertices=%d unsafe_plan_frames=%d") % [
			"PASS" if passed else "FAIL", climbed, planted_samples,
			worst_plant_error, worst_plant_frame, worst_plant_side, worst_step,
			worst_shoe, worst_shoe_frame, worst_shoe_side,
			highest_planted_shoe, highest_planted_frame, highest_planted_side,
			mesh_check.vertex_count,
			unsafe_plan_frames])
	return passed
