extends Node3D
## Hinged door. The root node is the hinge; the panel hangs off it on +X.
## Optionally locked behind a key Item, which is consumed on unlock.

@export var open_angle_deg: float = 100.0
@export var swing_time: float = 0.8
@export var locked := false
@export var required_item: Item

var _open := false
var _busy := false

@onready var interactable: Interactable = $Body/Interactable


func _on_interactable_interacted(player: Node3D) -> void:
	if _busy:
		return
	var hud: Node = get_tree().get_first_node_in_group(&"hud")
	if locked:
		var inventory: Inventory = player.get_node_or_null(^"Inventory")
		if required_item and inventory and inventory.count_of(required_item) > 0:
			inventory.remove_item(required_item, 1)
			locked = false
			if hud:
				hud.toast("Unlocked with " + required_item.display_name)
		else:
			if hud:
				var need := required_item.display_name if required_item else "a key"
				hud.toast("Locked — needs " + need)
			return
	_busy = true
	_open = not _open
	interactable.prompt = "Close door" if _open else "Open door"
	var target_y := deg_to_rad(open_angle_deg) if _open else 0.0
	var tween := create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(self, "rotation:y", target_y, swing_time)
	tween.finished.connect(func() -> void: _busy = false)
