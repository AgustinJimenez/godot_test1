extends RefCounted
## Closed-form output phase for one leg. Contact and gait policy remain owned
## by PlayerFootIKModifier; this class only converts a chosen target/weight
## into hierarchy-preserving hip, knee, foot, toe, and leaf bone poses.

var _owner


func _init(owner) -> void:
	_owner = owner


func solve(skel: Skeleton3D, side: StringName, hip_pos: Vector3, target: Vector3,
		upper_length: float, lower_length: float, ground_weight: float) -> void:
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
	var knee_pos: Vector3 = to_world * knee_pose.origin
	var foot_pos: Vector3 = to_world * foot_pose.origin
	var animated_hip_pos: Vector3 = to_world * hip_pose.origin
	var to_target := target - hip_pos
	if to_target.is_zero_approx():
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
	var new_hip_basis_world := Basis(hip_delta) * (to_world.basis * hip_pose.basis)
	var new_knee_basis_world := Basis(knee_delta) * (to_world.basis * knee_pose.basis)
	var animated_foot_basis_world := to_world.basis * foot_pose.basis
	var ground_foot_basis_world: Basis = _owner._compute_new_foot_basis_world(
			skel, side, -(_owner._smoothed_normal[side] as Vector3), foot_pose)
	var new_foot_basis_world := Basis(animated_foot_basis_world.get_rotation_quaternion().slerp(
			ground_foot_basis_world.get_rotation_quaternion(), ground_weight))
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
			"leaf_pose": leaf_pose, "weight": ground_weight,
		})


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
