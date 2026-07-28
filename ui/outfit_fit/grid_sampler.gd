class_name OutfitFitGridSampler
extends RefCounted
## Picks one representative garment vertex per world-space grid cell and surface direction.


static func sample(mesh_states: Dictionary, spacing: float) -> Array[Dictionary]:
	var grid: Dictionary = {}
	for mesh_key_variant in mesh_states:
		var mesh_key := String(mesh_key_variant)
		var state: Dictionary = mesh_states[mesh_key]
		var mesh_instance := state["node"] as MeshInstance3D
		var surfaces: Array = state["surfaces"]
		for surface_index in surfaces.size():
			var surface: Dictionary = surfaces[surface_index]
			if not surface["is_clothing"]:
				continue
			var vertices: PackedVector3Array = surface["base_vertices"]
			var arrays: Array = surface["arrays"]
			var normals := arrays[Mesh.ARRAY_NORMAL] as PackedVector3Array
			for vertex_index in vertices.size():
				var world_position := mesh_instance.to_global(vertices[vertex_index])
				var cell := Vector3i(
						floori(world_position.x / spacing),
						floori(world_position.y / spacing),
						floori(world_position.z / spacing))
				var cell_center := (Vector3(cell) + Vector3.ONE * 0.5) * spacing
				var world_normal := Vector3.ZERO
				if vertex_index < normals.size():
					world_normal = (
							mesh_instance.global_basis * normals[vertex_index]).normalized()
				var candidates: Array = grid.get(cell, [])
				var group_index := _matching_normal_group(candidates, world_normal)
				var record := {
					"mesh": mesh_key,
					"surface": surface_index,
					"vertex": vertex_index,
					"vertex_count": vertices.size(),
					"normal": world_normal,
					"distance_squared": world_position.distance_squared_to(cell_center),
				}
				if group_index < 0:
					candidates.append(record)
				elif (float(record["distance_squared"])
						< float(candidates[group_index]["distance_squared"])):
					candidates[group_index] = record
				grid[cell] = candidates
	var result: Array[Dictionary] = []
	for candidates_variant in grid.values():
		for candidate_variant in candidates_variant as Array:
			result.append(candidate_variant as Dictionary)
	return result


static func _matching_normal_group(candidates: Array, normal: Vector3) -> int:
	for index in candidates.size():
		var candidate: Dictionary = candidates[index]
		var candidate_normal: Vector3 = candidate["normal"]
		if (normal.is_zero_approx() or candidate_normal.is_zero_approx()
				or normal.dot(candidate_normal) > 0.5):
			return index
	return -1
