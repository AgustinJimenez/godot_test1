class_name FootIKLegPoseEvaluator
extends RefCounted
## Candidate-local computation only. All reads use a fixed input snapshot; all history and
## diagnostic writes go to this evaluator's private state, returned for optional acceptance.
## Intra-evaluation read-after-write ordering intentionally preserves the legacy solver.

const IDLE_STANCE_MIN_SIDE_CLEARANCE := 0.04
var _input: FootIKLegSolveInput
var state: FootIKLegSolveState


func _init(input: FootIKLegSolveInput) -> void:
	_input = input
	state = FootIKLegSolveState.capture(input.history)


func _new_result() -> FootIKLegPoseResult:
	var result := FootIKLegPoseResult.new()
	result.side = _input.side
	result.source_revision = _input.source_revision
	result.source_solver_id = _input.source_solver_id
	result.physics_frame = _input.physics_frame
	result.skeleton_id = _input.skeleton_id
	result.to_world = _input.to_world
	result.next_state = state
	return result


func evaluate_pose(side: StringName, hip_pos: Vector3, target: Vector3,
		upper_length: float, lower_length: float, ground_weight: float,
		chain_weight: float, delta: float, options: Dictionary = {}) -> FootIKLegPoseResult:
	var instant_correction: bool = options.get(&"instant", false)
	var target_plan_validated: bool = options.get(&"target_plan_validated", false)
	var stationary_slope: bool = options.get(&"stationary_slope", false)
	var indices: Dictionary = _input.indices
	state.debug_solve_target[side] = target
	var hip_idx: int = indices["hip"]
	var knee_idx: int = indices["knee"]
	var foot_idx: int = indices["foot"]
	var toe_idx: int = indices["toe"]
	var leaf_idx: int = indices["leaf"]
	var to_world := _input.to_world
	# Animation/loop-hold selection was frozen before candidate evaluation.
	var poses: Dictionary = _input.poses
	var hip_pose: Transform3D = poses["hip"]
	var knee_pose: Transform3D = poses["knee"]
	var foot_pose: Transform3D = poses["foot"]
	var toe_pose: Transform3D = poses["toe"]
	var leaf_pose: Transform3D = poses["leaf"]
	var solve_weight := clampf(ground_weight, 0.0, 1.0)
	var positional_weight := clampf(chain_weight, 0.0, 1.0)
	var knee_pos: Vector3 = to_world * knee_pose.origin
	var foot_pos: Vector3 = to_world * foot_pose.origin
	var animated_hip_pos: Vector3 = to_world * hip_pose.origin
	# Weight zero is a pass-through only when no stair swing-lift changed the
	# target. The predictor deliberately raises a released foot before its
	# next tread, and that positional correction still needs the chain solve.
	if positional_weight <= 0.0001 and target.distance_squared_to(foot_pos) < 0.000001:
		return release_pose(side, delta)
	var to_target := target - hip_pos
	if to_target.is_zero_approx():
		return release_pose(side, delta)
	var minimum_knee_angle := deg_to_rad(180.0 - _input.max_knee_flexion_degrees)
	var flexion_limited_reach := sqrt(maxf(0.0,
			upper_length * upper_length + lower_length * lower_length
			- 2.0 * upper_length * lower_length * cos(minimum_knee_angle)))
	var min_reach: float = maxf(absf(upper_length - lower_length) + 0.001,
			flexion_limited_reach)
	var dist := clampf(to_target.length(), min_reach,
			upper_length + lower_length - 0.001)
	var target_dir := to_target.normalized()
	var cos_hip_angle := clampf(
			(upper_length * upper_length + dist * dist - lower_length * lower_length)
			/ (2.0 * upper_length * dist), -1.0, 1.0)
	var hip_angle := acos(cos_hip_angle)
	# Target validation and the final solve share this constrained pole.
	var animated_bend := _animated_knee_pole(
			animated_hip_pos, knee_pos, foot_pos, to_target)
	var bend_direction := _solve_bend_direction(
			side, target_dir, hip_angle, to_world, dist, upper_length, animated_bend, delta)
	var new_hip_to_knee_dir := _thigh_direction(target_dir, bend_direction, hip_angle)
	# Anatomical hip swing limit: the thigh has never been constrained here,
	# so a target that ends up somewhere it shouldn't (a stale or wrong-tread
	# support target, a bad retraction) could rotate the whole leg sideways
	# or backward well past any real hip's range of motion. Clamp to a cone
	# around straight down - same trade-off the knee flexion clamp above
	# already accepts: the foot may fall short of target rather than force
	# an inhuman pose.
	var max_swing := deg_to_rad(_input.max_hip_swing_degrees)
	var swing_from_down := Vector3.DOWN.angle_to(new_hip_to_knee_dir)
	state.debug_swing_degrees[side] = rad_to_deg(swing_from_down)
	state.debug_swing_clamped[side] = swing_from_down > max_swing
	if swing_from_down > max_swing:
		var swing_axis := Vector3.DOWN.cross(new_hip_to_knee_dir)
		if swing_axis.length_squared() > 0.0001:
			new_hip_to_knee_dir = Vector3.DOWN.rotated(swing_axis.normalized(), max_swing)
	var new_knee_pos := hip_pos + new_hip_to_knee_dir * upper_length
	# Keep the calf rigid at lower_length, aimed from the (possibly clamped)
	# knee toward the original target - this is what lets the foot land
	# short of target instead of breaking bone length.
	var knee_to_target := target - new_knee_pos
	var new_knee_to_foot_dir := knee_to_target.normalized() if not knee_to_target.is_zero_approx() \
			else new_hip_to_knee_dir
	var new_foot_pos := new_knee_pos + new_knee_to_foot_dir * lower_length
	var hip_delta := Quaternion((knee_pos - animated_hip_pos).normalized(), new_hip_to_knee_dir)
	var knee_delta := Quaternion((foot_pos - knee_pos).normalized(), new_knee_to_foot_dir)
	# Weight the chain correction itself, not only its target position. Near
	# extension a small target change can imply a much larger hip/knee angle.
	# Landing grace uses a gentler cubic engagement, then ordinary gait keeps
	# the direct confidence weight while the rate limiter below prevents a
	# contact change from injecting a one-frame procedural joint snap.
	var rotation_weight := positional_weight
	if _input.landing_grace_time > 0.0:
		rotation_weight = positional_weight * positional_weight * positional_weight
	hip_delta = Quaternion.IDENTITY.slerp(hip_delta, rotation_weight)
	knee_delta = Quaternion.IDENTITY.slerp(knee_delta, rotation_weight)
	hip_delta = _limit_correction(side, &"hip", hip_delta, delta, instant_correction)
	knee_delta = _limit_correction(side, &"knee", knee_delta, delta, instant_correction)
	knee_delta = _limit_rendered_upright_shin(side, knee_delta, foot_pos - knee_pos)
	# Positions must come from the same weighted/rate-limited rotations that
	# will be rendered below. Previously they stayed at the full solve while
	# the bases were only partially corrected, so even a small IK weight could
	# put a crouch joint at 100% of the procedural target and visibly stretch
	# the skinned leg. Rotating the authored rigid segments preserves both bone
	# lengths and exact animation pass-through at zero weight.
	new_knee_pos = hip_pos + hip_delta * (knee_pos - animated_hip_pos)
	new_foot_pos = new_knee_pos + knee_delta * (foot_pos - knee_pos)
	state.debug_stance_limited[side] = false
	# stationary_slope legs already had their target pushed for stance clearance by
	# adjust_idle_slope_target (a slope-aware nudge on the target itself, in
	# player_foot_ik_modifier.gd). This check's own fallback is the raw *animated* pose,
	# which assumes flat ground - on a steep ramp that pose sits well below/above the real
	# surface, so re-triggering here on a mismatch this check can't explain (the swing clamp
	# above can shift the solved foot off the already-negotiated target) blends toward a
	# fallback that penetrates the ramp instead of preventing a crossed-leg pose. See 012.
	if not target_plan_validated and not stationary_slope:
		var stance_limit := _limit_idle_stance_crossing(
				side, to_world, hip_pos, animated_hip_pos, knee_pos, foot_pos,
				hip_delta, knee_delta, new_foot_pos)
		if not stance_limit.is_empty():
			hip_delta = stance_limit["hip_delta"]
			knee_delta = stance_limit["knee_delta"]
			new_knee_pos = stance_limit["knee_pos"]
			new_foot_pos = stance_limit["foot_pos"]
	var knee_limit := _limit_negative_rendered_knee(
			side, hip_pos, animated_hip_pos, knee_pos, foot_pos,
			new_knee_pos, new_foot_pos)
	if not knee_limit.is_empty():
		hip_delta = knee_limit["hip_delta"]
		knee_delta = knee_limit["knee_delta"]
		new_knee_pos = knee_limit["knee_pos"]
		new_foot_pos = knee_limit["foot_pos"]
	state.debug_target_error[side] = new_foot_pos.distance_to(target)
	state.debug_final_foot_position[side] = new_foot_pos
	var new_hip_basis_world := Basis(hip_delta) * (to_world.basis * hip_pose.basis)
	var new_knee_basis_world := Basis(knee_delta) * (to_world.basis * knee_pose.basis)
	var animated_foot_basis_world := to_world.basis * foot_pose.basis
	var ground_foot_basis_world := _input.ground_foot_basis
	var animated_foot_rotation := animated_foot_basis_world.get_rotation_quaternion()
	var desired_foot_rotation := animated_foot_rotation.slerp(
			ground_foot_basis_world.get_rotation_quaternion(), solve_weight)
	var foot_delta := _limit_correction(side, &"foot",
			desired_foot_rotation * animated_foot_rotation.inverse(), delta)
	var new_foot_basis_world := Basis(foot_delta) * animated_foot_basis_world
	var result := _new_result()
	result.has_pose = true
	result.hip_idx = hip_idx
	result.knee_idx = knee_idx
	result.foot_idx = foot_idx
	result.toe_idx = toe_idx
	result.leaf_idx = leaf_idx
	result.hip_basis = new_hip_basis_world
	result.hip_pos = hip_pos
	result.knee_basis = new_knee_basis_world
	result.knee_pos = new_knee_pos
	result.foot_basis = new_foot_basis_world
	result.foot_pos = new_foot_pos
	if toe_idx >= 0:
		_solve_toes(result, toe_idx, leaf_idx, {
			"to_world": to_world, "foot_pos": foot_pos,
			"new_foot_pos": new_foot_pos, "animated_basis": animated_foot_basis_world,
			"new_basis": new_foot_basis_world, "toe_pose": toe_pose,
			"leaf_pose": leaf_pose, "weight": solve_weight,
		})
	return result



func _solve_bend_direction(side: StringName, target_dir: Vector3,
		hip_angle: float, to_world: Transform3D,
		distance: float = 0.0, upper_length: float = 0.0,
		preferred_bend_world: Vector3 = Vector3.ZERO, delta: float = 0.0) -> Vector3:
	var bend: Vector3 = (preferred_bend_world if not preferred_bend_world.is_zero_approx()
			else to_world.basis * _input.knee_pole_local)
	bend -= target_dir * bend.dot(target_dir)
	if bend.length_squared() < 0.0001:
		bend = Vector3.FORWARD - target_dir * target_dir.z
	bend = bend.normalized()
	var positive_bend := bend
	var animation_name := _input.animation_name
	var own_surface: Vector3 = _input.own_surface
	var riser_surface_y: float = _input.riser_surface_y
	if (animation_name.contains("idle") and absf(own_surface.y - riser_surface_y) <= 0.03
			and _input.has_riser_away):
		var riser_away: Vector3 = _input.riser_away
		var safe_bend := riser_away - target_dir * riser_away.dot(target_dir)
		if safe_bend.length_squared() >= 0.0001:
			bend = safe_bend
	bend = bend.normalized()
	var max_swing := deg_to_rad(_input.max_hip_swing_degrees)
	if Vector3.DOWN.angle_to(_thigh_direction(target_dir, bend, hip_angle)) > max_swing:
		var down_bend := Vector3.DOWN - target_dir * Vector3.DOWN.dot(target_dir)
		if down_bend.length_squared() >= 0.0001:
			down_bend = down_bend.normalized()
			var low := 0.0
			var high := 1.0
			for _iteration in 10:
				var middle := (low + high) * 0.5
				var candidate := bend.slerp(down_bend, middle).normalized()
				if Vector3.DOWN.angle_to(_thigh_direction(
						target_dir, candidate, hip_angle)) > max_swing:
					low = middle
				else:
					high = middle
			bend = bend.slerp(down_bend, high).normalized()
	bend = _limit_upright_shin(
			side, target_dir, bend, hip_angle, distance, upper_length, max_swing)
	return _select_feasible_bend(target_dir, bend, positive_bend,
			hip_angle, distance, upper_length, max_swing, side, delta)


func _select_feasible_bend(target_dir: Vector3,
		preferred: Vector3, positive: Vector3, hip_angle: float,
		distance: float, upper_length: float, max_thigh_swing: float,
		side: StringName = &"", delta: float = 0.0) -> Vector3:
	if distance <= 0.0 or upper_length <= 0.0:
		return preferred
	var required_alignment := clampf(_input.minimum_knee_pole_alignment, 0.0, 1.0)
	var shin_limit := deg_to_rad(_input.max_upright_shin_swing_degrees)
	var best := Vector3.ZERO
	var best_score := INF
	# Both hard limits constrain the same knee plane. Select one plane that
	# satisfies them together instead of letting independent late guards undo
	# one another and become competing pose owners.
	for step in range(145):
		var angle := -PI + TAU * float(step) / 144.0
		var candidate := positive.rotated(target_dir, angle).normalized()
		if candidate.dot(positive) < required_alignment:
			continue
		var thigh := _thigh_direction(target_dir, candidate, hip_angle)
		if Vector3.DOWN.angle_to(thigh) > max_thigh_swing:
			continue
		var shin := target_dir * distance - thigh * upper_length
		if shin.length_squared() <= 0.000001 \
				or Vector3.DOWN.angle_to(shin.normalized()) > shin_limit:
			continue
		var score := preferred.angle_to(candidate)
		if score < best_score:
			best = candidate
			best_score = score
	var result := preferred if best.is_zero_approx() else best
	if side == &"":
		return result
	if delta <= 0.0:
		# A zero-delta re-evaluation (SkeletonModifier3D can run one per tick) has no time
		# budget to ease across, so reuse the last real update's choice instead of a fresh,
		# unsmoothed one.
		return state._previous_bend.get(side, result)
	var previous: Vector3 = state._previous_bend.get(side, Vector3.ZERO)
	if not previous.is_zero_approx():
		var previous_tangent := previous - target_dir * previous.dot(target_dir)
		if previous_tangent.length_squared() >= 0.0001:
			previous_tangent = previous_tangent.normalized()
			# Always ease toward the fresh result at a bounded angular rate instead of
			# snapping - see 013. Gating this on the previous choice still being feasible
			# does not help (it becomes infeasible too often to matter); a genuine large
			# state change still catches up within a handful of frames at this rate.
			const BEND_HYSTERESIS_SPEED_DEGREES := 240.0
			var max_step := deg_to_rad(BEND_HYSTERESIS_SPEED_DEGREES) * delta
			var angle_to_target := previous_tangent.angle_to(result)
			result = (previous_tangent.slerp(result, max_step / angle_to_target)
					if angle_to_target > max_step and angle_to_target > 0.000001
					else result)
	state._previous_bend[side] = result
	return result


func _limit_upright_shin(side: StringName, target_dir: Vector3, bend: Vector3,
		hip_angle: float, distance: float, upper_length: float,
		max_thigh_swing: float) -> Vector3:
	state.debug_shin_clamped[side] = false
	if distance <= 0.0 or upper_length <= 0.0:
		return bend
	var animation_name := _input.animation_name
	var normal: Vector3 = _input.normal
	if (animation_name.contains("crouch") or animation_name.contains("jump")
			or not (animation_name.contains("idle") or animation_name.contains("walk"))
			or normal.dot(Vector3.UP) < 0.999):
		return bend
	var limit := deg_to_rad(_input.max_upright_shin_swing_degrees)
	var steer_start := deg_to_rad(minf(
			_input.upright_shin_steer_start_degrees,
			_input.max_upright_shin_swing_degrees))
	var thigh := _thigh_direction(target_dir, bend, hip_angle)
	var shin := target_dir * distance - thigh * upper_length
	var swing := Vector3.DOWN.angle_to(shin.normalized())
	state.debug_shin_swing_degrees[side] = rad_to_deg(swing)
	if swing <= steer_start:
		return bend
	for step in range(1, 73):
		var angle := deg_to_rad(float(step) * 2.5)
		var best := Vector3.ZERO
		var best_swing := INF
		for sign_value in [-1.0, 1.0]:
			var candidate := bend.rotated(target_dir, angle * sign_value).normalized()
			var candidate_thigh := _thigh_direction(target_dir, candidate, hip_angle)
			if Vector3.DOWN.angle_to(candidate_thigh) > max_thigh_swing:
				continue
			var candidate_shin := target_dir * distance - candidate_thigh * upper_length
			var candidate_swing := Vector3.DOWN.angle_to(candidate_shin.normalized())
			if candidate_swing <= limit and candidate_swing < best_swing:
				best = candidate
				best_swing = candidate_swing
		if not best.is_zero_approx():
			# Begin turning the knee plane before the lower leg reaches its hard
			# limit. Switching to the distant valid pole only after crossing 45
			# degrees made the knee visibly snap during a platform-height change.
			var steer_weight := clampf(
					(swing - steer_start) / (limit - steer_start), 0.0, 1.0)
			best = bend.slerp(best, steer_weight).normalized()
			var steered_thigh := _thigh_direction(target_dir, best, hip_angle)
			var steered_shin := target_dir * distance - steered_thigh * upper_length
			best_swing = Vector3.DOWN.angle_to(steered_shin.normalized())
			state.debug_shin_clamped[side] = true
			state.debug_shin_swing_degrees[side] = rad_to_deg(best_swing)
			return best
	return bend


func _thigh_direction(target_dir: Vector3, bend: Vector3, hip_angle: float) -> Vector3:
	return (target_dir * cos(hip_angle) + bend * sin(hip_angle)).normalized()


func release_pose(side: StringName, delta: float) -> FootIKLegPoseResult:
	var result := _new_result()
	var hold_idle_loop := _input.hold_idle_loop
	if not state._previous_corrections.has("%s:hip" % side) and not hold_idle_loop:
		return result
	var poses: Dictionary = _input.release_poses
	var hip_delta := _limit_correction(side, &"hip", Quaternion.IDENTITY, delta)
	var knee_delta := _limit_correction(side, &"knee", Quaternion.IDENTITY, delta)
	var foot_delta := _limit_correction(side, &"foot", Quaternion.IDENTITY, delta)
	if (hip_delta.angle_to(Quaternion.IDENTITY) < 0.0001
			and knee_delta.angle_to(Quaternion.IDENTITY) < 0.0001
			and foot_delta.angle_to(Quaternion.IDENTITY) < 0.0001 and not hold_idle_loop):
		for joint: StringName in [&"hip", &"knee", &"foot"]:
			state._previous_corrections.erase("%s:%s" % [side, joint])
			state._previous_correction_frames.erase("%s:%s" % [side, joint])
		return result
	var indices: Dictionary = _input.indices
	var to_world := _input.to_world
	var animated_hip: Vector3 = to_world * (poses["hip"] as Transform3D).origin
	var animated_knee: Vector3 = to_world * (poses["knee"] as Transform3D).origin
	var animated_foot: Vector3 = to_world * (poses["foot"] as Transform3D).origin
	# Release and solve share the displaced pelvis frame. Cancelling its shift
	# only while correction history exists makes the whole leg jump at identity.
	var pelvis_offset: Vector3 = _input.pelvis_offset
	animated_hip += pelvis_offset
	animated_knee += pelvis_offset
	animated_foot += pelvis_offset
	var corrected_positions := {
		&"hip": animated_hip,
		&"knee": animated_hip + hip_delta * (animated_knee - animated_hip),
	}
	corrected_positions[&"foot"] = (corrected_positions[&"knee"] as Vector3) \
			+ knee_delta * (animated_foot - animated_knee)
	for joint: StringName in [&"hip", &"knee", &"foot"]:
		var pose: Transform3D = poses[joint]
		var correction := Quaternion.IDENTITY
		if joint == &"hip":
			correction = hip_delta
		elif joint == &"knee":
			correction = knee_delta
		elif joint == &"foot":
			correction = foot_delta
		var basis := Basis(correction) * (to_world.basis * pose.basis)
		result.set("%s_idx" % joint, indices[joint])
		result.set("%s_basis" % joint, basis)
		result.set("%s_pos" % joint, corrected_positions[joint])
	result.has_pose = true
	return result


func _limit_negative_rendered_knee(side: StringName, hip_pos: Vector3,
		animated_hip_pos: Vector3, animated_knee_pos: Vector3,
		animated_foot_pos: Vector3, rendered_knee_pos: Vector3,
		rendered_foot_pos: Vector3) -> Dictionary:
	state.debug_negative_knee_clamped[side] = false
	state.debug_knee_direction_constrained[side] = false
	var positive_axis := _animated_knee_pole(
			animated_hip_pos, animated_knee_pos, animated_foot_pos,
			rendered_foot_pos - hip_pos)
	var signed_flexion := _signed_knee_flexion(
			hip_pos, rendered_knee_pos, rendered_foot_pos, positive_axis)
	state.debug_signed_knee_flexion[side] = signed_flexion
	var animation_name := _input.animation_name
	var normal: Vector3 = _input.normal
	if (animation_name.contains("crouch")
			or not (animation_name.contains("idle") or animation_name.contains("walk"))
			or normal.dot(Vector3.UP) < 0.999):
		return {}
	var leg_line := rendered_foot_pos - hip_pos
	var distance := leg_line.length()
	var upper_length := (animated_knee_pos - animated_hip_pos).length()
	var lower_length := (animated_foot_pos - animated_knee_pos).length()
	if distance <= 0.0001 or upper_length <= 0.0001 or lower_length <= 0.0001:
		return {}
	var direction := leg_line / distance
	if positive_axis.length_squared() < 0.000001:
		return {}
	var current_pole := rendered_knee_pos - hip_pos
	current_pole -= direction * current_pole.dot(direction)
	var required_alignment := clampf(_input.minimum_knee_pole_alignment, 0.0, 1.0)
	var current_alignment := (current_pole.normalized().dot(positive_axis)
			if current_pole.length_squared() >= 0.000001 else 1.0)
	state.debug_knee_pole_alignment[side] = current_alignment
	if signed_flexion >= 0.0 and current_alignment >= required_alignment:
		return {}
	var boundary_pole := current_pole - positive_axis * current_pole.dot(positive_axis)
	if boundary_pole.length_squared() < 0.000001:
		boundary_pole = direction.cross(positive_axis)
	# Merely crossing the sign boundary leaves a deeply bent knee almost
	# sideways. Keep a modest authored-direction component without mirroring
	# the complete pole, which previously pushed calves into platform corners.
	var boundary_weight := sqrt(1.0 - required_alignment * required_alignment)
	var positive_pole := (boundary_pole.normalized() * boundary_weight
			+ positive_axis * required_alignment).normalized()
	var clamped_distance := minf(distance, upper_length + lower_length - 0.0001)
	var cos_hip_angle := clampf((upper_length * upper_length
			+ clamped_distance * clamped_distance - lower_length * lower_length)
			/ (2.0 * upper_length * clamped_distance), -1.0, 1.0)
	positive_pole = _select_feasible_bend(direction, positive_pole,
			positive_axis, acos(cos_hip_angle), clamped_distance, upper_length,
			deg_to_rad(_input.max_hip_swing_degrees))
	var along := (upper_length * upper_length - lower_length * lower_length
			+ clamped_distance * clamped_distance) / (2.0 * clamped_distance)
	var pole_distance := sqrt(maxf(0.0, upper_length * upper_length - along * along))
	var corrected_knee := hip_pos + direction * along + positive_pole * pole_distance
	var corrected_foot := rendered_foot_pos
	var corrected_hip_delta := Quaternion(
			(animated_knee_pos - animated_hip_pos).normalized(),
			(corrected_knee - hip_pos).normalized())
	var corrected_knee_delta := Quaternion(
			(animated_foot_pos - animated_knee_pos).normalized(),
			(corrected_foot - corrected_knee).normalized())
	# A wrong-side knee must not overwrite the rate limiter's valid destination:
	# doing so traps a nearly straight leg at this boundary forever. An already
	# positive knee that only needs the alignment cone may retain the constrained
	# pose, keeping ordinary stair rotation continuous.
	if signed_flexion >= 0.0:
		state._previous_corrections["%s:hip" % side] = corrected_hip_delta
		state._previous_corrections["%s:knee" % side] = corrected_knee_delta
	state.debug_negative_knee_clamped[side] = signed_flexion < 0.0
	state.debug_knee_direction_constrained[side] = true
	state.debug_knee_pole_alignment[side] = required_alignment
	state.debug_signed_knee_flexion[side] = _signed_knee_flexion(
			hip_pos, corrected_knee, corrected_foot, positive_axis)
	return {
		"hip_delta": corrected_hip_delta,
		"knee_delta": corrected_knee_delta,
		"knee_pos": corrected_knee,
		"foot_pos": corrected_foot,
	}


func _animated_knee_pole(animated_hip: Vector3, animated_knee: Vector3,
		animated_foot: Vector3, rendered_line: Vector3) -> Vector3:
	var animated_line := animated_foot - animated_hip
	if animated_line.length_squared() < 0.000001 or rendered_line.length_squared() < 0.000001:
		return Vector3.ZERO
	var along := clampf((animated_knee - animated_hip).dot(animated_line)
			/ animated_line.length_squared(), 0.0, 1.0)
	var pole := animated_knee - (animated_hip + animated_line * along)
	var rendered_direction := rendered_line.normalized()
	pole -= rendered_direction * pole.dot(rendered_direction)
	if pole.length_squared() < 0.000001:
		var actor_forward: Vector3 = _input.actor_forward
		pole = actor_forward - rendered_direction * actor_forward.dot(rendered_direction)
	return pole.normalized() if pole.length_squared() >= 0.000001 else Vector3.ZERO


func _signed_knee_flexion(hip: Vector3, knee: Vector3, foot: Vector3,
		positive_axis: Vector3) -> float:
	var upper := knee - hip
	var lower := foot - knee
	if upper.length_squared() < 0.000001 or lower.length_squared() < 0.000001:
		return 0.0
	var flexion := rad_to_deg(upper.angle_to(lower))
	var line := foot - hip
	if line.length_squared() < 0.000001:
		return flexion
	var along := clampf((knee - hip).dot(line) / line.length_squared(), 0.0, 1.0)
	var pole := knee - (hip + line * along)
	return flexion if pole.dot(positive_axis) >= 0.0 else -flexion


func _limit_rendered_upright_shin(side: StringName, knee_delta: Quaternion,
		animated_shin: Vector3) -> Quaternion:
	var animation_name := _input.animation_name
	var normal: Vector3 = _input.normal
	if (animation_name.contains("crouch") or animation_name.contains("jump")
			or not (animation_name.contains("idle") or animation_name.contains("walk"))
			or normal.dot(Vector3.UP) < 0.999 or animated_shin.length_squared() < 0.000001):
		return knee_delta
	var rendered_direction := (knee_delta * animated_shin).normalized()
	var limit := deg_to_rad(_input.max_upright_shin_swing_degrees)
	var swing := Vector3.DOWN.angle_to(rendered_direction)
	if swing <= limit:
		return knee_delta
	var horizontal := Vector3(rendered_direction.x, 0.0, rendered_direction.z)
	if horizontal.length_squared() < 0.000001:
		return knee_delta
	var limited_direction := (horizontal.normalized() * sin(limit)
			+ Vector3.DOWN * cos(limit)).normalized()
	var result := Quaternion(rendered_direction, limited_direction) * knee_delta
	var key := "%s:knee" % side
	state._previous_corrections[key] = result
	state.debug_shin_clamped[side] = true
	state.debug_shin_swing_degrees[side] = _input.max_upright_shin_swing_degrees
	return result


func _limit_idle_stance_crossing(side: StringName, to_world: Transform3D,
		hip_pos: Vector3, animated_hip_pos: Vector3, knee_pos: Vector3,
		foot_pos: Vector3, hip_delta: Quaternion, knee_delta: Quaternion,
		new_foot_pos: Vector3) -> Dictionary:
	state.debug_stance_limited[side] = false
	var animation_name := _input.animation_name
	if not animation_name.contains("idle") or animation_name.contains("crouch"):
		return {}
	var left_fresh: Dictionary = _input.fresh_poses.get(&"left", {})
	var right_fresh: Dictionary = _input.fresh_poses.get(&"right", {})
	if left_fresh.is_empty() or right_fresh.is_empty():
		return {}
	var left_hip: Vector3 = to_world * (left_fresh["hip"] as Transform3D).origin
	var right_hip: Vector3 = to_world * (right_fresh["hip"] as Transform3D).origin
	var left_dir := left_hip - right_hip
	left_dir.y = 0.0
	if left_dir.length_squared() <= 0.0001:
		return {}
	left_dir = left_dir.normalized()
	var side_sign := 1.0 if side == &"left" else -1.0
	var minimum := IDLE_STANCE_MIN_SIDE_CLEARANCE
	var root_pos := _input.root_position
	var final_clearance := (new_foot_pos - root_pos).dot(left_dir) * side_sign
	if final_clearance >= minimum:
		return {}
	var base_knee := hip_pos + (knee_pos - animated_hip_pos)
	var base_foot := base_knee + (foot_pos - knee_pos)
	var base_clearance := (base_foot - root_pos).dot(left_dir) * side_sign
	# If the animation/pelvis is already outside its side, the earlier target
	# recovery must move it inward. This limiter only prevents an otherwise
	# safe pose from being crossed by the procedural correction itself.
	if base_clearance < minimum:
		return {}
	state.debug_stance_limited[side] = true
	var safe_weight := 0.0
	var unsafe_weight := 1.0
	var safe_knee := base_knee
	var safe_foot := base_foot
	for _iteration in 12:
		var weight := (safe_weight + unsafe_weight) * 0.5
		var limited_hip := Quaternion.IDENTITY.slerp(hip_delta, weight)
		var limited_knee := Quaternion.IDENTITY.slerp(knee_delta, weight)
		var candidate_knee := hip_pos + limited_hip * (knee_pos - animated_hip_pos)
		var candidate_foot := candidate_knee + limited_knee * (foot_pos - knee_pos)
		var clearance := (candidate_foot - root_pos).dot(left_dir) * side_sign
		if clearance >= minimum:
			safe_weight = weight
			safe_knee = candidate_knee
			safe_foot = candidate_foot
		else:
			unsafe_weight = weight
	var limited_hip_delta := Quaternion.IDENTITY.slerp(hip_delta, safe_weight)
	var limited_knee_delta := Quaternion.IDENTITY.slerp(knee_delta, safe_weight)
	# The rate limiter has already cached the unrestricted corrections for this
	# frame. Keep its history aligned with the stance-safe pose that is actually
	# rendered; otherwise the next frame starts from the rejected solution and
	# can alternate between crossed and safe legs during a turn.
	state._previous_corrections["%s:hip" % side] = limited_hip_delta
	state._previous_corrections["%s:knee" % side] = limited_knee_delta
	return {
		"hip_delta": limited_hip_delta,
		"knee_delta": limited_knee_delta,
		"knee_pos": safe_knee,
		"foot_pos": safe_foot,
	}


func _limit_correction(side: StringName, joint: StringName,
		desired: Quaternion, delta: float, instant: bool = false) -> Quaternion:
	var key := "%s:%s" % [side, joint]
	var previous: Quaternion = state._previous_corrections.get(key, Quaternion.IDENTITY)
	var current_frame := _input.physics_frame
	if delta <= 0.0:
		return previous
	if int(state._previous_correction_frames.get(key, -1)) == current_frame:
		return previous
	if instant:
		state._previous_corrections[key] = desired
		state._previous_correction_frames[key] = current_frame
		return desired
	var is_crouch_animation := _input.animation_name.begins_with("unarmed_crouch")
	var is_idle_animation := _input.animation_name.contains("idle")
	if joint == &"foot" and not is_crouch_animation:
		state._previous_corrections[key] = desired
		state._previous_correction_frames[key] = current_frame
		return desired
	var angle := previous.angle_to(desired)
	var angular_speed := _input.joint_correction_speed_degrees
	if is_crouch_animation:
		angular_speed = _input.crouch_joint_speed_degrees
	elif is_idle_animation:
		angular_speed = _input.standing_joint_speed_degrees
	# When shared pelvis sink engages on stairs, allow knees to bend quickly to
	# match the pelvis drop without lagging into the stair step.
	if (_input.shared_drop > 0.001
			and (not is_idle_animation or _input.stair_active)):
		angular_speed = maxf(angular_speed, 720.0)
	# A planted target stays fixed in world space while the body travels along
	# a ramp. The ordinary 120-degree budget lets the leg trail far behind that
	# target on steeper slopes, visibly floating or cutting through the ramp.
	# Combined with the shared-drop case above via the larger rate, not "first
	# match wins" - the two conditions can co-occur (e.g. a ramp with pelvis
	# sink) and neither concern should shadow the other. See 012 (phase=move).
	if (_input.normal as Vector3).dot(Vector3.UP) < 0.999:
		angular_speed = maxf(angular_speed, 3600.0)
	# Preserve the existing task 019 acquisition-speed override, captured with the input.
	if _input.lower_acquiring:
		angular_speed = maxf(angular_speed, _input.idle_lower_acquire_joint_speed_degrees)
	var maximum_step := deg_to_rad(angular_speed) * delta
	var result := desired
	if angle > maximum_step and angle > 0.000001:
		result = previous.slerp(desired, maximum_step / angle)
	state._previous_corrections[key] = result
	state._previous_correction_frames[key] = current_frame
	return result


## Fills result's toe/leaf fields (world space) - does not write bones itself; see
## No skeleton access is permitted during evaluation.


func _solve_toes(result: FootIKLegPoseResult, toe_idx: int, leaf_idx: int,
		context: Dictionary) -> void:
	var to_world: Transform3D = context["to_world"]
	var foot_pos: Vector3 = context["foot_pos"]
	var new_foot_pos: Vector3 = context["new_foot_pos"]
	var animated_foot_basis: Basis = context["animated_basis"]
	var new_foot_basis: Basis = context["new_basis"]
	var toe_pose: Transform3D = context["toe_pose"]
	var leaf_pose: Transform3D = context["leaf_pose"]
	var weight: float = context["weight"]
	var toe_world := to_world * toe_pose
	var toe_offset := animated_foot_basis.inverse() * (toe_world.origin - foot_pos)
	var toe_relative := animated_foot_basis.inverse() * toe_world.basis
	var swing_pos := new_foot_pos + new_foot_basis * toe_offset
	var swing_basis := new_foot_basis * toe_relative
	var rest_pos := new_foot_pos + new_foot_basis * (_input.toe_rest_offset as Vector3)
	var rest_basis := new_foot_basis * (_input.toe_rest_relative_basis as Basis)
	result.has_toe = true
	result.toe_idx = toe_idx
	result.toe_basis = Basis(swing_basis.get_rotation_quaternion().slerp(
			rest_basis.get_rotation_quaternion(), weight))
	result.toe_pos = swing_pos.lerp(rest_pos, weight)
	if leaf_idx < 0:
		return
	var leaf_world := to_world * leaf_pose
	var leaf_offset := animated_foot_basis.inverse() * (leaf_world.origin - foot_pos)
	var leaf_relative := animated_foot_basis.inverse() * leaf_world.basis
	var leaf_swing_pos := new_foot_pos + new_foot_basis * leaf_offset
	var leaf_swing_basis := new_foot_basis * leaf_relative
	var leaf_rest_pos := new_foot_pos + new_foot_basis * (_input.leaf_rest_offset as Vector3)
	var leaf_rest_basis := new_foot_basis * (_input.leaf_rest_relative_basis as Basis)
	result.has_leaf = true
	result.leaf_idx = leaf_idx
	result.leaf_basis = Basis(leaf_swing_basis.get_rotation_quaternion().slerp(
			leaf_rest_basis.get_rotation_quaternion(), weight))
	result.leaf_pos = leaf_swing_pos.lerp(leaf_rest_pos, weight)
