extends "res://tests/manual/foot_ik/foot_ik_live_penetration_check.gd"
## Test-only adapter: reuse the oracle's skinning inputs, not its collision arithmetic.
## All influenced vertices, including ball/heel/width, follow final post-modifier poses.


func capture(player: Player, ik: PlayerFootIKModifier, bone_filter: Dictionary) -> Dictionary:
	var points := PackedVector3Array()
	var regions: Array[StringName] = []
	for node: Node in player.body.character.find_children("*", "MeshInstance3D", true, false):
		var mesh_part := node as MeshInstance3D
		if mesh_part.mesh == null:
			continue
		var transforms := _mesh_bind_transforms(mesh_part, player.skeleton, ik)
		var names := _mesh_bind_bone_names(mesh_part, player.skeleton)
		for surface in mesh_part.mesh.get_surface_count():
			var arrays := mesh_part.mesh.surface_get_arrays(surface)
			var vertices := arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array
			var bones := (arrays[Mesh.ARRAY_BONES] as PackedInt32Array
					if arrays[Mesh.ARRAY_BONES] is PackedInt32Array else PackedInt32Array())
			var weights := (arrays[Mesh.ARRAY_WEIGHTS] as PackedFloat32Array
					if arrays[Mesh.ARRAY_WEIGHTS] is PackedFloat32Array else PackedFloat32Array())
			for index in vertices.size():
				if not _vertex_matches_bone_filter(index, vertices, bones, weights, names, bone_filter):
					continue
				var fallback := mesh_part.global_transform * vertices[index]
				points.append(_skin_vertex(index, vertices, bones, weights, transforms, fallback))
				regions.append(_dominant_skin_bone(index, vertices, bones, weights, names))
	return {"points": points, "regions": regions}
