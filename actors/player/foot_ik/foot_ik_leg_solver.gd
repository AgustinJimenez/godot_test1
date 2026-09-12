extends RefCounted
## Closed-form output phase for one leg. Contact and gait policy remain owned
## by PlayerFootIKModifier; this class only converts a chosen target/weight
## into hierarchy-preserving hip, knee, foot, toe, and leaf bone poses.

const EVALUATOR := preload("res://actors/player/foot_ik/foot_ik_leg_pose_evaluator.gd")
var _state_revision := 0

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
	_state_revision += 1
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
	_state_revision += 1
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


func _thigh_direction(target_dir: Vector3, bend: Vector3, hip_angle: float) -> Vector3:
	return (target_dir * cos(hip_angle) + bend * sin(hip_angle)).normalized()


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


var _perf_log_enabled := OS.get_environment("FOOT_IK_PERF_LOG") == "1"
var _perf_accum_usec := 0
var _perf_call_count := 0
var _perf_window_start_frame := 0
# Worst single solve() call this window (018 finding H: an average hides a rare expensive
# frame - a 145-candidate bend search or a compressed-upper reach search can spike one call
# far above the mean without moving the average enough to notice).
var _perf_worst_call_usec := 0
var _perf_current_frame := -1
var _perf_current_frame_usec := 0
var _perf_worst_window_frame_usec := 0


func solve(skel: Skeleton3D, side: StringName, hip_pos: Vector3, target: Vector3,
		upper_length: float, lower_length: float, ground_weight: float,
		chain_weight: float, delta: float, options: Dictionary = {}) -> void:
	if not _perf_log_enabled:
		_solve_impl(skel, side, hip_pos, target, upper_length, lower_length,
				ground_weight, chain_weight, delta, options)
		return
	var start_usec := Time.get_ticks_usec()
	_solve_impl(skel, side, hip_pos, target, upper_length, lower_length,
			ground_weight, chain_weight, delta, options)
	var call_usec := Time.get_ticks_usec() - start_usec
	_perf_accum_usec += call_usec
	_perf_call_count += 1
	_perf_worst_call_usec = maxi(_perf_worst_call_usec, call_usec)
	var frame := Engine.get_physics_frames()
	if frame != _perf_current_frame:
		_perf_worst_window_frame_usec = maxi(
				_perf_worst_window_frame_usec, _perf_current_frame_usec)
		_perf_current_frame = frame
		_perf_current_frame_usec = 0
	_perf_current_frame_usec += call_usec
	if frame - _perf_window_start_frame < 60:
		return
	# Flush the in-progress frame's total too - otherwise the very last frame of the window
	# never gets compared, since no "next frame started" event happens before this print.
	_perf_worst_window_frame_usec = maxi(_perf_worst_window_frame_usec, _perf_current_frame_usec)
	print(("[FOOT_IK_PERF] frame=%d fps=%.1f solve_calls=%d avg_solve_usec=%.1f " +
			"worst_call_usec=%d worst_frame_total_usec=%d total_solve_ms=%.2f") % [
			frame, Engine.get_frames_per_second(), _perf_call_count,
			float(_perf_accum_usec) / maxi(_perf_call_count, 1),
			_perf_worst_call_usec, _perf_worst_window_frame_usec, _perf_accum_usec / 1000.0])
	_perf_accum_usec = 0
	_perf_call_count = 0
	_perf_worst_call_usec = 0
	_perf_worst_window_frame_usec = 0
	_perf_window_start_frame = frame


func _apply_leg_pose(skel: Skeleton3D, to_local: Transform3D, result: FootIKLegPoseResult) -> void:
	skel.set_bone_global_pose(result.hip_idx,
			Transform3D(to_local.basis * result.hip_basis, to_local * result.hip_pos))
	skel.set_bone_global_pose(result.knee_idx,
			Transform3D(to_local.basis * result.knee_basis, to_local * result.knee_pos))
	skel.set_bone_global_pose(result.foot_idx,
			Transform3D(to_local.basis * result.foot_basis, to_local * result.foot_pos))
	if result.has_toe:
		skel.set_bone_global_pose(result.toe_idx,
				Transform3D(to_local.basis * result.toe_basis, to_local * result.toe_pos))
	if result.has_leaf:
		skel.set_bone_global_pose(result.leaf_idx,
				Transform3D(to_local.basis * result.leaf_basis, to_local * result.leaf_pos))



## Capture once, then evaluate any number of targets against these same inputs/history.
func capture_input(skel: Skeleton3D, side: StringName,
		release_only: bool = false) -> FootIKLegSolveInput:
	var input := FootIKLegSolveInput.capture(_owner, side, skel, release_only)
	input.history = FootIKLegSolveState.capture(self)
	input.source_revision = _state_revision
	input.source_solver_id = get_instance_id()
	return input


func evaluate_candidate(input: FootIKLegSolveInput, hip_pos: Vector3, target: Vector3,
		upper_length: float, lower_length: float, ground_weight: float,
		chain_weight: float, delta: float, options: Dictionary = {}) -> FootIKLegPoseResult:
	return EVALUATOR.new(input).evaluate_pose(input.side, hip_pos, target,
			upper_length, lower_length, ground_weight, chain_weight, delta, options)


## Accept only once against the originating solver/tick/skeleton. A rejected or stale
## candidate never publishes diagnostics/history or writes bones.
func commit_candidate(skel: Skeleton3D, result: FootIKLegPoseResult) -> bool:
	if (result.source_solver_id != get_instance_id()
			or result.source_revision != _state_revision
			or result.physics_frame != Engine.get_physics_frames()
			or result.skeleton_id != skel.get_instance_id()
			or result.to_world != skel.global_transform or result.next_state == null):
		return false
	if result.has_pose:
		_apply_leg_pose(skel, result.to_world.affine_inverse(), result)
	_commit_state(result.next_state)
	return true


func _commit_state(state: FootIKLegSolveState) -> void:
	state.publish_to(self)
	_state_revision += 1


func _solve_impl(skel: Skeleton3D, side: StringName, hip_pos: Vector3, target: Vector3,
		upper_length: float, lower_length: float, ground_weight: float,
		chain_weight: float, delta: float, options: Dictionary = {}) -> void:
	var input := capture_input(skel, side)
	var result := evaluate_candidate(input, hip_pos, target, upper_length, lower_length,
			ground_weight, chain_weight, delta, options)
	commit_candidate(skel, result)


func release_to_animation(skel: Skeleton3D, side: StringName, delta: float) -> void:
	var input := capture_input(skel, side, true)
	commit_candidate(skel, EVALUATOR.new(input).release_pose(side, delta))


# Compatibility adapters for existing target-policy queries and acceptance probes.
# Candidate evaluation calls the evaluator's helpers directly, never these publishing adapters.
func _solve_bend_direction(side: StringName, target_dir: Vector3,
		hip_angle: float, to_world: Transform3D,
		distance: float = 0.0, upper_length: float = 0.0,
		preferred_bend_world: Vector3 = Vector3.ZERO, delta: float = 0.0) -> Vector3:
	var evaluator := EVALUATOR.new(capture_input(null, side))
	var bend := evaluator._solve_bend_direction(side, target_dir, hip_angle, to_world,
			distance, upper_length, preferred_bend_world, delta)
	_commit_state(evaluator.state)
	return bend


func _limit_negative_rendered_knee(side: StringName, hip_pos: Vector3,
		animated_hip_pos: Vector3, animated_knee_pos: Vector3,
		animated_foot_pos: Vector3, rendered_knee_pos: Vector3,
		rendered_foot_pos: Vector3) -> Dictionary:
	var evaluator := EVALUATOR.new(capture_input(null, side))
	var result := evaluator._limit_negative_rendered_knee(side, hip_pos, animated_hip_pos,
			animated_knee_pos, animated_foot_pos, rendered_knee_pos, rendered_foot_pos)
	_commit_state(evaluator.state)
	return result


func _limit_idle_stance_crossing(side: StringName, to_world: Transform3D,
		hip_pos: Vector3, animated_hip_pos: Vector3, knee_pos: Vector3,
		foot_pos: Vector3, hip_delta: Quaternion, knee_delta: Quaternion,
		new_foot_pos: Vector3) -> Dictionary:
	var evaluator := EVALUATOR.new(capture_input(null, side))
	var result := evaluator._limit_idle_stance_crossing(side, to_world, hip_pos,
			animated_hip_pos, knee_pos, foot_pos, hip_delta, knee_delta, new_foot_pos)
	_commit_state(evaluator.state)
	return result
