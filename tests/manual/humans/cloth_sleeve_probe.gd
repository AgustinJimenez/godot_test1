extends Node
## Rest-pose sleeve evidence: how far simulated cloth sits above the upper arm surface.
## Run rendered with --fixed-fps 60; optional --gender=Female and --capture=<png>.

signal sampled(data: PackedFloat32Array)

var _lab: Node3D
var _failed: bool = false


func _ready() -> void:
	_lab = (load("res://tests/manual/humans/human_rig_lab.tscn") as PackedScene).instantiate()
	_lab.set("_cloth", true)
	_lab.set("_distance", 1.6)
	# This probe owns capture and exit; do not pass capture to the rig lab.
	add_child(_lab)
	_lab.set("_capture_path", "")
	for frame in 150:
		await get_tree().physics_frame
	await RenderingServer.frame_post_draw
	var solver: GPUClothSolver = (_lab.get("_cloth_root") as Node).get_child(0)
	RenderingServer.call_on_render_thread(func() -> void:
		var data: PackedFloat32Array = solver._rd.buffer_get_data(
			solver._positions_buffer).to_float32_array()
		_deliver.call_deferred(data)
	)
	var positions: PackedFloat32Array = await sampled
	_measure(solver, positions)
	var poses: Array = []
	var skeleton: Skeleton3D = _lab.get("_skeleton")
	for i in skeleton.get_bone_count():
		poses.append(skeleton.get_bone_global_pose(i))
	var started: int = Time.get_ticks_usec()
	for i in 100:
		HumanRig.skin_cloth_arms(solver._native_collider_data, poses)
	print("SLEEVE_PROBE native packing ms %.3f" % ((Time.get_ticks_usec() - started) / 100000.0))
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--capture="):
			get_viewport().get_texture().get_image().save_png(arg.trim_prefix("--capture="))
	if not _failed:
		print("CLOTH_SLEEVE_CHECK PASS")
	get_tree().quit(1 if _failed else 0)


func _deliver(data: PackedFloat32Array) -> void:
	sampled.emit(data)


func _measure(solver: GPUClothSolver, positions: PackedFloat32Array) -> void:
	var body: MeshInstance3D = _lab.get("_mesh")
	var skeleton: Skeleton3D = _lab.get("_skeleton")
	var arrays: Array = body.mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var body_to_ref: Transform3D = solver._ref_node.global_transform.affine_inverse() \
		* body.global_transform
	var up: Vector3 = solver._ref_node.global_basis.inverse() * Vector3.UP
	var simulated := PackedVector3Array()
	for i in positions.size() / 4:
		simulated.append(Vector3(positions[i * 4], positions[i * 4 + 1], positions[i * 4 + 2]))
	for side: String in ["Left", "Right"]:
		for segment: String in ["Arm", "ForeArm"]:
			var bone: int = skeleton.find_bone("mixamorig_" + side + segment)
			var end_name: String = "ForeArm" if segment == "Arm" else "Hand"
			var end: int = skeleton.find_bone("mixamorig_" + side + end_name)
			var a: Vector3 = skeleton.get_bone_global_rest(bone).origin
			var axis: Vector3 = skeleton.get_bone_global_rest(end).origin - a
			var gaps: Array[float] = []
			var movements: Array[float] = []
			var weights: Array[float] = []
			var ray_gaps: Array[float] = []
			for v in vertices.size():
				var p: Vector3 = body_to_ref * vertices[v]
				var n: Vector3 = (body_to_ref.basis * normals[v]).normalized()
				var along: float = (p - a).dot(axis) / axis.length_squared()
				if along < (0.2 if segment == "Arm" else 0.0) or along > 0.95 or n.dot(up) < 0.6:
					continue
				if p.distance_to(a + axis * along) > 0.12:
					continue
				var nearest: int = -1
				var distance_sq: float = INF
				for i in solver._welded_positions.size():
					var d: float = p.distance_squared_to(solver._welded_positions[i])
					if d < distance_sq:
						distance_sq = d
						nearest = i
				var actual := Vector3(positions[nearest * 4], positions[nearest * 4 + 1],
					positions[nearest * 4 + 2])
				gaps.append((actual - p).dot(n) + solver.cloth_render_offset)
				movements.append(actual.distance_to(solver._welded_positions[nearest]))
				weights.append(solver._debug_cloth_weights[nearest])
				var ray_gap: float = INF
				for tri in solver._welded_indices.size() / 3:
					var ta: Vector3 = simulated[solver._welded_indices[tri * 3]]
					var tb: Vector3 = simulated[solver._welded_indices[tri * 3 + 1]]
					var tc: Vector3 = simulated[solver._welded_indices[tri * 3 + 2]]
					var face: Vector3 = -(tb - ta).cross(tc - ta).normalized()
					if face.dot(n) < 0.3:
						continue
					# Work in centimetres around the ray origin: the engine's
					# absolute intersection epsilon misses small refined triangles
					# in metres. This preserves the same ray and coverage threshold.
					var hit: Variant = Geometry3D.segment_intersects_triangle(
						-n * 5.0, n * 8.0, (ta - p) * 100.0,
						(tb - p) * 100.0, (tc - p) * 100.0)
					if hit != null:
						var gap: float = (hit as Vector3).dot(n) / 100.0
						if absf(gap) < absf(ray_gap):
							ray_gap = gap
				if is_finite(ray_gap):
					ray_gaps.append(ray_gap + solver.cloth_render_offset)
					if ray_gap + solver.cloth_render_offset < -0.002:
						print("SLEEVE_PROBE inward ", side, segment, " along ", along,
							" gap_mm ", (ray_gap + solver.cloth_render_offset) * 1000.0)
			if gaps.is_empty():
				_failed = true
				print("SLEEVE_PROBE FAIL no samples: ", side, segment)
				continue
			print("SLEEVE_PROBE %s%s samples %d top_gap_mm %.1f movement_mm %.1f weight %.2f" % [
				side, segment, gaps.size(), _mean(gaps) * 1000.0,
				_mean(movements) * 1000.0, _mean(weights)])
			gaps.sort()
			if not ray_gaps.is_empty():
				ray_gaps.sort()
				print("SLEEVE_PROBE %s%s ray_samples %d ray_gap_mean_mm %.1f ray_gap_min_mm %.1f" % [
					side, segment, ray_gaps.size(), _mean(ray_gaps) * 1000.0, ray_gaps[0] * 1000.0])
				if _mean(ray_gaps) > 0.012 or ray_gaps[0] < -0.001 \
						or ray_gaps.size() < gaps.size() * 0.6:
					_failed = true
					print("CLOTH_SLEEVE_CHECK FAIL: ", side, segment)
			else:
				_failed = true
				print("CLOTH_SLEEVE_CHECK FAIL: no ray hits on ", side, segment)


func _mean(values: Array[float]) -> float:
	var total: float = 0.0
	for value: float in values:
		total += value
	return total / values.size()
