extends Area3D
## Placeholder pickup until the M2 inventory exists.

@export var item_name: String = "Battery"


func _on_interactable_interacted(_player: Node3D) -> void:
	print("Picked up: ", item_name)
	queue_free()
