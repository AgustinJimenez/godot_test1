extends RefCounted
## Coordinates stair swing prediction and stance-foot ownership.
## It consumes already-sampled contacts and never writes skeleton bones.
## TEMPORARY / EXPERIMENTAL: this is the refactored boundary for the current
## predictor, not an assertion that its visible stair gait is production-ready.


class LegState extends RefCounted:
	var swing_active := false
	var landing_seen := false
	var swing_base_y := 0.0
	var smoothed_lift := 0.0
	var has_latched_target := false
	var latched_target := Vector3.ZERO
	var latched_normal := Vector3.UP
	var over_surface_streak := 0
	var descending_to_landing := false
	var has_predicted_target := false
	var predicted_target := Vector3.ZERO


var _owner
var _legs: Dictionary = {} # side -> LegState
var _support_side: StringName = &""
var _support_ground_target := Vector3.ZERO
var _support_surface_target := Vector3.ZERO
var _support_normal := Vector3.UP
## Time since support last acquired/transferred to a leg, and that leg's own
## pre-support target at that moment - see _apply_support_contact()'s doc
## comment on why the handoff itself needs blending, not just engage/release.
var _support_transfer_elapsed := 0.0
var _support_transfer_from_pos := Vector3.ZERO
var _previous_root_position := Vector3.ZERO
var _has_previous_root_position := false
var _travel_direction := Vector3.ZERO


## Stair support ownership is only needed to bridge discontinuous, flat
## treads. On a continuous slope, retaining a world-space support point while
## the authored idle pose settles can drag that foot across the pelvis even
## though the target remains barely inside the leg's total reach.
const FLAT_SURFACE_UP_DOT := 0.95
## A genuine stair tread is horizontal, so its contact normal must be
## essentially Vector3.UP. Tighter than FLAT_SURFACE_UP_DOT: a shallow 15deg
## ramp reads 0.966 and must NOT be treated as a step-up tread. Matches the
## modifier's flat_contact threshold.
const STAIR_TREAD_UP_DOT := 0.999
const STATIONARY_HORIZONTAL_SPEED := 0.05


func _init(owner) -> void:
	_owner = owner


func reset() -> void:
	_legs.clear()
	_support_side = &""
	_support_ground_target = Vector3.ZERO
	_support_surface_target = Vector3.ZERO
	_support_normal = Vector3.UP
	_previous_root_position = Vector3.ZERO
	_has_previous_root_position = false
	_travel_direction = Vector3.ZERO
	_support_transfer_elapsed = 0.0
	_support_transfer_from_pos = Vector3.ZERO


func update_travel_direction(delta: float) -> void:
	if not _owner.step_prediction_enabled or delta <= 0.0 or _owner.player_body == null:
		return
	var motion_root := _owner.player_body.get_parent() as Node3D
	if motion_root == null:
		motion_root = _owner.player_body
	var root_position := motion_root.global_position
	if _has_previous_root_position:
		var travel: Vector3 = root_position - _previous_root_position
		travel.y = 0.0
		if travel.length_squared() > 0.0000001:
			_travel_direction = travel.normalized()
	_previous_root_position = root_position
	_has_previous_root_position = true


## flags: "step_down" (bool, default false) and "pelvis_sink" (float, default
## 0.0) - bundled to stay under the linter's max-argument count.
func update_swing_lift(space: PhysicsDirectSpaceState3D, side: StringName,
		foot_pos: Vector3, foot_basis_local: Basis, raw_target: Vector3,
		animated_lowest_point: Vector3, ground_weight: float, landed: bool,
		delta: float, flags: Dictionary = {}) -> float:
	var step_down: bool = flags.get("step_down", false)
	var pelvis_sink: float = flags.get("pelvis_sink", 0.0)
	var state := _state(side)
	if side == _support_side:
		clear_swing(side)
		state.smoothed_lift = 0.0
		return 0.0
	if step_down:
		# A stationary stance foot easing down onto a lower surface is not a
		# swing: clear any swing state so the forward prediction cannot keep
		# lifting it back up toward the next higher tread.
		clear_swing(side)
		state.smoothed_lift = 0.0
		return 0.0
	_discard_current_support_tread(state)
	var forward := _prediction_direction(side, foot_basis_local)
	var predicted_probe: Vector3 = foot_pos + forward * _owner.step_prediction_distance
	var predicted_hit: Dictionary = _owner._ground_sampler.raycast_ground(
			space, predicted_probe)

	if not state.swing_active and ground_weight < 0.8:
		state.swing_active = true
		state.landing_seen = false
		state.swing_base_y = minf(
				raw_target.y, (_owner._smoothed_target[side] as Vector3).y)
		state.over_surface_streak = 0
		state.descending_to_landing = false
	if landed:
		state.landing_seen = true
	if state.swing_active and state.landing_seen and ground_weight >= 0.8:
		state.swing_active = false
		state.landing_seen = false
		state.has_latched_target = false
		state.over_surface_streak = 0
		state.descending_to_landing = false

	var desired_lift := _desired_swing_lift(
			space, state, predicted_hit, raw_target, animated_lowest_point, delta, pelvis_sink)
	if delta > 0.0:
		var playback_scale := maxf(_owner.player_body.locomotion_playback_scale, 0.001)
		state.smoothed_lift = move_toward(state.smoothed_lift, desired_lift,
				_owner.step_lift_rate * playback_scale * delta)
	return state.smoothed_lift


func ensure_support(per_leg: Dictionary, shared_drop: float, delta: float) -> float:
	if not per_leg.has(&"left") or not per_leg.has(&"right"):
		return shared_drop
	var left: Dictionary = per_leg[&"left"]
	var right: Dictionary = per_leg[&"right"]
	if _is_stationary_on_continuous_slope(left, right):
		# The ordinary per-foot ray solution already follows a ramp. Releasing
		# stair ownership here keeps each target below its own animated leg
		# instead of preserving a stale target that can cross the body centre.
		_support_side = &""
		clear_swing(&"left")
		clear_swing(&"right")
		return shared_drop
	# Once acquired, support never released on its own - a foot stays "close
	# enough" to the ground almost always during ordinary flat walking, so
	# is_active()'s own contact check never fails. That let this system,
	# triggered once by spawning near a ramp/step, keep fighting the
	# ordinary ground-target latch with its own independently-timed target
	# for the rest of the session (confirmed live: SUPPORT prints firing
	# continuously, far from any real stairs). An earlier version released
	# once has_latched_target() (the OTHER leg's swing prediction) went
	# false - but that toggles many times a second during genuine, ongoing
	# stair climbing (confirmed live: released and instantly re-acquired
	# support mid-climb, each re-acquisition re-latching to that frame's own
	# noisy animated-pose raycast, producing a steadily drifting target
	# height via STAIR_FOOT_TRACE's ik_ground_target.y - even a 20-frame
	# debounce still hit this mid-climb, since a real climb's own "no swing
	# latched" window outlasted it). Both feet actually standing on the same
	# flat level is the direct, unambiguous "left the stairs" signal instead.
	if (not _support_side.is_empty() and shared_drop <= 0.0
			and _both_feet_on_matching_flat_ground(left, right)):
		_support_side = &""
		return shared_drop
	var left_clearance: float = left.get("animated_contact_distance", INF)
	var right_clearance: float = right.get("animated_contact_distance", INF)
	if _support_side.is_empty():
		var chosen := _choose_support_side(
				_is_contacting(left, left_clearance), _is_contacting(right, right_clearance),
				left_clearance, right_clearance)
		if chosen.is_empty():
			return shared_drop
		_support_side = chosen
		_latch_support_target(per_leg[_support_side])
	else:
		# Collision can advance the root to a new tread faster than the
		# animation supplies the opposite landing. Never preserve an old
		# support target once it is outside that leg's anatomical reach: the
		# previous behavior compensated by lowering the shared pelvis, dragging
		# the entire rendered body through the stair stack. That protection is
		# for a hip ABOVE an unreachable target (descending); a hip BELOW an
		# already-latched target (e.g. mid step-up climb, hip still catching
		# up to the tread) self-resolves as the hip keeps rising, and the leg
		# solver's own reach clamp (FOOT_IK_STRETCH_CHECK) keeps that stretch
		# safe meanwhile - re-latching here instead produced a ~20cm
		# target-height drift every climb frame (confirmed live via
		# STAIR_FOOT_TRACE's ik_ground_target.y), since each frame's noisy
		# animated-pose raycast landed somewhere slightly different.
		var support_leg: Dictionary = per_leg[_support_side]
		var support_clearance := (
				left_clearance if _support_side == &"left" else right_clearance)
		var reachable := _support_target_is_reachable(support_leg)
		var hip_below_target: bool = (
				(support_leg["hip_pos"] as Vector3).y < _support_ground_target.y)
		if (not _is_contacting(support_leg, support_clearance)
				or (not reachable and not hip_below_target)):
			_support_side = &""
			var chosen := _choose_support_side(
					_is_contacting(left, left_clearance), _is_contacting(right, right_clearance),
					left_clearance, right_clearance)
			if chosen.is_empty():
				return shared_drop
			_support_side = chosen
			_latch_support_target(per_leg[_support_side])
		_try_transfer_support(per_leg, left_clearance, right_clearance)
	var leg: Dictionary = per_leg[_support_side]
	_apply_support_contact(_support_side, leg, delta)
	var hip_pos: Vector3 = leg["hip_pos"]
	var target: Vector3 = leg["target"]
	var max_reach: float = float(leg["upper"]) + float(leg["lower"]) - 0.001
	var horizontal_dist_sq := Vector2(
			hip_pos.x - target.x, hip_pos.z - target.z).length_squared()
	var max_vertical_diff := sqrt(maxf(
			0.0, max_reach * max_reach - horizontal_dist_sq))
	return maxf(shared_drop, (hip_pos.y - target.y) - max_vertical_diff)


func _is_stationary_on_continuous_slope(
		left: Dictionary, right: Dictionary) -> bool:
	var motion_root := _owner.player_body.get_parent() as CharacterBody3D
	if motion_root == null:
		return false
	var horizontal_velocity := Vector2(
			motion_root.velocity.x, motion_root.velocity.z).length()
	if horizontal_velocity > STATIONARY_HORIZONTAL_SPEED:
		return false
	var left_normal: Vector3 = left.get("raw_normal", Vector3.UP)
	var right_normal: Vector3 = right.get("raw_normal", Vector3.UP)
	return (left.get("hit", false) and right.get("hit", false)
			and left_normal.dot(Vector3.UP) < FLAT_SURFACE_UP_DOT
			and right_normal.dot(Vector3.UP) < FLAT_SURFACE_UP_DOT)


## Direct "left the stairs" signal for ensure_support()'s release condition:
## during active climbing the two feet sit on different tread heights by
## construction (one step_height apart), so this only reads true once both
## are genuinely on one continuous, flat run.
func _both_feet_on_matching_flat_ground(left: Dictionary, right: Dictionary) -> bool:
	if not (left.get("hit", false) and right.get("hit", false)):
		return false
	var left_normal: Vector3 = left.get("raw_normal", Vector3.UP)
	var right_normal: Vector3 = right.get("raw_normal", Vector3.UP)
	if (left_normal.dot(Vector3.UP) < FLAT_SURFACE_UP_DOT
			or right_normal.dot(Vector3.UP) < FLAT_SURFACE_UP_DOT):
		return false
	var left_target: Vector3 = left.get("raw_target", Vector3.ZERO)
	var right_target: Vector3 = right.get("raw_target", Vector3.ZERO)
	return absf(left_target.y - right_target.y) <= _owner.step_min_rise


func _support_target_is_reachable(leg: Dictionary) -> bool:
	var max_reach: float = float(leg["upper"]) + float(leg["lower"]) - 0.001
	return (leg["hip_pos"] as Vector3).distance_to(_support_ground_target) <= max_reach


## Wider than GROUND_CONTACT_DISTANCE (which idle planting still uses) - a
## real stair-riser gap between the animated sole and the true tread is often
## tens of cm even for a genuinely planted stance foot (flat-ground-authored
## walk clip vs. real stair geometry), so 3cm almost never acquired support at
## all during active walking, leaving both feet on the raw animated pose.
const SUPPORT_CONTACT_DISTANCE := 0.15


## True when the secondary toe-tip probe reads a surface at least step_min_rise
## above the ankle's own primary ray. The toe probe is extrapolated forward
## (toe_tip_margin) before casting down, so during a step-up it can reach OVER
## a riser onto the NEXT tread's top while the ankle still sits above the
## current, lower tread. A support latch then anchors the foot a full step
## above the visible step beneath its ankle, rendering a mid-air hover
## (confirmed live on Stairs 0.50m: right foot held a 2.5m target for ~120
## frames while its ankle was over the 2.0m step). Such a foot is mid-swing,
## not planted - only trust the toe probe when its surface is at or below the
## ankle's own ray. Ramps/downhill are unaffected: there the toe is the lower
## point, so the probe reads below the ankle ray and the guard never fires.
##
## The height condition alone is not enough: a foot planted at the bottom edge
## of a ramp, facing uphill, has its toe probe legitimately read the rising
## slope above the ankle while the foot is genuinely planted on the flat floor
## below it. The ramp sweep flagged +138 such cases. A stair step-up's higher
## surface is a FLAT tread (normal near Vector3.UP), while a ramp's is sloped
## (45deg reads ~0.71), so require the probe's own surface to be flat before
## treating the foot as mid-step-up. Matches the modifier's flat_contact
## threshold so a shallow 15deg ramp (0.966) is not misread as a tread.
func _toe_probe_reaches_higher_surface(leg: Dictionary) -> bool:
	if not (leg.get("hit", false) and leg.get("animated_contact_hit", false)):
		return false
	var probe_y: float = (leg["animated_contact_position"] as Vector3).y
	var ankle_y: float = (leg["raw_target"] as Vector3).y
	if probe_y <= ankle_y + _owner.step_min_rise:
		return false
	var probe_normal: Vector3 = leg.get("animated_contact_normal", Vector3.UP)
	return probe_normal.dot(Vector3.UP) >= STAIR_TREAD_UP_DOT


func _is_contacting(leg: Dictionary, clearance: float) -> bool:
	return (leg.get("animated_contact_hit", false)
			and clearance <= SUPPORT_CONTACT_DISTANCE
			and not _toe_probe_reaches_higher_surface(leg))


## Picks which contacting leg becomes/keeps _support_side. A leg mid-swing
## (still climbing toward a latched tread) can transiently satisfy the plain
## contact/clearance check too - its predicted landing point can read close
## by - which wrongly made it "support" for one frame, hard-resetting its
## own in-progress step_lift to 0 via update_swing_lift()'s early-out
## (confirmed live via STAIR_FOOT_TRACE: a smoothly climbing lift reset to
## 0.0 mid-climb, then had to climb all over again - a visible stutter/bump
## right as the foot approached the next tread). Excluding a swinging leg
## only when the other candidate remains viable preserves the original
## fallback behavior for the rare case both legs are mid-air at once.
func _choose_support_side(left_contact: bool, right_contact: bool,
		left_clearance: float, right_clearance: float) -> StringName:
	var left_ok := left_contact and not (_state(&"left") as LegState).swing_active
	var right_ok := right_contact and not (_state(&"right") as LegState).swing_active
	if not left_ok and not right_ok:
		left_ok = left_contact
		right_ok = right_contact
	if left_ok and right_ok:
		return &"left" if left_clearance <= right_clearance else &"right"
	if left_ok:
		return &"left"
	if right_ok:
		return &"right"
	return &""


func clear_swing(side: StringName) -> void:
	var state := _state(side)
	state.swing_active = false
	state.landing_seen = false
	state.has_latched_target = false
	state.over_surface_streak = 0
	state.descending_to_landing = false
	state.has_predicted_target = false


func has_latched_target() -> bool:
	for state: LegState in _legs.values():
		if state.has_latched_target:
			return true
	return false


func is_active() -> bool:
	return not _support_side.is_empty() or has_latched_target()


func get_support_side() -> StringName:
	return _support_side


func get_step_lifts() -> Dictionary:
	var result: Dictionary = {}
	for side: StringName in _legs:
		result[side] = (_legs[side] as LegState).smoothed_lift
	return result


func get_predicted_targets() -> Dictionary:
	var result: Dictionary = {}
	for side: StringName in _legs:
		var state := _legs[side] as LegState
		if state.has_predicted_target:
			result[side] = state.predicted_target
	return result


func _state(side: StringName) -> LegState:
	var state := _legs.get(side) as LegState
	if state == null:
		state = LegState.new()
		_legs[side] = state
	return state


func _discard_current_support_tread(state: LegState) -> void:
	if not state.has_latched_target:
		return
	if state.latched_target.y > _support_surface_target.y + _owner.step_min_rise:
		return
	state.has_latched_target = false
	state.has_predicted_target = false
	state.swing_base_y = _support_surface_target.y
	state.over_surface_streak = 0
	state.descending_to_landing = false


func _prediction_direction(side: StringName, foot_basis_local: Basis) -> Vector3:
	var forward := _travel_direction
	if forward.length_squared() < 0.0001:
		var skel: Skeleton3D = _owner.get_skeleton()
		var foot_basis_world := skel.global_transform.basis * foot_basis_local
		var toe_forward_local: Vector3 = _owner._toe_rest_offset.get(side, Vector3.FORWARD)
		forward = foot_basis_world * toe_forward_local
		forward.y = 0.0
	return forward.normalized()


## A predicted landing spot right at a tread's front/back edge leaves too
## little sole area to plant on convincingly - the foot lands half over the
## drop. Nudge it toward whichever side (forward/back along travel) still
## reads as the same tread, so it settles nearer the tread's middle instead
## of its lip. Leaves the target alone on a tread narrower than 2x the
## margin (both sides read as an edge) or with room on both sides already;
## moving it to a different tread height entirely is a bigger follow-up.
const EDGE_SAFETY_MARGIN := 0.06


func _clear_landing_point(space: PhysicsDirectSpaceState3D, landing: Vector3) -> Vector3:
	var forward := _travel_direction
	if forward.length_squared() < 0.0001:
		return landing
	forward = forward.normalized()
	var ahead := _sample_same_tread(space, landing, forward)
	var behind := _sample_same_tread(space, landing, -forward)
	if ahead.is_empty() and not behind.is_empty():
		return behind["position"]
	if behind.is_empty() and not ahead.is_empty():
		return ahead["position"]
	return landing


## A ray cast down from EDGE_SAFETY_MARGIN in the given direction, kept only
## if it lands on (approximately) the same tread height as landing - i.e. the
## tread surface actually continues that way rather than ending in a riser or
## a drop. Returns the real surface hit, not just a same-height assumption -
## reusing landing.y at the nudged spot left the target floating above/below
## the true tread there, looking like a foot planting on an invisible step.
func _sample_same_tread(
		space: PhysicsDirectSpaceState3D, landing: Vector3, dir: Vector3) -> Dictionary:
	var probe := landing + dir * EDGE_SAFETY_MARGIN
	var hit: Dictionary = _owner._ground_sampler.raycast_ground(space, probe)
	if hit["hit"] and absf((hit["position"] as Vector3).y - landing.y) <= _owner.step_min_rise:
		return hit
	return {}


func _desired_swing_lift(space: PhysicsDirectSpaceState3D, state: LegState,
		predicted_hit: Dictionary, raw_target: Vector3,
		animated_lowest_point: Vector3, delta: float, pelvis_sink: float) -> float:
	if state.swing_active and predicted_hit["hit"]:
		var predicted_position: Vector3 = predicted_hit["position"]
		if (not state.has_latched_target
				and predicted_position.y > state.swing_base_y + _owner.step_min_rise):
			state.has_latched_target = true
			state.latched_target = _clear_landing_point(space, predicted_position)
			state.latched_normal = predicted_hit.get("normal", Vector3.UP)
	if not state.swing_active or not state.has_latched_target:
		state.has_predicted_target = false
		return 0.0
	state.has_predicted_target = true
	state.predicted_target = state.latched_target
	if delta > 0.0:
		var over_surface := raw_target.y >= state.latched_target.y - 0.001
		state.over_surface_streak = state.over_surface_streak + 1 if over_surface else 0
		if state.over_surface_streak >= 4:
			state.descending_to_landing = true
	if state.descending_to_landing:
		return 0.0
	# The shared pelvis sink (see _apply_support_pelvis_and_legs) lowers BOTH
	# legs' hip together, including this swinging one - so it also eats into
	# how high this leg can actually reach for its own elevated target, even
	# though the sink exists for the OTHER (support) leg's needs. Add back
	# last frame's sink so the swing target still clears the tread by the
	# full margin once the pelvis sinks (confirmed via STAIR_FOOT_TRACE: a
	# support-leg-driven sink was silently eating the swing leg's clearance,
	# producing exactly the toe/ball penetration this margin exists to avoid).
	# Flat treads only - on a ramp this pushed the sweep's failure count up
	# (2579->2809/6240), so restrict it to the same "real stair tread" signal
	# _toe_probe_reaches_higher_surface() already uses.
	var flat_tread := state.latched_normal.dot(Vector3.UP) >= STAIR_TREAD_UP_DOT
	var sink_compensation := pelvis_sink if flat_tread else 0.0
	var clearance_y: float = state.latched_target.y + _owner.step_clearance_margin + sink_compensation
	return maxf(0.0, clearance_y - animated_lowest_point.y)


func _try_transfer_support(per_leg: Dictionary,
		left_clearance: float, right_clearance: float) -> void:
	var candidate: StringName = &"right" if _support_side == &"left" else &"left"
	var candidate_leg: Dictionary = per_leg[candidate]
	var candidate_clearance := right_clearance if candidate == &"right" else left_clearance
	var candidate_velocity: float = candidate_leg.get("vertical_velocity", 0.0)
	var candidate_state := _state(candidate)
	if (candidate_leg.get("animated_contact_hit", false)
			and candidate_clearance <= _owner.GROUND_CONTACT_DISTANCE
			and candidate_state.smoothed_lift <= _owner.GROUND_CONTACT_DISTANCE
			and not _toe_probe_reaches_higher_surface(candidate_leg)
			and (candidate_velocity <= _owner.velocity_noise_floor
					or candidate_state.landing_seen)):
		_support_side = candidate
		_latch_support_target(candidate_leg)


func _latch_support_target(leg: Dictionary) -> void:
	_support_transfer_elapsed = 0.0
	_support_transfer_from_pos = leg.get("target", leg.get("hip_pos", Vector3.ZERO)) as Vector3
	if (leg.get("animated_contact_hit", false)
			and not _toe_probe_reaches_higher_surface(leg)):
		_support_surface_target = leg["animated_contact_position"]
		_support_normal = leg["animated_contact_normal"]
		_support_ground_target = (
				_support_surface_target + _support_normal * float(leg["effective_offset"]))
	else:
		_support_ground_target = leg["raw_ground_target"]
		_support_surface_target = leg["raw_target"]
		_support_normal = leg["raw_normal"]


## A flat stair tread's contact normal is near Vector3.UP; a sloped ramp's
## isn't (a 45deg ramp reads ~0.71). Distinguishes "real stair descent, must
## plant instantly or the pelvis sinks through the riser gap" from "sloped
## ramp re-latch mid-turn, safe to smooth" - two earlier attempts at this
## (an unconditional clamp, and one gated on debug_step_down) both hit the
## identical FOOT_IK_BODY_PENETRATION_CHECK failure (15 samples, max_depth
## 0.308m); debug_step_down isn't true for every frame of a real descent, so
## it didn't distinguish the two cases. Surface tilt does, since it doesn't
## depend on gait timing at all.
##
## The weight/target snap to their full support value here used to be
## unconditional (1.0 the instant support transfers), which is a DIFFERENT
## case from the general shared_drop engage/release smoothing documented on
## player_foot_ik_modifier.gd's _shape_shared_drop(): that smoothing is about
## a single leg's reach growing continuously (e.g. mid-descent), where a
## delay leaves the leg stretched. This is a discrete handoff between two
## already-latched targets - blending target/weight over a short fixed
## support_transfer_blend_time (not the general shared_drop lerp already
## reverted once) removes the once-per-step pelvis/foot pop at exactly the
## support-side swap without reopening that stretch/penetration regression.
## Gated on STAIR_TREAD_UP_DOT, not the looser FLAT_SURFACE_UP_DOT: a shallow
## ramp (15deg reads 0.966, above FLAT_SURFACE_UP_DOT but below this) still
## keeps stair-support ownership, and blending its settle-transfer measurably
## regressed FOOT_IK_RAMP_CASE (0 -> 4 penetrating samples, one static settle
## case) - a real stair tread is the only case this fix is meant to cover.
func _apply_support_contact(side: StringName, leg: Dictionary, delta: float) -> void:
	if delta > 0.0:
		_support_transfer_elapsed += delta
	var transfer_time: float = (
			_owner.support_transfer_blend_time
			if _support_normal.dot(Vector3.UP) >= STAIR_TREAD_UP_DOT else 0.0)
	var blend := 1.0 if transfer_time <= 0.0 else clampf(
			_support_transfer_elapsed / transfer_time, 0.0, 1.0)
	leg["preserve_idle_pose"] = false
	var on_flat_tread := _support_normal.dot(Vector3.UP) >= FLAT_SURFACE_UP_DOT
	var surface_target := _support_surface_target
	if not on_flat_tread and _owner._smoothed_target.has(side):
		surface_target = _owner._ground_sampler.move_target_smoothed(
				_owner._smoothed_target[side] as Vector3, _support_surface_target, delta)
	_owner._smoothed_target[side] = surface_target
	_owner._smoothed_normal[side] = _support_normal
	# leg["effective_offset"] is recomputed fresh every frame regardless of
	# support state (see FootIKGroundSampler.sample()) - use it directly instead
	# of _support_ground_target's cached offset, which is only set once at
	# _latch_support_target() and never refreshed during ordinary retention.
	# A retained support foot could keep a wrong offset for its entire
	# retention if the one latching frame measured it before the character
	# had settled onto the surface's true tilt (confirmed live: a support
	# foot toe-clipped by ~1cm for an entire idle session on a 45deg ramp).
	var offset := _support_normal * float(leg.get("effective_offset", 0.0))
	var full_target := surface_target + offset
	var blended_target: Vector3 = _support_transfer_from_pos.lerp(full_target, blend)
	leg["ground_weight"] = blend
	# leg["chain_weight"] must move with ground_weight, not just default to it -
	# _apply_support_pelvis_and_legs() reads chain_weight straight from this
	# dict (leg.get("chain_weight", ground_weight)), and the per-leg loop
	# already wrote its own (pre-support, often 0.0) chain_weight earlier this
	# frame. Leaving it unset here meant a support leg could read ground_weight
	# 1.0 while its solve() rotation weight (chain_weight) was still 0.0 - full
	# target/weight, zero actual correction applied (confirmed live: an idle
	# stair-edge stance clipping 15-18cm, foot bit-for-bit equal to its raw
	# animated pose despite ground_weight=1.0).
	leg["chain_weight"] = blend
	leg["target"] = blended_target
	leg["ground_target"] = blended_target
	_owner._smoothed_ground_weight[side] = blend
