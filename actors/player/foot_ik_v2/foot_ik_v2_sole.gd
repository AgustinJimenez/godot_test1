extends RefCounted
## The skinned sole of one foot: every foot-mesh vertex weighted onto the foot and toe bones, cached
## ONCE (walking the mesh costs ~8 ms), then replayed from the two bone poses. Each vertex is stored
## as its foot part and toe part, so a replay is two pose reads and a few multiplies per vertex.

const HEEL_SOLE_BAND := 0.04 # the heel is the rearmost point within this of the lowest vertex
const KEEP_BAND := 0.10 # vertices this near the rest sole can become the lowest point

var _foot := -1
var _toe := -1
var _foot_weight := PackedFloat32Array() # weight share on the foot bone
var _toe_weight := PackedFloat32Array()
var _foot_local := PackedVector3Array() # weighted bind-space position, foot part
var _toe_local := PackedVector3Array()


func _init(skel: Skeleton3D, character: Node, foot: int, toe: int) -> void:
	_foot = foot
	_toe = toe
	if character == null or not is_instance_valid(character):
		return
	for node: Node in character.find_children("*", "MeshInstance3D", true, false):
		var part := node as MeshInstance3D
		if part != null and part.mesh != null and part.get_skin_reference() != null:
			_add_mesh(skel, part)
	_prune(skel, KEEP_BAND)


func is_empty() -> bool:
	return _foot_weight.is_empty()


## The sole points in skeleton space: at rest, or (`live`) from the CURRENT bone poses.
func points(skel: Skeleton3D, live: bool) -> PackedVector3Array:
	var foot_pose := skel.get_bone_global_pose(_foot) if live else skel.get_bone_global_rest(_foot)
	var toe_pose := skel.get_bone_global_pose(_toe) if live else skel.get_bone_global_rest(_toe)
	var out := PackedVector3Array()
	out.resize(_foot_weight.size())
	for i in _foot_weight.size():
		out[i] = (foot_pose.basis * _foot_local[i] + foot_pose.origin * _foot_weight[i]
				+ toe_pose.basis * _toe_local[i] + toe_pose.origin * _toe_weight[i])
	return out


## How far the lowest foot-mesh vertex sits below the foot bone at rest.
func depth(skel: Skeleton3D) -> float:
	var foot_rest_y := skel.get_bone_global_rest(_foot).origin.y
	var lowest := INF
	for point: Vector3 in points(skel, false):
		lowest = minf(lowest, point.y)
	return foot_rest_y - lowest if is_finite(lowest) else foot_rest_y


## The rearmost sole-level point of the foot mesh, in the foot bone's rest space.
func heel_local(skel: Skeleton3D) -> Vector3:
	var all := points(skel, false)
	var foot_rest := skel.get_bone_global_rest(_foot)
	if all.is_empty() or _toe < 0:
		return Vector3.ZERO
	var forward := skel.get_bone_global_rest(_toe).origin - foot_rest.origin
	forward.y = 0.0
	forward = forward.normalized()
	var lowest := INF
	for point: Vector3 in all:
		lowest = minf(lowest, point.y)
	var heel := foot_rest.origin
	var rearmost := INF
	for point: Vector3 in all:
		if point.y > lowest + HEEL_SOLE_BAND:
			continue
		var along := point.dot(forward)
		if along < rearmost:
			rearmost = along
			heel = point
	heel.y = lowest # the contact point straight below the back of the heel, on the sole
	return foot_rest.affine_inverse() * heel


func _add_mesh(skel: Skeleton3D, part: MeshInstance3D) -> void:
	var skin := part.get_skin_reference().get_skin()
	if skin == null:
		return
	for surface in part.mesh.get_surface_count():
		var arrays := part.mesh.surface_get_arrays(surface)
		var vertices := arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array
		var bones := arrays[Mesh.ARRAY_BONES] as PackedInt32Array
		var weights := arrays[Mesh.ARRAY_WEIGHTS] as PackedFloat32Array
		if vertices.is_empty() or bones.is_empty() or weights.is_empty():
			continue
		var influences := bones.size() / vertices.size()
		for vertex in vertices.size():
			_add_vertex(skel, skin, vertices[vertex], bones, weights, vertex * influences, influences)


func _add_vertex(skel: Skeleton3D, skin: Skin, vertex: Vector3, bones: PackedInt32Array,
		weights: PackedFloat32Array, first: int, influences: int) -> void:
	var total := 0.0
	var foot_share := 0.0
	var toe_share := 0.0
	var foot_local := Vector3.ZERO
	var toe_local := Vector3.ZERO
	for slot in range(first, first + influences):
		var bind := bones[slot]
		var weight := weights[slot]
		if weight <= 0.0 or bind < 0 or bind >= skin.get_bind_count():
			continue
		var bone := skin.get_bind_bone(bind)
		if bone < 0:
			bone = skel.find_bone(skin.get_bind_name(bind))
		if bone < 0 or (bone != _foot and bone != _toe):
			continue
		var local := skin.get_bind_pose(bind) * vertex * weight
		total += weight
		if bone == _foot:
			foot_share += weight
			foot_local += local
		else:
			toe_share += weight
			toe_local += local
	if total > 0.5:
		_foot_weight.append(foot_share / total)
		_toe_weight.append(toe_share / total)
		_foot_local.append(foot_local / total)
		_toe_local.append(toe_local / total)


## The sole-level points in WORLD space under `to_world`: every vertex within `band` of the lowest.
## One pass finds the lowest, a second keeps only those, so the rest are never transformed.
func level_points(skel: Skeleton3D, to_world: Transform3D, band: float) -> Array[Vector3]:
	var local := points(skel, true)
	var b := to_world.basis
	var up := Vector3(b.x.y, b.y.y, b.z.y) # the world-Y row: a point's world height is up.dot(p)
	var heights := PackedFloat32Array()
	heights.resize(local.size())
	var lowest := INF
	for i in local.size():
		heights[i] = up.dot(local[i])
		lowest = minf(lowest, heights[i])
	var level: Array[Vector3] = []
	for i in local.size():
		if heights[i] <= lowest + band:
			level.append(to_world * local[i])
	return level


## Keep only the vertices within `band` of the sole at rest: a foot pitched or rolled by the IK
## still bottoms out on those, and the rest (ankle, laces, cuff) are never the lowest point.
func _prune(skel: Skeleton3D, band: float) -> void:
	var rest := points(skel, false)
	var lowest := INF
	for point: Vector3 in rest:
		lowest = minf(lowest, point.y)
	var keep := PackedInt32Array()
	for i in rest.size():
		if rest[i].y <= lowest + band:
			keep.append(i)
	var foot_weight := PackedFloat32Array()
	var toe_weight := PackedFloat32Array()
	var foot_local := PackedVector3Array()
	var toe_local := PackedVector3Array()
	for i in keep:
		foot_weight.append(_foot_weight[i])
		toe_weight.append(_toe_weight[i])
		foot_local.append(_foot_local[i])
		toe_local.append(_toe_local[i])
	_foot_weight = foot_weight
	_toe_weight = toe_weight
	_foot_local = foot_local
	_toe_local = toe_local
