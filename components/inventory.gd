class_name Inventory
extends Node
## Slot-based inventory. Each slot is {} (empty) or {"item": Item, "count": int}.

signal changed

@export var capacity: int = 8

var slots: Array[Dictionary] = []


func _ready() -> void:
	slots.resize(capacity)
	for i in capacity:
		slots[i] = {}


## Returns how many did NOT fit (0 = everything was added).
func add_item(item: Item, count: int = 1) -> int:
	var remaining := count
	for slot in slots:
		if not slot.is_empty() and slot["item"] == item:
			var space: int = item.max_stack - slot["count"]
			if space > 0:
				var moved: int = mini(space, remaining)
				slot["count"] += moved
				remaining -= moved
				if remaining == 0:
					break
	if remaining > 0:
		for i in slots.size():
			if slots[i].is_empty():
				var moved: int = mini(item.max_stack, remaining)
				slots[i] = {"item": item, "count": moved}
				remaining -= moved
				if remaining == 0:
					break
	if remaining != count:
		changed.emit()
	return remaining


func count_of(item: Item) -> int:
	var total := 0
	for slot in slots:
		if not slot.is_empty() and slot["item"] == item:
			total += slot["count"]
	return total


func remove_item(item: Item, count: int = 1) -> void:
	var remaining := count
	for i in slots.size():
		if remaining == 0:
			break
		if not slots[i].is_empty() and slots[i]["item"] == item:
			var taken: int = mini(slots[i]["count"], remaining)
			slots[i]["count"] -= taken
			remaining -= taken
			if slots[i]["count"] == 0:
				slots[i] = {}
	changed.emit()


func remove_at(index: int, count: int = 1) -> void:
	if slots[index].is_empty():
		return
	slots[index]["count"] -= count
	if slots[index]["count"] <= 0:
		slots[index] = {}
	changed.emit()
