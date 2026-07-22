extends Control
## Main menu shown on launch (project.godot's run/main_scene) - "New Game"
## always opens the Character Creator fresh (no save/load distinction yet,
## see docs/plans); PlayerProfile just means it opens pre-filled with the
## last choice instead of blank.

const CHARACTER_CREATOR_SCENE := "res://ui/character_creator.tscn"

@onready var new_game_button: Button = $Panel/Margin/VBox/NewGameButton
@onready var quit_button: Button = $Panel/Margin/VBox/QuitButton


func _ready() -> void:
	new_game_button.pressed.connect(_on_new_game_pressed)
	quit_button.pressed.connect(_on_quit_pressed)


func _on_new_game_pressed() -> void:
	get_tree().change_scene_to_file(CHARACTER_CREATOR_SCENE)


func _on_quit_pressed() -> void:
	get_tree().quit()
