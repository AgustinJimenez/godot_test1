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
const GRID_SAMPLER := preload("res://ui/outfit_fit/grid_sampler.gd")
const FIT_GEOMETRY := preload("res://ui/outfit_fit/geometry.gd")
const PROFILE_CODEC := preload("res://ui/outfit_fit/profile_codec.gd")
const OUTFIT_LAYERS := preload("res://ui/outfit_fit/layers.gd")
const OUTFIT_COMPONENTS := preload("res://ui/outfit_fit/components.gd")
const OUTFIT_SOLVER := preload("res://ui/outfit_fit/solver.gd")
const OUTFIT_VISUALIZATION := preload("res://ui/outfit_fit/visualization.gd")
const PROFILE_SCHEMA := 1
const HANDLE_GRID_SPACING := 0.04
const DEFAULT_RADIUS := 0.08
const PICK_RADIUS_PX := 14.0
const DOT_RADIUS := 0.009
const SELECTED_DOT_RADIUS := 0.016
const BODY_GRID_CELL_SIZE := 0.08
const DEFAULT_AUTO_CLEARANCE := 0.005
const AUTO_SEARCH_RADIUS := 0.45
const AUTO_MAX_OFFSET := 0.35

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
var _debug_body_vertices: Dictionary = {}
var _load_generation := 0
var _clip_refresh_generation := 0
var _selected_component_index := -1
var _isolate_selected := false
var _body_visible_before_load := true
var _dot_material: StandardMaterial3D
var _selected_dot_material: StandardMaterial3D

func setup(camera: Camera3D) -> void:
	_camera = camera
	_dot_material = OUTFIT_COMPONENTS.dot_material(Color(0.1, 0.95, 1.0))
	_selected_dot_material = OUTFIT_COMPONENTS.dot_material(Color(1.0, 0.55, 0.05))


func clear_outfit() -> void:
	_load_generation += 1
	_clip_refresh_generation += 1
	if is_instance_valid(_body_mesh):
		if _body_source_mesh != null:
			_body_mesh.mesh = _body_source_mesh
		_body_mesh.visible = _body_visible_before_load
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
	_debug_body_vertices.clear()
	_selected_key = ""
	_selected_component_index = -1
	_isolate_selected = false
	_body_visible_before_load = true
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
	_body_visible_before_load = body_mesh.visible
	_body_source_mesh = body_mesh.mesh as ArrayMesh if body_mesh.mesh is ArrayMesh else null
	_body_id = body_id
	_outfit_id = outfit_id
	_visualize_clipping = visualize_clipping
	_capture_meshes()
	_build_handles()
	_load_profile()
	OUTFIT_COMPONENTS.synchronize_auto_offset_constraints(_mesh_states, _auto_surface_offsets)
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

func _set_isolate_selected(enabled: bool) -> void:
	var selected := get_selected_surface()
	var next_value := enabled and (
			not selected.is_empty()
			and selected.get("component_index", -1) as int >= 0)
	if next_value == _isolate_selected:
		return
	_isolate_selected = next_value
	_apply_body_isolation_visibility()
	_rebuild_all_meshes()


func set_clipping_visualization(enabled: bool) -> void:
	if enabled == _visualize_clipping:
		return
	_clip_refresh_generation += 1
	_visualize_clipping = enabled
	_clipped_body_vertices.clear()
	_debug_body_vertices.clear()
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
	return _auto_adjust_surfaces(clearance)


func _auto_adjust_surfaces(
	clearance: float,
	filter_mesh: String = "",
	filter_surface: int = -1,
	filter_component: int = -1,
) -> int:
	if not has_outfit() or not is_instance_valid(_body_mesh):
		status_changed.emit("No body/outfit pair is loaded")
		return 0
	var filter_enabled := not filter_mesh.is_empty() and filter_surface >= 0
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
	if filter_enabled:
		var selected_offsets := _auto_surface_offsets[filter_mesh] as Array
		var offsets := selected_offsets[filter_surface] as PackedVector3Array
		if filter_component < 0:
			offsets.fill(Vector3.ZERO)
		else:
			for vertex_index in OUTFIT_COMPONENTS.vertex_indices(
					_mesh_states, filter_mesh, filter_surface, filter_component):
				offsets[vertex_index] = Vector3.ZERO
		_auto_surface_offsets[filter_mesh] = selected_offsets
	else:
		_edits.clear()
		_clear_auto_offsets()
	var result := OUTFIT_SOLVER.run({
		"mesh_states": _mesh_states,
		"auto_offsets": _auto_surface_offsets,
		"body_triangles": _body_triangles,
		"body_grid": _body_triangle_grid,
		"body_cell_size": BODY_GRID_CELL_SIZE,
		"body_normal_sign": _body_normal_sign,
		"search_radius": AUTO_SEARCH_RADIUS,
		"maximum_offset": AUTO_MAX_OFFSET,
		"rebuild_geometry": _rebuild_geometry_only,
		"closest_body_projection": _closest_body_projection,
	}, clearance, filter_mesh, filter_surface, filter_component)
	_refresh_dot_positions()
	_schedule_clipping_refresh()
	if not _selected_key.is_empty():
		_emit_selected()
	status_changed.emit(result["status"])
	return result["adjusted"]


func fit_selected_surface(clearance: float = DEFAULT_AUTO_CLEARANCE) -> int:
	if not has_outfit() or not is_instance_valid(_body_mesh):
		status_changed.emit("No body/outfit pair is loaded")
		return 0
	if _selected_key.is_empty():
		status_changed.emit("No surface selected")
		return 0
	var handle: Dictionary = _handle_by_key.get(_selected_key, {})
	var mesh_key := handle.get("mesh", "") as String
	var surface_index := handle.get("surface", -1) as int
	var component_index := _selected_component_index
	var state: Dictionary = _mesh_states.get(mesh_key, {})
	var surfaces: Array = state.get("surfaces", [])
	if state.is_empty():
		return 0
	var is_cloth := surface_index >= 0 and surface_index < surfaces.size()
	if not is_cloth or not surfaces[surface_index]["is_clothing"]:
		if is_cloth and not surfaces[surface_index]["is_clothing"]:
			status_changed.emit("Selected surface is skin, not clothing")
		return 0
	return _auto_adjust_surfaces(
			clearance, mesh_key, surface_index, component_index)


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
			var components := OUTFIT_LAYERS.surface_components(arrays)
			var vertex_components := PackedInt32Array()
			vertex_components.resize(vertices.size())
			vertex_components.fill(-1)
			for component_index in components.size():
				var component := components[component_index] as Dictionary
				for vertex_index in (component["vertex_indices"] as PackedInt32Array):
					vertex_components[vertex_index] = component_index
			var source_colors: Variant = arrays[Mesh.ARRAY_COLOR]
			if source_colors is PackedColorArray:
				source_colors = (source_colors as PackedColorArray).duplicate()
			surfaces.append({
				"arrays": arrays,
				"source_colors": source_colors,
				"base_vertices": vertices.duplicate(),
				"vertices": vertices.duplicate(),
				"blend_shapes": source.surface_get_blend_shape_arrays(surface_index),
				"format": source.surface_get_format(surface_index),
				"material": source.surface_get_material(surface_index),
				"name": source.surface_get_name(surface_index),
				"primitive": source.surface_get_primitive_type(surface_index),
				"is_clothing": OUTFIT_COMPONENTS.is_clothing_surface(
						source.surface_get_material(surface_index)),
				"components": components,
				"vertex_components": vertex_components,
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
		var state: Dictionary = _mesh_states[handle["mesh"]]
		var surfaces: Array = state["surfaces"]
		var surface: Dictionary = surfaces[handle["surface"]]
		var vertex_components := surface["vertex_components"] as PackedInt32Array
		handle["component"] = vertex_components[handle["vertex"]]
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
	var filter_mesh := ""
	var filter_surface := -1
	if not _selected_key.is_empty():
		var selected_handle: Dictionary = _handle_by_key.get(_selected_key, {})
		filter_mesh = selected_handle.get("mesh", "") as String
		filter_surface = selected_handle.get("surface", -1) as int
	for key_variant in _dots:
		var key := String(key_variant)
		var dot := _dots[key] as MeshInstance3D
		if is_instance_valid(dot):
			if _editing and _show_control_points:
				var handle: Dictionary = _handle_by_key.get(key, {})
				dot.visible = (
						filter_mesh.is_empty()
						or (
							handle.get("mesh", "") == filter_mesh
							and handle.get("surface", -1) == filter_surface
							and (
								_selected_component_index < 0
								or handle.get("component", -1)
										== _selected_component_index)))
			else:
				dot.visible = false


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

func _select_handle(key: String, preserve_component: bool = false) -> void:
	var was_isolated := _isolate_selected
	if not preserve_component or _selected_component_index < 0:
		_selected_component_index = -1
		_isolate_selected = false
	_selected_key = key
	_apply_body_isolation_visibility()
	if _isolate_selected or was_isolated:
		_rebuild_geometry_only()
	_refresh_dot_styles()
	_update_dot_visibility()
	_emit_selected()
	_refresh_clipping()


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
	var saved := _visualize_clipping
	_visualize_clipping = false
	for mesh_key_variant in _mesh_states:
		_rebuild_mesh(String(mesh_key_variant))
	_visualize_clipping = saved


func _refresh_clipping() -> void:
	if not _visualize_clipping or _body_triangles.is_empty():
		return
	_clipped_body_vertices.clear()
	_debug_body_vertices.clear()
	for skeleton_node in _outfit_root.find_children("*", "Skeleton3D", true, false):
		(skeleton_node as Skeleton3D).advance(0.0)
	var filter_mesh := ""
	var filter_surface := -1
	var filter_component := -1
	if not _selected_key.is_empty():
		var handle: Dictionary = _handle_by_key.get(_selected_key, {})
		filter_mesh = handle.get("mesh", "") as String
		filter_surface = handle.get("surface", -1) as int
		filter_component = _selected_component_index
	_rebuild_geometry_only()
	if not filter_mesh.is_empty():
		var colors := _detect_clipping_colors(
				filter_mesh, filter_surface, filter_component)
		var filtered: Dictionary = {}
		filtered[filter_surface] = colors.get(filter_surface, PackedColorArray())
		_rebuild_mesh(filter_mesh, filtered)
	else:
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
	var result := OUTFIT_COMPONENTS.rebuild_preview_mesh(
			source, surfaces, mesh_key, clipping_colors, _visualize_clipping,
			_isolation_selection(), _deform_vertices)
	var mesh_instance := state["node"] as MeshInstance3D
	mesh_instance.mesh = result["mesh"]


func _detect_clipping_colors(
	mesh_key: String,
	filter_surface: int = -1,
	filter_component: int = -1,
) -> Dictionary:
	var result: Dictionary = {}
	var state: Dictionary = _mesh_states[mesh_key]
	var mesh_instance := state["node"] as MeshInstance3D
	var surfaces: Array = state["surfaces"]
	for surface_index in surfaces.size():
		var surface: Dictionary = surfaces[surface_index]
		if not surface["is_clothing"]:
			continue
		if filter_surface >= 0 and surface_index != filter_surface:
			continue
		var arrays: Array = surface["arrays"]
		var world_vertices := FIT_GEOMETRY.skin_vertices_world(mesh_instance, arrays)
		var component_indices := PackedInt32Array()
		if filter_component >= 0:
			var components: Array = surface["components"]
			if filter_component < components.size():
				component_indices = (
						components[filter_component]["indices"] as PackedInt32Array)
		result[surface_index] = OUTFIT_VISUALIZATION.clipping_colors(
				world_vertices,
				arrays,
				component_indices,
				_body_triangles,
				_body_triangle_grid,
				BODY_GRID_CELL_SIZE,
				_body_normal_sign,
				_clipped_body_vertices,
				_debug_body_vertices)
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
						"component": handle.get("component", -1),
					})
					direct_offsets[handle["vertex"]] = edit["offset"]
	if relevant.is_empty():
		return result
	var vertex_components := (
			(_mesh_states[mesh_key]["surfaces"] as Array)[surface_index][
					"vertex_components"] as PackedInt32Array)
	for vertex_index in base_vertices.size():
		if direct_offsets.has(vertex_index):
			result[vertex_index] += direct_offsets[vertex_index] as Vector3
			continue
		var weighted_offset := Vector3.ZERO
		var total_weight := 0.0
		for edit in relevant:
			if edit["component"] != vertex_components[vertex_index]:
				continue
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
	var result := OUTFIT_VISUALIZATION.build_body_triangle_grid(
			_body_mesh, _body_source_mesh, BODY_GRID_CELL_SIZE)
	_body_triangles = result["triangles"]
	_body_triangle_grid = result["grid"]
	_body_normal_sign = result["normal_sign"]


func _closest_body_projection(point: Vector3, region: String = "") -> Dictionary:
	return FIT_GEOMETRY.closest_body_projection(
			point,
			_body_triangles,
			_body_triangle_grid,
			BODY_GRID_CELL_SIZE,
			AUTO_SEARCH_RADIUS,
			_body_normal_sign,
			region)


func _apply_body_clipping_colors() -> void:
	if not _visualize_clipping or _body_source_mesh == null:
		return
	OUTFIT_VISUALIZATION.apply_body_clipping_colors(
			_body_mesh,
			_body_source_mesh,
			_clipped_body_vertices,
			_debug_body_vertices,
			not _selected_key.is_empty())


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
				"component": (surface["vertex_components"] as PackedInt32Array)[vertex_index],
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
	return "%s/%s__%s.json" % [
			PROFILE_DIR, PROFILE_CODEC.safe_id(_body_id), PROFILE_CODEC.safe_id(_outfit_id)]


func _handle_key(mesh_key: String, surface_index: int, vertex_index: int) -> String:
	return "%s::%d::%d" % [mesh_key, surface_index, vertex_index]


func get_clothing_surfaces() -> Array[Dictionary]:
	return OUTFIT_COMPONENTS.clothing_surfaces(_mesh_states)
func get_surface_components(mesh_key: String, surface_index: int) -> Array[Dictionary]:
	return OUTFIT_COMPONENTS.surface_components(_mesh_states, mesh_key, surface_index)
func select_surface(
	mesh_key: String, surface_index: int, component_index: int = -1,
) -> bool:
	for handle in _handles:
		if (handle["mesh"] == mesh_key
				and handle["surface"] == surface_index
				and (
					component_index < 0
					or handle.get("component", -1) == component_index)):
			_selected_component_index = component_index
			_select_handle(handle["key"], true)
			return true
	return false


func clear_surface_selection() -> void:
	if _selected_key.is_empty():
		return
	_selected_key = ""
	_selected_component_index = -1
	_isolate_selected = false
	_apply_body_isolation_visibility()
	_rebuild_geometry_only()
	_refresh_dot_styles()
	_update_dot_visibility()
	selection_cleared.emit()
	_refresh_clipping()


func get_selected_surface() -> Dictionary:
	if _selected_key.is_empty():
		return {}
	var handle: Dictionary = _handle_by_key.get(_selected_key, {})
	if handle.is_empty():
		return {}
	return {
		"mesh_key": handle["mesh"],
		"surface_index": handle["surface"],
		"component_index": _selected_component_index,
	}


func get_selected_surface_center() -> Vector3:
	if _selected_key.is_empty():
		return Vector3.ZERO
	var handle: Dictionary = _handle_by_key.get(_selected_key, {})
	if handle.is_empty():
		return Vector3.ZERO
	var mesh_key := handle["mesh"] as String
	var surface_index := handle["surface"] as int
	return OUTFIT_COMPONENTS.center(
			_mesh_states,
			mesh_key,
			surface_index,
			_selected_component_index)


func _isolation_selection() -> Dictionary:
	return get_selected_surface() if _isolate_selected else {}


func _apply_body_isolation_visibility() -> void:
	if is_instance_valid(_body_mesh):
		_body_mesh.visible = (
				false if _isolate_selected else _body_visible_before_load)
