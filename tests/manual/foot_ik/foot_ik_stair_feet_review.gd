extends Node3D
## Manual review harness: a real Player auto-walks the 0.35m stair (reusing
## foot_ik_preview.tscn's own "stair_walk_marker" auto-walk loop) in slow
## motion, while the only thing you control is an orbit camera locked onto
## the feet - left-drag to orbit horizontal/vertical, scroll to zoom.
## Launch: godot --path . res://tests/manual/foot_ik/foot_ik_stair_feet_review.tscn

const PREVIEW_SCENE := preload("res://tests/manual/foot_ik/foot_ik_preview.tscn")
## Kept moderate (not the 0.05-0.2 extremes tried earlier), which amplified
## velocity-based noise into false swing/contact-lost readings and made the
## legacy mode look worse than it actually is - see CURRENT_TASK_IK_FOOT.md.
const TIME_SCALE := 0.4
const ORBIT_DISTANCE_DEFAULT := 1.4
const ORBIT_DISTANCE_MIN := 0.4
const ORBIT_DISTANCE_MAX := 4.0
const ORBIT_SENSITIVITY := 0.006 # radians per pixel of drag
const ORBIT_PITCH_LIMIT := 1.4 # radians, short of the poles
const ZOOM_STEP := 0.15

var _player: Player
var _modifier: PlayerFootIKModifier
var _camera: Camera3D
var _orbit_yaw := 0.0
var _orbit_pitch := 0.3
var _orbit_distance := ORBIT_DISTANCE_DEFAULT
var _dragging := false
var _foot_target := Vector3.ZERO
var _hint_label: Label


func _ready() -> void:
	Engine.time_scale = TIME_SCALE
	FileAccess.open("user://foot_ik_stair_walk_marker", FileAccess.WRITE).close()
	var preview: Node3D = PREVIEW_SCENE.instantiate()
	add_child(preview)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE # undo Player._ready()'s own capture
	_player = preview.get_node(^"Player") as Player
	_player.debug_cam.current = false
	_player.hud.visible = false
	_modifier = _find_foot_ik_modifier()
	_camera = Camera3D.new()
	add_child(_camera)
	_camera.current = true
	_build_hint_label()
	_update_foot_target()
	_update_camera()


func _exit_tree() -> void:
	Engine.time_scale = 1.0
	# Don't leak the marker into a later plain foot_ik_preview.tscn launch.
	DirAccess.remove_absolute("user://foot_ik_stair_walk_marker")


func _find_foot_ik_modifier() -> PlayerFootIKModifier:
	for child in _player.skeleton.get_children():
		if child is PlayerFootIKModifier:
			return child
	return null


func _build_hint_label() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	_hint_label = Label.new()
	_hint_label.position = Vector2(16, 16)
	layer.add_child(_hint_label)
	_update_hint_label()


func _update_hint_label() -> void:
	var mode_name := "LEGACY" if _modifier.locomotion_mode \
			== PlayerFootIKModifier.LocomotionMode.LEGACY else "RESIDUAL_STAIR"
	_hint_label.text = ("Left-drag: orbit camera around the feet | Scroll: zoom | "
			+ "Tab: switch locomotion mode (current: %s) | %d%% speed"
			% [mode_name, roundi(TIME_SCALE * 100.0)])


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			_dragging = mb.pressed
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			_orbit_distance = clampf(
					_orbit_distance - ZOOM_STEP, ORBIT_DISTANCE_MIN, ORBIT_DISTANCE_MAX)
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_orbit_distance = clampf(
					_orbit_distance + ZOOM_STEP, ORBIT_DISTANCE_MIN, ORBIT_DISTANCE_MAX)
	elif event is InputEventMouseMotion and _dragging:
		var motion := (event as InputEventMouseMotion).relative
		_orbit_yaw -= motion.x * ORBIT_SENSITIVITY
		_orbit_pitch = clampf(
				_orbit_pitch - motion.y * ORBIT_SENSITIVITY, -ORBIT_PITCH_LIMIT, ORBIT_PITCH_LIMIT)
	elif event is InputEventKey and event.pressed and not event.echo \
			and (event as InputEventKey).keycode == KEY_TAB:
		_modifier.locomotion_mode = (
				PlayerFootIKModifier.LocomotionMode.RESIDUAL_STAIR
				if _modifier.locomotion_mode == PlayerFootIKModifier.LocomotionMode.LEGACY
				else PlayerFootIKModifier.LocomotionMode.LEGACY)
		_update_hint_label()


func _process(_delta: float) -> void:
	_update_foot_target()
	_update_camera()


## Tracks the rendered (post-IK) sole midpoint, not the pre-IK animated pose,
## so the camera frames what actually gets drawn.
func _update_foot_target() -> void:
	if _player == null or _modifier == null:
		return
	var skel := _player.skeleton
	var left_idx := skel.find_bone(_player.body.resolve_bone_name(&"LeftFoot"))
	var right_idx := skel.find_bone(_player.body.resolve_bone_name(&"RightFoot"))
	if left_idx < 0 or right_idx < 0:
		return
	var to_world := skel.global_transform
	var left_pos := to_world * _modifier.get_final_bone_global_pose(left_idx).origin
	var right_pos := to_world * _modifier.get_final_bone_global_pose(right_idx).origin
	_foot_target = (left_pos + right_pos) * 0.5


func _update_camera() -> void:
	var horizontal := cos(_orbit_pitch)
	var direction := Vector3(
			sin(_orbit_yaw) * horizontal, sin(_orbit_pitch), cos(_orbit_yaw) * horizontal)
	_camera.global_position = _foot_target + direction * _orbit_distance
	_camera.look_at(_foot_target, Vector3.UP)
