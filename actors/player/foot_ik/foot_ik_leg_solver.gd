extends RefCounted
## Closed-form output phase for one leg. Contact and gait policy remain owned
## by PlayerFootIKModifier; this class only converts a chosen target/weight
## into hierarchy-preserving hip, knee, foot, toe, and leaf bone poses.

var _owner
var _settings: FootIKRuntimeSettings
var _previous_corrections: Dictionary = {}
var _previous_correction_frames: Dictionary = {}
var _idle_slope_targets: Dictionary = {}
var _idle_slope_target_frames: Dictionary = {}
var _previous_bend: Dictionary = {} # side -> Vector3 (world-space, unit, tangent to target_dir)
var debug_stance_limited: Dictionary = {}
var debug_swing_clamped: Dictionary = {}
var debug_swing_degrees: Dictionary = {}
var debug_target_error: Dictionary = {}
var debug_solve_target: Dictionary = {}
var debug_final_foot_position: Dictionary = {}
var debug_shin_swing_degrees: Dictionary = {}
var debug_shin_clamped: Dictionary = {}
var debug_signed_knee_flexion: Dictionary = {}
var debug_negative_knee_clamped: Dictionary = {}
var debug_knee_pole_alignment: Dictionary = {}
var debug_knee_direction_constrained: Dictionary = {}

const IDLE_STANCE_MIN_SIDE_CLEARANCE := 0.04


func _init(owner) -> void:
	_owner = owner
	_settings = owner._ground_sampler._settings


func reset_runtime_state() -> void:
	_previous_corrections.clear()
	_previous_correction_frames.clear()
	_idle_slope_targets.clear()
	_idle_slope_target_frames.clear()
	_previous_bend.clear()
	debug_stance_limited.clear()
	debug_swing_clamped.clear()
	debug_swing_degrees.clear()
	debug_target_error.clear()
	debug_solve_target.clear()
	debug_final_foot_position.clear()
	debug_shin_swing_degrees.clear()
	debug_shin_clamped.clear()
	debug_signed_knee_flexion.clear()
	debug_negative_knee_clamped.clear()
	debug_knee_pole_alignment.clear()
	debug_knee_direction_constrained.clear()


func is_idle_stance_crossed(side: StringName, lateral_offset: float,
		animation_name: String) -> bool:
	return (animation_name.contains("idle") and not animation_name.contains("crouch")
			and (lateral_offset < IDLE_STANCE_MIN_SIDE_CLEARANCE
			if side == &"left" else lateral_offset > -IDLE_STANCE_MIN_SIDE_CLEARANCE))


func stance_lateral_offset(foot_position: Vector3, left_direction: Vector3,
		fallback_center: Vector3) -> float:
	var player_root := _owner.player_body.get_parent() as Node3D
	var center: Vector3 = player_root.global_position if player_root != null else fallback_center
	return (foot_position - center).dot(left_direction)


func release(side: StringName) -> void:
	for joint: StringName in [&"hip", &"knee", &"foot"]:
		_previous_corrections.erase("%s:%s" % [side, joint])
		_previous_correction_frames.erase("%s:%s" % [side, joint])


func has_active_correction(side: StringName) -> bool:
	return _previous_corrections.has("%s:hip" % side)


func capture_stable_animation_pose(side: StringName, poses: Dictionary,
		current_frame: int) -> void:
	var animation_name := String(_owner.player_body.anim_player.current_animation.get_file())
	var hold_idle_loop: bool = (animation_name.contains("idle")
			and not _owner._gait_tracker.is_body_translating()
			and (_owner._velocity_suppressed
			or _owner.player_body.anim_player.current_animation_position <= 0.10))
	if hold_idle_loop or _owner._prev_leg_bone_poses_frame.get(side, -1) == current_frame:
		return
	_owner._prev_leg_bone_poses[side] = poses
	_owner._prev_leg_bone_poses_frame[side] = current_frame


func adjust_idle_slope_target(side: StringName, hip: Vector3, target: Vector3,
		upper: float, lower: float, to_world: Transform3D, left_direction: Vector3) -> Vector3:
	var normal: Vector3 = _owner._smoothed_normal.get(side, Vector3.UP)
	var downhill := (Vector3.DOWN - normal * Vector3.DOWN.dot(normal)).normalized()
	var candidate := target
	for _step in 13:
		if _target_thigh_swing(side, hip, candidate, upper, lower, to_world) \
				<= deg_to_rad(max_hip_swing_degrees(side)):
			break
		candidate += downhill * 0.05
		var side_sign := 1.0 if side == &"left" else -1.0
		var clearance := stance_lateral_offset(candidate, left_direction, to_world.origin) * side_sign
		if clearance < IDLE_STANCE_MIN_SIDE_CLEARANCE:
			candidate += left_direction * side_sign * (IDLE_STANCE_MIN_SIDE_CLEARANCE - clearance)
			candidate -= normal * (candidate - target).dot(normal)
	var frame := Engine.get_physics_frames()
	var last_frame: int = _idle_slope_target_frames.get(side, -2)
	var previous: Vector3 = _idle_slope_targets.get(side, candidate)
	if last_frame == frame:
		return previous
	# The old >0.25m distance-based reset conflated two different situations: a leg
	# reacquiring after a different owner held it (genuinely needs to snap) and this
	# same owner running every frame while a rotating body legitimately moves the raw
	# candidate a lot in one frame (must stay smooth). Reset only on an actual gap in
	# consecutive calls - the real signal for reacquisition - not on how far the
	# candidate moved. See 013.
	if last_frame != frame - 1:
		previous = candidate
	var adjusted := previous.move_toward(candidate, 0.015)
	_idle_slope_targets[side] = adjusted
	_idle_slope_target_frames[side] = frame
	return adjusted

func _target_thigh_swing(side: StringName, hip: Vector3, target: Vector3,
		upper: float, lower: float, to_world: Transform3D) -> float:
	var to_target := target - hip
	var dist := clampf(to_target.length(), absf(upper - lower) + 0.001, upper + lower - 0.001)
	var target_dir := to_target.normalized()
	var cos_angle := clampf((upper * upper + dist * dist - lower * lower)
			/ (2.0 * upper * dist), -1.0, 1.0)
	var hip_angle := acos(cos_angle)
	var bend := _solve_bend_direction(
			side, target_dir, hip_angle, to_world, dist, upper)
	var thigh := _thigh_direction(target_dir, bend, hip_angle)
	return Vector3.DOWN.angle_to(thigh)


func max_hip_swing_degrees(_side: StringName) -> float:
	# Kept as a side-aware query because the regression validator and target
	# search share it. The exported anatomical safety cone currently applies
	# equally to both legs and every movement state.
	return _owner.max_hip_swing_degrees


func _solve_bend_direction(side: StringName, target_dir: Vector3,
		hip_angle: float, to_world: Transform3D,
		distance: float = 0.0, upper_length: float = 0.0,
		preferred_bend_world: Vector3 = Vector3.ZERO, delta: float = 0.0) -> Vector3:
	var bend: Vector3 = (preferred_bend_world if not preferred_bend_world.is_zero_approx()
			else to_world.basis * (_owner._knee_pole_local[side] as Vector3))
	bend -= target_dir * bend.dot(target_dir)
	if bend.length_squared() < 0.0001:
		bend = Vector3.FORWARD - target_dir * target_dir.z
	bend = bend.normalized()
	var positive_bend := bend
	var animation_name := String(_owner.player_body.anim_player.current_animation.get_file())
	var own_surface: Vector3 = _owner._smoothed_target.get(side, Vector3.ZERO)
	var riser_surface_y: float = _owner._ground_sampler.lower_riser_away_surface_y.get(
			side, INF)
	if (animation_name.contains("idle") and absf(own_surface.y - riser_surface_y) <= 0.03
			and _owner._ground_sampler.lower_riser_away.has(side)):
		var riser_away: Vector3 = _owner._ground_sampler.lower_riser_away[side]
		var safe_bend := riser_away - target_dir * riser_away.dot(target_dir)
		if safe_bend.length_squared() >= 0.0001:
			bend = safe_bend
	bend = bend.normalized()
	var max_swing := deg_to_rad(max_hip_swing_degrees(side))
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
	var required_alignment := clampf(_settings.minimum_knee_pole_alignment, 0.0, 1.0)
	var shin_limit := deg_to_rad(_settings.max_upright_shin_swing_degrees)
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
		return _previous_bend.get(side, result)
	var previous: Vector3 = _previous_bend.get(side, Vector3.ZERO)
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
	_previous_bend[side] = result
	return result


func _limit_upright_shin(side: StringName, target_dir: Vector3, bend: Vector3,
		hip_angle: float, distance: float, upper_length: float,
		max_thigh_swing: float) -> Vector3:
	debug_shin_clamped[side] = false
	if distance <= 0.0 or upper_length <= 0.0:
		return bend
	var animation_name := String(_owner.player_body.anim_player.current_animation.get_file())
	var normal: Vector3 = _owner._smoothed_normal.get(side, Vector3.UP)
	if (animation_name.contains("crouch") or animation_name.contains("jump")
			or not (animation_name.contains("idle") or animation_name.contains("walk"))
			or normal.dot(Vector3.UP) < 0.999):
		return bend
	var limit := deg_to_rad(_settings.max_upright_shin_swing_degrees)
	var steer_start := deg_to_rad(minf(
			_settings.upright_shin_steer_start_degrees,
			_settings.max_upright_shin_swing_degrees))
	var thigh := _thigh_direction(target_dir, bend, hip_angle)
	var shin := target_dir * distance - thigh * upper_length
	var swing := Vector3.DOWN.angle_to(shin.normalized())
	debug_shin_swing_degrees[side] = rad_to_deg(swing)
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
			debug_shin_clamped[side] = true
			debug_shin_swing_degrees[side] = rad_to_deg(best_swing)
			return best
	return bend


func _thigh_direction(target_dir: Vector3, bend: Vector3, hip_angle: float) -> Vector3:
	return (target_dir * cos(hip_angle) + bend * sin(hip_angle)).normalized()


func release_to_animation(skel: Skeleton3D, side: StringName, delta: float) -> void:
	var animation_name := String(_owner.player_body.anim_player.current_animation.get_file())
	var hold_idle_loop: bool = (animation_name.contains("idle")
			and not _owner._gait_tracker.is_body_translating()
			and (_owner._velocity_suppressed
			or _owner.player_body.anim_player.current_animation_position <= 0.10)
			and _owner._prev_leg_bone_poses.has(side))
	if not _previous_corrections.has("%s:hip" % side) and not hold_idle_loop:
		return
	var poses: Dictionary = _owner._leg_fresh_pose_cache[side]
	if hold_idle_loop:
		poses = _owner._prev_leg_bone_poses[side]
	var hip_delta := _limit_correction(side, &"hip", Quaternion.IDENTITY, delta)
	var knee_delta := _limit_correction(side, &"knee", Quaternion.IDENTITY, delta)
	var foot_delta := _limit_correction(side, &"foot", Quaternion.IDENTITY, delta)
	if (hip_delta.angle_to(Quaternion.IDENTITY) < 0.0001
			and knee_delta.angle_to(Quaternion.IDENTITY) < 0.0001
			and foot_delta.angle_to(Quaternion.IDENTITY) < 0.0001 and not hold_idle_loop):
		release(side)
		return
	var indices: Dictionary = _owner._bone_indices[side]
	var to_world := skel.global_transform
	var to_local := to_world.affine_inverse()
	var animated_hip: Vector3 = to_world * (poses["hip"] as Transform3D).origin
	var animated_knee: Vector3 = to_world * (poses["knee"] as Transform3D).origin
	var animated_foot: Vector3 = to_world * (poses["foot"] as Transform3D).origin
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
		skel.set_bone_global_pose(indices[joint], Transform3D(
				to_local.basis * basis, to_local * (corrected_positions[joint] as Vector3)))


func limit_idle_pelvis_shift(to_world: Transform3D, per_leg: Dictionary,
		proposed: Vector3, stationary: bool) -> Vector3:
	if not stationary or not per_leg.has(&"left") or not per_leg.has(&"right"):
		return proposed
	var left_leg: Dictionary = per_leg[&"left"]
	var right_leg: Dictionary = per_leg[&"right"]
	var left_hip: Vector3 = left_leg["hip_pos"]
	var right_hip: Vector3 = right_leg["hip_pos"]
	var left_dir := left_hip - right_hip
	left_dir.y = 0.0
	if left_dir.length_squared() <= 0.0001:
		return proposed
	left_dir = left_dir.normalized()
	var player_root := _owner.player_body.get_parent() as Node3D
	var center: Vector3 = player_root.global_position if player_root != null else to_world.origin
	var left_foot: Vector3 = left_leg.get("animated_foot_pos", center)
	var right_foot: Vector3 = right_leg.get("animated_foot_pos", center)
	var minimum := IDLE_STANCE_MIN_SIDE_CLEARANCE
	var minimum_shift := minimum - (left_foot - center).dot(left_dir)
	var maximum_shift := -minimum - (right_foot - center).dot(left_dir)
	if minimum_shift > maximum_shift:
		return proposed
	var lateral := proposed.dot(left_dir)
	return proposed + left_dir * (clampf(lateral, minimum_shift, maximum_shift) - lateral)


func solve(skel: Skeleton3D, side: StringName, hip_pos: Vector3, target: Vector3,
		upper_length: float, lower_length: float, ground_weight: float,
		chain_weight: float, delta: float, options: Dictionary = {}) -> void:
	var instant_correction: bool = options.get(&"instant", false)
	var target_plan_validated: bool = options.get(&"target_plan_validated", false)
	var stationary_slope: bool = options.get(&"stationary_slope", false)
	var indices: Dictionary = _owner._bone_indices[side]
	debug_solve_target[side] = target
	var hip_idx: int = indices["hip"]
	var knee_idx: int = indices["knee"]
	var foot_idx: int = indices["foot"]
	var toe_idx: int = indices["toe"]
	var leaf_idx: int = indices["leaf"]
	var to_world := skel.global_transform
	var to_local := to_world.affine_inverse()
	# A loop reset can leave a tiny, otherwise-invisible seam in the raw
	# animated pose; near full leg extension the law-of-cosines solve below
	# amplifies that seam into a visible whole-leg snap. On that one frame,
	# reuse last frame's held pose instead of this frame's fresh (seamed) one.
	# fresh_poses comes from PlayerFootIKModifier's own per-leg loop, captured
	# before _apply_support_pelvis_and_legs() sinks the pelvis this same tick -
	# reading the skeleton again here would see that same-tick sink, since the
	# pelvis is hip/knee/foot's parent (see that loop's own doc comment).
	var fresh_poses: Dictionary = _owner._leg_fresh_pose_cache[side]
	var poses: Dictionary = fresh_poses
	if _owner._animation_discontinuous and _owner._prev_leg_bone_poses.has(side):
		poses = _owner._prev_leg_bone_poses[side]
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
		release_to_animation(skel, side, delta)
		return
	var to_target := target - hip_pos
	if to_target.is_zero_approx():
		release_to_animation(skel, side, delta)
		return
	var minimum_knee_angle := deg_to_rad(180.0 - _owner.max_knee_flexion_degrees)
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
	var max_swing := deg_to_rad(max_hip_swing_degrees(side))
	var swing_from_down := Vector3.DOWN.angle_to(new_hip_to_knee_dir)
	debug_swing_degrees[side] = rad_to_deg(swing_from_down)
	debug_swing_clamped[side] = swing_from_down > max_swing
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
	if _owner._landing_grace_time > 0.0:
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
	debug_stance_limited[side] = false
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
	debug_target_error[side] = new_foot_pos.distance_to(target)
	debug_final_foot_position[side] = new_foot_pos
	var new_hip_basis_world := Basis(hip_delta) * (to_world.basis * hip_pose.basis)
	var new_knee_basis_world := Basis(knee_delta) * (to_world.basis * knee_pose.basis)
	var animated_foot_basis_world := to_world.basis * foot_pose.basis
	var raw_norm: Vector3 = _owner._smoothed_normal.get(side, Vector3.UP)
	var ground_foot_basis_world: Basis = (
			_owner._compute_new_foot_basis_world(skel, side, -raw_norm, foot_pose)
			if raw_norm.dot(Vector3.UP) < 0.999
			else animated_foot_basis_world)
	var animated_foot_rotation := animated_foot_basis_world.get_rotation_quaternion()
	var desired_foot_rotation := animated_foot_rotation.slerp(
			ground_foot_basis_world.get_rotation_quaternion(), solve_weight)
	var foot_delta := _limit_correction(side, &"foot",
			desired_foot_rotation * animated_foot_rotation.inverse(), delta)
	var new_foot_basis_world := Basis(foot_delta) * animated_foot_basis_world
	skel.set_bone_global_pose(hip_idx,
			Transform3D(to_local.basis * new_hip_basis_world, to_local * hip_pos))
	skel.set_bone_global_pose(knee_idx,
			Transform3D(to_local.basis * new_knee_basis_world, to_local * new_knee_pos))
	skel.set_bone_global_pose(foot_idx,
			Transform3D(to_local.basis * new_foot_basis_world, to_local * new_foot_pos))
	if toe_idx >= 0:
		_solve_toes(skel, side, toe_idx, leaf_idx, {
			"to_world": to_world, "to_local": to_local, "foot_pos": foot_pos,
			"new_foot_pos": new_foot_pos, "animated_basis": animated_foot_basis_world,
			"new_basis": new_foot_basis_world, "toe_pose": toe_pose,
			"leaf_pose": leaf_pose, "weight": solve_weight,
		})


func _limit_negative_rendered_knee(side: StringName, hip_pos: Vector3,
		animated_hip_pos: Vector3, animated_knee_pos: Vector3,
		animated_foot_pos: Vector3, rendered_knee_pos: Vector3,
		rendered_foot_pos: Vector3) -> Dictionary:
	debug_negative_knee_clamped[side] = false
	debug_knee_direction_constrained[side] = false
	var positive_axis := _animated_knee_pole(
			animated_hip_pos, animated_knee_pos, animated_foot_pos,
			rendered_foot_pos - hip_pos)
	var signed_flexion := _signed_knee_flexion(
			hip_pos, rendered_knee_pos, rendered_foot_pos, positive_axis)
	debug_signed_knee_flexion[side] = signed_flexion
	var animation_name := String(_owner.player_body.anim_player.current_animation.get_file())
	var normal: Vector3 = _owner._smoothed_normal.get(side, Vector3.UP)
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
	var required_alignment := clampf(_settings.minimum_knee_pole_alignment, 0.0, 1.0)
	var current_alignment := (current_pole.normalized().dot(positive_axis)
			if current_pole.length_squared() >= 0.000001 else 1.0)
	debug_knee_pole_alignment[side] = current_alignment
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
			deg_to_rad(max_hip_swing_degrees(side)))
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
		_previous_corrections["%s:hip" % side] = corrected_hip_delta
		_previous_corrections["%s:knee" % side] = corrected_knee_delta
	debug_negative_knee_clamped[side] = signed_flexion < 0.0
	debug_knee_direction_constrained[side] = true
	debug_knee_pole_alignment[side] = required_alignment
	debug_signed_knee_flexion[side] = _signed_knee_flexion(
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
		var actor_forward: Vector3 = -_owner.player_body.global_transform.basis.z.normalized()
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
	var animation_name := String(_owner.player_body.anim_player.current_animation.get_file())
	var normal: Vector3 = _owner._smoothed_normal.get(side, Vector3.UP)
	if (animation_name.contains("crouch") or animation_name.contains("jump")
			or not (animation_name.contains("idle") or animation_name.contains("walk"))
			or normal.dot(Vector3.UP) < 0.999 or animated_shin.length_squared() < 0.000001):
		return knee_delta
	var rendered_direction := (knee_delta * animated_shin).normalized()
	var limit := deg_to_rad(_settings.max_upright_shin_swing_degrees)
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
	_previous_corrections[key] = result
	debug_shin_clamped[side] = true
	debug_shin_swing_degrees[side] = _settings.max_upright_shin_swing_degrees
	return result


func _limit_idle_stance_crossing(side: StringName, to_world: Transform3D,
		hip_pos: Vector3, animated_hip_pos: Vector3, knee_pos: Vector3,
		foot_pos: Vector3, hip_delta: Quaternion, knee_delta: Quaternion,
		new_foot_pos: Vector3) -> Dictionary:
	debug_stance_limited[side] = false
	var animation_name := String(_owner.player_body.anim_player.current_animation.get_file())
	if not animation_name.contains("idle") or animation_name.contains("crouch"):
		return {}
	var left_fresh: Dictionary = _owner._leg_fresh_pose_cache.get(&"left", {})
	var right_fresh: Dictionary = _owner._leg_fresh_pose_cache.get(&"right", {})
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
	var player_root := _owner.player_body.get_parent() as Node3D
	var root_pos: Vector3 = player_root.global_position if player_root != null else to_world.origin
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
	debug_stance_limited[side] = true
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
	_previous_corrections["%s:hip" % side] = limited_hip_delta
	_previous_corrections["%s:knee" % side] = limited_knee_delta
	return {
		"hip_delta": limited_hip_delta,
		"knee_delta": limited_knee_delta,
		"knee_pos": safe_knee,
		"foot_pos": safe_foot,
	}


func _limit_correction(side: StringName, joint: StringName,
		desired: Quaternion, delta: float, instant: bool = false) -> Quaternion:
	var key := "%s:%s" % [side, joint]
	var previous: Quaternion = _previous_corrections.get(key, Quaternion.IDENTITY)
	var current_frame := Engine.get_physics_frames()
	if delta <= 0.0:
		return previous
	if int(_previous_correction_frames.get(key, -1)) == current_frame:
		return previous
	if instant:
		_previous_corrections[key] = desired
		_previous_correction_frames[key] = current_frame
		return desired
	var is_crouch_animation := false
	var is_idle_animation := false
	if _owner.player_body != null and _owner.player_body.anim_player != null:
		var animation_name := String(_owner.player_body.anim_player.current_animation.get_file())
		is_crouch_animation = animation_name.begins_with("unarmed_crouch")
		is_idle_animation = animation_name.contains("idle")
	if joint == &"foot" and not is_crouch_animation:
		_previous_corrections[key] = desired
		_previous_correction_frames[key] = current_frame
		return desired
	var angle := previous.angle_to(desired)
	var angular_speed := _settings.joint_correction_speed_degrees
	# When shared pelvis sink engages on stairs, allow knees to bend quickly to
	# match the pelvis drop without lagging into the stair step.
	if (_owner._smoothed_shared_drop > 0.001
			and (not is_idle_animation or _owner._stair_predictor.is_active())):
		angular_speed = 720.0
	# A planted target stays fixed in world space while the body travels along
	# a ramp. The ordinary 120-degree budget lets the leg trail far behind that
	# target on steeper slopes, visibly floating or cutting through the ramp.
	elif (_owner._smoothed_normal.get(side, Vector3.UP) as Vector3).dot(Vector3.UP) < 0.999:
		angular_speed = 3600.0
	elif is_crouch_animation:
		angular_speed = _settings.crouch_joint_speed_degrees
	elif is_idle_animation:
		angular_speed = _settings.standing_joint_speed_degrees
	var maximum_step := deg_to_rad(angular_speed) * delta
	var result := desired
	if angle > maximum_step and angle > 0.000001:
		result = previous.slerp(desired, maximum_step / angle)
	_previous_corrections[key] = result
	_previous_correction_frames[key] = current_frame
	return result


func _solve_toes(skel: Skeleton3D, side: StringName, toe_idx: int, leaf_idx: int,
		context: Dictionary) -> void:
	var to_world: Transform3D = context["to_world"]
	var to_local: Transform3D = context["to_local"]
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
	var rest_pos := new_foot_pos + new_foot_basis * (_owner._toe_rest_offset[side] as Vector3)
	var rest_basis := new_foot_basis * (_owner._toe_rest_relative_basis[side] as Basis)
	var toe_basis := Basis(swing_basis.get_rotation_quaternion().slerp(
			rest_basis.get_rotation_quaternion(), weight))
	skel.set_bone_global_pose(toe_idx, Transform3D(to_local.basis * toe_basis,
			to_local * swing_pos.lerp(rest_pos, weight)))
	if leaf_idx < 0:
		return
	var leaf_world := to_world * leaf_pose
	var leaf_offset := animated_foot_basis.inverse() * (leaf_world.origin - foot_pos)
	var leaf_relative := animated_foot_basis.inverse() * leaf_world.basis
	var leaf_swing_pos := new_foot_pos + new_foot_basis * leaf_offset
	var leaf_swing_basis := new_foot_basis * leaf_relative
	var leaf_rest_pos := new_foot_pos + new_foot_basis * (_owner._leaf_rest_offset[side] as Vector3)
	var leaf_rest_basis := new_foot_basis * (_owner._leaf_rest_relative_basis[side] as Basis)
	var leaf_basis := Basis(leaf_swing_basis.get_rotation_quaternion().slerp(
			leaf_rest_basis.get_rotation_quaternion(), weight))
	skel.set_bone_global_pose(leaf_idx, Transform3D(to_local.basis * leaf_basis,
			to_local * leaf_swing_pos.lerp(leaf_rest_pos, weight)))
