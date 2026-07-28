class_name OutfitFitSolver
extends RefCounted
## Synchronous body-contact and garment-layer fitting pipeline.
##
## The editor owns preview state and interaction. This helper mutates only the supplied automatic
## offset arrays and asks the editor to rebuild geometry between dependent solver stages.

const FIT_GEOMETRY := preload("res://ui/outfit_fit/geometry.gd")
const OUTFIT_LAYERS := preload("res://ui/outfit_fit/layers.gd")
const OUTFIT_COMPONENTS := preload("res://ui/outfit_fit/components.gd")

const AUTO_FIT_PASSES := 3
const AUTO_MAX_STEP := 0.03
const AUTO_SMOOTH_PASSES := 2
const AUTO_SMOOTH_BLEND := 0.4
const CLOTH_LAYER_STEP := 0.003
const CLOTH_LAYER_MAX_PASSES := 12
const COLLISION_STEP := 0.002
const COLLISION_PASSES := 16
const LAYER_CLEARANCE := 0.002


static func run(
	context: Dictionary,
	clearance: float,
	filter_mesh: String = "",
	filter_surface: int = -1,
	filter_component: int = -1,
) -> Dictionary:
	var mesh_states: Dictionary = context["mesh_states"]
	var auto_offsets: Dictionary = context["auto_offsets"]
	var body_triangles: Array = context["body_triangles"]
	var body_grid: Dictionary = context["body_grid"]
	var body_cell_size: float = context["body_cell_size"]
	var body_normal_sign: float = context["body_normal_sign"]
	var search_radius: float = context["search_radius"]
	var maximum_offset: float = context["maximum_offset"]
	var rebuild_geometry := context["rebuild_geometry"] as Callable
	var closest_body_projection := context["closest_body_projection"] as Callable
	var filter_enabled := not filter_mesh.is_empty() and filter_surface >= 0
	var authored_layer_order := OUTFIT_LAYERS.compute_authored_order(
			mesh_states,
			body_triangles,
			body_grid,
			body_cell_size,
			body_normal_sign,
			search_radius)
	var layer_context := {
		"body_triangles": body_triangles,
		"body_grid": body_grid,
		"body_cell_size": body_cell_size,
		"body_normal_sign": body_normal_sign,
		"search_radius": search_radius,
		"body_clearance": clearance,
		"layer_clearance": LAYER_CLEARANCE,
		"layer_step": CLOTH_LAYER_STEP,
		"maximum_offset": maximum_offset,
	}
	rebuild_geometry.call()
	var adjusted := 0
	var skipped := 0
	# Solve every garment vertex, including the cloth between visible controls.
	for iteration in AUTO_FIT_PASSES:
		var correction_count := 0
		for mesh_key_variant in mesh_states:
			var mesh_key := String(mesh_key_variant)
			if filter_enabled and mesh_key != filter_mesh:
				continue
			var state: Dictionary = mesh_states[mesh_key]
			var mesh_instance := state["node"] as MeshInstance3D
			var surfaces: Array = state["surfaces"]
			var mesh_offsets := auto_offsets[mesh_key] as Array
			for surface_index in surfaces.size():
				if filter_enabled and surface_index != filter_surface:
					continue
				var surface: Dictionary = surfaces[surface_index]
				if not surface["is_clothing"]:
					continue
				var allowed_vertices := OUTFIT_COMPONENTS.vertex_set(
						surface, filter_component if filter_enabled else -1)
				var vertices: PackedVector3Array = surface["vertices"]
				var arrays: Array = surface["arrays"]
				var world_vertices := FIT_GEOMETRY.skin_vertices_world(mesh_instance, arrays)
				var regions := FIT_GEOMETRY.vertex_regions(mesh_instance, arrays)
				var smooth_surface := FIT_GEOMETRY.is_leg_surface(regions)
				var intersections := FIT_GEOMETRY.find_intersections(
						world_vertices,
						arrays[Mesh.ARRAY_INDEX] as PackedInt32Array,
						body_triangles,
						body_grid,
						body_cell_size,
						body_normal_sign)
				var clipping_vertices: Dictionary = intersections["cloth_vertices"]
				var offsets := mesh_offsets[surface_index] as PackedVector3Array
				var corrections := PackedVector3Array()
				corrections.resize(vertices.size())
				for vertex_index in vertices.size():
					if not allowed_vertices.is_empty() and not allowed_vertices.has(vertex_index):
						continue
					var current_world := world_vertices[vertex_index]
					var projection := closest_body_projection.call(
							current_world, regions[vertex_index]) as Dictionary
					if projection.is_empty():
						if iteration == 0:
							skipped += 1
						continue
					var normal: Vector3 = projection["normal"]
					var signed_distance := (
							current_world - (projection["position"] as Vector3)).dot(normal)
					var intersects := clipping_vertices.has(vertex_index)
					var error := FIT_GEOMETRY.clipping_error(
							signed_distance, clearance, intersects, COLLISION_STEP)
					if error <= 0.0:
						continue
					if smooth_surface:
						projection = FIT_GEOMETRY.outer_body_projection(
								current_world, body_triangles, body_grid,
								body_cell_size, search_radius, body_normal_sign,
								regions[vertex_index])
						normal = projection["normal"]
						signed_distance = (
								current_world - (projection["position"] as Vector3)
								).dot(normal)
						error = FIT_GEOMETRY.clipping_error(
								signed_distance, clearance, intersects, COLLISION_STEP)
						if error <= 0.0:
							continue
					var corrected_world := current_world + normal * error
					var local_correction := (
							mesh_instance.to_local(corrected_world)
							- mesh_instance.to_local(current_world))
					corrections[vertex_index] = (
							local_correction.limit_length(AUTO_MAX_STEP)
							if smooth_surface else local_correction)
					correction_count += 1
					if iteration == 0:
						adjusted += 1
				if smooth_surface:
					corrections = FIT_GEOMETRY.smooth_offsets(
							vertices,
							arrays[Mesh.ARRAY_INDEX] as PackedInt32Array,
							corrections,
							AUTO_SMOOTH_PASSES,
							AUTO_SMOOTH_BLEND)
					if not allowed_vertices.is_empty():
						for vertex_index in corrections.size():
							if not allowed_vertices.has(vertex_index):
								corrections[vertex_index] = Vector3.ZERO
				for vertex_index in offsets.size():
					offsets[vertex_index] = (
							offsets[vertex_index] + corrections[vertex_index]
							).limit_length(maximum_offset)
				mesh_offsets[surface_index] = offsets
			auto_offsets[mesh_key] = mesh_offsets
		OUTFIT_COMPONENTS.synchronize_auto_offset_constraints(
				mesh_states, auto_offsets, filter_mesh, filter_surface)
		if correction_count == 0:
			break
		rebuild_geometry.call()
	var remaining_intersections := _resolve_body_intersections(
			context, clearance, filter_mesh, filter_surface, filter_component)
	var layer_result := _resolve_garment_layers(
			context,
			authored_layer_order,
			layer_context,
			filter_mesh,
			filter_surface,
			filter_component)
	return {
		"adjusted": adjusted,
		"status": _status_message(
				adjusted,
				skipped,
				clearance,
				filter_enabled,
				filter_component,
				remaining_intersections,
				layer_result,
				authored_layer_order),
	}


static func _resolve_body_intersections(
	context: Dictionary,
	clearance: float,
	filter_mesh: String,
	filter_surface: int,
	filter_component: int,
) -> int:
	var mesh_states: Dictionary = context["mesh_states"]
	var auto_offsets: Dictionary = context["auto_offsets"]
	var body_triangles: Array = context["body_triangles"]
	var body_grid: Dictionary = context["body_grid"]
	var body_cell_size: float = context["body_cell_size"]
	var body_normal_sign: float = context["body_normal_sign"]
	var rebuild_geometry := context["rebuild_geometry"] as Callable
	var closest_body_projection := context["closest_body_projection"] as Callable
	var filter_enabled := not filter_mesh.is_empty() and filter_surface >= 0
	var remaining_intersections := 0
	for _collision_pass in COLLISION_PASSES:
		var pushed_vertices := 0
		for mesh_key_variant in mesh_states:
			var mesh_key := String(mesh_key_variant)
			if filter_enabled and mesh_key != filter_mesh:
				continue
			var state: Dictionary = mesh_states[mesh_key]
			var mesh_instance := state["node"] as MeshInstance3D
			var surfaces: Array = state["surfaces"]
			var mesh_offsets := auto_offsets[mesh_key] as Array
			for surface_index in surfaces.size():
				if filter_enabled and surface_index != filter_surface:
					continue
				var surface: Dictionary = surfaces[surface_index]
				if not surface["is_clothing"]:
					continue
				var allowed_vertices := OUTFIT_COMPONENTS.vertex_set(
						surface, filter_component if filter_enabled else -1)
				var arrays: Array = surface["arrays"]
				var world_vertices := FIT_GEOMETRY.skin_vertices_world(mesh_instance, arrays)
				var intersections := FIT_GEOMETRY.find_intersections(
						world_vertices,
						arrays[Mesh.ARRAY_INDEX] as PackedInt32Array,
						body_triangles,
						body_grid,
						body_cell_size,
						body_normal_sign)
				var marked: Dictionary = intersections["cloth_vertices"]
				var collision_normals: Dictionary = intersections["cloth_normals"]
				var offsets := mesh_offsets[surface_index] as PackedVector3Array
				for vertex_index_variant in marked:
					var vertex_index := int(vertex_index_variant)
					if not allowed_vertices.is_empty() and not allowed_vertices.has(vertex_index):
						continue
					var current_world := world_vertices[vertex_index]
					var normal := (collision_normals.get(
							vertex_index, Vector3.ZERO) as Vector3).normalized()
					if normal.is_zero_approx():
						var projection := closest_body_projection.call(
								current_world, "") as Dictionary
						if projection.is_empty():
							continue
						normal = projection["normal"]
					var pushed_world := current_world + normal * maxf(
							COLLISION_STEP, clearance * 0.5)
					offsets[vertex_index] += (
							mesh_instance.to_local(pushed_world)
							- mesh_instance.to_local(current_world))
					pushed_vertices += 1
				mesh_offsets[surface_index] = offsets
			auto_offsets[mesh_key] = mesh_offsets
		OUTFIT_COMPONENTS.synchronize_auto_offset_constraints(
				mesh_states, auto_offsets, filter_mesh, filter_surface)
		remaining_intersections = pushed_vertices
		if pushed_vertices == 0:
			break
		rebuild_geometry.call()
	return remaining_intersections


static func _resolve_garment_layers(
	context: Dictionary,
	authored_layer_order: Dictionary,
	layer_context: Dictionary,
	filter_mesh: String,
	filter_surface: int,
	filter_component: int,
) -> Dictionary:
	var mesh_states: Dictionary = context["mesh_states"]
	var auto_offsets: Dictionary = context["auto_offsets"]
	var rebuild_geometry := context["rebuild_geometry"] as Callable
	var layer_pushes := 0
	var remaining_layer_intersections := 0
	var layer_levels := int(authored_layer_order.get("levels", 0))
	for _layer_pass in CLOTH_LAYER_MAX_PASSES:
		var pass_pushes := 0
		for layer_level in range(2, layer_levels + 1):
			var pushed := OUTFIT_LAYERS.resolve_pass(
					mesh_states,
					auto_offsets,
					authored_layer_order,
					layer_context,
					filter_mesh, filter_surface, filter_component, layer_level)
			pass_pushes += pushed
			if pushed > 0:
				OUTFIT_COMPONENTS.synchronize_auto_offset_constraints(
						mesh_states, auto_offsets, filter_mesh, filter_surface)
				rebuild_geometry.call()
		remaining_layer_intersections = pass_pushes
		if pass_pushes == 0:
			break
		layer_pushes += pass_pushes
	return {
		"pushes": layer_pushes,
		"remaining": remaining_layer_intersections,
		"levels": layer_levels,
	}


static func _status_message(
	adjusted: int,
	skipped: int,
	clearance: float,
	filter_enabled: bool,
	filter_component: int,
	remaining_intersections: int,
	layer_result: Dictionary,
	authored_layer_order: Dictionary,
) -> String:
	var scope := (" on selected component"
			if filter_component >= 0
			else " on selected surface" if filter_enabled else "")
	var layer_pushes := int(layer_result["pushes"])
	var remaining_layers := int(layer_result["remaining"])
	var layer_levels := int(layer_result["levels"])
	return (
		"Contact-fit %d cloth vertices%s at %.1f mm%s%s%s%s; inspect, then save or reset"
		% [
			adjusted, scope, clearance * 1000.0,
			" (%d skipped)" % skipped if skipped > 0 else "",
			(" (%d intersection vertices remain)" % remaining_intersections
					if remaining_intersections > 0 else ""),
			(" (%d layer pushes%s)" % [
					layer_pushes,
					", limit reached" if remaining_layers > 0 else "",
				] if layer_pushes > 0 else ""),
			" (%d local layer relations across %d levels)" % [
					(authored_layer_order.get("pairs", []) as Array).size(),
					layer_levels] if layer_levels > 0 else "",
		])
