class_name ClothOverlapProbe
extends RefCounted
## (debug, --cloth-overlap in the rig and body labs; call on the render thread) where the shirt covers the trousers: for every shirt particle below the trousers' top, the nearest trouser particle; how
## far the shirt is outside it (along the horizontal direction from the body's axis), and how far each moved in or out from its rest place
static var _rest_done: Dictionary = {}
static var last_inside: int = -1   # (count_inside's result, read by the checks)
static var last_worst: String = ""   # (and where the deepest point was)


## The garments of an outfit, inside out (each solver carries its garment's recipe as meta, ClothSetup).
static func _by_layer(solvers: Array) -> Array:
	var layered: Array = solvers.filter(func(s: Node) -> bool: return is_instance_valid(s) and s.has_meta(&"garment"))
	layered.sort_custom(func(a: Node, b: Node) -> bool: return int(a.get_meta(&"garment")["layer"]) < int(b.get_meta(&"garment")["layer"]))
	return layered


## Every pair of adjacent layers measured (printed).
static func measure_layers(solvers: Array) -> void:
	var layered := _by_layer(solvers)
	for k in range(1, layered.size()):
		measure(layered[k], layered[k - 1])


## The points of every garment inside the garment under it, all pairs together, into last_inside (for the checks): measured against the lower
## garment's own triangles as they are now (the nearest point on its surface, signed by the face's outward side). The nearest-particle measure of
## measure() misread the shirt's rolled hem lip over the belly as inside the trousers at the slider extremes.
static func count_inside(solvers: Array) -> void:
	var layered := _by_layer(solvers)
	var total := 0
	last_worst = ""
	for k in range(1, layered.size()):
		total += _surface_inside(layered[k], layered[k - 1])
	last_inside = total


static func _surface_inside(upper: GPUClothSolver, lower: GPUClothSolver) -> int:
	var up: PackedFloat32Array = upper._rd.buffer_get_data(upper._positions_buffer).to_float32_array()
	var lp: PackedFloat32Array = lower._rd.buffer_get_data(lower._positions_buffer).to_float32_array()
	var lower_points := PackedVector3Array()
	lower_points.resize(lp.size() / 4)
	var top := -1e9
	var centre := Vector3.ZERO
	for i in lower_points.size():
		lower_points[i] = Vector3(lp[i * 4], lp[i * 4 + 1], lp[i * 4 + 2])
		top = maxf(top, lower_points[i].y)
		centre += lower_points[i]
	centre /= maxf(lower_points.size(), 1)
	# the lower garment's triangles near its top (where an upper layer can cover it), in particle indices
	var tris: Array = []
	for t in lower._src_indices.size() / 3:
		var a: int = lower._original_to_welded[lower._src_indices[t * 3]]
		var b: int = lower._original_to_welded[lower._src_indices[t * 3 + 1]]
		var c: int = lower._original_to_welded[lower._src_indices[t * 3 + 2]]
		if lower_points[a].y > top - 0.2:
			tris.append(Vector3i(a, b, c))
	var inside := 0
	var worst := 0.0
	for i in up.size() / 4:
		var p := Vector3(up[i * 4], up[i * 4 + 1], up[i * 4 + 2])
		if p.y > top - 0.015:
			continue   # (from 1.5 cm under the lower garment's top: at its edge the nearest feature is the edge itself and in / out has no sign)
		var best_d := 1e9
		var best_gap := 1e9
		var best_q := Vector3.ZERO
		for tri: Vector3i in tris:
			var a: Vector3 = lower_points[tri.x]
			if a.distance_squared_to(p) > 0.01:   # (more than 10 cm away: not the nearest)
				continue
			var b: Vector3 = lower_points[tri.y]
			var c: Vector3 = lower_points[tri.z]
			var q := _closest_on_triangle(p, a, b, c)
			var d := q.distance_squared_to(p)
			if d < best_d:
				var n := (b - a).cross(c - a)
				if n.length_squared() < 1e-14:
					continue
				n = -n.normalized()   # (our garments' winding gives inward normals: the solver's flip_normals is on for them)
				if absf(n.y) > 0.7:
					continue   # (the rolled lip on top of a waistband faces up: "under" it is not inside the garment; the sides decide)
				best_d = d
				best_gap = (p - q).dot(n)
				best_q = q
		if best_gap < -0.001:   # (1 mm: the sleeve checks' tolerance; the lab's particle surface and Blender's disagree by that much at a slope)
			inside += 1
			if best_gap < worst:
				worst = best_gap
				last_worst = "%s %.1f mm inside %s at %s (rest %s); the lower layer's top %.3f, nearest on it %s" % [upper.name, -best_gap * 1000.0, lower.name, p, upper._welded_positions[i], top, best_q]
	return inside


static func _closest_on_triangle(p: Vector3, a: Vector3, b: Vector3, c: Vector3) -> Vector3:
	# (Ericson, Real-Time Collision Detection 5.1.5)
	var ab := b - a
	var ac := c - a
	var ap := p - a
	var d1 := ab.dot(ap)
	var d2 := ac.dot(ap)
	if d1 <= 0.0 and d2 <= 0.0:
		return a
	var bp := p - b
	var d3 := ab.dot(bp)
	var d4 := ac.dot(bp)
	if d3 >= 0.0 and d4 <= d3:
		return b
	var vc := d1 * d4 - d3 * d2
	if vc <= 0.0 and d1 >= 0.0 and d3 <= 0.0:
		return a + ab * (d1 / (d1 - d3))
	var cp := p - c
	var d5 := ab.dot(cp)
	var d6 := ac.dot(cp)
	if d6 >= 0.0 and d5 <= d6:
		return c
	var vb := d5 * d2 - d1 * d6
	if vb <= 0.0 and d2 >= 0.0 and d6 <= 0.0:
		return a + ac * (d2 / (d2 - d6))
	var va := d3 * d6 - d5 * d4
	if va <= 0.0 and (d4 - d3) >= 0.0 and (d5 - d6) >= 0.0:
		return b + (c - b) * ((d4 - d3) / ((d4 - d3) + (d5 - d6)))
	var denom := 1.0 / (va + vb + vc)
	return a + ab * (vb * denom) + ac * (vc * denom)


## `shirt`: the upper garment, `pants`: the one under it. Returns how many of the upper one's points are inside the lower one.
static func measure(shirt: GPUClothSolver, pants: GPUClothSolver, quiet := false) -> int:
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
	if quiet:
		return inside
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
	return inside




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
