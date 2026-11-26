class_name ClothOverlapProbe
extends RefCounted
## (debug, --cloth-overlap in the rig and body labs; call on the render thread) where the shirt covers the trousers: for every shirt particle below the trousers' top, the nearest trouser particle; how
## far the shirt is outside it (along the horizontal direction from the body's axis), and how far each moved in or out from its rest place
static var _rest_done: Dictionary = {}


static func measure(shirt: GPUClothSolver, pants: GPUClothSolver) -> void:
	var sp: PackedFloat32Array = shirt._rd.buffer_get_data(shirt._positions_buffer).to_float32_array()
	var pp: PackedFloat32Array = pants._rd.buffer_get_data(pants._positions_buffer).to_float32_array()
	var s_rest: PackedVector3Array = shirt._welded_positions
	var p_rest: PackedVector3Array = pants._welded_positions
	var top := -1e9
	for v in p_rest:
		top = maxf(top, v.y)
	var axis := Vector3.ZERO
	var n_axis := 0
	for v in p_rest:
		if v.y > top - 0.05:
			axis += v
			n_axis += 1
	axis /= maxf(n_axis, 1)
	var worst: Array = []
	var inside := 0
	var count := 0
	for i in s_rest.size():
		if s_rest[i].y > top + 0.005:
			continue
		var s_now := Vector3(sp[i * 4], sp[i * 4 + 1], sp[i * 4 + 2])
		var best := -1
		var best_d := 1e9
		for j in p_rest.size():
			if p_rest[j].y < top - 0.12:
				continue
			var p_now := Vector3(pp[j * 4], pp[j * 4 + 1], pp[j * 4 + 2])
			var d := p_now.distance_squared_to(s_now)
			if d < best_d:
				best_d = d
				best = j
		var p_now := Vector3(pp[best * 4], pp[best * 4 + 1], pp[best * 4 + 2])
		var out := Vector3(s_now.x - axis.x, 0.0, s_now.z - axis.z).normalized()
		var gap: float = (s_now - p_now).dot(out)
		var s_move: float = (s_now - s_rest[i]).dot(out)
		var p_move: float = (p_now - p_rest[best]).dot(out)
		count += 1
		if gap < 0.0:
			inside += 1
		worst.append([gap, s_rest[i], s_move, p_move])
	if not _rest_done.has(shirt.get_instance_id()):
		_rest_done[shirt.get_instance_id()] = true
		# the same at rest, from the garments' own shapes: where the shirt is built inside the trousers
		var rest_inside: Array = []
		for i in s_rest.size():
			if s_rest[i].y > top + 0.005:
				continue
			var best := 0
			var best_d := 1e9
			for j in p_rest.size():
				var d := p_rest[j].distance_squared_to(s_rest[i])
				if d < best_d:
					best_d = d
					best = j
			var out := Vector3(s_rest[i].x - axis.x, 0.0, s_rest[i].z - axis.z).normalized()
			var gap: float = (s_rest[i] - p_rest[best]).dot(out)
			if gap < 0.002:
				rest_inside.append("(%.3f %.3f %.3f) %.4f" % [s_rest[i].x, s_rest[i].y, s_rest[i].z, gap])
		print("CLOTH_OVERLAP rest: trousers top y %.3f axis %s, shirt particles closer than 2 mm or inside: %d  %s" % [top, axis, rest_inside.size(), rest_inside.slice(0, 30)])
	worst.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	print("CLOTH_OVERLAP frame ", Engine.get_process_frames(), " shirt particles over the trousers ", count, " inside ", inside)
	for k in mini(4, worst.size()):
		print("CLOTH_OVERLAP   gap %.4f at rest %s  shirt moved %+.4f out, trousers %+.4f out" % [worst[k][0], worst[k][1], worst[k][2], worst[k][3]])




## (debug) the trousers' buckle particles (front middle of the belt, at rest): where the simulation has them now
static func buckle(pants: GPUClothSolver) -> void:
	var pp: PackedFloat32Array = pants._rd.buffer_get_data(pants._positions_buffer).to_float32_array()
	var rest: PackedVector3Array = pants._welded_positions
	var top := -1e9
	for v in rest:
		top = maxf(top, v.y)
	var shown := 0
	var far := 0
	for i in rest.size():
		if absf(rest[i].x) < 0.03 and rest[i].z > 0.05 and rest[i].y > top - 0.05:
			var now := Vector3(pp[i * 4], pp[i * 4 + 1], pp[i * 4 + 2])
			if now.distance_to(rest[i]) > 0.02:
				far += 1
			if shown < 6:
				print("CLOTH_BUCKLE particle %d rest %s now %s" % [i, rest[i], now])
				shown += 1
	print("CLOTH_BUCKLE particles more than 2 cm from rest: ", far, " particles ", rest.size(), " render verts ", pants._render_vert_count)


## (debug) the shirt's back hem: the particles that moved furthest in (toward the body's axis) from their rest place
static func back_hem(shirt: GPUClothSolver) -> void:
	var sp: PackedFloat32Array = shirt._rd.buffer_get_data(shirt._positions_buffer).to_float32_array()
	var rest: PackedVector3Array = shirt._welded_positions
	var rows: Array = []
	for i in rest.size():
		if rest[i].y < 0.88 or rest[i].y > 1.0 or rest[i].z > -0.02 or absf(rest[i].x) > 0.2:
			continue
		var now := Vector3(sp[i * 4], sp[i * 4 + 1], sp[i * 4 + 2])
		var out := Vector3(rest[i].x, 0.0, rest[i].z - 0.02).normalized()
		rows.append([(now - rest[i]).dot(out), rest[i], now - rest[i]])
	rows.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	print("CLOTH_BACKHEM particles ", rows.size())
	for k in mini(10, rows.size()):
		print("CLOTH_BACKHEM   in %+.4f rest (%.3f %.3f %.3f) move (%.4f %.4f %.4f)" % [rows[k][0], rows[k][1].x, rows[k][1].y, rows[k][1].z, rows[k][2].x, rows[k][2].y, rows[k][2].z])


static var _leg_points: PackedVector3Array = PackedVector3Array()
static var _leg_normals: PackedVector3Array = PackedVector3Array()
static var _leg_worst: float = 1e9
static var _leg_most: int = 0


## (debug, --cloth-legs in the body lab) the trousers below the knee against the body's own surface (the body lab's rig stays in its rest pose, so
## the skeleton's space is the body's): for each particle the nearest body vertex, and how far the particle is outside along that vertex's normal
static func legs(pants: GPUClothSolver, body: MeshInstance3D) -> void:
	if _leg_points.is_empty():
		var arrays: Array = (body.mesh as ArrayMesh).surface_get_arrays(0)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		for i in vertices.size():
			if vertices[i].y < 0.55 and vertices[i].y > 0.12:
				_leg_points.append(vertices[i])
				_leg_normals.append(normals[i])
	var pp: PackedFloat32Array = pants._rd.buffer_get_data(pants._positions_buffer).to_float32_array()
	var rest: PackedVector3Array = pants._welded_positions
	var inside := 0
	var worst := 1e9
	var worst_at := Vector3.ZERO
	for i in rest.size():
		if rest[i].y > 0.5 or rest[i].y < 0.15:
			continue
		var p := Vector3(pp[i * 4], pp[i * 4 + 1], pp[i * 4 + 2])
		var best := 0
		var best_d := 1e9
		for j in _leg_points.size():
			var d := _leg_points[j].distance_squared_to(p)
			if d < best_d:
				best_d = d
				best = j
		var out: float = (p - _leg_points[best]).dot(_leg_normals[best])
		if out < 0.0:
			inside += 1
		if out < worst:
			worst = out
			worst_at = rest[i]
	_leg_worst = minf(_leg_worst, worst)
	_leg_most = maxi(_leg_most, inside)
	print("CLOTH_LEGS frame %d inside %d closest %+.4f at %s   (run: most inside %d, closest %+.4f)" % [Engine.get_process_frames(), inside, worst, worst_at, _leg_most, _leg_worst])
