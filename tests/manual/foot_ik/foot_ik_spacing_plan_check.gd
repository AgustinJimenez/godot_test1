extends Node
## Deterministic coordinator contract: spacing is proposed before support/stance/reach
## validation, and rejected proposals never overwrite the accepted fallback afterward.


class Sampler extends RefCounted:
	var smoothed_target: Dictionary = {}
	var smoothed_normal: Dictionary = {}
	var idle_lower_acquiring: Dictionary = {}
	var idle_lower_latched_target: Dictionary = {}
	var landing_committed_target: Dictionary = {}
	var idle_stance_rehoming: Dictionary = {}
	var _settings := FootIKRuntimeSettings.new()
	func is_target_inside_stance_zone(_side: StringName, target: Vector3) -> bool:
		return target.is_finite() and absf(target.x) <= 0.56 and absf(target.z) <= 0.4


class Gait extends RefCounted:
	func invalidate_idle_freeze(_side: StringName) -> void:
		pass


class StairStub extends RefCounted:
	func is_descending_treads() -> bool:
		return false
	func is_active() -> bool:
		return false


class Owner extends RefCounted:
	var _ground_sampler := Sampler.new()
	var _gait_tracker := Gait.new()
	var _stair_predictor := StairStub.new()
	var _solved_target_smoothed: Dictionary = {}
	var player_body: Dictionary = {"anim_player": {"current_animation": &"moves/unarmed_idle"}}
	var _landing_grace_time := 0.0
	var step_down_max_crouch := 0.4
	var ankle_offset := 0.1


class Coordinator extends FootIKTargetCoordinator:
	var support_half_width := 1.0
	var checked_surfaces: Array[Vector3] = []
	var split_height := false
	func _legacy_owner(_side: StringName) -> FootIKTargetPlan.Owner:
		return FootIKTargetPlan.Owner.LIVE_CONTACT
	func _has_support_at(_space: PhysicsDirectSpaceState3D, surface: Vector3) -> bool:
		checked_surfaces.append(surface)
		var height := 0.2 if split_height and surface.x > 0.0 else 0.0
		return absf(surface.x) <= support_half_width and absf(surface.y - height) <= 0.001
	func _toe_envelope_valid(_space: PhysicsDirectSpaceState3D, _plan: FootIKTargetPlan) -> bool:
		return true


var _failures: Array[String] = []
var _cases := 0


func _ready() -> void:
	for support_width in [1.0, 0.09, 0.0]:
		_check_validation(support_width)
	for mode in ["flat_idle", "moving", "wide", "missing_hit", "single_leg"]:
		_check_passthrough(mode)
	for degrees in range(0, 360, 15):
		_check_rotation(deg_to_rad(degrees))
	_check_split_height()
	_check_ground_target_override()
	for prefer in [false, true]:
		for has_ground in [false, true]:
			_check_target_priority(prefer, has_ground)
	_check_invalid_ground_target()
	print("FOOT_IK_SPACING_PLAN_CHECK %s cases=%d failures=%s" % [
			"PASS" if _failures.is_empty() else "FAIL", _cases, _failures])
	get_tree().quit(0 if _failures.is_empty() else 1)


func _legs(owner_state: Owner, half_width: float = 0.08) -> Dictionary:
	var legs: Dictionary = {}
	for side: StringName in [&"left", &"right"]:
		var sign_value := 1.0 if side == &"left" else -1.0
		var surface := Vector3(half_width * sign_value, 0.0, 0.0)
		owner_state._ground_sampler.smoothed_target[side] = surface
		owner_state._ground_sampler.smoothed_normal[side] = Vector3.UP
		legs[side] = {"hit": true, "hip_pos": Vector3(0.15 * sign_value, 0.95, 0.0),
				"raw_target": surface, "raw_normal": Vector3.UP,
				"target": surface + Vector3.UP * 0.1,
				"ground_target": surface + Vector3.UP * 0.1, "effective_offset": 0.1,
				"upper": 0.5, "lower": 0.5, "ground_weight": 1.0, "preserve_idle_pose": false}
	return legs


func _check_validation(support_width: float) -> void:
	_cases += 1
	var owner_state := Owner.new()
	var coordinator := Coordinator.new(owner_state)
	coordinator.support_half_width = support_width
	var legs := _legs(owner_state)
	coordinator.resolve_stationary(null, legs, true, 0.016, Transform3D.IDENTITY)
	for side: StringName in legs:
		var plan := coordinator.get_plan(side)
		var leg: Dictionary = legs[side]
		_expect(plan.spacing_requested, "narrow pair did not propose spacing")
		_expect(absf(absf(plan.proposed_ankle_target.x) - 0.11) < 0.000001,
				"proposal differs from legacy 22 cm formula")
		if support_width == 0.0:
			_expect(not plan.valid and not leg["hit"], "unsupported pair was not released")
			continue
		_expect(plan.matches_solve_target(leg["target"]), "accepted target/input mismatch")
		_expect(coordinator.record_solve_target(side, leg["target"], true),
				"accepted target unreported")
		_expect(plan.solve_target_reason == "accepted_plan", "accepted target wrong reason")
		var accepted := plan.ankle_target
		_expect(not coordinator.record_solve_target(side, accepted + Vector3.RIGHT * 0.0001, true),
				"late override incorrectly inherits plan guarantee")
		_expect(plan.ankle_target == accepted, "observation rewrote accepted plan")
		_expect(plan.solve_target_reason == "late_target_override", "override missing explanation")
		_expect(not plan.solve_validation_retained, "override retains validation flag")
		if support_width < 0.11:
			_expect(plan.reason == "replace_invalid_with_raw_support", "no supported fallback")
			_expect(absf(absf(plan.ankle_target.x) - 0.08) < 0.000001,
					"spacing reapplied after fallback validation")
		else:
			_expect(absf(absf(plan.surface_target.x) - 0.11) < 0.000001,
					"support still refers to unspaced surface")
	_expect(coordinator.checked_surfaces.has(Vector3(0.11, 0.0, 0.0)),
			"shifted support point never checked")


func _check_passthrough(mode: String) -> void:
	_cases += 1
	var owner_state := Owner.new()
	var legs := _legs(owner_state, 0.2 if mode == "wide" else 0.08)
	if mode == "flat_idle":
		legs[&"left"]["preserve_idle_pose"] = true
		legs[&"right"]["preserve_idle_pose"] = true
	elif mode == "missing_hit":
		legs[&"right"]["hit"] = false
	elif mode == "single_leg":
		legs.erase(&"right")
	var before := legs.duplicate(true)
	FootIKTargetCoordinator._propose_spacing(legs, mode != "moving", Transform3D.IDENTITY)
	_expect(legs == before, "%s changed targets" % mode)


func _check_rotation(yaw: float) -> void:
	_cases += 1
	var owner_state := Owner.new()
	var legs := _legs(owner_state)
	var world := Transform3D(Basis(Vector3.UP, yaw), Vector3(4.0, 2.0, -3.0))
	for side: StringName in legs:
		for field in ["hip_pos", "target", "ground_target"]:
			legs[side][field] = world * (legs[side][field] as Vector3)
	var midpoint: Vector3 = (legs[&"left"]["target"] + legs[&"right"]["target"]) * 0.5
	FootIKTargetCoordinator._propose_spacing(legs, true, world)
	_expect((legs[&"left"]["target"] as Vector3).is_equal_approx(
			midpoint + world.basis.x * 0.11), "rotated left proposal changed formula")
	_expect((legs[&"right"]["target"] as Vector3).is_equal_approx(
			midpoint - world.basis.x * 0.11), "rotated right proposal changed formula")


func _check_split_height() -> void:
	_cases += 1
	var owner_state := Owner.new()
	var coordinator := Coordinator.new(owner_state)
	coordinator.split_height = true
	var legs := _legs(owner_state)
	for field in ["raw_target", "target", "ground_target"]:
		legs[&"left"][field] += Vector3.UP * 0.2
	owner_state._ground_sampler.smoothed_target[&"left"] += Vector3.UP * 0.2
	coordinator.resolve_stationary(null, legs, true, 0.016)
	for side: StringName in legs:
		var plan := coordinator.get_plan(side)
		_expect(plan.valid and plan.reason == "replace_invalid_with_raw_support",
				"averaged unsupported height did not fall back")
		_expect(plan.ankle_target == legs[side]["raw_target"] + Vector3.UP * 0.1,
				"accepted fallback lost its real support height")


func _check_ground_target_override() -> void:
	_cases += 1
	var owner_state := Owner.new()
	var coordinator := Coordinator.new(owner_state)
	var legs := _legs(owner_state)
	legs[&"left"]["preserve_idle_pose"] = true
	legs[&"left"]["prefer_ground_target"] = true
	coordinator.resolve_stationary(null, legs, true, 0.016)
	var plan := coordinator.get_plan(&"left")
	_expect(plan.ankle_target == legs[&"left"]["ground_target"],
			"ground target not selected before validation")
	_expect(plan.target_source == "ground_target" and not plan.spacing_requested,
			"ground target inherited discarded spacing provenance")
	_expect(plan.surface_target == owner_state._ground_sampler.smoothed_target[&"left"],
			"ground target incorrectly uses shifted spacing support")
	_expect(coordinator.record_solve_target(&"left", plan.ankle_target, true),
			"selected ground target lost its own validation")
	_expect(plan.solve_target_reason == "accepted_plan", "selected ground target not accepted")


func _check_target_priority(prefer: bool, has_ground: bool) -> void:
	_cases += 1
	var owner_state := Owner.new()
	var legs := _legs(owner_state, 0.2)
	for side: StringName in legs:
		var leg: Dictionary = legs[side]
		leg["prefer_ground_target"] = prefer
		leg["target"] += Vector3.FORWARD * 0.03
		if not has_ground:
			leg.erase("ground_target")
		# Reference is the former inline custom-solver choice, before any late adjustment.
		var expected: Vector3 = (leg.get("ground_target", leg.get("target", Vector3.ZERO))
				if prefer else leg.get("target", Vector3.ZERO))
		var pelvis_proposal: Vector3 = leg["target"]
		var coordinator := Coordinator.new(owner_state)
		coordinator.resolve_stationary(null, {side: leg}, true, 0.016)
		_expect(coordinator.get_plan(side).ankle_target == expected,
				"accepted selection differs from former inline priority")
		_expect(leg["target"] == pelvis_proposal,
				"solve selection silently changed the legacy pelvis proposal")


func _check_invalid_ground_target() -> void:
	_cases += 1
	var owner_state := Owner.new()
	var coordinator := Coordinator.new(owner_state)
	var legs := _legs(owner_state, 0.2)
	legs[&"left"]["prefer_ground_target"] = true
	legs[&"left"]["ground_target"] = Vector3(3.0, 0.1, 0.0)
	coordinator.resolve_stationary(null, legs, true, 0.016)
	var plan := coordinator.get_plan(&"left")
	_expect(plan.valid and plan.reason == "replace_invalid_with_raw_support",
			"invalid ground selection was not validated/fallen back")
	_expect(plan.target_source == "raw_recovery", "fallback has incorrect target provenance")
	_expect(plan.proposed_ankle_target == Vector3(3.0, 0.1, 0.0),
			"rejected ground selection missing from diagnostic")
	_expect(plan.ankle_target == legs[&"left"]["target"], "fallback not actual solve input")


func _expect(passed: bool, reason: String) -> void:
	if not passed:
		_failures.append("case=%d %s" % [_cases, reason])
