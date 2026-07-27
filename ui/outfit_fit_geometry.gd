class_name OutfitFitGeometry
extends RefCounted
## Pure geometry queries shared by contact fitting and penetration visualization.

const BOUNDARY_POSITION_EPSILON := 0.0001


static func solid_colors(count: int, color: Color) -> PackedColorArray:
	var colors := PackedColorArray()
	colors.resize(count)
	colors.fill(color)
	return colors


static func closest_point_on_triangle(
	point: Vector3,
	a: Vector3,
	b: Vector3,
	c: Vector3,
) -> Vector3:
	var ab := b - a
	var ac := c - a
	var ap := point - a
	var d1 := ab.dot(ap)
	var d2 := ac.dot(ap)
	var bp := point - b
	var d3 := ab.dot(bp)
	var d4 := ac.dot(bp)
	var vc := d1 * d4 - d3 * d2
	var cp := point - c
	var d5 := ab.dot(cp)
	var d6 := ac.dot(cp)
	var vb := d5 * d2 - d1 * d6
	var va := d3 * d6 - d5 * d4
	if d1 <= 0.0 and d2 <= 0.0:
		return a
	if d3 >= 0.0 and d4 <= d3:
		return b
	if vc <= 0.0 and d1 >= 0.0 and d3 <= 0.0:
		return a + ab * (d1 / (d1 - d3))
	if d6 >= 0.0 and d5 <= d6:
		return c
	if vb <= 0.0 and d2 >= 0.0 and d6 <= 0.0:
		return a + ac * (d2 / (d2 - d6))
	if va <= 0.0 and d4 - d3 >= 0.0 and d5 - d6 >= 0.0:
		return b + (c - b) * ((d4 - d3) / ((d4 - d3) + (d5 - d6)))
	var denominator := 1.0 / (va + vb + vc)
	return a + ab * (vb * denominator) + ac * (vc * denominator)


static func triangles_intersect(
	a: Vector3,
	b: Vector3,
	c: Vector3,
	d: Vector3,
	e: Vector3,
	f: Vector3,
) -> bool:
	return (
		Geometry3D.segment_intersects_triangle(a, b, d, e, f) != null
		or Geometry3D.segment_intersects_triangle(b, c, d, e, f) != null
		or Geometry3D.segment_intersects_triangle(c, a, d, e, f) != null
		or Geometry3D.segment_intersects_triangle(d, e, a, b, c) != null
		or Geometry3D.segment_intersects_triangle(e, f, a, b, c) != null
		or Geometry3D.segment_intersects_triangle(f, d, a, b, c) != null)


static func find_intersections(
	world_vertices: PackedVector3Array,
	indices: PackedInt32Array,
	body_triangles: Array[Dictionary],
	body_grid: Dictionary,
	cell_size: float,
	body_normal_sign: float,
) -> Dictionary:
	var cloth_vertices: Dictionary = {}
	var cloth_normals: Dictionary = {}
	var body_indices: Dictionary = {}
	var boundary_vertices := _boundary_vertices(world_vertices, indices)
	var triangle_count := (
			indices.size() / 3 if not indices.is_empty() else world_vertices.size() / 3)
	for triangle_index in triangle_count:
		var cloth_indices := PackedInt32Array()
		cloth_indices.resize(3)
		for corner in 3:
			cloth_indices[corner] = (
					indices[triangle_index * 3 + corner]
					if not indices.is_empty() else triangle_index * 3 + corner)
		# A triangle made entirely from a real open rim belongs to an intentional
		# collar/cuff/tear opening. Triangles merely touching that rim still need
		# collision checks; skipping them created an unchecked band around openings.
		if (boundary_vertices.has(cloth_indices[0])
				and boundary_vertices.has(cloth_indices[1])
				and boundary_vertices.has(cloth_indices[2])):
			continue
		var a := world_vertices[cloth_indices[0]]
		var b := world_vertices[cloth_indices[1]]
		var c := world_vertices[cloth_indices[2]]
		var bounds := AABB(a, Vector3.ZERO).expand(b).expand(c)
		var minimum_cell := _cell(bounds.position, cell_size)
		var maximum_cell := _cell(bounds.end, cell_size)
		var tested: Dictionary = {}
		for x in range(minimum_cell.x, maximum_cell.x + 1):
			for y in range(minimum_cell.y, maximum_cell.y + 1):
				for z in range(minimum_cell.z, maximum_cell.z + 1):
					var candidates := body_grid.get(
							Vector3i(x, y, z), PackedInt32Array()) as PackedInt32Array
					for body_index in candidates:
						if tested.has(body_index):
							continue
						tested[body_index] = true
						var body: Dictionary = body_triangles[body_index]
						if not triangles_intersect(
								a, b, c, body["a"], body["b"], body["c"]):
							continue
						body_indices[body_index] = true
						var normal: Vector3 = body["normal"] * body_normal_sign
						for vertex_index in cloth_indices:
							cloth_vertices[vertex_index] = true
							cloth_normals[vertex_index] = (
									cloth_normals.get(vertex_index, Vector3.ZERO) as Vector3
									) + normal
	return {
		"cloth_vertices": cloth_vertices,
		"cloth_normals": cloth_normals,
		"body_triangles": body_indices,
	}


static func _boundary_vertices(
	vertices: PackedVector3Array,
	indices: PackedInt32Array,
) -> Dictionary:
	var edge_counts: Dictionary = {}
	var edge_vertices: Dictionary = {}
	for triangle_start in range(0, indices.size(), 3):
		for corner in 3:
			var first := indices[triangle_start + corner]
			var second := indices[triangle_start + (corner + 1) % 3]
			var first_position := _position_key(vertices[first])
			var second_position := _position_key(vertices[second])
			if first_position == second_position:
				continue
			var edge := _edge_key(first_position, second_position)
			edge_counts[edge] = int(edge_counts.get(edge, 0)) + 1
			var members: Dictionary = edge_vertices.get(edge, {})
			members[first] = true
			members[second] = true
			edge_vertices[edge] = members
	var result: Dictionary = {}
	for edge_variant in edge_counts:
		if edge_counts[edge_variant] == 1:
			for vertex_index in (edge_vertices[edge_variant] as Dictionary):
				result[vertex_index] = true
	return result


static func _position_key(position: Vector3) -> Vector3i:
	return Vector3i(
			roundi(position.x / BOUNDARY_POSITION_EPSILON),
			roundi(position.y / BOUNDARY_POSITION_EPSILON),
			roundi(position.z / BOUNDARY_POSITION_EPSILON))


static func _edge_key(first: Vector3i, second: Vector3i) -> String:
	var first_text := "%d,%d,%d" % [first.x, first.y, first.z]
	var second_text := "%d,%d,%d" % [second.x, second.y, second.z]
	return (
			first_text + "|" + second_text
			if first_text < second_text
			else second_text + "|" + first_text)


static func _cell(point: Vector3, size: float) -> Vector3i:
	return Vector3i(
			floori(point.x / size), floori(point.y / size), floori(point.z / size))


static func skin_vertices_world(
	mesh_instance: MeshInstance3D,
	arrays: Array,
) -> PackedVector3Array:
	var vertices := arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array
	var bones := arrays[Mesh.ARRAY_BONES] as PackedInt32Array
	var weights := arrays[Mesh.ARRAY_WEIGHTS] as PackedFloat32Array
	var skeleton := mesh_instance.get_node_or_null(mesh_instance.skeleton) as Skeleton3D
	var skin := mesh_instance.skin
	if (skeleton == null or skin == null or bones.is_empty() or weights.is_empty()
			or vertices.is_empty()):
		var unskinned := vertices.duplicate()
		for vertex_index in unskinned.size():
			unskinned[vertex_index] = mesh_instance.to_global(unskinned[vertex_index])
		return unskinned
	var influences := bones.size() / vertices.size()
	var bind_transforms: Array[Transform3D] = []
	var valid_binds := PackedByteArray()
	bind_transforms.resize(skin.get_bind_count())
	valid_binds.resize(skin.get_bind_count())
	for bind_index in skin.get_bind_count():
		var bone_index := skin.get_bind_bone(bind_index)
		if bone_index < 0:
			bone_index = skeleton.find_bone(skin.get_bind_name(bind_index))
		if bone_index < 0:
			continue
		bind_transforms[bind_index] = (
				skeleton.global_transform
				* skeleton.get_bone_global_pose(bone_index)
				* skin.get_bind_pose(bind_index))
		valid_binds[bind_index] = 1
	var result := PackedVector3Array()
	result.resize(vertices.size())
	for vertex_index in vertices.size():
		var position := Vector3.ZERO
		var total_weight := 0.0
		var source_position := vertices[vertex_index]
		for influence in influences:
			var array_index := vertex_index * influences + influence
			var weight := weights[array_index]
			if weight <= 0.0:
				continue
			var bind_index := bones[array_index]
			if (bind_index < 0 or bind_index >= bind_transforms.size()
					or valid_binds[bind_index] == 0):
				continue
			position += (bind_transforms[bind_index] * source_position) * weight
			total_weight += weight
		result[vertex_index] = (
				position / total_weight
				if total_weight > 0.0 else mesh_instance.to_global(source_position))
	return result
