class_name OutfitFitVisualization
extends RefCounted
## Body contact cache and temporary clipping-color mesh construction.
##
## Debug meshes are rebuilt previews. Imported body and garment ArrayMeshes remain untouched.

const FIT_GEOMETRY := preload("res://ui/outfit_fit/geometry.gd")

const BODY_DEBUG_COLOR := Color(0.9, 0.04, 0.04)
const CLOTH_DEBUG_COLOR := Color(0.03, 0.18, 0.95)
const CLIP_DEBUG_COLOR := Color(0.05, 0.95, 0.15)
const CLIP_SEARCH_RADIUS := 0.08


static func build_body_triangle_grid(
	body_mesh: MeshInstance3D,
	body_source_mesh: ArrayMesh,
	cell_size: float,
) -> Dictionary:
	var body_triangles: Array[Dictionary] = []
	var body_grid: Dictionary = {}
	var orientation_score := 0.0
	for surface_index in body_source_mesh.get_surface_count():
		var arrays := body_source_mesh.surface_get_arrays(surface_index)
		var vertices := FIT_GEOMETRY.skin_vertices_world(body_mesh, arrays)
		var regions := FIT_GEOMETRY.vertex_regions(body_mesh, arrays)
		var indices := arrays[Mesh.ARRAY_INDEX] as PackedInt32Array
		var triangle_count := (
				indices.size() / 3 if not indices.is_empty() else vertices.size() / 3)
		for triangle_index in triangle_count:
			var vertex_indices := PackedInt32Array()
			vertex_indices.resize(3)
			for corner in 3:
				vertex_indices[corner] = (
					indices[triangle_index * 3 + corner]
					if not indices.is_empty() else triangle_index * 3 + corner)
			var a := vertices[vertex_indices[0]]
			var b := vertices[vertex_indices[1]]
			var c := vertices[vertex_indices[2]]
			var bounds := AABB(a, Vector3.ZERO).expand(b).expand(c)
			var normal := (b - a).cross(c - a).normalized()
			orientation_score += a.dot(b.cross(c))
			var stored_index := body_triangles.size()
			body_triangles.append({
				"a": a,
				"b": b,
				"c": c,
				"normal": normal,
				"region": FIT_GEOMETRY.triangle_region(regions, vertex_indices),
				"surface": surface_index,
				"surface_triangle": triangle_index,
				"vertices": vertex_indices,
			})
			var minimum_cell := FIT_GEOMETRY.grid_cell(bounds.position, cell_size)
			var maximum_cell := FIT_GEOMETRY.grid_cell(bounds.end, cell_size)
			for x in range(minimum_cell.x, maximum_cell.x + 1):
				for y in range(minimum_cell.y, maximum_cell.y + 1):
					for z in range(minimum_cell.z, maximum_cell.z + 1):
						var cell := Vector3i(x, y, z)
						var bucket := body_grid.get(
								cell, PackedInt32Array()) as PackedInt32Array
						bucket.append(stored_index)
						body_grid[cell] = bucket
	return {
		"triangles": body_triangles,
		"grid": body_grid,
		"normal_sign": 1.0 if orientation_score >= 0.0 else -1.0,
	}


static func clipping_colors(
	world_vertices: PackedVector3Array,
	arrays: Array,
	component_indices: PackedInt32Array,
	body_triangles: Array,
	body_grid: Dictionary,
	cell_size: float,
	normal_sign: float,
	clipped_body_vertices: Dictionary,
	debug_body_vertices: Dictionary,
	clipped_body_triangles: Dictionary = {},
) -> PackedColorArray:
	var colors := PackedColorArray()
	colors.resize(world_vertices.size())
	colors.fill(
			CLOTH_DEBUG_COLOR if component_indices.is_empty() else Color.WHITE)
	var indices := (
		arrays[Mesh.ARRAY_INDEX] as PackedInt32Array
		if component_indices.is_empty() else component_indices)
	if not component_indices.is_empty():
		for vertex_index in component_indices:
			colors[vertex_index] = CLOTH_DEBUG_COLOR
	var intersections := FIT_GEOMETRY.find_intersections(
			world_vertices,
			indices,
			body_triangles,
			body_grid,
			cell_size,
			normal_sign)
	for triangle_index in (intersections["body_triangles"] as Dictionary):
		_mark_body_triangle(
				triangle_index,
				body_triangles,
				clipped_body_vertices,
				debug_body_vertices,
				clipped_body_triangles)
	# Also catch a garment patch wholly embedded without crossing a body triangle.
	if component_indices.is_empty():
		for point in world_vertices:
			_mark_body_triangles_near_point(
					point, body_triangles, body_grid, cell_size, normal_sign,
					clipped_body_vertices, debug_body_vertices, clipped_body_triangles)
	else:
		var visited: Dictionary = {}
		for vertex_index in component_indices:
			if visited.has(vertex_index):
				continue
			visited[vertex_index] = true
			_mark_body_triangles_near_point(
					world_vertices[vertex_index], body_triangles, body_grid,
					cell_size,
					normal_sign,
					clipped_body_vertices,
					debug_body_vertices,
					clipped_body_triangles)
	return colors


static func apply_body_clipping_colors(
	body_mesh: MeshInstance3D,
	body_source_mesh: ArrayMesh,
	clipped_body_vertices: Dictionary,
	debug_body_vertices: Dictionary,
	filter_to_selection: bool,
) -> void:
	var rebuilt := ArrayMesh.new()
	for blend_shape_index in body_source_mesh.get_blend_shape_count():
		rebuilt.add_blend_shape(body_source_mesh.get_blend_shape_name(blend_shape_index))
	rebuilt.blend_shape_mode = body_source_mesh.blend_shape_mode
	for surface_index in body_source_mesh.get_surface_count():
		var arrays := body_source_mesh.surface_get_arrays(surface_index)
		var vertices := arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array
		var colors := PackedColorArray()
		colors.resize(vertices.size())
		var clipped: Dictionary = clipped_body_vertices.get(surface_index, {})
		var affected: Dictionary = debug_body_vertices.get(surface_index, {})
		for vertex_index in vertices.size():
			if clipped.has(vertex_index):
				colors[vertex_index] = CLIP_DEBUG_COLOR
			elif not filter_to_selection or affected.has(vertex_index):
				colors[vertex_index] = BODY_DEBUG_COLOR
			else:
				colors[vertex_index] = Color.WHITE
		arrays[Mesh.ARRAY_COLOR] = colors
		var format := body_source_mesh.surface_get_format(surface_index)
		format |= Mesh.ARRAY_FORMAT_COLOR
		rebuilt.add_surface_from_arrays(
				body_source_mesh.surface_get_primitive_type(surface_index),
				arrays,
				body_source_mesh.surface_get_blend_shape_arrays(surface_index),
				{},
				format)
		var material := body_source_mesh.surface_get_material(surface_index)
		if filter_to_selection and material is BaseMaterial3D:
			material = material.duplicate()
			(material as BaseMaterial3D).vertex_color_use_as_albedo = true
		rebuilt.surface_set_material(surface_index, material)
		rebuilt.surface_set_name(
				surface_index, body_source_mesh.surface_get_name(surface_index))
	body_mesh.mesh = rebuilt


static func apply_body_occlusion(
	body_mesh: MeshInstance3D,
	body_source_mesh: ArrayMesh,
	occluded_body_triangles: Dictionary,
) -> void:
	if occluded_body_triangles.is_empty():
		body_mesh.mesh = body_source_mesh
		return
	var rebuilt := ArrayMesh.new()
	for blend_shape_index in body_source_mesh.get_blend_shape_count():
		rebuilt.add_blend_shape(body_source_mesh.get_blend_shape_name(blend_shape_index))
	rebuilt.blend_shape_mode = body_source_mesh.blend_shape_mode
	for surface_index in body_source_mesh.get_surface_count():
		var arrays := body_source_mesh.surface_get_arrays(surface_index)
		var source_indices := arrays[Mesh.ARRAY_INDEX] as PackedInt32Array
		var vertices := arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array
		var triangle_count := (
				source_indices.size() / 3
				if not source_indices.is_empty() else vertices.size() / 3)
		var hidden := occluded_body_triangles.get(surface_index, {}) as Dictionary
		var visible_indices := PackedInt32Array()
		for triangle_index in triangle_count:
			if hidden.has(triangle_index):
				continue
			for corner in 3:
				visible_indices.append(
						source_indices[triangle_index * 3 + corner]
						if not source_indices.is_empty()
						else triangle_index * 3 + corner)
		arrays[Mesh.ARRAY_INDEX] = visible_indices
		var format := body_source_mesh.surface_get_format(surface_index)
		format |= Mesh.ARRAY_FORMAT_INDEX
		rebuilt.add_surface_from_arrays(
				body_source_mesh.surface_get_primitive_type(surface_index),
				arrays,
				body_source_mesh.surface_get_blend_shape_arrays(surface_index),
				{},
				format)
		rebuilt.surface_set_material(
				surface_index, body_source_mesh.surface_get_material(surface_index))
		rebuilt.surface_set_name(
				surface_index, body_source_mesh.surface_get_name(surface_index))
	body_mesh.mesh = rebuilt


static func _mark_body_triangles_near_point(
	point: Vector3,
	body_triangles: Array,
	body_grid: Dictionary,
	cell_size: float,
	normal_sign: float,
	clipped_body_vertices: Dictionary,
	debug_body_vertices: Dictionary,
	clipped_body_triangles: Dictionary,
) -> void:
	var bounds := AABB(point, Vector3.ZERO).grow(CLIP_SEARCH_RADIUS)
	var minimum_cell := FIT_GEOMETRY.grid_cell(bounds.position, cell_size)
	var maximum_cell := FIT_GEOMETRY.grid_cell(bounds.end, cell_size)
	var tested: Dictionary = {}
	var best_distance_squared := INF
	var best_triangle := -1
	var best_closest := Vector3.ZERO
	for x in range(minimum_cell.x, maximum_cell.x + 1):
		for y in range(minimum_cell.y, maximum_cell.y + 1):
			for z in range(minimum_cell.z, maximum_cell.z + 1):
				var triangle_indices := body_grid.get(
						Vector3i(x, y, z), PackedInt32Array()) as PackedInt32Array
				for triangle_index in triangle_indices:
					if tested.has(triangle_index):
						continue
					tested[triangle_index] = true
					var body: Dictionary = body_triangles[triangle_index]
					var closest := FIT_GEOMETRY.closest_point_on_triangle(
							point, body["a"], body["b"], body["c"])
					var distance_squared := point.distance_squared_to(closest)
					if distance_squared < best_distance_squared:
						best_distance_squared = distance_squared
						best_triangle = triangle_index
						best_closest = closest
	if best_triangle < 0:
		return
	var triangle: Dictionary = body_triangles[best_triangle]
	_mark_body_debug_triangle(best_triangle, body_triangles, debug_body_vertices)
	var outward_normal: Vector3 = triangle["normal"] * normal_sign
	if (point - best_closest).dot(outward_normal) < 0.0:
		_mark_body_triangle(
				best_triangle,
				body_triangles,
				clipped_body_vertices,
				debug_body_vertices,
				clipped_body_triangles)


static func _mark_body_triangle(
	triangle_index: int,
	body_triangles: Array,
	clipped_body_vertices: Dictionary,
	debug_body_vertices: Dictionary,
	clipped_body_triangles: Dictionary,
) -> void:
	_mark_body_debug_triangle(triangle_index, body_triangles, debug_body_vertices)
	var triangle: Dictionary = body_triangles[triangle_index]
	var surface_index: int = triangle["surface"]
	if not clipped_body_triangles.has(surface_index):
		clipped_body_triangles[surface_index] = {}
	var marked_triangles := clipped_body_triangles[surface_index] as Dictionary
	marked_triangles[int(triangle["surface_triangle"])] = true
	if not clipped_body_vertices.has(surface_index):
		clipped_body_vertices[surface_index] = {}
	var marked: Dictionary = clipped_body_vertices[surface_index]
	for vertex_index in triangle["vertices"]:
		marked[vertex_index] = true


static func _mark_body_debug_triangle(
	triangle_index: int,
	body_triangles: Array,
	debug_body_vertices: Dictionary,
) -> void:
	var triangle: Dictionary = body_triangles[triangle_index]
	var surface_index: int = triangle["surface"]
	if not debug_body_vertices.has(surface_index):
		debug_body_vertices[surface_index] = {}
	var marked: Dictionary = debug_body_vertices[surface_index]
	for vertex_index in triangle["vertices"]:
		marked[vertex_index] = true
