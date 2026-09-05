class_name FootIKTargetCoordinator
extends RefCounted
## Selects the sole target owner that may feed each leg solve.
##
## Existing feature modules still produce candidates during migration. This
## coordinator is the final policy boundary: stationary idle candidates are
## validated here before pelvis or bone solving, and an invalid retained target
## can never rely on a later pose correction to make it safe.

const TARGET_PLAN := preload("res://actors/player/foot_ik/foot_ik_target_plan.gd")
const PLANT_WEIGHT := 0.95
const FLAT_SUPPORT_DOT := 0.999
const SUPPORT_HEIGHT_TOLERANCE := 0.03

var _owner
var _plans: Dictionary = {}
var _generations: Dictionary = {}


func _init(owner) -> void:
	_owner = owner


func reset() -> void:
	_plans.clear()
	_generations.clear()


func get_plan(side: StringName) -> FootIKTargetPlan:
	return _plans.get(side) as FootIKTargetPlan


func resolve_stationary(space: PhysicsDirectSpaceState3D,
		per_leg: Dictionary, stationary: bool) -> void:
	var legacy_transition_active: bool = (not _owner._ground_sampler.idle_lower_acquiring.is_empty()
			or not _owner._ground_sampler.idle_lower_latched_target.is_empty())
	for side: StringName in per_leg:
		var leg: Dictionary = per_leg[side]
		var plan := _build_plan(space, side, leg, stationary, legacy_transition_active)
		_store_plan(side, plan)
		if plan.valid and plan.reason == "replace_invalid_with_raw_support":
			_apply_raw_recovery(side, leg, plan)
		elif not plan.valid and plan.reason.begins_with("reject_invalid_stationary"):
			leg[&"hit"] = false
			leg[&"target_plan_validated"] = true


func _build_plan(space: PhysicsDirectSpaceState3D, side: StringName,
		leg: Dictionary, stationary: bool, legacy_transition_active: bool) -> FootIKTargetPlan:
	var plan := TARGET_PLAN.new() as FootIKTargetPlan
	plan.side = side
	plan.owner = _legacy_owner(side)
	plan.raw_surface = leg.get(&"raw_target", Vector3.ZERO)
	plan.surface_target = _owner._ground_sampler.smoothed_target.get(
			side, plan.raw_surface)
	plan.surface_normal = _owner._ground_sampler.smoothed_normal.get(
			side, leg.get(&"raw_normal", Vector3.UP))
	plan.ankle_target = leg.get(&"target", leg.get(&"ground_target", Vector3.ZERO))
	plan.valid = bool(leg.get(&"hit", false))
	plan.reason = "selected_legacy_candidate"
	var animation_name := String(_owner.player_body.anim_player.current_animation.get_file())
	var coordinate_idle: bool = (stationary and animation_name.contains("idle")
			and not animation_name.contains("crouch")
			and _owner._landing_grace_time <= 0.0
			and _owner._ground_sampler.landing_committed_target.is_empty()
			and float(leg.get(&"ground_weight", 0.0)) >= PLANT_WEIGHT
			and plan.surface_normal.dot(Vector3.UP) >= FLAT_SUPPORT_DOT)
	var migrated_owner := plan.owner in [FootIKTargetPlan.Owner.LIVE_CONTACT,
			FootIKTargetPlan.Owner.IDLE_LOWER_LATCH,
			FootIKTargetPlan.Owner.IDLE_FREEZE]
	if legacy_transition_active and plan.owner != FootIKTargetPlan.Owner.IDLE_LOWER_LATCH:
		migrated_owner = false
	if not coordinate_idle or not migrated_owner:
		plan.stance_valid = true
		plan.support_valid = plan.valid
		plan.reach_valid = true
		return plan
	if plan.owner == FootIKTargetPlan.Owner.IDLE_LOWER_LATCH:
		plan.reason = "validated_lower_support"
	plan = _finish_validation(space, plan, leg, true)
	if plan.valid:
		leg[&"target_plan_validated"] = true
		return plan
	var raw_plan := _raw_recovery_plan(space, side, leg, plan)
	if raw_plan.valid:
		return raw_plan
	plan.reason = "reject_invalid_stationary_%s" % plan.reason
	return plan


func _finish_validation(space: PhysicsDirectSpaceState3D, plan: FootIKTargetPlan,
		leg: Dictionary, require_stance: bool) -> FootIKTargetPlan:
	plan.stance_valid = (not require_stance
			or (_owner._ground_sampler.is_target_inside_stance_zone(
					plan.side, plan.surface_target)
			and _owner._ground_sampler.is_target_inside_stance_zone(
						plan.side, plan.ankle_target)))
	plan.support_valid = _has_support_at(space, plan.surface_target)
	var hip: Vector3 = leg.get(&"hip_pos", Vector3.ZERO)
	var reach: float = float(leg.get(&"upper", 0.0)) + float(leg.get(&"lower", 0.0))
	plan.reach_valid = hip.distance_to(plan.ankle_target) \
			<= reach + _owner.step_down_max_crouch
	plan.valid = plan.valid and plan.stance_valid and plan.support_valid and plan.reach_valid
	if not plan.stance_valid:
		plan.reason = "outside_stance"
	elif not plan.support_valid:
		plan.reason = "unsupported"
	elif not plan.reach_valid:
		plan.reason = "unreachable"
	return plan


func _raw_recovery_plan(space: PhysicsDirectSpaceState3D, side: StringName,
		leg: Dictionary, rejected: FootIKTargetPlan) -> FootIKTargetPlan:
	var plan := TARGET_PLAN.new() as FootIKTargetPlan
	plan.side = side
	plan.owner = FootIKTargetPlan.Owner.LIVE_CONTACT
	plan.raw_surface = leg.get(&"raw_target", Vector3.ZERO)
	plan.surface_target = plan.raw_surface
	plan.surface_normal = leg.get(&"raw_normal", Vector3.UP)
	var offset: float = float(leg.get(&"effective_offset", _owner.ankle_offset))
	plan.ankle_target = plan.surface_target + plan.surface_normal * offset
	var height_continuous: bool = _owner._ground_sampler._settings \
			.allows_support_height_difference(plan.surface_target.y - rejected.surface_target.y)
	plan.valid = bool(leg.get(&"hit", false)) and height_continuous \
			and plan.surface_normal.dot(Vector3.UP) >= FLAT_SUPPORT_DOT
	plan.reason = "replace_invalid_with_raw_support"
	return _finish_validation(space, plan, leg, true)


func _has_support_at(space: PhysicsDirectSpaceState3D, surface: Vector3) -> bool:
	if not surface.is_finite():
		return false
	var hit: Dictionary = _owner._ground_sampler.raycast_ground(
			space, surface + Vector3.UP * 0.2, 0.4)
	return (bool(hit.get(&"hit", false))
			and (hit.get(&"normal", Vector3.UP) as Vector3).dot(Vector3.UP) >= FLAT_SUPPORT_DOT
			and absf((hit.get(&"position", surface) as Vector3).y - surface.y)
			<= SUPPORT_HEIGHT_TOLERANCE)


func _apply_raw_recovery(side: StringName, leg: Dictionary,
		plan: FootIKTargetPlan) -> void:
	_owner._ground_sampler.smoothed_target[side] = plan.surface_target
	_owner._ground_sampler.smoothed_normal[side] = plan.surface_normal
	_owner._ground_sampler.idle_stance_rehoming[side] = plan.surface_target
	_owner._ground_sampler.idle_lower_latched_target.erase(side)
	_owner._ground_sampler.idle_lower_acquiring.erase(side)
	_owner._gait_tracker.invalidate_idle_freeze(side)
	_owner._solved_target_smoothed.erase(side)
	leg[&"target"] = plan.ankle_target
	leg[&"ground_target"] = plan.ankle_target
	leg[&"preserve_idle_pose"] = false
	leg[&"target_plan_validated"] = true


func _store_plan(side: StringName, plan: FootIKTargetPlan) -> void:
	var previous := _plans.get(side) as FootIKTargetPlan
	var generation: int = int(_generations.get(side, 0))
	if previous == null or previous.owner != plan.owner or previous.reason != plan.reason:
		generation += 1
	_generations[side] = generation
	plan.generation = generation
	_plans[side] = plan


func _legacy_owner(side: StringName) -> FootIKTargetPlan.Owner:
	var sampler = _owner._ground_sampler
	var result := FootIKTargetPlan.Owner.LIVE_CONTACT
	if sampler.landing_committed_target.has(side):
		result = FootIKTargetPlan.Owner.LANDING_COMMITMENT
	elif sampler.landing_upper_confirmed.has(side):
		result = FootIKTargetPlan.Owner.LANDING_UPPER
	elif sampler.idle_lower_acquiring.has(side):
		result = FootIKTargetPlan.Owner.IDLE_LOWER_ACQUIRE
	elif sampler.idle_lower_latched_target.has(side):
		result = FootIKTargetPlan.Owner.IDLE_LOWER_LATCH
	elif sampler.idle_stance_rehoming.has(side):
		result = FootIKTargetPlan.Owner.IDLE_STANCE_REHOME
	elif bool(_owner._idle_frozen.get(side, false)):
		result = FootIKTargetPlan.Owner.IDLE_FREEZE
	elif _owner._forced_support_side == side:
		result = FootIKTargetPlan.Owner.STAIR_SUPPORT
	elif _owner.predicted_step_targets.has(side):
		result = FootIKTargetPlan.Owner.STAIR_SWING
	elif _owner._gait_tracker.is_locomotion_target_locked(side):
		result = FootIKTargetPlan.Owner.LOCOMOTION_LOCK
	elif _owner._gait_tracker.is_locomotion_stance_active(side):
		result = FootIKTargetPlan.Owner.LOCOMOTION_STANCE
	return result
