class_name FootIkJointLimitCheck
extends RefCounted
## Shared post-modifier anatomical safety check. Scenario-specific harnesses
## may impose stricter preferred pose limits, but no solved leg may exceed the
## IK modifier's configured hard knee-flexion or hip-swing limits.

const ANGLE_TOLERANCE_DEGREES := 1.0


static func failures(ik: PlayerFootIKModifier, skeleton: Skeleton3D,
		label: String) -> Array[String]:
	var result: Array[String] = []
	if ik == null or skeleton == null or ik._bone_indices.is_empty():
		return result
	var to_world := skeleton.global_transform
	for side: StringName in [&"left", &"right"]:
		if not ik._bone_indices.has(side):
			continue
		if not _has_active_leg_correction(ik, side):
			continue
		var indices: Dictionary = ik._bone_indices[side]
		var hip: Vector3 = to_world * _pose(ik, skeleton, int(indices[&"hip"])).origin
		var knee: Vector3 = to_world * _pose(ik, skeleton, int(indices[&"knee"])).origin
		var foot: Vector3 = to_world * _pose(ik, skeleton, int(indices[&"foot"])).origin
		var thigh := knee - hip
		var shin := foot - knee
		if thigh.length_squared() <= 0.000001 or shin.length_squared() <= 0.000001:
			result.append("%s %s leg collapsed to zero length" % [label, side])
			continue
		var flexion := 180.0 - rad_to_deg((-thigh).angle_to(shin))
		var hip_swing := rad_to_deg(Vector3.DOWN.angle_to(thigh.normalized()))
		if flexion > ik.max_knee_flexion_degrees + ANGLE_TOLERANCE_DEGREES:
			result.append("%s %s knee flexion %.2f exceeds %.2f degrees" % [
					label, side, flexion, ik.max_knee_flexion_degrees])
		var max_hip_swing: float = ik._leg_solver.max_hip_swing_degrees(side)
		if hip_swing > max_hip_swing + ANGLE_TOLERANCE_DEGREES:
			result.append("%s %s hip swing %.2f exceeds %.2f degrees" % [
					label, side, hip_swing, max_hip_swing])
		var animation_name := String(ik.player_body.anim_player.current_animation.get_file())
		var normal: Vector3 = ik._smoothed_normal.get(side, Vector3.UP)
		if (not animation_name.contains("crouch") and not animation_name.contains("jump")
				and (animation_name.contains("idle") or animation_name.contains("walk"))
				and normal.dot(Vector3.UP) >= 0.999):
			var shin_swing := rad_to_deg(Vector3.DOWN.angle_to(shin.normalized()))
			if (shin_swing > ik._leg_solver.MAX_UPRIGHT_SHIN_SWING_DEGREES
					+ ANGLE_TOLERANCE_DEGREES):
				result.append("%s %s shin swing %.2f exceeds %.2f degrees" % [label, side,
						shin_swing, ik._leg_solver.MAX_UPRIGHT_SHIN_SWING_DEGREES])
	return result


static func _has_active_leg_correction(ik: PlayerFootIKModifier, side: StringName) -> bool:
	for joint: StringName in [&"hip", &"knee"]:
		var key := "%s:%s" % [side, joint]
		var correction: Quaternion = ik._leg_solver._previous_corrections.get(
				key, Quaternion.IDENTITY)
		if rad_to_deg(correction.angle_to(Quaternion.IDENTITY)) > 0.5:
			return true
	return false


static func _pose(ik: PlayerFootIKModifier, skeleton: Skeleton3D,
		bone_index: int) -> Transform3D:
	return ik._final_bone_poses.get(
			bone_index, skeleton.get_bone_global_pose(bone_index))
