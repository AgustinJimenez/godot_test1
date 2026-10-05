extends Node
## The IK-off / IK-on comparison row (foot_ik_v2_comparison.tscn) inside the lab: one pair per
## animation with the live verdict, foot values and red joint markers. It stands behind the stairs
## (z = -12, clear of every ramp and staircase). F7 hides / shows it; it is not built headless, so
## the regression suite is unaffected. In a window the pairs use the walks the player really uses.

const COMPARISON := preload("res://tests/manual/foot_ik_v2/foot_ik_v2_comparison.tscn")
const ROW_POSITION := Vector3(17.5, 0.0, -12.0)

var _row: Node3D


func _ready() -> void:
	if DisplayServer.get_name() != "headless":
		_show_row()


## F7 toggles the row. Not F6 (that toggles v2) and not a player action.
func _unhandled_key_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo or key.keycode != KEY_F7:
		return
	if _row != null and is_instance_valid(_row):
		_row.queue_free()
		_row = null
	else:
		_show_row()


func _show_row() -> void:
	_row = COMPARISON.instantiate() as Node3D
	_row.set("embedded", true)
	_row.position = ROW_POSITION
	get_parent().add_child.call_deferred(_row) # the lab is still setting up its own children
