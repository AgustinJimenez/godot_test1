class_name FootStepArc
extends RefCounted
## A small idle-reposition step arc - a sine hump added on top of an otherwise straight
## move_toward, echoing how a walking swing rises then settles instead of dragging along a
## straight diagonal (see AGENT_TASKS/019's "similar to a walk anim" ask). Deliberately separate
## from foot_ik_stair_predictor.gd's gait-coupled swing lift, tied to stride phase and not
## applicable to a stationary idle reposition. Owns its own per-side progress state so callers
## need only hold one instance, not a side-keyed dict of their own.

var _state: Dictionary = {} # side -> {origin, target}


func reset() -> void:
	_state.clear()


func reset_side(side: StringName) -> void:
	_state.erase(side)


## Extra height to add above `pos` while it moves toward `target`, held short of any real
## geometry directly above (the peak is a tuning guess, not a proof it always clears a low
## stair nosing overhead). Progress is tracked per `side` and resets whenever `target` changes.
func lift(space: PhysicsDirectSpaceState3D, side: StringName, pos: Vector3, target: Vector3,
		peak: float, collision_mask: int, exclude: Array) -> float:
	if peak <= 0.0:
		return 0.0
	var state: Dictionary = _state.get(side, {})
	if not (state.get("target", Vector3.INF) as Vector3).is_equal_approx(target):
		state = {"origin": pos, "target": target}
		_state[side] = state
	var origin: Vector3 = state["origin"]
	var total := Vector2(origin.x, origin.z).distance_to(Vector2(target.x, target.z))
	if total < 0.001:
		return 0.0
	var remaining := Vector2(pos.x, pos.z).distance_to(Vector2(target.x, target.z))
	var t := clampf(1.0 - remaining / total, 0.0, 1.0)
	var raw_lift := sin(PI * t) * peak
	if raw_lift <= 0.0:
		return 0.0
	var query := PhysicsRayQueryParameters3D.create(pos, pos + Vector3.UP * raw_lift)
	query.collision_mask = collision_mask
	query.collide_with_areas = false
	query.exclude = exclude
	var hit := space.intersect_ray(query)
	if hit.is_empty():
		return raw_lift
	return pos.distance_to(hit["position"] as Vector3)
