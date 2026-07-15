extends Area3D
## A readable document; opens the HUD note overlay.

@export_multiline var text: String = ""


func _on_interactable_interacted(_player: Node3D) -> void:
	var hud: Node = get_tree().get_first_node_in_group(&"hud")
	if hud:
		hud.show_note(text)
