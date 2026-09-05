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
## Consecutive failing frames the toe/leaf envelope check must accumulate before it actually
## rejects a plan - a brief mid-turn sweep near real geometry must not pop the pose to the
## raw-recovery fallback and back; only a sustained block should. Same idea as
## min_falling_streak/STEP_DOWN_STATIC_STREAK elsewhere in this system.
const TOE_INVALID_HOLD_FRAMES := 10

var _owner
var _plans: Dictionary = {}
var _generations: Dictionary = {}
var _toe_invalid_streak: Dictionary = {} # side -> int


func _init(owner) -> void:
	_owner = owner


func reset() -> void:
	_plans.clear()
	_generations.clear()
	_toe_invalid_streak.clear()


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
	# LANDING_COMMITMENT structurally fails coordinate_idle above (its own existence means
	# landing_committed_target is non-empty, and its animation may be jump_land, not idle) -
	# it needs its own gate. _committed_landing_hit() already reconfirms real ground support
	# under the committed point every frame before this owner is ever reported, so this only
	# adds stance-zone/reach/toe checks on top of an already-reconfirmed surface.
	var coordinate_landing: bool = (plan.owner == FootIKTargetPlan.Owner.LANDING_COMMITMENT
			and _owner._landing_grace_time <= 0.0
			and plan.surface_normal.dot(Vector3.UP) >= FLAT_SUPPORT_DOT)
	var migrated_owner := plan.owner in [FootIKTargetPlan.Owner.LIVE_CONTACT,
			FootIKTargetPlan.Owner.IDLE_LOWER_LATCH,
			FootIKTargetPlan.Owner.LANDING_COMMITMENT,
			FootIKTargetPlan.Owner.LANDING_UPPER,
			FootIKTargetPlan.Owner.IDLE_FREEZE]
	if legacy_transition_active and plan.owner != FootIKTargetPlan.Owner.IDLE_LOWER_LATCH:
		migrated_owner = false
	if not (coordinate_idle or coordinate_landing) or not migrated_owner:
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
		leg: Dictionary, require_stance: bool, check_toe: bool = true) -> FootIKTargetPlan:
	plan.stance_valid = (not require_stance
			or (_owner._ground_sampler.is_target_inside_stance_zone(
					plan.side, plan.surface_target)
			and _owner._ground_sampler.is_target_inside_stance_zone(
						plan.side, plan.ankle_target)))
	# IDLE_LOWER_ACQUIRE's surface_target is a move_toward-interpolated waypoint, not a
	# settled raycast-confirmed surface - mid-transition it can sit at an XZ/Y combination
	# with no real ground directly beneath it even while correctly heading toward one, so
	# validate the actual acquire destination instead of the in-flight waypoint.
	var support_target := plan.surface_target
	if plan.owner == FootIKTargetPlan.Owner.IDLE_LOWER_ACQUIRE:
		support_target = _owner._ground_sampler.idle_lower_acquiring.get(
				plan.side, support_target)
	plan.support_valid = _has_support_at(space, support_target)
	var hip: Vector3 = leg.get(&"hip_pos", Vector3.ZERO)
	var reach: float = float(leg.get(&"upper", 0.0)) + float(leg.get(&"lower", 0.0))
	plan.reach_valid = hip.distance_to(plan.ankle_target) \
			<= reach + _owner.step_down_max_crouch
	# Raw recovery (check_toe=false) is already the fallback for a rejected primary
	# candidate; vetoing it with the same check that rejected the primary would leave
	# the leg with no target at all (full release to raw animation, which floats badly
	# on uneven ground) instead of a small, better-than-nothing toe overlap.
	plan.toe_valid = true if not check_toe else _toe_envelope_valid(space, plan)
	if check_toe:
		var streak: int = (0 if plan.toe_valid
				else int(_toe_invalid_streak.get(plan.side, 0)) + 1)
		_toe_invalid_streak[plan.side] = streak
		plan.toe_valid = plan.toe_valid or streak < TOE_INVALID_HOLD_FRAMES
	plan.valid = (plan.valid and plan.stance_valid and plan.support_valid
			and plan.reach_valid and plan.toe_valid)
	if not plan.stance_valid:
		plan.reason = "outside_stance"
	elif not plan.support_valid:
		plan.reason = "unsupported"
	elif not plan.reach_valid:
		plan.reason = "unreachable"
	elif not plan.toe_valid:
		plan.reason = "toe_envelope_blocked"
	return plan


## Rejects a plan whose ankle target is valid but whose toe/leaf reach - at this frame's
## animated foot orientation - lands on a surface higher than the ankle's own tread (the
## right-foot clip from AGENT_TASKS/008: a valid ankle latch with the toe poking into the
## next riser). A miss (nothing beneath the toe reach) is a reach/void concern handled
## elsewhere, not this check's job, so it passes here.
func _toe_envelope_valid(space: PhysicsDirectSpaceState3D, plan: FootIKTargetPlan) -> bool:
	var toe_local: Vector3 = _owner._toe_rest_offset.get(plan.side, Vector3.ZERO)
	var leaf_local: Vector3 = _owner._leaf_rest_offset.get(plan.side, Vector3.ZERO)
	if toe_local.is_zero_approx() and leaf_local.is_zero_approx():
		return true
	var fresh: Dictionary = _owner._leg_fresh_pose_cache.get(plan.side, {})
	if not fresh.has(&"foot"):
		return true
	var skel: Skeleton3D = _owner.get_skeleton()
	if skel == null:
		return true
	var foot_pose: Transform3D = fresh[&"foot"]
	var foot_basis: Basis = _owner._compute_new_foot_basis_world(
			skel, plan.side, -plan.surface_normal, foot_pose)
	# The leaf bone (a child of the toe) usually reaches farther than the toe
	# itself plus its tip margin - check whichever extremity actually reaches
	# farthest, not just the toe (the right-foot clip in 008 was a leaf clip).
	var candidates: Array[Vector3] = []
	if not toe_local.is_zero_approx():
		var toe_offset: Vector3 = foot_basis * toe_local
		candidates.append(toe_offset + toe_offset.normalized() * float(_owner.toe_tip_margin))
	if not leaf_local.is_zero_approx():
		candidates.append(foot_basis * leaf_local)
	if candidates.is_empty():
		return true
	var tip_offset: Vector3 = candidates[0]
	for candidate: Vector3 in candidates:
		if Vector2(candidate.x, candidate.z).length_squared() \
				> Vector2(tip_offset.x, tip_offset.z).length_squared():
			tip_offset = candidate
	# A downward raycast from above the toe's XZ column would flag any nearby
	# taller surface as an obstruction, even a separate platform with open air
	# beneath it (e.g. a split-height stance where this foot's toe legitimately
	# reaches back under the body toward the other foot's higher surface).
	# Test the toe's own candidate point directly instead - only a point that is
	# actually embedded in solid geometry is a real clip.
	var toe_point: Vector3 = plan.ankle_target + tip_offset
	var query := PhysicsPointQueryParameters3D.new()
	query.position = toe_point
	query.collision_mask = FootIKGroundSampler.GROUND_COLLISION_MASK
	query.collide_with_areas = false
	return space.intersect_point(query, 4).is_empty()


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
	return _finish_validation(space, plan, leg, true, false)


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
