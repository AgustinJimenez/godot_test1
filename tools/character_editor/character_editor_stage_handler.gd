class_name CharacterEditorStageHandler
extends RefCounted

## Progressive-disclosure workflow for the Character Editor panel.

enum Stage { CHARACTER, ANIMATION, ATTACHMENTS, POSE, REVIEW }

const CURRENT_STEP_COLOR := Color(0.96, 0.98, 1.0, 1.0)
const AVAILABLE_STEP_COLOR := Color(0.42, 0.76, 1.0, 1.0)
const VISITED_STEP_COLOR := Color(0.72, 0.8, 0.9, 1.0)
const DISABLED_STEP_COLOR := Color(0.38, 0.43, 0.5, 1.0)

var editor: CharacterEditor
var current := Stage.CHARACTER
var highest_unlocked := Stage.CHARACTER
var _controls: Array[Control] = []


func _init(editor_ref: CharacterEditor) -> void:
	editor = editor_ref


func setup() -> void:
	for index in editor.stage_buttons.size():
		editor.stage_buttons[index].pressed.connect(set_stage.bind(index))
	_controls = [
		editor.character_row,
		editor.animation_row,
		editor.editor_mode_row,
		editor.attachment_slots_row,
		editor.object_row,
		editor.attachment_row,
		editor.preset_row,
		editor.view_row,
		editor.display_options,
		editor.bone_section,
		editor.pose_helpers,
		editor.bone_scroll,
		editor.bone_buttons,
		editor.pose_actions,
	]
	_controls.append_array(editor.object_transform_controls)
	enter_empty()


func enter_empty() -> void:
	current = Stage.CHARACTER
	highest_unlocked = Stage.CHARACTER
	editor.viewport_toolbar.hide()
	_update()


func on_character_loaded() -> void:
	editor.empty_state.hide()
	editor.viewport_toolbar.show()
	current = Stage.CHARACTER
	highest_unlocked = Stage.ANIMATION
	_update()


func set_stage(stage: int, allow_locked: bool = false) -> void:
	if stage < Stage.CHARACTER or stage > Stage.REVIEW:
		return
	if stage != Stage.CHARACTER and editor.body == null:
		return
	if stage > highest_unlocked and not allow_locked:
		return
	if allow_locked:
		highest_unlocked = maxi(highest_unlocked, stage)
	current = stage
	if current < Stage.REVIEW:
		highest_unlocked = maxi(highest_unlocked, current + 1)
	_update()


func is_pose_stage() -> bool:
	return current == Stage.POSE


func refresh() -> void:
	_update()


func _update() -> void:
	for control: Control in _controls:
		control.hide()
	var is_empty := editor.body == null
	editor.empty_state.visible = (
			current == Stage.CHARACTER and is_empty and not editor._panel_collapsed)
	editor.status_label.visible = not is_empty and current != Stage.CHARACTER
	for button_index in editor.stage_buttons.size():
		var button := editor.stage_buttons[button_index]
		button.disabled = button_index > highest_unlocked
		button.set_pressed_no_signal(button_index == current)
		_style_stage_button(button, button_index)
	match current:
		Stage.CHARACTER:
			editor.character_row.show()
		Stage.ANIMATION:
			editor.animation_row.show()
			editor.editor_mode_row.show()
		Stage.ATTACHMENTS:
			editor.attachment_slots_row.show()
			editor.object_row.show()
			editor.attachment_row.show()
			for control: Control in editor.object_transform_controls:
				control.show()
		Stage.POSE:
			editor.bone_section.show()
			editor.bone_scroll.show()
			editor.bone_buttons.show()
			editor._bone_controls_handler._update_pose_helpers()
		Stage.REVIEW:
			editor.preset_row.show()
			editor.view_row.show()
			editor.pose_actions.show()
	_update_display_options()


func _style_stage_button(button: Button, button_index: int) -> void:
	var color := VISITED_STEP_COLOR
	if button.disabled:
		color = DISABLED_STEP_COLOR
	elif button_index == current:
		color = CURRENT_STEP_COLOR
	elif button_index == current + 1:
		color = AVAILABLE_STEP_COLOR
	button.add_theme_color_override(&"font_color", color)
	button.add_theme_color_override(&"font_hover_color", color.lightened(0.12))
	button.add_theme_color_override(&"font_pressed_color", CURRENT_STEP_COLOR)
	button.add_theme_color_override(&"font_focus_color", color)
	button.add_theme_color_override(&"font_hover_pressed_color", CURRENT_STEP_COLOR)
	button.add_theme_color_override(&"font_disabled_color", DISABLED_STEP_COLOR)


func _update_display_options() -> void:
	var show_display := current in [Stage.ANIMATION, Stage.POSE, Stage.REVIEW]
	editor.display_options.visible = show_display
	editor.pause_toggle.visible = current in [Stage.ANIMATION, Stage.POSE, Stage.REVIEW]
	editor.root_motion_toggle.visible = current == Stage.ANIMATION
	editor.show_bones_toggle.visible = current == Stage.POSE
	editor.free_camera_toggle.visible = current == Stage.REVIEW
