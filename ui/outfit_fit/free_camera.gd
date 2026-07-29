class_name OutfitFitFreeCamera
extends RefCounted
## Keeps Character Creator's orbit camera and optional captured-mouse inspection mode together.

const MOVE_SPEED := 2.0
const FAST_MOVE_MULTIPLIER := 3.0
const MAX_FREE_PITCH := deg_to_rad(89.0)

var enabled := false

var _owner: Node3D
var _camera: Camera3D
var _editor: OutfitFitEditor
var _button: CheckButton
var _comparison_enabled: Callable
var _orbit_sensitivity := 0.0
var _zoom_step := 0.0
var _minimum_distance := 0.0
var _maximum_distance := 0.0
var _face_target := Vector3.ZERO
var _face_distance := 0.0
var _default_target := Vector3.ZERO
var _default_distance := 0.0
var _comparison_spacing := 0.0
var _comparison_distance_bonus := 0.0
var _orbiting := false
var _free_yaw := 0.0
var _free_pitch := 0.0


func setup(
	owner: Node3D,
	camera: Camera3D,
	editor: OutfitFitEditor,
	comparison_enabled: Callable,
	config: Dictionary,
) -> void:
	_owner = owner
	_camera = camera
	_editor = editor
	_button = owner.get_node("UI/FitPanel/Margin/VBox/FreeCamera")
	_comparison_enabled = comparison_enabled
	_orbit_sensitivity = config["orbit_sensitivity"]
	_zoom_step = config["zoom_step"]
	_minimum_distance = config["minimum_distance"]
	_maximum_distance = config["maximum_distance"]
	_face_target = config["face_target"]
	_face_distance = config["face_distance"]
	_default_target = config["default_target"]
	_default_distance = config["default_distance"]
	_comparison_spacing = config["comparison_spacing"]
	_comparison_distance_bonus = config["comparison_distance_bonus"]


func toggle(value: bool) -> void:
	if enabled == value:
		return
	enabled = value
	_orbiting = false
	_kill_camera_tween()
	if value:
		_free_pitch = _camera.global_rotation.x
		_free_yaw = _camera.global_rotation.y
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	else:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		update_orbit_camera()


func release() -> void:
	if not enabled:
		return
	_button.set_pressed_no_signal(false)
	toggle(false)


func process(delta: float) -> void:
	if not enabled:
		return
	var planar := Input.get_vector(
			&"move_left", &"move_right", &"move_forward", &"move_back")
	var movement := Vector3(
			planar.x,
			Input.get_axis(&"free_camera_down", &"free_camera_up"),
			planar.y)
	if movement.is_zero_approx():
		return
	var speed := MOVE_SPEED
	if Input.is_action_pressed(&"sprint"):
		speed *= FAST_MOVE_MULTIPLIER
	var direction := (
			_camera.global_basis.x * movement.x
			+ -_camera.global_basis.z * -movement.z
			+ Vector3.UP * movement.y)
	_camera.global_position += direction.normalized() * speed * delta


func handle_input(event: InputEvent) -> bool:
	if enabled:
		return _handle_free_input(event)
	if event is InputEventMouseButton:
		var button_event := event as InputEventMouseButton
		if button_event.button_index == MOUSE_BUTTON_LEFT:
			if button_event.pressed and _editor.pick(button_event.position):
				_orbiting = false
				_owner.get_viewport().set_input_as_handled()
			else:
				_orbiting = button_event.pressed
		elif button_event.pressed and button_event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_set_orbit_distance(_orbit_distance() - _zoom_step)
			update_orbit_camera()
		elif button_event.pressed and button_event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_set_orbit_distance(_orbit_distance() + _zoom_step)
			update_orbit_camera()
	elif event is InputEventMagnifyGesture:
		var magnify_event := event as InputEventMagnifyGesture
		_set_orbit_distance(_orbit_distance() / maxf(magnify_event.factor, 0.01))
		update_orbit_camera()
		_owner.get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion and _orbiting:
		var motion := event as InputEventMouseMotion
		_owner.set("_orbit_yaw", float(_owner.get("_orbit_yaw")) -
				motion.relative.x * _orbit_sensitivity)
		_owner.set("_orbit_pitch", clampf(
				float(_owner.get("_orbit_pitch")) + motion.relative.y * _orbit_sensitivity,
				-deg_to_rad(60.0),
				deg_to_rad(60.0)))
		update_orbit_camera()
	elif event.is_action_pressed(&"debug_menu") and not _is_echo(event):
		toggle_face_focus()
	return false


func update_orbit_camera() -> void:
	if enabled:
		return
	_kill_camera_tween()
	var pitch := float(_owner.get("_orbit_pitch"))
	var yaw := float(_owner.get("_orbit_yaw"))
	var horizontal := cos(pitch)
	var direction := Vector3(sin(yaw) * horizontal, sin(pitch), cos(yaw) * horizontal)
	_camera.global_position = (_owner.get("_orbit_target") as Vector3) + (
			direction * _orbit_distance())
	_camera.look_at(_owner.get("_orbit_target") as Vector3)


func toggle_face_focus() -> void:
	var face_focused := not bool(_owner.get("_face_focused"))
	_owner.set("_face_focused", face_focused)
	var target := _face_target if face_focused else _default_target
	var distance := _face_distance if face_focused else _default_distance
	if bool(_comparison_enabled.call()):
		target.x -= _comparison_spacing * 0.5
		distance += _comparison_distance_bonus
	_owner.set("_orbit_target", target)
	_owner.set("_orbit_distance", distance)
	update_orbit_camera()


func _handle_free_input(event: InputEvent) -> bool:
	if event is InputEventMouseMotion:
		var motion := event as InputEventMouseMotion
		_free_yaw -= motion.relative.x * _orbit_sensitivity
		_free_pitch = clampf(
				_free_pitch - motion.relative.y * _orbit_sensitivity,
				-MAX_FREE_PITCH,
				MAX_FREE_PITCH)
		_camera.global_rotation = Vector3(_free_pitch, _free_yaw, 0.0)
		_owner.get_viewport().set_input_as_handled()
		return true
	if event.is_action_pressed(&"ui_cancel") and not _is_echo(event):
		release()
		_owner.get_viewport().set_input_as_handled()
		return true
	if event is InputEventMouseButton or event is InputEventMagnifyGesture:
		_owner.get_viewport().set_input_as_handled()
		return true
	return false


func _is_echo(event: InputEvent) -> bool:
	return event is InputEventKey and (event as InputEventKey).echo


func _set_orbit_distance(value: float) -> void:
	_owner.set("_orbit_distance", clampf(value, _minimum_distance, _maximum_distance))


func _orbit_distance() -> float:
	return float(_owner.get("_orbit_distance"))


func _kill_camera_tween() -> void:
	var tween := _owner.get("_camera_tween") as Tween
	if is_instance_valid(tween):
		tween.kill()
	_owner.set("_camera_tween", null)
