class_name FootIKTargetCoordinator
extends RefCounted
## Selects the sole target owner that may feed each leg solve.
##
## Existing feature modules still produce candidates during migration. This
## coordinator is the final policy boundary: stationary idle candidates are
## validated here before pelvis or bone solving, and an invalid retained target
## can never rely on a later pose correction to make it safe.

const TARGET_PLAN := preload("res://actors/player/foot_ik/foot_ik_target_plan.gd")
const PENETRATION_MONITOR := preload("res://tools/foot_ik/foot_ik_live_penetration_monitor.gd")
const PLANT_WEIGHT := 0.95
const FLAT_SUPPORT_DOT := 0.999
const SUPPORT_HEIGHT_TOLERANCE := 0.03
## Consecutive failing frames the toe/leaf envelope check must accumulate before it actually
## rejects a plan - a brief mid-turn sweep near real geometry must not pop the pose to the
## raw-recovery fallback and back; only a sustained block should. Same idea as
## min_falling_streak/STEP_DOWN_STATIC_STREAK elsewhere in this system.
const TOE_INVALID_HOLD_FRAMES := 10
## A rejected final adjustment holds the last accepted output for this many frames rather than
## snapping to this frame's un-adjusted base solve - a brief, sustained loss (e.g. a downhill
## nudge overshooting a finite ramp's edge for a few consecutive frames) must not pop the pose.
const FINAL_HOLD_FRAMES := 2
## Recovery may borrow a supported reference for at most 12 physics ticks (0.2 s at 60 Hz).
const PELVIS_HOLD_TICKS := 12
const POSE_PENETRATION_TRIGGER_M := 0.002
const POSE_CLEARANCE_MARGIN_M := 0.012
const POSE_CLEARANCE_CORRECTIONS := 3

class PelvisReference extends RefCounted:
	var target: Vector3
	var surface: Vector3
	var normal: Vector3
	var frame: int
	var require_stance: bool

var _owner
var _plans: Dictionary = {}
var _generations: Dictionary = {}
var _toe_invalid_streak: Dictionary = {} # side -> int
var _toe_invalid_streak_frames: Dictionary = {} # side -> int, see _limit_correction's guard
var _pelvis_references: Dictionary = {} # side -> PelvisReference
var _last_final_targets: Dictionary = {} # side -> Vector3, see _accept_final_target's hold
var _last_final_frames: Dictionary = {} # side -> int
var _idle_pelvis_hold: Dictionary = {} # side -> Vector3, last pre-rehome pelvis basis (021-023)


func _init(owner) -> void:
	_owner = owner


func reset() -> void:
	_plans.clear()
	_generations.clear()
	_toe_invalid_streak.clear()
	_toe_invalid_streak_frames.clear()
	_pelvis_references.clear()
	_last_final_targets.clear()
	_last_final_frames.clear()
	_idle_pelvis_hold.clear()


func get_plan(side: StringName) -> FootIKTargetPlan:
	return _plans.get(side) as FootIKTargetPlan


## Candidate-local stair clearance: measure the actual constrained toe, then reevaluate the same
## target with only a foot-pitch correction. No rejected history or target displacement escapes.
func solve_leg_candidate(skel: Skeleton3D, space: PhysicsDirectSpaceState3D,
		side: StringName, context: Dictionary) -> void:
	var solver = _owner._leg_solver
	var perf_start_usec: int = solver._begin_perf_sample()
	var dbg_cap := FootIKDebug.begin()
	var input: FootIKLegSolveInput = solver.capture_input(skel, side)
	FootIKDebug.end(&"capture", dbg_cap)
	var options: Dictionary = context[&"options"]
	var dbg_eval := FootIKDebug.begin()
	var result: FootIKLegPoseResult = solver.evaluate_candidate(
			input, context[&"hip"], context[&"target"], context[&"upper"], context[&"lower"],
			context[&"ground_weight"], context[&"chain_weight"], context[&"delta"], options)
	FootIKDebug.end(&"solve", dbg_eval)
	# The stair predictor can release at the top transition before the trailing walking toe
	# clears the final tread. Keep the same measured-pose safety active while translating;
	# it remains inert unless a candidate point is actually inside horizontal geometry.
	var stair_clearance_active: bool = (_owner._stair_predictor.is_active()
			or _owner._stair_predictor.is_descending_treads()) and _walking_animation()
	if result.has_pose and stair_clearance_active and FootIKDebug.subsystem_on(&"toe_clearance"):
		var dbg_clr := FootIKDebug.begin()
		var points := _candidate_points(result)
		var clearance := PENETRATION_MONITOR.check(space, points,
				FootIKGroundSampler.GROUND_COLLISION_MASK)
		if (clearance["penetrating"]
				and float(clearance["depth_m"]) > POSE_PENETRATION_TRIGGER_M):
			var point: Vector3 = clearance["point"]
			var surface: Dictionary = _owner._ground_sampler.raycast_ground(
					space, point + Vector3.UP * 0.5, 1.0)
			var surface_normal: Vector3 = surface.get("normal", Vector3.UP)
			if (surface["hit"] and surface_normal.dot(Vector3.UP) >= FLAT_SUPPORT_DOT
					and (surface["position"] as Vector3).y > point.y):
				var retry_options := options.duplicate()
				retry_options[&"instant"] = true
				var retry_target: Vector3 = context[&"target"]
				var retry_surface_y: float = (surface["position"] as Vector3).y
				# The deepest point can move from one tread into the next as pitch changes.
				# Resample that point before every residual lift instead of reusing the first
				# tread's height. The final iteration evaluates the third correction.
				for attempt in POSE_CLEARANCE_CORRECTIONS + 1:
					retry_options[&"toe_clearance_surface_y"] = retry_surface_y
					result = solver.evaluate_candidate(input, context[&"hip"], retry_target,
							context[&"upper"], context[&"lower"], context[&"ground_weight"],
							1.0, context[&"delta"], retry_options)
					var retry_clearance := PENETRATION_MONITOR.check(space,
							_candidate_points(result), FootIKGroundSampler.GROUND_COLLISION_MASK)
					if (not retry_clearance["penetrating"] or float(
							retry_clearance["depth_m"]) <= POSE_PENETRATION_TRIGGER_M):
						break
					if attempt >= POSE_CLEARANCE_CORRECTIONS:
						break
					var retry_point: Vector3 = retry_clearance["point"]
					var retry_surface: Dictionary = _owner._ground_sampler.raycast_ground(
							space, retry_point + Vector3.UP * 0.5, 1.0)
					var retry_normal: Vector3 = retry_surface.get("normal", Vector3.UP)
					if (not retry_surface["hit"]
							or retry_normal.dot(Vector3.UP) < FLAT_SUPPORT_DOT):
						break
					retry_surface_y = (retry_surface["position"] as Vector3).y
					if retry_surface_y <= retry_point.y:
						break
					retry_target.y += retry_surface_y + POSE_CLEARANCE_MARGIN_M - retry_point.y
				var plan := get_plan(side)
				if plan != null:
					plan.final_adjustment_reason = "pose_toe_clearance"
		FootIKDebug.end(&"clearance", dbg_clr)
	solver.commit_candidate(skel, result)
	solver._end_perf_sample(perf_start_usec)


## The same-frame, full-strength clearance retry is a locomotion step-up correction. It must not
## fire during idle: measured at full strength it snaps an idle leg (ledge check:
## idle_split_height_turn_pause foot snap 0.581m) and its toe pitch over-swings the shin
## (parallel_to_edge 51deg > 45). Gating it to walk/sprint clips keeps the walking fix while
## leaving idle ledge/split-height ownership untouched.
func _walking_animation() -> bool:
	if _owner.player_body == null or _owner.player_body.anim_player == null:
		return false
	var anim: String = _owner.player_body.anim_player.current_animation.get_file()
	return anim.contains("walk") or anim.contains("sprint")


## The ordinary flat-pose fast path must yield when the pose it would preserve is already
## inside a horizontal stair/platform collider. This is measured after pelvis placement, just
## before release; ordinary unobstructed flat walking still takes the zero-correction path.
func preserved_pose_needs_clearance(skel: Skeleton3D, space: PhysicsDirectSpaceState3D,
		side: StringName) -> bool:
	var indices: Dictionary = _owner._bone_indices[side]
	var to_world := skel.global_transform
	var foot: Vector3 = to_world * skel.get_bone_global_pose(indices["foot"]).origin
	var points := PackedVector3Array([foot])
	var toe_index: int = indices["toe"]
	if toe_index >= 0:
		var toe: Vector3 = to_world * skel.get_bone_global_pose(toe_index).origin
		var toe_reach := toe - foot
		if toe_reach.length_squared() > 0.000001:
			toe += toe_reach.normalized() * float(_owner.toe_tip_margin)
		points.append(toe)
	var leaf_index: int = indices["leaf"]
	if leaf_index >= 0:
		points.append(to_world * skel.get_bone_global_pose(leaf_index).origin)
	var clearance := PENETRATION_MONITOR.check(space, points,
			FootIKGroundSampler.GROUND_COLLISION_MASK)
	if (not clearance["penetrating"]
			or float(clearance["depth_m"]) <= POSE_PENETRATION_TRIGGER_M):
		return false
	var point: Vector3 = clearance["point"]
	var surface: Dictionary = _owner._ground_sampler.raycast_ground(
			space, point + Vector3.UP * 0.5, 1.0)
	var normal: Vector3 = surface.get("normal", Vector3.UP)
	return (surface["hit"] and normal.dot(Vector3.UP) >= FLAT_SUPPORT_DOT
			and (surface["position"] as Vector3).y > point.y)


func _candidate_points(result: FootIKLegPoseResult) -> PackedVector3Array:
	var points := PackedVector3Array([result.foot_pos])
	if result.has_toe:
		var toe_reach: Vector3 = result.toe_pos - result.foot_pos
		var toe_tip: Vector3 = result.toe_pos
		if toe_reach.length_squared() > 0.000001:
			toe_tip += toe_reach.normalized() * float(_owner.toe_tip_margin)
		points.append(toe_tip)
	if result.has_leaf:
		points.append(result.leaf_pos)
	return points


func resolve_stationary(space: PhysicsDirectSpaceState3D,
		per_leg: Dictionary, stationary: bool, delta: float,
		to_world: Transform3D = Transform3D.IDENTITY) -> void:
	var dbg := FootIKDebug.begin()
	_propose_spacing(per_leg, stationary, to_world)
	_select_solve_targets(per_leg)
	_apply_seam_hold(per_leg)
	for side: StringName in _pelvis_references.keys():
		if not per_leg.has(side): release_leg(side)
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
	FootIKDebug.end(&"coord_resolve", dbg)


## Finishes each leg's target decision (upper-foot/slope adjustment) here, before the modifier
## derives pelvis from it - these used to run after pelvis was already fixed for the frame, so
## pelvis never reflected their output (018 finding A, joint pass). A seam hold already has
## final say and skips them. Writes leg[&"final_target"] and tracks a bounded pelvis reference
## for pelvis_reference_target below. `prev_shared_drop`/`prev_lateral_shift` are last frame's
## stable pelvis values, used only to seed this frame's estimate hip for this math.
func finalize_leg_targets(per_leg: Dictionary, prev_shared_drop: float,
		prev_lateral_shift: Vector3, to_world: Transform3D, delta: float, native: bool,
		stationary: bool, initialize_pose: bool = false) -> void:
	var dbg := FootIKDebug.begin()
	for side: StringName in per_leg:
		var leg: Dictionary = per_leg[side]
		if not leg.get("hit", false) or not (leg.has("target") or leg.has("ground_target")):
			release_leg(side)
			continue
		var plan := get_plan(side)
		var final_target: Vector3 = (plan.ankle_target if plan != null
				else leg.get("target", leg.get("ground_target", leg["hip_pos"])))
		var selected_target := final_target
		var sampler = _owner._ground_sampler
		var previous_surface: Variant = sampler.smoothed_target.get(side)
		var previous_normal: Variant = sampler.smoothed_normal.get(side)
		var upper_reposition_active := false
		if not native and not leg.has(&"seam_hold_target"):
			var other_side: StringName = &"right" if side == &"left" else &"left"
			var est_hip: Vector3 = (leg["hip_pos"] - Vector3.UP * prev_shared_drop
					+ prev_lateral_shift)
			var upper_context := {
				"initialize_pose": initialize_pose,
				"hip": est_hip, "target": final_target,
				"surface": leg.get("raw_target", Vector3(INF, INF, INF)),
				"normal": leg.get("raw_normal", Vector3.UP), "upper": leg["upper"], "lower": leg["lower"],
				"offset": leg.get("effective_offset", _owner.ankle_offset), "to_world": to_world,
				"delta": delta, "lowest_hit": leg.get("animated_contact_hit", false),
				"lowest_surface": leg.get("animated_contact_position", Vector3.ZERO)}
			var dbg_up := FootIKDebug.begin()
			final_target = sampler.straighten_compressed_upper_target(
					_contact_space(), side, upper_context)
			FootIKDebug.end(&"upper_straighten", dbg_up)
			upper_reposition_active = upper_context.get("upper_reposition_active", false)
			if leg.get("stationary_slope", false):
				var hip_axis: Vector3 = leg["hip_pos"] - per_leg[other_side]["hip_pos"]
				var side_sign := 1.0 if side == &"left" else -1.0
				var left_dir := Vector3(hip_axis.x, 0.0, hip_axis.z).normalized() * side_sign
				final_target = _owner._leg_solver.adjust_idle_slope_target(
						side, est_hip, final_target, leg["upper"], leg["lower"], to_world, left_dir)
		if not native and plan != null:
			var dbg_acc := FootIKDebug.begin()
			var accepted := _accept_final_target(_contact_space(), plan, leg, final_target)
			FootIKDebug.end(&"accept_target", dbg_acc)
			if accepted != final_target:
				# Rejected interpolation must not leak into the producer's next frame.
				if previous_surface != null: sampler.smoothed_target[side] = previous_surface
				else: sampler.smoothed_target.erase(side)
				if previous_normal != null: sampler.smoothed_normal[side] = previous_normal
				else: sampler.smoothed_normal.erase(side)
				if leg.get("stationary_slope", false):
					_owner._leg_solver.retain_idle_slope_target(side, accepted)
			final_target = accepted
		leg[&"final_target"] = final_target
		# ground_target selection during active locomotion is a real terrain-follow divergence
		# from the animated foot - pelvis following it there measurably distorts walk pose (018
		# finding A, joint pass; both this and the reverted approach A regressed identically on
		# it). During idle/stationary the two rarely diverge meaningfully and avoiding
		# ground_target there instead cost a different, narrower idle-seam margin - keep the
		# upper-foot/slope adjustment's own contribution either way, just gate the avoidance.
		var pelvis_basis := final_target
		if (stationary and leg.has(&"seam_hold_target")
				and sampler.compressed_upper_target.has(side) and _idle_pelvis_hold.has(side)):
			pelvis_basis = _idle_pelvis_hold[side]
			leg[&"pelvis_reach_target"] = final_target
		elif (stationary and upper_reposition_active
				and plan != null and plan.target_source != "raw_recovery"):
			# Upper-foot extension is relative to the hip. Centering pelvis on its output
			# moves that hip toward the foot, cancels the extension, and restarts acquisition
			# forever (024). Balance against the independent live support, not this correction.
			# Use the producer's active flag even while it cannot find a feasible destination.
			pelvis_basis = leg.get("raw_ground_target", selected_target)
			leg[&"pelvis_reach_target"] = final_target
		elif not stationary and plan != null and plan.target_source == "ground_target":
			var pre_selection: Vector3 = leg.get(&"target", selected_target)
			pelvis_basis = pre_selection + (final_target - selected_target)
		# A foot idle-rehome is actively correcting this frame is genuinely in flux; feeding
		# pelvis that live, still-moving value couples balance math to the correction and can
		# fight it (021-023's boundary-retrigger investigation). Hold pelvis at the last value
		# from before this correction episode started instead, same principle as the locomotion
		# case above, resuming normal tracking the moment rehome stops firing.
		elif stationary and sampler.idle_stance_rehoming.has(side) and _idle_pelvis_hold.has(side):
			pelvis_basis = _idle_pelvis_hold[side]
		if not (stationary and sampler.idle_stance_rehoming.has(side)):
			_idle_pelvis_hold[side] = pelvis_basis
		leg[&"pelvis_basis_target"] = pelvis_basis
		if plan != null and plan.target_source != "raw_recovery":
			_remember_pelvis_reference(side, plan, pelvis_basis)
	FootIKDebug.end(&"coord_finalize", dbg)


## Recovery is a short lease, not a world-space lock of unlimited age. Reconfirm geometry
## and the original stance/reach contract when consuming it; refreshes cannot renew the lease.
func pelvis_reference_target(side: StringName, leg: Dictionary, fallback: Vector3) -> Vector3:
	var plan := get_plan(side)
	if plan != null and plan.target_source == "raw_recovery" and _pelvis_references.has(side):
		var cached: PelvisReference = _pelvis_references[side]
		var age := Engine.get_physics_frames() - cached.frame
		var reach: float = float(leg["upper"]) + float(leg["lower"]) + _owner.step_down_max_crouch
		var hip: Vector3 = leg["hip_pos"]
		var reason := "held"
		if not leg.get("hit", false): reason = "contact_lost"
		elif age < 0 or age >= PELVIS_HOLD_TICKS: reason = "expired"
		elif hip.distance_to(cached.target) > reach: reason = "unreachable"
		elif cached.require_stance and not _owner._ground_sampler.is_target_inside_stance_zone(
				side, cached.surface): reason = "outside_stance"
		elif not _has_contact_support(_contact_space(), cached.surface, cached.normal):
			reason = "unsupported"
		plan.pelvis_reference_reason = reason
		if reason == "held": return cached.target
		release_leg(side)
	return leg.get(&"pelvis_basis_target", fallback)


func release_leg(side: StringName) -> void:
	_pelvis_references.erase(side)
	_last_final_targets.erase(side)
	_last_final_frames.erase(side)


func _remember_pelvis_reference(side: StringName, plan: FootIKTargetPlan,
		target: Vector3) -> void:
	if not plan.valid or not target.is_finite() or not plan.surface_target.is_finite():
		release_leg(side)
		return
	var cached := PelvisReference.new()
	cached.target = target
	cached.surface = plan.surface_target
	cached.normal = plan.surface_normal
	cached.frame = Engine.get_physics_frames()
	cached.require_stance = plan.stance_status == FootIKTargetPlan.ConstraintStatus.SATISFIED
	_pelvis_references[side] = cached


## Accept a changed upper/slope proposal, or keep the already accepted input. Never veto
## the fallback with the same test that rejected the optional adjustment. This does not
## certify final skinned clearance or reach after this frame's pelvis has been shaped.
func _accept_final_target(space: PhysicsDirectSpaceState3D, plan: FootIKTargetPlan,
		leg: Dictionary, candidate: Vector3) -> Vector3:
	const STATUS := FootIKTargetPlan.ConstraintStatus
	plan.adjusted_ankle_target = candidate
	plan.final_adjustment_reason = "unchanged"
	if candidate == plan.ankle_target:
		_last_final_targets[plan.side] = candidate
		_last_final_frames[plan.side] = Engine.get_physics_frames()
		return candidate
	# ground_sampler.compressed_upper_target[side], when populated (mid stair-height
	# compression), names the sampler's own intended waypoint directly. Otherwise, project
	# the candidate back along the surface normal by this leg's known ankle-to-surface
	# offset as a first estimate; _sample_contact_support then self-corrects it against a
	# real raycast rather than requiring an exact match. A generic vector translation of the
	# OLD surface point by candidate-ankle drifts laterally on a continuous slope (a slope
	# nudge's own downhill/sideways component is not aligned with the normal), landing the
	# check far enough off the real surface to miss it for several consecutive frames (018
	# finding D; a real ramp-spin regression).
	var offset_len: float = plan.ankle_target.distance_to(plan.surface_target)
	var estimate: Vector3 = _owner._ground_sampler.compressed_upper_target.get(
			plan.side, candidate - plan.surface_normal * offset_len)
	var sample := _sample_contact_support(space, estimate, plan.surface_normal)
	var support_point: Vector3 = sample.get("position", estimate) as Vector3
	plan.final_support_target = support_point
	var check_stance := plan.stance_status not in [STATUS.NOT_APPLICABLE, STATUS.NOT_CHECKED]
	var check_toe := plan.toe_status not in [STATUS.NOT_APPLICABLE, STATUS.NOT_CHECKED]
	var hip: Vector3 = leg["hip_pos"]
	var reach: float = float(leg["upper"]) + float(leg["lower"]) + _owner.step_down_max_crouch
	var rejection := ""
	# A candidate rehome is actively adjusting this frame gets the same small boundary
	# tolerance rehome itself already uses - otherwise this stricter check rejects it,
	# reverting toward the base solve, which rehome then nudges out again next cycle (023).
	var sampler = _owner._ground_sampler
	var rehoming: bool = sampler.idle_stance_rehoming.has(plan.side)
	var stance_margin: float = sampler.IDLE_STANCE_REHOME_MARGIN if rehoming else 0.0
	if not candidate.is_finite(): rejection = "nonfinite"
	elif hip.distance_to(candidate) > reach: rejection = "unreachable"
	elif check_stance and not sampler.is_target_inside_stance_zone(
			plan.side, candidate, stance_margin): rejection = "outside_stance"
	elif not (sample.get("ok", false) as bool): rejection = "unsupported"
	elif check_toe and not _toe_envelope_valid_at(space, plan, candidate):
		rejection = "toe_envelope_blocked"
	if not rejection.is_empty():
		plan.final_adjustment_reason = "rejected_" + rejection
		# A rejected candidate here is a genuine one-frame outlier from the adjustment's own
		# constraint-satisfaction search (e.g. a downhill nudge briefly overshooting a ramp's
		# physical edge), not a sustained loss of ground - snapping straight to this frame's
		# un-adjusted base solve pops visibly against neighboring frames that WERE adjusted.
		# Hold the last known-good final output for a couple of frames instead, same idea as
		# this file's other short holds (seam hold, pelvis reference lease).
		var held: Variant = _last_final_targets.get(plan.side)
		var held_frame: int = _last_final_frames.get(plan.side, -999)
		if held != null and Engine.get_physics_frames() - held_frame <= FINAL_HOLD_FRAMES:
			return held as Vector3
		return plan.ankle_target
	# Preserve the solver's existing guard policy: accepting an adjustment is not proof
	# that its final pelvis/pose will satisfy all of that guard's anatomical constraints.
	leg[&"target_plan_validated"] = (leg.get(&"target_plan_validated", false)
			and plan.ankle_target.distance_to(candidate) <= 0.001)
	plan.ankle_target = candidate
	plan.surface_target = support_point
	_last_final_targets[plan.side] = candidate
	_last_final_frames[plan.side] = Engine.get_physics_frames()
	plan.reach_status = STATUS.SATISFIED
	plan.support_status = STATUS.SATISFIED
	if check_toe:
		plan.toe_status = STATUS.SATISFIED
		plan.constraint_reasons.erase("toe")
		plan.constraint_expiry_frames.erase("toe")
	plan.final_adjustment_reason = "accepted_adjustment"
	return candidate


func _contact_space() -> PhysicsDirectSpaceState3D:
	return _owner.player_body.get_world_3d().direct_space_state


## A slope-aware point support check. Discrete transition callers supply their destination,
## not their airborne waypoint; this is not a swept-volume or toe clearance check.
func _has_contact_support(space: PhysicsDirectSpaceState3D,
		surface: Vector3, normal: Vector3) -> bool:
	if not surface.is_finite() or not normal.is_finite(): return false
	var hit: Dictionary = _owner._ground_sampler.raycast_ground(
			space, surface + Vector3.UP * 0.2, 0.4)
	return (hit.get("hit", false)
			and (hit.get("normal", Vector3.ZERO) as Vector3).dot(normal) >= 0.98
			and (hit.get("position", Vector3.INF) as Vector3).distance_to(surface)
			<= SUPPORT_HEIGHT_TOLERANCE)


## Same real-ground query as _has_contact_support, but for a freshly-computed candidate
## estimate rather than a cached, already-trusted surface: hit existence and normal alignment
## are what a candidate's own support actually depends on, so accept the raycast's own hit
## position as ground truth instead of also requiring it to land within a few cm of an
## estimate that a move_toward-smoothed adjustment cannot guarantee that precisely (018
## finding D). _has_contact_support's tighter match stays as-is for pelvis_reference_target's
## staleness check on an already-accepted point, a genuinely different use case.
func _sample_contact_support(space: PhysicsDirectSpaceState3D,
		estimate: Vector3, normal: Vector3) -> Dictionary:
	if not estimate.is_finite() or not normal.is_finite():
		return {"ok": false, "position": estimate}
	var hit: Dictionary = _owner._ground_sampler.raycast_ground(
			space, estimate + Vector3.UP * 0.2, 0.4)
	var ok: bool = (hit.get("hit", false)
			and (hit.get("normal", Vector3.ZERO) as Vector3).dot(normal) >= 0.98)
	return {"ok": ok, "position": (hit["position"] as Vector3) if ok else estimate}


## Joint proposal only: never move targets again after validation/recovery. Preserve the
## original flat-idle/missing-contact gates and 22 cm spacing; caches remain producer-owned.
static func _propose_spacing(per_leg: Dictionary, stationary: bool,
		to_world: Transform3D) -> void:
	for side: StringName in per_leg:
		(per_leg[side] as Dictionary).erase(&"spacing_delta")
	if not stationary or not per_leg.has(&"left") or not per_leg.has(&"right"):
		return
	var left: Dictionary = per_leg[&"left"]
	var right: Dictionary = per_leg[&"right"]
	if (not left.get("hit", false) or not right.get("hit", false)
			or (left.get("preserve_idle_pose", false) and right.get("preserve_idle_pose", false))):
		return
	var l_hip: Vector3 = left["hip_pos"]
	var r_hip: Vector3 = right["hip_pos"]
	var l_target: Vector3 = left.get("target", left.get("ground_target", l_hip))
	var r_target: Vector3 = right.get("target", right.get("ground_target", r_hip))
	var axis := Vector3(l_hip.x - r_hip.x, 0.0, l_hip.z - r_hip.z)
	var left_dir := axis.normalized() if axis.length_squared() > 0.0001 \
			else -to_world.basis.x.normalized()
	if (l_target - r_target).dot(left_dir) >= 0.22:
		return
	var midpoint := (l_target + r_target) * 0.5
	left[&"target"] = midpoint + left_dir * 0.11
	right[&"target"] = midpoint - left_dir * 0.11
	left[&"spacing_delta"] = (left[&"target"] as Vector3) - l_target
	right[&"spacing_delta"] = (right[&"target"] as Vector3) - r_target


## Preserve the custom solver's ground-target priority, but select it before validation.
## Ground targets replace the spacing proposal; derive their support from that actual ankle.
## Native callers do not request this custom-only policy during their migration.
static func _select_solve_targets(per_leg: Dictionary) -> void:
	for side: StringName in per_leg:
		var leg: Dictionary = per_leg[side]
		leg[&"target_source"] = "target"
		leg[&"solve_candidate"] = leg.get(&"target", leg.get(&"ground_target", Vector3.ZERO))
		if not leg.get(&"prefer_ground_target", false) or not leg.has(&"ground_target"):
			continue
		# Pelvis planning still consumes the legacy target; migrating it jointly is separate.
		leg[&"solve_candidate"] = leg[&"ground_target"]
		leg[&"target_source"] = "ground_target"
		leg.erase(&"spacing_delta")


## Idle-loop-reset velocity suppression must freeze the ankle at last frame's actual solve,
## overriding spacing/ground-target selection same as it always overrode upper-foot/slope
## adjustment - highest priority among the late overrides, now validated instead of applied
## after the fact. The modifier computes the hold value itself (last frame's solver history).
static func _apply_seam_hold(per_leg: Dictionary) -> void:
	for side: StringName in per_leg:
		var leg: Dictionary = per_leg[side]
		if not leg.has(&"seam_hold_target"):
			continue
		leg[&"solve_candidate"] = leg[&"seam_hold_target"]
		leg[&"target_source"] = "seam_hold"
		leg.erase(&"spacing_delta")


## Observe actual inputs without rewriting the accepted plan. A finalized target must
## never lend a later override its validation flag, even below the old 1 mm tolerance.
func record_solve_target(side: StringName, target: Vector3, validation_claim: bool) -> bool:
	var plan := get_plan(side)
	if plan == null:
		return false
	plan.solve_target_observed = true
	plan.actual_solve_target = target
	var matches := plan.matches_solve_target(target)
	plan.solve_target_reason = "accepted_plan" if matches else "late_target_override"
	var must_match := plan.spacing_requested or plan.final_adjustment_reason != "not_finalized"
	plan.solve_validation_retained = validation_claim and (not must_match or matches)
	return plan.solve_validation_retained


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
	plan.ankle_target = leg[&"solve_candidate"]
	plan.proposed_ankle_target = plan.ankle_target
	plan.spacing_requested = leg.has(&"spacing_delta")
	plan.target_source = leg.get(&"target_source", "target")
	# Support and ankle must describe the same proposal, not the pre-spacing surface.
	plan.surface_target += leg.get(&"spacing_delta", Vector3.ZERO) as Vector3
	if plan.target_source == "ground_target" or plan.target_source == "seam_hold":
		# A frozen ankle validated against this frame's fresh raw surface would fail on a
		# stale/current mismatch that never existed before (seam used to bypass validation
		# entirely) - derive the paired surface from the frozen ankle itself instead.
		plan.surface_target = plan.ankle_target - plan.surface_normal * float(
				leg.get(&"effective_offset", _owner.ankle_offset))
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
	# Descending locomotion is corrected against the actual evaluated toe/ankle pose in
	# solve_leg_candidate(). Rejecting its approximate pre-solve toe envelope here releases the
	# whole leg to the very animation pose that penetrated the tread, before correction can run.
	# Guard the predictor access: pure-function contract fixtures use a mock owner that omits it.
	var descending_locomotion: bool = (_owner.get("_stair_predictor") != null
			and _owner._stair_predictor.is_descending_treads()
			and plan.owner in [FootIKTargetPlan.Owner.LOCOMOTION_LOCK,
					FootIKTargetPlan.Owner.LOCOMOTION_STANCE])
	var check_toe: bool = (plan.owner != FootIKTargetPlan.Owner.STAIR_SUPPORT
			and not descending_locomotion)
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
	# A descending locomotion lock/stance target is likewise an interpolated waypoint between
	# discrete treads. Validate the real sampled destination, then let the final-pose clearance
	# retry guard the in-flight rendering instead of demanding ground in midair.
	elif (_owner._stair_predictor.is_descending_treads()
			and plan.owner in [FootIKTargetPlan.Owner.LOCOMOTION_LOCK,
					FootIKTargetPlan.Owner.LOCOMOTION_STANCE]):
		support_target = plan.raw_surface
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
			plan.constraint_reasons["toe"] = "toe_envelope_blocked"
			plan.constraint_expiry_frames["toe"] = (TOE_INVALID_HOLD_FRAMES
					- int(_toe_invalid_streak.get(plan.side, 0)))
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
## right-foot clip from archived task 008: a valid ankle latch with the toe poking into the
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
	plan.spacing_requested = rejected.spacing_requested
	plan.proposed_ankle_target = rejected.proposed_ankle_target
	plan.target_source = "raw_recovery"
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
