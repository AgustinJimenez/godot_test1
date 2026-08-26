extends RefCounted
## Converts animation motion and contact observations into a stable IK weight.
## It owns no geometry decisions and writes no bones.

var _owner


func _init(owner) -> void:
	_owner = owner


func reset_runtime_state() -> void:
	_locomotion_lock_released.clear()
	_locomotion_lock_active.clear()
	_locomotion_stance_active.clear()
	_locomotion_landing_imminent.clear()


const DISCONTINUITY_HOLD_FRAMES := 1
## Wider than DISCONTINUITY_HOLD_FRAMES on purpose - see this function's doc.
const VELOCITY_SUPPRESS_FRAMES := 2
const STAIR_WEIGHT_RISE_TIME := 0.12
const STAIR_WEIGHT_FALL_TIME := 0.05


## An animation loop reset jumps current_animation_position backward
## instantly - a real discontinuity, not motion. Diffing across it in
## _measure_velocity as if it were a normal frame produced a spurious
## velocity spike large enough to trigger a visible sag/pop, confirmed live
## locked to the loop point. Called once per frame (not per-leg) from
## player_foot_ik_modifier.gd, before either leg's velocity is measured.
##
## Two separate windows, not one: holding rendered pose/state across several
## frames while the real animation keeps advancing underneath just delays
## and enlarges the same snap once it expires (confirmed via the automated
## FOOT_IK_POSE_CONTINUITY_CHECK harness catching a widened 3-frame pose hold
## reproducing a bigger version of the bug), so DISCONTINUITY_HOLD_FRAMES
## (pose holds, contact_lost bypass) stays exactly 1. But velocity itself
## isn't held pose - it's just suppressed to 0 - and the clip's own post-seam
## motion still read as a real ~8 m/s spike a full frame after the 1-frame
## hold had already expired (also caught live via the same harness's capture
## file), so VELOCITY_SUPPRESS_FRAMES covers one frame more.
func update_animation_discontinuity(delta: float) -> void:
	# Called twice per physics tick (see player_foot_ik_modifier.gd's own note
	# on that pattern) - the phantom delta<=0 call must leave state alone
	# rather than touch it, or it always clobbers back right after the real
	# call sets it, before anything downstream can see it.
	if delta <= 0.0 or _owner.player_body == null or _owner.player_body.anim_player == null:
		return
	var anim_pos: float = _owner.player_body.anim_player.current_animation_position
	if _owner._prev_animation_position >= 0.0 and anim_pos < _owner._prev_animation_position - 0.05:
		_owner._animation_discontinuity_hold = DISCONTINUITY_HOLD_FRAMES
		_owner._velocity_suppress_hold = VELOCITY_SUPPRESS_FRAMES
	else:
		_owner._animation_discontinuity_hold = maxi(0, _owner._animation_discontinuity_hold - 1)
		_owner._velocity_suppress_hold = maxi(0, _owner._velocity_suppress_hold - 1)
	_owner._animation_discontinuous = _owner._animation_discontinuity_hold > 0
	_owner._velocity_suppressed = _owner._velocity_suppress_hold > 0
	_owner._prev_animation_position = anim_pos


## flags: "step_down"/"skip_velocity_gate"/"frozen"/"force_plant" bools (default false) -
## bundled to stay under the linter's max-argument count.
func update(
	side: StringName,
	animated_foot_pos: Vector3,
	foot_pos: Vector3,
	ground_target: Vector3,
	contact_hit: bool,
	contact_distance: float,
	to_world: Transform3D,
	delta: float,
	flags: Dictionary = {}
) -> Dictionary:
	var step_down: bool = flags.get("step_down", false)
	var penetrating_contact: bool = flags.get("penetrating_contact", false)
	var skip_velocity_gate: bool = flags.get("skip_velocity_gate", false)
	var frozen: bool = flags.get("frozen", false)
	var void_dangle: bool = flags.get("void_dangle", false)
	var velocity := _measure_velocity(side, animated_foot_pos, to_world, delta)
	var landed := _update_landing(side, velocity, delta)
	var locomotion_stance := false
	if skip_velocity_gate or void_dangle:
		_locomotion_stance_active[side] = false
	else:
		locomotion_stance = _update_locomotion_stance(side, velocity, landed)
	# A vertical-velocity valley can look like a landing while a crouch foot
	# is still high in its swing. Phase alone must not bypass contact loss or
	# apply full plant weight until the sole is near a real surface.
	var stance_contact: bool = (
		locomotion_stance and contact_hit and contact_distance <= _owner.step_min_rise
	)
	var force_plant: bool = _owner.force_plant_mode or flags.get("force_plant", false)
	var clearance_above_target := foot_pos.y - ground_target.y
	var idle_settle_budget: float = _owner.step_down_pelvis_drop
	var on_slope := ((_owner._smoothed_normal.get(side, Vector3.UP) as Vector3)
			.dot(Vector3.UP) < 0.999)
	if on_slope:
		# Turning in place can put one animated foot far downhill on a steep
		# ramp. It is still valid support within the shared pelvis crouch range;
		# treating it as a lost swing contact drops IK and leaves it floating.
		idle_settle_budget = _owner.step_down_max_crouch
	var idle_settling: bool = (
		not void_dangle
		and _body_horizontal_speed() <= IDLE_TRANSLATION_EPSILON
		and _owner._grounded
		and contact_hit
		and clearance_above_target <= idle_settle_budget + _owner.step_min_rise
	)
	var idle_sloped_contact: bool = (
		not void_dangle
		and _body_horizontal_speed() <= IDLE_TRANSLATION_EPSILON
		and _owner._grounded
		and contact_hit
		and on_slope
	)
	var contact_lost: bool = (
		void_dangle
		or (
			not idle_sloped_contact
			and not step_down
			and not idle_settling
			and not penetrating_contact
			and _owner.step_prediction_enabled
			and not force_plant
			and not frozen
			and not stance_contact
			and not _owner._animation_discontinuous
			and (
				not contact_hit
				or clearance_above_target > _owner.GROUND_CONTACT_DISTANCE
			)
		)
	)
	var raw_weight := _raw_weight(side, velocity)
	# Velocity is deliberately zeroed across an animation loop seam. Zero is
	# otherwise interpreted as a planted foot, which created a one-frame IK
	# pulse on a released swing leg. Hold the existing state across the seam.
	if _owner._velocity_suppressed and not force_plant and not frozen:
		raw_weight = float(_owner._smoothed_ground_weight.get(side, raw_weight))
		contact_lost = false
	elif penetrating_contact:
		raw_weight = 1.0
		contact_lost = false
	elif contact_lost:
		raw_weight = 0.0
	elif force_plant:
		raw_weight = 1.0
	elif stance_contact and not _locomotion_target_overextended(side):
		raw_weight = 1.0
	elif frozen:
		# Freezing already bypasses the raycast search and contact_lost
		# above, on the reasoning that this foot is genuinely planted and
		# should stop reacting to noise - but _raw_weight()'s own velocity
		# formula never checked frozen, so ordinary idle sway crossing
		# velocity_noise_floor still nudged weight down every cycle even
		# on an already-frozen foot (confirmed live: freeze_streak pinned
		# at its cap - genuinely frozen - while weight kept dipping anyway).
		raw_weight = 1.0
	elif skip_velocity_gate:
		# Landing-grace window (see player_foot_ik_modifier.gd's
		# _landing_grace_time): the land-recovery animation's own foot motion
		# right after a real touchdown is fast enough to read as a genuine
		# swing to the velocity-based gate below, even though the character
		# has already landed and contact is confirmed close by (contact_lost
		# false). Plant fully instead of fighting that animation noise for
		# the grace window's duration.
		raw_weight = 1.0
	_owner.debug_raw_weight[side] = raw_weight
	_owner.debug_contact_lost[side] = contact_lost
	var weight := _smooth_weight(side, raw_weight, contact_lost, delta)
	if penetrating_contact or force_plant or idle_sloped_contact:
		weight = 1.0
		_owner._smoothed_ground_weight[side] = 1.0
	return {"vertical_velocity": velocity, "ground_weight": weight, "landed": landed}


func _measure_velocity(
	side: StringName, foot_pos: Vector3, to_world: Transform3D, delta: float
) -> float:
	var velocity := 0.0
	if delta <= 0.0:
		return velocity
	# See update_animation_discontinuity's doc comment - _velocity_suppressed
	# covers a wider window than the pose hold - but still refresh the
	# reference below so later frames diff against the fresh, post-loop pose.
	if not _owner._velocity_suppressed and _owner._prev_animated_foot_pos.has(side):
		var previous: Vector3 = _owner._prev_animated_foot_pos[side]
		var world_delta := to_world.basis * (foot_pos - previous)
		velocity = (
			world_delta.dot(_owner._smoothed_normal[side] as Vector3)
			/ (delta * maxf(_owner.player_body.locomotion_playback_scale, 0.001))
		)
	_owner._prev_animated_foot_pos[side] = foot_pos
	# Same fix as _step_down_classification's static streak (see that comment
	# for the full story): idle-animation noise can tick velocity back above
	# -velocity_noise_floor for a single frame without the foot having
	# actually started rising, and a hard reset here made min_falling_streak
	# never sustain, which pinned _raw_weight's falling branch at 0.0
	# indefinitely - confirmed live (paused=false, animation genuinely
	# advancing, ground_weight stuck at exactly 0.0 the whole time). Only
	# decay by 1 for that near-zero noise band; a real reversal into
	# genuinely positive (rising) velocity still resets immediately, same as
	# a genuine swing start must.
	var falling: int = _owner._falling_streak.get(side, 0)
	if velocity < -_owner.velocity_noise_floor:
		falling += 1
	elif velocity < _owner.velocity_noise_floor:
		falling = maxi(0, falling - 1)
	else:
		falling = 0
	_owner._falling_streak[side] = falling
	# Same hysteresis, mirrored for the rising side - see _raw_weight's own
	# comment for why this pairs with min_falling_streak below. Without it,
	# a single-frame idle-sway blip (breathing, etc.) that barely exceeds
	# velocity_noise_floor gets amplified by rising_penalty into a large,
	# instant raw_weight drop with zero debounce, then recovers slower than
	# it fell (ground_weight_fall_time < rise_time) - a periodic sag/recover
	# twitch confirmed live, locked to the idle animation's own cycle.
	var rising: int = _owner._rising_streak.get(side, 0)
	if velocity > _owner.velocity_noise_floor:
		rising += 1
	elif velocity > -_owner.velocity_noise_floor:
		rising = maxi(0, rising - 1)
	else:
		rising = 0
	_owner._rising_streak[side] = rising
	_owner.debug_vertical_velocity[side] = velocity
	return velocity


## A genuine swing-start's rising velocity sustains for many frames, not one -
## same principle as min_falling_streak's own doc comment, just applied to
## the previously-unguarded rising branch (see _measure_velocity above). Kept
## as a flat, magnitude-independent 1.0 while the streak is low (unlike the
## falling branch's own margin below) - the rising formula's rising_penalty
## multiplier (4x) turns even a noise-floor-adjacent velocity into a real
## drop, so gating this branch by magnitude the same way the falling branch
## is gated made small idle sway swing-release far more often, not less
## (confirmed live: "now is more frequent" after that attempt).
##
## The falling branch's streak gate only kicks in once velocity is clearly
## past mere noise, not merely past velocity_noise_floor itself: idle sway
## barely crossing the floor (e.g. 0.032 vs a 0.03 floor) was getting the
## same hard snap to 0 as a genuine fast swing start, before any streak
## could build up - a periodic full-weight-drop-and-recover confirmed live
## and via the automated FOOT_IK_POSE_CONTINUITY_CHECK harness's trace file.
## A real swing quickly clears this margin anyway, so the streak protection
## (needed to stop a single-frame noise blip from sinking a foot into a
## tread before it's actually lifted) is unaffected for genuine swings.
const STREAK_GATE_MARGIN := 3.0  # multiple of velocity_noise_floor


func _raw_weight(side: StringName, velocity: float) -> float:
	var anim_name: String = (_owner.player_body.anim_player.current_animation.get_file()
			if _owner.player_body != null and _owner.player_body.anim_player != null else "")
	var is_idle_anim: bool = anim_name.is_empty() or anim_name.contains("idle")
	if is_idle_anim and _body_horizontal_speed() <= IDLE_TRANSLATION_EPSILON and _owner._grounded:
		return 1.0
	if absf(velocity) < _owner.velocity_noise_floor:
		return 1.0
	if velocity > 0.0:
		if int(_owner._rising_streak.get(side, 0)) < _owner.min_falling_streak:
			return 1.0
		return clampf(
			1.0 - velocity * _owner.rising_penalty / _owner.swing_speed_threshold, 0.0, 1.0
		)
	var past_margin: bool = absf(velocity) >= _owner.velocity_noise_floor * STREAK_GATE_MARGIN
	if past_margin and int(_owner._falling_streak.get(side, 0)) < _owner.min_falling_streak:
		return 0.0
	return clampf(1.0 - absf(velocity) / _owner.swing_speed_threshold, 0.0, 1.0)


## contact_lost forces raw_weight toward 0 same as any other fall, not as a
## post-hoc override - an override bypassed ground_weight_fall_time entirely,
## snapping instantly from the corrected pose to the raw animated pose in
## one frame whenever contact_lost coincided with unfreezing (the frozen
## target and the fresh animated pose routinely differ by tens of cm right
## after unfreezing) - confirmed via a live capture pinpointing the exact
## frame weight went 1.0 -> 0.0 with no intermediate step.
func _smooth_weight(side: StringName, raw_weight: float, contact_lost: bool, delta: float) -> float:
	# Once the body has landed, brief probe loss must not undo the deliberate
	# grace ramp. Dropping and reacquiring weight here made the solved leg
	# oscillate during the same touchdown instead of converging monotonically.
	if contact_lost and _owner._landing_grace_time <= 0.0:
		raw_weight = 0.0
	var previous: float = _owner._smoothed_ground_weight.get(
		side, 0.0 if _owner._landing_grace_time > 0.0 else raw_weight
	)
	var weight := raw_weight
	var rise_time: float = _owner.ground_weight_rise_time
	var fall_time: float = _owner.ground_weight_fall_time
	var character: Node = _owner.player_body.get_parent()
	var stair_hover: Variant = character.get("_stair_hover_offset_y")
	if stair_hover != null and absf(float(stair_hover)) > 0.001:
		rise_time = STAIR_WEIGHT_RISE_TIME
		fall_time = STAIR_WEIGHT_FALL_TIME
	if raw_weight > previous and rise_time > 0.0:
		weight = minf(raw_weight, previous + delta / rise_time)
	elif raw_weight < previous and fall_time > 0.0:
		weight = maxf(raw_weight, previous - delta / fall_time)
	# Watchdog: a normal ramp finishes within a handful of
	# ground_weight_rise_time windows. If raw_weight/contact_lost say weight
	# should clearly be rising and it has stayed far below raw_weight much
	# longer than that, something has gotten stuck by a mechanism testing
	# never reproduced (jump-in-place, jump-and-reposition, and 60 real
	# seconds of just standing still all recovered correctly in isolation -
	# only live play has shown a genuine, lasting stuck state, previously
	# clearable only by manually toggling "IK Active", which force-calls
	# reset_runtime_state() unconditionally; set_character_grounded()'s own
	# reset only fires on an actual airborne<->grounded transition). Self-heal
	# the same way that manual click does, automatically.
	# A brief single-frame contact_lost blip (the same kind of flicker the
	# streak fixes above tolerate) must not wipe out accumulated stuck time
	# in one shot, or the watchdog can never reach its threshold if that
	# flicker recurs every so often - decay gently instead of resetting to 0.
	var stuck: float = float(_owner._weight_stuck_time.get(side, 0.0))
	if not contact_lost and raw_weight - weight > 0.05 and delta > 0.0:
		stuck += delta
		if stuck > maxf(_owner.ground_weight_rise_time * 5.0, 0.5):
			weight = raw_weight
			stuck = 0.0
	else:
		stuck = maxf(0.0, stuck - delta * 4.0)
	_owner._weight_stuck_time[side] = stuck
	_owner._smoothed_ground_weight[side] = weight
	return weight


func _update_landing(side: StringName, velocity: float, delta: float) -> bool:
	# Landing is a phase edge, not every descent-to-leveling wobble inside an
	# already planted stance. Crouch-strafe's authored foot keeps bobbing after
	# contact; re-arming here emitted a second landing, reset lock-release
	# hysteresis, and teleported the target to the moving ray hit by ~0.9 m.
	# Toe-off clears stance below, after which the next real descent may arm.
	if bool(_locomotion_stance_active.get(side, false)):
		_owner._landing_fell[side] = false
		return false
	if (
		velocity < -_owner.velocity_noise_floor * STREAK_GATE_MARGIN
		and int(_owner._falling_streak.get(side, 0)) >= _owner.min_falling_streak
	):
		_owner._landing_fell[side] = true
	elif (
		delta > 0.0
		and velocity >= -_owner.velocity_noise_floor
		and bool(_owner._landing_fell.get(side, false))
	):
		_owner._landing_fell[side] = false
		_owner.foot_landed.emit(side, _owner._smoothed_target[side] as Vector3)
		return true
	return false


func _update_locomotion_stance(side: StringName, velocity: float, landed: bool) -> bool:
	if _body_horizontal_speed() <= IDLE_TRANSLATION_EPSILON:
		_locomotion_stance_active[side] = false
		return false
	var stance: bool = _locomotion_stance_active.get(side, false)
	if landed:
		stance = true
		_locomotion_lock_released[side] = false
	elif (
		stance
		and velocity > _owner.swing_speed_threshold
		and int(_owner._rising_streak.get(side, 0)) >= _owner.min_falling_streak
	):
		stance = false
	_locomotion_stance_active[side] = stance
	return stance


const IDLE_FREEZE_STREAK := 30
const IDLE_UNFREEZE_SPEED_MULT := 3.0
const IDLE_UNFREEZE_STREAK := 3

## Reddit r/gamedev thread on foot IK (2020, "for anyone working on foot/leg
## IK please read this"): the classic "twitchy IK while standing still" bug
## comes from continuously re-raycasting even when idle, so ordinary noise
## (breathing, idle sway) occasionally flips the target between two adjacent
## valid surfaces. Their fix - stop resampling entirely once idle, freeze the
## last placement - matches this project's own repeated experience fighting
## that exact class of flicker with hysteresis/streak tuning instead of
## removing the resampling. Once a fully-planted foot (ground_weight >= 0.999)
## has read near-motionless for IDLE_FREEZE_STREAK real ticks, freeze; only a
## clearly real motion (IDLE_UNFREEZE_SPEED_MULT times the idle threshold, not
## just noise) releases it, so a genuine step still un-freezes promptly. The
## streak only advances on real (delta > 0) ticks - see
## player_foot_ik_modifier.gd's own note on the twice-per-tick call pattern.
## Un-freezing itself also needs IDLE_UNFREEZE_STREAK consecutive real ticks
## above that speed, not just one - a single-frame trigger let one idle
## animation's own periodic breathing/sway peak (higher than freeze's own
## streak tolerates, but only for an instant) yank a foot out of freeze every
## few seconds, visible as a recurring twitch right on the animation's cycle
## period - confirmed live via a debug-panel capture at the exact moment.
##
## anim_speed alone (vertical-only, and measured in the ANIMATED foot's own
## skeleton-local space) never rises while the player turns in place: pure
## rotation barely changes the animated pose relative to the skeleton, but
## the frozen *target* is a fixed world-space raycast hit that doesn't turn
## with the body at all, so the corrected foot stayed pinned to that stale
## point while the animated reference swept away from it turn after turn -
## confirmed live as "the legs aren't following" while spinning in place.
## Track the yaw at the moment of freezing and also unfreeze once it's
## rotated past IDLE_UNFREEZE_ROTATION_DEG - unlike the velocity trigger,
## this releases immediately with no debounce streak: a real cumulative
## rotation isn't ambiguous the way idle-sway noise is (it's a
## low-frequency, deliberate signal, not a per-frame velocity blip), and
## waiting several frames before resuming the raycast search would itself
## read as the leg lagging behind the turn rather than following it.
const IDLE_UNFREEZE_ROTATION_DEG := 6.0
const IDLE_TURNING_EPSILON_DEG := 0.1
const IDLE_TRANSLATION_EPSILON := 0.05
const LOCOMOTION_LOCK_RELEASE_REACH_RATIO := 0.98
const LOCOMOTION_AUTHORED_REACH_MARGIN := 0.0
const LOCOMOTION_LOCK_REARM_WEIGHT := 0.5

var _locomotion_lock_released: Dictionary = {}
var _locomotion_lock_active: Dictionary = {}
var _locomotion_stance_active: Dictionary = {}
var _locomotion_landing_imminent: Dictionary = {}


func prepare_contact_phase(side: StringName, velocity: float, delta: float) -> void:
	_locomotion_landing_imminent[side] = (
		delta > 0.0
		and bool(_owner._landing_fell.get(side, false))
		and velocity >= -_owner.velocity_noise_floor
	)


func is_locomotion_landing_imminent(side: StringName) -> bool:
	return bool(_locomotion_landing_imminent.get(side, false))


func update_idle_freeze(side: StringName, anim_speed: float, delta: float, yaw: float) -> bool:
	var frozen: bool = _owner._idle_frozen.get(side, false)
	var body_translating := _body_horizontal_speed() > IDLE_TRANSLATION_EPSILON
	var last_yaw_key := StringName("%s:last" % side)
	var last_yaw: float = _owner._idle_freeze_yaw.get(last_yaw_key, yaw)
	var yaw_stable := absf(angle_difference(last_yaw, yaw)) <= deg_to_rad(IDLE_TURNING_EPSILON_DEG)
	if delta > 0.0:
		_owner._idle_freeze_yaw[last_yaw_key] = yaw
		_owner._idle_freeze_yaw[StringName("%s:turning" % side)] = not yaw_stable
	if frozen and delta > 0.0:
		var freeze_yaw: float = _owner._idle_freeze_yaw.get(side, yaw)
		if body_translating:
			frozen = false
			_owner._idle_freeze_streak[side] = 0
			_owner._idle_unfreeze_streak[side] = 0
		elif absf(angle_difference(freeze_yaw, yaw)) > deg_to_rad(IDLE_UNFREEZE_ROTATION_DEG):
			frozen = false
			_owner._idle_freeze_streak[side] = 0
			_owner._idle_unfreeze_streak[side] = 0
		elif absf(anim_speed) > _owner.idle_step_down_speed * IDLE_UNFREEZE_SPEED_MULT:
			_owner._idle_unfreeze_streak[side] = int(_owner._idle_unfreeze_streak.get(side, 0)) + 1
		else:
			_owner._idle_unfreeze_streak[side] = 0
		if int(_owner._idle_unfreeze_streak.get(side, 0)) >= IDLE_UNFREEZE_STREAK:
			frozen = false
			_owner._idle_freeze_streak[side] = 0
			_owner._idle_unfreeze_streak[side] = 0
	elif not frozen and delta > 0.0:
		if (
			not body_translating
			and _owner._smoothed_ground_weight.get(side, 0.0) >= 0.999
			and absf(anim_speed) <= _owner.idle_step_down_speed
			and yaw_stable
		):
			_owner._idle_freeze_streak[side] = int(_owner._idle_freeze_streak.get(side, 0)) + 1
		else:
			_owner._idle_freeze_streak[side] = 0
		frozen = int(_owner._idle_freeze_streak.get(side, 0)) >= IDLE_FREEZE_STREAK
		if frozen:
			_owner._idle_freeze_yaw[side] = yaw
	_owner._idle_frozen[side] = frozen
	return frozen


func invalidate_idle_freeze(side: StringName) -> void:
	_owner._idle_frozen[side] = false
	_owner._idle_freeze_streak[side] = 0
	_owner._idle_unfreeze_streak[side] = 0
	_owner._idle_freeze_yaw.erase(side)


## A translating stance foot stays at its world contact instead of skating
## with the body. The lock is finite: release before the target consumes the
## leg's anatomical reach, then keep it released until the animation enters
## swing. That hysteresis prevents release/re-latch chatter and works for any
## movement direction; playback speed remains responsible for gait cadence.
## At idle the existing freeze-yaw rule still owns target stability.
func target_lock_allows_latch(side: StringName) -> bool:
	if _body_horizontal_speed() > IDLE_TRANSLATION_EPSILON:
		if not bool(_locomotion_stance_active.get(side, false)):
			_locomotion_lock_active[side] = false
			return false
		var weight: float = _owner._smoothed_ground_weight.get(side, 0.0)
		if weight <= LOCOMOTION_LOCK_REARM_WEIGHT:
			_locomotion_lock_released[side] = false
		var released: bool = _locomotion_lock_released.get(side, false)
		if not released and _locomotion_target_overextended(side):
			released = true
			_locomotion_lock_released[side] = true
		_locomotion_lock_active[side] = not released
		return not released
	_locomotion_lock_active[side] = false
	if not _owner._idle_freeze_yaw.has(side):
		return false
	var current_yaw := (_owner.player_body.get_parent() as Node3D).rotation.y
	var freeze_yaw: float = _owner._idle_freeze_yaw[side]
	return absf(angle_difference(freeze_yaw, current_yaw)) <= deg_to_rad(IDLE_UNFREEZE_ROTATION_DEG)


func is_locomotion_target_locked(side: StringName) -> bool:
	return bool(_locomotion_lock_active.get(side, false))


func is_locomotion_stance_active(side: StringName) -> bool:
	return bool(_locomotion_stance_active.get(side, false))


func _locomotion_target_overextended(side: StringName) -> bool:
	if (
		not _owner._smoothed_target.has(side)
		or not _owner._leg_fresh_pose_cache.has(side)
		or not _owner._leg_lengths.has(side)
	):
		return false
	var hip_pose: Transform3D = (_owner._leg_fresh_pose_cache[side] as Dictionary)["hip"]
	var hip_world: Vector3 = _owner.player_body.skeleton.global_transform * hip_pose.origin
	var offset: float = maxf(
		_owner.ankle_offset, float(_owner._sole_depth_below_foot.get(side, 0.0))
	)
	var target: Vector3 = (
		(_owner._smoothed_target[side] as Vector3)
		+ (_owner._smoothed_normal[side] as Vector3) * offset
	)
	var to_world: Transform3D = _owner.player_body.skeleton.global_transform
	var local_tgt := to_world.affine_inverse() * target
	if (side == &"left" and local_tgt.x > 0.0) or (side == &"right" and local_tgt.x < 0.0):
		return true
	var lengths := _owner._leg_lengths[side] as Dictionary
	var reach: float = float(lengths["upper"]) + float(lengths["lower"])
	var fresh := _owner._leg_fresh_pose_cache[side] as Dictionary
	var animated_hip: Vector3 = (
		_owner.player_body.skeleton.global_transform * (fresh["hip"] as Transform3D).origin
	)
	var animated_foot: Vector3 = (
		_owner.player_body.skeleton.global_transform * (fresh["foot"] as Transform3D).origin
	)
	var authored_reach := animated_hip.distance_to(animated_foot)
	var release_reach := minf(
		reach * LOCOMOTION_LOCK_RELEASE_REACH_RATIO,
		authored_reach + LOCOMOTION_AUTHORED_REACH_MARGIN
	)
	return hip_world.distance_to(target) >= release_reach


func is_body_turning(side: StringName) -> bool:
	return bool(_owner._idle_freeze_yaw.get(StringName("%s:turning" % side), false))


## True while the owning CharacterBody3D actually translates. Distinguishes
## "turning in place" (pure rotation) from walking while turning - a planted
## foot may follow a turn sideways, but only real translation may move it UP
## onto a higher stair tread (see FootIKGroundSampler.sample()).
func is_body_translating() -> bool:
	return _body_horizontal_speed() > IDLE_TRANSLATION_EPSILON


func _body_horizontal_speed() -> float:
	var node: Node = _owner.player_body.get_parent()
	while node != null and not node is CharacterBody3D:
		node = node.get_parent()
	if node == null:
		return 0.0
	var velocity := (node as CharacterBody3D).velocity
	return Vector2(velocity.x, velocity.z).length()
