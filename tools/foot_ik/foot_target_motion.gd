extends RefCounted
## Single-height horizontal target-path hold. Not a swept-foot-volume clearance check (025).


static func hold_short_of_collision(space: PhysicsDirectSpaceState3D,
		previous: Vector3, intended: Vector3, mask: int, exclude: Array) -> Vector3:
	var horizontal_dist := Vector2(previous.x, previous.z).distance_to(Vector2(intended.x, intended.z))
	if horizontal_dist < 0.001:
		return intended
	const HOLD_PROBE_UP := 0.05
	const HOLD_MARGIN := 0.03
	var probe_y := maxf(previous.y, intended.y) + HOLD_PROBE_UP
	var from := Vector3(previous.x, probe_y, previous.z)
	var to := Vector3(intended.x, probe_y, intended.z)
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.collision_mask = mask
	query.collide_with_areas = false
	query.exclude = exclude
	var hit := space.intersect_ray(query)
	if hit.is_empty():
		return intended
	var hit_dist: float = from.distance_to(hit["position"])
	if hit_dist >= horizontal_dist - HOLD_MARGIN:
		return intended
	var safe_fraction := maxf(0.0, hit_dist - HOLD_MARGIN) / horizontal_dist
	return previous.lerp(intended, safe_fraction)
