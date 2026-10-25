extends RefCounted
## The smallest gap between a foot's sole-level points and the floor under them: every few points are ray-cast straight down and the
## smallest height above the hit wins (a hit further below than `sink_max` is a drop-off, not a lower tread). The native class does the
## loop when the library is loaded (FootIKV2Native in native/planet_crust; PLANET_NO_NATIVE=1: this GDScript, the reference).

static var _native_state := -1 # -1 unknown, 0 GDScript, 1 native


static func gap(space: PhysicsDirectSpaceState3D, query: PhysicsRayQueryParameters3D, level: PackedVector3Array,
		hip_y: float, ray_up: float, ray_down: float, samples: int, sink_max: float) -> float:
	if _native_state < 0:
		_native_state = 1 if ClassDB.class_exists(&"FootIKV2Native") and not OS.has_environment("PLANET_NO_NATIVE") else 0
	if _native_state == 1:
		return ClassDB.class_call_static(&"FootIKV2Native", &"min_gap", space, query, level, hip_y, ray_up, ray_down, samples, sink_max)
	var best := INF
	for index in range(0, level.size(), maxi(1, level.size() / samples)):
		var point := level[index]
		query.from = Vector3(point.x, maxf(hip_y, point.y + ray_up), point.z)
		query.to = point - Vector3.UP * ray_down
		var hit := space.intersect_ray(query)
		if not hit.is_empty() and point.y - (hit["position"] as Vector3).y <= sink_max:
			best = minf(best, point.y - (hit["position"] as Vector3).y)
	return best
