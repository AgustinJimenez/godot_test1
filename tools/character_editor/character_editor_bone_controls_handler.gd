class_name CharacterEditorBoneControlsHandler
extends RefCounted

## Bone control list: section grouping/collapsing, per-bone rows, pose
## helpers (reference poses, hand open/close macro), reset buttons.
## Holds a back-reference to the main CharacterEditor - extracted
## purely to keep character_editor.gd under a manageable size.

var editor: CharacterEditor


func _init(editor_ref: CharacterEditor) -> void:
	editor = editor_ref


func _populate_bone_controls() -> void:
	editor._bone_slider_controls.clear()
	editor._section_headers.clear()
	editor._section_contents.clear()
	editor._section_expanded.clear()
	editor._section_parents.clear()
	for child in editor.bone_controls.get_children():
		child.free()
	var section_bones := {}
	for section: Dictionary in editor.BONE_SECTION_LAYOUT:
		var key: StringName = section["key"]
		section_bones[key] = PackedStringArray()
		editor._section_parents[key] = section["parent"]
		editor._section_expanded[key] = true
	for bone_index in editor.body.skeleton.get_bone_count():
		var bone_name := editor.body.skeleton.get_bone_name(bone_index)
		var section_key := _get_bone_section(bone_name)
		var names: PackedStringArray = section_bones[section_key]
		names.append(bone_name)
		section_bones[section_key] = names
	for section: Dictionary in editor.BONE_SECTION_LAYOUT:
		var key: StringName = section["key"]
		var bones: PackedStringArray = section_bones[key]
		if bones.is_empty():
			continue
		var header := Button.new()
		header.custom_minimum_size.y = 34.0
		header.toggle_mode = true
		header.button_pressed = true
		header.flat = true
		header.alignment = HORIZONTAL_ALIGNMENT_LEFT
		header.add_theme_font_size_override(&"font_size", 13)
		header.toggled.connect(_on_bone_section_toggled.bind(key))
		editor.bone_controls.add_child(header)
		editor._section_headers[key] = header
		var content := VBoxContainer.new()
		content.add_theme_constant_override(&"separation", 3)
		editor.bone_controls.add_child(content)
		editor._section_contents[key] = content
		for bone_name in bones:
			_add_bone_control_row(content, bone_name)
	_refresh_bone_section_visibility()
	_update_selected_bone_ui()
	_update_pose_helpers()


func _add_bone_control_row(container: VBoxContainer, bone_name: StringName) -> void:
	var row_panel := PanelContainer.new()
	row_panel.custom_minimum_size.y = 52.0
	row_panel.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	row_panel.gui_input.connect(editor._gizmo_handler._on_bone_row_gui_input.bind(bone_name))
	container.add_child(row_panel)
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_PASS
	row.add_theme_constant_override(&"separation", 8)
	row_panel.add_child(row)
	var joint_label := Label.new()
	joint_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	joint_label.custom_minimum_size.x = 140.0
	joint_label.text = _display_bone_name(String(bone_name))
	joint_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	row.add_child(joint_label)
	var rotation := editor._modifier.get_bone_rotation(bone_name)
	var sliders: Array[HSlider] = []
	var labels: Array[Label] = []
	for axis in 3:
		var axis_box := VBoxContainer.new()
		axis_box.mouse_filter = Control.MOUSE_FILTER_PASS
		axis_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		axis_box.add_theme_constant_override(&"separation", 0)
		row.add_child(axis_box)
		var value_label := Label.new()
		value_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		value_label.text = "%s  %+.0f" % ["XYZ"[axis], rotation[axis]]
		value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		value_label.add_theme_font_size_override(&"font_size", 11)
		value_label.add_theme_color_override(&"font_color", editor.AXIS_COLORS[axis])
		axis_box.add_child(value_label)
		var slider := HSlider.new()
		slider.min_value = -180.0
		slider.max_value = 180.0
		slider.step = 1.0
		slider.value = rotation[axis]
		slider.modulate = editor.AXIS_COLORS[axis]
		slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		slider.value_changed.connect(editor._gizmo_handler._on_bone_slider_changed.bind(
				bone_name, axis, value_label))
		axis_box.add_child(slider)
		sliders.append(slider)
		labels.append(value_label)
	editor._bone_slider_controls[bone_name] = {
		"sliders": sliders,
		"labels": labels,
		"row": row_panel,
		"joint_label": joint_label,
	}


func _on_bone_section_toggled(expanded: bool, section_key: StringName) -> void:
	editor._section_expanded[section_key] = expanded
	_refresh_bone_section_visibility()


func _refresh_bone_section_visibility() -> void:
	for section: Dictionary in editor.BONE_SECTION_LAYOUT:
		var key: StringName = section["key"]
		if not editor._section_headers.has(key):
			continue
		var ancestors_expanded := true
		var parent: StringName = editor._section_parents[key]
		while parent != &"":
			if not editor._section_expanded.get(parent, true):
				ancestors_expanded = false
				break
			parent = editor._section_parents.get(parent, &"")
		var expanded: bool = editor._section_expanded[key]
		var header: Button = editor._section_headers[key]
		header.visible = ancestors_expanded
		header.text = "%s%s  %s" % [
			"  ".repeat(section["depth"]), "-" if expanded else "+", section["label"]]
		(editor._section_contents[key] as VBoxContainer).visible = ancestors_expanded and expanded


func _get_bone_section(bone_name: StringName) -> StringName:
	var name := String(bone_name)
	if name in ["Hips", "Spine", "Spine1", "Spine2", "Neck", "Head"]:
		return &"body"
	var section := &"other"
	for side: String in ["Right", "Left"]:
		var side_key: String = side.to_lower()
		if name in [side + "Shoulder", side + "Arm", side + "ForeArm"]:
			section = StringName(side_key + "_arm")
		elif name == side + "Hand":
			section = StringName(side_key + "_hand")
		elif name.begins_with(side + "Hand"):
			section = StringName(side_key + "_hand")
			for finger in ["Thumb", "Index", "Middle", "Ring", "Pinky"]:
				if finger in name:
					section = StringName(side_key + "_" + finger.to_lower())
					break
		elif name in [side + "UpLeg", side + "Leg"]:
			section = StringName(side_key + "_leg")
		elif name.begins_with(side + "Foot") or name.begins_with(side + "Toe"):
			section = StringName(side_key + "_foot")
		if section != &"other":
			break
	return section


func _display_bone_name(bone_name: String) -> String:
	if bone_name in ["RightShoulder", "LeftShoulder"]:
		return "Shoulder"
	if bone_name in ["RightArm", "LeftArm"]:
		return "Upper arm"
	if bone_name in ["RightForeArm", "LeftForeArm"]:
		return "Forearm"
	if bone_name in ["RightHand", "LeftHand"]:
		return "Wrist"
	var label := bone_name.trim_prefix("RightHand").trim_prefix("LeftHand")
	label = label.replace("Pinky", "Little")
	for joint in range(1, 5):
		label = label.replace(str(joint), " joint " + str(joint))
	return label


func _expand_finger_sections(side: String) -> void:
	for finger in ["thumb", "index", "middle", "ring", "pinky"]:
		var section_key := StringName(side.to_lower() + "_" + finger)
		editor._section_expanded[section_key] = true
		if editor._section_headers.has(section_key):
			(editor._section_headers[section_key] as Button).set_pressed_no_signal(true)
	_refresh_bone_section_visibility()


func _update_pose_helpers() -> void:
	for child in editor.pose_helper_controls.get_children():
		child.free()
	editor._hand_openness_slider = null
	if editor._stage_handler == null or not editor._stage_handler.is_pose_stage():
		editor.pose_helpers.hide()
		return
	var bone_name := String(editor._selected_bone)
	var side := "Right" if bone_name.begins_with("Right") else (
			"Left" if bone_name.begins_with("Left") else "")
	if "Hand" in bone_name:
		_setup_hand_pose_helper(side)
	elif bone_name in [side + "Shoulder", side + "Arm", side + "ForeArm"]:
		_setup_animation_pose_helpers("%s ARM" % side.to_upper(), {
			"Relaxed": &"unarmed_idle",
			"Aim Front": &"Pistol_Aim_Neutral",
			"Carry": &"Walk_Carry",
			"Hand to Face": &"Idle_TalkingPhone",
		})
	elif bone_name in ["Head", "Neck"]:
		_setup_animation_pose_helpers("HEAD / NECK", {
			"Neutral": &"unarmed_idle",
			"Look Up": &"Pistol_Aim_Up",
			"Look Down": &"Pistol_Aim_Down",
			"Phone": &"Idle_TalkingPhone",
		})
	elif ("Leg" in bone_name or "Foot" in bone_name or "Toe" in bone_name
			or bone_name == "Hips"):
		_setup_animation_pose_helpers("LEGS / STANCE", {
			"Idle": &"unarmed_idle",
			"Crouch": &"unarmed_crouch_idle",
			"Jump": &"unarmed_jump",
			"Run": &"unarmed_sprint",
		})
	elif bone_name in ["Spine", "Spine1", "Spine2"]:
		_setup_animation_pose_helpers("BODY POSE", {
			"Idle": &"unarmed_idle",
			"Crouch": &"unarmed_crouch_idle",
			"Jump": &"unarmed_jump",
			"Run": &"unarmed_sprint",
		})
	else:
		editor.pose_helpers.visible = false


func _setup_animation_pose_helpers(title: String, presets: Dictionary) -> void:
	editor.pose_helpers.visible = true
	editor.pose_helper_title.text = title
	for label: String in presets:
		var button := Button.new()
		button.custom_minimum_size = Vector2(92.0, 32.0)
		button.text = label
		button.pressed.connect(_apply_reference_pose.bind(presets[label]))
		editor.pose_helper_controls.add_child(button)


func _apply_reference_pose(animation_name: StringName) -> void:
	editor._ui_setup_handler._select_animation_in_ui(animation_name)
	editor._ui_setup_handler._set_animation(animation_name)


func _setup_hand_pose_helper(side: String) -> void:
	if side.is_empty():
		editor.pose_helpers.visible = false
		return
	editor.pose_helpers.visible = true
	editor.pose_helper_title.text = "%s HAND" % side.to_upper()
	editor._hand_helper_side = side
	editor._hand_helper_baseline.clear()
	for finger in ["Thumb", "Index", "Middle", "Ring", "Pinky"]:
		for joint in range(1, 4):
			var bone_name := StringName("%sHand%s%d" % [side, finger, joint])
			if editor.body.skeleton.find_bone(bone_name) >= 0:
				editor._hand_helper_baseline[bone_name] = editor._modifier.get_bone_rotation(bone_name)
	var open_label := Label.new()
	open_label.text = "Open"
	editor.pose_helper_controls.add_child(open_label)
	editor._hand_openness_slider = HSlider.new()
	editor._hand_openness_slider.custom_minimum_size = Vector2(300.0, 32.0)
	editor._hand_openness_slider.min_value = -1.0
	editor._hand_openness_slider.max_value = 1.0
	editor._hand_openness_slider.step = 0.01
	editor._hand_openness_slider.value = 0.0
	editor._hand_openness_slider.value_changed.connect(_on_hand_openness_changed)
	editor.pose_helper_controls.add_child(editor._hand_openness_slider)
	var close_label := Label.new()
	close_label.text = "Close"
	editor.pose_helper_controls.add_child(close_label)
	var center_button := Button.new()
	center_button.custom_minimum_size = Vector2(76.0, 32.0)
	center_button.text = "Center"
	center_button.pressed.connect(_center_hand_openness)
	editor.pose_helper_controls.add_child(center_button)


func _center_hand_openness() -> void:
	if is_instance_valid(editor._hand_openness_slider):
		editor._hand_openness_slider.value = 0.0


func _on_hand_openness_changed(value: float) -> void:
	var open_amounts := [35.0, 25.0, 15.0]
	var close_amounts := [12.0, 18.0, 24.0]
	for finger in ["Index", "Middle", "Ring", "Pinky"]:
		for joint_index in 3:
			var bone_name := StringName("%sHand%s%d" % [
					editor._hand_helper_side, finger, joint_index + 1])
			if not editor._hand_helper_baseline.has(bone_name):
				continue
			var rotation: Vector3 = editor._hand_helper_baseline[bone_name]
			rotation.z += (close_amounts[joint_index] * value
					if value >= 0.0 else open_amounts[joint_index] * value)
			editor._modifier.set_bone_rotation(bone_name, rotation)
	var thumb_name := StringName("%sHandThumb1" % editor._hand_helper_side)
	if editor._hand_helper_baseline.has(thumb_name):
		var thumb_rotation: Vector3 = editor._hand_helper_baseline[thumb_name]
		thumb_rotation.z -= value * 10.0
		editor._modifier.set_bone_rotation(thumb_name, thumb_rotation)
	_sync_bone_controls()
	editor._gizmo_handler._refresh_skeleton()
	editor._gizmo_handler._update_bone_gizmo()


func _expand_section_for_bone(bone_name: StringName) -> void:
	var section_key := _get_bone_section(bone_name)
	while section_key != &"":
		editor._section_expanded[section_key] = true
		if editor._section_headers.has(section_key):
			(editor._section_headers[section_key] as Button).set_pressed_no_signal(true)
		section_key = editor._section_parents.get(section_key, &"")
	_refresh_bone_section_visibility()


func _update_selected_bone_ui() -> void:
	for bone_name: StringName in editor._bone_slider_controls:
		var controls: Dictionary = editor._bone_slider_controls[bone_name]
		var row := controls["row"] as PanelContainer
		var joint_label := controls["joint_label"] as Label
		if bone_name == editor._selected_bone:
			var selected_style := StyleBoxFlat.new()
			selected_style.bg_color = Color(0.12, 0.42, 0.68, 0.55)
			selected_style.corner_radius_top_left = 3
			selected_style.corner_radius_top_right = 3
			selected_style.corner_radius_bottom_right = 3
			selected_style.corner_radius_bottom_left = 3
			row.add_theme_stylebox_override(&"panel", selected_style)
			joint_label.add_theme_color_override(&"font_color", Color(0.75, 0.9, 1.0))
		else:
			row.add_theme_stylebox_override(&"panel", StyleBoxEmpty.new())
			joint_label.remove_theme_color_override(&"font_color")


func _sync_bone_controls() -> void:
	for bone_name: StringName in editor._bone_slider_controls:
		var controls: Dictionary = editor._bone_slider_controls[bone_name]
		var sliders: Array = controls["sliders"]
		var labels: Array = controls["labels"]
		var rotation := editor._modifier.get_bone_rotation(bone_name)
		for axis in 3:
			(sliders[axis] as HSlider).set_value_no_signal(rotation[axis])
			(labels[axis] as Label).text = "%s  %+.0f" % ["XYZ"[axis], rotation[axis]]


func _on_reset_bone_pressed() -> void:
	editor._modifier.reset_bone(editor._selected_bone)
	_sync_bone_controls()
	editor._gizmo_handler._refresh_skeleton()
	editor.status_label.text = "Selected bone reset"


func _on_reset_all_pressed() -> void:
	editor._modifier.reset_all()
	# Held-object reset is meaningless - and _held_object is null - for
	# characters that don't support held objects (see MIXAMO_CHARACTERS/
	# RETARGETED_MIXAMO_CHARACTERS/_custom_characters). Previously crashed
	# unconditionally here for every character except Player, aborting
	# before _refresh_skeleton() ever ran - the modifier reset above would
	# partially apply with no follow-up skeleton refresh, which is very
	# likely why the mesh visually broke.
	if editor.body.supports_held_object:
		editor._attachment_handler.reset_transforms()
	_sync_bone_controls()
	editor._gizmo_handler._refresh_skeleton()
	editor.status_label.text = "All values reset"
