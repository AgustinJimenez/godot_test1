extends Node
## Acceptance contract for slope-target ownership, independently of bend feasibility.


class PolicyOwner extends RefCounted:
	var _ground_sampler: Dictionary = {"_settings": FootIKRuntimeSettings.new()}
	var _smoothed_normal: Dictionary = {&"left": Vector3(0.0, 1.0, 1.0).normalized()}
	var max_hip_swing_degrees := 100.0


class PolicySolver extends "res://actors/player/foot_ik/foot_ik_leg_solver.gd":
	# Keep every candidate feasible to isolate acquisition/rate-limit behavior.
	func _target_thigh_swing(_side: StringName, _hip: Vector3, _target: Vector3,
			_upper: float, _lower: float, _to_world: Transform3D) -> float:
		return 0.0


var _solver: PolicySolver
var _phase := 0
var _failures: Array[String] = []


func _ready() -> void:
	_solver = PolicySolver.new(PolicyOwner.new())


func _physics_process(_delta: float) -> void:
	_phase += 1
	match _phase:
		1:
			_expect(_sample(Vector3.ZERO).is_zero_approx(), "fresh acquisition")
		2:
			var moved := _sample(Vector3(0.5, 0.0, 0.0))
			_expect(absf(moved.x - 0.015) < 0.00001, "continuous owner must not teleport")
			_expect(_sample(Vector3.ONE).is_equal_approx(moved), "same-tick refresh advances twice")
		3:
			pass # Walking owns this tick; slope adjustment is inactive.
		4:
			var target := Vector3(2.0, 0.0, 0.0)
			_expect(_sample(target).is_equal_approx(target), "reacquisition uses stale walking anchor")
		5:
			_solver.reset_runtime_state()
			_expect(_sample(Vector3.ONE).is_equal_approx(Vector3.ONE), "reset retains target history")
		6:
			print("FOOT_IK_SLOPE_TARGET_LIFECYCLE_CHECK %s failures=%s" % [
					"PASS" if _failures.is_empty() else "FAIL", _failures])
			get_tree().quit(0 if _failures.is_empty() else 1)


func _sample(target: Vector3) -> Vector3:
	return _solver.adjust_idle_slope_target(&"left", Vector3.UP, target,
			0.5, 0.5, Transform3D.IDENTITY, Vector3.LEFT)


func _expect(passed: bool, reason: String) -> void:
	if not passed:
		_failures.append(reason)
