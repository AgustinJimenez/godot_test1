extends SceneTree
## Read actual GPU cloth and body contact together during the walking elbow bend.
## Run rendered with --fixed-fps 60 -- --pose=walk --sweep=40 [--gender=Female].

signal sampled(cloth: PackedFloat32Array, body: PackedFloat32Array, targets: PackedFloat32Array)

var lab: Node3D


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	lab = (load("res://tests/manual/humans/human_rig_lab.tscn") as PackedScene).instantiate()
	lab.set("_cloth", true)
	root.add_child(lab)
	var sample_frame: int = 90
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--sample-frame="):
			sample_frame = maxi(30, arg.trim_prefix("--sample-frame=").to_int())
	for i in sample_frame:
		await physics_frame
	await RenderingServer.frame_post_draw
	paused = true
	var solver: GPUClothSolver = ClothSetup.sleeve_solver((lab.get("_cloth_root") as Node).get_children())
	var skeleton: Skeleton3D = lab.get("_skeleton")
	var poses: Array = []
	for i in skeleton.get_bone_count():
		poses.append(skeleton.get_bone_global_pose(i))
	var expected: PackedFloat32Array = HumanRig.skin_cloth_arms(
		solver._native_collider_data, poses).to_float32_array()
	RenderingServer.call_on_render_thread(func() -> void:
		var cloth: PackedFloat32Array = solver._rd.buffer_get_data(
			solver._positions_buffer).to_float32_array()
		var body: PackedFloat32Array = solver._rd.buffer_get_data(
			solver._collider_tri_buffer).to_float32_array()
		var targets: PackedFloat32Array = solver._rd.buffer_get_data(
			solver._skinned_targets_buffer).to_float32_array()
		_deliver.call_deferred(cloth, body, targets))
	var sampled_data: Array = await sampled
	var cloth: PackedFloat32Array = sampled_data[0]
	var body: PackedFloat32Array = sampled_data[1]
	var targets: PackedFloat32Array = sampled_data[2]
	var frame_gap: float = 0.0
	for i in expected.size() / 4:
		frame_gap = maxf(frame_gap, _point(expected, i).distance_to(_point(body, i)))
	print("CLOTH_MOTION body pose GPU/CPU gap mm ", frame_gap * 1000.0)
	var triangle_points := PackedVector3Array()
	for i in body.size() / 4:
		triangle_points.append(_point(body, i))
	var min_vertex: float = INF
	var min_center: float = INF
	var vertices_inside: int = 0
	var centers_inside: int = 0
	var tested_faces: int = 0
	for i in cloth.size() / 4:
		if solver._debug_cloth_weights[i] < 0.999:
			continue
		var d: float = _signed(_point(cloth, i), triangle_points)
		min_vertex = minf(min_vertex, d)
		if d < -0.001:
			vertices_inside += 1
			if vertices_inside <= 10:
				print("CLOTH_MOTION inward particle %d travel_mm %.3f target_mm %.3f" % [
					i, _point(cloth, i).distance_to(_point(targets, i)) * 1000.0,
					_signed(_point(targets, i), triangle_points) * 1000.0])
	for i in solver._welded_indices.size() / 3:
		var a: int = solver._welded_indices[i * 3]
		var b: int = solver._welded_indices[i * 3 + 1]
		var c: int = solver._welded_indices[i * 3 + 2]
		if minf(solver._debug_cloth_weights[a], minf(solver._debug_cloth_weights[b],
				solver._debug_cloth_weights[c])) < 0.999:
			continue
		var pa: Vector3 = _point(cloth, a)
		var pb: Vector3 = _point(cloth, b)
		var pc: Vector3 = _point(cloth, c)
		for p: Vector3 in [(pa + pb + pc) / 3.0, (pa + pb) * 0.5,
				(pb + pc) * 0.5, (pc + pa) * 0.5]:
			var d: float = _signed(p, triangle_points)
			min_center = minf(min_center, d)
			if d < -0.001:
				centers_inside += 1
		tested_faces += 1
	print("CLOTH_MOTION vertex min mm %.3f inside %d face/edge min mm %.3f inside %d faces %d" % [
		min_vertex * 1000.0, vertices_inside, min_center * 1000.0, centers_inside, tested_faces])
	# The rendered surface sits 1 mm outside the simulated surface. Check the
	# interiors too: safe vertices alone missed the original 3.86 mm elbow clip.
	var passed: bool = frame_gap < 0.0001 and vertices_inside == 0 \
		and centers_inside == 0 and tested_faces > 100
	print("CLOTH_MOTION_CHECK PASS" if passed else "CLOTH_MOTION_CHECK FAIL")
	quit(0 if passed else 1)


func _deliver(cloth: PackedFloat32Array, body: PackedFloat32Array,
		targets: PackedFloat32Array) -> void:
	sampled.emit(cloth, body, targets)


func _point(data: PackedFloat32Array, i: int) -> Vector3:
	return Vector3(data[i * 4], data[i * 4 + 1], data[i * 4 + 2])


func _signed(p: Vector3, triangles: PackedVector3Array) -> float:
	var best: float = INF
	var value: float = INF
	for i in triangles.size() / 3:
		var a: Vector3 = triangles[i * 3]
		var b: Vector3 = triangles[i * 3 + 1]
		var c: Vector3 = triangles[i * 3 + 2]
		var low: Vector3 = a.min(b).min(c)
		var high: Vector3 = a.max(b).max(c)
		if p.distance_squared_to(p.clamp(low, high)) > best:
			continue
		var nearest: Vector3 = OutfitFitGeometry.closest_point_on_triangle(p, a, b, c)
		var d: float = p.distance_squared_to(nearest)
		if d < best:
			best = d
			value = (p - nearest).dot((b - a).cross(c - a).normalized())
	return value
