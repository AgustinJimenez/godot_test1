class_name OutfitFitComponents
extends RefCounted
## Catalogs disconnected topology pieces contained inside imported mesh surfaces.

const FIT_GEOMETRY := preload("res://ui/outfit_fit/geometry.gd")
const SKIN_MATERIAL_PATTERNS := ["regular_male", "regular_female"]
const THICK_SHAPE_SMOOTH_PASSES := 8
const THICK_SHAPE_SMOOTH_BLEND := 0.35
const MAXIMUM_RIGID_ATTACHMENT_CORRECTION := 0.03
const RIGID_CLEARANCE_SCALE_PERCENTILE := 0.90
const MINIMUM_RIGID_COMPONENT_SCALE := 1.0
const MAXIMUM_RIGID_COMPONENT_SCALE := 1.12


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
	synchronized += _synchronize_internal_panels(
			mesh_states, auto_surface_offsets, filter_mesh, filter_surface)
	synchronized += _synchronize_auto_offset_thickness(
			mesh_states, auto_surface_offsets, filter_mesh, filter_surface)
	synchronized += _synchronize_internal_panels(
			mesh_states, auto_surface_offsets, filter_mesh, filter_surface)
	synchronized += synchronize_auto_offset_seams(
			mesh_states, auto_surface_offsets, filter_mesh, filter_surface)
	synchronized += _synchronize_internal_panels(
			mesh_states, auto_surface_offsets, filter_mesh, filter_surface)
	return synchronized


static func _synchronize_internal_panels(
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
		var state := mesh_states[mesh_key] as Dictionary
		var surfaces := state["surfaces"] as Array
		var mesh_offsets := auto_surface_offsets[mesh_key] as Array
		for surface_index in surfaces.size():
			if filter_surface >= 0 and surface_index != filter_surface:
				continue
			var surface := surfaces[surface_index] as Dictionary
			if not surface["is_clothing"]:
				continue
			var rigid_components := surface.get(
					"rigid_fit_components", {}) as Dictionary
			if rigid_components.is_empty():
				continue
			var vertices := surface["base_vertices"] as PackedVector3Array
			var offsets := mesh_offsets[surface_index] as PackedVector3Array
			var baseline_offsets := surface.get(
					"rigid_fit_baseline_offsets",
					PackedVector3Array()) as PackedVector3Array
			if baseline_offsets.size() != vertices.size():
				baseline_offsets = PackedVector3Array()
				baseline_offsets.resize(vertices.size())
			var components := surface["components"] as Array
			var component_transforms: Dictionary = {}
			for component_index_variant in rigid_components:
				var component_index := int(component_index_variant)
				if component_index < 0 or component_index >= components.size():
					continue
				var component := components[component_index] as Dictionary
				var component_vertices := (
						component["vertex_indices"] as PackedInt32Array)
				if component_vertices.size() < 3:
					continue
				component_transforms[component_index] = _component_similarity_transform(
						vertices, baseline_offsets, offsets, component_vertices)
			_attach_rigid_component_transforms(
					surface,
					vertices,
					baseline_offsets,
					component_transforms)
			for component_index_variant in component_transforms:
				var component_index := int(component_index_variant)
				var component := components[component_index] as Dictionary
				var component_vertices := (
						component["vertex_indices"] as PackedInt32Array)
				var panel_transform := (
						component_transforms[component_index] as Transform3D)
				for target_index in component_vertices:
					var target_position := (
							vertices[target_index] + baseline_offsets[target_index])
					var shared_offset := (
							panel_transform * target_position - vertices[target_index])
					if not offsets[target_index].is_equal_approx(shared_offset):
						synchronized += 1
					offsets[target_index] = shared_offset
			mesh_offsets[surface_index] = offsets
		auto_surface_offsets[mesh_key] = mesh_offsets
	return synchronized


static func _attach_rigid_component_transforms(
	surface: Dictionary,
	vertices: PackedVector3Array,
	baseline_offsets: PackedVector3Array,
	component_transforms: Dictionary,
) -> void:
	for link_variant in _rigid_component_links(
			surface, vertices, baseline_offsets, component_transforms):
		var link := link_variant as Dictionary
		var parent_index := int(link["parent"])
		var child_index := int(link["child"])
		if (not component_transforms.has(parent_index)
				or not component_transforms.has(child_index)):
			continue
		var parent_transform := component_transforms[parent_index] as Transform3D
		var child_transform := component_transforms[child_index] as Transform3D
		var child_anchor_index := int(link["child_anchor"])
		var child_anchor := (
				vertices[child_anchor_index] + baseline_offsets[child_anchor_index])
		var desired_anchor := parent_transform * child_anchor
		var current_anchor := child_transform * child_anchor
		var correction := desired_anchor - current_anchor
		correction.y = 0.0
		if correction.length() > MAXIMUM_RIGID_ATTACHMENT_CORRECTION:
			correction = (
					correction.normalized() * MAXIMUM_RIGID_ATTACHMENT_CORRECTION)
		child_transform.origin += correction
		component_transforms[child_index] = child_transform


static func _rigid_component_links(
	surface: Dictionary,
	vertices: PackedVector3Array,
	baseline_offsets: PackedVector3Array,
	component_transforms: Dictionary,
) -> Array:
	if surface.has("rigid_fit_component_links"):
		return surface["rigid_fit_component_links"] as Array
	var components := surface["components"] as Array
	var component_sides := surface.get(
			"rigid_fit_component_sides", {}) as Dictionary
	var side_components: Dictionary = {}
	for component_index_variant in component_transforms:
		var component_index := int(component_index_variant)
		var side := String(component_sides.get(
				component_index, "component_%d" % component_index))
		var members := side_components.get(side, []) as Array
		members.append(component_index)
		side_components[side] = members
	var links: Array = []
	for members_variant in side_components.values():
		var members := members_variant as Array
		if members.size() < 2:
			continue
		var root := int(members[0])
		var root_height := _component_center_height(
				components[root], vertices, baseline_offsets)
		for component_index_variant in members:
			var component_index := int(component_index_variant)
			var height := _component_center_height(
					components[component_index], vertices, baseline_offsets)
			# Keep the distal shoe/foot correction on the body, then attach the
			# proximal shaft to it. Reversing this exposes the fitted foot.
			if height < root_height:
				root = component_index
				root_height = height
		var attached := {root: true}
		while attached.size() < members.size():
			var nearest: Dictionary = {}
			var nearest_distance_squared := INF
			for parent_index_variant in attached:
				var parent_index := int(parent_index_variant)
				for child_index_variant in members:
					var child_index := int(child_index_variant)
					if attached.has(child_index):
						continue
					var candidate := _closest_component_anchor(
							components[parent_index],
							components[child_index],
							vertices,
							baseline_offsets)
					if float(candidate["distance_squared"]) < nearest_distance_squared:
						nearest_distance_squared = candidate["distance_squared"]
						nearest = candidate
						nearest["parent"] = parent_index
						nearest["child"] = child_index
			if nearest.is_empty():
				break
			links.append(nearest)
			attached[int(nearest["child"])] = true
	surface["rigid_fit_component_links"] = links
	return links


static func _component_center_height(
	component: Dictionary,
	vertices: PackedVector3Array,
	baseline_offsets: PackedVector3Array,
) -> float:
	var component_vertices := component["vertex_indices"] as PackedInt32Array
	var height := 0.0
	for vertex_index in component_vertices:
		height += (vertices[vertex_index] + baseline_offsets[vertex_index]).y
	return height / float(component_vertices.size())


static func _closest_component_anchor(
	parent: Dictionary,
	child: Dictionary,
	vertices: PackedVector3Array,
	baseline_offsets: PackedVector3Array,
) -> Dictionary:
	var nearest_parent := -1
	var nearest_child := -1
	var nearest_distance_squared := INF
	for parent_index in (parent["vertex_indices"] as PackedInt32Array):
		var parent_position := (
				vertices[parent_index] + baseline_offsets[parent_index])
		for child_index in (child["vertex_indices"] as PackedInt32Array):
			var child_position := (
					vertices[child_index] + baseline_offsets[child_index])
			var distance_squared := parent_position.distance_squared_to(child_position)
			if distance_squared < nearest_distance_squared:
				nearest_parent = parent_index
				nearest_child = child_index
				nearest_distance_squared = distance_squared
	return {
		"parent_anchor": nearest_parent,
		"child_anchor": nearest_child,
		"distance_squared": nearest_distance_squared,
	}


static func _component_similarity_transform(
	vertices: PackedVector3Array,
	baseline_offsets: PackedVector3Array,
	offsets: PackedVector3Array,
	vertex_indices: PackedInt32Array,
) -> Transform3D:
	var source_center := Vector3.ZERO
	var destination_center := Vector3.ZERO
	for vertex_index in vertex_indices:
		source_center += vertices[vertex_index] + baseline_offsets[vertex_index]
		destination_center += vertices[vertex_index] + offsets[vertex_index]
	source_center /= float(vertex_indices.size())
	destination_center /= float(vertex_indices.size())
	var covariance := PackedFloat64Array()
	covariance.resize(9)
	for vertex_index in vertex_indices:
		var source := (
				vertices[vertex_index] + baseline_offsets[vertex_index] - source_center)
		var destination := (
				vertices[vertex_index] + offsets[vertex_index] - destination_center)
		covariance[0] += source.x * destination.x
		covariance[1] += source.x * destination.y
		covariance[2] += source.x * destination.z
		covariance[3] += source.y * destination.x
		covariance[4] += source.y * destination.y
		covariance[5] += source.y * destination.z
		covariance[6] += source.z * destination.x
		covariance[7] += source.z * destination.y
		covariance[8] += source.z * destination.z
	var rotation := _covariance_rotation(covariance)
	var rotated_variance := 0.0
	var source_variance := 0.0
	var clearance_scales: Array[float] = []
	for vertex_index in vertex_indices:
		var source := (
				vertices[vertex_index] + baseline_offsets[vertex_index] - source_center)
		var destination := (
				vertices[vertex_index] + offsets[vertex_index] - destination_center)
		var rotated_source := rotation * source
		var projected_scale := (
				destination.dot(rotated_source) / rotated_source.length_squared()
				if rotated_source.length_squared() > 0.00000001 else 1.0)
		if projected_scale > 0.0:
			clearance_scales.append(projected_scale)
		rotated_variance += destination.dot(rotated_source)
		source_variance += source.length_squared()
	clearance_scales.sort()
	var conservative_scale := 1.0
	if not clearance_scales.is_empty():
		var percentile_index := floori(
				float(clearance_scales.size() - 1)
				* RIGID_CLEARANCE_SCALE_PERCENTILE)
		conservative_scale = clearance_scales[percentile_index]
	var scale := clampf(maxf(
			rotated_variance / source_variance if source_variance > 0.00000001 else 1.0,
			conservative_scale),
			MINIMUM_RIGID_COMPONENT_SCALE,
			MAXIMUM_RIGID_COMPONENT_SCALE)
	var basis := Basis(rotation).scaled(Vector3.ONE * scale)
	return Transform3D(basis, destination_center - basis * source_center)


static func _covariance_rotation(covariance: PackedFloat64Array) -> Quaternion:
	var xx := covariance[0]
	var xy := covariance[1]
	var xz := covariance[2]
	var yx := covariance[3]
	var yy := covariance[4]
	var yz := covariance[5]
	var zx := covariance[6]
	var zy := covariance[7]
	var zz := covariance[8]
	var trace := xx + yy + zz
	var quaternion := PackedFloat64Array([1.0, 0.0, 0.0, 0.0])
	for _iteration in 20:
		var next := PackedFloat64Array([
			trace * quaternion[0] + (yz - zy) * quaternion[1]
					+ (zx - xz) * quaternion[2] + (xy - yx) * quaternion[3],
			(yz - zy) * quaternion[0] + (xx - yy - zz) * quaternion[1]
					+ (xy + yx) * quaternion[2] + (zx + xz) * quaternion[3],
			(zx - xz) * quaternion[0] + (xy + yx) * quaternion[1]
					+ (-xx + yy - zz) * quaternion[2] + (yz + zy) * quaternion[3],
			(xy - yx) * quaternion[0] + (zx + xz) * quaternion[1]
					+ (yz + zy) * quaternion[2] + (-xx - yy + zz) * quaternion[3],
		])
		var length := sqrt(
				next[0] * next[0] + next[1] * next[1]
				+ next[2] * next[2] + next[3] * next[3])
		if length <= 0.00000001:
			return Quaternion.IDENTITY
		for value_index in next.size():
			next[value_index] /= length
		quaternion = next
	return Quaternion(
			quaternion[1], quaternion[2], quaternion[3], quaternion[0]).normalized()


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
