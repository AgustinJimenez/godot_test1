extends SceneTree
## The native foot IK maths (FootIKV2Native, native/planet_crust) against the GDScript reference, on random legs and a random cached sole.
## godot --headless --path . --script res://tests/manual/foot_ik_v2/foot_ik_v2_native_check.gd   -> FOOT_IK_V2_NATIVE_CHECK PASS (or SKIP when the library is not built)

const REFERENCE := preload("res://tests/manual/foot_ik_v2/foot_ik_v2_solver_reference.gd")
const TOLERANCE := 0.0001 # metres: single precision floats in both, so the two agree to about 1e-6; leave room for the acos/cos paths


func _initialize() -> void:
	if not ClassDB.class_exists(&"FootIKV2Native"):
		print("FOOT_IK_V2_NATIVE_CHECK SKIP (FootIKV2Native is not built: scripts/build_native.sh)")
		quit(0)
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	var worst_solve := 0.0
	for trial in 4000:
		var hip := Vector3(rng.randf_range(-1, 1), rng.randf_range(0.7, 1.1), rng.randf_range(-1, 1))
		var knee := hip + Vector3(rng.randf_range(-0.2, 0.2), -0.45, rng.randf_range(0.0, 0.3))
		var target := hip + Vector3(rng.randf_range(-0.6, 0.6), rng.randf_range(-1.0, -0.3), rng.randf_range(-0.6, 0.6))
		var upper := rng.randf_range(0.35, 0.5)
		var lower := rng.randf_range(0.35, 0.5)
		var flex := 0.0 if trial % 3 == 0 else 150.0
		var swing := 0.0 if trial % 2 == 0 else 100.0
		var free := rng.randf()
		var a: Dictionary = REFERENCE.solve(hip, knee, target, upper, lower, Vector3.FORWARD, flex, swing, Vector3.DOWN, free)
		var b: Dictionary = FootIKV2Solver.solve(hip, knee, target, upper, lower, Vector3.FORWARD, flex, swing, Vector3.DOWN, free)
		for key in ["knee", "ankle", "direction", "pole"]:
			worst_solve = maxf(worst_solve, (a[key] as Vector3).distance_to(b[key] as Vector3))
		worst_solve = maxf(worst_solve, absf(float(a["distance"]) - float(b["distance"])))
	var count := 600
	var foot_weight := PackedFloat32Array()
	var toe_weight := PackedFloat32Array()
	var foot_local := PackedVector3Array()
	var toe_local := PackedVector3Array()
	for i in count:
		var w := rng.randf()
		foot_weight.append(w)
		toe_weight.append(1.0 - w)
		foot_local.append(Vector3(rng.randf_range(-0.1, 0.1), rng.randf_range(-0.1, 0.05), rng.randf_range(-0.1, 0.2)))
		toe_local.append(Vector3(rng.randf_range(-0.1, 0.1), rng.randf_range(-0.05, 0.05), rng.randf_range(-0.1, 0.1)))
	var native: RefCounted = ClassDB.instantiate(&"FootIKV2Native")
	native.call(&"set_sole", foot_weight, toe_weight, foot_local, toe_local)
	var worst_points := 0.0
	var worst_level := 0.0
	var worst_low := 0.0
	for trial in 200:
		var foot_pose := Transform3D(Basis(Quaternion(Vector3(rng.randf_range(-1, 1), rng.randf_range(-1, 1), rng.randf_range(-1, 1)).normalized(), rng.randf_range(0, 1))), Vector3(rng.randf_range(-1, 1), rng.randf_range(0, 1), rng.randf_range(-1, 1)))
		var toe_pose := Transform3D(foot_pose.basis * Basis(Vector3.RIGHT, rng.randf_range(-0.5, 0.5)), foot_pose.origin + Vector3(0, -0.05, 0.15))
		var to_world := Transform3D(Basis(Vector3.UP, rng.randf_range(0, TAU)), Vector3(rng.randf_range(-5, 5), 0, rng.randf_range(-5, 5)))
		var pts: PackedVector3Array = native.call(&"points", foot_pose, toe_pose)
		for i in count:
			var expected := foot_pose.basis * foot_local[i] + foot_pose.origin * foot_weight[i] + toe_pose.basis * toe_local[i] + toe_pose.origin * toe_weight[i]
			worst_points = maxf(worst_points, expected.distance_to(pts[i]))
		var level: PackedVector3Array = native.call(&"level_points", foot_pose, toe_pose, to_world, 0.005)
		var up := Vector3(to_world.basis.x.y, to_world.basis.y.y, to_world.basis.z.y)
		var lowest := INF
		var expected_level := PackedVector3Array()
		for i in count:
			var local := foot_pose.basis * foot_local[i] + foot_pose.origin * foot_weight[i] + toe_pose.basis * toe_local[i] + toe_pose.origin * toe_weight[i]
			lowest = minf(lowest, up.dot(local))
		for i in count:
			var local := foot_pose.basis * foot_local[i] + foot_pose.origin * foot_weight[i] + toe_pose.basis * toe_local[i] + toe_pose.origin * toe_weight[i]
			if up.dot(local) <= lowest + 0.005:
				expected_level.append(to_world * local)
		if expected_level.size() != level.size():
			worst_level = maxf(worst_level, 1.0)
		else:
			for i in level.size():
				worst_level = maxf(worst_level, expected_level[i].distance_to(level[i]))
		var low_y := INF
		for i in count:
			low_y = minf(low_y, (to_world * (foot_pose.basis * foot_local[i] + foot_pose.origin * foot_weight[i] + toe_pose.basis * toe_local[i] + toe_pose.origin * toe_weight[i])).y)
		worst_low = maxf(worst_low, absf(low_y - float(native.call(&"lowest_world_y", foot_pose, toe_pose, to_world))))
	print("worst difference (metres): solve %s  points %s  level_points %s  lowest %s  (limit %s)" % [
			String.num(worst_solve, 9), String.num(worst_points, 9), String.num(worst_level, 9), String.num(worst_low, 9), String.num(TOLERANCE, 9)])
	var ok := worst_solve < TOLERANCE and worst_points < TOLERANCE and worst_level < TOLERANCE and worst_low < TOLERANCE
	print("FOOT_IK_V2_NATIVE_CHECK %s" % ("PASS" if ok else "FAIL"))
	quit(0 if ok else 1)
