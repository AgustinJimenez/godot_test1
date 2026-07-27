class_name OutfitFitGeometry
extends RefCounted
## Pure geometry queries shared by contact fitting and penetration visualization.

const BOUNDARY_POSITION_EPSILON := 0.0001


static func solid_colors(count: int, color: Color) -> PackedColorArray:
	var colors := PackedColorArray()
	colors.resize(count)
	colors.fill(color)
	return colors


static func vertex_regions(
	mesh_instance: MeshInstance3D,
	arrays: Array,
) -> PackedStringArray:
	var vertices := arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array
	var bones := arrays[Mesh.ARRAY_BONES] as PackedInt32Array
	var weights := arrays[Mesh.ARRAY_WEIGHTS] as PackedFloat32Array
	var result := PackedStringArray()
	result.resize(vertices.size())
	var skeleton := mesh_instance.get_node_or_null(mesh_instance.skeleton) as Skeleton3D
	var skin := mesh_instance.skin
	if skeleton == null or skin == null or bones.is_empty() or weights.is_empty():
		return result
	var influences := bones.size() / vertices.size()
	for vertex_index in vertices.size():
		var best_weight := -1.0
		var best_bind := -1
		for influence in influences:
			var array_index := vertex_index * influences + influence
			if weights[array_index] > best_weight:
				best_weight = weights[array_index]
				best_bind = bones[array_index]
		if best_bind < 0 or best_bind >= skin.get_bind_count():
			continue
		var bone_index := skin.get_bind_bone(best_bind)
		var bone_name := skin.get_bind_name(best_bind)
		if bone_index >= 0:
			bone_name = skeleton.get_bone_name(bone_index)
		result[vertex_index] = _bone_region(String(bone_name))
	return result


static func triangle_region(
	regions: PackedStringArray,
	indices: PackedInt32Array,
) -> String:
	var counts: Dictionary = {}
	for vertex_index in indices:
		var region := regions[vertex_index] if vertex_index < regions.size() else ""
		if not region.is_empty():
			counts[region] = int(counts.get(region, 0)) + 1
	var best_region := ""
	var best_count := 0
	for region_variant in counts:
		var count := int(counts[region_variant])
		if count > best_count:
			best_region = String(region_variant)
			best_count = count
	return best_region if best_count >= 2 or counts.size() == 1 else "mixed"


static func is_leg_surface(regions: PackedStringArray) -> bool:
	if regions.is_empty():
		return false
	var leg_vertices := 0
	for region in regions:
		if region == "left_leg" or region == "right_leg":
			leg_vertices += 1
	return leg_vertices > regions.size() / 2


static func clipping_error(
	signed_distance: float,
	clearance: float,
	intersects: bool,
	minimum_push: float,
) -> float:
	if intersects:
		return maxf(clearance - signed_distance, minimum_push)
	return clearance - signed_distance if signed_distance < 0.0 else 0.0


static func closest_body_projection(
	point: Vector3,
	body_triangles: Array[Dictionary],
	body_grid: Dictionary,
	cell_size: float,
	search_radius: float,
	body_normal_sign: float,
	required_region: String = "",
) -> Dictionary:
	var center_cell := grid_cell(point, cell_size)
	var maximum_ring := ceili(search_radius / cell_size)
	var tested: Dictionary = {}
	var best_distance_squared := INF
	var result: Dictionary = {}
	var first_occupied_ring := -1
	for ring in range(maximum_ring + 1):
		for x_offset in range(-ring, ring + 1):
			for y_offset in range(-ring, ring + 1):
				for z_offset in range(-ring, ring + 1):
					if maxi(
							absi(x_offset), maxi(absi(y_offset), absi(z_offset))) != ring:
						continue
					var candidates := body_grid.get(
							center_cell + Vector3i(x_offset, y_offset, z_offset),
							PackedInt32Array()) as PackedInt32Array
					for triangle_index in candidates:
						if tested.has(triangle_index):
							continue
						tested[triangle_index] = true
						var triangle: Dictionary = body_triangles[triangle_index]
						if not _region_matches(required_region, triangle.get("region", "")):
							continue
						var closest := closest_point_on_triangle(
								point, triangle["a"], triangle["b"], triangle["c"])
						var distance_squared := point.distance_squared_to(closest)
						var normal: Vector3 = triangle["normal"]
						if distance_squared >= best_distance_squared or normal.is_zero_approx():
							continue
						best_distance_squared = distance_squared
						result = {
							"position": closest,
							"normal": normal * body_normal_sign,
							"triangle": triangle_index,
						}
		if not result.is_empty() and first_occupied_ring < 0:
			first_occupied_ring = ring
		if first_occupied_ring >= 0 and ring >= first_occupied_ring + 1:
			break
	return result


static func outer_body_projection(
	point: Vector3,
	body_triangles: Array[Dictionary],
	body_grid: Dictionary,
	cell_size: float,
	search_radius: float,
	body_normal_sign: float,
	required_region: String = "",
) -> Dictionary:
	var nearest := closest_body_projection(
			point, body_triangles, body_grid, cell_size, search_radius,
			body_normal_sign, required_region)
	if nearest.is_empty():
		return nearest
	var normal: Vector3 = nearest["normal"]
	var start: Vector3 = nearest["position"] + normal * search_radius
	var finish: Vector3 = nearest["position"] - normal * search_radius
	var tested: Dictionary = {}
	var steps := maxi(1, ceili(start.distance_to(finish) / (cell_size * 0.5)))
	for step in range(steps + 1):
		var cell := grid_cell(start.lerp(finish, float(step) / steps), cell_size)
		for triangle_index in (
				body_grid.get(cell, PackedInt32Array()) as PackedInt32Array):
			tested[triangle_index] = true
	var best_distance_squared := INF
	var result: Dictionary = {}
	for triangle_index_variant in tested:
		var triangle_index := int(triangle_index_variant)
		var triangle: Dictionary = body_triangles[triangle_index]
		if not _region_matches(required_region, triangle.get("region", "")):
			continue
		var hit: Variant = Geometry3D.segment_intersects_triangle(
				start, finish, triangle["a"], triangle["b"], triangle["c"])
		if hit == null:
			continue
		var hit_position := hit as Vector3
		var distance_squared := start.distance_squared_to(hit_position)
		if distance_squared >= best_distance_squared:
			continue
		best_distance_squared = distance_squared
		result = {
			"position": hit_position,
			"normal": (triangle["normal"] as Vector3) * body_normal_sign,
			"triangle": triangle_index,
		}
	return result if not result.is_empty() else nearest


static func smooth_offsets(
	vertices: PackedVector3Array,
	indices: PackedInt32Array,
	offsets: PackedVector3Array,
	iterations: int,
	blend: float,
) -> PackedVector3Array:
	var neighbors: Array[Dictionary] = []
	neighbors.resize(vertices.size())
	for vertex_index in vertices.size():
		neighbors[vertex_index] = {}
	var triangle_count := indices.size() / 3 if not indices.is_empty() else vertices.size() / 3
	for triangle_index in triangle_count:
		var triangle := PackedInt32Array()
		triangle.resize(3)
		for corner in 3:
			triangle[corner] = (
					indices[triangle_index * 3 + corner]
					if not indices.is_empty() else triangle_index * 3 + corner)
		for corner in 3:
			var first := triangle[corner]
			var second := triangle[(corner + 1) % 3]
			neighbors[first][second] = true
			neighbors[second][first] = true
	var welded: Dictionary = {}
	for vertex_index in vertices.size():
		var key := _position_key(vertices[vertex_index])
		var members: Array = welded.get(key, [])
		for member_variant in members:
			var member := int(member_variant)
			neighbors[vertex_index][member] = true
			neighbors[member][vertex_index] = true
		members.append(vertex_index)
		welded[key] = members
	var current := offsets.duplicate()
	for _iteration in iterations:
		var next := current.duplicate()
		for vertex_index in current.size():
			if neighbors[vertex_index].is_empty():
				continue
			var average := Vector3.ZERO
			for neighbor_variant in neighbors[vertex_index]:
				average += current[int(neighbor_variant)]
			average /= neighbors[vertex_index].size()
			next[vertex_index] = current[vertex_index].lerp(average, blend)
		current = next
	return current


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
		var minimum_cell := grid_cell(bounds.position, cell_size)
		var maximum_cell := grid_cell(bounds.end, cell_size)
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


static func _bone_region(bone_name: String) -> String:
	var name := bone_name.to_lower()
	for token in ["thigh", "calf", "foot", "ball", "toe"]:
		if token in name:
			if name.ends_with("_l") or name.ends_with(".l"):
				return "left_leg"
			if name.ends_with("_r") or name.ends_with(".r"):
				return "right_leg"
	for token in ["upperarm", "lowerarm", "hand"]:
		if token in name:
			if name.ends_with("_l") or name.ends_with(".l"):
				return "left_arm"
			if name.ends_with("_r") or name.ends_with(".r"):
				return "right_arm"
	return "torso" if not name.is_empty() else ""


static func _region_matches(required: String, candidate: String) -> bool:
	return (
			required.is_empty() or candidate.is_empty() or candidate == "mixed"
			or required == candidate)


static func grid_cell(point: Vector3, size: float) -> Vector3i:
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
