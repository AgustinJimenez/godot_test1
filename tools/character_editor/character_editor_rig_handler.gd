class_name CharacterEditorRigHandler
extends RefCounted

## Validates imported humanoid rigs, maps their deforming chain, and can build
## a first-pass native rig for a neutral-pose static humanoid mesh.

const AUTORIGGER := preload("res://tools/character_editor/character_editor_autorigger.gd")
const T_POSE_REFERENCE := preload(
		"res://tools/character_editor/reference/rig_reference_t_pose.png")
const A_POSE_REFERENCE := preload(
		"res://tools/character_editor/reference/rig_reference.png")
const GENERATED_DIRECTORY := "res://assets/models/generated_characters"
const IMPORTED_DIRECTORY := "res://assets/models/imported_characters"

const MENU_RENAME := 1
const MENU_RESET_RIG := 2
const MENU_REMOVE := 3

const REQUIRED_ROLES: Array[Dictionary] = [
	{"role": "Hips", "label": "Hips", "aliases": ["hips", "pelvis"]},
	{"role": "Spine1", "label": "Chest", "aliases": ["spine1", "spine", "chest"]},
	{"role": "Spine2", "label": "Upper chest",
		"aliases": ["spine2", "upperchest", "chest2", "chest"]},
	{"role": "Neck", "label": "Neck", "aliases": ["neck"]},
	{"role": "Head", "label": "Head", "aliases": ["head"]},
	{"role": "LeftShoulder", "label": "Left shoulder",
		"aliases": ["leftshoulder", "shoulderl", "lshoulder"]},
	{"role": "LeftArm", "label": "Left upper arm",
		"aliases": ["leftarm", "upperarml", "lupperarm"]},
	{"role": "LeftForeArm", "label": "Left lower arm",
		"aliases": ["leftforearm", "forearml", "lowerarml", "lforearm"]},
	{"role": "LeftHand", "label": "Left hand", "aliases": ["lefthand", "handl", "lhand"]},
	{"role": "RightShoulder", "label": "Right shoulder",
		"aliases": ["rightshoulder", "shoulderr", "rshoulder"]},
	{"role": "RightArm", "label": "Right upper arm",
		"aliases": ["rightarm", "upperarmr", "rupperarm"]},
	{"role": "RightForeArm", "label": "Right lower arm",
		"aliases": ["rightforearm", "forearmr", "lowerarmr", "rforearm"]},
	{"role": "RightHand", "label": "Right hand", "aliases": ["righthand", "handr", "rhand"]},
	{"role": "LeftUpLeg", "label": "Left upper leg", "aliases": ["leftupleg", "thighl", "lthigh"]},
	{"role": "LeftLeg", "label": "Left lower leg", "aliases": ["leftleg", "shinl", "lshin"]},
	{"role": "LeftFoot", "label": "Left foot", "aliases": ["leftfoot", "footl", "lfoot"]},
	{"role": "RightUpLeg", "label": "Right upper leg", "aliases": ["rightupleg", "thighr", "rthigh"]},
	{"role": "RightLeg", "label": "Right lower leg", "aliases": ["rightleg", "shinr", "rshin"]},
	{"role": "RightFoot", "label": "Right foot", "aliases": ["rightfoot", "footr", "rfoot"]},
]

const MIXAMO_URL := "https://www.mixamo.com/"
const BLENDER_URL := (
		"https://docs.blender.org/manual/en/latest/animation/armatures/skinning/parenting.html")

var editor: CharacterEditor
var _selectors: Dictionary = {}
var _syncing_joint_controls := false
var _joint_editor: VBoxContainer
var _joint_name: Label
var _joint_sliders: Array[HSlider] = []
var _joint_values: Array[Label] = []
var _save_button: Button
var _reset_joint_button: Button
var _character_menu: MenuButton
var _rename_dialog: ConfirmationDialog
var _rename_field: LineEdit
var _action_dialog: ConfirmationDialog
var _pending_catalog_action := 0
var _reference_panel: PanelContainer
var _reference_toggle: Button
var _reference_resize_handle: Button
var _reference_image: TextureRect
var _reference_page_label: Label
var _reference_page := 0
var _reference_stage_active := false
var _reference_user_layout := false
var _dragging_reference := false
var _resizing_reference := false


func _init(editor_ref: CharacterEditor) -> void:
	editor = editor_ref


func setup() -> void:
	_reference_panel = editor.get_node(^"UI/RigReference")
	_reference_toggle = editor.get_node(^"UI/ViewportToolbar/Margin/Buttons/RigReference")
	_reference_resize_handle = editor.get_node(^"UI/RigReferenceResizeHandle")
	_reference_image = editor.get_node(^"UI/RigReference/Margin/Content/Image")
	_reference_page_label = editor.get_node(^"UI/RigReference/Margin/Content/TitleBar/Page")
	_reference_toggle.toggled.connect(_on_reference_toggled)
	_reference_panel.get_node(^"Margin/Content/TitleBar/Previous").pressed.connect(
			_on_reference_page_changed.bind(-1))
	_reference_panel.get_node(^"Margin/Content/TitleBar/Next").pressed.connect(
			_on_reference_page_changed.bind(1))
	_reference_panel.get_node(^"Margin/Content/TitleBar").gui_input.connect(
			_on_reference_title_gui_input)
	_reference_resize_handle.gui_input.connect(_on_reference_resize_gui_input)
	_joint_editor = editor.get_node(
			^"UI/Panel/PanelScroll/Margin/VBox/RigSection/JointEditor")
	_joint_name = _joint_editor.get_node(^"JointName")
	for axis_name: String in ["X", "Y", "Z"]:
		_joint_sliders.append(_joint_editor.get_node(NodePath(axis_name + "/Slider")))
		_joint_values.append(_joint_editor.get_node(NodePath(axis_name + "/Value")))
	_save_button = _joint_editor.get_node(^"Actions/SaveRig")
	_reset_joint_button = _joint_editor.get_node(^"Actions/ResetJoint")
	_character_menu = editor.get_node(
			^"UI/Panel/PanelScroll/Margin/VBox/CharacterRow/CharacterMenu")
	_rename_dialog = editor.get_node(^"UI/RenameCharacterDialog")
	_rename_field = _rename_dialog.get_node(^"Name")
	_action_dialog = editor.get_node(^"UI/CharacterActionDialog")
	var popup := _character_menu.get_popup()
	popup.add_item("Rename...", MENU_RENAME)
	popup.add_item("Reset Generated Rig...", MENU_RESET_RIG)
	popup.add_separator()
	popup.add_item("Remove from Editor...", MENU_REMOVE)
	popup.id_pressed.connect(_on_character_menu_pressed)
	_character_menu.about_to_popup.connect(_update_character_menu)
	_rename_dialog.confirmed.connect(_on_rename_confirmed)
	_action_dialog.confirmed.connect(_on_catalog_action_confirmed)
	editor.rig_auto_map_button.pressed.connect(_on_auto_map_pressed)
	editor.rig_apply_button.pressed.connect(_on_apply_pressed)
	editor.rig_generate_button.pressed.connect(_on_generate_rig_pressed)
	for axis in 3:
		_joint_sliders[axis].value_changed.connect(
				_on_joint_axis_changed.bind(axis))
	_save_button.pressed.connect(_on_save_rig_pressed)
	_reset_joint_button.pressed.connect(_on_reset_joint_pressed)
	editor.rig_mixamo_button.pressed.connect(OS.shell_open.bind(MIXAMO_URL))
	editor.rig_blender_button.pressed.connect(OS.shell_open.bind(BLENDER_URL))
	update_reference_layout(editor.get_viewport().get_visible_rect().size / editor._ui_scale)


func set_reference_stage_active(active: bool) -> void:
	var was_visible := _reference_panel.visible
	_reference_stage_active = active
	_reference_toggle.visible = active
	_reference_panel.visible = active and _reference_toggle.button_pressed
	_reference_resize_handle.visible = _reference_panel.visible
	_update_reference_resize_handle()
	if was_visible != _reference_panel.visible and editor.body != null:
		editor._camera_handler._frame_full_body()


func update_reference_layout(viewport_size: Vector2) -> void:
	if _reference_panel == null:
		return
	if not _reference_user_layout:
		var width := clampf(viewport_size.x * 0.21, 240.0, 360.0)
		var height := minf(viewport_size.y - 112.0, width * 1.5 + 48.0)
		_reference_panel.size = Vector2(width, maxf(height, 400.0))
		_reference_panel.position = Vector2(
				viewport_size.x - width - 16.0,
				maxf(76.0, (viewport_size.y - _reference_panel.size.y) * 0.5))
	else:
		_clamp_reference_to_viewport(viewport_size)
	_update_reference_resize_handle()


func get_visible_right_edge(viewport_width: float) -> float:
	if _reference_panel != null and _reference_panel.visible:
		return _reference_panel.position.x * editor._ui_scale
	return viewport_width


func is_pointer_over_reference(logical_position: Vector2) -> bool:
	return (_reference_panel != null and _reference_panel.visible
			and Rect2(_reference_panel.position, _reference_panel.size).has_point(logical_position)
			or (_reference_resize_handle.visible
				and Rect2(_reference_resize_handle.position,
						_reference_resize_handle.size).has_point(logical_position)))


func _on_reference_toggled(enabled: bool) -> void:
	_reference_panel.visible = _reference_stage_active and enabled
	_reference_resize_handle.visible = _reference_panel.visible
	_update_reference_resize_handle()
	if editor.body != null and not editor._comparison.enabled:
		editor._camera_handler._frame_full_body()


func _on_reference_page_changed(direction: int) -> void:
	_reference_page = wrapi(_reference_page + direction, 0, 2)
	if _reference_page == 0:
		_reference_image.texture = T_POSE_REFERENCE
		_reference_page_label.text = "T-POSE  1 / 2"
	else:
		_reference_image.texture = A_POSE_REFERENCE
		_reference_page_label.text = "A-POSE  2 / 2"


func _on_reference_title_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_dragging_reference = event.pressed
		if event.pressed:
			_reference_user_layout = true
		elif editor.body != null:
			editor._camera_handler._frame_full_body()
	elif event is InputEventMouseMotion and _dragging_reference:
		_reference_panel.position += event.relative / editor._ui_scale
		_clamp_reference_position(
				editor.get_viewport().get_visible_rect().size / editor._ui_scale)
		_update_reference_resize_handle()


func _on_reference_resize_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_resizing_reference = event.pressed
		if event.pressed:
			_reference_user_layout = true
		elif editor.body != null:
			editor._camera_handler._frame_full_body()
	elif event is InputEventMouseMotion and _resizing_reference:
		_reference_panel.size += event.relative / editor._ui_scale
		_clamp_reference_to_viewport(
				editor.get_viewport().get_visible_rect().size / editor._ui_scale)
		_update_reference_resize_handle()


func _clamp_reference_to_viewport(viewport_size: Vector2) -> void:
	var available := viewport_size - _reference_panel.position - Vector2(8.0, 8.0)
	_reference_panel.size = Vector2(
			clampf(_reference_panel.size.x, minf(220.0, available.x), available.x),
			clampf(_reference_panel.size.y, minf(360.0, available.y), available.y))
	_clamp_reference_position(viewport_size)


func _clamp_reference_position(viewport_size: Vector2) -> void:
	var max_position := Vector2(
			maxf(8.0, viewport_size.x - _reference_panel.size.x - 8.0),
			maxf(68.0, viewport_size.y - _reference_panel.size.y - 8.0))
	_reference_panel.position = _reference_panel.position.clamp(Vector2(8.0, 68.0), max_position)


func _update_reference_resize_handle() -> void:
	if _reference_resize_handle == null:
		return
	_reference_resize_handle.position = (
			_reference_panel.position + _reference_panel.size
			- _reference_resize_handle.size - Vector2(4.0, 4.0))


func restore_generated_characters() -> void:
	_restore_characters_from_directory(IMPORTED_DIRECTORY)
	_restore_characters_from_directory(GENERATED_DIRECTORY)


func _restore_characters_from_directory(path: String) -> void:
	var directory := DirAccess.open(path)
	if directory == null:
		return
	directory.list_dir_begin()
	var filename := directory.get_next()
	while not filename.is_empty():
		if not directory.current_is_dir() and filename.ends_with(".character.json"):
			var manifest_path := path.path_join(filename)
			var file := FileAccess.open(manifest_path, FileAccess.READ)
			var parsed: Variant = JSON.parse_string(file.get_as_text()) if file != null else null
			if parsed is Dictionary:
				var info: Dictionary = parsed
				var kind_id: String = info.get("kind_id", "")
				var model_path: String = info.get("model_path", "")
				if not kind_id.is_empty() and ResourceLoader.exists(model_path):
					info["manifest_path"] = manifest_path
					editor._custom_characters[kind_id] = info
		filename = directory.get_next()
	directory.list_dir_end()


func on_character_loaded() -> void:
	_character_menu.disabled = editor._custom_characters.get(
			editor._character_kind, {}).is_empty()
	_populate()
	editor._stage_handler.set_rig_ready(is_ready())


func on_character_unloaded() -> void:
	_character_menu.disabled = true


func is_ready() -> bool:
	return editor.body != null and editor.body.humanoid_ready


func _populate() -> void:
	for child: Node in editor.rig_mapping_list.get_children():
		child.free()
	_selectors.clear()
	if editor.body == null:
		return
	var bone_count := editor.body.skeleton.get_bone_count()
	var custom_info: Dictionary = editor._custom_characters.get(editor._character_kind, {})
	var is_custom := not custom_info.is_empty()
	var has_skin: bool = editor.body.has_skin if is_custom else true
	var mapped_count := _mapped_required_count(editor.body.humanoid_map)
	if not is_custom:
		editor.rig_summary.text = (
				"Ready · %d bones · skinned mesh · built-in humanoid mapping" % bone_count)
		editor.rig_mapping_scroll.hide()
		editor.rig_auto_map_button.hide()
		editor.rig_apply_button.hide()
		editor.rig_external_actions.hide()
		_joint_editor.hide()
		return
	if bone_count == 0:
		editor.rig_summary.text = (
				"Not rigged · generate a native humanoid rig from this neutral-pose mesh.")
	elif not has_skin:
		editor.rig_summary.text = (
				"Not skinned · generate a replacement rig, or finish the existing weights externally.")
	else:
		editor.rig_summary.text = "%s · %d bones · %d/%d required roles mapped" % [
				"Ready" if editor.body.humanoid_ready else "Mapping required",
				bone_count, mapped_count, REQUIRED_ROLES.size()]
	editor.rig_mapping_scroll.visible = bone_count > 0
	editor.rig_auto_map_button.visible = bone_count > 0
	editor.rig_apply_button.visible = bone_count > 0 and has_skin
	editor.rig_external_actions.visible = bone_count == 0 or not has_skin
	editor.rig_generate_button.visible = bone_count == 0 or not has_skin
	_joint_editor.visible = custom_info.get("generated_rig", false) and has_skin
	if bone_count > 0:
		_build_mapping_rows()
	if _joint_editor.visible:
		on_bone_selected(editor._selected_bone)


func _build_mapping_rows() -> void:
	var bone_names := PackedStringArray()
	for index in editor.body.skeleton.get_bone_count():
		bone_names.append(editor.body.skeleton.get_bone_name(index))
	for role_info: Dictionary in _all_roles():
		var row := HBoxContainer.new()
		row.add_theme_constant_override(&"separation", 8)
		editor.rig_mapping_list.add_child(row)
		var label := Label.new()
		label.custom_minimum_size.x = 150.0
		label.text = role_info["label"]
		row.add_child(label)
		var picker := OptionButton.new()
		picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		picker.add_item("Not mapped")
		picker.set_item_metadata(0, "")
		for bone_name: String in bone_names:
			picker.add_item(bone_name)
			picker.set_item_metadata(picker.item_count - 1, bone_name)
		var mapped_name: String = editor.body.humanoid_map.get(role_info["role"], "")
		for item_index in picker.item_count:
			if picker.get_item_metadata(item_index) == mapped_name:
				picker.select(item_index)
				break
		row.add_child(picker)
		_selectors[role_info["role"]] = picker


func _on_auto_map_pressed() -> void:
	var suggestions := auto_map(editor.body.skeleton)
	for role: String in _selectors:
		var picker := _selectors[role] as OptionButton
		var suggested: String = suggestions.get(role, "")
		for item_index in picker.item_count:
			if picker.get_item_metadata(item_index) == suggested:
				picker.select(item_index)
				break
	_update_mapping_summary(_mapping_from_selectors())


func _on_apply_pressed() -> void:
	var mapping := _mapping_from_selectors()
	if _mapped_required_count(mapping) != REQUIRED_ROLES.size():
		editor.rig_summary.text = "Mapping incomplete · assign every required humanoid role"
		return
	var info: Dictionary = editor._custom_characters.get(editor._character_kind, {})
	if info.is_empty():
		return
	info["humanoid_map"] = mapping
	editor._custom_characters[editor._character_kind] = info
	_save_profile(info["model_path"], mapping)
	var current_kind := editor._character_kind
	editor._load_character(current_kind)
	editor._stage_handler.set_stage(CharacterEditorStageHandler.Stage.RIG)


func _on_generate_rig_pressed() -> void:
	var info: Dictionary = editor._custom_characters.get(editor._character_kind, {})
	if info.is_empty():
		editor.rig_summary.text = "Native generation is available for imported characters"
		return
	var source_path: String = info.get("source_model_path", info.get("model_path", ""))
	if source_path.is_empty():
		editor.rig_summary.text = "The imported character has no source model path"
		return
	var output_path := _generated_output_path(source_path)
	editor.rig_generate_button.disabled = true
	editor.rig_summary.text = "Generating skeleton and anatomical skin weights..."
	await editor.get_tree().process_frame
	var result: Dictionary = AUTORIGGER.generate(source_path, output_path)
	editor.rig_generate_button.disabled = false
	if not result.get("ok", false):
		editor.rig_summary.text = "Could not generate rig · %s" % result.get("error", "unknown error")
		return
	info["source_model_path"] = source_path
	info["kind_id"] = editor._character_kind
	info["model_path"] = result["path"]
	info["bone_prefix"] = null
	info["has_skin"] = true
	info["humanoid_map"] = result["humanoid_map"]
	info["generated_rig"] = true
	info["joint_positions"] = result["joint_positions"]
	info["default_joint_positions"] = result["joint_positions"].duplicate(true)
	info["rig_landmarks"] = result.get("landmarks", {})
	editor._custom_characters[editor._character_kind] = info
	_save_profile(result["path"], result["humanoid_map"])
	_save_generated_character(info)
	var landmarks: Dictionary = result.get("landmarks", {})
	var landmark_source := (
			"geometry analysis" if landmarks.get("detection_valid", false) else "fallback")
	editor.status_label.text = (
			"Generated %d-bone native rig · pelvis %.0f%% (%s) · inspect before animation" % [
				int(result["bone_count"]),
				float(landmarks.get("pelvis_height", AUTORIGGER.DEFAULT_PELVIS_HEIGHT)) * 100.0,
				landmark_source,
			])
	editor._load_character(editor._character_kind)
	editor.show_bones_toggle.set_pressed_no_signal(true)
	editor._gizmo_handler._on_show_bones_toggled(true)
	editor._stage_handler.set_stage(CharacterEditorStageHandler.Stage.RIG)


func on_bone_selected(bone_name: StringName) -> void:
	if not _joint_editor.visible or editor.body == null:
		return
	var bone_index := editor.body.skeleton.find_bone(bone_name)
	if bone_index < 0:
		return
	var position := editor.body.skeleton.get_bone_global_rest(bone_index).origin
	_syncing_joint_controls = true
	_joint_name.text = "%s rest position" % bone_name
	for axis in 3:
		_joint_sliders[axis].set_value_no_signal(position[axis])
		_joint_values[axis].text = "%+.3f" % position[axis]
	_syncing_joint_controls = false


func _on_joint_axis_changed(value: float, axis: int) -> void:
	if _syncing_joint_controls or editor.body == null:
		return
	var bone_index := editor.body.skeleton.find_bone(editor._selected_bone)
	if bone_index < 0:
		return
	var preserved_global_positions: Array[Vector3] = []
	for current_index in editor.body.skeleton.get_bone_count():
		preserved_global_positions.append(
				editor.body.skeleton.get_bone_global_rest(current_index).origin)
	var global_position := editor.body.skeleton.get_bone_global_rest(bone_index).origin
	global_position[axis] = value
	var parent_index := editor.body.skeleton.get_bone_parent(bone_index)
	var local_position := global_position
	if parent_index >= 0:
		local_position = (
				editor.body.skeleton.get_bone_global_rest(parent_index).affine_inverse()
				* global_position)
	var rest := editor.body.skeleton.get_bone_rest(bone_index)
	rest.origin = local_position
	editor.body.skeleton.set_bone_rest(bone_index, rest)
	# A joint-placement edit changes that joint without dragging every child
	# marker with it. Recompute descendant locals against their preserved
	# global positions, matching what the saved override map will regenerate.
	for current_index in editor.body.skeleton.get_bone_count():
		if current_index == bone_index:
			continue
		var current_parent := editor.body.skeleton.get_bone_parent(current_index)
		if current_parent < 0:
			continue
		var current_rest := editor.body.skeleton.get_bone_rest(current_index)
		current_rest.origin = (
				editor.body.skeleton.get_bone_global_rest(current_parent).affine_inverse()
				* preserved_global_positions[current_index])
		editor.body.skeleton.set_bone_rest(current_index, current_rest)
	editor.body.skeleton.reset_bone_poses()
	_update_skin_binds()
	var info: Dictionary = editor._custom_characters[editor._character_kind]
	var positions: Dictionary = info.get("joint_positions", {})
	positions[String(editor._selected_bone)] = [
		global_position.x, global_position.y, global_position.z]
	info["joint_positions"] = positions
	editor._custom_characters[editor._character_kind] = info
	_joint_values[axis].text = "%+.3f" % value
	editor._gizmo_handler._refresh_skeleton()
	editor._gizmo_handler._update_bone_gizmo()


func _update_skin_binds() -> void:
	var updated_skins := {}
	for mesh: MeshInstance3D in editor.body.meshes:
		if mesh.skin == null or updated_skins.has(mesh.skin):
			continue
		updated_skins[mesh.skin] = true
		for bind_index in mesh.skin.get_bind_count():
			var bone_index := editor.body.skeleton.find_bone(mesh.skin.get_bind_name(bind_index))
			if bone_index >= 0:
				mesh.skin.set_bind_pose(
						bind_index,
						editor.body.skeleton.get_bone_global_rest(bone_index).affine_inverse())


func _on_reset_joint_pressed() -> void:
	var info: Dictionary = editor._custom_characters.get(editor._character_kind, {})
	var defaults: Dictionary = info.get("default_joint_positions", {})
	var bone_name := String(editor._selected_bone)
	if not defaults.has(bone_name):
		return
	var saved: Array = defaults[bone_name]
	_syncing_joint_controls = true
	for axis in 3:
		_joint_sliders[axis].value = saved[axis]
	_syncing_joint_controls = false
	for axis in 3:
		_on_joint_axis_changed(saved[axis], axis)


func _on_save_rig_pressed() -> void:
	var info: Dictionary = editor._custom_characters.get(editor._character_kind, {})
	var source_path: String = info.get("source_model_path", "")
	if source_path.is_empty():
		return
	var output_path := _generated_output_path(source_path)
	_save_button.disabled = true
	editor.rig_summary.text = "Saving adjusted rig..."
	await editor.get_tree().process_frame
	var result: Dictionary = AUTORIGGER.generate(
			source_path, output_path, info.get("joint_positions", {}))
	_save_button.disabled = false
	if not result.get("ok", false):
		editor.rig_summary.text = "Could not save rig · %s" % result.get("error", "unknown error")
		return
	ResourceLoader.load(output_path, "", ResourceLoader.CACHE_MODE_REPLACE)
	info["model_path"] = output_path
	info["humanoid_map"] = result["humanoid_map"]
	info["joint_positions"] = result["joint_positions"]
	info["rig_landmarks"] = result.get("landmarks", {})
	editor._custom_characters[editor._character_kind] = info
	_save_profile(output_path, result["humanoid_map"])
	_save_generated_character(info)
	editor._load_character(editor._character_kind)
	editor._stage_handler.set_stage(CharacterEditorStageHandler.Stage.RIG)
	editor.status_label.text = "Saved adjusted native rig"


static func _generated_output_path(source_path: String) -> String:
	return "res://assets/models/generated_characters/%s_rigged.tscn" % (
			source_path.get_file().get_basename().to_snake_case())


func _save_generated_character(info: Dictionary) -> void:
	var output_path: String = info.get("model_path", "")
	if output_path.is_empty():
		return
	persist_character(info, output_path.get_basename() + ".character.json")


func persist_character(info: Dictionary, manifest_path: String) -> void:
	var old_manifest: String = info.get("manifest_path", "")
	if not old_manifest.is_empty() and old_manifest != manifest_path:
		_remove_file(old_manifest)
	info["manifest_path"] = manifest_path
	var file := FileAccess.open(manifest_path, FileAccess.WRITE)
	if file == null:
		editor.rig_summary.text = "Rig saved, but its character manifest could not be written"
		return
	var persistent := info.duplicate(true)
	persistent["version"] = 1
	file.store_string(JSON.stringify(persistent, "  "))


func _update_character_menu() -> void:
	var info: Dictionary = editor._custom_characters.get(editor._character_kind, {})
	var popup := _character_menu.get_popup()
	popup.set_item_disabled(popup.get_item_index(MENU_RENAME), info.is_empty())
	popup.set_item_disabled(
			popup.get_item_index(MENU_RESET_RIG), not info.get("generated_rig", false))
	popup.set_item_disabled(
			popup.get_item_index(MENU_REMOVE), editor._character_kind in editor.CHARACTER_KINDS)


func _on_character_menu_pressed(action_id: int) -> void:
	var info: Dictionary = editor._custom_characters.get(editor._character_kind, {})
	if info.is_empty():
		return
	match action_id:
		MENU_RENAME:
			_rename_field.text = info.get("display_name", "")
			_rename_dialog.popup_centered()
			_rename_field.grab_focus()
			_rename_field.select_all()
		MENU_RESET_RIG:
			_pending_catalog_action = MENU_RESET_RIG
			_action_dialog.dialog_text = (
					"Delete the generated rig and return to the original unrigged source? "
					+ "The source model will be preserved.")
			_action_dialog.popup_centered()
		MENU_REMOVE:
			_pending_catalog_action = MENU_REMOVE
			_action_dialog.dialog_text = (
					"Remove this character from the editor catalog? "
					+ "Source and generated asset files will be preserved.")
			_action_dialog.popup_centered()


func _on_rename_confirmed() -> void:
	var new_name := _rename_field.text.strip_edges()
	if new_name.is_empty():
		return
	var info: Dictionary = editor._custom_characters.get(editor._character_kind, {})
	if info.is_empty():
		return
	info["display_name"] = new_name
	editor._custom_characters[editor._character_kind] = info
	persist_character(info, info.get("manifest_path", _manifest_path_for_info(info)))
	editor.character_picker.set_item_text(editor.character_picker.selected, new_name)
	editor.body.display_name = new_name
	editor.status_label.text = "Renamed character to %s" % new_name


func _on_catalog_action_confirmed() -> void:
	match _pending_catalog_action:
		MENU_RESET_RIG:
			_reset_generated_rig()
		MENU_REMOVE:
			_remove_character_registration()
	_pending_catalog_action = 0


func _reset_generated_rig() -> void:
	var kind_id := editor._character_kind
	var info: Dictionary = editor._custom_characters.get(kind_id, {})
	if info.is_empty() or not info.get("generated_rig", false):
		return
	var generated_path: String = info.get("model_path", "")
	_remove_file(info.get("manifest_path", ""))
	_remove_file(generated_path)
	_remove_file(generated_path.get_basename() + ".rig.json")
	var source_path: String = info.get("source_model_path", "")
	info["model_path"] = source_path
	info["has_skin"] = false
	info["bone_prefix"] = null
	info["humanoid_map"] = load_profile(source_path)
	info["generated_rig"] = false
	info.erase("joint_positions")
	info.erase("default_joint_positions")
	info.erase("manifest_path")
	persist_character(info, source_path.get_basename() + ".character.json")
	editor._custom_characters[kind_id] = info
	editor._load_character(kind_id)
	editor._stage_handler.set_stage(CharacterEditorStageHandler.Stage.RIG)
	editor.status_label.text = "Generated rig deleted · source model restored"


func _remove_character_registration() -> void:
	var kind_id := editor._character_kind
	var info: Dictionary = editor._custom_characters.get(kind_id, {})
	if info.is_empty() or kind_id in editor.CHARACTER_KINDS:
		return
	_remove_file(info.get("manifest_path", ""))
	var selected_item := editor.character_picker.selected
	editor._custom_characters.erase(kind_id)
	editor.character_picker.remove_item(selected_item)
	editor._unload_character()
	editor.status_label.text = "Character removed from editor · asset files preserved"


static func _manifest_path_for_info(info: Dictionary) -> String:
	var model_path: String = info.get("model_path", "")
	return model_path.get_basename() + ".character.json"


static func _remove_file(path: String) -> void:
	if path.is_empty() or not FileAccess.file_exists(path):
		return
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _mapping_from_selectors() -> Dictionary:
	var mapping := editor.body.humanoid_map.duplicate(true)
	for role: String in _selectors:
		var picker := _selectors[role] as OptionButton
		mapping[role] = picker.get_item_metadata(picker.selected)
	return mapping


func _update_mapping_summary(mapping: Dictionary) -> void:
	editor.rig_summary.text = "Auto-map suggestion · %d/%d required roles found" % [
			_mapped_required_count(mapping), REQUIRED_ROLES.size()]


static func auto_map(skeleton: Skeleton3D) -> Dictionary:
	var result := {}
	var used := {}
	for role_info: Dictionary in _all_roles():
		var best_name := ""
		var best_score := -1
		for bone_index in skeleton.get_bone_count():
			var bone_name := String(skeleton.get_bone_name(bone_index))
			if used.has(bone_name):
				continue
			var normalized := _normalize_bone_name(bone_name)
			var score := _match_score(normalized, role_info["aliases"])
			if score > best_score:
				best_score = score
				best_name = bone_name
		if best_score >= 80:
			result[role_info["role"]] = best_name
			used[best_name] = true
	return result


static func full_map_from_prefix(skeleton: Skeleton3D, prefix: String) -> Dictionary:
	var result := {}
	for role_info: Dictionary in REQUIRED_ROLES:
		var role: String = role_info["role"]
		var candidate := prefix + role
		if skeleton.find_bone(candidate) >= 0:
			result[role] = candidate
	for bone_index in skeleton.get_bone_count():
		var bone_name := String(skeleton.get_bone_name(bone_index))
		if bone_name.begins_with(prefix):
			result[bone_name.trim_prefix(prefix)] = bone_name
	return result


static func load_profile(model_path: String) -> Dictionary:
	var profile_path := _profile_path(model_path)
	if not FileAccess.file_exists(profile_path):
		return {}
	var file := FileAccess.open(profile_path, FileAccess.READ)
	var parsed: Variant = JSON.parse_string(file.get_as_text()) if file != null else null
	return parsed.get("humanoid_bones", {}) if parsed is Dictionary else {}


func _save_profile(model_path: String, mapping: Dictionary) -> void:
	var file := FileAccess.open(_profile_path(model_path), FileAccess.WRITE)
	if file == null:
		editor.rig_summary.text = "Could not save rig profile"
		return
	file.store_string(JSON.stringify({"version": 1, "humanoid_bones": mapping}, "  "))


static func _profile_path(model_path: String) -> String:
	return model_path.get_basename() + ".rig.json"


static func _mapped_required_count(mapping: Dictionary) -> int:
	var count := 0
	for role_info: Dictionary in REQUIRED_ROLES:
		if not String(mapping.get(role_info["role"], "")).is_empty():
			count += 1
	return count


static func _all_roles() -> Array[Dictionary]:
	var roles: Array[Dictionary] = REQUIRED_ROLES.duplicate(true)
	roles.append({
		"role": "Spine",
		"label": "Additional lower spine (optional)",
		"aliases": ["spine", "spine0"],
	})
	for side: String in ["Left", "Right"]:
		var side_short := "l" if side == "Left" else "r"
		roles.append({
			"role": side + "ToeBase",
			"label": side + " toes (optional)",
			"aliases": [side.to_lower() + "toebase", "toe" + side_short],
		})
		for finger: String in ["Thumb", "Index", "Middle", "Ring", "Pinky"]:
			for joint in range(1, 5):
				var finger_lower := finger.to_lower()
				var hbm_finger := (
						finger_lower + "finger"
						if finger in ["Index", "Middle", "Ring"] else finger_lower)
				roles.append({
					"role": "%sHand%s%d" % [side, finger, joint],
					"label": "%s %s %d (optional)" % [side, finger_lower, joint],
					"aliases": [
						"%shand%s%d" % [side.to_lower(), finger_lower, joint],
						"%s%d%s" % [finger_lower, joint, side_short],
						"%s%s%d" % [side_short, finger_lower, joint],
						"%s0%d%s" % [hbm_finger, joint, side_short],
					],
				})
	return roles


static func _normalize_bone_name(value: String) -> String:
	var normalized := value.to_lower()
	for separator in ["mixamorig", "bone", "def", "bip", "_", "-", ".", ":", " "]:
		normalized = normalized.replace(separator, "")
	if normalized.begins_with("b"):
		normalized = normalized.trim_prefix("b")
	return normalized


static func _match_score(value: String, aliases: Array) -> int:
	var score := -1
	for alias: String in aliases:
		if value == alias:
			score = maxi(score, 100)
		elif value.ends_with(alias):
			score = maxi(score, 90)
		elif value.contains(alias):
			score = maxi(score, 80)
	return score
