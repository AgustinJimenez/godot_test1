class_name CharacterEditorPoseLibraryHandler
extends RefCounted

## Visual index of saved Character Editor presets. Preset JSON remains the
## source of truth; this handler stores only discovery paths and thumbnails.

const LIBRARY_PATH := "user://character_editor_pose_library.json"
const PREVIEW_DIRECTORY := "user://character_editor_pose_previews"
const LIVE_PREVIEW_DISTANCE_FACTOR := 2.35
const THUMBNAIL_DISTANCE_FACTOR := 1.15
const BUTTON_ROTATION_STEP := PI / 12.0
const BUTTON_ZOOM_FACTOR := 0.88
const BUTTON_REPEAT_DELAY := 0.3
const BUTTON_REPEAT_INTERVAL := 0.06
const ACTION_ROTATE_LEFT := &"rotate_left"
const ACTION_ROTATE_RIGHT := &"rotate_right"
const ACTION_ROTATE_UP := &"rotate_up"
const ACTION_ROTATE_DOWN := &"rotate_down"
const ACTION_ZOOM_OUT := &"zoom_out"
const ACTION_ZOOM_IN := &"zoom_in"
const BUILTIN_POSES: PackedStringArray = [
	"res://actors/player/flashlight_grip_pose.json",
	"res://actors/player/rusty_knife_grip_pose.json",
]

var editor: CharacterEditor
var _entries: Array[Dictionary] = []
var _selected_pose_path := ""
var _card_buttons: Dictionary[String, Button] = {}
var _preview_textures: Dictionary[String, TextureRect] = {}
var _live_preview_root: Node3D
var _live_camera: Camera3D
var _live_fill_light: OmniLight3D
var _generating_previews := false
var _preview_dragging := false
var _preview_yaw := 0.0
var _preview_pitch := 0.0
var _preview_distance := 1.0
var _preview_extent := 1.0
var _preview_control_timer: Timer
var _held_preview_action := &""


func _init(editor_ref: CharacterEditor) -> void:
	editor = editor_ref


func setup() -> void:
	editor.pose_library_close_button.pressed.connect(close)
	editor.pose_library_browse_button.pressed.connect(_browse)
	editor.pose_library_load_button.pressed.connect(_load_selected)
	editor.pose_library_search.text_changed.connect(_rebuild_grid)
	editor.pose_library_viewport_container.gui_input.connect(_on_preview_gui_input)
	editor.pose_library_viewport_container.mouse_default_cursor_shape = Control.CURSOR_DRAG
	_connect_preview_control(editor.pose_library_rotate_left_button, ACTION_ROTATE_LEFT)
	_connect_preview_control(editor.pose_library_rotate_right_button, ACTION_ROTATE_RIGHT)
	_connect_preview_control(editor.pose_library_rotate_up_button, ACTION_ROTATE_UP)
	_connect_preview_control(editor.pose_library_rotate_down_button, ACTION_ROTATE_DOWN)
	_connect_preview_control(editor.pose_library_zoom_out_button, ACTION_ZOOM_OUT)
	_connect_preview_control(editor.pose_library_zoom_in_button, ACTION_ZOOM_IN)
	_preview_control_timer = Timer.new()
	_preview_control_timer.one_shot = true
	_preview_control_timer.timeout.connect(_on_preview_control_timeout)
	editor.add_child(_preview_control_timer)
	_setup_live_preview()
	for path: String in BUILTIN_POSES:
		_add_pose(path)
	_load_persisted_paths()
	_rebuild_grid()


func open() -> void:
	_rebuild_grid()
	editor.pose_library_overlay.show()
	var initial_path := editor._current_pose_path
	if not _entry_exists(initial_path) and not _entries.is_empty():
		initial_path = _entries[0]["path"]
	if not initial_path.is_empty():
		_select_card(initial_path)
	_generate_missing_previews()
	editor.pose_library_search.grab_focus()


func close() -> void:
	editor.pose_library_overlay.hide()
	_preview_dragging = false
	_stop_preview_control()


func register_saved_pose(path: String) -> void:
	_add_pose(editor._localize_resource_path(path))
	_save_paths()
	if editor.pose_library_overlay.visible:
		_rebuild_grid()


func capture_object_preview(path: String) -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(PREVIEW_DIRECTORY))
	await _render_object_preview(path, _preview_path(path))
	if editor.pose_library_overlay.visible:
		_update_cached_preview(path)


func _setup_live_preview() -> void:
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.018, 0.028, 0.042)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.55, 0.62, 0.72)
	environment.ambient_light_energy = 1.25
	var world_environment := WorldEnvironment.new()
	world_environment.environment = environment
	editor.pose_library_viewport.add_child(world_environment)
	_live_camera = Camera3D.new()
	_live_camera.fov = 36.0
	editor.pose_library_viewport.add_child(_live_camera)
	_live_camera.current = true
	var key_light := DirectionalLight3D.new()
	key_light.rotation_degrees = Vector3(-42.0, -32.0, 0.0)
	key_light.light_energy = 1.8
	editor.pose_library_viewport.add_child(key_light)
	_live_fill_light = OmniLight3D.new()
	_live_fill_light.light_energy = 2.2
	editor.pose_library_viewport.add_child(_live_fill_light)


func _show_live_preview(path: String) -> void:
	if is_instance_valid(_live_preview_root):
		_live_preview_root.free()
	var object_path := _read_object_path(path)
	var packed := load(object_path) as PackedScene
	if packed == null:
		return
	var instance := packed.instantiate() as Node3D
	if instance == null:
		return
	_live_preview_root = Node3D.new()
	editor.pose_library_viewport.add_child(_live_preview_root)
	_live_preview_root.add_child(instance)
	var bounds := _object_bounds(instance)
	if bounds.size.is_zero_approx():
		return
	instance.position -= bounds.get_center()
	_preview_extent = maxf(bounds.size.x, maxf(bounds.size.y, bounds.size.z))
	_preview_distance = _preview_extent * LIVE_PREVIEW_DISTANCE_FACTOR
	_preview_yaw = 0.0
	_preview_pitch = 0.0
	_preview_dragging = false
	_live_preview_root.rotation = Vector3.ZERO
	_live_fill_light.position = Vector3(
			-_preview_extent, _preview_extent, _preview_extent)
	_live_fill_light.omni_range = _preview_extent * 5.0
	_update_live_preview_camera()


func _on_preview_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var button_event := event as InputEventMouseButton
		if button_event.button_index == MOUSE_BUTTON_LEFT:
			_preview_dragging = button_event.pressed
			editor.pose_library_viewport_container.accept_event()
		elif button_event.pressed and button_event.button_index in [
				MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			var zoom_factor := BUTTON_ZOOM_FACTOR \
					if button_event.button_index == MOUSE_BUTTON_WHEEL_UP \
					else 1.0 / BUTTON_ZOOM_FACTOR
			_zoom_live_preview(zoom_factor)
			editor.pose_library_viewport_container.accept_event()
	elif event is InputEventMouseMotion and _preview_dragging:
		var motion := event as InputEventMouseMotion
		_preview_yaw -= motion.relative.x * 0.01
		_preview_pitch = clampf(
				_preview_pitch - motion.relative.y * 0.01,
				-deg_to_rad(85.0), deg_to_rad(85.0))
		if is_instance_valid(_live_preview_root):
			_live_preview_root.rotation = Vector3(_preview_pitch, _preview_yaw, 0.0)
		editor.pose_library_viewport_container.accept_event()
	elif event is InputEventMagnifyGesture:
		var magnify := event as InputEventMagnifyGesture
		_zoom_live_preview(1.0 / maxf(magnify.factor, 0.01))
		editor.pose_library_viewport_container.accept_event()


func _rotate_live_preview(pitch_delta: float, yaw_delta: float) -> void:
	_preview_yaw += yaw_delta
	_preview_pitch = clampf(
			_preview_pitch + pitch_delta,
			-deg_to_rad(85.0), deg_to_rad(85.0))
	if is_instance_valid(_live_preview_root):
		_live_preview_root.rotation = Vector3(_preview_pitch, _preview_yaw, 0.0)


func _connect_preview_control(button: Button, action: StringName) -> void:
	button.button_down.connect(_start_preview_control.bind(action))
	button.button_up.connect(_stop_preview_control)


func _start_preview_control(action: StringName) -> void:
	_held_preview_action = action
	_apply_preview_control(action)
	_preview_control_timer.one_shot = true
	_preview_control_timer.start(BUTTON_REPEAT_DELAY)


func _stop_preview_control() -> void:
	_held_preview_action = &""
	if is_instance_valid(_preview_control_timer):
		_preview_control_timer.stop()


func _on_preview_control_timeout() -> void:
	if _held_preview_action.is_empty():
		return
	_apply_preview_control(_held_preview_action)
	_preview_control_timer.one_shot = false
	_preview_control_timer.start(BUTTON_REPEAT_INTERVAL)


func _apply_preview_control(action: StringName) -> void:
	match action:
		ACTION_ROTATE_LEFT:
			_rotate_live_preview(0.0, -BUTTON_ROTATION_STEP)
		ACTION_ROTATE_RIGHT:
			_rotate_live_preview(0.0, BUTTON_ROTATION_STEP)
		ACTION_ROTATE_UP:
			_rotate_live_preview(-BUTTON_ROTATION_STEP, 0.0)
		ACTION_ROTATE_DOWN:
			_rotate_live_preview(BUTTON_ROTATION_STEP, 0.0)
		ACTION_ZOOM_OUT:
			_zoom_live_preview(1.0 / BUTTON_ZOOM_FACTOR)
		ACTION_ZOOM_IN:
			_zoom_live_preview(BUTTON_ZOOM_FACTOR)


func _zoom_live_preview(factor: float) -> void:
	_preview_distance = clampf(
			_preview_distance * factor,
			_preview_extent * 1.15,
			_preview_extent * 6.0)
	_update_live_preview_camera()


func _update_live_preview_camera() -> void:
	if not is_instance_valid(_live_camera):
		return
	_live_camera.position = Vector3(1.0, 0.65, 1.0).normalized() * _preview_distance
	_live_camera.look_at(Vector3.ZERO)


func _render_object_preview(pose_path: String, output_path: String) -> Error:
	var object_path := _read_object_path(pose_path)
	var packed := load(object_path) as PackedScene
	if packed == null:
		return ERR_CANT_OPEN
	var instance := packed.instantiate() as Node3D
	if instance == null:
		return ERR_INVALID_DATA
	instance.rotation_degrees += _read_thumbnail_rotation(pose_path)

	var viewport := SubViewport.new()
	viewport.size = Vector2i(384, 240)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport.own_world_3d = true
	editor.add_child(viewport)
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.018, 0.028, 0.042)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.55, 0.62, 0.72)
	environment.ambient_light_energy = 1.25
	var world_environment := WorldEnvironment.new()
	world_environment.environment = environment
	viewport.add_child(world_environment)
	viewport.add_child(instance)

	var bounds := _object_bounds(instance)
	if bounds.size.is_zero_approx():
		viewport.queue_free()
		return ERR_INVALID_DATA
	var target := bounds.get_center()
	var extent := maxf(bounds.size.x, maxf(bounds.size.y, bounds.size.z))
	var camera := Camera3D.new()
	camera.fov = 36.0
	camera.position = target + Vector3(1.0, 0.65, 1.0).normalized() \
			* extent * THUMBNAIL_DISTANCE_FACTOR
	viewport.add_child(camera)
	camera.look_at(target)
	camera.current = true
	var key_light := DirectionalLight3D.new()
	key_light.rotation_degrees = Vector3(-42.0, -32.0, 0.0)
	key_light.light_energy = 1.8
	viewport.add_child(key_light)
	var fill_light := OmniLight3D.new()
	fill_light.position = target + Vector3(-extent, extent, extent)
	fill_light.omni_range = extent * 5.0
	fill_light.light_energy = 2.2
	viewport.add_child(fill_light)

	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var image := viewport.get_texture().get_image()
	var result := image.save_png(ProjectSettings.globalize_path(output_path))
	viewport.queue_free()
	return result


func _read_object_path(pose_path: String) -> String:
	var file := FileAccess.open(pose_path, FileAccess.READ)
	if file == null:
		return ""
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if parsed is Dictionary:
		var data := parsed as Dictionary
		var attachments: Array = data.get("attachments", [])
		if not attachments.is_empty() and attachments[0] is Dictionary:
			return String((attachments[0] as Dictionary).get("object_scene", ""))
		return String(data.get("object_scene", ""))
	return ""


func _read_thumbnail_rotation(pose_path: String) -> Vector3:
	var file := FileAccess.open(pose_path, FileAccess.READ)
	if file == null:
		return Vector3.ZERO
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if not parsed is Dictionary:
		return Vector3.ZERO
	var values: Array = (parsed as Dictionary).get("thumbnail_rotation_degrees", [])
	if values.size() < 3:
		return Vector3.ZERO
	return Vector3(float(values[0]), float(values[1]), float(values[2]))


func _object_bounds(root: Node3D) -> AABB:
	var combined := AABB()
	var has_bounds := false
	var root_inverse := root.global_transform.affine_inverse()
	for node: Node in root.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := node as MeshInstance3D
		if mesh_instance.mesh == null:
			continue
		var relative_transform := root_inverse * mesh_instance.global_transform
		var bounds := relative_transform * mesh_instance.get_aabb()
		combined = combined.merge(bounds) if has_bounds else bounds
		has_bounds = true
	return combined


func _browse() -> void:
	editor._pose_io_handler._browse_preset_file()


func _add_pose(path: String) -> void:
	if path.is_empty() or not FileAccess.file_exists(path):
		return
	for entry: Dictionary in _entries:
		if entry["path"] == path:
			entry.merge(_read_pose_metadata(path), true)
			return
	var entry := _read_pose_metadata(path)
	entry["path"] = path
	_entries.append(entry)


func _read_pose_metadata(path: String) -> Dictionary:
	var result := {
		"name": path.get_file().get_basename().replace("_", " ").capitalize(),
		"object": "Unknown object",
		"animation": "",
	}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return result
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if parsed is Dictionary:
		var data := parsed as Dictionary
		var object_path := ""
		var attachments: Array = data.get("attachments", [])
		if not attachments.is_empty() and attachments[0] is Dictionary:
			object_path = String((attachments[0] as Dictionary).get("object_scene", ""))
		else:
			object_path = String(data.get("object_scene", ""))
		if not object_path.is_empty():
			result["object"] = object_path.get_file().get_basename().replace("_", " ").capitalize()
		result["animation"] = String(data.get("animation", ""))
	return result


func _load_persisted_paths() -> void:
	if not FileAccess.file_exists(LIBRARY_PATH):
		return
	var file := FileAccess.open(LIBRARY_PATH, FileAccess.READ)
	if file == null:
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if parsed is Array:
		for path: Variant in parsed:
			_add_pose(String(path))


func _save_paths() -> void:
	var paths: Array[String] = []
	for entry: Dictionary in _entries:
		paths.append(entry["path"])
	var file := FileAccess.open(LIBRARY_PATH, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(paths, "  ") + "\n")


func _preview_path(pose_path: String) -> String:
	return PREVIEW_DIRECTORY.path_join("%s.png" % pose_path.md5_text())


func _load_preview(pose_path: String) -> Texture2D:
	var user_preview := _preview_path(pose_path)
	if FileAccess.file_exists(user_preview):
		var image := Image.load_from_file(ProjectSettings.globalize_path(user_preview))
		if image != null and not image.is_empty():
			return ImageTexture.create_from_image(image)
	var builtin_preview := "res://assets/ui/pose_previews/%s.png" % pose_path.get_file().get_basename()
	if ResourceLoader.exists(builtin_preview):
		return load(builtin_preview) as Texture2D
	return null


func _has_preview(pose_path: String) -> bool:
	return _load_preview(pose_path) != null


func _generate_missing_previews() -> void:
	if _generating_previews:
		return
	_generating_previews = true
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(PREVIEW_DIRECTORY))
	for entry: Dictionary in _entries:
		var path: String = entry["path"]
		if _has_preview(path):
			continue
		if await _render_object_preview(path, _preview_path(path)) == OK:
			_update_cached_preview(path)
	_generating_previews = false


func _update_cached_preview(path: String) -> void:
	if _preview_textures.has(path) and is_instance_valid(_preview_textures[path]):
		_preview_textures[path].texture = _load_preview(path)


func _rebuild_grid(_unused_query: String = "") -> void:
	for child: Node in editor.pose_library_grid.get_children():
		child.free()
	_card_buttons.clear()
	_preview_textures.clear()
	var query := editor.pose_library_search.text.strip_edges().to_lower()
	var filtered: Array[Dictionary] = []
	for entry: Dictionary in _entries:
		var haystack := (String(entry["name"]) + " " + String(entry["object"])
				+ " " + String(entry["animation"])).to_lower()
		if query.is_empty() or query in haystack:
			filtered.append(entry)
	filtered.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return a["name"] < b["name"])
	for entry: Dictionary in filtered:
		_add_card(entry)
	_update_card_highlights()


func _add_card(entry: Dictionary) -> void:
	var card := Button.new()
	card.custom_minimum_size = Vector2(205.0, 176.0)
	card.tooltip_text = entry["path"]
	var path: String = entry["path"]
	card.pressed.connect(_select_card.bind(path))
	editor.pose_library_grid.add_child(card)
	_card_buttons[path] = card
	var content := VBoxContainer.new()
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	content.offset_left = 8.0
	content.offset_top = 8.0
	content.offset_right = -8.0
	content.offset_bottom = -8.0
	card.add_child(content)
	var preview := TextureRect.new()
	preview.custom_minimum_size.y = 112.0
	preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
	preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	preview.texture = _load_preview(path)
	content.add_child(preview)
	_preview_textures[path] = preview
	var title := Label.new()
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title.text = entry["name"]
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	content.add_child(title)
	var detail := Label.new()
	detail.mouse_filter = Control.MOUSE_FILTER_IGNORE
	detail.text = entry["object"]
	detail.modulate = Color(0.68, 0.76, 0.86)
	detail.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	detail.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	content.add_child(detail)


func _select_card(path: String) -> void:
	var entry := _find_entry(path)
	if entry.is_empty():
		return
	_selected_pose_path = path
	editor.pose_library_load_button.disabled = false
	editor.pose_library_preview_name.text = entry["name"]
	editor.pose_library_preview_details.text = "%s\n%s" % [entry["object"], entry["animation"]]
	_update_card_highlights()
	_show_live_preview(path)


func _update_card_highlights() -> void:
	for path: String in _card_buttons:
		_card_buttons[path].modulate = (
				Color(0.55, 0.78, 1.0) if path == _selected_pose_path else Color.WHITE)


func _entry_exists(path: String) -> bool:
	return not _find_entry(path).is_empty()


func _find_entry(path: String) -> Dictionary:
	for entry: Dictionary in _entries:
		if entry["path"] == path:
			return entry
	return {}


func _load_selected() -> void:
	if (_entry_exists(_selected_pose_path)
			and editor._pose_io_handler._load_pose_from_path(_selected_pose_path, true)):
		register_saved_pose(_selected_pose_path)
		close()
