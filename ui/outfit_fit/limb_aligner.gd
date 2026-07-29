class_name OutfitFitLimbAligner
extends RefCounted
## Gross rest-frame alignment for rigid distal-limb garment components.
##
## Contact fitting is intentionally a fine surface correction. Before it runs, this helper maps
## boots/shoes and similar components from their outfit skeleton's authored calf/foot frames into
## the selected body's corresponding rest frames. Existing skin weights blend the per-bone rigid
## transforms across joints, preserving the garment silhouette around the ankle.

const OUTFIT_COMPONENTS := preload("res://ui/outfit_fit/components.gd")

const MINIMUM_DISTAL_WEIGHT_COVERAGE := 0.85
const POSITION_EPSILON := 0.00001
const ROTATION_EPSILON_RADIANS := 0.0001


static func apply(
	mesh_states: Dictionary,
	auto_offsets: Dictionary,
	body_mesh: MeshInstance3D,
	filter_mesh: String = "",
	filter_surface: int = -1,
	filter_component: int = -1,
) -> Dictionary:
	var body_skeleton := body_mesh.get_node_or_null(body_mesh.skeleton) as Skeleton3D
	if body_skeleton == null:
		return {
			"vertices": 0,
			"components": 0,
			"maximum_rotation": 0.0,
			"maximum_translation": 0.0,
			"vertex_sets": {},
		}
	var filter_enabled := not filter_mesh.is_empty() and filter_surface >= 0
	var adjusted_vertices := 0
	var adjusted_components := 0
	var aligned_vertex_sets: Dictionary = {}
	var maximum_rotation := 0.0
	var maximum_translation := 0.0
	for mesh_key_variant in mesh_states:
		var mesh_key := String(mesh_key_variant)
		if filter_enabled and mesh_key != filter_mesh:
			continue
		var state := mesh_states[mesh_key] as Dictionary
		for surface_index in (state["surfaces"] as Array).size():
			if filter_enabled and surface_index != filter_surface:
				continue
			var surface := (state["surfaces"] as Array)[surface_index] as Dictionary
			surface["rigid_fit_components"] = {}
			surface["rigid_fit_component_sides"] = {}
			surface.erase("rigid_fit_baseline_offsets")
			surface.erase("rigid_fit_component_links")
	for mesh_key_variant in mesh_states:
		var mesh_key := String(mesh_key_variant)
		if filter_enabled and mesh_key != filter_mesh:
			continue
		var state: Dictionary = mesh_states[mesh_key]
		var mesh_instance := state["node"] as MeshInstance3D
		var outfit_skeleton := (
				mesh_instance.get_node_or_null(mesh_instance.skeleton) as Skeleton3D)
		if outfit_skeleton == null:
			continue
		var surfaces: Array = state["surfaces"]
		var mesh_offsets := auto_offsets[mesh_key] as Array
		for surface_index in surfaces.size():
			if filter_enabled and surface_index != filter_surface:
				continue
			var surface: Dictionary = surfaces[surface_index]
			if not surface["is_clothing"]:
				continue
			var components: Array = surface["components"]
			var component_start := (
					filter_component if filter_enabled and filter_component >= 0 else 0)
			var component_end := (
					filter_component + 1
					if filter_enabled and filter_component >= 0
					else components.size())
			for component_index in range(component_start, component_end):
				if component_index < 0 or component_index >= components.size():
					continue
				var component := components[component_index] as Dictionary
				var alignment := _component_alignment(
						mesh_instance,
						outfit_skeleton,
						body_skeleton,
						surface,
						component)
				if alignment.is_empty():
					continue
				var rigid_components := (
						surface["rigid_fit_components"] as Dictionary)
				rigid_components[component_index] = true
				surface["rigid_fit_components"] = rigid_components
				var rigid_component_sides := (
						surface["rigid_fit_component_sides"] as Dictionary)
				rigid_component_sides[component_index] = String(alignment["side"])
				surface["rigid_fit_component_sides"] = rigid_component_sides
				var offsets := mesh_offsets[surface_index] as PackedVector3Array
				var component_offsets := alignment["offsets"] as Dictionary
				if not aligned_vertex_sets.has(mesh_key):
					aligned_vertex_sets[mesh_key] = {}
				var mesh_vertex_sets := aligned_vertex_sets[mesh_key] as Dictionary
				var aligned_vertices := mesh_vertex_sets.get(surface_index, {}) as Dictionary
				for vertex_index_variant in component_offsets:
					var vertex_index := int(vertex_index_variant)
					offsets[vertex_index] = component_offsets[vertex_index]
					aligned_vertices[vertex_index] = true
					adjusted_vertices += 1
				mesh_vertex_sets[surface_index] = aligned_vertices
				aligned_vertex_sets[mesh_key] = mesh_vertex_sets
				mesh_offsets[surface_index] = offsets
				adjusted_components += 1
				maximum_rotation = maxf(
						maximum_rotation, float(alignment["maximum_rotation"]))
				maximum_translation = maxf(
						maximum_translation, float(alignment["maximum_translation"]))
			if not (surface["rigid_fit_components"] as Dictionary).is_empty():
				surface["rigid_fit_baseline_offsets"] = (
						mesh_offsets[surface_index] as PackedVector3Array).duplicate()
		auto_offsets[mesh_key] = mesh_offsets
	if adjusted_vertices > 0:
		OUTFIT_COMPONENTS.synchronize_auto_offset_constraints(
				mesh_states, auto_offsets, filter_mesh, filter_surface)
	return {
		"vertices": adjusted_vertices,
		"components": adjusted_components,
		"maximum_rotation": maximum_rotation,
		"maximum_translation": maximum_translation,
		"vertex_sets": aligned_vertex_sets,
	}


static func _component_alignment(
	mesh_instance: MeshInstance3D,
	outfit_skeleton: Skeleton3D,
	body_skeleton: Skeleton3D,
	surface: Dictionary,
	component: Dictionary,
) -> Dictionary:
	var arrays: Array = surface["arrays"]
	var vertices := surface["base_vertices"] as PackedVector3Array
	var bones := arrays[Mesh.ARRAY_BONES] as PackedInt32Array
	var weights := arrays[Mesh.ARRAY_WEIGHTS] as PackedFloat32Array
	var skin := mesh_instance.skin
	if skin == null or bones.is_empty() or weights.is_empty() or vertices.is_empty():
		return {}
	var influences := bones.size() / vertices.size()
	if influences <= 0:
		return {}
	var component_vertices := component["vertex_indices"] as PackedInt32Array
	var side_weights := {"left": 0.0, "right": 0.0}
	var total_weight := 0.0
	for vertex_index in component_vertices:
		for influence in influences:
			var value_index := vertex_index * influences + influence
			var weight := weights[value_index]
			if weight <= 0.0:
				continue
			total_weight += weight
			var bone_name := _bind_bone_name(
					skin, outfit_skeleton, bones[value_index])
			var side := _distal_leg_side(bone_name)
			if not side.is_empty():
				side_weights[side] = float(side_weights[side]) + weight
	if total_weight <= 0.0:
		return {}
	var dominant_side := (
			"left" if float(side_weights["left"]) >= float(side_weights["right"]) else "right")
	if float(side_weights[dominant_side]) / total_weight < MINIMUM_DISTAL_WEIGHT_COVERAGE:
		return {}
	var corrections: Dictionary = {}
	var maximum_rotation := 0.0
	var maximum_translation := 0.0
	for vertex_index in component_vertices:
		for influence in influences:
			var value_index := vertex_index * influences + influence
			var weight := weights[value_index]
			if weight <= 0.0:
				continue
			var bind_index := bones[value_index]
			if corrections.has(bind_index):
				continue
			var bone_name := _bind_bone_name(skin, outfit_skeleton, bind_index)
			if bone_name.is_empty():
				continue
			var outfit_bone := outfit_skeleton.find_bone(bone_name)
			var body_bone := body_skeleton.find_bone(bone_name)
			if outfit_bone < 0 or body_bone < 0:
				continue
			var source_frame := (
					outfit_skeleton.global_transform
					* outfit_skeleton.get_bone_global_rest(outfit_bone))
			var target_frame := (
					body_skeleton.global_transform
					* body_skeleton.get_bone_global_rest(body_bone))
			var correction := target_frame * source_frame.affine_inverse()
			corrections[bind_index] = correction
			maximum_rotation = maxf(
					maximum_rotation,
					correction.basis.get_rotation_quaternion().get_angle())
			maximum_translation = maxf(
					maximum_translation, correction.origin.length())
	if corrections.is_empty() or (
			maximum_rotation < ROTATION_EPSILON_RADIANS
			and maximum_translation < POSITION_EPSILON):
		return {}
	var aligned_offsets: Dictionary = {}
	for vertex_index in component_vertices:
		var source_world := mesh_instance.to_global(vertices[vertex_index])
		var aligned_world := Vector3.ZERO
		var applied_weight := 0.0
		for influence in influences:
			var value_index := vertex_index * influences + influence
			var weight := weights[value_index]
			if weight <= 0.0:
				continue
			var correction := corrections.get(bones[value_index]) as Transform3D
			if correction == null:
				continue
			aligned_world += (correction * source_world) * weight
			applied_weight += weight
		if applied_weight <= 0.0:
			continue
		if applied_weight < 1.0:
			aligned_world += source_world * (1.0 - applied_weight)
		aligned_offsets[vertex_index] = (
				mesh_instance.to_local(aligned_world) - vertices[vertex_index])
	return {
		"offsets": aligned_offsets,
		"side": dominant_side,
		"maximum_rotation": maximum_rotation,
		"maximum_translation": maximum_translation,
	}


static func _bind_bone_name(
	skin: Skin,
	skeleton: Skeleton3D,
	bind_index: int,
) -> String:
	if bind_index < 0 or bind_index >= skin.get_bind_count():
		return ""
	var bone_index := skin.get_bind_bone(bind_index)
	if bone_index >= 0 and bone_index < skeleton.get_bone_count():
		return skeleton.get_bone_name(bone_index)
	return String(skin.get_bind_name(bind_index))


static func _distal_leg_side(bone_name: String) -> String:
	var lower_name := bone_name.to_lower()
	var is_distal := false
	for token in ["calf", "shin", "lowerleg", "foot", "ankle", "ball", "toe"]:
		if token in lower_name:
			is_distal = true
			break
	if not is_distal:
		return ""
	if lower_name.ends_with("_l") or lower_name.ends_with(".l"):
		return "left"
	if lower_name.ends_with("_r") or lower_name.ends_with(".r"):
		return "right"
	return ""
