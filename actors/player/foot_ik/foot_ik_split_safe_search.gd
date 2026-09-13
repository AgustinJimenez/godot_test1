class_name FootIKSplitSafeSearch
extends RefCounted
## Extracted from foot_ik_ground_sampler.gd (018 finding H) to stay under that file's line cap.
## This spiral search is the real multi-millisecond-per-call cost finding H's profiling found -
## an expanding ring of candidate root offsets, each checked against root/left/right support.

const SEARCH_STEP := 0.05
const SEARCH_RINGS := 16

var _sampler # FootIKGroundSampler, for its _has_surface_at_height/debug_raw_target/etc.


func _init(sampler) -> void:
	_sampler = sampler


func find_root(space: PhysicsDirectSpaceState3D, root: Vector3, surface_y: float,
		probe_y: float, left := Vector3(INF, INF, INF),
		right := Vector3(INF, INF, INF)) -> Vector3:
	if not left.is_finite() or not right.is_finite():
		if not _sampler.debug_raw_target.has(&"left") \
				or not _sampler.debug_raw_target.has(&"right"):
			return Vector3(INF, INF, INF)
		left = _sampler.debug_raw_target[&"left"]
		right = _sampler.debug_raw_target[&"right"]
	for ring in range(1, SEARCH_RINGS + 1):
		var radius := float(ring) * SEARCH_STEP
		var samples := ring * 8
		for sample_index in samples:
			var angle := TAU * float(sample_index) / float(samples)
			var motion := Vector3(cos(angle), 0.0, sin(angle)) * radius
			if (_sampler._has_surface_at_height(space, root + motion, surface_y, probe_y)
					and _sampler._has_surface_at_height(space, left + motion, surface_y, probe_y)
					and _sampler._has_surface_at_height(space, right + motion, surface_y, probe_y)):
				return root + motion
	return Vector3(INF, INF, INF)


## Cheap check for "is this already-found candidate still worth keeping" - both that ground
## still exists there (avoids re-running the full ring search on every arrival, 021) and that
## it actually converged the two feet onto one shared level (a ground-only check can pass while
## the real per-foot targets still straddle two different heights - also 021's regression).
func reconfirm(space: PhysicsDirectSpaceState3D, candidate: Vector3, root: Vector3,
		surface_y: float, probe_y: float, left: Vector3, right: Vector3,
		observed_height_delta: float) -> bool:
	if observed_height_delta > 0.05: return false
	var motion := candidate - root
	return (_sampler._has_surface_at_height(space, candidate, surface_y, probe_y)
			and _sampler._has_surface_at_height(space, left + motion, surface_y, probe_y)
			and _sampler._has_surface_at_height(space, right + motion, surface_y, probe_y))


func find_nearest_root(space: PhysicsDirectSpaceState3D, root: Vector3,
		upper_y: float, lower_y: float, probe_y: float,
		left: Vector3, right: Vector3) -> Dictionary:
	var upper := find_root(space, root, upper_y, probe_y, left, right)
	var lower := find_root(space, root, lower_y, probe_y, left, right)
	if is_equal_approx(_sampler.split_rejected_surface_y, upper_y): upper = Vector3(INF, INF, INF)
	if is_equal_approx(_sampler.split_rejected_surface_y, lower_y): lower = Vector3(INF, INF, INF)
	if not upper.is_finite(): return {"root": lower, "surface_y": lower_y}
	if not lower.is_finite() or root.distance_to(upper) <= root.distance_to(lower):
		return {"root": upper, "surface_y": upper_y}
	return {"root": lower, "surface_y": lower_y}
