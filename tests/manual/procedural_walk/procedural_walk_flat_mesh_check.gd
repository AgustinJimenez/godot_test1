class_name ProceduralWalkFlatMeshCheck
extends RefCounted
## Final skinned-shoe contact checks for every flat source-derived gait.

const MODES := [&"walk", &"walk_aim", &"sprint", &"crouch"]
const FRAMES := 120


func run(lab: Node3D, character: Node3D, skeleton: Skeleton3D,
		modifier: ProceduralWalkLabModifier) -> bool:
	await lab.get_tree().physics_frame
	var mesh_check := ProceduralWalkMeshClearance.new()
	mesh_check.prepare(character, skeleton)
	var all_passed := mesh_check.vertex_count > 100
	for mode: StringName in MODES:
		lab.call("_select_reference_mode",
				ProceduralWalkReferenceBank.MODE_ORDER.find(mode) + 1)
		for moving in [false, true]:
			lab.call("_set_moving_mode", moving)
			lab.set("_playing", moving)
			var lowest := INF
			var highest_lowest := -INF
			var contact_frames := 0
			for frame in FRAMES:
				if not moving:
					lab.call("_set_frame", float(frame))
				await lab.get_tree().physics_frame
				var foot_min := mesh_check.sample(skeleton, modifier.debug_bone_poses)
				var low := minf(foot_min[0], foot_min[1])
				lowest = minf(lowest, low)
				highest_lowest = maxf(highest_lowest, low)
				if low <= 0.03:
					contact_frames += 1
			var passed := lowest >= 0.003 and contact_frames >= 60
			all_passed = all_passed and passed
			print(("FLAT_MESH %s %s %s vertices=%d min=%.3fm max_low=%.3fm "
					+ "contact_frames=%d/%d") % [
					mode, "moving" if moving else "in_place", "PASS" if passed else "FAIL",
					mesh_check.vertex_count, lowest, highest_lowest, contact_frames, FRAMES])
	return all_passed
