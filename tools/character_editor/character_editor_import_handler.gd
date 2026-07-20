class_name CharacterEditorImportHandler
extends RefCounted

## "Import Character..."/"Import Animation..." feature: native file
## picker, editor round-trip (copy + reimport over the live MCP bridge),
## bone-prefix auto-detection. Holds a back-reference to the main
## CharacterEditor - extracted purely to keep character_editor.gd under
## a manageable size.

var editor: CharacterEditor

const RIG_HANDLER := preload("res://tools/character_editor/character_editor_rig_handler.gd")


func _init(editor_ref: CharacterEditor) -> void:
	editor = editor_ref


func _on_import_character_pressed() -> void:
	editor._import_mode = editor.ImportMode.CHARACTER
	_open_import_dialog("Import character")


func _on_import_animation_pressed() -> void:
	if editor._animation_package_handler.selected_package == null:
		editor.status_label.text = "Create or select a user animation package before importing"
		return
	editor._import_mode = editor.ImportMode.ANIMATION
	_open_import_dialog("Import animation into %s" %
			editor._animation_package_handler.selected_package.display_name)


## FileDialog's own use_native_dialog property has a real history of not
## actually invoking the OS picker in various Godot versions (see e.g.
## godotengine/godot#82531) - calling DisplayServer.file_dialog_show()
## directly sidesteps that wrapper entirely and is what actually opens
## Finder's real file picker on macOS. Falls back to the Godot-drawn
## FileDialog node on any platform/build that doesn't report native
## support at all (has_feature check), so this still works everywhere.
func _open_import_dialog(title: String) -> void:
	if DisplayServer.has_feature(DisplayServer.FEATURE_NATIVE_DIALOG_FILE):
		var err := DisplayServer.file_dialog_show(
				title, "", "", false, DisplayServer.FILE_DIALOG_MODE_OPEN_FILE,
				PackedStringArray(["*.fbx,*.glb,*.gltf ; 3D models and animations"]),
				_on_native_import_file_selected)
		if err != OK:
			editor.status_label.text = (
					"Native file dialog failed (%s) - using built-in picker" % error_string(err))
			editor.import_dialog.title = title
			editor.import_dialog.popup_centered_ratio(0.82)
	else:
		editor.import_dialog.title = title
		editor.import_dialog.popup_centered_ratio(0.82)


func _on_native_import_file_selected(
		status: bool, selected_paths: PackedStringArray, _selected_filter_index: int) -> void:
	# The native OS picker (see _open_import_dialog) can close without
	# actually raising this window back to the front on macOS - DisplayServer
	# still reports window_is_focused()/window_can_draw() as true throughout
	# (confirmed via a live file-based log spanning the entire import, no
	# gaps), meaning the spinner genuinely is rendering the whole time; the
	# user just isn't looking at an on-top window, which reads identically
	# to a freeze. Forcing it to the front here is the fix, not anything
	# about the spinner's own update logic, which was never broken.
	DisplayServer.window_move_to_foreground(editor.get_window().get_window_id())
	if status and not selected_paths.is_empty():
		_on_import_file_selected(selected_paths[0])


func _on_import_file_selected(path: String) -> void:
	editor._import_in_progress = true
	editor.import_character_button.disabled = true
	editor.import_animation_button.disabled = true
	editor.status_label.text = "Importing %s... this may take a few seconds" % path.get_file()
	match editor._import_mode:
		editor.ImportMode.CHARACTER:
			await _import_character(path)
		editor.ImportMode.ANIMATION:
			await _import_animation(path)
	editor._import_in_progress = false
	editor.import_character_button.disabled = false
	editor._animation_package_handler.refresh_selection()


## Copies source_path into assets/models/imported_characters/, detects its
## skeleton's bone-name convention from its own bones (not assumed), and
## registers it as a new selectable character for this session. See
## _detect_bone_prefix's doc comment for what "detects" covers and what it
## doesn't.
func _import_character(source_path: String) -> void:
	var dest_path := (
			"res://assets/models/imported_characters/" + _sanitize_filename(source_path.get_file()))
	var result := await editor._mcp_handler._request_import_asset(source_path, dest_path)
	if not result.get("ok", false):
		editor.status_label.text = "Import failed: %s" % result.get("error", "unknown error")
		return
	var instance: Node = (load(dest_path) as PackedScene).instantiate()
	var new_skeleton: Skeleton3D = instance.find_child("Skeleton3D", true, false)
	var has_skeleton := new_skeleton != null and new_skeleton.get_bone_count() > 0
	var bone_prefix: Variant = (
			_detect_bone_prefix(new_skeleton)
			if has_skeleton else null)
	var has_skin := false
	for found: Node in instance.find_children("*", "MeshInstance3D", true, false):
		var found_mesh := found as MeshInstance3D
		if found_mesh.skin != null or not found_mesh.skeleton.is_empty():
			has_skin = true
			break
	var mapping: Dictionary = RIG_HANDLER.load_profile(dest_path)
	if mapping.is_empty() and has_skeleton:
		mapping = (
				RIG_HANDLER.auto_map(new_skeleton)
				if bone_prefix == null or bone_prefix == "B-"
				else RIG_HANDLER.full_map_from_prefix(new_skeleton, bone_prefix))
	instance.free()

	var kind_id := "custom_" + dest_path.get_file().get_basename().to_snake_case()
	var display_name := dest_path.get_file().get_basename()
	var character_info := {
		"kind_id": kind_id,
		"model_path": dest_path,
		"source_model_path": dest_path,
		"display_name": display_name,
		"bone_prefix": bone_prefix,
		"has_skin": has_skin,
		"humanoid_map": mapping,
	}
	editor._custom_characters[kind_id] = character_info
	editor._rig_handler.persist_character(
			character_info, dest_path.get_basename() + ".character.json")
	var picker_index := -1
	for item_index in editor.character_picker.item_count:
		if editor.character_picker.get_item_metadata(item_index) == kind_id:
			picker_index = item_index
			break
	if picker_index < 0:
		editor.character_picker.add_item(display_name)
		picker_index = editor.character_picker.item_count - 1
		editor.character_picker.set_item_metadata(picker_index, kind_id)
	else:
		editor.character_picker.set_item_text(picker_index, display_name)
	var convention_note := ""
	if not has_skeleton:
		convention_note = " (unrigged - complete the Rig step)"
	elif not has_skin:
		convention_note = " (skeleton has no skinned mesh - complete the Rig step)"
	elif not editor._rig_mapping_complete(mapping):
		convention_note = " (humanoid mapping required)"
	editor.status_label.text = "Imported %s%s" % [display_name, convention_note]
	editor._ui_setup_handler._on_character_selected(picker_index)


## Copies source_path into a package folder under imported_animations/, detects its
## skeleton's bone-name convention, retargets its primary animation onto
## whichever character is currently loaded, and persists the source path in
## the selected CharacterAnimationPackage.
func _import_animation(source_path: String) -> void:
	var package_id := editor._animation_package_handler.selected_package_id()
	if package_id.is_empty():
		editor.status_label.text = "No user animation package selected"
		return
	var dest_path := (
			"res://assets/models/imported_animations/%s/%s" % [
				package_id, _sanitize_filename(source_path.get_file())])
	var result := await editor._mcp_handler._request_import_asset(source_path, dest_path)
	if not result.get("ok", false):
		editor.status_label.text = "Import failed: %s" % result.get("error", "unknown error")
		return
	var retargeted := retarget_animation_source(dest_path)
	if retargeted == null:
		return
	var clip_name := editor._animation_package_handler.add_source(dest_path)
	editor._custom_clips[clip_name] = retargeted
	rebuild_custom_clip_library()
	editor.status_label.text = "Imported %s into %s" % [
			dest_path.get_file(), editor._animation_package_handler.selected_package.display_name]
	editor._ui_setup_handler._populate_animation_controls()
	editor._animation_package_handler._refresh_groups_and_select(
			editor._animation_package_handler.selected_package.display_name)
	editor._ui_setup_handler._select_animation_in_ui(clip_name)
	editor._ui_setup_handler._set_animation(clip_name)


func retarget_animation_source(source_path: String) -> Animation:
	var resource := load(source_path)
	if not resource is PackedScene:
		editor.status_label.text = "Animation source is not an imported 3D scene: %s" % source_path
		return null
	var instance: Node = (resource as PackedScene).instantiate()
	var source_skeleton: Skeleton3D = instance.find_child("Skeleton3D", true, false)
	var clip_ap: AnimationPlayer = instance.find_child("AnimationPlayer", true, false)
	if source_skeleton == null or clip_ap == null:
		instance.free()
		editor.status_label.text = (
				"Import failed: %s has no Skeleton3D/AnimationPlayer" % source_path.get_file())
		return null
	var source_prefix: Variant = _detect_bone_prefix(source_skeleton)
	var src_animation := UniversalAnimationPools.find_primary_animation(clip_ap)
	if source_prefix == null or src_animation == null:
		instance.free()
		editor.status_label.text = ("Import failed: unrecognized skeleton or no animation found in %s "
				+ "- ask your assistant to add support for this rig") % source_path.get_file()
		return null

	var config: HumanoidRetargeter.BoneMapConfig
	if source_prefix.begins_with("B-"):
		config = RetargetedMixamoAdapter._bone_map_config(_current_bone_prefix())
	else:
		config = UniversalAnimationPools.mixamo_family_bone_map_config(
				source_prefix, _current_bone_prefix())
	var retargeted := HumanoidRetargeter.retarget_clip(
			source_skeleton, src_animation, editor.body.skeleton, config, true)
	instance.free()
	return retargeted


func rebuild_custom_clip_library() -> void:
	if editor.body.anim_player.is_playing():
		editor.body.anim_player.stop()
	if editor.body.anim_player.has_animation_library(&"custom"):
		editor.body.anim_player.remove_animation_library(&"custom")
	if editor._custom_clips.is_empty():
		return
	var lib := AnimationLibrary.new()
	for clip_name: StringName in editor._custom_clips:
		lib.add_animation(clip_name, editor._custom_clips[clip_name])
	editor.body.anim_player.add_animation_library(&"custom", lib)


## "" for MotusMan's bare names (only meaningful when body is the Player
## adapter), otherwise whatever prefix the currently loaded character's own
## bone 0 uses - covers plain "mixamorig_" characters, numbered ones, and
## custom-imported ones alike without needing to ask which adapter is active.
func _current_bone_prefix() -> String:
	if editor._character_kind == "player":
		return ""
	return (
			_detect_bone_prefix(editor.body.skeleton)
			if editor.body.skeleton.get_bone_count() > 0 else "")


## Mixamo-family rigs (the vast majority of what gets imported) all name
## their hip bone "<prefix>Hips" where prefix is "", "mixamorig_", or
## "mixamorig<N>_" for some number N - detected here by searching for
## whichever bone ends in "Hips" and taking what's left after stripping it,
## rather than assuming bone 0 specifically (PlayerBody's MotusMan has an
## extra non-Hips "Root" bone at index 0 - see _setup_root_motion_track's
## doc comment for the same issue in a different context). Human Basic
## Motions FREE-style rigs use "B-hips" instead - detected as a special
## case since it doesn't fit the "<prefix>Hips" pattern. Returns null for
## anything else: this only covers the two conventions this tool already
## knows how to retarget from, not truly arbitrary skeletons.
func _detect_bone_prefix(skeleton: Skeleton3D):
	for i in skeleton.get_bone_count():
		var name := skeleton.get_bone_name(i)
		if name == "B-hips":
			return "B-"
		if name.ends_with("Hips") and not name.begins_with("B-"):
			return name.substr(0, name.length() - "Hips".length())
	return null


func _sanitize_filename(filename: String) -> String:
	var sanitized := filename
	for bad_char in ["\"", ":", "?", "*", "<", ">", "|"]:
		sanitized = sanitized.replace(bad_char, "_")
	return sanitized


func _globalize_if_resource(path: String) -> String:
	if path.begins_with("res://") or path.begins_with("user://"):
		return ProjectSettings.globalize_path(path)
	return path
