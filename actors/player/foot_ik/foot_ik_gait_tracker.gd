extends RefCounted
## Converts animation motion and contact observations into a stable IK weight.
## It owns no geometry decisions and writes no bones.

var _owner


func _init(owner) -> void:
	_owner = owner


func update(side: StringName, animated_foot_pos: Vector3, foot_pos: Vector3,
		ground_target: Vector3, contact_hit: bool, contact_distance: float,
		to_world: Transform3D, delta: float, step_down: bool = false,
		skip_velocity_gate: bool = false) -> Dictionary:
	var velocity := _measure_velocity(side, animated_foot_pos, to_world, delta)
	var force_plant: bool = _owner.force_plant_mode
	# A stationary stance foot easing down onto a reachable lower surface must
	# not be treated as contact-lost just because the sole is further than
	# GROUND_CONTACT_DISTANCE above it - step-down bypasses the distance gate
	# so the weight can rise and plant the foot on the lower target.
	var contact_lost: bool = not step_down and _owner.step_prediction_enabled \
			and not force_plant and (
			not contact_hit
			or contact_distance > _owner.GROUND_CONTACT_DISTANCE
			or foot_pos.distance_to(ground_target) > _owner.GROUND_CONTACT_DISTANCE)
	var raw_weight := _raw_weight(side, velocity)
	if contact_lost:
		raw_weight = 0.0
	elif force_plant:
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
	var landed := _update_landing(side, velocity, delta)
	return {"vertical_velocity": velocity, "ground_weight": weight, "landed": landed}


func _measure_velocity(side: StringName, foot_pos: Vector3,
		to_world: Transform3D, delta: float) -> float:
	var velocity := 0.0
	if delta <= 0.0:
		return velocity
	if _owner._prev_animated_foot_pos.has(side):
		var previous: Vector3 = _owner._prev_animated_foot_pos[side]
		var world_delta := to_world.basis * (foot_pos - previous)
		velocity = world_delta.dot(_owner._smoothed_normal[side] as Vector3) / (
				delta * maxf(_owner.player_body.locomotion_playback_scale, 0.001))
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
	_owner.debug_vertical_velocity[side] = velocity
	return velocity


func _raw_weight(side: StringName, velocity: float) -> float:
	if absf(velocity) < _owner.velocity_noise_floor:
		return 1.0
	if velocity > 0.0:
		return clampf(1.0 - velocity * _owner.rising_penalty
				/ _owner.swing_speed_threshold, 0.0, 1.0)
	if int(_owner._falling_streak.get(side, 0)) < _owner.min_falling_streak:
		return 0.0
	return clampf(1.0 - absf(velocity) / _owner.swing_speed_threshold, 0.0, 1.0)


func _smooth_weight(side: StringName, raw_weight: float,
		contact_lost: bool, delta: float) -> float:
	var previous: float = _owner._smoothed_ground_weight.get(side, raw_weight)
	var weight := raw_weight
	if raw_weight > previous and _owner.ground_weight_rise_time > 0.0:
		weight = minf(raw_weight, previous + delta / _owner.ground_weight_rise_time)
	elif raw_weight < previous and _owner.ground_weight_fall_time > 0.0:
		weight = maxf(raw_weight, previous - delta / _owner.ground_weight_fall_time)
	if contact_lost:
		weight = 0.0
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
	if velocity < -_owner.swing_speed_threshold:
		_owner._landing_fell[side] = true
	elif (delta > 0.0 and velocity >= -_owner.velocity_noise_floor
			and bool(_owner._landing_fell.get(side, false))):
		_owner._landing_fell[side] = false
		_owner.foot_landed.emit(side, _owner._smoothed_target[side] as Vector3)
		return true
	return false


const IDLE_FREEZE_STREAK := 30
const IDLE_UNFREEZE_SPEED_MULT := 3.0

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
func update_idle_freeze(side: StringName, anim_speed: float, delta: float) -> bool:
	var frozen: bool = _owner._idle_frozen.get(side, false)
	if frozen:
		if absf(anim_speed) > _owner.idle_step_down_speed * IDLE_UNFREEZE_SPEED_MULT:
			frozen = false
			_owner._idle_freeze_streak[side] = 0
	elif delta > 0.0:
		if (_owner._smoothed_ground_weight.get(side, 0.0) >= 0.999
				and absf(anim_speed) <= _owner.idle_step_down_speed):
			_owner._idle_freeze_streak[side] = int(_owner._idle_freeze_streak.get(side, 0)) + 1
		else:
			_owner._idle_freeze_streak[side] = 0
		frozen = int(_owner._idle_freeze_streak.get(side, 0)) >= IDLE_FREEZE_STREAK
	_owner._idle_frozen[side] = frozen
	return frozen
