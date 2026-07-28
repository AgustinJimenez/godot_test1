class_name OutfitFitLayers
extends RefCounted
## Resolves intersections between garment surfaces without changing their authored order.
##
## Layer order is measured only where two surfaces project onto the same body-space cells.
## During cleanup the authored outer surface moves outward; for a selected-only fit, an
## authored inner selection may move inward only while preserving body clearance.

const FIT_GEOMETRY := preload("res://ui/outfit_fit_geometry.gd")
const ORDER_CELL_SIZE := 0.08


static func compute_authored_order(
	mesh_states: Dictionary,
	body_triangles: Array[Dictionary],
	body_grid: Dictionary,
	body_cell_size: float,
	body_normal_sign: float,
	search_radius: float,
) -> Dictionary:
	var surfaces := _clothing_surfaces(mesh_states)
	var depth_maps: Dictionary = {}
	for descriptor in surfaces:
		depth_maps[descriptor["id"]] = _authored_depth_map(
				descriptor,
				body_triangles,
				body_grid,
				body_cell_size,
				body_normal_sign,
				search_radius)
	var result: Dictionary = {}
	for first_index in surfaces.size():
		for second_index in range(first_index + 1, surfaces.size()):
			var first: Dictionary = surfaces[first_index]
			var second: Dictionary = surfaces[second_index]
			var difference := _shared_depth_difference(
					depth_maps[first["id"]], depth_maps[second["id"]])
			if absf(difference) < 0.0001:
				difference = (
						float((depth_maps[first["id"]] as Dictionary)["average"])
						- float((depth_maps[second["id"]] as Dictionary)["average"]))
			var pair_key := _pair_key(first["id"], second["id"])
			result[pair_key] = first["id"] if difference >= 0.0 else second["id"]
	return result


static func resolve_pass(
	mesh_states: Dictionary,
	auto_surface_offsets: Dictionary,
	authored_order: Dictionary,
	context: Dictionary,
	filter_mesh: String = "",
	filter_surface: int = -1,
) -> int:
	var descriptors := _clothing_surfaces(mesh_states)
	var collision_meshes: Dictionary = {}
	for descriptor in descriptors:
		collision_meshes[descriptor["id"]] = _collision_mesh(
				descriptor, context["body_cell_size"])
	var filter_enabled := not filter_mesh.is_empty() and filter_surface >= 0
	var selected_id := _surface_id(filter_mesh, filter_surface) if filter_enabled else ""
	var pushed := 0
	for first_index in descriptors.size():
		for second_index in range(first_index + 1, descriptors.size()):
			var first: Dictionary = descriptors[first_index]
			var second: Dictionary = descriptors[second_index]
			var first_collision: Dictionary = collision_meshes[first["id"]]
			var second_collision: Dictionary = collision_meshes[second["id"]]
			if not (first_collision["bounds"] as AABB).intersects(
					second_collision["bounds"] as AABB):
				continue
			var pair_key := _pair_key(first["id"], second["id"])
			var outer_id := String(authored_order.get(pair_key, first["id"]))
			var outer := first if first["id"] == outer_id else second
			var inner := second if first["id"] == outer_id else first
			var moving := outer
			var reference := inner
			var direction := 1.0
			if filter_enabled:
				if selected_id == outer["id"]:
					pass
				elif selected_id == inner["id"]:
					moving = inner
					reference = outer
					direction = -1.0
				else:
					continue
			pushed += _separate_pair(
					moving,
					collision_meshes[moving["id"]],
					collision_meshes[reference["id"]],
					auto_surface_offsets,
					context,
					direction)
	return pushed


static func _separate_pair(
	moving: Dictionary,
	moving_collision: Dictionary,
	reference_collision: Dictionary,
	auto_surface_offsets: Dictionary,
	context: Dictionary,
	direction: float,
) -> int:
	var intersections := FIT_GEOMETRY.find_intersections(
			moving_collision["vertices"],
			moving_collision["indices"],
			reference_collision["triangles"],
			reference_collision["grid"],
			context["body_cell_size"],
			1.0)
	var marked: Dictionary = intersections["cloth_vertices"]
	if marked.is_empty():
		return 0
	var mesh_key := moving["mesh_key"] as String
	var surface_index := moving["surface_index"] as int
	var mesh_instance := moving["mesh_instance"] as MeshInstance3D
	var mesh_offsets := auto_surface_offsets[mesh_key] as Array
	var offsets := mesh_offsets[surface_index] as PackedVector3Array
	var world_vertices := moving_collision["vertices"] as PackedVector3Array
	var pushed := 0
	for vertex_index_variant in marked:
		var vertex_index := int(vertex_index_variant)
		var current_world := world_vertices[vertex_index]
		var projection := FIT_GEOMETRY.closest_body_projection(
				current_world,
				context["body_triangles"],
				context["body_grid"],
				context["body_cell_size"],
				context["search_radius"],
				context["body_normal_sign"])
		if projection.is_empty():
			continue
		var normal := projection["normal"] as Vector3
		var push_distance := float(context["layer_step"])
		if direction < 0.0:
			var signed_distance := (
					current_world - (projection["position"] as Vector3)).dot(normal)
			push_distance = minf(
					push_distance, signed_distance - float(context["body_clearance"]))
			if push_distance <= 0.0:
				continue
		var pushed_world := current_world + normal * push_distance * direction
		var local_delta := (
				mesh_instance.to_local(pushed_world)
				- mesh_instance.to_local(current_world))
		offsets[vertex_index] = (
				offsets[vertex_index] + local_delta).limit_length(
						context["maximum_offset"])
		pushed += 1
	mesh_offsets[surface_index] = offsets
	auto_surface_offsets[mesh_key] = mesh_offsets
	return pushed


static func _clothing_surfaces(mesh_states: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for mesh_key_variant in mesh_states:
		var mesh_key := String(mesh_key_variant)
		var state: Dictionary = mesh_states[mesh_key]
		var mesh_instance := state["node"] as MeshInstance3D
		var surfaces := state["surfaces"] as Array
		for surface_index in surfaces.size():
			var surface := surfaces[surface_index] as Dictionary
			if not surface["is_clothing"]:
				continue
			result.append({
				"id": _surface_id(mesh_key, surface_index),
				"mesh_key": mesh_key,
				"surface_index": surface_index,
				"mesh_instance": mesh_instance,
				"surface": surface,
			})
	return result


static func _authored_depth_map(
	descriptor: Dictionary,
	body_triangles: Array[Dictionary],
	body_grid: Dictionary,
	body_cell_size: float,
	body_normal_sign: float,
	search_radius: float,
) -> Dictionary:
	var surface := descriptor["surface"] as Dictionary
	var arrays := (surface["arrays"] as Array).duplicate(true)
	arrays[Mesh.ARRAY_VERTEX] = (
			surface["base_vertices"] as PackedVector3Array).duplicate()
	var world_vertices := FIT_GEOMETRY.skin_vertices_world(
			descriptor["mesh_instance"], arrays)
	var cells: Dictionary = {}
	var total := 0.0
	var count := 0
	for point in world_vertices:
		var projection := FIT_GEOMETRY.closest_body_projection(
				point,
				body_triangles,
				body_grid,
				body_cell_size,
				search_radius,
				body_normal_sign)
		if projection.is_empty():
			continue
		var normal := projection["normal"] as Vector3
		var depth := (point - (projection["position"] as Vector3)).dot(normal)
		var cell := FIT_GEOMETRY.grid_cell(
				projection["position"], ORDER_CELL_SIZE)
		var sample: Vector2 = cells.get(cell, Vector2.ZERO)
		cells[cell] = sample + Vector2(depth, 1.0)
		total += depth
		count += 1
	return {
		"cells": cells,
		"average": total / float(count) if count > 0 else 0.0,
	}


static func _shared_depth_difference(first: Dictionary, second: Dictionary) -> float:
	var first_cells := first["cells"] as Dictionary
	var second_cells := second["cells"] as Dictionary
	var total := 0.0
	var count := 0
	for cell in first_cells:
		if not second_cells.has(cell):
			continue
		var first_sample := first_cells[cell] as Vector2
		var second_sample := second_cells[cell] as Vector2
		if first_sample.y <= 0.0 or second_sample.y <= 0.0:
			continue
		total += first_sample.x / first_sample.y - second_sample.x / second_sample.y
		count += 1
	return total / float(count) if count > 0 else 0.0


static func _collision_mesh(descriptor: Dictionary, cell_size: float) -> Dictionary:
	var surface := descriptor["surface"] as Dictionary
	var arrays := surface["arrays"] as Array
	var vertices := FIT_GEOMETRY.skin_vertices_world(
			descriptor["mesh_instance"], arrays)
	var indices := arrays[Mesh.ARRAY_INDEX] as PackedInt32Array
	var triangles: Array[Dictionary] = []
	var grid: Dictionary = {}
	var bounds := AABB()
	var has_bounds := false
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
		var triangle_bounds := AABB(a, Vector3.ZERO).expand(b).expand(c)
		bounds = triangle_bounds if not has_bounds else bounds.merge(triangle_bounds)
		has_bounds = true
		var stored_index := triangles.size()
		triangles.append({
			"a": a,
			"b": b,
			"c": c,
			"normal": (b - a).cross(c - a).normalized(),
		})
		var minimum_cell := FIT_GEOMETRY.grid_cell(triangle_bounds.position, cell_size)
		var maximum_cell := FIT_GEOMETRY.grid_cell(triangle_bounds.end, cell_size)
		for x in range(minimum_cell.x, maximum_cell.x + 1):
			for y in range(minimum_cell.y, maximum_cell.y + 1):
				for z in range(minimum_cell.z, maximum_cell.z + 1):
					var cell := Vector3i(x, y, z)
					var bucket := grid.get(cell, PackedInt32Array()) as PackedInt32Array
					bucket.append(stored_index)
					grid[cell] = bucket
	return {
		"vertices": vertices,
		"indices": indices,
		"triangles": triangles,
		"grid": grid,
		"bounds": bounds,
	}


static func _surface_id(mesh_key: String, surface_index: int) -> String:
	return "%s\u001f%d" % [mesh_key, surface_index]


static func _pair_key(first: String, second: String) -> String:
	return first + "\u001e" + second if first < second else second + "\u001e" + first
