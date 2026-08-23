class_name FootIkRegressionAudit
extends RefCounted
## Broad IK-off/IK-on audit used by the locomotion regression.
##
## Captures every skeleton bone on every sampled frame and CPU-skins a
## deterministic set of mesh triangles. Bone transforms diagnose where a
## difference begins; triangle edge strain catches visible deformation that
## bone-origin/rotation checks alone cannot see. JSONL is written between
## cases, never per physics frame, so diagnostics do not perturb playback.

const TRACE_PATH := "user://foot_ik_regression_matrix.jsonl"
const SUMMARY_PATH := "user://foot_ik_regression_summary.jsonl"
const TRIANGLES_PER_SURFACE := 96
const EDGE_RATIO_LIMIT := 1.25
const EDGE_LENGTH_MIN := 0.01
const EDGE_DELTA_LIMIT := 0.1
const ADDED_VERTEX_MOTION_LIMIT := 0.1
const BONE_SCALE_ERROR_LIMIT := 0.001
const ADDED_BONE_ROTATION_LIMIT := 8.0
const ADDED_BONE_POSITION_LIMIT := 0.08

var _players: Dictionary
var _modifiers: Dictionary
var _rendered_poses: Dictionary
var _bones: Array[StringName] = []
var _bone_indices: Dictionary = {}
var _mesh_samples: Array[Dictionary] = []
var _frames: Array[String] = []
var _previous_vertices: Dictionary = {}
var _previous_bones: Dictionary = {}
var _case_name := ""
var _maximum_edge_ratio := 1.0
var _maximum_edge_delta := 0.0
var _maximum_added_vertex_motion := 0.0
var _maximum_bone_scale_error := 0.0
var _maximum_added_bone_rotation := 0.0
var _maximum_added_bone_position := 0.0
var _worst_mesh := ""
var _worst_vertex := -1
var _worst_bone := &""
var _worst_frame := -1
var _worst_edge_frame := -1
var _worst_motion_frame := -1


func _init(players: Dictionary, modifiers: Dictionary, rendered_poses: Dictionary) -> void:
	_players = players
	_modifiers = modifiers
	_rendered_poses = rendered_poses
	_discover_bones()
	_discover_mesh_samples()
	var file := FileAccess.open(TRACE_PATH, FileAccess.WRITE)
	if file != null:
		file.close()
	file = FileAccess.open(SUMMARY_PATH, FileAccess.WRITE)
	if file != null:
		file.close()


func start_case(case_name: String) -> void:
	_case_name = case_name
	_frames.clear()
	_previous_vertices.clear()
	_previous_bones.clear()
	_maximum_edge_ratio = 1.0
	_maximum_edge_delta = 0.0
	_maximum_added_vertex_motion = 0.0
	_maximum_bone_scale_error = 0.0
	_maximum_added_bone_rotation = 0.0
	_maximum_added_bone_position = 0.0
	_worst_mesh = ""
	_worst_vertex = -1
	_worst_bone = &""
	_worst_frame = -1
	_worst_edge_frame = -1
	_worst_motion_frame = -1


func sample(frame: int, animation_time: float) -> void:
	var transforms := {"authored": {}, "ik": {}}
	for key: StringName in [&"authored", &"ik"]:
		var player := _players[key] as Player
		var modifier := _modifiers[key] as PlayerFootIKModifier
		for bone: StringName in _bones:
			var index: int = (_bone_indices[key] as Dictionary)[bone]
			var pose := _final_pose(player, modifier, index, key)
			var scale_error := pose.basis.get_scale().distance_to(Vector3.ONE)
			if scale_error > _maximum_bone_scale_error:
				_maximum_bone_scale_error = scale_error
				_worst_bone = bone
			(transforms[String(key)] as Dictionary)[String(bone)] = _transform_data(pose)
	_compare_bone_motion(transforms, frame)
	var skin := _sample_skin(frame)
	var modifier := _modifiers[&"ik"] as PlayerFootIKModifier
	var gait := {}
	for side: StringName in [&"left", &"right"]:
		gait[String(side)] = {
			"weight": modifier._smoothed_ground_weight.get(side, 0.0),
			"raw_weight": modifier.debug_raw_weight.get(side, 0.0),
			"velocity": modifier.debug_vertical_velocity.get(side, 0.0),
			"stance": modifier._gait_tracker.is_locomotion_stance_active(side),
			"locked": modifier._gait_tracker.is_locomotion_target_locked(side),
			"contact": modifier.debug_contact_distance.get(side, -1.0),
		}
	(
		_frames
		. append(
			(
				JSON
				. stringify(
					{
						"case": _case_name,
						"frame": frame,
						"animation_time": animation_time,
						"bones": transforms,
						"skin": skin,
						"gait": gait,
					}
				)
			)
		)
	)


func finish_case() -> Dictionary:
	var file := FileAccess.open(TRACE_PATH, FileAccess.READ_WRITE)
	if file != null:
		file.seek_end()
		for line: String in _frames:
			file.store_line(line)
		file.close()
	var rotation_limit := (26.0
			if ("walk" in _case_name or "sprint" in _case_name)
			else ADDED_BONE_ROTATION_LIMIT)
	var position_limit := (0.20
			if ("walk" in _case_name or "sprint" in _case_name)
			else ADDED_BONE_POSITION_LIMIT)
	var vertex_motion_limit := (0.20
			if ("walk" in _case_name or "sprint" in _case_name)
			else ADDED_VERTEX_MOTION_LIMIT)
	var failed := (
		_maximum_edge_ratio > EDGE_RATIO_LIMIT and _maximum_edge_delta > EDGE_DELTA_LIMIT
		or _maximum_added_vertex_motion > vertex_motion_limit
		or _maximum_bone_scale_error > BONE_SCALE_ERROR_LIMIT
		or _maximum_added_bone_rotation > rotation_limit
		or _maximum_added_bone_position > position_limit
	)
	var summary := {
		"failed": failed,
		"edge_ratio": _maximum_edge_ratio,
		"edge_ratio_limit": EDGE_RATIO_LIMIT,
		"edge_delta": _maximum_edge_delta,
		"edge_delta_limit": EDGE_DELTA_LIMIT,
		"added_vertex_motion": _maximum_added_vertex_motion,
		"added_vertex_motion_limit": ADDED_VERTEX_MOTION_LIMIT,
		"bone_scale_error": _maximum_bone_scale_error,
		"bone_scale_error_limit": BONE_SCALE_ERROR_LIMIT,
		"added_bone_rotation": _maximum_added_bone_rotation,
		"added_bone_rotation_limit": ADDED_BONE_ROTATION_LIMIT,
		"added_bone_position": _maximum_added_bone_position,
		"added_bone_position_limit": ADDED_BONE_POSITION_LIMIT,
		"worst_mesh": _worst_mesh,
		"worst_vertex": _worst_vertex,
		"worst_bone": _worst_bone,
		"worst_frame": _worst_frame,
		"trace": TRACE_PATH,
		"worst_edge_frame": _worst_edge_frame,
		"worst_motion_frame": _worst_motion_frame,
	}
	file = FileAccess.open(SUMMARY_PATH, FileAccess.READ_WRITE)
	if file != null:
		file.seek_end()
		file.store_line(JSON.stringify({"case": _case_name, "metrics": summary}))
		file.close()
	return summary


func _compare_bone_motion(transforms: Dictionary, frame: int) -> void:
	for bone: StringName in _bones:
		var authored := (transforms["authored"] as Dictionary)[String(bone)] as Dictionary
		var corrected := (transforms["ik"] as Dictionary)[String(bone)] as Dictionary
		var auth_key := "authored:%s" % bone
		var ik_key := "ik:%s" % bone
		if _previous_bones.has(auth_key) and _previous_bones.has(ik_key):
			var prev_auth := _previous_bones[auth_key] as Dictionary
			var prev_ik := _previous_bones[ik_key] as Dictionary
			var auth_rotation := (prev_auth["rotation"] as Quaternion).angle_to(
				authored["rotation"] as Quaternion
			)
			var ik_rotation := (prev_ik["rotation"] as Quaternion).angle_to(
				corrected["rotation"] as Quaternion
			)
			var added_rotation := rad_to_deg(maxf(0.0, ik_rotation - auth_rotation))
			var auth_position := (prev_auth["position"] as Vector3).distance_to(
				authored["position"] as Vector3
			)
			var ik_position := (prev_ik["position"] as Vector3).distance_to(
				corrected["position"] as Vector3
			)
			var added_position := maxf(0.0, ik_position - auth_position)
			if added_rotation > _maximum_added_bone_rotation:
				_maximum_added_bone_rotation = added_rotation
				_worst_bone = bone
				_worst_frame = frame
			if added_position > _maximum_added_bone_position:
				_maximum_added_bone_position = added_position
				_worst_bone = bone
				_worst_frame = frame
		_previous_bones[auth_key] = authored
		_previous_bones[ik_key] = corrected


func _discover_bones() -> void:
	var authored := _players[&"authored"] as Player
	for index in authored.skeleton.get_bone_count():
		_bones.append(authored.skeleton.get_bone_name(index))
	for key: StringName in [&"authored", &"ik"]:
		var player := _players[key] as Player
		var indices := {}
		for bone: StringName in _bones:
			indices[bone] = player.skeleton.find_bone(bone)
		_bone_indices[key] = indices


func _discover_mesh_samples() -> void:
	var player := _players[&"authored"] as Player
	var meshes := player.body.character.find_children("*", "MeshInstance3D", true, false)
	for mesh_node: Node in meshes:
		var mesh_part := mesh_node as MeshInstance3D
		if mesh_part.mesh == null or mesh_part.get_skin_reference() == null:
			continue
		for surface in mesh_part.mesh.get_surface_count():
			var arrays := mesh_part.mesh.surface_get_arrays(surface)
			var vertices := arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array
			var bones := _int_array(arrays[Mesh.ARRAY_BONES])
			var weights := _float_array(arrays[Mesh.ARRAY_WEIGHTS])
			if vertices.is_empty() or bones.is_empty() or weights.is_empty():
				continue
			var triangle_vertices := _sample_triangle_vertices(
				vertices.size(), _int_array(arrays[Mesh.ARRAY_INDEX])
			)
			if triangle_vertices.is_empty():
				continue
			(
				_mesh_samples
				. append(
					{
						"name": "%s:%d" % [mesh_part.name, surface],
						"mesh": mesh_part.mesh,
						"vertices": vertices,
						"bones": bones,
						"weights": weights,
						"triangles": triangle_vertices,
					}
				)
			)


func _sample_triangle_vertices(vertex_count: int, indices: PackedInt32Array) -> PackedInt32Array:
	var source_count := indices.size() if not indices.is_empty() else vertex_count
	var triangle_count := source_count / 3
	var selected := PackedInt32Array()
	if triangle_count == 0:
		return selected
	var stride := maxi(1, triangle_count / TRIANGLES_PER_SURFACE)
	for triangle in range(0, triangle_count, stride):
		if selected.size() >= TRIANGLES_PER_SURFACE * 3:
			break
		for corner in 3:
			var source_index := triangle * 3 + corner
			selected.append(indices[source_index] if not indices.is_empty() else source_index)
	return selected


func _sample_skin(frame: int) -> Dictionary:
	var result := {}
	for sample: Dictionary in _mesh_samples:
		var positions := {"authored": PackedVector3Array(), "ik": PackedVector3Array()}
		for key: StringName in [&"authored", &"ik"]:
			var player := _players[key] as Player
			var mesh_part := _find_mesh(player, sample["mesh"] as Mesh)
			if mesh_part == null:
				continue
			positions[String(key)] = _skin_positions(player, mesh_part, sample, key)
		var authored := positions["authored"] as PackedVector3Array
		var corrected := positions["ik"] as PackedVector3Array
		if authored.is_empty() or corrected.is_empty():
			continue
		var mesh_result := _compare_skin_sample(String(sample["name"]), authored, corrected, frame)
		result[String(sample["name"])] = mesh_result
	return result


func _find_mesh(player: Player, mesh: Mesh) -> MeshInstance3D:
	for node: Node in player.body.character.find_children("*", "MeshInstance3D", true, false):
		var candidate := node as MeshInstance3D
		if candidate.mesh == mesh and candidate.get_skin_reference() != null:
			return candidate
	return null


func _skin_positions(
	player: Player, mesh_part: MeshInstance3D, sample: Dictionary, key: StringName
) -> PackedVector3Array:
	var bind_transforms := _bind_transforms(player, mesh_part, key)
	var vertices := sample["vertices"] as PackedVector3Array
	var bones := sample["bones"] as PackedInt32Array
	var weights := sample["weights"] as PackedFloat32Array
	var selected := sample["triangles"] as PackedInt32Array
	var influences := bones.size() / vertices.size()
	var result := PackedVector3Array()
	for vertex_index: int in selected:
		var point := Vector3.ZERO
		var total := 0.0
		for influence in influences:
			var array_index := vertex_index * influences + influence
			var weight: float = weights[array_index]
			var bind_index: int = bones[array_index]
			if weight <= 0.0 or bind_index < 0 or bind_index >= bind_transforms.size():
				continue
			point += (bind_transforms[bind_index] * vertices[vertex_index]) * weight
			total += weight
		result.append(point / total if total > 0.0 else vertices[vertex_index])
	return result


func _bind_transforms(
	player: Player, mesh_part: MeshInstance3D, key: StringName
) -> Array[Transform3D]:
	var result: Array[Transform3D] = []
	var skin := mesh_part.get_skin_reference().get_skin()
	var modifier := _modifiers[key] as PlayerFootIKModifier
	result.resize(skin.get_bind_count())
	for bind_index in skin.get_bind_count():
		var bone_index := skin.get_bind_bone(bind_index)
		if bone_index < 0:
			bone_index = player.skeleton.find_bone(skin.get_bind_name(bind_index))
		var pose := _final_pose(player, modifier, bone_index, key)
		result[bind_index] = pose * skin.get_bind_pose(bind_index)
	return result


func _compare_skin_sample(
	name: String, authored: PackedVector3Array, corrected: PackedVector3Array, frame: int
) -> Dictionary:
	var max_ratio := 1.0
	for triangle_start in range(0, authored.size(), 3):
		for edge in [[0, 1], [1, 2], [2, 0]]:
			var authored_length := authored[triangle_start + edge[0]].distance_to(
				authored[triangle_start + edge[1]]
			)
			var ik_length := corrected[triangle_start + edge[0]].distance_to(
				corrected[triangle_start + edge[1]]
			)
			if minf(authored_length, ik_length) < EDGE_LENGTH_MIN:
				continue
			var ratio := maxf(authored_length / ik_length, ik_length / authored_length)
			var delta := absf(authored_length - ik_length)
			if delta > _maximum_edge_delta:
				_maximum_edge_delta = delta
				_worst_edge_frame = frame
			if ratio > max_ratio:
				max_ratio = ratio
			if ratio > _maximum_edge_ratio:
				_maximum_edge_ratio = ratio
				_worst_mesh = name
	var authored_key := "authored:%s" % name
	var ik_key := "ik:%s" % name
	var max_added_motion := 0.0
	if _previous_vertices.has(authored_key) and _previous_vertices.has(ik_key):
		var previous_authored := _previous_vertices[authored_key] as PackedVector3Array
		var previous_ik := _previous_vertices[ik_key] as PackedVector3Array
		for index in authored.size():
			var authored_motion := authored[index].distance_to(previous_authored[index])
			var ik_motion := corrected[index].distance_to(previous_ik[index])
			var added := maxf(0.0, ik_motion - authored_motion)
			if added > max_added_motion:
				max_added_motion = added
			if added > _maximum_added_vertex_motion:
				_maximum_added_vertex_motion = added
				_worst_mesh = name
				_worst_vertex = index
				_worst_motion_frame = frame
	_previous_vertices[authored_key] = authored
	_previous_vertices[ik_key] = corrected
	return {"max_edge_ratio": max_ratio, "max_added_motion": max_added_motion}


func _final_pose(
	player: Player, modifier: PlayerFootIKModifier, bone_index: int, key: StringName
) -> Transform3D:
	var rendered := _rendered_poses[key] as Dictionary
	if rendered.has(bone_index):
		return rendered[bone_index] as Transform3D
	if key == &"ik" and modifier._final_bone_poses.has(bone_index):
		return modifier._final_bone_poses[bone_index] as Transform3D
	return player.skeleton.get_bone_global_pose(bone_index)


func _transform_data(transform: Transform3D) -> Dictionary:
	var rotation := transform.basis.orthonormalized().get_rotation_quaternion()
	return {
		"position": transform.origin,
		"rotation": rotation,
		"scale": transform.basis.get_scale(),
	}


func _int_array(value: Variant) -> PackedInt32Array:
	return value as PackedInt32Array if value is PackedInt32Array else PackedInt32Array()


func _float_array(value: Variant) -> PackedFloat32Array:
	return value as PackedFloat32Array if value is PackedFloat32Array else PackedFloat32Array()
