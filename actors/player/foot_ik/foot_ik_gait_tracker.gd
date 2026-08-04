extends RefCounted
## Converts animation motion and contact observations into a stable IK weight.
## It owns no geometry decisions and writes no bones.

var _owner


func _init(owner) -> void:
	_owner = owner


func update(side: StringName, animated_foot_pos: Vector3, foot_pos: Vector3,
		ground_target: Vector3, contact_hit: bool, contact_distance: float,
		to_world: Transform3D, delta: float, step_down: bool = false) -> Dictionary:
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
	_owner._falling_streak[side] = (int(_owner._falling_streak.get(side, 0)) + 1
			if velocity < -_owner.velocity_noise_floor else 0)
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
