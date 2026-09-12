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
var _toe_invalid_streak_frames: Dictionary = {} # side -> int, see _limit_correction's guard


func _init(owner) -> void:
	_owner = owner


func reset() -> void:
	_plans.clear()
	_generations.clear()
	_toe_invalid_streak.clear()
	_toe_invalid_streak_frames.clear()


func get_plan(side: StringName) -> FootIKTargetPlan:
	return _plans.get(side) as FootIKTargetPlan


func resolve_stationary(space: PhysicsDirectSpaceState3D,
		per_leg: Dictionary, stationary: bool, delta: float) -> void:
	var legacy_transition_active: bool = (not _owner._ground_sampler.idle_lower_acquiring.is_empty()
			or not _owner._ground_sampler.idle_lower_latched_target.is_empty())
	for side: StringName in per_leg:
		var leg: Dictionary = per_leg[side]
		var plan := _build_plan(space, side, leg, stationary, legacy_transition_active, delta)
		_store_plan(side, plan)
		if plan.valid and plan.reason == "replace_invalid_with_raw_support":
			_apply_raw_recovery(side, leg, plan)
		elif not plan.valid and plan.reason.begins_with("reject_invalid_stationary"):
			leg[&"hit"] = false
			leg[&"target_plan_validated"] = true


func _build_plan(space: PhysicsDirectSpaceState3D, side: StringName, leg: Dictionary,
		stationary: bool, legacy_transition_active: bool, delta: float) -> FootIKTargetPlan:
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
	# LOCOMOTION_LOCK/LOCOMOTION_STANCE only ever occur while the body is translating
	# (foot_ik_gait_tracker.gd gates both behind _body_horizontal_speed() >
	# IDLE_TRANSLATION_EPSILON before ever reporting them), so coordinate_idle's own
	# `stationary` requirement can never hold for them - they need their own gate, and
	# their own stance-zone exemption below (see require_stance): a real walking stride
	# plants the stance foot meaningfully ahead of/behind the root, well outside the
	# idle-sized stance zone. _has_support_at's own raycast reconfirmation - already run
	# for every migrated owner - covers the "is this actually real ground" question
	# without needing a zone at all. See 010's "Locomotion-owner design finding".
	var coordinate_locomotion: bool = (plan.owner in [FootIKTargetPlan.Owner.LOCOMOTION_LOCK,
				FootIKTargetPlan.Owner.LOCOMOTION_STANCE]
			and _owner._landing_grace_time <= 0.0
			and _owner._ground_sampler.landing_committed_target.is_empty()
			and float(leg.get(&"ground_weight", 0.0)) >= PLANT_WEIGHT
			and plan.surface_normal.dot(Vector3.UP) >= FLAT_SUPPORT_DOT)
	# STAIR_SUPPORT can occur while idle or while actively translating up/down stairs, so
	# neither coordinate_idle's `stationary` nor a translating-only gate fits - it needs its
	# own, unconditional-on-animation gate. No ground_weight/flat-normal requirement either:
	# a stair tread's own weight/normal are managed entirely by _apply_support_contact's
	# transfer-blend, not the general per-leg ground_weight path this dict field reflects.
	# See 010's validation design proposal.
	var coordinate_stair := plan.owner == FootIKTargetPlan.Owner.STAIR_SUPPORT
	var migrated_owner := plan.owner in [FootIKTargetPlan.Owner.LIVE_CONTACT,
			FootIKTargetPlan.Owner.IDLE_LOWER_LATCH,
			FootIKTargetPlan.Owner.IDLE_LOWER_ACQUIRE,
			FootIKTargetPlan.Owner.IDLE_STANCE_REHOME,
			FootIKTargetPlan.Owner.LANDING_COMMITMENT,
			FootIKTargetPlan.Owner.LANDING_UPPER,
			FootIKTargetPlan.Owner.IDLE_FREEZE,
			FootIKTargetPlan.Owner.SPLIT_RECOVERY,
			FootIKTargetPlan.Owner.LOCOMOTION_LOCK,
			FootIKTargetPlan.Owner.LOCOMOTION_STANCE,
			FootIKTargetPlan.Owner.STAIR_SUPPORT]
	var owner_is_lower_transition := plan.owner in [FootIKTargetPlan.Owner.IDLE_LOWER_LATCH,
			FootIKTargetPlan.Owner.IDLE_LOWER_ACQUIRE,
			FootIKTargetPlan.Owner.IDLE_STANCE_REHOME]
	if legacy_transition_active and not owner_is_lower_transition:
		migrated_owner = false
	if (not (coordinate_idle or coordinate_landing or coordinate_locomotion
				or coordinate_stair)
			or not migrated_owner):
		plan.stance_status = FootIKTargetPlan.ConstraintStatus.NOT_APPLICABLE
		plan.support_status = (FootIKTargetPlan.ConstraintStatus.SATISFIED if plan.valid
				else FootIKTargetPlan.ConstraintStatus.VIOLATED)
		plan.reach_status = FootIKTargetPlan.ConstraintStatus.NOT_APPLICABLE
		return plan
	if plan.owner == FootIKTargetPlan.Owner.IDLE_LOWER_LATCH:
		plan.reason = "validated_lower_support"
	# IDLE_STANCE_REHOME only activates when its target is already outside the stance zone
	# (see _rehome_idle_stance_target's own early-out) - requiring it be inside would reject
	# every single rehome candidate by definition, since correcting exactly that is its job.
	# SPLIT_RECOVERY holds a foot at a fixed world point while the root is nudged toward
	# split_safe_root_target (see prepare_overheight_split_safe_zone) - the held foot can
	# legitimately sit outside the per-side stance zone mid-nudge, same shape of conflict.
	# LOCOMOTION_LOCK/LOCOMOTION_STANCE hold a real walking stride's stance foot, which sits
	# meaningfully ahead of/behind the root at different points in the gait cycle - the
	# idle-sized stance zone would reject legitimate mid-stride targets outright. Rely on
	# support/reach/toe validation instead of a zone check for these two, same as the other
	# exemptions here. STAIR_SUPPORT's support foot sits on whichever tread the climb is
	# currently on, arbitrarily far from the root along the stair's own axis - same shape
	# of conflict again.
	# IDLE_LOWER_LATCH holds a foot at a fixed WORLD point once settled - is_target_inside_
	# stance_zone measures laterally/longitudinally against the body's CURRENT forward/outward
	# basis, which rotates with the body's yaw. A world-fixed latch that never moved can still
	# fail this check purely because the body kept turning; no frame budget can bound that for
	# a sustained turn, so it's exempted like the others below rather than tolerated for a
	# streak (AGENT_TASKS/019's "clipped out of nowhere" case). support/reach still gate it.
	var require_stance := not plan.owner in [FootIKTargetPlan.Owner.IDLE_STANCE_REHOME,
			FootIKTargetPlan.Owner.IDLE_LOWER_LATCH,
			FootIKTargetPlan.Owner.SPLIT_RECOVERY,
			FootIKTargetPlan.Owner.LOCOMOTION_LOCK,
			FootIKTargetPlan.Owner.LOCOMOTION_STANCE,
			FootIKTargetPlan.Owner.STAIR_SUPPORT]
	# _toe_probe_reaches_higher_surface (foot_ik_stair_predictor.gd) already does
	# stair-specific toe/riser reasoning as part of choosing this owner's own surface - the
	# coordinator's generic toe/leaf envelope check is unverified against that existing logic
	# and could duplicate or conflict with it (see 010's validation design proposal); exempt
	# it here rather than guess.
	var check_toe := plan.owner != FootIKTargetPlan.Owner.STAIR_SUPPORT
	plan = _finish_validation(space, plan, leg, require_stance, delta, check_toe)
	if plan.valid:
		leg[&"target_plan_validated"] = true
		return plan
	var raw_plan := _raw_recovery_plan(space, side, leg, plan, delta)
	if raw_plan.valid:
		return raw_plan
	plan.reason = "reject_invalid_stationary_%s" % plan.reason
	return plan


func _finish_validation(space: PhysicsDirectSpaceState3D, plan: FootIKTargetPlan,
		leg: Dictionary, require_stance: bool, delta: float,
		check_toe: bool = true) -> FootIKTargetPlan:
	const STATUS := FootIKTargetPlan.ConstraintStatus
	if not require_stance:
		plan.stance_status = STATUS.NOT_APPLICABLE
	else:
		plan.stance_status = (STATUS.SATISFIED
				if (_owner._ground_sampler.is_target_inside_stance_zone(
						plan.side, plan.surface_target)
				and _owner._ground_sampler.is_target_inside_stance_zone(
						plan.side, plan.ankle_target))
				else STATUS.VIOLATED)
	# IDLE_LOWER_ACQUIRE's surface_target is a move_toward-interpolated waypoint, not a
	# settled raycast-confirmed surface - mid-transition it can sit at an XZ/Y combination
	# with no real ground directly beneath it even while correctly heading toward one, so
	# validate the actual acquire destination instead of the in-flight waypoint.
	var support_target := plan.surface_target
	if plan.owner == FootIKTargetPlan.Owner.IDLE_LOWER_ACQUIRE:
		support_target = _owner._ground_sampler.idle_lower_acquiring.get(
				plan.side, support_target)
	# STAIR_SUPPORT's smoothed_target can likewise sit in between two real surfaces for
	# several frames (a discrete support-transfer blend, or ordinary smoothing on a steeply-
	# tilted tread) - same shape of conflict, same fix: validate the real surface the
	# predictor is actually converging toward, not its currently-smoothed value.
	elif plan.owner == FootIKTargetPlan.Owner.STAIR_SUPPORT:
		support_target = _owner._stair_predictor.get_current_support_surface_target()
	plan.support_status = (STATUS.SATISFIED if _has_support_at(space, support_target)
			else STATUS.VIOLATED)
	var hip: Vector3 = leg.get(&"hip_pos", Vector3.ZERO)
	var reach: float = float(leg.get(&"upper", 0.0)) + float(leg.get(&"lower", 0.0))
	plan.reach_status = (STATUS.SATISFIED
			if hip.distance_to(plan.ankle_target) <= reach + _owner.step_down_max_crouch
			else STATUS.VIOLATED)
	# Raw recovery (check_toe=false) is already the fallback for a rejected primary
	# candidate; vetoing it with the same check that rejected the primary would leave
	# the leg with no target at all (full release to raw animation, which floats badly
	# on uneven ground) instead of a small, better-than-nothing toe overlap.
	if not check_toe:
		plan.toe_status = STATUS.NOT_APPLICABLE
	else:
		var envelope_ok := _toe_envelope_valid(space, plan)
		plan.toe_status = STATUS.SATISFIED if envelope_ok else STATUS.VIOLATED
		if _streak_tolerated(_toe_invalid_streak, _toe_invalid_streak_frames,
				plan.side, not envelope_ok, TOE_INVALID_HOLD_FRAMES, delta):
			plan.toe_status = STATUS.TEMPORARILY_TOLERATED
	plan.valid = (plan.valid and FootIKTargetPlan.constraint_ok(plan.stance_status)
			and FootIKTargetPlan.constraint_ok(plan.support_status)
			and FootIKTargetPlan.constraint_ok(plan.reach_status)
			and FootIKTargetPlan.constraint_ok(plan.toe_status))
	if plan.stance_status == STATUS.VIOLATED:
		plan.reason = "outside_stance"
	elif plan.support_status == STATUS.VIOLATED:
		plan.reason = "unsupported"
	elif plan.reach_status == STATUS.VIOLATED:
		plan.reason = "unreachable"
	elif plan.toe_status == STATUS.VIOLATED:
		plan.reason = "toe_envelope_blocked"
	return plan


## True while `violated` should still be tolerated rather than rejected outright: false once
## a fresh violation streak (tracked per side in `streak_dict`/`frame_dict`) reaches
## `hold_frames`. A zero-delta or already-advanced-this-frame call must not consume the
## streak budget - see _limit_correction's identical guard in foot_ik_leg_solver.gd.
func _streak_tolerated(streak_dict: Dictionary, frame_dict: Dictionary, side: StringName,
		violated: bool, hold_frames: int, delta: float) -> bool:
	var current_frame := Engine.get_physics_frames()
	var prev_streak: int = int(streak_dict.get(side, 0))
	var streak: int = prev_streak
	if delta > 0.0 and int(frame_dict.get(side, -1)) != current_frame:
		streak = 0 if not violated else prev_streak + 1
		streak_dict[side] = streak
		frame_dict[side] = current_frame
	return violated and streak < hold_frames


## Rejects a plan whose ankle target is valid but whose toe/leaf reach - at this frame's
## animated foot orientation - lands on a surface higher than the ankle's own tread (the
## right-foot clip from AGENT_TASKS/008: a valid ankle latch with the toe poking into the
## next riser). A miss (nothing beneath the toe reach) is a reach/void concern handled
## elsewhere, not this check's job, so it passes here.
func _toe_envelope_valid(space: PhysicsDirectSpaceState3D, plan: FootIKTargetPlan) -> bool:
	return _toe_envelope_valid_at(space, plan, plan.ankle_target)
## Same check against a candidate ankle_target other than the plan's own - lets a retreat
## search (below) probe positions without mutating the plan being evaluated.
func _toe_envelope_valid_at(space: PhysicsDirectSpaceState3D,
		plan: FootIKTargetPlan, ankle_target: Vector3) -> bool:
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
	var toe_point: Vector3 = ankle_target + tip_offset
	var query := PhysicsPointQueryParameters3D.new()
	query.position = toe_point
	query.collision_mask = FootIKGroundSampler.GROUND_COLLISION_MASK
	query.collide_with_areas = false
	return space.intersect_point(query, 4).is_empty()


func _raw_recovery_plan(space: PhysicsDirectSpaceState3D, side: StringName,
		leg: Dictionary, rejected: FootIKTargetPlan, delta: float) -> FootIKTargetPlan:
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
	return _finish_validation(space, plan, leg, true, delta, false)


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
	# A leg mid idle-lower reposition (or freshly latched) commits like a real step: once
	# claimed, it must finish and plant before LANDING_UPPER's knee-straightening - an
	# unrelated mechanism - can seize the same leg and substitute a discontinuous target
	# mid-flight (see AGENT_TASKS/019's "clipped out of nowhere" case).
	elif sampler.idle_lower_acquiring.has(side):
		result = FootIKTargetPlan.Owner.IDLE_LOWER_ACQUIRE
	elif sampler.idle_lower_latched_target.has(side):
		result = FootIKTargetPlan.Owner.IDLE_LOWER_LATCH
	elif sampler.landing_upper_confirmed.has(side):
		result = FootIKTargetPlan.Owner.LANDING_UPPER
	elif sampler.split_safe_held_upper_target.has(side):
		result = FootIKTargetPlan.Owner.SPLIT_RECOVERY
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
