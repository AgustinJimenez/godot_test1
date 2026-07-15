class_name Interactable
extends Node
## Attach as a child named "Interactable" of any CollisionObject3D the player's
## interact ray can hit. The owner reacts by connecting to `interacted`.

signal interacted(player: Node3D)

@export var prompt: String = "Interact"
@export var enabled: bool = true


func interact(player: Node3D) -> void:
	if enabled:
		interacted.emit(player)
