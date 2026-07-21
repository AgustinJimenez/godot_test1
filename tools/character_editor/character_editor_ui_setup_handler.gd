class_name CharacterEditorUiSetupHandler
extends RefCounted

## Panel/control setup and population: editor mode, camera mode buttons,
## panel resize/collapse, animation and attachment pickers, character
## selection. Holds a back-reference to the main CharacterEditor -
## extracted purely to keep character_editor.gd under a manageable size.

var editor: CharacterEditor

const TOGGLE_ON_COLOR := Color(0.22, 0.82, 0.42, 1.0)
const TOGGLE_OFF_COLOR := Color(0.95, 0.28, 0.3, 1.0)
const TOGGLE_ICON_SCALE := 1.45


func _init(editor_ref: CharacterEditor) -> void:
	editor = editor_ref


## Raw counts for "is this character heavy" - triangles/verts summed across
## every mesh part (not just body.mesh - several characters here are
## multi-part, e.g. Shambler's action_adventure_pack armor pieces), plus
## bone count and the source file's size on disk. Computed fresh on every
## load rather than cached: cheap (surface_get_arrays reads already-loaded
## mesh data, no re-import), and only ever needed once per character switch.
func _update_mesh_stats_label() -> void:
	var vertex_count := 0
	var triangle_count := 0
	for mesh_part in editor.body.meshes:
		if mesh_part == null or mesh_part.mesh == null:
			continue
		for surface in mesh_part.mesh.get_surface_count():
			var arrays := mesh_part.mesh.surface_get_arrays(surface)
			var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			vertex_count += verts.size()
			var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
			triangle_count += (indices.size() / 3) if not indices.is_empty() else (verts.size() / 3)
	var file_size := 0
	if not editor.body.model_path.is_empty():
		var file := FileAccess.open(editor.body.model_path, FileAccess.READ)
		if file != null:
			file_size = file.get_length()
	# Visibility itself is stage-gated (see character_editor_stage_handler.gd's
	# Stage.CHARACTER branch) - only the Character tab shows this panel. This
	# just keeps the values current whenever a character (re)loads, so
	# they're already right by the time that tab is shown.
	var grid := editor.mesh_stats_panel.get_node(^"Grid")
	(grid.get_node(^"TrianglesValue") as Label).text = "%d" % triangle_count
	(grid.get_node(^"VertsValue") as Label).text = "%d" % vertex_count
	(grid.get_node(^"MeshPartsValue") as Label).text = str(editor.body.meshes.size())
	(grid.get_node(^"BonesValue") as Label).text = str(editor.body.skeleton.get_bone_count())
	(grid.get_node(^"FileSizeValue") as Label).text = String.humanize_size(file_size)


func _update_responsive_layout() -> void:
	var viewport_size := editor.get_viewport().get_visible_rect().size
	editor._ui_scale = clampf(viewport_size.y / editor.BASE_UI_HEIGHT, 1.0, editor.MAX_UI_SCALE)
	editor.ui_layer.transform = Transform2D.IDENTITY.scaled(Vector2.ONE * editor._ui_scale)
	var logical_viewport_size := viewport_size / editor._ui_scale
	var panel_width := clampf(
			logical_viewport_size.x * editor.PANEL_WIDTH_RATIO,
			editor.MIN_PANEL_WIDTH,
			editor.MAX_PANEL_WIDTH)
	var panel_height := clampf(
			logical_viewport_size.y - 32.0,
			editor.MIN_PANEL_HEIGHT,
			editor.MAX_PANEL_HEIGHT)
	if not editor._panel_user_layout:
		editor.panel.position = Vector2(16.0, 16.0)
		editor.panel.size = Vector2(panel_width, panel_height)
		editor._expanded_panel_size = editor.panel.size
	else:
		_clamp_panel_to_viewport(logical_viewport_size)
	# The empty-state message belongs to the unused panel workspace below the
	# character controls. It lives outside PanelScroll so it can stay centered
	# without adding artificial scrollable content.
	var empty_margin := 24.0
	var empty_top := editor.panel.position.y + 178.0
	editor.empty_state.position = Vector2(
			editor.panel.position.x + empty_margin,
			empty_top)
	editor.empty_state.size = Vector2(
			maxf(editor.panel.size.x - empty_margin * 2.0, 1.0),
			maxf(editor.panel.position.y + editor.panel.size.y - empty_top - empty_margin, 1.0))
	editor.viewport_toolbar.position = Vector2(
			logical_viewport_size.x - editor.viewport_toolbar.size.x - 16.0,
			16.0)
	editor.playback_toolbar.position = Vector2(
			logical_viewport_size.x - editor.playback_toolbar.size.x - 16.0,
			logical_viewport_size.y - editor.playback_toolbar.size.y - 16.0)
	if editor._rig_handler != null:
		editor._rig_handler.update_reference_layout(logical_viewport_size)
	_update_panel_dependent_layout()
	_update_panel_resize_handle()


func _clamp_panel_to_viewport(logical_viewport_size: Vector2) -> void:
	var max_position := Vector2(
			maxf(16.0, logical_viewport_size.x - 240.0),
			maxf(16.0, logical_viewport_size.y - editor.COLLAPSED_PANEL_HEIGHT))
	editor.panel.position = editor.panel.position.clamp(Vector2(0.0, 0.0), max_position)
	var available_size := logical_viewport_size - editor.panel.position - Vector2(8.0, 8.0)
	if editor._panel_collapsed:
		editor.panel.size.y = editor.COLLAPSED_PANEL_HEIGHT
		editor.panel.size.x = minf(editor.panel.size.x, available_size.x)
	else:
		editor.panel.size = Vector2(
				clampf(editor.panel.size.x, minf(editor.MIN_USER_PANEL_SIZE.x, available_size.x),
						available_size.x),
				clampf(editor.panel.size.y, minf(editor.MIN_USER_PANEL_SIZE.y, available_size.y),
						available_size.y))
		editor._expanded_panel_size = editor.panel.size


func _update_panel_dependent_layout() -> void:
	if not editor._panel_collapsed:
		editor.bone_scroll.custom_minimum_size.y = editor.MIN_BONE_SCROLL_HEIGHT + maxf(
				editor.panel.size.y - editor.MIN_PANEL_HEIGHT, 0.0)


func _update_panel_resize_handle() -> void:
	editor.panel_resize_handle.visible = not editor._panel_collapsed
	editor.panel_resize_handle.position = (
			editor.panel.position + editor.panel.size - editor.panel_resize_handle.size)


func _setup_controls() -> void:
	_style_binary_toggles()
	editor.character_picker.add_item("Select character...")
	editor.character_picker.set_item_metadata(0, "")
	for kind in editor.CHARACTER_KINDS:
		var built_in_info: Dictionary = editor._custom_characters.get(kind, {})
		editor.character_picker.add_item(
				built_in_info.get("display_name", kind.capitalize()))
		editor.character_picker.set_item_metadata(editor.character_picker.item_count - 1, kind)
	for kind: String in editor._custom_characters:
		# "builtin_"-prefixed entries are CharacterCatalog's mirror of an
		# ALREADY-listed CHARACTER_KINDS entry (see CATALOG's own doc comment
		# on that prefix) - they exist for the game's debug-menu character
		# swap (PlayerBody.swap_character), not as a second, confusingly
		# identical-looking option in this picker. Without this skip, e.g.
		# "X Bot" appeared twice - once via MixamoCharacterAdapter (this
		# tool's own posing/animation path, Rig tab shows just a summary
		# line) and once via the catalog's own humanoid_map (Rig tab shows
		# the full bone-mapping controls) - same display name, materially
		# different behavior, no visual way to tell them apart. A real
		# session-imported character still gets its own entry here: those
		# use a "custom_"-prefixed kind_id instead (see
		# character_editor_import_handler.gd's _import_character).
		if kind in editor.CHARACTER_KINDS or kind.begins_with("builtin_"):
			continue
		var info: Dictionary = editor._custom_characters[kind]
		editor.character_picker.add_item(info.get("display_name", kind.capitalize()))
		editor.character_picker.set_item_metadata(editor.character_picker.item_count - 1, kind)
	editor.character_picker.item_selected.connect(_on_character_selected)
	_setup_animation_controls()
	_setup_attachment_controls()
	editor.edit_mode_button.pressed.connect(_on_editor_mode_pressed.bind(false))
	editor.compare_mode_button.pressed.connect(_on_editor_mode_pressed.bind(true))
	editor.view_picker.add_item("Full body")
	editor.view_picker.add_item("Attachment close-up")
	editor.view_picker.add_item("Isolated attachment")
	editor.view_picker.item_selected.connect(editor._camera_handler._on_view_selected)
	editor.pause_toggle.toggled.connect(editor._camera_handler._on_pause_toggled)
	editor.show_bones_toggle.toggled.connect(editor._gizmo_handler._on_show_bones_toggled)
	editor.free_camera_toggle.toggled.connect(editor._camera_handler._on_free_camera_toggled)
	editor.root_motion_toggle.toggled.connect(editor._camera_handler._on_root_motion_toggled)
	editor.orbit_camera_button.pressed.connect(_on_camera_mode_pressed.bind(editor.CAMERA_MODE_ORBIT))
	editor.move_camera_button.pressed.connect(_on_camera_mode_pressed.bind(editor.CAMERA_MODE_MOVE))
	editor.zoom_out_button.pressed.connect(_on_zoom_out_pressed)
	editor.zoom_in_button.pressed.connect(_on_zoom_in_pressed)
	editor.reset_view_button.pressed.connect(_on_reset_camera_view_pressed)
	editor.collapse_panel_button.pressed.connect(_on_collapse_panel_pressed)
	editor.title_bar.gui_input.connect(_on_title_bar_gui_input)
	editor.panel_resize_handle.gui_input.connect(_on_panel_resize_handle_gui_input)
	for axis in 3:
		editor.axis_ring_toggles[axis].toggled.connect(
				editor._gizmo_handler._on_axis_ring_toggled.bind(axis))
	# _populate_bone_controls() and _sync_object_controls() are NOT called
	# here - both touch body/_held_object, which don't exist yet until
	# _load_character() runs (right after _setup_controls(), including for
	# the very first character load). _load_character() calls both itself.
	for axis in 3:
		editor.position_sliders[axis].value_changed.connect(
				editor._gizmo_handler._on_object_position_changed.bind(axis))
		editor.rotation_sliders[axis].value_changed.connect(
				editor._gizmo_handler._on_object_rotation_changed.bind(axis))
		_color_axis_slider(editor.position_sliders[axis], editor.position_values[axis], axis)
		_color_axis_slider(editor.rotation_sliders[axis], editor.rotation_values[axis], axis)
	editor.scale_slider.value_changed.connect(editor._gizmo_handler._on_object_scale_changed)
	editor.preset_path_field.text = editor._current_pose_path
	_update_camera_mode_buttons()
	_update_editor_mode_buttons()
	# These 16 used to be wired as scene-file (.tscn [connection]) signals
	# pointing "to=. method=_on_x_pressed" - i.e. calling a method directly
	# on the root CharacterEditor node. Moving their handler functions out
	# to component objects (this whole file's worth of extraction) silently
	# broke every one of them: the scene-file connections still existed,
	# still fired, but called a method name that no longer exists on the
	# root - Import Character's dialog simply never opened, with no error
	# visible anywhere I was testing from (the MCP bridge always called
	# component methods directly, never through the actual button-click ->
	# scene-signal path). Reconnecting all of them here, in code, instead of
	# leaving them as invisible-to-grep .tscn resource data - the matching
	# [connection] blocks were removed from character_editor.tscn.
	editor.get_node(^"UI/Panel/PanelScroll/Margin/VBox/BoneButtons/ResetBone").pressed.connect(
			editor._bone_controls_handler._on_reset_bone_pressed)
	editor.get_node(^"UI/Panel/PanelScroll/Margin/VBox/BoneButtons/ResetAll").pressed.connect(
			editor._bone_controls_handler._on_reset_all_pressed)
	editor.get_node(^"UI/Panel/PanelScroll/Margin/VBox/ObjectRow/BrowseObject").pressed.connect(
			editor._pose_io_handler._on_browse_object_pressed)
	editor.get_node(^"UI/Panel/PanelScroll/Margin/VBox/PresetRow/NewPreset").pressed.connect(
			editor._pose_io_handler._on_new_preset_pressed)
	editor.get_node(^"UI/Panel/PanelScroll/Margin/VBox/PresetRow/OpenPreset").pressed.connect(
			editor._pose_io_handler._on_open_preset_pressed)
	editor.get_node(^"UI/Panel/PanelScroll/Margin/VBox/PresetRow/SavePresetAs").pressed.connect(
			editor._pose_io_handler._on_save_preset_as_pressed)
	editor.save_pose_button.pressed.connect(editor._pose_io_handler._on_save_pose_pressed)
	editor.load_pose_button.pressed.connect(editor._pose_io_handler._on_load_pose_pressed)
	editor.get_node(^"UI/Panel/PanelScroll/Margin/VBox/PoseActions/SaveImage").pressed.connect(
			editor._pose_io_handler._on_save_image_pressed)
	editor.get_node(^"UI/Panel/PanelScroll/Margin/VBox/PoseActions/Copy").pressed.connect(
			editor._pose_io_handler._on_copy_pressed)
	editor.import_character_button.pressed.connect(
			editor._import_handler._on_import_character_pressed)
	editor.import_animation_button.pressed.connect(
			editor._import_handler._on_import_animation_pressed)
	editor.object_dialog.file_selected.connect(editor._pose_io_handler._on_object_file_selected)
	editor.open_preset_dialog.file_selected.connect(editor._pose_io_handler._on_preset_file_selected)
	editor.save_preset_dialog.file_selected.connect(
			editor._pose_io_handler._on_save_preset_file_selected)
	editor.import_dialog.file_selected.connect(editor._import_handler._on_import_file_selected)


func _style_binary_toggles() -> void:
	var toggle_nodes: Array[Node] = editor.panel.find_children("*", "CheckButton", true, false)
	if toggle_nodes.is_empty():
		return
	var source_toggle := toggle_nodes[0] as CheckButton
	var scaled_icons: Dictionary = {}
	var icon_names: Array[StringName] = [
		&"checked",
		&"unchecked",
		&"checked_disabled",
		&"unchecked_disabled",
		&"checked_mirrored",
		&"unchecked_mirrored",
		&"checked_disabled_mirrored",
		&"unchecked_disabled_mirrored",
	]
	for icon_name in icon_names:
		var source_icon := source_toggle.get_theme_icon(icon_name, &"CheckButton")
		if source_icon == null:
			continue
		var image := source_icon.get_image()
		if image == null or image.is_empty():
			continue
		image.resize(
				maxi(roundi(image.get_width() * TOGGLE_ICON_SCALE), 1),
				maxi(roundi(image.get_height() * TOGGLE_ICON_SCALE), 1),
				Image.INTERPOLATE_LANCZOS)
		scaled_icons[icon_name] = ImageTexture.create_from_image(image)
	for node in toggle_nodes:
		var toggle := node as CheckButton
		toggle.custom_minimum_size.y = maxf(toggle.custom_minimum_size.y, 42.0)
		toggle.add_theme_color_override(&"button_checked_color", TOGGLE_ON_COLOR)
		toggle.add_theme_color_override(&"button_unchecked_color", TOGGLE_OFF_COLOR)
		for icon_name in scaled_icons:
			toggle.add_theme_icon_override(icon_name, scaled_icons[icon_name])


func _on_editor_mode_pressed(compare_enabled: bool) -> void:
	if editor.body == null or not editor.body.supports_comparison:
		return
	editor.view_picker.select(0)
	editor.view_picker.disabled = compare_enabled
	if (editor.body.supports_isolated_attachment
			and editor.body.mesh != null and editor._full_body_mesh != null):
		editor.body.mesh.mesh = editor._full_body_mesh
	editor._joint_focus_active = false
	editor._orbiting = false
	editor._orbiting_joint = false
	var comparison_status: String = editor._comparison.set_enabled(
			compare_enabled, editor._current_animation)
	editor._comparison.set_paused(editor.pause_toggle.button_pressed)
	_update_editor_mode_buttons()
	editor._camera_handler._frame_full_body()
	editor.status_label.text = comparison_status


func _update_editor_mode_buttons() -> void:
	editor.edit_mode_button.set_pressed_no_signal(not editor._comparison.enabled)
	editor.compare_mode_button.set_pressed_no_signal(editor._comparison.enabled)


func _on_camera_mode_pressed(mode: int) -> void:
	editor._camera_mode = mode
	editor._captured = false
	editor._orbiting = false
	editor._orbiting_joint = false
	editor._camera_handler._end_camera_move()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if editor.free_camera_toggle.button_pressed:
		editor.free_camera_toggle.set_pressed_no_signal(false)
	_update_camera_mode_buttons()
	editor.status_label.text = ""


func _update_camera_mode_buttons() -> void:
	editor.orbit_camera_button.set_pressed_no_signal(editor._camera_mode == editor.CAMERA_MODE_ORBIT)
	editor.move_camera_button.set_pressed_no_signal(editor._camera_mode == editor.CAMERA_MODE_MOVE)


func _on_zoom_out_pressed() -> void:
	editor._camera_handler._apply_camera_zoom(1.0 / editor.ZOOM_STEP)


func _on_zoom_in_pressed() -> void:
	editor._camera_handler._apply_camera_zoom(editor.ZOOM_STEP)


func _on_reset_camera_view_pressed() -> void:
	editor.view_picker.select(0)
	editor._camera_handler._on_view_selected(0)
	editor.status_label.text = ""


func _on_collapse_panel_pressed() -> void:
	editor._panel_collapsed = not editor._panel_collapsed
	editor._panel_user_layout = true
	if editor._panel_collapsed:
		editor._expanded_panel_size = editor.panel.size
	for child in editor.panel_vbox.get_children():
		if child != editor.title_bar:
			(child as Control).visible = not editor._panel_collapsed
	editor.collapse_panel_button.icon = (
			editor.EXPAND_ICON if editor._panel_collapsed else editor.COLLAPSE_ICON)
	editor.collapse_panel_button.tooltip_text = (
			"Restore panel" if editor._panel_collapsed else "Minimize panel")
	if editor._panel_collapsed:
		editor.panel.size.y = editor.COLLAPSED_PANEL_HEIGHT
	else:
		editor.panel.size = editor._expanded_panel_size
		editor._stage_handler.refresh()
	_update_panel_dependent_layout()
	_update_panel_resize_handle()


func _on_title_bar_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		editor._dragging_panel = event.pressed
		if event.pressed:
			editor._panel_user_layout = true
	elif event is InputEventMouseMotion and editor._dragging_panel:
		editor.panel.position += event.relative / editor._ui_scale
		_clamp_panel_to_viewport(editor.get_viewport().get_visible_rect().size / editor._ui_scale)
		_update_panel_resize_handle()


func _on_panel_resize_handle_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		editor._resizing_panel = event.pressed
		if event.pressed:
			editor._panel_user_layout = true
	elif event is InputEventMouseMotion and editor._resizing_panel:
		var logical_viewport_size := editor.get_viewport().get_visible_rect().size / editor._ui_scale
		var available_size := logical_viewport_size - editor.panel.position - Vector2(8.0, 8.0)
		var desired_size: Vector2 = editor.panel.size + event.relative / editor._ui_scale
		desired_size = Vector2(
				clampf(desired_size.x, minf(editor.MIN_USER_PANEL_SIZE.x, available_size.x),
						available_size.x),
				clampf(desired_size.y, minf(editor.MIN_USER_PANEL_SIZE.y, available_size.y),
						available_size.y))
		editor.bone_scroll.custom_minimum_size.y = editor.MIN_BONE_SCROLL_HEIGHT + maxf(
				desired_size.y - editor.MIN_PANEL_HEIGHT, 0.0)
		editor.panel.size = desired_size
		editor._expanded_panel_size = editor.panel.size
		_update_panel_resize_handle()


func _color_axis_slider(slider: HSlider, value_label: Label, axis: int) -> void:
	var axis_color: Color = editor.AXIS_COLORS[axis]
	slider.modulate = axis_color
	value_label.add_theme_color_override(&"font_color", axis_color)
	var axis_label := slider.get_parent().get_node_or_null("Axis") as Label
	if axis_label != null:
		axis_label.add_theme_color_override(&"font_color", axis_color)


func _setup_animation_controls() -> void:
	# One-time signal wiring only - unlike _populate_animation_controls(),
	# which needs body to exist and is called by _load_character() instead,
	# including for the very first character load.
	editor.animation_group_picker.item_selected.connect(_on_animation_group_selected)
	editor.animation_picker.item_selected.connect(_on_animation_selected)


## Re-run on every character switch (unlike _setup_animation_controls, which
## wires signals exactly once) - the animation groups and current animation
## are entirely character-specific.
func _populate_animation_controls() -> void:
	editor.animation_group_picker.clear()
	editor.animation_group_picker.add_item("Select animation package...")
	editor.animation_group_picker.set_item_metadata(0, &"")
	editor._animation_groups = editor.body.get_animation_groups()
	editor._animation_groups[&"Base Pose"] = [&""]
	var package_groups := editor._animation_package_handler.groups()
	for package_name: StringName in package_groups:
		editor._animation_groups[package_name] = package_groups[package_name]
	for group_name in editor._animation_groups:
		editor.animation_group_picker.add_item(String(group_name))
		editor.animation_group_picker.set_item_metadata(
				editor.animation_group_picker.item_count - 1, StringName(group_name))
	if not _animation_exists_in_groups(editor._current_animation):
		editor._current_animation = &""
	editor.animation_group_picker.select(0)
	editor.animation_picker.clear()
	editor.animation_picker.hide()
	if editor._current_animation != &"":
		_select_animation_in_ui(editor._current_animation)
	_set_animation(editor._current_animation)


func _animation_exists_in_groups(animation_name: StringName) -> bool:
	for group_name in editor._animation_groups:
		if animation_name in editor._animation_groups.get(group_name, []):
			return true
	return false


func _setup_attachment_controls() -> void:
	# One-time signal wiring only - see _setup_animation_controls().
	editor.attachment_picker.item_selected.connect(_on_attachment_selected)


## Re-run on every character switch - the attachment bone list is
## character-specific (different skeletons, different bone names).
func _populate_attachment_controls() -> void:
	editor.attachment_picker.clear()
	for bone_index in editor.body.skeleton.get_bone_count():
		var bone_name := editor.body.skeleton.get_bone_name(bone_index)
		editor.attachment_picker.add_item(String(bone_name))
		editor.attachment_picker.set_item_metadata(editor.attachment_picker.item_count - 1, bone_name)
	if (editor.body.skeleton.find_bone(editor._attachment_bone) < 0
			and editor.body.skeleton.get_bone_count() > 0):
		editor._attachment_bone = editor.body.skeleton.get_bone_name(0)
	_select_attachment_in_ui(editor._attachment_bone)
	editor._isolated_attachment_mesh = (
			editor._build_isolated_attachment_mesh()
			if editor.body.supports_isolated_attachment else null)


func _on_character_selected(index: int) -> void:
	var kind: String = editor.character_picker.get_item_metadata(index)
	if kind.is_empty():
		editor._unload_character()
		return
	if kind != editor._character_kind:
		editor._load_character(kind)


func _select_character_in_ui(kind: String) -> void:
	for index in editor.character_picker.item_count:
		if editor.character_picker.get_item_metadata(index) == kind:
			editor.character_picker.select(index)
			return


func _on_animation_group_selected(index: int) -> void:
	var group_name: StringName = editor.animation_group_picker.get_item_metadata(index)
	editor._animation_package_handler.select_group(group_name)
	if group_name == &"":
		editor.animation_picker.clear()
		editor.animation_picker.hide()
		_set_animation(&"")
		return
	editor._animation_package_handler.ensure_group_loaded(group_name)
	_populate_animation_picker(group_name)
	_set_animation(&"")


func _populate_animation_picker(group_name: StringName) -> void:
	editor.animation_picker.clear()
	editor.animation_picker.show()
	var animations: Array = editor._animation_groups.get(group_name, [])
	if group_name != &"Base Pose":
		editor.animation_picker.add_item("No animation")
		editor.animation_picker.set_item_metadata(0, &"")
	for animation_name in animations:
		var display_name := (
				"Base pose" if StringName(animation_name) == &""
				else editor._animation_package_handler.animation_display_name(animation_name))
		editor.animation_picker.add_item(display_name)
		editor.animation_picker.set_item_metadata(
				editor.animation_picker.item_count - 1, StringName(animation_name))


func _on_animation_selected(index: int) -> void:
	_set_animation(editor.animation_picker.get_item_metadata(index))


func reset_animation_state() -> void:
	editor.animation_group_picker.select(0)
	editor.animation_picker.clear()
	editor.animation_picker.hide()
	editor._animation_package_handler.select_group(&"")
	_set_animation(&"")


func _set_animation(animation_name: StringName) -> void:
	var previous_animation := editor._current_animation
	editor._current_animation = animation_name
	editor.body.node.position = editor.CHARACTER_SPAWN_POSITION
	if animation_name == &"":
		editor.pause_toggle.set_pressed_no_signal(false)
		editor.pause_toggle.disabled = true
		editor.root_motion_toggle.disabled = true
		if previous_animation != &"":
			editor.body.anim_player.stop()
		editor.body.skeleton.reset_bone_poses()
		editor.body.skeleton.advance(0.0)
		if editor._comparison.enabled:
			_on_editor_mode_pressed(false)
		editor.status_label.text = ""
		editor._animation_transport.refresh()
		return
	editor.pause_toggle.disabled = false
	editor.root_motion_toggle.disabled = false
	var custom_path := "custom/" + String(animation_name)
	if editor.body.anim_player.has_animation(custom_path):
		editor.body.anim_player.play(custom_path, 0.0)
	else:
		editor.body.play_debug_anim(animation_name, 0.0)
	var comparison_status: String = editor._comparison.play_animation(animation_name)
	if editor.pause_toggle.button_pressed:
		editor.body.anim_player.pause()
		editor._comparison.set_paused(true)
	editor.status_label.text = comparison_status
	editor._animation_transport.refresh()


func _select_animation_in_ui(animation_name: StringName) -> void:
	for group_index in editor.animation_group_picker.item_count:
		var group_name: StringName = editor.animation_group_picker.get_item_metadata(group_index)
		if animation_name in editor._animation_groups.get(group_name, []):
			editor.animation_group_picker.select(group_index)
			_populate_animation_picker(group_name)
			for animation_index in editor.animation_picker.item_count:
				if editor.animation_picker.get_item_metadata(animation_index) == animation_name:
					editor.animation_picker.select(animation_index)
					return


func _on_attachment_selected(index: int) -> void:
	_set_attachment_bone(editor.attachment_picker.get_item_metadata(index), true)


func _set_attachment_bone(bone_name: StringName, update_view: bool) -> void:
	if editor.body.skeleton.find_bone(bone_name) < 0:
		return
	if not is_instance_valid(editor._object_attachment):
		return
	editor._attachment_bone = bone_name
	editor._object_attachment.bone_name = bone_name
	editor._attachment_handler.sync_selected_bone(bone_name)
	editor._isolated_attachment_mesh = editor._build_isolated_attachment_mesh()
	if update_view and editor.view_picker.selected == 2:
		editor.body.mesh.mesh = (editor._isolated_attachment_mesh
				if editor._isolated_attachment_mesh != null else editor._full_body_mesh)
	if update_view and editor.view_picker.selected != 0:
		editor._camera_handler._frame_attachment()
	editor.status_label.text = "Object attached to %s" % bone_name


func _select_attachment_in_ui(bone_name: StringName) -> void:
	for index in editor.attachment_picker.item_count:
		if editor.attachment_picker.get_item_metadata(index) == bone_name:
			editor.attachment_picker.select(index)
			return
