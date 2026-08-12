extends RefCounted
## Closed-form output phase for one leg. Contact and gait policy remain owned
## by PlayerFootIKModifier; this class only converts a chosen target/weight
## into hierarchy-preserving hip, knee, foot, toe, and leaf bone poses.

var _owner
var _previous_corrections: Dictionary = {}
var _previous_correction_frames: Dictionary = {}

const MAX_CORRECTION_ANGULAR_SPEED := 120.0
const CROUCH_CORRECTION_ANGULAR_SPEED := 45.0


func _init(owner) -> void:
	_owner = owner


func reset_runtime_state() -> void:
	_previous_corrections.clear()
	_previous_correction_frames.clear()


func release(side: StringName) -> void:
	for joint: StringName in [&"hip", &"knee", &"foot"]:
		_previous_corrections.erase("%s:%s" % [side, joint])
		_previous_correction_frames.erase("%s:%s" % [side, joint])


func release_to_animation(skel: Skeleton3D, side: StringName, delta: float) -> void:
	if not _previous_corrections.has("%s:hip" % side):
		return
	var poses: Dictionary = _owner._leg_fresh_pose_cache[side]
	if _owner._animation_discontinuous and _owner._prev_leg_bone_poses.has(side):
		poses = _owner._prev_leg_bone_poses[side]
	var hip_delta := _limit_correction(side, &"hip", Quaternion.IDENTITY, delta)
	var knee_delta := _limit_correction(side, &"knee", Quaternion.IDENTITY, delta)
	var foot_delta := _limit_correction(side, &"foot", Quaternion.IDENTITY, delta)
	if (hip_delta.angle_to(Quaternion.IDENTITY) < 0.0001
			and knee_delta.angle_to(Quaternion.IDENTITY) < 0.0001
			and foot_delta.angle_to(Quaternion.IDENTITY) < 0.0001):
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


func solve(skel: Skeleton3D, side: StringName, hip_pos: Vector3, target: Vector3,
		upper_length: float, lower_length: float, ground_weight: float, delta: float) -> void:
	var indices: Dictionary = _owner._bone_indices[side]
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
	var current_frame := Engine.get_physics_frames()
	var fresh_poses: Dictionary = _owner._leg_fresh_pose_cache[side]
	var poses: Dictionary = fresh_poses
	if _owner._animation_discontinuous and _owner._prev_leg_bone_poses.has(side):
		poses = _owner._prev_leg_bone_poses[side]
	# Only the first call for a given physics frame gets to update the
	# held reference used across a later discontinuous frame.
	if _owner._prev_leg_bone_poses_frame.get(side, -1) != current_frame:
		_owner._prev_leg_bone_poses[side] = fresh_poses
		_owner._prev_leg_bone_poses_frame[side] = current_frame
	var hip_pose: Transform3D = poses["hip"]
	var knee_pose: Transform3D = poses["knee"]
	var foot_pose: Transform3D = poses["foot"]
	var toe_pose: Transform3D = poses["toe"]
	var leaf_pose: Transform3D = poses["leaf"]
	var solve_weight := clampf(ground_weight, 0.0, 1.0)
	var knee_pos: Vector3 = to_world * knee_pose.origin
	var foot_pos: Vector3 = to_world * foot_pose.origin
	var animated_hip_pos: Vector3 = to_world * hip_pose.origin
	# Weight zero is a pass-through only when no stair swing-lift changed the
	# target. The predictor deliberately raises a released foot before its
	# next tread, and that positional correction still needs the chain solve.
	if solve_weight <= 0.0001 and target.distance_squared_to(foot_pos) < 0.000001:
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
	var bend_direction := to_world.basis * (_owner._knee_pole_local[side] as Vector3)
	bend_direction -= target_dir * bend_direction.dot(target_dir)
	if bend_direction.length_squared() < 0.0001:
		bend_direction = Vector3.FORWARD - target_dir * target_dir.z
	bend_direction = bend_direction.normalized()
	var cos_hip_angle := clampf(
			(upper_length * upper_length + dist * dist - lower_length * lower_length)
			/ (2.0 * upper_length * dist), -1.0, 1.0)
	var new_hip_to_knee_dir := (target_dir * cos(acos(cos_hip_angle))
			+ bend_direction * sin(acos(cos_hip_angle))).normalized()
	# Anatomical hip swing limit: the thigh has never been constrained here,
	# so a target that ends up somewhere it shouldn't (a stale or wrong-tread
	# support target, a bad retraction) could rotate the whole leg sideways
	# or backward well past any real hip's range of motion. Clamp to a cone
	# around straight down - same trade-off the knee flexion clamp above
	# already accepts: the foot may fall short of target rather than force
	# an inhuman pose.
	var max_swing := deg_to_rad(_owner.max_hip_swing_degrees)
	var swing_from_down := Vector3.DOWN.angle_to(new_hip_to_knee_dir)
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
	var rotation_weight := solve_weight
	if _owner._landing_grace_time > 0.0:
		rotation_weight = solve_weight * solve_weight * solve_weight
	hip_delta = Quaternion.IDENTITY.slerp(hip_delta, rotation_weight)
	knee_delta = Quaternion.IDENTITY.slerp(knee_delta, rotation_weight)
	hip_delta = _limit_correction(side, &"hip", hip_delta, delta)
	knee_delta = _limit_correction(side, &"knee", knee_delta, delta)
	# Positions must come from the same weighted/rate-limited rotations that
	# will be rendered below. Previously they stayed at the full solve while
	# the bases were only partially corrected, so even a small IK weight could
	# put a crouch joint at 100% of the procedural target and visibly stretch
	# the skinned leg. Rotating the authored rigid segments preserves both bone
	# lengths and exact animation pass-through at zero weight.
	new_knee_pos = hip_pos + hip_delta * (knee_pos - animated_hip_pos)
	new_foot_pos = new_knee_pos + knee_delta * (foot_pos - knee_pos)
	var new_hip_basis_world := Basis(hip_delta) * (to_world.basis * hip_pose.basis)
	var new_knee_basis_world := Basis(knee_delta) * (to_world.basis * knee_pose.basis)
	var animated_foot_basis_world := to_world.basis * foot_pose.basis
	var ground_foot_basis_world: Basis = _owner._compute_new_foot_basis_world(
			skel, side, -(_owner._smoothed_normal[side] as Vector3), foot_pose)
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


func _limit_correction(side: StringName, joint: StringName,
		desired: Quaternion, delta: float) -> Quaternion:
	var key := "%s:%s" % [side, joint]
	var previous: Quaternion = _previous_corrections.get(key, Quaternion.IDENTITY)
	var current_frame := Engine.get_physics_frames()
	if int(_previous_correction_frames.get(key, -1)) == current_frame:
		return previous
	var is_crouch_animation := false
	if _owner.player_body != null and _owner.player_body.anim_player != null:
		var animation_name := String(_owner.player_body.anim_player.current_animation)
		is_crouch_animation = animation_name.begins_with("moves/unarmed_crouch")
	# Stair clearance needs the foot orientation to follow its tread target in
	# the current solve. Delaying that rotation causes the rendered toes/sole to
	# pass through the riser even when the leg target itself is valid.
	if joint == &"foot" and not is_crouch_animation:
		_previous_corrections[key] = desired
		_previous_correction_frames[key] = current_frame
		return desired
	var angle := previous.angle_to(desired)
	var angular_speed := MAX_CORRECTION_ANGULAR_SPEED
	# The compact crouch gait brings the leg chain close to its flexion limit,
	# where a small contact change can otherwise become a visible joint snap.
	# Keep the ordinary/stair solve responsive and use the tighter budget only
	# for crouch locomotion and its release into crouch idle.
	if is_crouch_animation:
		angular_speed = CROUCH_CORRECTION_ANGULAR_SPEED
	var maximum_step := deg_to_rad(angular_speed) * maxf(delta, 0.0)
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
