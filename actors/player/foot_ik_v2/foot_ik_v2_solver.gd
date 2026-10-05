class_name FootIKV2Solver
extends RefCounted
## Pure two-bone leg maths for the v2 foot IK. No skeleton, no physics scene: give it positions and
## bone lengths, get back where the knee and the ankle go.
##
## Keeping this pure is the point - it is the one piece of v2 that can be tested exactly, so
## `foot_ik_v2_solver_check.gd` asserts its behaviour directly instead of only through a live scene.


## `animated_knee` supplies the bend plane (the animated leg's own knee direction); `rest_pole` is
## the fallback for a straight animated leg, where that direction is undefined. Optional anatomical
## limits (0 = off), v1's approach: `max_flexion_deg` keeps the knee's interior angle above
## 180 - max (the foot falls short rather than fold the leg), `max_swing_deg` keeps the thigh in a
## cone around `down` (the knee is swung back into it; the foot may then land short).
static func solve(hip: Vector3, animated_knee: Vector3, target: Vector3,
		upper: float, lower: float, rest_pole: Vector3, max_flexion_deg := 0.0,
		max_swing_deg := 0.0, down := Vector3.DOWN, bend_free := 0.0) -> Dictionary:
	var to_target := target - hip
	var min_distance := absf(upper - lower) + 0.001
	if max_flexion_deg > 0.0:
		var interior := deg_to_rad(180.0 - max_flexion_deg)
		min_distance = maxf(min_distance, sqrt(maxf(0.0,
				upper * upper + lower * lower - 2.0 * upper * lower * cos(interior))))
	var distance := clampf(to_target.length(), min_distance, upper + lower - 0.001)
	var direction := to_target.normalized()
	var pole := animated_knee - hip
	pole -= direction * pole.dot(direction)
	# A knee never bends BACKWARD: as the animated bend swings against the rest pole (foot moved a
	# long way in, hips dropped) it is blended toward the rest pole. A hard switch at dot = 0 flipped
	# the knee 90 degrees in one frame when an idle loop hovered around it (a 47 degree joint pop).
	var rest := (rest_pole - direction * rest_pole.dot(direction)).normalized()
	if pole.length_squared() < 0.000001:
		pole = rest
	else:
		pole = pole.normalized()
		# bend_free (0 resting .. 1 walking, eased): walking, only a knee bending BACKWARD is pulled back
		var edge := Vector2(-0.3, 0.5).lerp(Vector2(-0.9, -0.5), bend_free)
		pole = rest.lerp(pole, smoothstep(edge.x, edge.y, pole.dot(rest))).normalized()
	var along := (upper * upper - lower * lower + distance * distance) / (2.0 * distance)
	var outward := sqrt(maxf(0.0, upper * upper - along * along))
	var knee := hip + direction * along + pole * outward
	var thigh := (knee - hip) / upper
	if max_swing_deg > 0.0 and down.angle_to(thigh) > deg_to_rad(max_swing_deg):
		var axis := down.cross(thigh)
		if axis.length_squared() > 0.0001:
			knee = hip + down.rotated(axis.normalized(), deg_to_rad(max_swing_deg)) * upper
	return {
		"knee": knee,
		"ankle": hip + direction * distance,
		"direction": direction,
		"pole": pole,
		"distance": distance,
	}
