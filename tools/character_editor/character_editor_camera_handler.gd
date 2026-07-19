class_name CharacterEditorCameraHandler
extends RefCounted

## Camera framing/orbit/zoom: view mode switching, full-body/attachment
## framing, focused-joint orbit, free-camera pan. Holds a back-reference
## to the main CharacterEditor - extracted purely to keep
## character_editor.gd under a manageable size.

var editor: CharacterEditor


func _init(editor_ref: CharacterEditor) -> void:
	editor = editor_ref


func _on_view_selected(index: int) -> void:
	editor._joint_focus_active = false
	editor._orbiting = false
	editor._orbiting_joint = false
	# _full_body_mesh/_isolated_attachment_mesh are only ever populated for
	# held-object characters (see _load_character - every other character
	# leaves _full_body_mesh explicitly null, since the "close-up"/"isolated
	# attachment" views exist to inspect a held flashlight, which only
	# Player has). Applying this swap unconditionally overwrote body.mesh's
	# actual mesh resource with that null for any other character - this is
	# Bug 9's real root cause (see docs/task_history/
	# character_editor_import_feature.md): "Reset Camera View" selects view
	# index 0 ("Full body"), which hit this exact line and wiped Ch28_Body's
	# geometry entirely, leaving a head-shaped hole showing the black
	# background behind it - not a lighting or material problem at all,
	# despite looking like one from a screenshot.
	if editor.body.supports_held_object:
		editor.body.mesh.mesh = (editor._isolated_attachment_mesh
				if index == 2 and editor._isolated_attachment_mesh != null else editor._full_body_mesh)
	if index == 0:
		_frame_full_body()
	else:
		_frame_attachment()


func _on_free_camera_toggled(enabled: bool) -> void:
	editor._captured = false
	editor._orbiting = false
	editor._orbiting_joint = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if enabled:
		editor.status_label.text = "Click the 3D view to move the camera"
	elif editor._joint_focus_active:
		_frame_selected_joint()
	else:
		_focus_character_general()


func _on_root_motion_toggled(moving: bool) -> void:
	editor._root_motion_moving = moving
	editor.body.node.position = editor.CHARACTER_SPAWN_POSITION


func _focus_character_general() -> void:
	editor._joint_focus_active = false
	if editor.view_picker.selected == 0:
		_frame_full_body()
	else:
		_frame_attachment()


func _on_pause_toggled(paused: bool) -> void:
	editor._comparison.set_paused(paused)
	if paused:
		editor.body.anim_player.pause()
		editor.status_label.text = "Animation paused"
	else:
		editor.body.anim_player.play()
		editor.status_label.text = "Animation playing"


func _frame_full_body() -> void:
	if editor._comparison.enabled:
		editor.camera.fov = 50.0
		editor.camera.h_offset = -1.9
		editor._orbit_target = editor._comparison.get_frame_target()
		editor.camera.global_position = editor._orbit_target + Vector3(0.35, 0.2, 4.6)
	else:
		editor.camera.fov = 44.0
		editor.camera.h_offset = -0.95
		editor.camera.global_position = editor.body.global_position + Vector3(0.5, 1.2, 2.5)
		editor._orbit_target = editor.body.global_position + Vector3(0.0, 1.05, 0.0)
	editor.camera.look_at(editor._orbit_target)
	var orbit_offset := editor.camera.global_position - editor._orbit_target
	editor._orbit_distance = orbit_offset.length()
	editor._orbit_yaw = atan2(orbit_offset.x, orbit_offset.z)
	editor._orbit_pitch = asin(clampf(
			orbit_offset.y / maxf(editor._orbit_distance, 0.001), -1.0, 1.0))
	editor._pitch = editor.camera.rotation.x
	editor._yaw = editor.camera.rotation.y


func _update_orbit_camera() -> void:
	var direction := _get_orbit_direction()
	editor.camera.global_position = editor._orbit_target + direction * editor._orbit_distance
	editor.camera.look_at(editor._orbit_target)


func _get_orbit_direction() -> Vector3:
	var horizontal := cos(editor._orbit_pitch)
	return Vector3(
			sin(editor._orbit_yaw) * horizontal,
			sin(editor._orbit_pitch),
			cos(editor._orbit_yaw) * horizontal)


func _begin_focused_joint_orbit() -> void:
	editor._orbiting = true
	editor._orbiting_joint = true
	editor._orbit_distance = editor._focused_camera_offset.length()
	if editor._orbit_distance <= 0.001:
		editor._orbit_distance = editor.MIN_ORBIT_DISTANCE
	var direction := editor._focused_camera_offset / editor._orbit_distance
	editor._orbit_yaw = atan2(direction.x, direction.z)
	editor._orbit_pitch = asin(clampf(direction.y, -1.0, 1.0))
	editor.status_label.text = "Joint focus locked; drag to orbit and use the wheel to zoom"


func _apply_camera_zoom(zoom_factor: float) -> void:
	if editor._joint_focus_active:
		var focus_distance := clampf(
				editor._focused_camera_offset.length() * zoom_factor,
				editor.MIN_ORBIT_DISTANCE * 0.5, editor.MAX_ORBIT_DISTANCE)
		editor._focused_camera_offset = editor._focused_camera_offset.normalized() * focus_distance
		editor._orbit_distance = focus_distance
		_update_focused_camera()
	else:
		editor._orbit_distance = clampf(
				editor._orbit_distance * zoom_factor,
				editor.MIN_ORBIT_DISTANCE, editor.MAX_ORBIT_DISTANCE)
		_update_orbit_camera()


func _frame_attachment() -> void:
	var attachment_index := editor.body.skeleton.find_bone(editor._attachment_bone)
	if attachment_index < 0:
		return
	var attachment_position := editor.body.skeleton.to_global(
			editor.body.skeleton.get_bone_global_pose(attachment_index).origin)
	editor.camera.fov = 38.0
	editor.camera.h_offset = -0.68
	editor.camera.global_position = attachment_position + Vector3(-0.48, 0.12, 0.55)
	editor.camera.look_at(attachment_position)
	editor._orbit_target = attachment_position
	var orbit_offset := editor.camera.global_position - editor._orbit_target
	editor._orbit_distance = orbit_offset.length()
	editor._orbit_yaw = atan2(orbit_offset.x, orbit_offset.z)
	editor._orbit_pitch = asin(clampf(
			orbit_offset.y / maxf(editor._orbit_distance, 0.001), -1.0, 1.0))
	editor._pitch = editor.camera.rotation.x
	editor._yaw = editor.camera.rotation.y


func _frame_selected_joint() -> void:
	var bone_index := editor.body.skeleton.find_bone(editor._selected_bone)
	if bone_index < 0:
		return
	var target := editor.body.skeleton.to_global(
			editor.body.skeleton.get_bone_global_pose(bone_index).origin)
	var view_direction := (editor.camera.global_position - target).normalized()
	if view_direction.is_zero_approx():
		view_direction = Vector3.FORWARD
	var focus_distance := 0.48 if "Hand" in String(editor._selected_bone) else 0.72
	editor._focused_camera_offset = view_direction * focus_distance
	editor.camera.fov = 38.0
	editor.camera.h_offset = 0.0
	editor.camera.global_position = target + editor._focused_camera_offset
	editor.camera.look_at(target)
	editor._pitch = editor.camera.rotation.x
	editor._yaw = editor.camera.rotation.y


func _update_focused_camera() -> void:
	var bone_index := editor.body.skeleton.find_bone(editor._selected_bone)
	if bone_index < 0:
		return
	var target := editor.body.skeleton.to_global(
			editor.body.skeleton.get_bone_global_pose(bone_index).origin)
	editor.camera.global_position = target + editor._focused_camera_offset
	editor.camera.look_at(target)


func _begin_camera_move() -> void:
	editor._moving_camera = true
	editor._joint_focus_active = false
	editor._orbiting = false
	editor._orbiting_joint = false
	editor.camera.h_offset = 0.0
	editor._orbit_target = (
			editor.camera.global_position - editor.camera.global_basis.z * editor._orbit_distance)
	var orbit_offset := editor.camera.global_position - editor._orbit_target
	editor._orbit_yaw = atan2(orbit_offset.x, orbit_offset.z)
	editor._orbit_pitch = asin(clampf(
			orbit_offset.y / maxf(editor._orbit_distance, 0.001), -1.0, 1.0))
	editor.status_label.text = "Moving camera; drag and use +/- to zoom"


func _move_camera_from_drag(relative: Vector2) -> void:
	var scale_factor := maxf(editor._orbit_distance, editor.MIN_ORBIT_DISTANCE) * 0.0015
	var offset := (editor.camera.global_basis.x * -relative.x
			+ editor.camera.global_basis.y * relative.y) * scale_factor
	editor.camera.global_position += offset
	editor._orbit_target += offset
