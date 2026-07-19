class_name ItemPickup
extends Area3D
## World representation of an Item. Interacting moves it into the player's inventory.

@export var item: Item
@export var count: int = 1

@onready var interactable: Interactable = $Interactable
@onready var visual_anchor: Node3D = $VisualAnchor
@onready var fallback_mesh: MeshInstance3D = $VisualAnchor/FallbackMesh


func _ready() -> void:
	if item:
		interactable.prompt = "Take " + item.display_name
		_load_item_visual()


func _load_item_visual() -> void:
	if item.world_scene == null:
		return
	var instance := item.world_scene.instantiate() as Node3D
	if instance == null:
		return
	fallback_mesh.hide()
	visual_anchor.add_child(instance)
	instance.scale = Vector3.ONE * item.world_scale
	instance.rotation_degrees = item.world_rotation_degrees
	instance.position = item.world_offset


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
