class_name ItemPickup
extends Area3D
## World representation of an Item. Interacting moves it into the player's inventory.

@export var item: Item
@export var count: int = 1

@onready var interactable: Interactable = $Interactable


func _ready() -> void:
	if item:
		interactable.prompt = "Take " + item.display_name


func _on_interactable_interacted(player: Node3D) -> void:
	var inventory: Inventory = player.get_node_or_null(^"Inventory")
	if inventory == null:
		return
	var hud: Node = get_tree().get_first_node_in_group(&"hud")
	var leftover := inventory.add_item(item, count)
	if leftover == 0:
		if hud:
			var label := item.display_name if count == 1 else "%s ×%d" % [item.display_name, count]
			hud.toast("Picked up " + label)
		queue_free()
	else:
		count = leftover
		if hud:
			hud.toast("Inventory full")
