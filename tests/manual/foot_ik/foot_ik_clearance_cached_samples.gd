extends "res://tests/manual/foot_ik/foot_ik_clearance_mesh_samples.gd"
## Explicitly rebuilt per actor/rig. Retains ALL selected points: no envelope approximation.

const SAMPLES := preload("res://tools/foot_ik/foot_clearance_skin_samples.gd")
var _parts: Array[Dictionary] = []
var _regions: Array[StringName] = []


func rebuild(player: Player, bone_filter: Dictionary) -> bool:
	_parts.clear()
	_regions.clear()
	for node: Node in player.body.character.find_children("*", "MeshInstance3D", true, false):
		var mesh_part := node as MeshInstance3D
		if mesh_part.mesh == null:
			continue
		var samples := SAMPLES.new()
		var names := _mesh_bind_bone_names(mesh_part, player.skeleton)
		for surface in mesh_part.mesh.get_surface_count():
			var arrays := mesh_part.mesh.surface_get_arrays(surface)
			var vertices := arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array
			var bones := (arrays[Mesh.ARRAY_BONES] as PackedInt32Array
					if arrays[Mesh.ARRAY_BONES] is PackedInt32Array else PackedInt32Array())
			var weights := (arrays[Mesh.ARRAY_WEIGHTS] as PackedFloat32Array
					if arrays[Mesh.ARRAY_WEIGHTS] is PackedFloat32Array else PackedFloat32Array())
			var selected := PackedInt32Array()
			for index in vertices.size():
				if _vertex_matches_bone_filter(index, vertices, bones, weights, names, bone_filter):
					selected.append(index)
					_regions.append(_dominant_skin_bone(index, vertices, bones, weights, names))
			if not selected.is_empty() and not samples.append_surface(vertices, bones, weights, selected):
				_parts.clear()
				_regions.clear()
				return false
		_parts.append({"mesh": mesh_part, "samples": samples})
	return not _regions.is_empty()


func capture(player: Player, ik: PlayerFootIKModifier, _bone_filter: Dictionary) -> Dictionary:
	var points := PackedVector3Array()
	for part: Dictionary in _parts:
		var mesh_part: MeshInstance3D = part["mesh"]
		var samples: SAMPLES = part["samples"]
		points.append_array(samples.sample(_mesh_bind_transforms(mesh_part, player.skeleton, ik),
				mesh_part.global_transform))
	return {"points": points, "regions": _regions}
