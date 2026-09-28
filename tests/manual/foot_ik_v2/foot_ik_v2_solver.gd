class_name FootIKV2Solver
extends RefCounted
## Pure two-bone leg maths for the v2 foot IK. No skeleton, no physics scene: give it positions and
## bone lengths, get back where the knee and the ankle go.
##
## Keeping this pure is the point - it is the one piece of v2 that can be tested exactly, so
## `foot_ik_v2_solver_check.gd` asserts its behaviour directly instead of only through a live scene.


## `animated_knee` supplies the bend plane (the animated leg's own knee direction); `rest_pole` is
## the fallback for a straight animated leg, where that direction is undefined.
static func solve(hip: Vector3, animated_knee: Vector3, target: Vector3,
		upper: float, lower: float, rest_pole: Vector3) -> Dictionary:
	var to_target := target - hip
	var distance := clampf(to_target.length(),
			absf(upper - lower) + 0.001, upper + lower - 0.001)
	var direction := to_target.normalized()
	var pole := animated_knee - hip
	pole -= direction * pole.dot(direction)
	# a knee never bends BACKWARD: when the animated bend has swung against the rest pole (the foot
	# moved a long way in, or the hips dropped) that direction is meaningless - take the rest pole
	var rest := (rest_pole - direction * rest_pole.dot(direction)).normalized()
	pole = rest if pole.length_squared() < 0.000001 or pole.dot(rest) < 0.0 else pole.normalized()
	var along := (upper * upper - lower * lower + distance * distance) / (2.0 * distance)
	var outward := sqrt(maxf(0.0, upper * upper - along * along))
	return {
		"knee": hip + direction * along + pole * outward,
		"ankle": hip + direction * distance,
		"direction": direction,
		"pole": pole,
		"distance": distance,
	}
