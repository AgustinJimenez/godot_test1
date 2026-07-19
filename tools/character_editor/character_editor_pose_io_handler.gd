class_name CharacterEditorPoseIoHandler
extends RefCounted

## Pose/object file I/O: save/load/new-preset, object browsing, pose-data
## serialization, screenshot capture. Holds a back-reference to the main
## CharacterEditor - extracted purely to keep character_editor.gd under
## a manageable size.

var editor: CharacterEditor


func _init(editor_ref: CharacterEditor) -> void:
	editor = editor_ref


func _on_copy_pressed() -> void:
	DisplayServer.clipboard_set(JSON.stringify(_get_pose_data(), "  "))
	editor.status_label.text = "Values copied to clipboard"


func _get_pose_data() -> Dictionary:
	return {
		"format_version": 2,
		"animation": String(editor._current_animation),
		"object_scene": editor._current_object_path,
		"attachment_bone": String(editor._attachment_bone),
		"bone_rotations_degrees": editor._modifier.get_serializable_values(),
		"object_position": _vector3_to_array(editor._held_object.position),
		"object_rotation_degrees": _vector3_to_array(editor._held_object.rotation_degrees),
		"object_scale": editor._held_object.scale.x,
		# Compatibility fields used by PlayerBody's flashlight loader.
		"hand": String(editor._attachment_bone),
		"flashlight_position": [
			editor._held_object.position.x,
			editor._held_object.position.y,
			editor._held_object.position.z,
		],
		"flashlight_rotation_degrees": [
			editor._held_object.rotation_degrees.x,
			editor._held_object.rotation_degrees.y,
			editor._held_object.rotation_degrees.z,
		],
	}


func _vector3_to_array(value: Vector3) -> Array[float]:
	return [value.x, value.y, value.z]


func _on_save_pose_pressed() -> void:
	if editor._current_pose_path.is_empty():
		_on_save_preset_as_pressed()
		return
	_save_pose_to_path(editor._current_pose_path)


func _save_pose_to_path(path: String) -> bool:
	if path.is_empty():
		return false
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		editor.status_label.text = "Could not save pose: %s" % error_string(FileAccess.get_open_error())
		return false
	file.store_string(JSON.stringify(_get_pose_data(), "  ") + "\n")
	editor._current_pose_path = path
	editor.preset_path_field.text = path
	editor.status_label.text = "Pose saved to %s" % path.get_file()
	return true


func _on_load_pose_pressed() -> void:
	if editor._current_pose_path.is_empty():
		editor.status_label.text = "This pose has not been saved yet"
		return
	_load_pose_from_path(editor._current_pose_path, true)


func _on_new_preset_pressed() -> void:
	editor._modifier.reset_all()
	# Same held-object bugs as _on_reset_all_pressed() had (see that
	# function's comment): unconditional access would crash for characters
	# without a held object (this button is only visible for Player in
	# practice, via preset_row.visible = body.supports_held_object, so the
	# crash itself was never actually reachable here - but the wrong
	# Vector3.ONE scale default was, on Player, which is exactly the
	# character this button is visible for).
	if editor.body.supports_held_object:
		editor._held_object.position = Vector3.ZERO
		editor._held_object.rotation = Vector3.ZERO
		editor._held_object.scale = Vector3.ONE * editor.DEFAULT_OBJECT_SCALE
		editor._gizmo_handler._sync_object_controls()
	editor._current_pose_path = ""
	editor._bone_controls_handler._sync_bone_controls()
	editor.preset_path_field.text = "(unsaved pose)"
	editor._gizmo_handler._refresh_skeleton()
	editor.status_label.text = "New pose; choose Save or Save As when ready"


func _on_browse_object_pressed() -> void:
	editor.object_dialog.current_path = editor._current_object_path
	editor.object_dialog.popup_centered_ratio(0.82)


func _on_object_file_selected(path: String) -> void:
	if editor._load_object(path, true):
		editor._gizmo_handler._sync_object_controls()
		editor.status_label.text = "Loaded object %s" % editor._current_object_path.get_file()


func _on_open_preset_pressed() -> void:
	editor.open_preset_dialog.current_path = (
			editor._import_handler._globalize_if_resource(editor._current_pose_path))
	editor.open_preset_dialog.popup_centered_ratio(0.82)


func _on_save_preset_as_pressed() -> void:
	editor.save_preset_dialog.current_path = (
			editor._import_handler._globalize_if_resource(editor._current_pose_path))
	editor.save_preset_dialog.popup_centered_ratio(0.82)


func _on_preset_file_selected(path: String) -> void:
	_load_pose_from_path(editor._localize_resource_path(path), true)


func _on_save_preset_file_selected(path: String) -> void:
	_save_pose_to_path(editor._localize_resource_path(path))


func _load_pose_from_path(path: String, update_ui: bool) -> bool:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		if update_ui:
			editor.status_label.text = "Could not load pose: %s" % error_string(
					FileAccess.get_open_error())
		return false
	var parsed = JSON.parse_string(file.get_as_text())
	if not parsed is Dictionary:
		if update_ui:
			editor.status_label.text = "Pose file is not valid JSON"
		return false
	var data := parsed as Dictionary
	var object_scene := String(data.get("object_scene", editor._current_object_path))
	if not object_scene.is_empty() and object_scene != editor._current_object_path:
		if not editor._load_object(object_scene, true):
			return false
	var attachment_name := StringName(data.get(
			"attachment_bone", data.get("hand", String(editor.DEFAULT_ATTACHMENT_BONE))))
	editor._ui_setup_handler._set_attachment_bone(attachment_name, false)
	editor._ui_setup_handler._select_attachment_in_ui(editor._attachment_bone)
	var animation_name := StringName(data.get("animation", String(editor.DEFAULT_ANIMATION)))
	editor._ui_setup_handler._select_animation_in_ui(animation_name)
	editor._ui_setup_handler._set_animation(animation_name)
	editor._modifier.reset_all()
	var rotations: Dictionary = data.get("bone_rotations_degrees", {})
	for bone_name: String in rotations:
		var values: Array = rotations[bone_name]
		if values.size() >= 3 and editor.body.skeleton.find_bone(StringName(bone_name)) >= 0:
			editor._modifier.set_bone_rotation(StringName(bone_name), Vector3(
					float(values[0]), float(values[1]), float(values[2])))
	# Held-object fields are meaningless - and _held_object is null - for
	# characters without one (see _on_reset_all_pressed's comment for the
	# same issue found elsewhere in this file). Not currently reachable
	# through the UI (pose load/save is hidden unless
	# body.supports_held_object), but _run_automation_args' "pose=" CLI
	# option calls this unconditionally regardless of character, so guard
	# here once rather than at every call site.
	if editor.body.supports_held_object:
		var position_values_data: Array = data.get(
				"object_position", data.get("flashlight_position", []))
		if position_values_data.size() >= 3:
			editor._held_object.position = Vector3(
					float(position_values_data[0]),
					float(position_values_data[1]),
					float(position_values_data[2]))
		var rotation_values_data: Array = data.get(
				"object_rotation_degrees", data.get("flashlight_rotation_degrees", []))
		if rotation_values_data.size() >= 3:
			editor._held_object.rotation_degrees = Vector3(
					float(rotation_values_data[0]),
					float(rotation_values_data[1]),
					float(rotation_values_data[2]))
		var object_scale := float(data.get("object_scale", editor._held_object.scale.x))
		editor._held_object.scale = Vector3.ONE * object_scale
	editor._current_pose_path = path
	if update_ui:
		editor._bone_controls_handler._sync_bone_controls()
		if editor.body.supports_held_object:
			editor._gizmo_handler._sync_object_controls()
		editor._gizmo_handler._refresh_skeleton()
		editor._gizmo_handler._update_bone_gizmo()
		editor.status_label.text = "Pose loaded from %s" % path.get_file()
	return true


func _on_save_image_pressed() -> void:
	var directory := ProjectSettings.globalize_path("user://pose_captures")
	DirAccess.make_dir_recursive_absolute(directory)
	var timestamp := Time.get_datetime_string_from_system().replace(":", "-")
	var path := directory.path_join("character_pose_%s.png" % timestamp)
	await _capture_pose_image(path, false)
	editor.status_label.text = "Image saved: %s" % path


func _capture_pose_image(path: String, include_ui: bool) -> Error:
	var global_path := ProjectSettings.globalize_path(path)
	var ui_was_visible := editor.ui_layer.visible
	if not include_ui:
		editor.ui_layer.visible = false
	await RenderingServer.frame_post_draw
	var image := editor.get_viewport().get_texture().get_image()
	var result := image.save_png(global_path)
	editor.ui_layer.visible = ui_was_visible
	return result
