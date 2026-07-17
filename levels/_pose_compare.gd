extends Node3D
## Live retarget comparison: the gameplay MotusMan implementation beside the
## untouched UAL source model. Pick a clip from the menu to play it on both.
## Click empty viewport space to capture the mouse; Esc releases it. While
## captured, use WASD to move, Q/E to descend/ascend, and Shift to move faster.
## Retained as the manual acceptance harness while hand/contact differences
## between the source and target meshes remain under investigation.

const DEFAULT_CLIP := &"Pistol_Aim_Down"
const MOVE_SPEED := 3.5
const FAST_MULTIPLIER := 3.0
const LOOK_SENS := 0.003
const SWIM_PREVIEW_HEIGHT := 1.35

@onready var camera: Camera3D = $DemoCamera
@onready var implementation: PlayerBody = $Implementation
@onready var raw_source: Node3D = $RawSource
@onready var animation_picker: OptionButton = $UI/MenuMargin/MenuPanel/MenuPadding/MenuVBox/AnimationPicker

var _raw_animation_player: AnimationPlayer
var _clip_names: Array[StringName] = []
var _captured := false
var _yaw := 0.0
var _pitch := 0.0


func _ready() -> void:
	camera.current = true
	_raw_animation_player = raw_source.find_child("AnimationPlayer", true, false) as AnimationPlayer
	_align_reference_facing()
	_build_animation_picker()
	animation_picker.item_selected.connect(_on_animation_selected)
	var initial_clip := DEFAULT_CLIP
	var user_args := OS.get_cmdline_user_args()
	if not user_args.is_empty() and StringName(user_args[0]) in _clip_names:
		initial_clip = StringName(user_args[0])
	_select_and_play(initial_clip)


## The rigs' rest silhouettes face about 7 degrees apart even with identity
## model transforms. Keep MotusMan in its real gameplay orientation and yaw
## only the raw reference so an oblique free-camera view compares animation
## rotation rather than that asset-authoring offset.
func _align_reference_facing() -> void:
	var source_skeleton := raw_source.find_child("Skeleton3D", true, false) as Skeleton3D
	var target_facing := _rest_body_facing(
			implementation.skeleton, &"Hips", &"Head", &"LeftShoulder", &"RightShoulder")
	var source_facing := _rest_body_facing(
			source_skeleton, &"pelvis", &"Head", &"clavicle_l", &"clavicle_r")
	if target_facing.is_zero_approx() or source_facing.is_zero_approx():
		return
	raw_source.rotate_y(source_facing.signed_angle_to(target_facing, Vector3.UP))
	var aligned_source_facing := raw_source.basis * source_facing
	print("COMPARE: rest-facing alignment error deg=",
			rad_to_deg(target_facing.angle_to(aligned_source_facing)))


func _rest_body_facing(skeleton: Skeleton3D, hips: StringName, head: StringName,
		left_shoulder: StringName, right_shoulder: StringName) -> Vector3:
	var hips_position := skeleton.get_bone_global_rest(skeleton.find_bone(hips)).origin
	var head_position := skeleton.get_bone_global_rest(skeleton.find_bone(head)).origin
	var left_position := skeleton.get_bone_global_rest(skeleton.find_bone(left_shoulder)).origin
	var right_position := skeleton.get_bone_global_rest(skeleton.find_bone(right_shoulder)).origin
	var right := (right_position - left_position).normalized()
	var up := (head_position - hips_position).normalized()
	var facing := right.cross(up)
	facing.y = 0.0
	return facing.normalized() if facing.length_squared() > 0.0001 else Vector3.ZERO


func _build_animation_picker() -> void:
	_clip_names.append(&"Walk")
	var groups := implementation.get_animation_groups()
	for clip_name: StringName in groups[&"Universal Animation Library"]:
		_clip_names.append(clip_name)
	_clip_names.sort()
	for clip_name in _clip_names:
		animation_picker.add_item(String(clip_name))
		animation_picker.set_item_metadata(animation_picker.item_count - 1, clip_name)


func _select_and_play(clip_name: StringName) -> void:
	var index := _clip_names.find(clip_name)
	if index < 0:
		return
	animation_picker.select(index)
	_play_clip(clip_name)


func _on_animation_selected(index: int) -> void:
	_play_clip(StringName(animation_picker.get_item_metadata(index)))


func _play_clip(raw_clip_name: StringName) -> void:
	_set_preview_height(SWIM_PREVIEW_HEIGHT if String(raw_clip_name).begins_with("Swim_") else 0.0)
	var target_clip := &"unarmed_walk" if raw_clip_name == &"Walk" else raw_clip_name
	implementation.play_debug_anim(target_clip, 0.0)
	for library_name in _raw_animation_player.get_animation_library_list():
		var library := _raw_animation_player.get_animation_library(library_name)
		if library.has_animation(raw_clip_name):
			var source_animation := library.get_animation(raw_clip_name)
			var full_name := (String(library_name) + "/" + String(raw_clip_name)
					if library_name != &"" else String(raw_clip_name))
			_raw_animation_player.play(full_name)
			var target_animation := implementation.anim_player.get_animation("moves/" + target_clip)
			print("COMPARE: playing ", raw_clip_name, " source_loop=", source_animation.loop_mode,
					" target_loop=", target_animation.loop_mode)
			return
	push_warning("Raw UAL animation not found: " + raw_clip_name)


func _set_preview_height(height: float) -> void:
	implementation.position.y = 0.1 + height
	raw_source.position.y = height
	# Labels stay at their normal world height while only the models lift.
	implementation.get_node("Label").position.y = 2.15 - height
	raw_source.get_node("Label").position.y = 2.15 - height


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"ui_cancel"):
		_captured = false
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif event is InputEventMouseButton and event.pressed and not _captured:
		_captured = true
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	elif event is InputEventMouseMotion and _captured:
		_yaw -= event.relative.x * LOOK_SENS
		_pitch = clampf(_pitch - event.relative.y * LOOK_SENS, -1.55, 1.55)
		camera.rotation = Vector3(_pitch, _yaw, 0.0)


func _process(delta: float) -> void:
	if not _captured:
		return
	var movement := Vector3.ZERO
	if Input.is_key_pressed(KEY_W):
		movement -= camera.global_transform.basis.z
	if Input.is_key_pressed(KEY_S):
		movement += camera.global_transform.basis.z
	if Input.is_key_pressed(KEY_A):
		movement -= camera.global_transform.basis.x
	if Input.is_key_pressed(KEY_D):
		movement += camera.global_transform.basis.x
	if Input.is_key_pressed(KEY_E):
		movement += Vector3.UP
	if Input.is_key_pressed(KEY_Q):
		movement -= Vector3.UP
	if movement.is_zero_approx():
		return
	var speed := MOVE_SPEED * (FAST_MULTIPLIER if Input.is_key_pressed(KEY_SHIFT) else 1.0)
	camera.global_position += movement.normalized() * speed * delta
