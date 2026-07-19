class_name ObjectLibrary
extends Node3D
## Searchable 3D browser for reusable ObjectCatalog resources.

const MIN_ORBIT_DISTANCE := 0.5
const MAX_ORBIT_DISTANCE := 20.0
const ORBIT_SENSITIVITY := 0.008

@export var catalog: ObjectCatalog

var _visible_entries: Array[ObjectDefinition] = []
var _entry_buttons: Array[Button] = []
var _selected: ObjectDefinition
var _model: Node3D
var _orbiting := false
var _orbit_yaw := 0.55
var _orbit_pitch := 0.18
var _orbit_distance := 3.0
var _framed_distance := 3.0
var _orbit_target := Vector3(0, 0.5, 0)

@onready var camera: Camera3D = $Camera
@onready var model_anchor: Node3D = $ModelAnchor
@onready var platform: MeshInstance3D = $Platform
@onready var sidebar: PanelContainer = $UI/Sidebar
@onready var catalog_title: Label = $UI/Sidebar/Margin/VBox/Header/CatalogTitle
@onready var count_label: Label = $UI/Sidebar/Margin/VBox/Header/Count
@onready var search_field: LineEdit = $UI/Sidebar/Margin/VBox/Search
@onready var category_picker: OptionButton = $UI/Sidebar/Margin/VBox/FilterRow/Category
@onready var object_grid: GridContainer = $UI/Sidebar/Margin/VBox/ObjectScroll/ObjectGrid
@onready var object_name: Label = $UI/Details/Margin/VBox/ObjectName
@onready var object_category: Label = $UI/Details/Margin/VBox/Category
@onready var object_tags: Label = $UI/Details/Margin/VBox/Tags
@onready var object_path: Label = $UI/Details/Margin/VBox/Path
@onready var copy_path_button: Button = $UI/Details/Margin/VBox/CopyPath
@onready var zoom_out_button: Button = $UI/ViewportToolbar/Margin/Buttons/ZoomOut
@onready var zoom_in_button: Button = $UI/ViewportToolbar/Margin/Buttons/ZoomIn
@onready var reset_view_button: Button = $UI/ViewportToolbar/Margin/Buttons/ResetView


func _ready() -> void:
	camera.current = true
	search_field.text_changed.connect(_on_filter_changed)
	category_picker.item_selected.connect(_on_category_selected)
	copy_path_button.pressed.connect(_copy_selected_path)
	zoom_out_button.pressed.connect(_zoom.bind(1.2))
	zoom_in_button.pressed.connect(_zoom.bind(0.82))
	reset_view_button.pressed.connect(_reset_view)
	_setup_catalog()


func _setup_catalog() -> void:
	if catalog == null:
		catalog_title.text = "OBJECT LIBRARY"
		count_label.text = "0 OBJECTS"
		return
	catalog_title.text = catalog.display_name.to_upper()
	category_picker.clear()
	category_picker.add_item("All categories")
	category_picker.set_item_metadata(0, &"")
	for category in catalog.categories():
		category_picker.add_item(category)
		category_picker.set_item_metadata(category_picker.item_count - 1, StringName(category))
	_refresh_entries()


func _on_filter_changed(_text: String) -> void:
	_refresh_entries()


func _on_category_selected(_index: int) -> void:
	_refresh_entries()


func _refresh_entries() -> void:
	var category_filter := StringName(category_picker.get_selected_metadata())
	_visible_entries = catalog.filtered(search_field.text, category_filter)
	for child in object_grid.get_children():
		child.queue_free()
	_entry_buttons.clear()
	var selection_still_visible := _selected != null and _selected in _visible_entries
	var button_group := ButtonGroup.new()
	for entry in _visible_entries:
		var button := Button.new()
		button.custom_minimum_size = Vector2(154, 54)
		button.text = entry.display_name
		button.tooltip_text = ", ".join(entry.tags)
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.toggle_mode = true
		button.button_group = button_group
		button.pressed.connect(_select_entry.bind(entry))
		object_grid.add_child(button)
		_entry_buttons.append(button)
	count_label.text = "%d OBJECT%s" % [
		_visible_entries.size(), "" if _visible_entries.size() == 1 else "S"]
	if not selection_still_visible:
		_selected = null
		if not _visible_entries.is_empty():
			_select_entry(_visible_entries[0])
	else:
		_sync_button_selection()


func _select_entry(entry: ObjectDefinition) -> void:
	_selected = entry
	_sync_button_selection()
	_update_details()
	_load_preview()


func _sync_button_selection() -> void:
	for i in _entry_buttons.size():
		_entry_buttons[i].set_pressed_no_signal(
				i < _visible_entries.size() and _visible_entries[i] == _selected)


func _update_details() -> void:
	if _selected == null:
		object_name.text = "No object selected"
		object_category.text = ""
		object_tags.text = ""
		object_path.text = ""
		copy_path_button.disabled = true
		return
	object_name.text = _selected.display_name
	object_category.text = String(_selected.category).to_upper()
	object_tags.text = "  ".join(_selected.tags)
	object_path.text = _selected.scene.resource_path
	copy_path_button.disabled = false


func _load_preview() -> void:
	if _model != null:
		_model.free()
		_model = null
	if _selected == null or _selected.scene == null:
		return
	_model = _selected.scene.instantiate() as Node3D
	if _model == null:
		return
	model_anchor.add_child(_model)
	_model.scale = Vector3.ONE * _selected.preview_scale
	_model.rotation_degrees = _selected.preview_rotation_degrees
	_model.position = _selected.preview_offset
	_frame_model()


func _frame_model() -> void:
	var bounds := _calculate_bounds()
	if bounds.size.is_zero_approx():
		return
	var center := bounds.get_center()
	_model.position += Vector3(-center.x, -bounds.position.y, -center.z)
	var diameter := maxf(bounds.size.x, maxf(bounds.size.y, bounds.size.z))
	_orbit_target = Vector3(0, maxf(bounds.size.y * 0.5, 0.15), 0)
	_framed_distance = clampf(diameter * 1.75, MIN_ORBIT_DISTANCE, MAX_ORBIT_DISTANCE)
	_orbit_distance = _framed_distance
	var platform_radius := clampf(maxf(bounds.size.x, bounds.size.z) * 0.7, 0.45, 3.0)
	platform.scale = Vector3(platform_radius, 1.0, platform_radius)
	_reset_view()


func _calculate_bounds() -> AABB:
	var result := AABB()
	var has_bounds := false
	for child in _model.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := child as MeshInstance3D
		if mesh_instance.mesh == null:
			continue
		var relative_transform := (
				model_anchor.global_transform.affine_inverse() * mesh_instance.global_transform)
		var mesh_bounds: AABB = relative_transform * mesh_instance.get_aabb()
		result = result.merge(mesh_bounds) if has_bounds else mesh_bounds
		has_bounds = true
	return result


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mouse_button := event as InputEventMouseButton
		if mouse_button.position.x <= sidebar.size.x:
			return
		if mouse_button.button_index == MOUSE_BUTTON_WHEEL_UP and mouse_button.pressed:
			_zoom(0.88)
		elif mouse_button.button_index == MOUSE_BUTTON_WHEEL_DOWN and mouse_button.pressed:
			_zoom(1.14)
		elif mouse_button.button_index == MOUSE_BUTTON_LEFT:
			_orbiting = mouse_button.pressed
	elif event is InputEventMouseMotion and _orbiting:
		var motion := event as InputEventMouseMotion
		_orbit_yaw -= motion.relative.x * ORBIT_SENSITIVITY
		_orbit_pitch = clampf(
				_orbit_pitch - motion.relative.y * ORBIT_SENSITIVITY, -1.2, 1.2)
		_update_camera()


func _zoom(factor: float) -> void:
	_orbit_distance = clampf(
			_orbit_distance * factor, MIN_ORBIT_DISTANCE, MAX_ORBIT_DISTANCE)
	_update_camera()


func _reset_view() -> void:
	_orbit_yaw = 0.55
	_orbit_pitch = 0.18
	_orbit_distance = _framed_distance
	_update_camera()


func _update_camera() -> void:
	var horizontal := cos(_orbit_pitch)
	var direction := Vector3(
			sin(_orbit_yaw) * horizontal,
			sin(_orbit_pitch),
			cos(_orbit_yaw) * horizontal)
	camera.global_position = _orbit_target + direction * _orbit_distance
	camera.look_at(_orbit_target)


func _copy_selected_path() -> void:
	if _selected != null and _selected.scene != null:
		DisplayServer.clipboard_set(_selected.scene.resource_path)
		copy_path_button.text = "PATH COPIED"
		get_tree().create_timer(1.0).timeout.connect(
				func() -> void: copy_path_button.text = "COPY RESOURCE PATH")
