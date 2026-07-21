class_name CharacterEditorAutorigger
extends RefCounted

## Builds a reusable Godot-native humanoid scene from a neutral-pose mesh.
## This is intentionally a transparent anatomical heuristic, not a claim of
## production auto-rigging: vertices are weighted against nearby bone segments.

const CORE_BONES: Array[Dictionary] = [
	{"name": "Hips", "parent": "", "point": Vector3(0.0, 0.37, 0.0)},
	{"name": "Spine", "parent": "Hips", "point": Vector3(0.0, 0.46, 0.0)},
	{"name": "Spine1", "parent": "Spine", "point": Vector3(0.0, 0.58, 0.0)},
	{"name": "Spine2", "parent": "Spine1", "point": Vector3(0.0, 0.70, 0.0)},
	{"name": "Neck", "parent": "Spine2", "point": Vector3(0.0, 0.80, 0.0)},
	{"name": "Head", "parent": "Neck", "point": Vector3(0.0, 0.92, 0.0)},
	{"name": "HeadTop", "parent": "Head", "point": Vector3(0.0, 0.985, 0.0)},
]

const CENTER_WEIGHT_BONES: Array[String] = [
	"Hips", "Spine", "Spine1", "Spine2", "Neck", "Head",
]
const SIDE_WEIGHT_BONES: Array[String] = [
	"Shoulder", "Arm", "ForeArm", "Hand", "UpLeg", "Leg", "Foot", "ToeBase",
]
const INFLUENCE_CUTOFF := 0.02
const MAX_VERTEX_INFLUENCES := 4
const MAX_SMOOTHING_INFLUENCES := 8
const WEIGHT_SMOOTHING_PASSES := 2
const WEIGHT_SMOOTHING_FACTOR := 0.25
const DEFAULT_PELVIS_HEIGHT := 0.515
const PELVIS_PROFILE_START := 0.28
const PELVIS_PROFILE_END := 0.68
const PELVIS_PROFILE_STEP := 0.01


static func generate(
		source_path: String, output_path: String, joint_positions: Dictionary = {}) -> Dictionary:
	var source_root_result := _load_source_meshes(source_path)
	if not source_root_result["ok"]:
		return source_root_result
	var source_root: Node3D = source_root_result["source_root"]
	var source_meshes: Array[MeshInstance3D] = source_root_result["source_meshes"]
	var bounds_result := _combined_baked_geometry(source_root, source_meshes)
	if not bounds_result["ok"]:
		source_root.free()
		return bounds_result
	var bounds: AABB = bounds_result["bounds"]
	var geometry_vertices: PackedVector3Array = bounds_result["vertices"]
	if bounds.size.y <= 0.001 or bounds.size.x <= 0.001:
		source_root.free()
		return _failure("Character bounds are too small to infer a humanoid rig")
	if bounds.size.x < bounds.size.y * 0.45:
		source_root.free()
		return _failure("Automatic rigging expects a neutral T/A pose with visible arm span")

	var output_root := Node3D.new()
	output_root.name = StringName(source_path.get_file().get_basename().to_pascal_case() + "Rigged")
	var skeleton := Skeleton3D.new()
	skeleton.name = &"Skeleton3D"
	output_root.add_child(skeleton)
	skeleton.owner = output_root
	var landmarks := _infer_pelvis_landmarks(bounds, geometry_vertices)
	_build_skeleton(skeleton, bounds, joint_positions, geometry_vertices, landmarks)

	var result := _finish_and_save(
			output_root, skeleton, source_root, source_meshes, bounds, output_path,
			_candidate_weights_for_vertex)
	source_root.free()
	if result["ok"]:
		result["landmarks"] = landmarks
	return result


## Weights and saves a rigged scene for a skeleton the caller already built -
## e.g. via manual bone placement in the Rig tab's "Build Custom Rig" mode -
## instead of generating one from the fixed humanoid heuristic generate()
## uses. skeleton is duplicated rather than packed directly, so this never
## disturbs the live skeleton the caller is still showing/editing (that one
## may be mid-scene, e.g. editor.body.skeleton). Considers every bone as a
## weighting candidate for each vertex (see
## _candidate_weights_for_vertex_generic) rather than a named humanoid
## whitelist, since a custom skeleton's bone names carry no fixed meaning.
static func generate_from_skeleton(
		skeleton: Skeleton3D, source_path: String, output_path: String) -> Dictionary:
	if skeleton.get_bone_count() == 0:
		return _failure("No bones have been placed yet")
	var source_root_result := _load_source_meshes(source_path)
	if not source_root_result["ok"]:
		return source_root_result
	var source_root: Node3D = source_root_result["source_root"]
	var source_meshes: Array[MeshInstance3D] = source_root_result["source_meshes"]
	var bounds_result := _combined_baked_geometry(source_root, source_meshes)
	if not bounds_result["ok"]:
		source_root.free()
		return bounds_result
	var bounds: AABB = bounds_result["bounds"]

	var output_root := Node3D.new()
	output_root.name = StringName(source_path.get_file().get_basename().to_pascal_case() + "Rigged")
	var skeleton_copy := _copy_skeleton(skeleton)
	output_root.add_child(skeleton_copy)
	skeleton_copy.owner = output_root

	var result := _finish_and_save(
			output_root, skeleton_copy, source_root, source_meshes, bounds, output_path,
			_candidate_weights_for_vertex_generic)
	source_root.free()
	return result


## Skeleton3D bones are internal engine state (added via add_bone()/
## set_bone_rest()/set_bone_parent(), not regular exported properties), not
## something Node.duplicate() is documented to clone - copying explicitly
## bone-by-bone, the same way _build_skeleton() constructs one, is the only
## reliable way to get an independent copy that doesn't disturb the live
## skeleton the caller is still showing/editing.
static func _copy_skeleton(source: Skeleton3D) -> Skeleton3D:
	var copy := Skeleton3D.new()
	copy.name = &"Skeleton3D"
	for bone_index in source.get_bone_count():
		copy.add_bone(source.get_bone_name(bone_index))
		copy.set_bone_rest(bone_index, source.get_bone_rest(bone_index))
	for bone_index in source.get_bone_count():
		copy.set_bone_parent(bone_index, source.get_bone_parent(bone_index))
	return copy


static func _load_source_meshes(source_path: String) -> Dictionary:
	var source_resource := load(source_path)
	if not source_resource is PackedScene:
		return _failure("Character source is not an imported 3D scene")
	var source_root := (source_resource as PackedScene).instantiate() as Node3D
	if source_root == null:
		return _failure("Character source has no Node3D root")
	var source_meshes: Array[MeshInstance3D] = []
	for found: Node in source_root.find_children("*", "MeshInstance3D", true, false):
		var found_mesh := found as MeshInstance3D
		if found_mesh.mesh != null:
			source_meshes.append(found_mesh)
	if source_meshes.is_empty():
		source_root.free()
		return _failure("Character source contains no mesh surfaces")
	return {"ok": true, "source_root": source_root, "source_meshes": source_meshes}


## Shared tail of generate()/generate_from_skeleton(): weight every source
## mesh against skeleton (via candidate_fn - the only thing that differs
## between the humanoid and custom-skeleton paths), bind them to a shared
## Skin, pack output_root, and save it to output_path. Does not free
## source_root - callers still need it alive up to this call
## (_transform_relative_to walks up to it) and are responsible for freeing
## it themselves afterward.
static func _finish_and_save(
		output_root: Node3D, skeleton: Skeleton3D, source_root: Node3D,
		source_meshes: Array[MeshInstance3D], bounds: AABB, output_path: String,
		candidate_fn: Callable) -> Dictionary:
	var skin := _build_skin(skeleton)
	for source_mesh: MeshInstance3D in source_meshes:
		var baked_transform := _transform_relative_to(source_mesh, source_root)
		var rigged_mesh := MeshInstance3D.new()
		rigged_mesh.name = source_mesh.name
		rigged_mesh.mesh = _build_weighted_mesh(
				source_mesh.mesh, baked_transform, bounds, skeleton, candidate_fn)
		if rigged_mesh.mesh == null:
			output_root.free()
			return _failure("A mesh surface could not be converted to a weighted ArrayMesh")
		output_root.add_child(rigged_mesh)
		rigged_mesh.owner = output_root
		rigged_mesh.skin = skin
		rigged_mesh.skeleton = rigged_mesh.get_path_to(skeleton)
	var animation_player := AnimationPlayer.new()
	animation_player.name = &"AnimationPlayer"
	output_root.add_child(animation_player)
	animation_player.owner = output_root

	var packed := PackedScene.new()
	var pack_error := packed.pack(output_root)
	if pack_error != OK:
		output_root.free()
		return _failure("Could not pack generated rig: %s" % error_string(pack_error))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output_path.get_base_dir()))
	var humanoid_map := _identity_map(skeleton)
	var generated_joint_positions := _joint_positions(skeleton)
	var bone_count := skeleton.get_bone_count()
	var save_error := ResourceSaver.save(packed, output_path, ResourceSaver.FLAG_BUNDLE_RESOURCES)
	output_root.free()
	if save_error != OK:
		return _failure("Could not save generated rig: %s" % error_string(save_error))
	return {
		"ok": true,
		"path": output_path,
		"humanoid_map": humanoid_map,
		"joint_positions": generated_joint_positions,
		"bone_count": bone_count,
	}


static func _combined_baked_geometry(
		source_root: Node3D, source_meshes: Array[MeshInstance3D]) -> Dictionary:
	var combined := AABB()
	var has_bounds := false
	var vertices := PackedVector3Array()
	for mesh_instance: MeshInstance3D in source_meshes:
		var relative := _transform_relative_to(mesh_instance, source_root)
		var transformed: AABB = relative * mesh_instance.get_aabb()
		combined = combined.merge(transformed) if has_bounds else transformed
		has_bounds = true
		for surface_index in mesh_instance.mesh.get_surface_count():
			var arrays: Array = mesh_instance.mesh.surface_get_arrays(surface_index)
			var surface_vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			for vertex: Vector3 in surface_vertices:
				vertices.append(relative * vertex)
	return {"ok": has_bounds, "bounds": combined, "vertices": vertices}


static func _transform_relative_to(node: Node3D, ancestor: Node3D) -> Transform3D:
	var result := node.transform
	var parent := node.get_parent()
	while parent != null and parent != ancestor:
		if parent is Node3D:
			result = (parent as Node3D).transform * result
		parent = parent.get_parent()
	return result


static func _build_skeleton(
		skeleton: Skeleton3D, bounds: AABB, joint_positions: Dictionary,
		geometry_vertices: PackedVector3Array, landmarks: Dictionary) -> void:
	var definitions: Array[Dictionary] = CORE_BONES.duplicate(true)
	var half_width := bounds.size.x * 0.5
	var shoulder_height := _estimate_shoulder_height(bounds, geometry_vertices)
	var pelvis_height: float = landmarks.get("pelvis_height", DEFAULT_PELVIS_HEIGHT)
	var pelvis_y := bounds.position.y + bounds.size.y * pelvis_height
	for side: String in ["Left", "Right"]:
		var sign_value := 1.0 if side == "Left" else -1.0
		definitions.append_array([
			{"name": side + "Shoulder", "parent": "Spine2",
				"point": Vector3(sign_value * 0.28, 0.76, 0.0)},
			{"name": side + "Arm", "parent": side + "Shoulder",
				"point": Vector3(sign_value * 0.36, 0.76, 0.0)},
			{"name": side + "ForeArm", "parent": side + "Arm",
				"point": Vector3(sign_value * 0.63, 0.73, 0.0)},
			{"name": side + "Hand", "parent": side + "ForeArm",
				"point": Vector3(sign_value * 0.88, 0.71, 0.0)},
			{"name": side + "UpLeg", "parent": "Hips",
				"point": Vector3(sign_value * 0.16, 0.37, 0.0)},
			{"name": side + "Leg", "parent": side + "UpLeg",
				"point": Vector3(sign_value * 0.16, 0.20, 0.0)},
			{"name": side + "Foot", "parent": side + "Leg",
				"point": Vector3(sign_value * 0.16, 0.04, 0.0)},
			{"name": side + "ToeBase", "parent": side + "Foot",
				"point": Vector3(sign_value * 0.16, 0.02, 0.36)},
		])
		for finger: String in ["Thumb", "Index", "Middle", "Ring", "Pinky"]:
			var parent_name := side + "Hand"
			for joint_index in range(1, 5):
				var role := "%sHand%s%d" % [side, finger, joint_index]
				definitions.append({
					"name": role,
					"parent": parent_name,
					"point": Vector3(sign_value * (0.90 + joint_index * 0.018), 0.71, 0.0),
				})
				parent_name = role
	var global_points := {}
	for definition: Dictionary in definitions:
		var normalized: Vector3 = definition["point"]
		var global_point := Vector3(
			bounds.get_center().x + normalized.x * half_width,
			bounds.position.y + normalized.y * bounds.size.y,
			bounds.get_center().z + normalized.z * bounds.size.z)
		var bone_name: String = definition["name"]
		if bone_name == "Hips" or bone_name.ends_with("UpLeg"):
			global_point.y = pelvis_y
		elif bone_name == "Spine":
			global_point.y = lerpf(pelvis_y, shoulder_height, 0.25)
		elif bone_name == "Spine1":
			global_point.y = lerpf(pelvis_y, shoulder_height, 0.58)
		elif bone_name == "Spine2":
			global_point.y = shoulder_height
		if _is_finger_bone(bone_name):
			var side := "Left" if bone_name.begins_with("Left") else "Right"
			global_point = _fit_finger_joint(
					bone_name, global_points[side + "Hand"], bounds, geometry_vertices)
		elif bone_name.ends_with("ToeBase"):
			var side := "Left" if bone_name.begins_with("Left") else "Right"
			global_point = _fit_toe_joint(
					global_points[side + "Foot"], side, bounds, geometry_vertices)
		else:
			global_point = _fit_joint_to_geometry(
					bone_name, global_point, bounds, geometry_vertices)
		if joint_positions.has(bone_name):
			var saved: Variant = joint_positions[bone_name]
			global_point = saved if saved is Vector3 else Vector3(saved[0], saved[1], saved[2])
		var bone_index := skeleton.get_bone_count()
		skeleton.add_bone(bone_name)
		var parent_name: String = definition["parent"]
		if not parent_name.is_empty():
			var parent_index := skeleton.find_bone(parent_name)
			skeleton.set_bone_parent(bone_index, parent_index)
			var parent_point: Vector3 = global_points[parent_name]
			skeleton.set_bone_rest(bone_index, Transform3D(Basis.IDENTITY, global_point - parent_point))
		else:
			skeleton.set_bone_rest(bone_index, Transform3D(Basis.IDENTITY, global_point))
		global_points[bone_name] = global_point


static func _infer_pelvis_landmarks(
		bounds: AABB, vertices: PackedVector3Array) -> Dictionary:
	var profiles: Array[Dictionary] = []
	var normalized_y := PELVIS_PROFILE_START
	while normalized_y <= PELVIS_PROFILE_END + 0.0001:
		var profile := _horizontal_slice_profile(normalized_y, bounds, vertices)
		if profile.get("valid", false):
			profiles.append(profile)
		normalized_y += PELVIS_PROFILE_STEP
	var crotch_height := -1.0
	for profile: Dictionary in profiles:
		var sample_height: float = profile["height"]
		if sample_height > 0.5:
			break
		if float(profile["center_gap"]) <= 0.005:
			crotch_height = sample_height
			break
	var waist_height := -1.0
	var narrowest_width := INF
	var waist_search_start := maxf(crotch_height + 0.08, 0.5)
	for profile: Dictionary in profiles:
		var sample_height: float = profile["height"]
		if sample_height < waist_search_start:
			continue
		var width: float = profile["half_width"]
		if width < narrowest_width:
			narrowest_width = width
			waist_height = sample_height
	var detection_valid := (
			crotch_height >= 0.38 and crotch_height <= 0.5
			and waist_height >= 0.54 and waist_height <= 0.68
			and waist_height - crotch_height >= 0.08
			and waist_height - crotch_height <= 0.25)
	var detected_height := DEFAULT_PELVIS_HEIGHT
	if detection_valid:
		detected_height = clampf((crotch_height + waist_height) * 0.5, 0.48, 0.55)
	# The silhouette transition is sensitive to clothing. Blending it with a
	# conservative humanoid prior keeps the result stable while still allowing
	# body geometry to move the pelvis away from a fixed bounds percentage.
	var pelvis_height := lerpf(DEFAULT_PELVIS_HEIGHT, detected_height, 0.5)
	return {
		"pelvis_height": pelvis_height,
		"crotch_height": crotch_height,
		"waist_height": waist_height,
		"detection_valid": detection_valid,
		"confidence": "geometry" if detection_valid else "fallback",
	}


static func _horizontal_slice_profile(
		normalized_y: float, bounds: AABB,
		vertices: PackedVector3Array) -> Dictionary:
	var coordinate := bounds.position.y + bounds.size.y * normalized_y
	var radius := bounds.size.y * 0.015
	var distances: Array[float] = []
	var center_x := bounds.get_center().x
	for vertex: Vector3 in vertices:
		if absf(vertex.y - coordinate) <= radius:
			distances.append(absf(vertex.x - center_x))
	if distances.size() < 16 or bounds.size.x <= 0.0001:
		return {"valid": false, "height": normalized_y}
	distances.sort()
	return {
		"valid": true,
		"height": normalized_y,
		"center_gap": distances[int(distances.size() * 0.05)] / bounds.size.x,
		"half_width": distances[int(distances.size() * 0.9)] / bounds.size.x,
	}


static func _estimate_shoulder_height(
		bounds: AABB, vertices: PackedVector3Array) -> float:
	var half_width := bounds.size.x * 0.5
	var initial_y := bounds.position.y + bounds.size.y * 0.76
	var left := _fit_arm_joint(Vector3(
			bounds.get_center().x + half_width * 0.28,
			initial_y, bounds.get_center().z), bounds, vertices)
	var right := _fit_arm_joint(Vector3(
			bounds.get_center().x - half_width * 0.28,
			initial_y, bounds.get_center().z), bounds, vertices)
	return (left.y + right.y) * 0.5


static func _fit_joint_to_geometry(
		bone_name: String, initial: Vector3, bounds: AABB,
		vertices: PackedVector3Array) -> Vector3:
	if vertices.is_empty():
		return initial
	if bone_name.begins_with("Left") or bone_name.begins_with("Right"):
		if _is_arm_bone(bone_name):
			return _fit_arm_joint(initial, bounds, vertices)
		return _fit_leg_joint(initial, bounds, vertices)
	return _fit_center_joint(initial, bounds, vertices)


static func _is_arm_bone(bone_name: String) -> bool:
	return (
			bone_name.contains("Shoulder")
			or bone_name.contains("Arm")
			or bone_name.contains("Hand")
	)


static func _is_finger_bone(bone_name: String) -> bool:
	return bone_name.contains("Hand") and not bone_name.ends_with("Hand")


static func _fit_finger_joint(
		bone_name: String, hand_root: Vector3, bounds: AABB,
		vertices: PackedVector3Array) -> Vector3:
	var is_left := bone_name.begins_with("Left")
	var side_sign := 1.0 if is_left else -1.0
	var hand_tip_x := bounds.get_center().x + bounds.size.x * 0.5 * side_sign
	var hand_length := absf(hand_tip_x - hand_root.x)
	var section_min := Vector3(INF, INF, INF)
	var section_max := Vector3(-INF, -INF, -INF)
	var count := 0
	for vertex: Vector3 in vertices:
		var along := (vertex.x - hand_root.x) * side_sign
		if along < -hand_length * 0.08 or along > hand_length * 1.1:
			continue
		if absf(vertex.y - hand_root.y) > bounds.size.y * 0.075:
			continue
		if absf(vertex.z - hand_root.z) > bounds.size.z * 0.42:
			continue
		section_min = section_min.min(vertex)
		section_max = section_max.max(vertex)
		count += 1
	if count < 12:
		return hand_root.lerp(Vector3(hand_tip_x, hand_root.y, hand_root.z), 0.75)
	var spread_axis := 1 if section_max.y - section_min.y > section_max.z - section_min.z else 2
	var spread_center := (section_min[spread_axis] + section_max[spread_axis]) * 0.5
	var spread_radius := (section_max[spread_axis] - section_min[spread_axis]) * 0.42
	var tip_center := Vector3(hand_tip_x,
			(section_min.y + section_max.y) * 0.5,
			(section_min.z + section_max.z) * 0.5)
	var tip_sum := Vector3.ZERO
	var tip_count := 0
	for vertex: Vector3 in vertices:
		var along := (vertex.x - hand_root.x) * side_sign
		if along < hand_length * 0.72 or along > hand_length * 1.1:
			continue
		if absf(vertex.y - hand_root.y) > bounds.size.y * 0.075:
			continue
		if absf(vertex.z - hand_root.z) > bounds.size.z * 0.42:
			continue
		tip_sum += vertex
		tip_count += 1
	if tip_count >= 4:
		var detected_tip := tip_sum / float(tip_count)
		tip_center.y = detected_tip.y
		tip_center.z = detected_tip.z
	var finger := _finger_name(bone_name)
	var lane: float = {
		"Thumb": -0.82,
		"Index": 0.68,
		"Middle": 0.23,
		"Ring": -0.2,
		"Pinky": -0.64,
	}.get(finger, 0.0)
	var length_scale: float = {
		"Thumb": 0.56,
		"Index": 0.9,
		"Middle": 1.0,
		"Ring": 0.92,
		"Pinky": 0.76,
	}.get(finger, 0.85)
	var joint_index := int(bone_name.right(1))
	var along_amount := 0.38 + 0.58 * length_scale * (float(joint_index) / 4.0)
	var point := hand_root.lerp(tip_center, along_amount)
	point[spread_axis] = spread_center + lane * spread_radius
	if finger == "Thumb":
		var thickness_axis := 2 if spread_axis == 1 else 1
		point[thickness_axis] = lerpf(
				section_min[thickness_axis], section_max[thickness_axis], 0.25)
	return point


static func _finger_name(bone_name: String) -> String:
	for finger: String in ["Thumb", "Index", "Middle", "Ring", "Pinky"]:
		if finger in bone_name:
			return finger
	return ""


static func _fit_toe_joint(
		foot_root: Vector3, side: String, bounds: AABB,
		vertices: PackedVector3Array) -> Vector3:
	var side_sign := 1.0 if side == "Left" else -1.0
	var section_min := Vector3(INF, INF, INF)
	var section_max := Vector3(-INF, -INF, -INF)
	var count := 0
	for vertex: Vector3 in vertices:
		if vertex.y > bounds.position.y + bounds.size.y * 0.13:
			continue
		if (vertex.x - bounds.get_center().x) * side_sign < 0.0:
			continue
		if absf(vertex.x - foot_root.x) > bounds.size.x * 0.12:
			continue
		section_min = section_min.min(vertex)
		section_max = section_max.max(vertex)
		count += 1
	if count < 8:
		return Vector3(foot_root.x, bounds.position.y + bounds.size.y * 0.02,
				bounds.get_center().z + bounds.size.z * 0.36)
	var front_z := section_max.z
	if absf(section_min.z - foot_root.z) > absf(section_max.z - foot_root.z):
		front_z = section_min.z
	var toe_z := lerpf(foot_root.z, front_z, 0.82)
	return Vector3((section_min.x + section_max.x) * 0.5,
			lerpf(section_min.y, section_max.y, 0.35), toe_z)


static func _fit_arm_joint(
		initial: Vector3, bounds: AABB, vertices: PackedVector3Array) -> Vector3:
	var x_radius := maxf(bounds.size.x * 0.025, bounds.size.y * 0.008)
	var minimum_y := bounds.position.y + bounds.size.y * 0.55
	var limits := _cross_section_limits(vertices, 0, initial.x, x_radius, minimum_y)
	if not limits["valid"]:
		return initial
	var section_min: Vector3 = limits["min"]
	var section_max: Vector3 = limits["max"]
	return Vector3(initial.x, (section_min.y + section_max.y) * 0.5,
			(section_min.z + section_max.z) * 0.5)


static func _fit_leg_joint(
		initial: Vector3, bounds: AABB, vertices: PackedVector3Array) -> Vector3:
	var y_radius := maxf(bounds.size.y * 0.018, bounds.size.x * 0.008)
	var side_sign := 1.0 if initial.x >= bounds.get_center().x else -1.0
	var center_x := bounds.get_center().x
	var side_limit := bounds.size.x * 0.28
	var limits := _cross_section_limits(
			vertices, 1, initial.y, y_radius, -INF, side_sign, center_x, side_limit)
	if not limits["valid"]:
		return initial
	var section_min: Vector3 = limits["min"]
	var section_max: Vector3 = limits["max"]
	return Vector3((section_min.x + section_max.x) * 0.5, initial.y,
			(section_min.z + section_max.z) * 0.5)


static func _fit_center_joint(
		initial: Vector3, bounds: AABB, vertices: PackedVector3Array) -> Vector3:
	var y_radius := maxf(bounds.size.y * 0.018, bounds.size.x * 0.008)
	var center_x := bounds.get_center().x
	var center_limit := bounds.size.x * 0.14
	var limits := _cross_section_limits(
			vertices, 1, initial.y, y_radius, -INF, 0.0, center_x, center_limit)
	if not limits["valid"]:
		return initial
	var section_min: Vector3 = limits["min"]
	var section_max: Vector3 = limits["max"]
	return Vector3((section_min.x + section_max.x) * 0.5, initial.y,
			(section_min.z + section_max.z) * 0.5)


static func _cross_section_limits(
		vertices: PackedVector3Array, axis: int, coordinate: float, radius: float,
		minimum_y: float = -INF, side_sign: float = 0.0, center_x: float = 0.0,
		x_limit: float = INF) -> Dictionary:
	var section_min := Vector3(INF, INF, INF)
	var section_max := Vector3(-INF, -INF, -INF)
	var count := 0
	for vertex: Vector3 in vertices:
		if absf(vertex[axis] - coordinate) > radius or vertex.y < minimum_y:
			continue
		if side_sign != 0.0 and (vertex.x - center_x) * side_sign < 0.0:
			continue
		if absf(vertex.x - center_x) > x_limit:
			continue
		section_min = section_min.min(vertex)
		section_max = section_max.max(vertex)
		count += 1
	return {"valid": count >= 4, "min": section_min, "max": section_max}


static func _build_skin(skeleton: Skeleton3D) -> Skin:
	var skin := Skin.new()
	for bone_index in skeleton.get_bone_count():
		skin.add_named_bind(
				skeleton.get_bone_name(bone_index),
				skeleton.get_bone_global_rest(bone_index).affine_inverse())
	return skin


static func _build_weighted_mesh(
		source: Mesh, baked_transform: Transform3D, bounds: AABB,
		skeleton: Skeleton3D, candidate_fn: Callable) -> ArrayMesh:
	var result := ArrayMesh.new()
	var segments := _build_influence_segments(skeleton, bounds)
	for surface_index in source.get_surface_count():
		var arrays: Array = source.surface_get_arrays(surface_index)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		if vertices.is_empty():
			continue
		var baked_vertices := PackedVector3Array()
		baked_vertices.resize(vertices.size())
		var bones := PackedInt32Array()
		var weights := PackedFloat32Array()
		bones.resize(vertices.size() * 4)
		weights.resize(vertices.size() * 4)
		var candidate_weights: Array[Dictionary] = []
		for vertex_index in vertices.size():
			var vertex := baked_transform * vertices[vertex_index]
			baked_vertices[vertex_index] = vertex
			candidate_weights.append(candidate_fn.call(vertex, bounds, segments))
		var adjacency := _build_vertex_adjacency(
				vertices.size(), arrays[Mesh.ARRAY_INDEX],
				source.surface_get_primitive_type(surface_index))
		candidate_weights = _smooth_candidate_weights(candidate_weights, adjacency)
		for vertex_index in vertices.size():
			var influences := _finalize_weight_map(candidate_weights[vertex_index])
			for influence_index in influences.size():
				var influence: Array = influences[influence_index]
				bones[vertex_index * 4 + influence_index] = influence[0]
				weights[vertex_index * 4 + influence_index] = influence[1]
		arrays[Mesh.ARRAY_VERTEX] = baked_vertices
		arrays[Mesh.ARRAY_BONES] = bones
		arrays[Mesh.ARRAY_WEIGHTS] = weights
		if arrays[Mesh.ARRAY_NORMAL] is PackedVector3Array:
			var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
			for normal_index in normals.size():
				normals[normal_index] = (baked_transform.basis * normals[normal_index]).normalized()
			arrays[Mesh.ARRAY_NORMAL] = normals
		result.add_surface_from_arrays(source.surface_get_primitive_type(surface_index), arrays)
		result.surface_set_material(
				result.get_surface_count() - 1, source.surface_get_material(surface_index))
		result.surface_set_name(result.get_surface_count() - 1, source.surface_get_name(surface_index))
	return result if result.get_surface_count() > 0 else null


static func _build_influence_segments(skeleton: Skeleton3D, bounds: AABB) -> Dictionary:
	var segments := {}
	for bone_index in skeleton.get_bone_count():
		var bone_name := String(skeleton.get_bone_name(bone_index))
		var start := skeleton.get_bone_global_rest(bone_index).origin
		var end := _segment_end(skeleton, bone_index, start, bounds)
		segments[bone_name] = {
			"bone_index": bone_index,
			"start": start,
			"end": end,
		}
	return segments


static func _segment_end(
		skeleton: Skeleton3D, bone_index: int, start: Vector3, bounds: AABB) -> Vector3:
	for candidate_index in skeleton.get_bone_count():
		if skeleton.get_bone_parent(candidate_index) == bone_index:
			return skeleton.get_bone_global_rest(candidate_index).origin
	var bone_name := String(skeleton.get_bone_name(bone_index))
	if bone_name == "Head":
		return Vector3(start.x, bounds.end.y, start.z)
	if bone_name.ends_with("Hand"):
		var side_sign := 1.0 if bone_name.begins_with("Left") else -1.0
		return Vector3(bounds.get_center().x + bounds.size.x * 0.5 * side_sign, start.y, start.z)
	if _is_finger_bone(bone_name):
		var parent_index := skeleton.get_bone_parent(bone_index)
		if parent_index >= 0:
			var parent_start := skeleton.get_bone_global_rest(parent_index).origin
			return start + (start - parent_start) * 0.65
	return start


static func _candidate_weights_for_vertex(
		vertex: Vector3, bounds: AABB, segments: Dictionary) -> Dictionary:
	var candidate_names: Array[String] = CENTER_WEIGHT_BONES.duplicate()
	var side := "Left" if vertex.x >= bounds.get_center().x else "Right"
	for suffix: String in SIDE_WEIGHT_BONES:
		candidate_names.append(side + suffix)
	for bone_name: String in segments:
		if bone_name.begins_with(side + "Hand") and bone_name not in candidate_names:
			candidate_names.append(bone_name)
	var scored: Array[Array] = []
	var distance_floor := maxf(bounds.size.y * 0.002, 0.0001)
	for bone_name: String in candidate_names:
		if not segments.has(bone_name):
			continue
		var segment: Dictionary = segments[bone_name]
		var distance := _distance_to_segment(vertex, segment["start"], segment["end"])
		var safe_distance := maxf(distance, distance_floor)
		scored.append([segment["bone_index"], 1.0 / (safe_distance * safe_distance)])
	scored.sort_custom(func(a: Array, b: Array) -> bool:
		return float(a[1]) > float(b[1]))
	var retained := _retain_influences(scored, MAX_SMOOTHING_INFLUENCES)
	var result := {}
	for influence: Array in retained:
		result[int(influence[0])] = float(influence[1])
	return result


## Generic sibling of _candidate_weights_for_vertex for a custom (non-
## humanoid) skeleton, used by generate_from_skeleton(): a custom skeleton's
## bone names carry no fixed meaning, so there's no CENTER_WEIGHT_BONES/
## SIDE_WEIGHT_BONES whitelist to draw candidates from - every bone in
## segments is a candidate instead. Same inverse-square-distance scoring and
## _retain_influences pruning as the humanoid version.
static func _candidate_weights_for_vertex_generic(
		vertex: Vector3, bounds: AABB, segments: Dictionary) -> Dictionary:
	var scored: Array[Array] = []
	var distance_floor := maxf(bounds.size.y * 0.002, 0.0001)
	for bone_name: String in segments:
		var segment: Dictionary = segments[bone_name]
		var distance := _distance_to_segment(vertex, segment["start"], segment["end"])
		var safe_distance := maxf(distance, distance_floor)
		scored.append([segment["bone_index"], 1.0 / (safe_distance * safe_distance)])
	scored.sort_custom(func(a: Array, b: Array) -> bool:
		return float(a[1]) > float(b[1]))
	var retained := _retain_influences(scored, MAX_SMOOTHING_INFLUENCES)
	var result := {}
	for influence: Array in retained:
		result[int(influence[0])] = float(influence[1])
	return result


static func _build_vertex_adjacency(
		vertex_count: int, index_data: Variant, primitive: int) -> Array[PackedInt32Array]:
	var empty_result: Array[PackedInt32Array] = []
	empty_result.resize(vertex_count)
	for vertex_index in vertex_count:
		empty_result[vertex_index] = PackedInt32Array()
	if primitive != Mesh.PRIMITIVE_TRIANGLES:
		return empty_result
	var neighbors: Array[Dictionary] = []
	neighbors.resize(vertex_count)
	for vertex_index in vertex_count:
		neighbors[vertex_index] = {}
	var indices := PackedInt32Array()
	if index_data is PackedInt32Array:
		indices = index_data
	if indices.is_empty():
		indices.resize(vertex_count)
		for vertex_index in vertex_count:
			indices[vertex_index] = vertex_index
	for triangle_start in range(0, indices.size() - 2, 3):
		var first := indices[triangle_start]
		var second := indices[triangle_start + 1]
		var third := indices[triangle_start + 2]
		_add_adjacency_edge(neighbors, first, second)
		_add_adjacency_edge(neighbors, second, third)
		_add_adjacency_edge(neighbors, third, first)
	var result: Array[PackedInt32Array] = []
	result.resize(vertex_count)
	for vertex_index in vertex_count:
		result[vertex_index] = PackedInt32Array(neighbors[vertex_index].keys())
	return result


static func _add_adjacency_edge(neighbors: Array[Dictionary], first: int, second: int) -> void:
	if first < 0 or second < 0 or first >= neighbors.size() or second >= neighbors.size():
		return
	neighbors[first][second] = true
	neighbors[second][first] = true


static func _smooth_candidate_weights(
		weights: Array[Dictionary], adjacency: Array[PackedInt32Array]) -> Array[Dictionary]:
	var current := weights
	for _pass_index in WEIGHT_SMOOTHING_PASSES:
		var smoothed: Array[Dictionary] = []
		smoothed.resize(current.size())
		for vertex_index in current.size():
			var neighbors := adjacency[vertex_index]
			if neighbors.is_empty():
				smoothed[vertex_index] = current[vertex_index].duplicate()
				continue
			var blended := {}
			_accumulate_weight_map(blended, current[vertex_index], 1.0 - WEIGHT_SMOOTHING_FACTOR)
			var neighbor_factor := WEIGHT_SMOOTHING_FACTOR / float(neighbors.size())
			for neighbor_index: int in neighbors:
				_accumulate_weight_map(blended, current[neighbor_index], neighbor_factor)
			smoothed[vertex_index] = _prune_weight_map(blended, MAX_SMOOTHING_INFLUENCES)
		current = smoothed
	return current


static func _accumulate_weight_map(target: Dictionary, source: Dictionary, factor: float) -> void:
	for bone_index: int in source:
		target[bone_index] = float(target.get(bone_index, 0.0)) + float(source[bone_index]) * factor


static func _prune_weight_map(weights: Dictionary, maximum: int) -> Dictionary:
	var scored := _weight_map_to_scored(weights)
	var retained := _retain_influences(scored, maximum)
	var result := {}
	for influence: Array in retained:
		result[int(influence[0])] = float(influence[1])
	return result


static func _weight_map_to_scored(weights: Dictionary) -> Array[Array]:
	var scored: Array[Array] = []
	for bone_index: int in weights:
		scored.append([bone_index, float(weights[bone_index])])
	scored.sort_custom(func(a: Array, b: Array) -> bool:
		return float(a[1]) > float(b[1]))
	return scored


static func _finalize_weight_map(weights: Dictionary) -> Array[Array]:
	return _retain_influences(_weight_map_to_scored(weights), MAX_VERTEX_INFLUENCES)


static func _distance_to_segment(point: Vector3, start: Vector3, end: Vector3) -> float:
	var offset := end - start
	var length_squared := offset.length_squared()
	if length_squared <= 0.0000001:
		return point.distance_to(start)
	var amount := clampf((point - start).dot(offset) / length_squared, 0.0, 1.0)
	return point.distance_to(start + offset * amount)


static func _retain_influences(scored: Array[Array], maximum: int) -> Array[Array]:
	if scored.is_empty():
		return []
	var retained: Array[Array] = []
	var strongest := float(scored[0][1])
	for influence: Array in scored:
		if retained.size() >= maximum:
			break
		if not retained.is_empty() and float(influence[1]) < strongest * INFLUENCE_CUTOFF:
			break
		retained.append(influence.duplicate())
	var total := 0.0
	for influence: Array in retained:
		total += float(influence[1])
	if total <= 0.000001:
		return [[scored[0][0], 1.0]]
	for influence: Array in retained:
		influence[1] = float(influence[1]) / total
	return retained


static func _identity_map(skeleton: Skeleton3D) -> Dictionary:
	var mapping := {}
	for bone_index in skeleton.get_bone_count():
		var bone_name := String(skeleton.get_bone_name(bone_index))
		mapping[bone_name] = bone_name
	return mapping


static func _joint_positions(skeleton: Skeleton3D) -> Dictionary:
	var positions := {}
	for bone_index in skeleton.get_bone_count():
		var position := skeleton.get_bone_global_rest(bone_index).origin
		positions[String(skeleton.get_bone_name(bone_index))] = [
			position.x, position.y, position.z]
	return positions


static func _failure(message: String) -> Dictionary:
	return {"ok": false, "error": message}
