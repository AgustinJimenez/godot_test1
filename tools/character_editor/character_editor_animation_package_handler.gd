class_name CharacterEditorAnimationPackageHandler
extends RefCounted

## Persistent package CRUD and lazy per-character retargeting.

const PACKAGE_DIRECTORY := "res://assets/animations/packages"
const MENU_CREATE := 0
const MENU_RENAME := 1
const MENU_DELETE := 2

var editor: CharacterEditor
var packages: Array[CharacterAnimationPackage] = []
var selected_package: CharacterAnimationPackage
var _package_paths: Dictionary = {}
var _clip_display_names: Dictionary = {}
var _dialog_mode := MENU_CREATE


func _init(editor_ref: CharacterEditor) -> void:
	editor = editor_ref


func setup() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(PACKAGE_DIRECTORY))
	_load_packages()
	var popup := editor.animation_package_menu.get_popup()
	popup.add_item("New package", MENU_CREATE)
	popup.add_item("Rename package", MENU_RENAME)
	popup.add_separator()
	popup.add_item("Delete package", MENU_DELETE)
	popup.id_pressed.connect(_on_menu_action)
	editor.animation_package_name_dialog.confirmed.connect(_on_name_confirmed)
	editor.animation_package_delete_dialog.confirmed.connect(_on_delete_confirmed)
	refresh_selection()


func groups() -> Dictionary:
	_clip_display_names.clear()
	var result := {}
	for package: CharacterAnimationPackage in packages:
		var clips: Array[StringName] = []
		for source_path: String in package.source_paths:
			var clip_name := clip_name_for_path(package, source_path)
			clips.append(clip_name)
			_clip_display_names[clip_name] = source_path.get_file().get_basename()
		result[StringName(package.display_name)] = clips
	return result


func animation_display_name(clip_name: StringName) -> String:
	return String(_clip_display_names.get(clip_name, clip_name))


func select_group(group_name: StringName) -> void:
	selected_package = _find_by_display_name(String(group_name))
	refresh_selection()


func refresh_selection() -> void:
	var editable := selected_package != null
	editor.import_animation_button.disabled = not editable or editor._import_in_progress
	var popup := editor.animation_package_menu.get_popup()
	popup.set_item_disabled(popup.get_item_index(MENU_RENAME), not editable)
	popup.set_item_disabled(popup.get_item_index(MENU_DELETE), not editable)


func selected_package_id() -> String:
	return selected_package.package_id if selected_package != null else ""


func add_source(source_path: String) -> StringName:
	if selected_package == null:
		return &""
	if source_path not in selected_package.source_paths:
		selected_package.source_paths.append(source_path)
		_save(selected_package)
	return clip_name_for_path(selected_package, source_path)


func ensure_group_loaded(group_name: StringName) -> void:
	var package := _find_by_display_name(String(group_name))
	if package == null:
		return
	var changed := false
	for source_path: String in package.source_paths:
		var clip_name := clip_name_for_path(package, source_path)
		if editor._custom_clips.has(clip_name):
			continue
		var animation := editor._import_handler.retarget_animation_source(source_path)
		if animation != null:
			editor._custom_clips[clip_name] = animation
			changed = true
	if changed:
		editor._import_handler.rebuild_custom_clip_library()


func clip_name_for_path(
		package: CharacterAnimationPackage, source_path: String) -> StringName:
	return StringName("%s__%s" % [
		package.package_id, source_path.get_file().get_basename().to_snake_case()])


func on_character_changed() -> void:
	selected_package = null
	refresh_selection()


func _load_packages() -> void:
	packages.clear()
	_package_paths.clear()
	for filename: String in DirAccess.get_files_at(PACKAGE_DIRECTORY):
		if not filename.ends_with(".tres"):
			continue
		var path := PACKAGE_DIRECTORY.path_join(filename)
		var resource := load(path)
		if resource is CharacterAnimationPackage:
			var package := resource as CharacterAnimationPackage
			if package.package_id.is_empty() or package.display_name.strip_edges().is_empty():
				continue
			packages.append(package)
			_package_paths[package.package_id] = path
	packages.sort_custom(func(a: CharacterAnimationPackage, b: CharacterAnimationPackage) -> bool:
		return a.display_name.naturalnocasecmp_to(b.display_name) < 0)


func _on_menu_action(action_id: int) -> void:
	match action_id:
		MENU_CREATE:
			_dialog_mode = MENU_CREATE
			_open_name_dialog("Create animation package", "")
		MENU_RENAME:
			if selected_package != null:
				_dialog_mode = MENU_RENAME
				_open_name_dialog("Rename animation package", selected_package.display_name)
		MENU_DELETE:
			if selected_package != null:
				editor.animation_package_delete_dialog.dialog_text = (
						"Delete package '%s'?\nImported source files will be kept."
						% selected_package.display_name)
				editor.animation_package_delete_dialog.popup_centered()


func _open_name_dialog(title: String, value: String) -> void:
	editor.animation_package_name_dialog.title = title
	editor.animation_package_name_field.text = value
	editor.animation_package_name_dialog.popup_centered()
	editor.animation_package_name_field.grab_focus.call_deferred()
	editor.animation_package_name_field.select_all.call_deferred()


func _on_name_confirmed() -> void:
	var name := editor.animation_package_name_field.text.strip_edges()
	if name.is_empty():
		editor.status_label.text = "Package name cannot be empty"
		return
	var existing := _find_by_display_name(name)
	if existing != null and existing != selected_package:
		editor.status_label.text = "An animation package named '%s' already exists" % name
		return
	if _is_reserved_name(name):
		editor.status_label.text = "'%s' is a read-only built-in package name" % name
		return
	if _dialog_mode == MENU_CREATE:
		_create(name)
	elif selected_package != null:
		selected_package.display_name = name
		_save(selected_package)
		_refresh_groups_and_select(name)
		editor.status_label.text = "Renamed animation package to %s" % name


func _create(name: String) -> void:
	var package := CharacterAnimationPackage.new()
	package.package_id = _unique_id(name.to_snake_case())
	package.display_name = name
	var path := PACKAGE_DIRECTORY.path_join(package.package_id + ".tres")
	packages.append(package)
	_package_paths[package.package_id] = path
	_save(package)
	packages.sort_custom(func(a: CharacterAnimationPackage, b: CharacterAnimationPackage) -> bool:
		return a.display_name.naturalnocasecmp_to(b.display_name) < 0)
	_refresh_groups_and_select(name)
	editor.status_label.text = "Created animation package %s" % name


func _on_delete_confirmed() -> void:
	if selected_package == null:
		return
	var deleted := selected_package
	var prefix := deleted.package_id + "__"
	if editor._current_animation.begins_with(prefix):
		editor._ui_setup_handler._set_animation(&"")
	for clip_name: StringName in editor._custom_clips.keys():
		if String(clip_name).begins_with(prefix):
			editor._custom_clips.erase(clip_name)
	editor._import_handler.rebuild_custom_clip_library()
	packages.erase(deleted)
	var path := String(_package_paths.get(deleted.package_id, ""))
	_package_paths.erase(deleted.package_id)
	if not path.is_empty():
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	selected_package = null
	editor._ui_setup_handler._populate_animation_controls()
	editor.status_label.text = "Deleted package %s; source files were kept" % deleted.display_name


func _refresh_groups_and_select(group_name: String) -> void:
	editor._ui_setup_handler._populate_animation_controls()
	for index in editor.animation_group_picker.item_count:
		if String(editor.animation_group_picker.get_item_metadata(index)) == group_name:
			editor.animation_group_picker.select(index)
			editor._ui_setup_handler._on_animation_group_selected(index)
			return


func _save(package: CharacterAnimationPackage) -> void:
	var path := String(_package_paths.get(package.package_id, ""))
	var error := ResourceSaver.save(package, path)
	if error != OK:
		editor.status_label.text = "Could not save package: %s" % error_string(error)


func _find_by_display_name(name: String) -> CharacterAnimationPackage:
	for package: CharacterAnimationPackage in packages:
		if package.display_name == name:
			return package
	return null


func _is_reserved_name(name: String) -> bool:
	if name == "Base Pose" or editor.body == null:
		return name == "Base Pose"
	return StringName(name) in editor.body.get_animation_groups()


func _unique_id(candidate: String) -> String:
	var base := candidate if not candidate.is_empty() else "animation_package"
	var result := base
	var suffix := 2
	while _package_paths.has(result):
		result = "%s_%d" % [base, suffix]
		suffix += 1
	return result
