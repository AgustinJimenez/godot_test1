class_name CharacterEditorAnimationTransport
extends RefCounted

## Viewport animation transport shared by edit and comparison playback.

const FRAME_STEP := 1.0 / 60.0

var editor: CharacterEditor
var _dragging := false
var _resume_after_drag := false


func _init(editor_ref: CharacterEditor) -> void:
	editor = editor_ref


func setup() -> void:
	editor.playback_button.pressed.connect(_on_playback_pressed)
	editor.playback_slider.drag_started.connect(_on_drag_started)
	editor.playback_slider.drag_ended.connect(_on_drag_ended)
	editor.playback_slider.value_changed.connect(_on_timeline_changed)
	editor.playback_slider.step = FRAME_STEP
	editor.playback_toolbar.hide()


func update() -> void:
	if editor.body == null or editor._current_animation == &"":
		editor.playback_toolbar.hide()
		return
	var player := editor.body.anim_player
	var length := player.current_animation_length
	if length <= 0.0:
		editor.playback_toolbar.hide()
		return
	editor.playback_toolbar.show()
	editor.playback_slider.max_value = length
	if not _dragging:
		editor.playback_slider.set_value_no_signal(
				clampf(player.current_animation_position, 0.0, length))
	_update_time_label(editor.playback_slider.value, length)
	_update_playback_icon()


func refresh() -> void:
	_dragging = false
	_resume_after_drag = false
	update()


func _on_playback_pressed() -> void:
	if editor.body == null or editor._current_animation == &"":
		return
	var should_pause := not editor.pause_toggle.button_pressed
	if not should_pause:
		var player := editor.body.anim_player
		if player.current_animation_position >= player.current_animation_length - FRAME_STEP:
			_seek(0.0)
	editor.pause_toggle.set_pressed_no_signal(should_pause)
	editor._camera_handler._on_pause_toggled(should_pause)
	_update_playback_icon()


func _on_drag_started() -> void:
	if editor.body == null or editor._current_animation == &"":
		return
	_dragging = true
	_resume_after_drag = not editor.pause_toggle.button_pressed
	if _resume_after_drag:
		editor.pause_toggle.set_pressed_no_signal(true)
		editor._camera_handler._on_pause_toggled(true)


func _on_drag_ended(_value_changed: bool) -> void:
	if not _dragging:
		return
	_dragging = false
	if _resume_after_drag:
		editor.pause_toggle.set_pressed_no_signal(false)
		editor._camera_handler._on_pause_toggled(false)
	_resume_after_drag = false
	_update_playback_icon()


func _on_timeline_changed(value: float) -> void:
	if not _dragging:
		return
	_seek(value)
	_update_time_label(value, editor.playback_slider.max_value)


func _seek(time: float) -> void:
	editor.body.anim_player.seek(time, true)
	editor._comparison.seek(time)
	editor.body.skeleton.advance(0.0)


func _update_playback_icon() -> void:
	var paused := editor.pause_toggle.button_pressed
	editor.playback_button.icon = editor.play_icon if paused else editor.pause_icon
	editor.playback_button.tooltip_text = "Play animation" if paused else "Pause animation"


func _update_time_label(position: float, length: float) -> void:
	editor.playback_time_label.text = "%s / %s" % [_format_time(position), _format_time(length)]


func _format_time(seconds: float) -> String:
	var whole_seconds := floori(maxf(seconds, 0.0))
	var centiseconds := floori(fposmod(seconds, 1.0) * 100.0)
	return "%02d:%02d.%02d" % [whole_seconds / 60, whole_seconds % 60, centiseconds]
