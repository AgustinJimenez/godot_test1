class_name OutfitFitComponents
extends RefCounted
## Catalogs disconnected topology pieces contained inside imported mesh surfaces.

const FIT_GEOMETRY := preload("res://ui/outfit_fit_geometry.gd")
const SKIN_MATERIAL_PATTERNS := ["regular_male", "regular_female"]


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
