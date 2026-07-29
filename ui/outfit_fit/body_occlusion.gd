class_name OutfitFitBodyOcclusion
extends RefCounted
## Computes and serializes body-triangle masks beneath fitted rigid opaque garments.

const FIT_GEOMETRY := preload("res://ui/outfit_fit/geometry.gd")
const OUTFIT_VISUALIZATION := preload("res://ui/outfit_fit/visualization.gd")
const OCCLUSION_GUARD_BAND_PASSES := 1


static func compute(
	outfit_root: Node3D,
	mesh_states: Dictionary,
	body_triangles: Array,
	body_triangle_grid: Dictionary,
	body_cell_size: float,
	body_normal_sign: float,
) -> Dictionary:
	var found_rigid_components := false
	var occluded_triangles: Dictionary = {}
	var ignored_clipped_vertices: Dictionary = {}
	var ignored_debug_vertices: Dictionary = {}
	for skeleton_node in outfit_root.find_children("*", "Skeleton3D", true, false):
		(skeleton_node as Skeleton3D).advance(0.0)
	for mesh_key_variant in mesh_states:
		var mesh_key := String(mesh_key_variant)
		var state := mesh_states[mesh_key] as Dictionary
		var mesh_instance := state["node"] as MeshInstance3D
		for surface in (state["surfaces"] as Array):
			var rigid_components := surface.get(
					"rigid_fit_components", {}) as Dictionary
			if rigid_components.is_empty() or not _is_opaque(surface["material"]):
				continue
			found_rigid_components = true
			var arrays := surface["arrays"] as Array
			var world_vertices := FIT_GEOMETRY.skin_vertices_world(mesh_instance, arrays)
			var components := surface["components"] as Array
			for component_index_variant in rigid_components:
				var component_index := int(component_index_variant)
				if component_index < 0 or component_index >= components.size():
					continue
				var component := components[component_index] as Dictionary
				OUTFIT_VISUALIZATION.clipping_colors(
						world_vertices,
						arrays,
						component["indices"] as PackedInt32Array,
						body_triangles,
						body_triangle_grid,
						body_cell_size,
						body_normal_sign,
						ignored_clipped_vertices,
						ignored_debug_vertices,
						occluded_triangles)
	return {
		"found": found_rigid_components,
		"triangles": _add_guard_band(
				occluded_triangles,
				body_triangles,
				OCCLUSION_GUARD_BAND_PASSES),
	}


static func _is_opaque(material: Material) -> bool:
	if material is BaseMaterial3D:
		return (
				(material as BaseMaterial3D).transparency
				== BaseMaterial3D.TRANSPARENCY_DISABLED)
	return material != null


static func _add_guard_band(
	occluded_triangles: Dictionary,
	body_triangles: Array,
	passes: int,
) -> Dictionary:
	var result := occluded_triangles.duplicate(true)
	for _pass in passes:
		var hidden_vertices: Dictionary = {}
		for body_triangle in body_triangles:
			var surface_index := int(body_triangle["surface"])
			var surface_triangle := int(body_triangle["surface_triangle"])
			var hidden := result.get(surface_index, {}) as Dictionary
			if not hidden.has(surface_triangle):
				continue
			if not hidden_vertices.has(surface_index):
				hidden_vertices[surface_index] = {}
			var surface_vertices := hidden_vertices[surface_index] as Dictionary
			for vertex_index in body_triangle["vertices"]:
				surface_vertices[int(vertex_index)] = true
		var additions: Dictionary = {}
		for body_triangle in body_triangles:
			var surface_index := int(body_triangle["surface"])
			var surface_triangle := int(body_triangle["surface_triangle"])
			var hidden := result.get(surface_index, {}) as Dictionary
			if hidden.has(surface_triangle):
				continue
			var surface_vertices := hidden_vertices.get(surface_index, {}) as Dictionary
			var shared_vertices := 0
			for vertex_index in body_triangle["vertices"]:
				if surface_vertices.has(int(vertex_index)):
					shared_vertices += 1
			if shared_vertices < 2:
				continue
			if not additions.has(surface_index):
				additions[surface_index] = {}
			(additions[surface_index] as Dictionary)[surface_triangle] = true
		for surface_index_variant in additions:
			var surface_index := int(surface_index_variant)
			if not result.has(surface_index):
				result[surface_index] = {}
			var hidden := result[surface_index] as Dictionary
			for triangle_index_variant in (additions[surface_index] as Dictionary):
				hidden[int(triangle_index_variant)] = true
	return result


static func refresh(
	body_mesh: MeshInstance3D,
	body_source_mesh: ArrayMesh,
	outfit_root: Node3D,
	mesh_states: Dictionary,
	body_triangles: Array,
	body_triangle_grid: Dictionary,
	body_cell_size: float,
	body_normal_sign: float,
	visualize_clipping: bool,
	force_compute: bool,
	rebuild_geometry: Callable,
	existing_occlusion: Dictionary,
) -> Dictionary:
	if (not is_instance_valid(body_mesh)
			or body_source_mesh == null
			or body_triangles.is_empty()
			or (visualize_clipping and not force_compute)):
		return existing_occlusion
	rebuild_geometry.call()
	var result := compute(
			outfit_root,
			mesh_states,
			body_triangles,
			body_triangle_grid,
			body_cell_size,
			body_normal_sign)
	var occlusion := (
			result["triangles"] as Dictionary
			if result["found"] else existing_occlusion)
	if not visualize_clipping:
		OUTFIT_VISUALIZATION.apply_body_occlusion(
				body_mesh, body_source_mesh, occlusion)
	return occlusion


static func encode(occluded_triangles: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var surface_indices: Array[int] = []
	for surface_index_variant in occluded_triangles:
		surface_indices.append(int(surface_index_variant))
	surface_indices.sort()
	for surface_index in surface_indices:
		var triangles: Array[int] = []
		for triangle_index_variant in (
				occluded_triangles[surface_index] as Dictionary):
			triangles.append(int(triangle_index_variant))
		triangles.sort()
		result.append({
			"surface": surface_index,
			"triangles": triangles,
		})
	return result


static func decode(records: Variant, body_surface_count: int) -> Dictionary:
	var result: Dictionary = {}
	if not records is Array:
		return result
	for record_variant in records:
		if not record_variant is Dictionary:
			continue
		var record := record_variant as Dictionary
		var surface_index := int(record.get("surface", -1))
		if surface_index < 0 or surface_index >= body_surface_count:
			continue
		var triangles: Dictionary = {}
		for triangle_index_variant in record.get("triangles", []):
			var triangle_index := int(triangle_index_variant)
			if triangle_index >= 0:
				triangles[triangle_index] = true
		if not triangles.is_empty():
			result[surface_index] = triangles
	return result
