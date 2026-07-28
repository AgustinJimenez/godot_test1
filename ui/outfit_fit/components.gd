class_name OutfitFitComponents
extends RefCounted
## Catalogs disconnected topology pieces contained inside imported mesh surfaces.

const FIT_GEOMETRY := preload("res://ui/outfit_fit/geometry.gd")
const SKIN_MATERIAL_PATTERNS := ["regular_male", "regular_female"]
const THICK_SHAPE_SMOOTH_PASSES := 8
const THICK_SHAPE_SMOOTH_BLEND := 0.35


static func clothing_surfaces(mesh_states: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for mesh_key_variant in mesh_states:
		var mesh_key := String(mesh_key_variant)
		var state: Dictionary = mesh_states[mesh_key]
		var mesh_instance := state.get("node") as MeshInstance3D
		var node_name := ""
		if is_instance_valid(mesh_instance):
			node_name = String(mesh_instance.name).trim_suffix(":Mesh")
		var surfaces: Array = state["surfaces"]
		var cloth_count := 0
		for surface in surfaces:
			if surface.get("is_clothing", false):
				cloth_count += 1
		for surface_index in surfaces.size():
			var surface: Dictionary = surfaces[surface_index]
			if not surface.get("is_clothing", false):
				continue
			var material := surface.get("material") as Material
			var material_name := "" if material == null else material.resource_name
			var surface_name := surface.get("name", "") as String
			var display := node_name if not node_name.is_empty() else material_name
			if display.is_empty():
				display = "Surface %d" % surface_index
			if cloth_count > 1 and not surface_name.is_empty():
				display += " / " + surface_name
			result.append({
				"name": display,
				"mesh_key": mesh_key,
				"surface_index": surface_index,
			})
	return result


static func surface_components(
	mesh_states: Dictionary,
	mesh_key: String,
	surface_index: int,
) -> Array[Dictionary]:
	var surface := _surface(mesh_states, mesh_key, surface_index)
	if surface.is_empty():
		return []
	var state: Dictionary = mesh_states[mesh_key]
	var mesh_instance := state.get("node") as MeshInstance3D
	var node_name := (
			String(mesh_instance.name)
			if is_instance_valid(mesh_instance) else "")
	var components: Array = surface.get("components", [])
	var result: Array[Dictionary] = []
	var accessory_number := 1
	for component_index in components.size():
		var component := components[component_index] as Dictionary
		var vertex_indices := component["vertex_indices"] as PackedInt32Array
		var name := _display_name(
				node_name, surface, component_index, vertex_indices, accessory_number)
		if name.begins_with("Accessory"):
			accessory_number += 1
		result.append({
			"name": name,
			"component_index": component_index,
			"vertex_count": vertex_indices.size(),
		})
	return result


static func vertex_indices(
	mesh_states: Dictionary,
	mesh_key: String,
	surface_index: int,
	component_index: int,
) -> PackedInt32Array:
	var surface := _surface(mesh_states, mesh_key, surface_index)
	if surface.is_empty():
		return PackedInt32Array()
	var components: Array = surface.get("components", [])
	if component_index < 0 or component_index >= components.size():
		return PackedInt32Array()
	return components[component_index]["vertex_indices"] as PackedInt32Array


static func vertex_set(surface: Dictionary, component_index: int) -> Dictionary:
	if component_index < 0:
		return {}
	var components: Array = surface.get("components", [])
	if component_index >= components.size():
		return {}
	var result: Dictionary = {}
	for vertex_index in (
			components[component_index]["vertex_indices"] as PackedInt32Array):
		result[vertex_index] = true
	return result


static func is_clothing_surface(material: Material) -> bool:
	if material == null:
		return true
	var material_name := material.resource_name.to_lower()
	for pattern in SKIN_MATERIAL_PATTERNS:
		if pattern in material_name:
			return false
	return true


static func dot_material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.disable_receive_shadows = true
	return material


static func rebuild_preview_mesh(
	source: Mesh,
	surfaces: Array,
	mesh_key: String,
	clipping_colors: Dictionary,
	visualize_clipping: bool,
	isolation: Dictionary,
	deform_vertices: Callable,
) -> Dictionary:
	for surface_index in surfaces.size():
		var surface: Dictionary = surfaces[surface_index]
		var base_vertices: PackedVector3Array = surface["base_vertices"]
		var vertices := base_vertices.duplicate()
		if surface["is_clothing"]:
			vertices = deform_vertices.call(
					mesh_key, surface_index, base_vertices) as PackedVector3Array
		surface["vertices"] = vertices
		var arrays: Array = surface["arrays"].duplicate(true)
		arrays[Mesh.ARRAY_VERTEX] = vertices
		var has_clipping: bool = (
				visualize_clipping
				and surface["is_clothing"]
				and clipping_colors.has(surface_index))
		surface["_has_clipping"] = has_clipping
		if has_clipping:
			arrays[Mesh.ARRAY_COLOR] = clipping_colors[surface_index]
		else:
			# Rebuilds are cumulative; restore imported colors after debug rendering.
			arrays[Mesh.ARRAY_COLOR] = surface["source_colors"]
		surface["arrays"] = arrays
	var rebuilt := ArrayMesh.new()
	for blend_shape_index in source.get_blend_shape_count():
		rebuilt.add_blend_shape(source.get_blend_shape_name(blend_shape_index))
	rebuilt.blend_shape_mode = source.blend_shape_mode
	var rendered_surface_indices := PackedInt32Array()
	for surface_index in surfaces.size():
		if not isolation.is_empty() and (
				isolation["mesh_key"] != mesh_key
				or isolation["surface_index"] != surface_index):
			continue
		var surface: Dictionary = surfaces[surface_index]
		var format: int = surface["format"]
		if surface.get("_has_clipping", false):
			format |= Mesh.ARRAY_FORMAT_COLOR
		var render_arrays := surface["arrays"] as Array
		if not isolation.is_empty():
			render_arrays = render_arrays.duplicate(true)
			var components: Array = surface["components"]
			var component_index := isolation["component_index"] as int
			if component_index < 0 or component_index >= components.size():
				continue
			render_arrays[Mesh.ARRAY_INDEX] = (
					components[component_index]["indices"] as PackedInt32Array)
		rebuilt.add_surface_from_arrays(
				surface["primitive"], render_arrays, surface["blend_shapes"], {},
				format)
		var rendered_index := rebuilt.get_surface_count() - 1
		rebuilt.surface_set_material(rendered_index, surface["material"])
		rebuilt.surface_set_name(rendered_index, surface["name"])
		rendered_surface_indices.append(surface_index)
	rebuilt.set_meta(&"source_surface_indices", rendered_surface_indices)
	return {
		"mesh": rebuilt,
		"surface_indices": rendered_surface_indices,
	}


static func source_surface_index(mesh: Mesh, rendered_surface_index: int) -> int:
	var rendered := mesh.get_meta(
			&"source_surface_indices", PackedInt32Array()) as PackedInt32Array
	if rendered_surface_index < 0 or rendered_surface_index >= rendered.size():
		return rendered_surface_index
	return rendered[rendered_surface_index]


static func synchronize_auto_offset_seams(
	mesh_states: Dictionary,
	auto_surface_offsets: Dictionary,
	filter_mesh: String = "",
	filter_surface: int = -1,
) -> int:
	var synchronized := 0
	for mesh_key_variant in mesh_states:
		var mesh_key := String(mesh_key_variant)
		if not filter_mesh.is_empty() and mesh_key != filter_mesh:
			continue
		var state: Dictionary = mesh_states[mesh_key]
		var surfaces: Array = state["surfaces"]
		var mesh_offsets := auto_surface_offsets[mesh_key] as Array
		for surface_index in surfaces.size():
			if filter_surface >= 0 and surface_index != filter_surface:
				continue
			var surface: Dictionary = surfaces[surface_index]
			if not surface["is_clothing"]:
				continue
			var vertices := surface["base_vertices"] as PackedVector3Array
			var offsets := mesh_offsets[surface_index] as PackedVector3Array
			var groups: Dictionary = {}
			for vertex_index in vertices.size():
				var key := _position_key(vertices[vertex_index])
				var members: Array = groups.get(key, [])
				members.append(vertex_index)
				groups[key] = members
			for members_variant in groups.values():
				var members := members_variant as Array
				if members.size() < 2:
					continue
				var average := Vector3.ZERO
				for vertex_index in members:
					average += offsets[vertex_index]
				average /= float(members.size())
				for vertex_index in members:
					if not offsets[vertex_index].is_equal_approx(average):
						synchronized += 1
					offsets[vertex_index] = average
			mesh_offsets[surface_index] = offsets
		auto_surface_offsets[mesh_key] = mesh_offsets
	return synchronized


static func synchronize_auto_offset_constraints(
	mesh_states: Dictionary,
	auto_surface_offsets: Dictionary,
	filter_mesh: String = "",
	filter_surface: int = -1,
) -> int:
	var synchronized := synchronize_auto_offset_seams(
			mesh_states, auto_surface_offsets, filter_mesh, filter_surface)
	synchronized += _synchronize_auto_offset_thickness(
			mesh_states, auto_surface_offsets, filter_mesh, filter_surface)
	synchronized += synchronize_auto_offset_seams(
			mesh_states, auto_surface_offsets, filter_mesh, filter_surface)
	return synchronized


static func _synchronize_auto_offset_thickness(
	mesh_states: Dictionary,
	auto_surface_offsets: Dictionary,
	filter_mesh: String,
	filter_surface: int,
) -> int:
	var synchronized := 0
	for mesh_key_variant in mesh_states:
		var mesh_key := String(mesh_key_variant)
		if not filter_mesh.is_empty() and mesh_key != filter_mesh:
			continue
		var state: Dictionary = mesh_states[mesh_key]
		var surfaces: Array = state["surfaces"]
		var mesh_offsets := auto_surface_offsets[mesh_key] as Array
		for surface_index in surfaces.size():
			if filter_surface >= 0 and surface_index != filter_surface:
				continue
			var surface := surfaces[surface_index] as Dictionary
			if not surface["is_clothing"]:
				continue
			var offsets := mesh_offsets[surface_index] as PackedVector3Array
			for component_variant in surface["components"]:
				var component := component_variant as Dictionary
				var groups := _thickness_groups(surface, component)
				if groups.is_empty():
					continue
				synchronized += _average_group_offsets(offsets, groups)
				offsets = _smooth_component_offsets(component, offsets, groups)
				synchronized += _average_group_offsets(offsets, groups)
			mesh_offsets[surface_index] = offsets
		auto_surface_offsets[mesh_key] = mesh_offsets
	return synchronized


static func _average_group_offsets(offsets: PackedVector3Array, groups: Array) -> int:
	var synchronized := 0
	for group_variant in groups:
		var group := group_variant as PackedInt32Array
		var shared_offset := Vector3.ZERO
		for vertex_index in group:
			shared_offset += offsets[vertex_index]
		shared_offset /= float(group.size())
		for vertex_index in group:
			if not offsets[vertex_index].is_equal_approx(shared_offset):
				synchronized += 1
			offsets[vertex_index] = shared_offset
	return synchronized


static func _smooth_component_offsets(
	component: Dictionary,
	offsets: PackedVector3Array,
	groups: Array,
) -> PackedVector3Array:
	var neighbors := _component_neighbors(component) as Dictionary
	var component_vertices := component["vertex_indices"] as PackedInt32Array
	var current := offsets
	for _iteration in THICK_SHAPE_SMOOTH_PASSES:
		var next := current.duplicate()
		for vertex_index in component_vertices:
			var adjacent := neighbors.get(
					vertex_index, PackedInt32Array()) as PackedInt32Array
			if adjacent.is_empty():
				continue
			var average := Vector3.ZERO
			for neighbor_index in adjacent:
				average += current[neighbor_index]
			average /= float(adjacent.size())
			next[vertex_index] = current[vertex_index].lerp(
					average, THICK_SHAPE_SMOOTH_BLEND)
		current = next
		_average_group_offsets(current, groups)
	return current


static func _component_neighbors(component: Dictionary) -> Dictionary:
	if component.has("topology_neighbors"):
		return component["topology_neighbors"] as Dictionary
	var neighbor_sets: Dictionary = {}
	for triangle_start in range(
			0, (component["indices"] as PackedInt32Array).size(), 3):
		var indices := component["indices"] as PackedInt32Array
		for corner in 3:
			var first := indices[triangle_start + corner]
			var second := indices[triangle_start + (corner + 1) % 3]
			var first_neighbors: Dictionary = neighbor_sets.get(first, {})
			var second_neighbors: Dictionary = neighbor_sets.get(second, {})
			first_neighbors[second] = true
			second_neighbors[first] = true
			neighbor_sets[first] = first_neighbors
			neighbor_sets[second] = second_neighbors
	var result: Dictionary = {}
	for vertex_index_variant in neighbor_sets:
		var vertex_index := int(vertex_index_variant)
		var adjacent := PackedInt32Array()
		for neighbor_variant in (neighbor_sets[vertex_index] as Dictionary):
			adjacent.append(int(neighbor_variant))
		result[vertex_index] = adjacent
	component["topology_neighbors"] = result
	return result


static func _thickness_groups(
	surface: Dictionary,
	component: Dictionary,
) -> Array:
	if component.has("thickness_groups"):
		return component["thickness_groups"] as Array
	var vertices := surface["base_vertices"] as PackedVector3Array
	var indices := component["indices"] as PackedInt32Array
	var component_vertices := component["vertex_indices"] as PackedInt32Array
	var normals := PackedVector3Array()
	normals.resize(vertices.size())
	var edge_lengths := PackedFloat32Array()
	for triangle_start in range(0, indices.size(), 3):
		var triangle := PackedInt32Array([
			indices[triangle_start],
			indices[triangle_start + 1],
			indices[triangle_start + 2],
		])
		var face_normal := (
				vertices[triangle[1]] - vertices[triangle[0]]).cross(
				vertices[triangle[2]] - vertices[triangle[0]]).normalized()
		for corner in 3:
			normals[triangle[corner]] += face_normal
			var edge_length := vertices[triangle[corner]].distance_to(
					vertices[triangle[(corner + 1) % 3]])
			if edge_length > 0.0001:
				edge_lengths.append(edge_length)
	if edge_lengths.is_empty():
		component["thickness_groups"] = []
		return []
	edge_lengths.sort()
	var search_radius := edge_lengths[edge_lengths.size() / 2] * 3.0
	var cells: Dictionary = {}
	for vertex_index in component_vertices:
		normals[vertex_index] = normals[vertex_index].normalized()
		var cell := _spatial_cell(vertices[vertex_index], search_radius)
		var members: Array = cells.get(cell, [])
		members.append(vertex_index)
		cells[cell] = members
	var parents := PackedInt32Array()
	parents.resize(vertices.size())
	parents.fill(-1)
	for vertex_index in component_vertices:
		parents[vertex_index] = vertex_index
	var welded: Dictionary = {}
	for vertex_index in component_vertices:
		var key := _position_key(vertices[vertex_index])
		var members := welded.get(key, PackedInt32Array()) as PackedInt32Array
		if not members.is_empty():
			_union_vertices(parents, vertex_index, members[0])
		members.append(vertex_index)
		welded[key] = members
	var paired: Dictionary = {}
	for vertex_index in component_vertices:
		var position := vertices[vertex_index]
		var center_cell := _spatial_cell(position, search_radius)
		var nearest := -1
		var nearest_distance_squared := search_radius * search_radius
		for x_offset in range(-1, 2):
			for y_offset in range(-1, 2):
				for z_offset in range(-1, 2):
					var cell := center_cell + Vector3i(x_offset, y_offset, z_offset)
					for candidate_variant in cells.get(cell, []):
						var candidate := int(candidate_variant)
						var distance_squared := position.distance_squared_to(vertices[candidate])
						if (candidate == vertex_index
								or distance_squared <= 0.00000001
								or distance_squared >= nearest_distance_squared
								or normals[vertex_index].dot(normals[candidate]) > -0.35):
							continue
						nearest = candidate
						nearest_distance_squared = distance_squared
		if nearest >= 0:
			_union_vertices(parents, vertex_index, nearest)
			paired[vertex_index] = true
			paired[nearest] = true
	var minimum_pairs := maxi(8, ceili(component_vertices.size() * 0.8))
	if paired.size() < minimum_pairs:
		component["thickness_groups"] = []
		return []
	var paired_roots: Dictionary = {}
	for vertex_index_variant in paired:
		paired_roots[_find_vertex_root(parents, int(vertex_index_variant))] = true
	var grouped: Dictionary = {}
	for vertex_index in component_vertices:
		var root := _find_vertex_root(parents, vertex_index)
		if not paired_roots.has(root):
			continue
		var group := grouped.get(root, PackedInt32Array()) as PackedInt32Array
		group.append(vertex_index)
		grouped[root] = group
	var result: Array[PackedInt32Array] = []
	for group_variant in grouped.values():
		var group := group_variant as PackedInt32Array
		if group.size() > 1:
			result.append(group)
	component["thickness_groups"] = result
	return result


static func _spatial_cell(position: Vector3, cell_size: float) -> Vector3i:
	return Vector3i(
			floori(position.x / cell_size),
			floori(position.y / cell_size),
			floori(position.z / cell_size))


static func _find_vertex_root(parents: PackedInt32Array, vertex_index: int) -> int:
	var current := vertex_index
	while parents[current] != current:
		parents[current] = parents[parents[current]]
		current = parents[current]
	return current


static func _union_vertices(
	parents: PackedInt32Array,
	first: int,
	second: int,
) -> void:
	var first_root := _find_vertex_root(parents, first)
	var second_root := _find_vertex_root(parents, second)
	if first_root != second_root:
		parents[second_root] = first_root


static func center(
	mesh_states: Dictionary,
	mesh_key: String,
	surface_index: int,
	component_index: int,
) -> Vector3:
	var surface := _surface(mesh_states, mesh_key, surface_index)
	if surface.is_empty():
		return Vector3.ZERO
	var state: Dictionary = mesh_states[mesh_key]
	var mesh_instance := state["node"] as MeshInstance3D
	var world_vertices := FIT_GEOMETRY.skin_vertices_world(
			mesh_instance, surface["arrays"])
	var selected_indices := vertex_indices(
			mesh_states, mesh_key, surface_index, component_index)
	var center_point := Vector3.ZERO
	var count := 0
	if selected_indices.is_empty():
		for vertex in world_vertices:
			center_point += vertex
			count += 1
	else:
		for vertex_index in selected_indices:
			center_point += world_vertices[vertex_index]
			count += 1
	return center_point / float(count) if count > 0 else Vector3.ZERO


static func _position_key(position: Vector3) -> Vector3i:
	const WELD_EPSILON := 0.0001
	return Vector3i(
			roundi(position.x / WELD_EPSILON),
			roundi(position.y / WELD_EPSILON),
			roundi(position.z / WELD_EPSILON))


static func _surface(
	mesh_states: Dictionary,
	mesh_key: String,
	surface_index: int,
) -> Dictionary:
	var state: Dictionary = mesh_states.get(mesh_key, {})
	var surfaces: Array = state.get("surfaces", [])
	if surface_index < 0 or surface_index >= surfaces.size():
		return {}
	return surfaces[surface_index]


static func _display_name(
	node_name: String,
	surface: Dictionary,
	component_index: int,
	vertex_indices: PackedInt32Array,
	accessory_number: int,
) -> String:
	if "Male_Peasant_Body" in node_name:
		var vertices := surface["base_vertices"] as PackedVector3Array
		var bounds := AABB()
		var has_bounds := false
		for vertex_index in vertex_indices:
			var point_bounds := AABB(vertices[vertex_index], Vector3.ZERO)
			bounds = point_bounds if not has_bounds else bounds.merge(point_bounds)
			has_bounds = true
		if bounds.size.y > 0.3:
			return "Shirt"
		if vertex_indices.size() > 500:
			return "Leather belt"
		if vertex_indices.size() > 100:
			return "Metal buckle"
		return "Accessory %d" % accessory_number
	return "Piece %d (%d vertices)" % [
		component_index + 1, vertex_indices.size()]
