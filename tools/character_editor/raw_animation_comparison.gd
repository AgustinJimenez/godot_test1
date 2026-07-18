extends RefCounted
class_name RawAnimationComparison
## Owns the raw UAL reference shown beside the editable MotusMan target.

const TARGET_EDIT_POSITION := Vector3(0.0, 0.1, 0.0)
const TARGET_COMPARE_POSITION := Vector3(-0.35, 0.1, 0.0)
const RAW_COMPARE_POSITION := Vector3(0.65, 0.0, 0.0)
const SWIM_PREVIEW_HEIGHT := 1.35

var enabled := false
var has_raw_reference := false

var _target: PlayerBody
var _target_label: Label3D
var _raw_source_ual1: Node3D
var _raw_source_ual2: Node3D
var _raw_source: Node3D
var _raw_animation_player: AnimationPlayer
var _preview_height := 0.0


func setup(target: PlayerBody, target_label: Label3D,
		raw_source_ual1: Node3D, raw_source_ual2: Node3D) -> void:
	_target = target
	_target_label = target_label
	_raw_source_ual1 = raw_source_ual1
	_raw_source_ual2 = raw_source_ual2
	_align_reference_facing(_raw_source_ual1)
	_align_reference_facing(_raw_source_ual2)
	_hide_references()
	_target_label.hide()


func set_enabled(value: bool, animation_name: StringName) -> String:
	enabled = value
	if not enabled:
		has_raw_reference = false
		_hide_references()
		_target.position = TARGET_EDIT_POSITION
		_target_label.hide()
		_set_preview_height(0.0)
		return "Edit mode"
	_target_label.show()
	return play_animation(animation_name)


func play_animation(target_clip: StringName) -> String:
	if not enabled:
		return ""
	var raw_clip_name := _target.get_animation_source_clip(target_clip)
	var source_pack := _target.get_animation_source_pack(target_clip)
	_preview_height = (SWIM_PREVIEW_HEIGHT
			if String(raw_clip_name).begins_with("Swim_") else 0.0)
	_set_preview_height(_preview_height)
	if not _activate_raw_source(source_pack):
		has_raw_reference = false
		_target.position.x = 0.0
		_target_label.text = "MOTUSMAN - NO RAW SOURCE"
		return "No raw source reference for %s" % target_clip
	has_raw_reference = true
	_target.position.x = TARGET_COMPARE_POSITION.x
	_target_label.text = "RETARGETED - MOTUSMAN"
	for library_name in _raw_animation_player.get_animation_library_list():
		var library := _raw_animation_player.get_animation_library(library_name)
		if not library.has_animation(raw_clip_name):
			continue
		var full_name := (String(library_name) + "/" + String(raw_clip_name)
				if library_name != &"" else String(raw_clip_name))
		_raw_animation_player.play(full_name)
		return "Comparing %s with raw %s" % [target_clip, raw_clip_name]
	_hide_references()
	has_raw_reference = false
	_target.position.x = 0.0
	_target_label.text = "MOTUSMAN - RAW CLIP MISSING"
	return "Raw animation not found: %s" % raw_clip_name


func set_paused(paused: bool) -> void:
	if _raw_animation_player == null or not has_raw_reference:
		return
	if paused:
		_raw_animation_player.pause()
	else:
		_raw_animation_player.play()


func seek(time: float) -> void:
	if _raw_animation_player != null and has_raw_reference:
		_raw_animation_player.seek(time, true)


func get_frame_target() -> Vector3:
	var center_x := (TARGET_COMPARE_POSITION.x + RAW_COMPARE_POSITION.x) * 0.5
	var center_y := _preview_height if _preview_height > 0.0 else 1.05
	return Vector3(center_x if has_raw_reference else 0.0,
			center_y, 0.0)


func _activate_raw_source(source_pack: StringName) -> bool:
	_hide_references()
	if source_pack == &"ual1":
		_raw_source = _raw_source_ual1
	elif source_pack == &"ual2":
		_raw_source = _raw_source_ual2
	else:
		if _raw_animation_player != null:
			_raw_animation_player.stop()
		return false
	_raw_source.show()
	_raw_animation_player = _raw_source.find_child(
			"AnimationPlayer", true, false) as AnimationPlayer
	return _raw_animation_player != null


func _hide_references() -> void:
	_raw_source_ual1.hide()
	_raw_source_ual2.hide()


func _set_preview_height(height: float) -> void:
	_target.position.y = TARGET_EDIT_POSITION.y + height
	_raw_source_ual1.position = RAW_COMPARE_POSITION + Vector3.UP * height
	_raw_source_ual2.position = RAW_COMPARE_POSITION + Vector3.UP * height
	_target_label.position.y = 2.15 - height
	(_raw_source_ual1.get_node("Label") as Label3D).position.y = 2.15 - height
	(_raw_source_ual2.get_node("Label") as Label3D).position.y = 2.15 - height


func _align_reference_facing(source: Node3D) -> void:
	var source_skeleton := source.find_child("Skeleton3D", true, false) as Skeleton3D
	var target_facing := _rest_body_facing(
			_target.skeleton, &"Hips", &"Head", &"LeftShoulder", &"RightShoulder")
	var source_facing := _rest_body_facing(
			source_skeleton, &"pelvis", &"Head", &"clavicle_l", &"clavicle_r")
	if target_facing.is_zero_approx() or source_facing.is_zero_approx():
		return
	source.rotate_y(source_facing.signed_angle_to(target_facing, Vector3.UP))


func _rest_body_facing(skeleton: Skeleton3D, hips: StringName, head: StringName,
		left_shoulder: StringName, right_shoulder: StringName) -> Vector3:
	var hips_position := skeleton.get_bone_global_rest(skeleton.find_bone(hips)).origin
	var head_position := skeleton.get_bone_global_rest(skeleton.find_bone(head)).origin
	var left_position := skeleton.get_bone_global_rest(
			skeleton.find_bone(left_shoulder)).origin
	var right_position := skeleton.get_bone_global_rest(
			skeleton.find_bone(right_shoulder)).origin
	var right := (right_position - left_position).normalized()
	var up := (head_position - hips_position).normalized()
	var facing := right.cross(up)
	facing.y = 0.0
	return facing.normalized() if facing.length_squared() > 0.0001 else Vector3.ZERO
