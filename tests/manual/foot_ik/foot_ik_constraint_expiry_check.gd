extends Node
## Regression for 018 finding C's general per-constraint reason/expiry mechanism: the toe/leaf
## envelope's streak tolerance must report an accurate, monotonically-decreasing "frames until
## this becomes VIOLATED" value while tolerated, then both the reason and expiry entries must
## disappear once the toe genuinely becomes valid again - absence means "not degrading," not a
## stale leftover from an earlier frame.


class Sampler extends RefCounted:
	var smoothed_target: Dictionary = {}
	var smoothed_normal: Dictionary = {}
	var idle_lower_acquiring: Dictionary = {}
	var idle_lower_latched_target: Dictionary = {}
	var landing_committed_target: Dictionary = {}
	var idle_stance_rehoming: Dictionary = {}
	var _settings := FootIKRuntimeSettings.new()
	func is_target_inside_stance_zone(_side: StringName, _target: Vector3) -> bool:
		return true


class Gait extends RefCounted:
	func invalidate_idle_freeze(_side: StringName) -> void:
		pass


class Owner extends RefCounted:
	var _ground_sampler := Sampler.new()
	var _gait_tracker := Gait.new()
	var _solved_target_smoothed: Dictionary = {}
	var player_body: Dictionary = {"anim_player": {"current_animation": &"moves/unarmed_idle"}}
	var _landing_grace_time := 0.0
	var step_down_max_crouch := 0.4
	var ankle_offset := 0.1


class Coordinator extends FootIKTargetCoordinator:
	var toe_valid := true
	func _legacy_owner(_side: StringName) -> FootIKTargetPlan.Owner:
		return FootIKTargetPlan.Owner.LIVE_CONTACT
	func _has_support_at(_space: PhysicsDirectSpaceState3D, _surface: Vector3) -> bool:
		return true
	func _toe_envelope_valid(_space: PhysicsDirectSpaceState3D, _plan: FootIKTargetPlan) -> bool:
		return toe_valid


const HOLD_FRAMES := 10 # must match FootIKTargetCoordinator.TOE_INVALID_HOLD_FRAMES

var _owner_state := Owner.new()
var _coordinator := Coordinator.new(_owner_state)
var _leg: Dictionary
var _phase := 0
var _last_expiry := -1
var _failures: Array[String] = []


func _ready() -> void:
	var surface := Vector3.ZERO
	_owner_state._ground_sampler.smoothed_target[&"left"] = surface
	_owner_state._ground_sampler.smoothed_normal[&"left"] = Vector3.UP
	_leg = {"hit": true, "hip_pos": Vector3(0.1, 0.95, 0.0), "raw_target": surface,
			"raw_normal": Vector3.UP, "target": surface + Vector3.UP * 0.1,
			"ground_target": surface + Vector3.UP * 0.1, "effective_offset": 0.1,
			"upper": 0.5, "lower": 0.5, "ground_weight": 1.0, "preserve_idle_pose": false}


func _physics_process(_delta: float) -> void:
	_phase += 1
	if _phase <= HOLD_FRAMES:
		_coordinator.toe_valid = false
		_coordinator.resolve_stationary(null, {&"left": _leg}, true, 0.016)
		var plan := _coordinator.get_plan(&"left")
		var status: int = plan.toe_status
		if _phase < HOLD_FRAMES:
			_expect(status == FootIKTargetPlan.ConstraintStatus.TEMPORARILY_TOLERATED,
					"phase %d: expected TEMPORARILY_TOLERATED, got %d" % [_phase, status])
			var expiry: int = int(plan.constraint_expiry_frames.get("toe", -1))
			_expect(expiry == HOLD_FRAMES - _phase,
					"phase %d: expiry=%d expected %d" % [_phase, expiry, HOLD_FRAMES - _phase])
			_expect(_last_expiry == -1 or expiry < _last_expiry, "expiry did not decrease")
			_expect(plan.constraint_reasons.get("toe", "") == "toe_envelope_blocked",
					"phase %d: missing/wrong toe reason" % _phase)
			_last_expiry = expiry
		else:
			# Once the hold truly expires, _build_plan falls through to _raw_recovery_plan,
			# which deliberately skips toe re-validation (NOT_APPLICABLE) rather than vetoing
			# its own fallback with the same check that just rejected the primary candidate -
			# expiry_frames/reasons must not still claim "toe" is degrading past this point.
			_expect(status == FootIKTargetPlan.ConstraintStatus.NOT_APPLICABLE,
					"phase %d: expected NOT_APPLICABLE (raw recovery), got %d" % [_phase, status])
			_expect(not plan.constraint_reasons.has("toe"), "stale toe reason past expiry")
			_expect(not plan.constraint_expiry_frames.has("toe"), "stale toe expiry past expiry")
	elif _phase == HOLD_FRAMES + 1:
		_coordinator.toe_valid = true
		_coordinator.resolve_stationary(null, {&"left": _leg}, true, 0.016)
		var recovered := _coordinator.get_plan(&"left")
		_expect(recovered.toe_status == FootIKTargetPlan.ConstraintStatus.SATISFIED,
				"recovered toe status wrong: %d" % recovered.toe_status)
		_expect(not recovered.constraint_reasons.has("toe"), "stale toe reason after recovery")
		_expect(not recovered.constraint_expiry_frames.has("toe"), "stale toe expiry after recovery")
		print("FOOT_IK_CONSTRAINT_EXPIRY_CHECK %s failures=%s" % [
				"PASS" if _failures.is_empty() else "FAIL", _failures])
		get_tree().quit(0 if _failures.is_empty() else 1)


func _expect(passed: bool, reason: String) -> void:
	if not passed:
		_failures.append(reason)
