class_name ProceduralFootstepPlan
extends RefCounted
## Reusable world-space footstep queue. Gait policy decides where entries go;
## consumers (leg solving, debug drawing, terrain checks) share this accepted data.

var _targets: Array[Vector3] = []
var _sides: Array[int] = []


func reset() -> void:
	_targets.clear()
	_sides.clear()


func size() -> int:
	return _targets.size()


func target(index: int) -> Vector3:
	return _targets[index]


func side(index: int) -> int:
	return _sides[index]


func first_side() -> int:
	return _sides[0] if not _sides.is_empty() else -1


func last_target() -> Vector3:
	return _targets[-1]


func last_side() -> int:
	return _sides[-1]


func append(target_position: Vector3, foot_side: int) -> void:
	_targets.append(target_position)
	_sides.append(foot_side)


func consume(foot_side: int) -> bool:
	if _sides.is_empty() or _sides[0] != foot_side:
		return false
	_targets.pop_front()
	_sides.pop_front()
	return true
