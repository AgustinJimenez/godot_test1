class_name OutfitFitLayers
extends RefCounted
## Resolves intersections between garment surfaces without changing their authored order.
##
## Layer order is measured only where two surfaces project onto the same body-space cells.
## During cleanup the authored outer surface moves outward; for a selected-only fit, an
## authored inner selection may move inward only while preserving body clearance.

const FIT_GEOMETRY := preload("res://ui/outfit_fit_geometry.gd")
const ORDER_CELL_SIZE := 0.08
const COMPONENT_DEPTH_CELL_SIZE := 0.03


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
	var pairs: Array[Dictionary] = []
	for first_index in surfaces.size():
		for second_index in range(first_index + 1, surfaces.size()):
			var first: Dictionary = surfaces[first_index]
			var second: Dictionary = surfaces[second_index]
			var shared := _shared_depth_difference(
					depth_maps[first["id"]], depth_maps[second["id"]])
			if int(shared["count"]) == 0:
				continue
			var difference := float(shared["difference"])
			if absf(difference) < 0.0001:
				difference = (
						float((depth_maps[first["id"]] as Dictionary)["average"])
						- float((depth_maps[second["id"]] as Dictionary)["average"]))
			var outer_id := (
					first["id"] as String
					if difference >= 0.0 else second["id"] as String)
			var inner_id := (
					second["id"] as String
					if difference >= 0.0 else first["id"] as String)
			pairs.append({
				"inner_id": inner_id,
				"outer_id": outer_id,
				"shared_cells": shared["count"],
			})
	var levels := _assign_layer_levels(surfaces, pairs, depth_maps)
	var maximum_level := 0
	for pair in pairs:
		var level := int(levels.get(pair["outer_id"], 1))
		pair["level"] = level
		maximum_level = maxi(maximum_level, level)
	pairs.sort_custom(
			func(first: Dictionary, second: Dictionary) -> bool:
				if first["level"] == second["level"]:
					return first["outer_id"] < second["outer_id"]
				return first["level"] < second["level"])
	return {
		"pairs": pairs,
		"levels": maximum_level,
		"components": surfaces.size(),
	}


static func resolve_pass(
	mesh_states: Dictionary,
	auto_surface_offsets: Dictionary,
	authored_order: Dictionary,
	context: Dictionary,
	filter_mesh: String = "",
	filter_surface: int = -1,
	filter_component: int = -1,
	target_level: int = -1,
) -> int:
	var descriptors := _clothing_surfaces(mesh_states)
	var descriptor_by_id: Dictionary = {}
	for descriptor in descriptors:
		descriptor_by_id[descriptor["id"]] = descriptor
	var collision_meshes: Dictionary = {}
	var filter_enabled := not filter_mesh.is_empty() and filter_surface >= 0
	var pushed := 0
	for pair_variant in authored_order.get("pairs", []):
		var pair := pair_variant as Dictionary
		if target_level >= 0 and pair["level"] != target_level:
			continue
		var outer: Dictionary = descriptor_by_id.get(pair["outer_id"], {})
		var inner: Dictionary = descriptor_by_id.get(pair["inner_id"], {})
		if outer.is_empty() or inner.is_empty():
			continue
		var moving := outer
		var reference := inner
		var direction := 1.0
		if filter_enabled:
			var outer_selected := _descriptor_is_selected(
					outer, filter_mesh, filter_surface, filter_component)
			var inner_selected := _descriptor_is_selected(
					inner, filter_mesh, filter_surface, filter_component)
			if outer_selected:
				pass
			elif inner_selected:
				moving = inner
				reference = outer
				direction = -1.0
			else:
				continue
		for descriptor in [moving, reference]:
			if not collision_meshes.has(descriptor["id"]):
				collision_meshes[descriptor["id"]] = _collision_mesh(
						descriptor, context)
		var moving_collision: Dictionary = collision_meshes[moving["id"]]
		var reference_collision: Dictionary = collision_meshes[reference["id"]]
		if not (moving_collision["bounds"] as AABB).intersects(
				reference_collision["bounds"] as AABB):
			continue
		pushed += _separate_pair(
				moving,
				moving_collision,
				reference_collision,
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
	var mesh_key := moving["mesh_key"] as String
	var surface_index := moving["surface_index"] as int
	var mesh_instance := moving["mesh_instance"] as MeshInstance3D
	var mesh_offsets := auto_surface_offsets[mesh_key] as Array
	var offsets := mesh_offsets[surface_index] as PackedVector3Array
	var same_surface: bool = (
			moving["mesh_key"] == reference_collision["mesh_key"]
			and moving["surface_index"] == reference_collision["surface_index"])
	if same_surface:
		return _separate_same_surface_depth(
				moving,
				moving_collision,
				reference_collision,
				auto_surface_offsets,
				context,
				direction)
	var intersections := FIT_GEOMETRY.find_intersections(
			moving_collision["vertices"],
			moving_collision["indices"],
			reference_collision["triangles"],
			reference_collision["grid"],
			context["body_cell_size"],
			1.0)
	var marked := intersections["cloth_vertices"] as Dictionary
	if marked.is_empty():
		return 0
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
		var moving_depth := (
				current_world - (projection["position"] as Vector3)).dot(normal)
		var push_distance := float(context["layer_step"])
		if direction < 0.0:
			push_distance = minf(
					push_distance, moving_depth - float(context["body_clearance"]))
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


static func _separate_same_surface_depth(
	moving: Dictionary,
	moving_collision: Dictionary,
	reference_collision: Dictionary,
	auto_surface_offsets: Dictionary,
	context: Dictionary,
	direction: float,
) -> int:
	var mesh_key := moving["mesh_key"] as String
	var surface_index := moving["surface_index"] as int
	var mesh_instance := moving["mesh_instance"] as MeshInstance3D
	var mesh_offsets := auto_surface_offsets[mesh_key] as Array
	var offsets := mesh_offsets[surface_index] as PackedVector3Array
	var world_vertices := moving_collision["vertices"] as PackedVector3Array
	var projections := moving_collision["projections"] as Dictionary
	var reference_samples := reference_collision["depth_samples"] as Dictionary
	var layer_clearance := float(context["layer_clearance"])
	var pushed := 0
	for vertex_index_variant in (moving["vertex_indices"] as PackedInt32Array):
		var vertex_index := int(vertex_index_variant)
		if not projections.has(vertex_index):
			continue
		var projection := projections[vertex_index] as Dictionary
		var cell := projection["cell"] as Vector3i
		var reference_depth: Variant = _neighbor_reference_depth(
				reference_samples,
				cell,
				projection["position"])
		if reference_depth == null:
			continue
		var moving_depth := float(projection["depth"])
		var push_distance := 0.0
		if direction > 0.0:
			push_distance = (
					float(reference_depth) + layer_clearance - moving_depth)
		else:
			push_distance = (
					moving_depth
					- (float(reference_depth) - layer_clearance))
			push_distance = minf(
					push_distance,
					moving_depth - float(context["body_clearance"]))
		push_distance = minf(push_distance, float(context["layer_step"]))
		if push_distance <= 0.0:
			continue
		var current_world := world_vertices[vertex_index]
		var pushed_world := (
				current_world
				+ (projection["normal"] as Vector3) * push_distance * direction)
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


static func _neighbor_reference_depth(
	depth_samples: Dictionary,
	center: Vector3i,
	position: Vector3,
) -> Variant:
	const SAMPLE_RADIUS := 0.06
	const SAMPLE_COUNT := 4
	var nearest: Array[Vector2] = []
	for x_offset in range(-1, 2):
		for y_offset in range(-1, 2):
			for z_offset in range(-1, 2):
				var cell := center + Vector3i(x_offset, y_offset, z_offset)
				if not depth_samples.has(cell):
					continue
				for sample_variant in (depth_samples[cell] as Array):
					var sample := sample_variant as Vector4
					var distance := position.distance_to(Vector3(
							sample.x, sample.y, sample.z))
					if distance > SAMPLE_RADIUS:
						continue
					nearest.append(Vector2(distance, sample.w))
	nearest.sort_custom(
			func(first: Vector2, second: Vector2) -> bool:
				return first.x < second.x)
	if nearest.is_empty():
		return null
	var weighted_depth := 0.0
	var total_weight := 0.0
	for sample_index in mini(nearest.size(), SAMPLE_COUNT):
		var sample := nearest[sample_index]
		var weight := 1.0 / maxf(sample.x, 0.001)
		weighted_depth += sample.y * weight
		total_weight += weight
	return weighted_depth / total_weight


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
			var components := surface_components(surface["arrays"])
			for component_index in components.size():
				var component := components[component_index] as Dictionary
				result.append({
					"id": "%s\u001f%d" % [
							_surface_id(mesh_key, surface_index), component_index],
					"mesh_key": mesh_key,
					"surface_index": surface_index,
					"component_index": component_index,
					"mesh_instance": mesh_instance,
					"surface": surface,
					"indices": component["indices"],
					"vertex_indices": component["vertex_indices"],
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
	for vertex_index in (descriptor["vertex_indices"] as PackedInt32Array):
		var point := world_vertices[vertex_index]
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


static func _shared_depth_difference(first: Dictionary, second: Dictionary) -> Dictionary:
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
	return {
		"difference": total / float(count) if count > 0 else 0.0,
		"count": count,
	}


static func _assign_layer_levels(
	descriptors: Array[Dictionary],
	pairs: Array[Dictionary],
	depth_maps: Dictionary,
) -> Dictionary:
	var levels: Dictionary = {}
	var indegrees: Dictionary = {}
	var outgoing: Dictionary = {}
	for descriptor in descriptors:
		var descriptor_id := descriptor["id"] as String
		levels[descriptor_id] = 1
		indegrees[descriptor_id] = 0
		outgoing[descriptor_id] = []
	for pair in pairs:
		var inner_id := pair["inner_id"] as String
		var outer_id := pair["outer_id"] as String
		(outgoing[inner_id] as Array).append(outer_id)
		indegrees[outer_id] = int(indegrees[outer_id]) + 1
	var ready: Array[String] = []
	for descriptor_id_variant in indegrees:
		var descriptor_id := String(descriptor_id_variant)
		if int(indegrees[descriptor_id]) == 0:
			ready.append(descriptor_id)
	ready.sort()
	var processed: Dictionary = {}
	while not ready.is_empty():
		var inner_id := ready.pop_front() as String
		processed[inner_id] = true
		for outer_id_variant in (outgoing[inner_id] as Array):
			var outer_id := String(outer_id_variant)
			levels[outer_id] = maxi(
					int(levels[outer_id]), int(levels[inner_id]) + 1)
			indegrees[outer_id] = int(indegrees[outer_id]) - 1
			if int(indegrees[outer_id]) == 0:
				ready.append(outer_id)
				ready.sort()
	var cyclic: Array[String] = []
	for descriptor_id_variant in indegrees:
		var descriptor_id := String(descriptor_id_variant)
		if not processed.has(descriptor_id):
			cyclic.append(descriptor_id)
	cyclic.sort_custom(
			func(first: String, second: String) -> bool:
				return (
					float((depth_maps[first] as Dictionary)["average"])
					< float((depth_maps[second] as Dictionary)["average"])))
	var cycle_level := 2
	for descriptor_id in cyclic:
		levels[descriptor_id] = cycle_level
		cycle_level += 1
	return levels


static func _collision_mesh(
	descriptor: Dictionary,
	context: Dictionary = {},
) -> Dictionary:
	var surface := descriptor["surface"] as Dictionary
	var arrays := surface["arrays"] as Array
	var vertices := FIT_GEOMETRY.skin_vertices_world(
			descriptor["mesh_instance"], arrays)
	var indices := descriptor["indices"] as PackedInt32Array
	var bounds := AABB()
	var has_bounds := false
	var triangles: Array[Dictionary] = []
	var grid: Dictionary = {}
	var projections: Dictionary = {}
	var depth_samples: Dictionary = {}
	for vertex_index in (descriptor["vertex_indices"] as PackedInt32Array):
		var point := vertices[vertex_index]
		var point_bounds := AABB(point, Vector3.ZERO)
		bounds = point_bounds if not has_bounds else bounds.merge(point_bounds)
		has_bounds = true
		var projection := FIT_GEOMETRY.closest_body_projection(
				point,
				context["body_triangles"],
				context["body_grid"],
				context["body_cell_size"],
				context["search_radius"],
				context["body_normal_sign"])
		if projection.is_empty():
			continue
		var normal := projection["normal"] as Vector3
		var depth := (point - (projection["position"] as Vector3)).dot(normal)
		var cell := FIT_GEOMETRY.grid_cell(
				projection["position"], COMPONENT_DEPTH_CELL_SIZE)
		projections[vertex_index] = {
			"cell": cell,
			"depth": depth,
			"normal": normal,
			"position": projection["position"],
		}
		var samples: Array = depth_samples.get(cell, [])
		var body_position := projection["position"] as Vector3
		samples.append(Vector4(
				body_position.x, body_position.y, body_position.z, depth))
		depth_samples[cell] = samples
	for triangle_start in range(0, indices.size(), 3):
		var a := vertices[indices[triangle_start]]
		var b := vertices[indices[triangle_start + 1]]
		var c := vertices[indices[triangle_start + 2]]
		var triangle_bounds := AABB(a, Vector3.ZERO).expand(b).expand(c)
		var stored_index := triangles.size()
		triangles.append({
			"a": a,
			"b": b,
			"c": c,
			"normal": (b - a).cross(c - a).normalized(),
		})
		var minimum_cell := FIT_GEOMETRY.grid_cell(
				triangle_bounds.position, context["body_cell_size"])
		var maximum_cell := FIT_GEOMETRY.grid_cell(
				triangle_bounds.end, context["body_cell_size"])
		for x in range(minimum_cell.x, maximum_cell.x + 1):
			for y in range(minimum_cell.y, maximum_cell.y + 1):
				for z in range(minimum_cell.z, maximum_cell.z + 1):
					var cell := Vector3i(x, y, z)
					var bucket := grid.get(cell, PackedInt32Array()) as PackedInt32Array
					bucket.append(stored_index)
					grid[cell] = bucket
	return {
		"mesh_key": descriptor["mesh_key"],
		"surface_index": descriptor["surface_index"],
		"vertices": vertices,
		"indices": indices,
		"bounds": bounds,
		"triangles": triangles,
		"grid": grid,
		"projections": projections,
		"depth_samples": depth_samples,
	}


static func _surface_id(mesh_key: String, surface_index: int) -> String:
	return "%s\u001f%d" % [mesh_key, surface_index]


static func _descriptor_is_selected(
	descriptor: Dictionary,
	mesh_key: String,
	surface_index: int,
	component_index: int = -1,
) -> bool:
	return (
			descriptor["mesh_key"] == mesh_key
			and descriptor["surface_index"] == surface_index
			and (
				component_index < 0
				or descriptor["component_index"] == component_index))


static func surface_components(arrays: Array) -> Array[Dictionary]:
	var vertices := arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array
	var source_indices := arrays[Mesh.ARRAY_INDEX] as PackedInt32Array
	var indices := source_indices
	if indices.is_empty():
		indices = PackedInt32Array()
		indices.resize(vertices.size())
		for vertex_index in vertices.size():
			indices[vertex_index] = vertex_index
	var parents: Array[int] = []
	parents.resize(vertices.size())
	for vertex_index in vertices.size():
		parents[vertex_index] = vertex_index
	var position_owners: Dictionary = {}
	for vertex_index in vertices.size():
		var position_key := _position_key(vertices[vertex_index])
		if position_owners.has(position_key):
			_union(parents, vertex_index, int(position_owners[position_key]))
		else:
			position_owners[position_key] = vertex_index
	for triangle_start in range(0, indices.size(), 3):
		_union(parents, indices[triangle_start], indices[triangle_start + 1])
		_union(parents, indices[triangle_start], indices[triangle_start + 2])
	var grouped_indices: Dictionary = {}
	var grouped_vertices: Dictionary = {}
	for triangle_start in range(0, indices.size(), 3):
		var root := _find_root(parents, indices[triangle_start])
		var component_indices := grouped_indices.get(
				root, PackedInt32Array()) as PackedInt32Array
		var component_vertices: Dictionary = grouped_vertices.get(root, {})
		for corner in 3:
			var vertex_index := indices[triangle_start + corner]
			component_indices.append(vertex_index)
			component_vertices[vertex_index] = true
		grouped_indices[root] = component_indices
		grouped_vertices[root] = component_vertices
	var result: Array[Dictionary] = []
	for root in grouped_indices:
		var vertex_indices := PackedInt32Array()
		var first_vertex := 2147483647
		for vertex_index in (grouped_vertices[root] as Dictionary):
			vertex_indices.append(vertex_index)
			first_vertex = mini(first_vertex, vertex_index)
		result.append({
			"indices": grouped_indices[root],
			"vertex_indices": vertex_indices,
			"first_vertex": first_vertex,
		})
	result.sort_custom(
			func(first: Dictionary, second: Dictionary) -> bool:
				return first["first_vertex"] < second["first_vertex"])
	return result


static func _find_root(parents: Array[int], vertex_index: int) -> int:
	var root := vertex_index
	while parents[root] != root:
		root = parents[root]
	var current := vertex_index
	while parents[current] != current:
		var next := parents[current]
		parents[current] = root
		current = next
	return root


static func _union(parents: Array[int], first: int, second: int) -> void:
	var first_root := _find_root(parents, first)
	var second_root := _find_root(parents, second)
	if first_root != second_root:
		parents[second_root] = first_root


static func _position_key(position: Vector3) -> Vector3i:
	const WELD_EPSILON := 0.0001
	return Vector3i(
			roundi(position.x / WELD_EPSILON),
			roundi(position.y / WELD_EPSILON),
			roundi(position.z / WELD_EPSILON))
