class_name OutfitFitEditor
extends Node3D
## Experimental sparse rest-pose garment fitter.
##
## Imported meshes remain untouched. Each preview receives a rebuilt ArrayMesh whose vertex
## positions include the saved body/outfit-specific control-point offsets. Bone indices and
## weights are copied unchanged, so the adjusted rest shape still follows its original skeleton.

signal selection_changed(label: String, distance: float, radius: float)
signal selection_cleared
signal status_changed(message: String)

const PROFILE_DIR := "res://assets/outfit_fit_profiles"
const GRID_SAMPLER := preload("res://ui/outfit_fit_grid_sampler.gd")
const FIT_GEOMETRY := preload("res://ui/outfit_fit_geometry.gd")
const PROFILE_CODEC := preload("res://ui/outfit_fit_profile_codec.gd")
const PROFILE_SCHEMA := 1
const HANDLE_GRID_SPACING := 0.04
const DEFAULT_RADIUS := 0.08
const PICK_RADIUS_PX := 14.0
const DOT_RADIUS := 0.009
const SELECTED_DOT_RADIUS := 0.016
const SKIN_MATERIAL_PATTERNS := ["regular_male", "regular_female"]
const BODY_GRID_CELL_SIZE := 0.08
const DEFAULT_AUTO_CLEARANCE := 0.005
const COLLISION_STEP := 0.002
const CLIP_SEARCH_RADIUS := 0.08
const AUTO_SEARCH_RADIUS := 0.45
const AUTO_MAX_OFFSET := 0.35
const BODY_DEBUG_COLOR := Color(0.9, 0.04, 0.04)
const CLOTH_DEBUG_COLOR := Color(0.03, 0.18, 0.95)
const CLIP_DEBUG_COLOR := Color(0.05, 0.95, 0.15)

var _camera: Camera3D
var _outfit_root: Node3D
var _body_mesh: MeshInstance3D
var _body_id := ""
var _outfit_id := ""
var _visualize_clipping := false
var _mesh_states: Dictionary = {}
var _handles: Array[Dictionary] = []
var _handle_by_key: Dictionary = {}
var _edits: Dictionary = {}
var _auto_surface_offsets: Dictionary = {}
var _dots: Dictionary = {}
var _selected_key := ""
var _editing := false
var _show_control_points := true
var _body_triangles: Array[Dictionary] = []
var _body_triangle_grid: Dictionary = {}
var _body_normal_sign := 1.0
var _body_source_mesh: ArrayMesh
var _clipped_body_vertices: Dictionary = {}
var _load_generation := 0
var _clip_refresh_generation := 0
var _dot_material: StandardMaterial3D
var _selected_dot_material: StandardMaterial3D

func setup(camera: Camera3D) -> void:
	_camera = camera
	_dot_material = _make_dot_material(Color(0.1, 0.95, 1.0))
	_selected_dot_material = _make_dot_material(Color(1.0, 0.55, 0.05))


func clear_outfit() -> void:
	_load_generation += 1
	_clip_refresh_generation += 1
	if is_instance_valid(_body_mesh) and _body_source_mesh != null:
		_body_mesh.mesh = _body_source_mesh
	_outfit_root = null
	_body_mesh = null
	_body_source_mesh = null
	_body_id = ""
	_outfit_id = ""
	_visualize_clipping = false
	_mesh_states.clear()
	_handles.clear()
	_handle_by_key.clear()
	_edits.clear()
	_auto_surface_offsets.clear()
	_body_triangles.clear()
	_body_triangle_grid.clear()
	_body_normal_sign = 1.0
	_clipped_body_vertices.clear()
	_selected_key = ""
	_clear_dots()
	selection_cleared.emit()


func load_outfit(
	root: Node3D,
	body_mesh: MeshInstance3D,
	body_id: String,
	outfit_id: String,
	visualize_clipping: bool,
) -> void:
	clear_outfit()
	_outfit_root = root
	_body_mesh = body_mesh
	_body_source_mesh = body_mesh.mesh as ArrayMesh if body_mesh.mesh is ArrayMesh else null
	_body_id = body_id
	_outfit_id = outfit_id
	_visualize_clipping = visualize_clipping
	_capture_meshes()
	_build_handles()
	_load_profile()
	_rebuild_all_meshes()
	_build_dots()
	_update_dot_visibility()
	_initialize_clipping(_load_generation)


func set_editing(enabled: bool) -> void:
	_editing = enabled
	if not enabled:
		_selected_key = ""
		selection_cleared.emit()
	_update_dot_visibility()
	_refresh_dot_styles()


func set_control_points_visible(enabled: bool) -> void:
	_show_control_points = enabled
	_update_dot_visibility()

func set_clipping_visualization(enabled: bool) -> void:
	if enabled == _visualize_clipping:
		return
	_clip_refresh_generation += 1
	_visualize_clipping = enabled
	_clipped_body_vertices.clear()
	if not enabled:
		if is_instance_valid(_body_mesh) and _body_source_mesh != null:
			_body_mesh.mesh = _body_source_mesh
		_rebuild_geometry_only()
		return
	if _body_triangles.is_empty():
		_build_body_triangle_grid()
	_refresh_clipping()

func has_outfit() -> bool:
	return is_instance_valid(_outfit_root) and not _handles.is_empty()


func pick(screen_position: Vector2) -> bool:
	if not _editing or not is_instance_valid(_camera):
		return false
	var best_key := ""
	var best_distance_squared := PICK_RADIUS_PX * PICK_RADIUS_PX
	var best_depth := INF
	for handle in _handles:
		var key: String = handle["key"]
		var dot := _dots.get(key) as MeshInstance3D
		if not is_instance_valid(dot) or _camera.is_position_behind(dot.global_position):
			continue
		var projected := _camera.unproject_position(dot.global_position)
		var distance_squared := projected.distance_squared_to(screen_position)
		var depth := _camera.global_position.distance_squared_to(dot.global_position)
		if (distance_squared < best_distance_squared
				or (is_equal_approx(distance_squared, best_distance_squared) and depth < best_depth)):
			best_key = key
			best_distance_squared = distance_squared
			best_depth = depth
	if best_key.is_empty():
		return false
	_select_handle(best_key)
	return true


func set_selected_distance(distance: float, radius: float) -> void:
	if _selected_key.is_empty():
		return
	var handle: Dictionary = _handle_by_key.get(_selected_key, {})
	var measurement := _measure_handle(handle)
	if measurement.is_empty():
		status_changed.emit("Could not find the body surface below this point")
		return
	var current_world: Vector3 = measurement["world_position"]
	var normal: Vector3 = measurement["normal"]
	var corrected_world := current_world + normal * (distance - float(measurement["distance"]))
	var state: Dictionary = _mesh_states[handle["mesh"]]
	var mesh_instance := state["node"] as MeshInstance3D
	var local_correction := (
			mesh_instance.to_local(corrected_world) - mesh_instance.to_local(current_world))
	var previous: Dictionary = _edits.get(
			_selected_key, {"offset": Vector3.ZERO, "radius": DEFAULT_RADIUS})
	_edits[_selected_key] = {
		"offset": ((previous["offset"] as Vector3) + local_correction).limit_length(
				AUTO_MAX_OFFSET),
		"radius": maxf(radius, 0.001),
	}
	_rebuild_geometry_only()
	_refresh_dot_positions()
	_schedule_clipping_refresh()
	_emit_selected()
	status_changed.emit("Unsaved fit changes")


func reset_selected_distance() -> void:
	if _selected_key.is_empty():
		return
	var previous: Dictionary = _edits.get(
			_selected_key, {"offset": Vector3.ZERO, "radius": DEFAULT_RADIUS})
	if is_equal_approx(float(previous["radius"]), DEFAULT_RADIUS):
		_edits.erase(_selected_key)
	else:
		previous["offset"] = Vector3.ZERO
		_edits[_selected_key] = previous
	_rebuild_geometry_only()
	_refresh_dot_positions()
	_schedule_clipping_refresh()
	_emit_selected()
	status_changed.emit("Selected point distance reset; save to persist")


func reset_all() -> void:
	_edits.clear()
	_clear_auto_offsets()
	_rebuild_geometry_only()
	_refresh_dot_positions()
	_schedule_clipping_refresh()
	if not _selected_key.is_empty():
		_emit_selected()
	status_changed.emit("All points reset; save to persist")


func _clear_auto_offsets() -> void:
	for mesh_offsets_variant in _auto_surface_offsets.values():
		var mesh_offsets := mesh_offsets_variant as Array
		for offsets_variant in mesh_offsets:
			var offsets := offsets_variant as PackedVector3Array
			offsets.fill(Vector3.ZERO)


func auto_adjust(clearance: float = DEFAULT_AUTO_CLEARANCE) -> int:
	if not has_outfit() or not is_instance_valid(_body_mesh):
		status_changed.emit("No body/outfit pair is loaded")
		return 0
	for skeleton_node in _outfit_root.find_children("*", "Skeleton3D", true, false):
		(skeleton_node as Skeleton3D).advance(0.0)
	var body_skeleton := _body_mesh.get_node_or_null(_body_mesh.skeleton) as Skeleton3D
	if body_skeleton != null:
		body_skeleton.advance(0.0)
	if _body_triangles.is_empty():
		_build_body_triangle_grid()
	if _body_triangles.is_empty():
		status_changed.emit("Could not build the body surface for Auto Adjust")
		return 0
	_edits.clear()
	_clear_auto_offsets()
	_rebuild_geometry_only()
	var adjusted := 0
	var skipped := 0
	# Solve every garment vertex, including the cloth between visible controls.
	for iteration in 2:
		var correction_count := 0
		for mesh_key_variant in _mesh_states:
			var mesh_key := String(mesh_key_variant)
			var state: Dictionary = _mesh_states[mesh_key]
			var mesh_instance := state["node"] as MeshInstance3D
			var surfaces: Array = state["surfaces"]
			var mesh_offsets := _auto_surface_offsets[mesh_key] as Array
			for surface_index in surfaces.size():
				var surface: Dictionary = surfaces[surface_index]
				if not surface["is_clothing"]:
					continue
				var vertices: PackedVector3Array = surface["vertices"]
				var world_vertices := FIT_GEOMETRY.skin_vertices_world(
						mesh_instance, surface["arrays"])
				var offsets := mesh_offsets[surface_index] as PackedVector3Array
				for vertex_index in vertices.size():
					var current_world := world_vertices[vertex_index]
					var projection := _closest_body_projection(current_world)
					if projection.is_empty():
						if iteration == 0:
							skipped += 1
						continue
					var normal: Vector3 = projection["normal"]
					var signed_distance := (
							current_world - (projection["position"] as Vector3)).dot(normal)
					var error := clearance - signed_distance
					if error <= minf(clearance * 0.25, 0.00025):
						continue
					var corrected_world := current_world + normal * error
					var local_correction := (
							mesh_instance.to_local(corrected_world)
							- mesh_instance.to_local(current_world))
					offsets[vertex_index] = (
							offsets[vertex_index] + local_correction).limit_length(
									AUTO_MAX_OFFSET)
					correction_count += 1
					if iteration == 0:
						adjusted += 1
				mesh_offsets[surface_index] = offsets
			_auto_surface_offsets[mesh_key] = mesh_offsets
		if correction_count == 0:
			break
		_rebuild_geometry_only()
	var remaining_intersections := 0
	for _collision_pass in 64:
		var pushed_vertices := 0
		for mesh_key_variant in _mesh_states:
			var mesh_key := String(mesh_key_variant)
			var state: Dictionary = _mesh_states[mesh_key]
			var mesh_instance := state["node"] as MeshInstance3D
			var surfaces: Array = state["surfaces"]
			var mesh_offsets := _auto_surface_offsets[mesh_key] as Array
			for surface_index in surfaces.size():
				var surface: Dictionary = surfaces[surface_index]
				if not surface["is_clothing"]:
					continue
				var arrays: Array = surface["arrays"]
				var world_vertices := FIT_GEOMETRY.skin_vertices_world(mesh_instance, arrays)
				var intersections := FIT_GEOMETRY.find_intersections(
						world_vertices,
						arrays[Mesh.ARRAY_INDEX] as PackedInt32Array,
						_body_triangles,
						_body_triangle_grid,
						BODY_GRID_CELL_SIZE,
						_body_normal_sign)
				var marked: Dictionary = intersections["cloth_vertices"]
				var collision_normals: Dictionary = intersections["cloth_normals"]
				var offsets := mesh_offsets[surface_index] as PackedVector3Array
				var local_vertices: PackedVector3Array = surface["vertices"]
				for vertex_index_variant in marked:
					var vertex_index := int(vertex_index_variant)
					var current_world := mesh_instance.to_global(local_vertices[vertex_index])
					var normal := (collision_normals.get(
							vertex_index, Vector3.ZERO) as Vector3).normalized()
					if normal.is_zero_approx():
						var projection := _closest_body_projection(current_world)
						if projection.is_empty():
							continue
						normal = projection["normal"]
					var pushed_world := current_world + normal * maxf(
							COLLISION_STEP, clearance * 0.5)
					offsets[vertex_index] += (
							mesh_instance.to_local(pushed_world)
							- mesh_instance.to_local(current_world))
					pushed_vertices += 1
				mesh_offsets[surface_index] = offsets
			_auto_surface_offsets[mesh_key] = mesh_offsets
		remaining_intersections = pushed_vertices
		if pushed_vertices == 0:
			break
		_rebuild_geometry_only()
	_refresh_dot_positions()
	_schedule_clipping_refresh()
	if not _selected_key.is_empty():
		_emit_selected()
	status_changed.emit(
			"Contact-fit %d cloth vertices at %.1f mm%s%s; inspect, then save or reset"
			% [
				adjusted, clearance * 1000.0,
				" (%d skipped)" % skipped if skipped > 0 else "",
				(" (%d intersection vertices remain)" % remaining_intersections
						if remaining_intersections > 0 else ""),
			])
	return adjusted


func save_profile() -> bool:
	if _body_id.is_empty() or _outfit_id.is_empty():
		status_changed.emit("No body/outfit pair is loaded")
		return false
	var handles: Array[Dictionary] = []
	for key_variant in _edits:
		var key := String(key_variant)
		var edit: Dictionary = _edits[key]
		var offset: Vector3 = edit["offset"]
		if offset.is_zero_approx():
			continue
		var handle: Dictionary = _handle_by_key.get(key, {})
		if handle.is_empty():
			continue
		var state: Dictionary = _mesh_states[handle["mesh"]]
		var surfaces: Array = state["surfaces"]
		var surface: Dictionary = surfaces[handle["surface"]]
		var vertices: PackedVector3Array = surface["base_vertices"]
		var anchor := vertices[handle["vertex"]]
		handles.append({
			"mesh": handle["mesh"],
			"surface": handle["surface"],
			"vertex": handle["vertex"],
			"vertex_count": handle["vertex_count"],
			"anchor": [anchor.x, anchor.y, anchor.z],
			"offset": [offset.x, offset.y, offset.z],
			"radius": edit["radius"],
		})
	var document := {
		"schema": PROFILE_SCHEMA,
		"body_id": _body_id,
		"outfit_id": _outfit_id,
		"handles": handles,
		"auto_surfaces": PROFILE_CODEC.encode_auto_offsets(
				_auto_surface_offsets, _mesh_states),
	}
	var absolute_dir := ProjectSettings.globalize_path(PROFILE_DIR)
	var error := DirAccess.make_dir_recursive_absolute(absolute_dir)
	if error != OK:
		status_changed.emit("Could not create profile directory: error %d" % error)
		return false
	var file := FileAccess.open(_profile_path(), FileAccess.WRITE)
	if file == null:
		status_changed.emit("Could not write profile: error %d" % FileAccess.get_open_error())
		return false
	file.store_string(JSON.stringify(document, "\t") + "\n")
	status_changed.emit("Saved %d edited points to %s" % [handles.size(), _profile_path()])
	return true


func _capture_meshes() -> void:
	for node in _outfit_root.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := node as MeshInstance3D
		if not mesh_instance.mesh is ArrayMesh:
			continue
		var mesh_key := String(_outfit_root.get_path_to(mesh_instance))
		var source := mesh_instance.mesh as ArrayMesh
		var surfaces: Array[Dictionary] = []
		for surface_index in source.get_surface_count():
			var arrays := source.surface_get_arrays(surface_index)
			var vertices := arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array
			surfaces.append({
				"arrays": arrays,
				"base_vertices": vertices.duplicate(),
				"vertices": vertices.duplicate(),
				"blend_shapes": source.surface_get_blend_shape_arrays(surface_index),
				"format": source.surface_get_format(surface_index),
				"material": source.surface_get_material(surface_index),
				"name": source.surface_get_name(surface_index),
				"primitive": source.surface_get_primitive_type(surface_index),
				"is_clothing": _is_clothing_surface(source.surface_get_material(surface_index)),
			})
		_mesh_states[mesh_key] = {
			"node": mesh_instance,
			"source": source,
			"surfaces": surfaces,
		}
		var auto_offsets: Array[PackedVector3Array] = []
		for surface in surfaces:
			var offsets := PackedVector3Array()
			offsets.resize((surface["base_vertices"] as PackedVector3Array).size())
			auto_offsets.append(offsets)
		_auto_surface_offsets[mesh_key] = auto_offsets


func _build_handles() -> void:
	for candidate in GRID_SAMPLER.sample(_mesh_states, HANDLE_GRID_SPACING):
		var key := _handle_key(
				candidate["mesh"], candidate["surface"], candidate["vertex"])
		var handle := candidate.duplicate()
		handle["key"] = key
		_handles.append(handle)
		_handle_by_key[key] = handle


func _build_dots() -> void:
	_clear_dots()
	for handle in _handles:
		var dot := MeshInstance3D.new()
		var sphere := SphereMesh.new()
		sphere.radius = DOT_RADIUS
		sphere.height = DOT_RADIUS * 2.0
		sphere.radial_segments = 8
		sphere.rings = 4
		dot.mesh = sphere
		dot.material_override = _dot_material
		dot.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(dot)
		_dots[handle["key"]] = dot
	_refresh_dot_positions()
	_refresh_dot_styles()


func _clear_dots() -> void:
	for dot_variant in _dots.values():
		var dot := dot_variant as MeshInstance3D
		if is_instance_valid(dot):
			dot.queue_free()
	_dots.clear()


func _update_dot_visibility() -> void:
	for dot_variant in _dots.values():
		var dot := dot_variant as MeshInstance3D
		if is_instance_valid(dot):
			dot.visible = _editing and _show_control_points


func _refresh_dot_positions() -> void:
	for handle in _handles:
		var mesh_key: String = handle["mesh"]
		var state: Dictionary = _mesh_states.get(mesh_key, {})
		if state.is_empty():
			continue
		var surfaces: Array = state["surfaces"]
		var surface: Dictionary = surfaces[handle["surface"]]
		var vertices: PackedVector3Array = surface["vertices"]
		var dot := _dots.get(handle["key"]) as MeshInstance3D
		var mesh_instance := state["node"] as MeshInstance3D
		if is_instance_valid(dot) and is_instance_valid(mesh_instance):
			dot.global_position = mesh_instance.to_global(vertices[handle["vertex"]])


func _refresh_dot_styles() -> void:
	for key_variant in _dots:
		var key := String(key_variant)
		var dot := _dots[key] as MeshInstance3D
		var selected := key == _selected_key
		dot.material_override = _selected_dot_material if selected else _dot_material
		var radius := SELECTED_DOT_RADIUS if selected else DOT_RADIUS
		var sphere := dot.mesh as SphereMesh
		sphere.radius = radius
		sphere.height = radius * 2.0


func _select_handle(key: String) -> void:
	_selected_key = key
	_refresh_dot_styles()
	_emit_selected()


func _measure_handle(handle: Dictionary) -> Dictionary:
	if handle.is_empty():
		return {}
	if _body_triangles.is_empty():
		_build_body_triangle_grid()
	var state: Dictionary = _mesh_states.get(handle["mesh"], {})
	if state.is_empty():
		return {}
	var surfaces: Array = state["surfaces"]
	var surface: Dictionary = surfaces[handle["surface"]]
	var vertices: PackedVector3Array = surface["vertices"]
	var vertex_index := int(handle["vertex"])
	if vertex_index < 0 or vertex_index >= vertices.size():
		return {}
	var mesh_instance := state["node"] as MeshInstance3D
	var world_position := mesh_instance.to_global(vertices[vertex_index])
	var projection := _closest_body_projection(world_position)
	if projection.is_empty():
		return {}
	var normal: Vector3 = projection["normal"]
	return {
		"world_position": world_position,
		"normal": normal,
		"distance": (world_position - (projection["position"] as Vector3)).dot(normal),
	}


func _emit_selected() -> void:
	var handle: Dictionary = _handle_by_key.get(_selected_key, {})
	if handle.is_empty():
		selection_cleared.emit()
		return
	var edit: Dictionary = _edits.get(
			_selected_key, {"offset": Vector3.ZERO, "radius": DEFAULT_RADIUS})
	var measurement := _measure_handle(handle)
	if measurement.is_empty():
		selection_cleared.emit()
		return
	var label := "%s · surface %d · point %d" % [
		handle["mesh"], handle["surface"], handle["vertex"]]
	selection_changed.emit(label, measurement["distance"], edit["radius"])


func _rebuild_all_meshes() -> void:
	_rebuild_geometry_only()
	_refresh_clipping()


func _rebuild_geometry_only() -> void:
	for mesh_key_variant in _mesh_states:
		_rebuild_mesh(String(mesh_key_variant))


func _refresh_clipping() -> void:
	if not _visualize_clipping or _body_triangles.is_empty():
		return
	_clipped_body_vertices.clear()
	for skeleton_node in _outfit_root.find_children("*", "Skeleton3D", true, false):
		(skeleton_node as Skeleton3D).advance(0.0)
	for mesh_key_variant in _mesh_states:
		var mesh_key := String(mesh_key_variant)
		_rebuild_mesh(mesh_key, _detect_clipping_colors(mesh_key))
	_apply_body_clipping_colors()


func _schedule_clipping_refresh() -> void:
	_clip_refresh_generation += 1
	_refresh_clipping_after_delay(_clip_refresh_generation)


func _refresh_clipping_after_delay(generation: int) -> void:
	await get_tree().create_timer(0.18).timeout
	if generation != _clip_refresh_generation or not is_instance_valid(_outfit_root):
		return
	_refresh_clipping()


func _initialize_clipping(generation: int) -> void:
	if not _visualize_clipping:
		return
	await get_tree().process_frame
	if generation != _load_generation or not is_instance_valid(_outfit_root):
		return
	_build_body_triangle_grid()
	_refresh_clipping()


func _rebuild_mesh(mesh_key: String, clipping_colors: Dictionary = {}) -> void:
	var state: Dictionary = _mesh_states[mesh_key]
	var source := state["source"] as Mesh
	var surfaces: Array = state["surfaces"]
	for surface_index in surfaces.size():
		var surface: Dictionary = surfaces[surface_index]
		var base_vertices: PackedVector3Array = surface["base_vertices"]
		var vertices := base_vertices.duplicate()
		if surface["is_clothing"]:
			vertices = _deform_vertices(mesh_key, surface_index, base_vertices)
		surface["vertices"] = vertices
		var arrays: Array = surface["arrays"].duplicate(true)
		arrays[Mesh.ARRAY_VERTEX] = vertices
		if _visualize_clipping and surface["is_clothing"]:
			arrays[Mesh.ARRAY_COLOR] = clipping_colors.get(
					surface_index,
					FIT_GEOMETRY.solid_colors(vertices.size(), CLOTH_DEBUG_COLOR))
		surface["arrays"] = arrays
	var rebuilt := ArrayMesh.new()
	for blend_shape_index in source.get_blend_shape_count():
		rebuilt.add_blend_shape(source.get_blend_shape_name(blend_shape_index))
	rebuilt.blend_shape_mode = source.blend_shape_mode
	for surface_index in surfaces.size():
		var surface: Dictionary = surfaces[surface_index]
		var format: int = surface["format"]
		if _visualize_clipping and surface["is_clothing"]:
			format |= Mesh.ARRAY_FORMAT_COLOR
		rebuilt.add_surface_from_arrays(
				surface["primitive"], surface["arrays"], surface["blend_shapes"], {},
				format)
		rebuilt.surface_set_material(surface_index, surface["material"])
		rebuilt.surface_set_name(surface_index, surface["name"])
	var mesh_instance := state["node"] as MeshInstance3D
	mesh_instance.mesh = rebuilt


func _detect_clipping_colors(mesh_key: String) -> Dictionary:
	var result: Dictionary = {}
	var state: Dictionary = _mesh_states[mesh_key]
	var mesh_instance := state["node"] as MeshInstance3D
	var surfaces: Array = state["surfaces"]
	for surface_index in surfaces.size():
		var surface: Dictionary = surfaces[surface_index]
		if not surface["is_clothing"]:
			continue
		var arrays: Array = surface["arrays"]
		var world_vertices := FIT_GEOMETRY.skin_vertices_world(mesh_instance, arrays)
		result[surface_index] = _clipping_colors(world_vertices, arrays)
	return result


func _deform_vertices(
	mesh_key: String,
	surface_index: int,
	base_vertices: PackedVector3Array,
) -> PackedVector3Array:
	var result := base_vertices.duplicate()
	var mesh_offsets := _auto_surface_offsets.get(mesh_key, []) as Array
	if surface_index < mesh_offsets.size():
		var auto_offsets := mesh_offsets[surface_index] as PackedVector3Array
		if auto_offsets.size() == result.size():
			for vertex_index in result.size():
				result[vertex_index] += auto_offsets[vertex_index]
	var relevant: Array[Dictionary] = []
	var direct_offsets: Dictionary = {}
	for key_variant in _edits:
		var key := String(key_variant)
		var handle: Dictionary = _handle_by_key.get(key, {})
		if handle.get("mesh", "") == mesh_key and handle.get("surface", -1) == surface_index:
			var edit: Dictionary = _edits[key]
			if not (edit["offset"] as Vector3).is_zero_approx():
					relevant.append({
						"vertex": handle["vertex"],
						"position": base_vertices[handle["vertex"]],
						"offset": edit["offset"],
						"radius": edit["radius"],
					})
					direct_offsets[handle["vertex"]] = edit["offset"]
	if relevant.is_empty():
		return result
	for vertex_index in base_vertices.size():
		if direct_offsets.has(vertex_index):
			result[vertex_index] += direct_offsets[vertex_index] as Vector3
			continue
		var weighted_offset := Vector3.ZERO
		var total_weight := 0.0
		for edit in relevant:
			var radius: float = edit["radius"]
			var distance := base_vertices[vertex_index].distance_to(edit["position"])
			if distance >= radius:
				continue
			var unit := 1.0 - distance / radius
			var weight := unit * unit * (3.0 - 2.0 * unit)
			weighted_offset += (edit["offset"] as Vector3) * weight
			total_weight += weight
		if total_weight > 0.0:
			result[vertex_index] += weighted_offset / maxf(1.0, total_weight)
	return result


func _build_body_triangle_grid() -> void:
	if (not _body_triangles.is_empty() or not is_instance_valid(_body_mesh)
			or _body_source_mesh == null):
		return
	var orientation_score := 0.0
	for surface_index in _body_source_mesh.get_surface_count():
		var arrays := _body_source_mesh.surface_get_arrays(surface_index)
		var vertices := FIT_GEOMETRY.skin_vertices_world(_body_mesh, arrays)
		var indices := arrays[Mesh.ARRAY_INDEX] as PackedInt32Array
		var triangle_count := indices.size() / 3 if not indices.is_empty() else vertices.size() / 3
		for triangle_index in triangle_count:
			var vertex_indices := PackedInt32Array()
			vertex_indices.resize(3)
			for corner in 3:
				vertex_indices[corner] = (
					indices[triangle_index * 3 + corner]
					if not indices.is_empty() else triangle_index * 3 + corner)
			var a := vertices[vertex_indices[0]]
			var b := vertices[vertex_indices[1]]
			var c := vertices[vertex_indices[2]]
			var bounds := AABB(a, Vector3.ZERO).expand(b).expand(c)
			var normal := (b - a).cross(c - a).normalized()
			orientation_score += a.dot(b.cross(c))
			var stored_index := _body_triangles.size()
			_body_triangles.append({
				"a": a,
				"b": b,
				"c": c,
				"normal": normal,
				"surface": surface_index,
				"vertices": vertex_indices,
			})
			var minimum_cell := _body_grid_cell(bounds.position)
			var maximum_cell := _body_grid_cell(bounds.end)
			for x in range(minimum_cell.x, maximum_cell.x + 1):
				for y in range(minimum_cell.y, maximum_cell.y + 1):
					for z in range(minimum_cell.z, maximum_cell.z + 1):
						var cell := Vector3i(x, y, z)
						var bucket := _body_triangle_grid.get(
								cell, PackedInt32Array()) as PackedInt32Array
						bucket.append(stored_index)
						_body_triangle_grid[cell] = bucket
	_body_normal_sign = 1.0 if orientation_score >= 0.0 else -1.0


func _closest_body_projection(point: Vector3) -> Dictionary:
	var center_cell := _body_grid_cell(point)
	var maximum_ring := ceili(AUTO_SEARCH_RADIUS / BODY_GRID_CELL_SIZE)
	var tested: Dictionary = {}
	var best_distance_squared := INF
	var result: Dictionary = {}
	var first_occupied_ring := -1
	for ring in range(maximum_ring + 1):
		for x_offset in range(-ring, ring + 1):
			for y_offset in range(-ring, ring + 1):
				for z_offset in range(-ring, ring + 1):
					if maxi(
							absi(x_offset), maxi(absi(y_offset), absi(z_offset))) != ring:
						continue
					var cell := center_cell + Vector3i(x_offset, y_offset, z_offset)
					var triangle_indices := _body_triangle_grid.get(
							cell, PackedInt32Array()) as PackedInt32Array
					for triangle_index in triangle_indices:
						if tested.has(triangle_index):
							continue
						tested[triangle_index] = true
						var triangle: Dictionary = _body_triangles[triangle_index]
						var closest := FIT_GEOMETRY.closest_point_on_triangle(
								point, triangle["a"], triangle["b"], triangle["c"])
						var distance_squared := point.distance_squared_to(closest)
						if distance_squared >= best_distance_squared:
							continue
						var normal: Vector3 = triangle["normal"]
						if normal.is_zero_approx():
							continue
						best_distance_squared = distance_squared
						result = {
							"position": closest,
							"normal": normal * _body_normal_sign,
						}
		if not result.is_empty() and first_occupied_ring < 0:
			first_occupied_ring = ring
		# One extra ring accounts for a closer triangle just across a cell boundary.
		if first_occupied_ring >= 0 and ring >= first_occupied_ring + 1:
			break
	return result


func _clipping_colors(world_vertices: PackedVector3Array, arrays: Array) -> PackedColorArray:
	var colors := PackedColorArray()
	colors.resize(world_vertices.size())
	colors.fill(CLOTH_DEBUG_COLOR)
	var intersections := FIT_GEOMETRY.find_intersections(
			world_vertices,
			arrays[Mesh.ARRAY_INDEX] as PackedInt32Array,
			_body_triangles,
			_body_triangle_grid,
			BODY_GRID_CELL_SIZE,
			_body_normal_sign)
	for triangle_index in (intersections["body_triangles"] as Dictionary):
		_mark_body_triangle(triangle_index)
	# Also catch a garment patch wholly embedded without crossing a body triangle.
	for point in world_vertices:
		_mark_body_triangles_near_point(point)
	return colors


func _mark_body_triangles_near_point(point: Vector3) -> void:
	var bounds := AABB(point, Vector3.ZERO).grow(CLIP_SEARCH_RADIUS)
	var minimum_cell := _body_grid_cell(bounds.position)
	var maximum_cell := _body_grid_cell(bounds.end)
	var tested: Dictionary = {}
	var best_distance_squared := INF
	var best_triangle := -1
	var best_closest := Vector3.ZERO
	for x in range(minimum_cell.x, maximum_cell.x + 1):
		for y in range(minimum_cell.y, maximum_cell.y + 1):
			for z in range(minimum_cell.z, maximum_cell.z + 1):
				var triangle_indices := _body_triangle_grid.get(
						Vector3i(x, y, z), PackedInt32Array()) as PackedInt32Array
				for triangle_index in triangle_indices:
					if tested.has(triangle_index):
						continue
					tested[triangle_index] = true
					var body: Dictionary = _body_triangles[triangle_index]
					var closest := FIT_GEOMETRY.closest_point_on_triangle(
							point, body["a"], body["b"], body["c"])
					var distance_squared := point.distance_squared_to(closest)
					if distance_squared < best_distance_squared:
						best_distance_squared = distance_squared
						best_triangle = triangle_index
						best_closest = closest
	if best_triangle < 0:
		return
	var triangle: Dictionary = _body_triangles[best_triangle]
	var outward_normal: Vector3 = triangle["normal"] * _body_normal_sign
	if (point - best_closest).dot(outward_normal) < 0.0:
		_mark_body_triangle(best_triangle)


func _mark_body_triangle(triangle_index: int) -> void:
	var triangle: Dictionary = _body_triangles[triangle_index]
	var surface_index: int = triangle["surface"]
	if not _clipped_body_vertices.has(surface_index):
		_clipped_body_vertices[surface_index] = {}
	var marked: Dictionary = _clipped_body_vertices[surface_index]
	for vertex_index in triangle["vertices"]:
		marked[vertex_index] = true


func _apply_body_clipping_colors() -> void:
	if not _visualize_clipping or _body_source_mesh == null:
		return
	var rebuilt := ArrayMesh.new()
	for blend_shape_index in _body_source_mesh.get_blend_shape_count():
		rebuilt.add_blend_shape(_body_source_mesh.get_blend_shape_name(blend_shape_index))
	rebuilt.blend_shape_mode = _body_source_mesh.blend_shape_mode
	for surface_index in _body_source_mesh.get_surface_count():
		var arrays := _body_source_mesh.surface_get_arrays(surface_index)
		var vertices := arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array
		var colors := PackedColorArray()
		colors.resize(vertices.size())
		var marked: Dictionary = _clipped_body_vertices.get(surface_index, {})
		for vertex_index in vertices.size():
			colors[vertex_index] = (
				CLIP_DEBUG_COLOR if marked.has(vertex_index) else BODY_DEBUG_COLOR)
		arrays[Mesh.ARRAY_COLOR] = colors
		var format := _body_source_mesh.surface_get_format(surface_index)
		format |= Mesh.ARRAY_FORMAT_COLOR
		rebuilt.add_surface_from_arrays(
				_body_source_mesh.surface_get_primitive_type(surface_index),
				arrays,
				_body_source_mesh.surface_get_blend_shape_arrays(surface_index),
				{},
				format)
		rebuilt.surface_set_material(
				surface_index, _body_source_mesh.surface_get_material(surface_index))
		rebuilt.surface_set_name(
				surface_index, _body_source_mesh.surface_get_name(surface_index))
	_body_mesh.mesh = rebuilt


func _body_grid_cell(point: Vector3) -> Vector3i:
	return Vector3i(
			floori(point.x / BODY_GRID_CELL_SIZE),
			floori(point.y / BODY_GRID_CELL_SIZE),
			floori(point.z / BODY_GRID_CELL_SIZE))


func _load_profile() -> void:
	var path := _profile_path()
	if not FileAccess.file_exists(path):
		status_changed.emit("No saved fit for this body/outfit")
		return
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		status_changed.emit("Could not read saved fit")
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if not parsed is Dictionary:
		status_changed.emit("Saved fit is invalid JSON")
		return
	var document := parsed as Dictionary
	if (document.get("schema") != PROFILE_SCHEMA
			or document.get("body_id") != _body_id
			or document.get("outfit_id") != _outfit_id):
		status_changed.emit("Saved fit does not match this body/outfit")
		return
	var loaded := 0
	var loaded_auto := PROFILE_CODEC.decode_auto_offsets(
			document.get("auto_surfaces", []), _mesh_states, _auto_surface_offsets)
	for record_variant in document.get("handles", []):
		var record := record_variant as Dictionary
		var mesh_key := String(record.get("mesh", ""))
		var surface_index := int(record.get("surface", -1))
		var vertex_index := int(record.get("vertex", -1))
		var state: Dictionary = _mesh_states.get(mesh_key, {})
		if state.is_empty():
			continue
		var surfaces: Array = state["surfaces"]
		if surface_index < 0 or surface_index >= surfaces.size():
			continue
		var surface: Dictionary = surfaces[surface_index]
		var vertices: PackedVector3Array = surface["base_vertices"]
		if (record.get("vertex_count", -1) != vertices.size()
			or vertex_index < 0 or vertex_index >= vertices.size()):
			continue
		var anchor_values: Array = record.get("anchor", [])
		if anchor_values.size() != 3:
			continue
		var saved_anchor := Vector3(
				float(anchor_values[0]), float(anchor_values[1]), float(anchor_values[2]))
		if not saved_anchor.is_equal_approx(vertices[vertex_index]):
			continue
		var key := _handle_key(mesh_key, surface_index, vertex_index)
		# Grid sampling can choose different representative vertices than an older
		# profile. Keep any previously saved anchor as an additional control so
		# existing body/outfit fits continue to load exactly.
		if not _handle_by_key.has(key):
			var handle := {
				"key": key,
				"mesh": mesh_key,
				"surface": surface_index,
				"vertex": vertex_index,
				"vertex_count": vertices.size(),
			}
			_handles.append(handle)
			_handle_by_key[key] = handle
		var values: Array = record.get("offset", [])
		if values.size() != 3:
			continue
		_edits[key] = {
			"offset": Vector3(float(values[0]), float(values[1]), float(values[2])),
			"radius": float(record.get("radius", DEFAULT_RADIUS)),
		}
		loaded += 1
	status_changed.emit(
			"Loaded %d manual points and %d contact-fit vertices" % [loaded, loaded_auto])


func _profile_path() -> String:
	return "%s/%s__%s.json" % [PROFILE_DIR, _safe_id(_body_id), _safe_id(_outfit_id)]


func _handle_key(mesh_key: String, surface_index: int, vertex_index: int) -> String:
	return "%s::%d::%d" % [mesh_key, surface_index, vertex_index]


func _is_clothing_surface(material: Material) -> bool:
	if material == null:
		return true
	var material_name := material.resource_name.to_lower()
	for pattern in SKIN_MATERIAL_PATTERNS:
		if pattern in material_name:
			return false
	return true


func _make_dot_material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.disable_receive_shadows = true
	return material


func _safe_id(value: String) -> String:
	var result := ""
	for character in value:
		result += character if character.is_valid_identifier() or character == "-" else "_"
	return result
