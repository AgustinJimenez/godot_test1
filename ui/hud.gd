extends CanvasLayer
## Minimal HUD: interaction prompt, stamina bar (only while not full),
## and the note reader overlay (pauses the game while open).


@onready var prompt_label: Label = $PromptLabel
@onready var stamina_bar: ProgressBar = $StaminaBar
@onready var note_overlay: Control = $NoteOverlay
@onready var note_text: Label = $NoteOverlay/Center/Panel/Margin/VBox/NoteText


func _ready() -> void:
	add_to_group(&"hud")


func _unhandled_input(event: InputEvent) -> void:
	if note_overlay.visible and (event.is_action_pressed(&"interact")
			or event.is_action_pressed(&"pause")):
		note_overlay.hide()
		get_tree().paused = false
		get_viewport().set_input_as_handled()


func set_prompt(text: String) -> void:
	prompt_label.text = text
	prompt_label.visible = text != ""


func set_stamina(value: float, max_value: float) -> void:
	stamina_bar.max_value = max_value
	stamina_bar.value = value
	stamina_bar.visible = value < max_value - 0.01


func show_note(text: String) -> void:
	note_text.text = text
	note_overlay.show()
	get_tree().paused = true
