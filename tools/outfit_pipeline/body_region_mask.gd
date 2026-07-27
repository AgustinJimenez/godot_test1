class_name BodyRegionMask
extends RefCounted

const DEFAULT_HIDDEN_BONES := [
	"pelvis",
	"spine_01",
	"spine_02",
	"spine_03",
	"clavicle_l",
	"clavicle_r",
	"upperarm_l",
	"upperarm_r",
	"lowerarm_l",
	"lowerarm_r",
	"thigh_l",
	"thigh_r",
	"calf_l",
	"calf_r",
	"foot_l",
	"foot_r",
	"ball_l",
	"ball_r",
]

const HAND_BONES := [
	"RightHand",
	"LeftHand",
	"thumb_01_l",
	"thumb_01_r",
	"thumb_02_l",
	"thumb_02_r",
	"thumb_03_l",
	"thumb_03_r",
	"index_01_l",
	"index_01_r",
	"index_02_l",
	"index_02_r",
	"index_03_l",
	"index_03_r",
	"mid_01_l",
	"mid_01_r",
	"mid_02_l",
	"mid_02_r",
	"mid_03_l",
	"mid_03_r",
	"ring_01_l",
	"ring_01_r",
	"ring_02_l",
	"ring_02_r",
	"ring_03_l",
	"ring_03_r",
	"pinky_01_l",
	"pinky_01_r",
	"pinky_02_l",
	"pinky_02_r",
	"pinky_03_l",
	"pinky_03_r",
]

const NECK_EXEMPT_BONES := ["neck_01", "Head"]
const NECK_EXEMPT_WEIGHT := 0.15

const SKIN_BRIDGE_MATERIAL_PATTERNS := [
	"regular_male",
	"regular_female",
]


static func apply(body_mesh: MeshInstance3D, outfit_root: Node3D) -> ArrayMesh:
	var skeleton := body_mesh.get_node_or_null(
			body_mesh.skeleton) as Skeleton3D
	var skin := body_mesh.skin
	if skeleton == null or skin == null:
		return body_mesh.mesh as ArrayMesh
	var arrays := _collect_surface_arrays(body_mesh)
	if arrays.is_empty():
		return body_mesh.mesh as ArrayMesh
	var vertices := arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array
	var bones := arrays[Mesh.ARRAY_BONES] as PackedInt32Array
	var weights := arrays[Mesh.ARRAY_WEIGHTS] as PackedFloat32Array
	var indices := arrays[Mesh.ARRAY_INDEX] as PackedInt32Array
	var blend_shapes := []
	var format := 0
	var primitive := Mesh.PRIMITIVE_TRIANGLES
	var material: Material = null
	var name := ""
	if body_mesh.mesh.get_surface_count() > 0:
		blend_shapes = (
				body_mesh.mesh.surface_get_blend_shape_arrays(0))
		format = body_mesh.mesh.surface_get_format(0)
		primitive = body_mesh.mesh.surface_get_primitive_type(0)
		material = body_mesh.mesh.surface_get_material(0)
		name = body_mesh.mesh.surface_get_name(0)
	var hidden := _compute_hidden(
			bones, weights, vertices.size(), skeleton, outfit_root)
	var kept_indices := _keep_triangle_indices(indices, hidden)
	var result := ArrayMesh.new()
	for blend_shape_index in blend_shapes.size():
		result.add_blend_shape(
				body_mesh.mesh.get_blend_shape_name(blend_shape_index))
	result.blend_shape_mode = body_mesh.mesh.blend_shape_mode
	var rebuilt_arrays := arrays.duplicate(true)
	rebuilt_arrays[Mesh.ARRAY_INDEX] = kept_indices
	result.add_surface_from_arrays(
			primitive, rebuilt_arrays, blend_shapes, {}, format)
	result.surface_set_material(0, material)
	result.surface_set_name(0, name)
	return result


static func outfit_supplies_hand_bridge(outfit_root: Node3D) -> bool:
	for node in outfit_root.find_children(
			"*", "MeshInstance3D", true, false):
		var mesh_instance := node as MeshInstance3D
		for surface_index in mesh_instance.mesh.get_surface_count():
			var mat := mesh_instance.mesh.surface_get_material(
					surface_index)
			if mat == null:
				continue
			var material_name := mat.resource_name.to_lower()
			for pattern in SKIN_BRIDGE_MATERIAL_PATTERNS:
				if pattern in material_name:
					return true
	return false


static func _collect_surface_arrays(body_mesh: MeshInstance3D) -> Array:
	var mesh := body_mesh.mesh
	if mesh == null or mesh.get_surface_count() == 0:
		return []
	return mesh.surface_get_arrays(0)


static func _compute_hidden(
	bones: PackedInt32Array,
	weights: PackedFloat32Array,
	vertex_count: int,
	skeleton: Skeleton3D,
	outfit_root: Node3D,
) -> Dictionary:
	var hidden := {}
	var hand_bones_to_hide := HAND_BONES if (
			outfit_supplies_hand_bridge(outfit_root)) else []
	var influences_per_vertex := 1
	if vertex_count > 0 and not bones.is_empty():
		influences_per_vertex = bones.size() / vertex_count
	if influences_per_vertex == 0:
		influences_per_vertex = 1
	for vertex_index in vertex_count:
		var best_weight := -1.0
		var best_bone_name := ""
		for influence in influences_per_vertex:
			var array_index := (
					vertex_index * influences_per_vertex + influence)
			if array_index >= bones.size():
				continue
			var weight := weights[array_index]
			if weight <= best_weight:
				continue
			var bone_index := bones[array_index]
			if bone_index < 0 or bone_index >= skeleton.get_bone_count():
				continue
			var bone_name := skeleton.get_bone_name(bone_index)
			best_weight = weight
			best_bone_name = String(bone_name)
		if best_bone_name.is_empty():
			continue
		if best_bone_name.to_lower() == "neck_01" or (
				best_bone_name.to_lower() == "head"):
			var exempt_weight := _sum_exempt_weight(
					bones, weights, vertex_index,
					influences_per_vertex, skeleton)
			if exempt_weight >= NECK_EXEMPT_WEIGHT:
				continue
		if DEFAULT_HIDDEN_BONES.has(StringName(best_bone_name)):
			hidden[vertex_index] = true
		elif not hand_bones_to_hide.is_empty() and (
				hand_bones_to_hide.has(StringName(best_bone_name))):
			hidden[vertex_index] = true
	return hidden


static func _sum_exempt_weight(
	bones: PackedInt32Array,
	weights: PackedFloat32Array,
	vertex_index: int,
	influences_per_vertex: int,
	skeleton: Skeleton3D,
) -> float:
	var total := 0.0
	for influence in influences_per_vertex:
		var array_index := (
				vertex_index * influences_per_vertex + influence)
		if array_index >= bones.size():
			continue
		var bone_index := bones[array_index]
		if bone_index < 0 or bone_index >= skeleton.get_bone_count():
			continue
		var bone_name := String(skeleton.get_bone_name(bone_index))
		if NECK_EXEMPT_BONES.has(StringName(bone_name)):
			total += weights[array_index]
	return total


static func _keep_triangle_indices(
	indices: PackedInt32Array,
	hidden: Dictionary,
) -> PackedInt32Array:
	if indices.is_empty():
		return indices
	var kept := PackedInt32Array()
	var triangle_count := indices.size() / 3
	for triangle_index in triangle_count:
		var a := indices[triangle_index * 3]
		var b := indices[triangle_index * 3 + 1]
		var c := indices[triangle_index * 3 + 2]
		if hidden.has(a) and hidden.has(b) and hidden.has(c):
			continue
		kept.append(a)
		kept.append(b)
		kept.append(c)
	return kept