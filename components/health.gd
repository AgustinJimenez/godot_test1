class_name Health
extends Node
## Reusable hit-point pool. Add as a child named exactly "Health" of any
## damageable body; weapons find it with get_node_or_null(^"Health"), the
## same discovery trick the interact ray uses for Interactable.

signal changed(current: float, max_value: float)
signal damaged(amount: float)
signal died

@export var max_health: float = 100.0

var current: float


func _ready() -> void:
	current = max_health


func is_dead() -> bool:
	return current <= 0.0


func apply_damage(amount: float) -> float:
	if is_dead() or amount <= 0.0:
		return 0.0
	var applied := minf(amount, current)
	current -= applied
	damaged.emit(applied)
	changed.emit(current, max_health)
	if current == 0.0:
		died.emit()
	return applied


## Restores up to `amount`; returns how much was actually restored
## (0 means the target was already full — callers can refuse to consume).
func heal(amount: float) -> float:
	if is_dead():
		return 0.0
	var restored := minf(amount, max_health - current)
	if restored > 0.0:
		current += restored
		changed.emit(current, max_health)
	return restored
