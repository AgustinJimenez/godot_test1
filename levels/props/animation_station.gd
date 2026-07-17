class_name AnimationStation
extends Area3D
## Debug-room action preview using the same Interactable contract as gameplay.

@export var display_name := "ANIMATION"
@export var animation_name: StringName = &"unarmed_interact"
@export var animation_speed := 1.0
@export var enable_torch := false

@onready var label: Label3D = $Label
@onready var interactable: Interactable = $Interactable


func _ready() -> void:
	label.text = "PRESS [E]  " + display_name
	interactable.prompt = "Preview " + display_name


func _on_interactable_interacted(player: Node3D) -> void:
	if not player is Player:
		return
	var typed_player := player as Player
	if enable_torch:
		typed_player.flashlight.visible = true
	elif animation_name != &"":
		typed_player.body.play_action_animation(animation_name, animation_speed)
	var hud := get_tree().get_first_node_in_group(&"hud")
	if hud:
		hud.toast(display_name)
