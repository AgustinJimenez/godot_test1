extends RefCounted
## Where a correction that would put the ankle out of the leg's reach can still go: the point on the
## line from the animated ankle toward the corrected one that is farthest along yet reachable.
## Handing the whole correction back in one frame (a "release") turned the foot 50-120 degrees.


## `animated` and `corrected` are in the same space as `hip`. Returns `animated` if even that is
## out of reach (nothing to blend toward), otherwise the farthest reachable point along the line.
static func reachable(hip: Vector3, animated: Vector3, corrected: Vector3, reach: float) -> Vector3:
	if hip.distance_to(corrected) <= reach:
		return corrected
	if hip.distance_to(animated) > reach:
		return animated
	var low := 0.0
	var high := 1.0
	for i in 10:
		var middle := (low + high) * 0.5
		if hip.distance_to(animated.lerp(corrected, middle)) <= reach:
			low = middle
		else:
			high = middle
	return animated.lerp(corrected, low)
