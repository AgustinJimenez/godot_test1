extends Node3D
## Controlled coordinator contract checks; terrain/skin replays remain separate acceptance gates.

class Sampler extends RefCounted:
	var compressed_upper_target: Dictionary = {}
	var idle_stance_rehoming: Dictionary = {}
	const IDLE_STANCE_REHOME_MARGIN := 0.05
	var stance_ok := true
	func is_target_inside_stance_zone(_side: StringName, _point: Vector3,
			_margin: float = 0.0) -> bool:
		return stance_ok
	func raycast_ground(space: PhysicsDirectSpaceState3D, origin: Vector3,
			length: float) -> Dictionary:
		var query := PhysicsRayQueryParameters3D.create(origin, origin + Vector3.DOWN * length, 1)
		var hit := space.intersect_ray(query)
		return {"hit": not hit.is_empty(), "position": hit.get("position", origin),
				"normal": hit.get("normal", Vector3.UP)}

class Owner extends RefCounted:
	var _ground_sampler := Sampler.new()
	var step_down_max_crouch := 0.4
	var player_body: Node3D

class Coordinator extends FootIKTargetCoordinator:
	var support_ok := true
	var toe_ok := true
	var observed_support := Vector3.ZERO
	func _contact_space() -> PhysicsDirectSpaceState3D:
		return null
	func _has_contact_support(_space: PhysicsDirectSpaceState3D, surface: Vector3,
			_normal: Vector3) -> bool:
		observed_support = surface
		return support_ok
	func _sample_contact_support(_space: PhysicsDirectSpaceState3D, estimate: Vector3,
			_normal: Vector3) -> Dictionary:
		observed_support = estimate
		return {"ok": support_ok, "position": estimate}
	func _toe_envelope_valid_at(_space: PhysicsDirectSpaceState3D,
			_plan: FootIKTargetPlan, _target: Vector3) -> bool:
		return toe_ok

var _failures: Array[String] = []
var _cases := 0

func _ready() -> void:
	for mode in ["accept", "unsupported", "outside_stance", "unreachable", "nonfinite",
			"toe_blocked", "raw_recovery", "acquiring", "slope"]:
		_check_adjustment(mode)
	for mode in ["hold", "expired", "unsupported", "unreachable", "outside_stance",
			"released", "reset"]:
		_check_reference(mode)
	await _check_geometry()
	print("FOOT_IK_FINAL_TARGET_CONTRACT_CHECK %s cases=%d failures=%s" % [
			"PASS" if _failures.is_empty() else "FAIL", _cases, _failures])
	get_tree().quit(0 if _failures.is_empty() else 1)

func _plan() -> FootIKTargetPlan:
	var plan := FootIKTargetPlan.new()
	plan.side = &"left"
	plan.valid = true
	plan.owner = FootIKTargetPlan.Owner.LIVE_CONTACT
	plan.ankle_target = Vector3(0.2, 0.1, 0.0)
	plan.surface_target = Vector3(0.2, 0.0, 0.0)
	plan.stance_status = FootIKTargetPlan.ConstraintStatus.SATISFIED
	plan.support_status = FootIKTargetPlan.ConstraintStatus.SATISFIED
	plan.reach_status = FootIKTargetPlan.ConstraintStatus.SATISFIED
	plan.toe_status = FootIKTargetPlan.ConstraintStatus.SATISFIED
	return plan

func _leg() -> Dictionary:
	return {"hip_pos": Vector3(0.2, 0.95, 0.0), "upper": 0.5, "lower": 0.5,
			"target_plan_validated": true, "hit": true}

func _check_adjustment(mode: String) -> void:
	_cases += 1
	var owner_state := Owner.new()
	var coordinator := Coordinator.new(owner_state)
	var plan := _plan()
	var leg := _leg()
	var original := plan.ankle_target
	var candidate := original + Vector3.FORWARD * 0.02
	if mode == "unsupported": coordinator.support_ok = false
	if mode == "outside_stance": owner_state._ground_sampler.stance_ok = false
	if mode == "unreachable": candidate += Vector3.DOWN * 3.0
	if mode == "nonfinite": candidate = Vector3(INF, INF, INF)
	if mode == "toe_blocked": coordinator.toe_ok = false
	if mode == "raw_recovery":
		plan.target_source = "raw_recovery"
		plan.toe_status = FootIKTargetPlan.ConstraintStatus.NOT_APPLICABLE
		coordinator.toe_ok = false
	if mode == "acquiring":
		owner_state._ground_sampler.compressed_upper_target[&"left"] = Vector3(0.3, 0.0, 0.0)
	if mode == "slope":
		leg["stationary_slope"] = true
		plan.surface_normal = Vector3(0.0, 1.0, 0.3).normalized()
		plan.support_status = FootIKTargetPlan.ConstraintStatus.NOT_CHECKED
	var accepted := coordinator._accept_final_target(null, plan, leg, candidate)
	var should_accept := mode in ["accept", "raw_recovery", "acquiring", "slope"]
	_expect(accepted == (candidate if should_accept else original), mode + ": wrong decision")
	_expect(plan.ankle_target == accepted, mode + ": plan/input mismatch")
	_expect(plan.adjusted_ankle_target == candidate, mode + ": lost proposed adjustment")
	coordinator._store_plan(&"left", plan)
	_expect(not coordinator.record_solve_target(&"left", accepted + Vector3.RIGHT * 0.0001, true),
			mode + ": finalized target lent validation to a later override")
	if should_accept:
		_expect(not leg["target_plan_validated"], mode + ": changed legacy solver guard policy")
		_expect(plan.final_adjustment_reason == "accepted_adjustment", mode + ": missing acceptance")
	else:
		_expect(plan.final_adjustment_reason.begins_with("rejected_"), mode + ": missing rejection")
	if mode == "acquiring":
		_expect(coordinator.observed_support == Vector3(0.3, 0.0, 0.0),
				"acquiring: checked airborne waypoint instead of destination")
	if mode == "accept":
		_expect(coordinator.observed_support == plan.surface_target,
				"accept: support check does not describe accepted target")

func _check_reference(mode: String) -> void:
	_cases += 1
	var owner_state := Owner.new()
	var coordinator := Coordinator.new(owner_state)
	var plan := _plan()
	var leg := _leg()
	coordinator._store_plan(&"left", plan)
	coordinator._remember_pelvis_reference(&"left", plan, plan.ankle_target)
	plan.target_source = "raw_recovery"
	var fallback := Vector3(0.3, 0.1, 0.0)
	leg["pelvis_basis_target"] = fallback
	if mode == "expired":
		coordinator._pelvis_references[&"left"].frame -= FootIKTargetCoordinator.PELVIS_HOLD_TICKS
	if mode == "unsupported": coordinator.support_ok = false
	if mode == "unreachable": leg["hip_pos"] = Vector3(5.0, 1.0, 0.0)
	if mode == "outside_stance": owner_state._ground_sampler.stance_ok = false
	if mode == "released":
		coordinator.finalize_leg_targets({&"left": {"hit": false}}, 0.0,
				Vector3.ZERO, Transform3D.IDENTITY, 0.0, false, true)
	if mode == "reset": coordinator.reset()
	var actual := coordinator.pelvis_reference_target(&"left", leg, Vector3.ZERO)
	_expect(actual == (plan.ankle_target if mode == "hold" else fallback),
			mode + ": incorrect cached-reference lifetime")
	if mode != "hold":
		_expect(coordinator._pelvis_references.is_empty(), mode + ": invalid cache not cleared")
	else:
		var frame: int = coordinator._pelvis_references[&"left"].frame
		coordinator.pelvis_reference_target(&"left", leg, Vector3.ZERO)
		_expect(coordinator._pelvis_references[&"left"].frame == frame,
				"repeated refresh renewed a recovery lease")

func _expect(passed: bool, reason: String) -> void:
	if not passed: _failures.append(reason)

func _check_geometry() -> void:
	var body := StaticBody3D.new()
	var collision := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(1.0, 0.2, 1.0)
	collision.shape = box
	body.add_child(collision)
	add_child(body)
	body.rotation.x = deg_to_rad(25.0)
	body.position.y = -0.1
	for _frame in 30: await get_tree().physics_frame
	var owner_state := Owner.new()
	owner_state.player_body = self
	var coordinator := FootIKTargetCoordinator.new(owner_state)
	var plan := _plan()
	plan.surface_target = body.global_transform * Vector3(0.0, 0.1, 0.0)
	plan.surface_normal = body.global_basis.y.normalized()
	plan.ankle_target = plan.surface_target + plan.surface_normal * 0.1
	plan.toe_status = FootIKTargetPlan.ConstraintStatus.NOT_CHECKED
	var leg := _leg()
	leg["stationary_slope"] = true
	leg["hip_pos"] = plan.ankle_target + Vector3.UP * 0.8
	var space := get_world_3d().direct_space_state
	_cases += 1
	_expect(not coordinator._has_contact_support(space, plan.surface_target, Vector3.UP),
			"real geometry: mismatched normal accepted")
	_cases += 1
	var inside := plan.ankle_target + Vector3.RIGHT * 0.1
	_expect(coordinator._accept_final_target(space, plan, leg, inside) == inside,
			"real geometry: valid slope adjustment rejected")
	_cases += 1
	_expect(coordinator._accept_final_target(space, plan, leg, inside + Vector3.RIGHT * 0.6) == inside,
			"real geometry: adjustment beyond finite ramp edge accepted")
	_expect(plan.final_adjustment_reason == "rejected_unsupported",
			"real geometry: ramp-edge rejection did not test support")
	_cases += 1
	coordinator._store_plan(&"left", plan)
	coordinator._remember_pelvis_reference(&"left", plan, inside)
	plan.target_source = "raw_recovery"
	leg["pelvis_basis_target"] = inside + Vector3.RIGHT * 0.02
	collision.disabled = true
	for _frame in 2: await get_tree().physics_frame
	_expect(coordinator.pelvis_reference_target(&"left", leg, Vector3.ZERO)
			== leg["pelvis_basis_target"], "real geometry: removed support retained pelvis cache")
	_expect(plan.pelvis_reference_reason == "unsupported",
			"real geometry: removed-support reason missing")
	body.queue_free()
