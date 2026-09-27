class_name ProceduralWalkMeshClearance
extends RefCounted
## Measures final skinned foot vertices against the lab's visual flat floor.

var _parts: Array[Dictionary] = []
var vertex_count := 0
var last_low_positions: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO]
## Native +Z is forward. Per-millimetre highest shoe depth below the ankle, used to
## distinguish a low heel from a raised toe when checking neighboring stair treads.
var last_profiles: Array[Dictionary] = [{}, {}]


func prepare(character: Node3D, skeleton: Skeleton3D) -> void:
	_parts.clear()
	vertex_count = 0
	for node: Node in character.find_children("*", "MeshInstance3D", true, false):
		var mesh_part := node as MeshInstance3D
		if mesh_part.mesh == null or mesh_part.get_skin_reference() == null:
			continue
		var skin := mesh_part.get_skin_reference().get_skin()
		if skin == null:
			continue
		var binds: Array[Dictionary] = []
		for bind in skin.get_bind_count():
			var bone := skin.get_bind_bone(bind)
			if bone < 0:
				bone = skeleton.find_bone(skin.get_bind_name(bind))
			var name: StringName = skeleton.get_bone_name(bone) if bone >= 0 else &""
			binds.append({"bone": bone, "inverse_rest": skin.get_bind_pose(bind),
					"side": (0 if String(name).begins_with("Left") else
					1 if String(name).begins_with("Right") else -1),
					"foot": String(name).contains("Foot") or String(name).contains("Toe")})
		var points: Array[Dictionary] = []
		for surface in mesh_part.mesh.get_surface_count():
			var arrays := mesh_part.mesh.surface_get_arrays(surface)
			var vertices := arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array
			var bones := arrays[Mesh.ARRAY_BONES] as PackedInt32Array
			var weights := arrays[Mesh.ARRAY_WEIGHTS] as PackedFloat32Array
			if vertices.is_empty() or bones.is_empty() or weights.is_empty():
				continue
			var influences := bones.size() / vertices.size()
			for vertex in vertices.size():
				var left_weight := 0.0
				var right_weight := 0.0
				for influence in influences:
					var slot := vertex * influences + influence
					var bind := bones[slot]
					if bind < 0 or bind >= binds.size() or not binds[bind]["foot"]:
						continue
					if binds[bind]["side"] == 0:
						left_weight += weights[slot]
					elif binds[bind]["side"] == 1:
						right_weight += weights[slot]
				var side := 0 if left_weight >= right_weight else 1
				if maxf(left_weight, right_weight) < 0.5:
					continue
				points.append({"position": vertices[vertex], "side": side,
						"offset": vertex * influences, "influences": influences,
						"bones": bones, "weights": weights})
		vertex_count += points.size()
		_parts.append({"binds": binds, "points": points})


func sample(skeleton: Skeleton3D,
		final_poses: Array[Transform3D], support_height: Callable = Callable(),
		ankle_worlds: Array[Vector3] = []) -> Array[float]:
	var minimum: Array[float] = [INF, INF]
	last_low_positions = [Vector3.ZERO, Vector3.ZERO]
	last_profiles = [{}, {}]
	for part: Dictionary in _parts:
		var transforms: Array[Transform3D] = []
		for bind: Dictionary in part["binds"]:
			var bone: int = bind["bone"]
			transforms.append(skeleton.global_transform * final_poses[bone]
					* bind["inverse_rest"] if bone >= 0 else Transform3D.IDENTITY)
		for point: Dictionary in part["points"]:
			var position := Vector3.ZERO
			var total := 0.0
			for influence: int in point["influences"]:
				var slot: int = point["offset"] + influence
				var weight: float = point["weights"][slot]
				var bind: int = point["bones"][slot]
				if weight <= 0.0 or bind < 0 or bind >= transforms.size():
					continue
				position += (transforms[bind] * point["position"]) * weight
				total += weight
			if total > 0.0:
				var world_pos := position / total
				var side: int = point["side"]
				if ankle_worlds.size() == 2:
					var ahead := world_pos.z - ankle_worlds[side].z
					var bin := roundi(ahead * 1000.0)
					var drop := ankle_worlds[side].y - world_pos.y
					last_profiles[side][bin] = maxf(
							float(last_profiles[side].get(bin, -INF)), drop)
				var foot_height := world_pos.y
				if support_height.is_valid():
					foot_height -= support_height.call(world_pos.z)
				if foot_height < minimum[side]:
					minimum[side] = foot_height
					last_low_positions[side] = world_pos
	return minimum
