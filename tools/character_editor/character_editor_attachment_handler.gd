class_name CharacterEditorAttachmentHandler
extends RefCounted

## Owns the Character Editor's attachment collection. Legacy singular fields
## on CharacterEditor remain aliases for the selected slot.

var editor: CharacterEditor
var slots: Array[CharacterEditorAttachmentSlot] = []
var selected_index := -1
var _adding_attachment := false


func _init(editor_ref: CharacterEditor) -> void:
	editor = editor_ref


func setup() -> void:
	editor.attachment_slot_picker.item_selected.connect(select)
	editor.add_attachment_button.pressed.connect(begin_add)
	editor.remove_attachment_button.pressed.connect(remove_selected)
	editor.attachment_visible_toggle.toggled.connect(_on_visibility_toggled)
	editor.object_dialog.canceled.connect(cancel_add)
	_refresh_ui()


func clear() -> void:
	for slot: CharacterEditorAttachmentSlot in slots:
		if is_instance_valid(slot.attachment_node):
			slot.attachment_node.queue_free()
	slots.clear()
	selected_index = -1
	_clear_selected_aliases()
	_refresh_ui()


func add(path: String, bone_name: StringName, select_new := true) -> bool:
	var resource_path := editor._localize_resource_path(path)
	var resource := load(resource_path)
	if not resource is PackedScene:
		editor.status_label.text = "Object must import as a PackedScene"
		return false
	var instance := (resource as PackedScene).instantiate()
	if not instance is Node3D:
		instance.free()
		editor.status_label.text = "Object scene root must be Node3D"
		return false
	if editor.body.skeleton.find_bone(bone_name) < 0:
		bone_name = editor.DEFAULT_ATTACHMENT_BONE
	var attachment := BoneAttachment3D.new()
	attachment.name = StringName("ObjectAttachment%d" % (slots.size() + 1))
	attachment.bone_name = bone_name
	editor.body.skeleton.add_child(attachment)
	var object := instance as Node3D
	object.name = &"AttachedObject"
	attachment.add_child(object)
	var slot := CharacterEditorAttachmentSlot.new()
	slot.display_name = _unique_name(resource_path.get_file().get_basename().capitalize())
	slot.object_path = resource_path
	slot.bone_name = bone_name
	slot.attachment_node = attachment
	slot.object_node = object
	slots.append(slot)
	if select_new:
		select(slots.size() - 1)
	else:
		_refresh_ui()
	return true


func begin_add() -> void:
	_adding_attachment = true
	editor.object_dialog.title = "Add attachment"
	editor.object_dialog.popup_centered_ratio(0.82)


func cancel_add() -> void:
	_adding_attachment = false
	editor.object_dialog.title = "Choose held object"


func handle_object_selected(path: String) -> bool:
	if not _adding_attachment and selected_index >= 0:
		return false
	_adding_attachment = false
	editor.object_dialog.title = "Choose held object"
	add(path, editor.DEFAULT_ATTACHMENT_BONE)
	return true


func remove_selected() -> void:
	if selected_index < 0 or selected_index >= slots.size():
		return
	var removed := slots[selected_index]
	if is_instance_valid(removed.attachment_node):
		removed.attachment_node.queue_free()
	slots.remove_at(selected_index)
	if slots.is_empty():
		selected_index = -1
		_clear_selected_aliases()
	else:
		select(mini(selected_index, slots.size() - 1))
	_refresh_ui()
	editor.status_label.text = "Attachment removed"


func select(index: int) -> void:
	if index < 0 or index >= slots.size():
		return
	selected_index = index
	var slot := slots[index]
	editor._held_object = slot.object_node
	editor._object_attachment = slot.attachment_node
	editor._attachment_bone = slot.bone_name
	editor._current_object_path = slot.object_path
	_refresh_ui()
	editor._ui_setup_handler._select_attachment_in_ui(slot.bone_name)
	editor._gizmo_handler._sync_object_controls()
	editor._isolated_attachment_mesh = editor._build_isolated_attachment_mesh()
	if editor.view_picker.selected != 0:
		editor._camera_handler._frame_attachment()


func selected_slot() -> CharacterEditorAttachmentSlot:
	if selected_index < 0 or selected_index >= slots.size():
		return null
	return slots[selected_index]


func primary_slot() -> CharacterEditorAttachmentSlot:
	return slots[0] if not slots.is_empty() else null


func sync_selected_object(object: Node3D, path: String) -> void:
	var slot := selected_slot()
	if slot == null:
		return
	slot.object_node = object
	slot.object_path = path
	slot.display_name = _unique_name(path.get_file().get_basename().capitalize(), selected_index)
	_refresh_ui()


func sync_selected_bone(bone_name: StringName) -> void:
	var slot := selected_slot()
	if slot != null:
		slot.bone_name = bone_name


func serialize() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for slot: CharacterEditorAttachmentSlot in slots:
		result.append(slot.serialize())
	return result


func load_pose_data(data: Dictionary) -> bool:
	if data.has("attachments"):
		clear()
		var serialized_slots: Array = data.get("attachments", [])
		for serialized: Variant in serialized_slots:
			if not serialized is Dictionary:
				continue
			if not _add_serialized(serialized as Dictionary):
				return false
		if not slots.is_empty():
			select(0)
		return true
	var legacy_path := String(data.get("object_scene", editor._current_object_path))
	if legacy_path.is_empty():
		clear()
		return true
	clear()
	var legacy_bone := StringName(data.get(
			"attachment_bone", data.get("hand", String(editor.DEFAULT_ATTACHMENT_BONE))))
	if not add(legacy_path, legacy_bone):
		return false
	_apply_transform(slots[0], {
		"position": data.get("object_position", data.get("flashlight_position", [])),
		"rotation_degrees": data.get(
				"object_rotation_degrees", data.get("flashlight_rotation_degrees", [])),
		"scale": data.get("object_scale", slots[0].object_node.scale.x),
		"visible": true,
	})
	select(0)
	return true


func reset_transforms() -> void:
	for slot: CharacterEditorAttachmentSlot in slots:
		slot.object_node.position = Vector3.ZERO
		slot.object_node.rotation = Vector3.ZERO
		slot.object_node.scale = Vector3.ONE * editor.DEFAULT_OBJECT_SCALE
	if selected_index >= 0:
		editor._gizmo_handler._sync_object_controls()


func _add_serialized(data: Dictionary) -> bool:
	var path := String(data.get("object_scene", ""))
	if path.is_empty():
		return true
	var bone_name := StringName(data.get(
			"attachment_bone", String(editor.DEFAULT_ATTACHMENT_BONE)))
	if not add(path, bone_name, false):
		return false
	var slot := slots[-1]
	slot.display_name = String(data.get("name", slot.display_name))
	slot.role = StringName(data.get("role", "prop"))
	_apply_transform(slot, data)
	return true


func _apply_transform(slot: CharacterEditorAttachmentSlot, data: Dictionary) -> void:
	var position: Array = data.get("position", [])
	if position.size() >= 3:
		slot.object_node.position = Vector3(
				float(position[0]), float(position[1]), float(position[2]))
	var rotation: Array = data.get("rotation_degrees", [])
	if rotation.size() >= 3:
		slot.object_node.rotation_degrees = Vector3(
				float(rotation[0]), float(rotation[1]), float(rotation[2]))
	var uniform_scale := float(data.get("scale", slot.object_node.scale.x))
	slot.object_node.scale = Vector3.ONE * uniform_scale
	slot.visible = bool(data.get("visible", true))
	slot.object_node.visible = slot.visible


func _on_visibility_toggled(visible: bool) -> void:
	var slot := selected_slot()
	if slot == null:
		return
	slot.visible = visible
	slot.object_node.visible = visible


func _clear_selected_aliases() -> void:
	editor._held_object = null
	editor._object_attachment = null
	editor._attachment_bone = editor.DEFAULT_ATTACHMENT_BONE
	editor._current_object_path = ""


func _refresh_ui() -> void:
	if not is_instance_valid(editor.attachment_slot_picker):
		return
	editor.attachment_slot_picker.clear()
	for slot: CharacterEditorAttachmentSlot in slots:
		editor.attachment_slot_picker.add_item(slot.display_name)
	if selected_index >= 0 and selected_index < slots.size():
		editor.attachment_slot_picker.select(selected_index)
		var slot := slots[selected_index]
		editor.object_path_field.text = slot.object_path
		editor.attachment_visible_toggle.set_pressed_no_signal(slot.visible)
	else:
		editor.object_path_field.text = "(no attachments)"
		editor.attachment_visible_toggle.set_pressed_no_signal(false)
	var has_selection := selected_index >= 0
	editor.attachment_slot_picker.disabled = not has_selection
	editor.remove_attachment_button.disabled = not has_selection
	editor.attachment_visible_toggle.disabled = not has_selection
	editor.attachment_picker.disabled = not has_selection
	editor.scale_slider.editable = has_selection
	for slider: HSlider in editor.position_sliders + editor.rotation_sliders:
		slider.editable = has_selection


func _unique_name(base_name: String, ignore_index := -1) -> String:
	var candidate := base_name if not base_name.is_empty() else "Attachment"
	var suffix := 2
	while _name_exists(candidate, ignore_index):
		candidate = "%s %d" % [base_name, suffix]
		suffix += 1
	return candidate


func _name_exists(candidate: String, ignore_index: int) -> bool:
	for index in slots.size():
		if index != ignore_index and slots[index].display_name == candidate:
			return true
	return false
