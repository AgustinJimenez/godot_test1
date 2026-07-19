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
	var data := {
		"format_version": 3,
		"animation": String(editor._current_animation),
		"bone_rotations_degrees": editor._modifier.get_serializable_values(),
		"attachments": editor._attachment_handler.serialize(),
	}
	# Mirror the primary slot into schema-v2 fields for PlayerBody and older
	# tools that understand one held prop only.
	var primary := editor._attachment_handler.primary_slot()
	if primary != null:
		data["object_scene"] = primary.object_path
		data["attachment_bone"] = String(primary.bone_name)
		data["object_position"] = _vector3_to_array(primary.object_node.position)
		data["object_rotation_degrees"] = _vector3_to_array(
				primary.object_node.rotation_degrees)
		data["object_scale"] = primary.object_node.scale.x
		data["hand"] = String(primary.bone_name)
		data["flashlight_position"] = _vector3_to_array(primary.object_node.position)
		data["flashlight_rotation_degrees"] = _vector3_to_array(
				primary.object_node.rotation_degrees)
	var thumbnail_rotation := _read_existing_thumbnail_rotation()
	if not thumbnail_rotation.is_empty():
		data["thumbnail_rotation_degrees"] = thumbnail_rotation
	return data


func _read_existing_thumbnail_rotation() -> Array:
	if editor._current_pose_path.is_empty():
		return []
	var file := FileAccess.open(editor._current_pose_path, FileAccess.READ)
	if file == null:
		return []
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if not parsed is Dictionary:
		return []
	return (parsed as Dictionary).get("thumbnail_rotation_degrees", [])


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
	editor._pose_library_handler.register_saved_pose(path)
	editor._pose_library_handler.capture_object_preview.call_deferred(path)
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
		editor._attachment_handler.reset_transforms()
	editor._current_pose_path = ""
	editor._bone_controls_handler._sync_bone_controls()
	editor.preset_path_field.text = "(unsaved pose)"
	editor._gizmo_handler._refresh_skeleton()
	editor.status_label.text = "New pose; choose Save or Save As when ready"


func _on_browse_object_pressed() -> void:
	editor.object_dialog.current_path = editor._current_object_path
	editor.object_dialog.popup_centered_ratio(0.82)


func _on_object_file_selected(path: String) -> void:
	if editor._attachment_handler.handle_object_selected(path):
		editor._gizmo_handler._sync_object_controls()
		editor.status_label.text = "Added attachment %s" % path.get_file()
		return
	if editor._load_object(path, true):
		editor._gizmo_handler._sync_object_controls()
		editor.status_label.text = "Loaded object %s" % editor._current_object_path.get_file()


func _on_open_preset_pressed() -> void:
	editor._pose_library_handler.open()


func _browse_preset_file() -> void:
	var current_path := editor._import_handler._globalize_if_resource(
			editor._current_pose_path)
	if DisplayServer.has_feature(DisplayServer.FEATURE_NATIVE_DIALOG_FILE):
		var current_directory := current_path.get_base_dir() if not current_path.is_empty() else ""
		var current_file := current_path.get_file() if not current_path.is_empty() else ""
		var error := DisplayServer.file_dialog_show(
				"Open pose preset", current_directory, current_file, false,
				DisplayServer.FILE_DIALOG_MODE_OPEN_FILE,
				PackedStringArray(["*.json ; Pose presets"]),
				_on_native_preset_file_selected)
		if error == OK:
			return
		editor.status_label.text = (
				"Native file dialog failed (%s) - using built-in picker"
				% error_string(error))
	editor.open_preset_dialog.current_path = current_path
	editor.open_preset_dialog.popup_centered_ratio(0.82)


func _on_native_preset_file_selected(
		status: bool, selected_paths: PackedStringArray, _selected_filter_index: int) -> void:
	DisplayServer.window_move_to_foreground(editor.get_window().get_window_id())
	if status and not selected_paths.is_empty():
		_on_preset_file_selected(selected_paths[0])


func _on_save_preset_as_pressed() -> void:
	editor.save_preset_dialog.current_path = (
			editor._import_handler._globalize_if_resource(editor._current_pose_path))
	editor.save_preset_dialog.popup_centered_ratio(0.82)


func _on_preset_file_selected(path: String) -> void:
	var localized_path := editor._localize_resource_path(path)
	if _load_pose_from_path(localized_path, true):
		editor._pose_library_handler.register_saved_pose(localized_path)
		editor._pose_library_handler.close()


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
	if editor.body.supports_held_object:
		if not editor._attachment_handler.load_pose_data(data):
			return false
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
	editor._current_pose_path = path
	if update_ui:
		editor._bone_controls_handler._sync_bone_controls()
		if editor.body.supports_held_object and is_instance_valid(editor._held_object):
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
