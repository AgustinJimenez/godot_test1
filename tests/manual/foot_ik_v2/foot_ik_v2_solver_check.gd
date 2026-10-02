extends SceneTree
## Focused regression for the v2 two-bone solver maths. Pure - no scene, no physics, no skeleton -
## so it runs in milliseconds and a failure points straight at the solver instead of at a whole lab
## run. Grows one assertion per solver behaviour as v2 progresses.
##
## Run: godot --headless --path . --script \
##      res://tests/manual/foot_ik_v2/foot_ik_v2_solver_check.gd

const SOLVER := preload("res://actors/player/foot_ik_v2/foot_ik_v2_solver.gd")
const EPS := 0.0005
const UPPER := 0.45
const LOWER := 0.45
const HIP := Vector3(0.0, 1.0, 0.0)
const ANIMATED_KNEE := Vector3(0.0, 0.55, 0.20)
## Slightly forward of the hip in absolute terms but BEHIND the line to a target that leans forward.
const BACKWARD_KNEE := Vector3(0.0, 0.55, 0.12)
const REST_POLE := Vector3(0.0, 0.0, 1.0)

var _failures := 0


func _initialize() -> void:
	_reachable_target()
	_unreachable_target_clamps_to_reach()
	_collapsed_target_clamps_to_minimum()
	_knee_keeps_bone_lengths()
	_knee_stays_on_the_animated_side()
	_straight_leg_falls_back_to_the_rest_pole()
	_knee_never_bends_backward()
	_knee_flexion_is_capped()
	_hip_swing_is_capped()
	print("FOOT_IK_V2_SOLVER_CHECK %s" % (
			"PASS" if _failures == 0 else "FAIL failures=%d" % _failures))
	quit(0 if _failures == 0 else 1)


## A target within reach must be reached exactly - the whole point of the solve.
func _reachable_target() -> void:
	var target := Vector3(0.0, 0.35, 0.22)
	var solved := SOLVER.solve(HIP, ANIMATED_KNEE, target, UPPER, LOWER, REST_POLE)
	_check("reachable_target_lands_on_target",
			(solved["ankle"] as Vector3).distance_to(target) <= EPS,
			"error=%.6f" % (solved["ankle"] as Vector3).distance_to(target))


## Past the leg's length the ankle stops at full extension, not past it.
func _unreachable_target_clamps_to_reach() -> void:
	var solved := SOLVER.solve(HIP, ANIMATED_KNEE, Vector3(0.0, -1.0, 0.0),
			UPPER, LOWER, REST_POLE)
	var reach := (solved["ankle"] as Vector3).distance_to(HIP)
	_check("unreachable_target_clamps_to_reach", absf(reach - (UPPER + LOWER - 0.001)) <= EPS,
			"reach=%.4f" % reach)


## A target tighter than the bones allow stops at the minimum fold, so the leg never inverts.
func _collapsed_target_clamps_to_minimum() -> void:
	var solved := SOLVER.solve(HIP, ANIMATED_KNEE, HIP + Vector3(0.0, -0.001, 0.0),
			UPPER, LOWER, REST_POLE)
	var reach := (solved["ankle"] as Vector3).distance_to(HIP)
	_check("collapsed_target_clamps_to_minimum",
			absf(reach - (absf(UPPER - LOWER) + 0.001)) <= EPS, "reach=%.4f" % reach)


## Both segments keep their bone length whatever the target.
func _knee_keeps_bone_lengths() -> void:
	var solved := SOLVER.solve(HIP, ANIMATED_KNEE, Vector3(0.0, 0.35, 0.22),
			UPPER, LOWER, REST_POLE)
	var upper_error := absf((solved["knee"] as Vector3).distance_to(HIP) - UPPER)
	var lower_error := absf((solved["ankle"] as Vector3).distance_to(solved["knee"] as Vector3)
			- LOWER)
	_check("knee_keeps_bone_lengths", upper_error <= EPS and lower_error <= EPS,
			"upper_err=%.5f lower_err=%.5f" % [upper_error, lower_error])


## The knee bends toward the side the ANIMATED knee was on, so the pose keeps its own style instead
## of always folding one fixed way.
func _knee_stays_on_the_animated_side() -> void:
	var solved := SOLVER.solve(HIP, ANIMATED_KNEE, Vector3(0.0, 0.35, 0.22),
			UPPER, LOWER, REST_POLE)
	var direction := solved["direction"] as Vector3
	var animated_pole := ANIMATED_KNEE - HIP
	animated_pole -= direction * animated_pole.dot(direction)
	var solved_pole := (solved["knee"] as Vector3) - HIP
	solved_pole -= direction * solved_pole.dot(direction)
	_check("knee_stays_on_animated_side", solved_pole.normalized().dot(animated_pole.normalized())
			> 0.99, "dot=%.3f" % solved_pole.normalized().dot(animated_pole.normalized()))


## A straight animated leg has no bend direction of its own, so the rest pole decides.
func _straight_leg_falls_back_to_the_rest_pole() -> void:
	var target := Vector3(0.0, 0.3, 0.0)
	var straight_knee := HIP + (target - HIP).normalized() * UPPER
	var solved := SOLVER.solve(HIP, straight_knee, target, UPPER, LOWER, REST_POLE)
	var direction := solved["direction"] as Vector3
	var solved_pole := (solved["knee"] as Vector3) - HIP
	solved_pole -= direction * solved_pole.dot(direction)
	_check("straight_leg_uses_rest_pole", solved_pole.normalized().dot(REST_POLE) > 0.99,
			"dot=%.3f" % solved_pole.normalized().dot(REST_POLE))


## An animated knee that projects BEHIND the hip-to-target line (the foot moved a long way in, or
## the hips dropped) must not fold the leg backward: the rest pole takes over.
func _knee_never_bends_backward() -> void:
	var solved := SOLVER.solve(HIP, BACKWARD_KNEE, Vector3(0.0, 0.35, 0.22), UPPER, LOWER, REST_POLE)
	var direction := solved["direction"] as Vector3
	var solved_pole := (solved["knee"] as Vector3) - HIP
	solved_pole -= direction * solved_pole.dot(direction)
	_check("knee_never_bends_backward", solved_pole.normalized().dot(REST_POLE) > 0.0,
			"dot=%.3f" % solved_pole.normalized().dot(REST_POLE))


## A target close under the hip would fold the knee past the flexion cap: the foot stops short.
func _knee_flexion_is_capped() -> void:
	var solved := SOLVER.solve(HIP, ANIMATED_KNEE, HIP + Vector3(0.0, -0.10, 0.05), UPPER, LOWER,
			REST_POLE, 100.0)
	var knee := solved["knee"] as Vector3
	var ankle := solved["ankle"] as Vector3
	var flexion := 180.0 - rad_to_deg((HIP - knee).angle_to(ankle - knee))
	_check("knee_flexion_is_capped", flexion <= 100.5, "flexion=%.1f (cap 100)" % flexion)


## A target far out to the side would swing the thigh past the cone: the knee is pulled back in.
func _hip_swing_is_capped() -> void:
	var solved := SOLVER.solve(HIP, ANIMATED_KNEE, HIP + Vector3(0.0, -0.05, 0.85), UPPER, LOWER,
			REST_POLE, 0.0, 70.0)
	var swing := rad_to_deg(Vector3.DOWN.angle_to(((solved["knee"] as Vector3) - HIP).normalized()))
	_check("hip_swing_is_capped", swing <= 70.5, "swing=%.1f (cap 70)" % swing)


func _check(name: String, condition: bool, detail: String) -> void:
	if not condition:
		_failures += 1
	print("  %-32s %-4s %s" % [name, "ok" if condition else "FAIL", detail])
