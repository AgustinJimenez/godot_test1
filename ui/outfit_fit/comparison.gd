class_name OutfitFitComparison
extends RefCounted
## Owns the read-only imported-mesh copy used for original/result inspection.

var enabled := false

var _root: Node3D
var _owner: Node
var _fitted_label: Label3D
var _original_label: Label3D
var _compare_button: CheckButton
var _isolate_button: CheckButton
var _debug_button: CheckButton
var _control_points_button: CheckButton
var _editor: OutfitFitEditor
var _body_mesh_name: Callable
var _apply_body_material: Callable
var _apply_outfit_materials: Callable
var _sync_isolation: Callable
var _update_camera: Callable
var _set_debug_colors: Callable
var _spacing := 0.0
var _distance_bonus := 0.0
var _minimum_distance := 0.0
var _maximum_distance := 0.0
var _debug_was_enabled := false
var _points_were_visible := false
var _body: Node3D
var _outfit: Node3D


func setup(
	owner: Node,
	editor: OutfitFitEditor,
	spacing: float,
	distance_bonus: float,
	minimum_distance: float,
	maximum_distance: float,
) -> void:
	_owner = owner
	_root = owner.get_node("ComparisonRoot")
	_fitted_label = owner.get_node("PreviewRoot/FittedLabel")
	_original_label = owner.get_node("ComparisonRoot/OriginalLabel")
	_compare_button = owner.get_node("UI/FitPanel/Margin/VBox/CompareOriginal")
	_isolate_button = owner.get_node("UI/FitPanel/Margin/VBox/IsolateSelected")
	_debug_button = owner.get_node("UI/Panel/Margin/VBox/OutfitRow/DebugColors")
	_control_points_button = owner.get_node(
			"UI/FitPanel/Margin/VBox/ShowControlPoints")
	_editor = editor
	_body_mesh_name = Callable(owner, "_comparison_body_mesh_name")
	_apply_body_material = Callable(owner, "_apply_body_debug_material")
	_apply_outfit_materials = Callable(owner, "_apply_outfit_materials")
	_sync_isolation = Callable(owner, "_sync_fit_isolation_control")
	_update_camera = Callable(owner, "_update_orbit_camera")
	_set_debug_colors = Callable(owner, "_on_outfit_debug_colors_toggled")
	_spacing = spacing
	_distance_bonus = distance_bonus
	_minimum_distance = minimum_distance
	_maximum_distance = maximum_distance


func toggle(value: bool) -> void:
	if value and not _editor.has_outfit():
		_compare_button.set_pressed_no_signal(false)
		return
	if value and _editor._isolate_selected:
		_isolate_button.set_pressed_no_signal(false)
		_editor._set_isolate_selected(false)
	if enabled == value:
		if value:
			rebuild()
		return
	enabled = value
	_fitted_label.visible = value
	_original_label.visible = value
	_set_clean_inspection(value)
	var orbit_target := _owner.get("_orbit_target") as Vector3
	var orbit_distance := float(_owner.get("_orbit_distance"))
	if value:
		_root.position = Vector3(-_spacing, 0, 0)
		orbit_target.x -= _spacing * 0.5
		orbit_distance = minf(orbit_distance + _distance_bonus, _maximum_distance)
		rebuild()
	else:
		clear()
		orbit_target.x += _spacing * 0.5
		orbit_distance = maxf(orbit_distance - _distance_bonus, _minimum_distance)
	_owner.set("_orbit_target", orbit_target)
	_owner.set("_orbit_distance", orbit_distance)
	_sync_isolation.call()
	_update_camera.call()


func _set_clean_inspection(value: bool) -> void:
	if value:
		_debug_was_enabled = _debug_button.button_pressed
		_points_were_visible = _control_points_button.button_pressed
		_debug_button.set_pressed_no_signal(false)
		_control_points_button.set_pressed_no_signal(false)
		_set_debug_colors.call(false)
		_editor.set_control_points_visible(false)
	else:
		_debug_button.set_pressed_no_signal(_debug_was_enabled)
		_control_points_button.set_pressed_no_signal(_points_were_visible)
		_set_debug_colors.call(_debug_was_enabled)
		_editor.set_control_points_visible(_points_were_visible)
	_debug_button.disabled = value
	_control_points_button.disabled = value


func rebuild() -> void:
	if not enabled:
		return
	clear()
	var preview_body := _owner.get("_preview_body") as Node3D
	if not is_instance_valid(preview_body) or not _editor.has_outfit():
		return
	var body_mesh_name := String(_body_mesh_name.call())
	_body = preview_body.duplicate() as Node3D
	if _body != null:
		_root.add_child(_body)
		var base_mesh := _body.find_child(
				body_mesh_name, true, false) as MeshInstance3D
		if base_mesh != null and _editor._get_original_body_mesh() != null:
			base_mesh.mesh = _editor._get_original_body_mesh()
			_apply_body_material.call(base_mesh)
	_outfit = _editor._create_original_outfit_preview()
	if _outfit != null:
		_root.add_child(_outfit)
		_apply_outfit_materials.call(_outfit)


func clear() -> void:
	if is_instance_valid(_outfit):
		_outfit.free()
	if is_instance_valid(_body):
		_body.free()
	_outfit = null
	_body = null


func refresh_materials() -> void:
	if not enabled:
		return
	var body_mesh_name := String(_body_mesh_name.call())
	if is_instance_valid(_body):
		var base_mesh := _body.find_child(
				body_mesh_name, true, false) as MeshInstance3D
		if base_mesh != null:
			_apply_body_material.call(base_mesh)
	if is_instance_valid(_outfit):
		_apply_outfit_materials.call(_outfit)
