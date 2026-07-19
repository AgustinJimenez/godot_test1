class_name NPCController
extends Node

## Body-independent NPC identity and state. Actor scripts decide how a body
## executes each state; events may change disposition or behavior at runtime.

signal disposition_changed(previous: int, current: int)
signal behavior_changed(previous: int, current: int)

enum Disposition { FRIENDLY, NEUTRAL, SUSPICIOUS, HOSTILE }
enum Behavior { IDLE, PATROL, INVESTIGATE, CHASE, ATTACK, SEARCH, FLEE }

@export_enum("Friendly", "Neutral", "Suspicious", "Hostile")
var initial_disposition: int = Disposition.HOSTILE
@export_enum("Idle", "Patrol", "Investigate", "Chase", "Attack", "Search", "Flee")
var initial_behavior: int = Behavior.PATROL

var disposition: int
var behavior: int


func _ready() -> void:
	disposition = initial_disposition
	behavior = initial_behavior
	var actor := get_parent()
	actor.add_to_group(&"npcs")
	_update_hostile_group()


func set_disposition(value: int) -> void:
	if value < 0 or value >= Disposition.size() or value == disposition:
		return
	var previous := disposition
	disposition = value
	_update_hostile_group()
	disposition_changed.emit(previous, disposition)


func set_behavior(value: int) -> void:
	if value < 0 or value >= Behavior.size() or value == behavior:
		return
	var previous := behavior
	behavior = value
	behavior_changed.emit(previous, behavior)


func is_hostile() -> bool:
	return disposition == Disposition.HOSTILE


func become_hostile() -> void:
	set_disposition(Disposition.HOSTILE)


func _update_hostile_group() -> void:
	var actor := get_parent()
	if is_hostile():
		actor.add_to_group(&"enemies")
	else:
		actor.remove_from_group(&"enemies")
