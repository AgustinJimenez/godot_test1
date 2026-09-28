extends RefCounted
## Everything readable about one leg's pose for the trace: per-joint local rotation (Euler, and the
## delta from rest), knee / hip / ankle angles, segment lengths vs rest, knee bend-plane offset,
## and the same angles for the pre-IK ANIMATED pose so the correction can be read as a difference.
## Sagittal / frontal angles are measured against the character's facing (`forward`) and world up:
## hip / shank flexion is + when the knee / ankle is FORWARD of the joint above it, abduction is +
## toward the character's right. All angles are degrees, lengths metres.

const ROLES := ["hip", "knee", "foot", "toe"]


static func describe(v2: FootIKV2Modifier, skel: Skeleton3D, side: StringName,
		forward: Vector3) -> Dictionary:
	var leg: Dictionary = v2._legs[side]
	var to_world := skel.global_transform
	var world := {}
	for role: String in ROLES:
		var bone := int(leg[role])
		if bone >= 0 and v2.final_pose.has(bone):
			world[role] = v2.final_pose[bone]
	var animated := {}
	var base: Dictionary = v2._base.get(side, {})
	for role: String in ["hip", "knee", "foot"]:
		if base.has(role):
			animated[role] = to_world * (base[role] as Transform3D)
	var right := forward.cross(Vector3.UP).normalized()
	var out := {
		"joints": _joints(v2, skel, leg, world),
		"final": _angles(world, forward, right),
		"animated": _angles(animated, forward, right),
		"segments": {
			"upper": _len(world, "hip", "knee"), "upper_rest": snappedf(float(leg["upper"]), 0.001),
			"lower": _len(world, "knee", "foot"), "lower_rest": snappedf(float(leg["lower"]), 0.001),
		},
	}
	# The IK's correction as a difference (final - animated), the number to read first.
	var delta := {}
	for key: String in (out["final"] as Dictionary):
		if (out["animated"] as Dictionary).has(key):
			delta[key] = snappedf(float(out["final"][key]) - float(out["animated"][key]), 0.01)
	out["ik_delta"] = delta
	return out


## Per joint: rotation relative to its parent (Euler XYZ) and how far that is from the rest pose.
static func _joints(v2: FootIKV2Modifier, skel: Skeleton3D, leg: Dictionary,
		world: Dictionary) -> Dictionary:
	var out := {}
	var parents := {"hip": v2._hips_bone, "knee": int(leg["hip"]), "foot": int(leg["knee"]),
			"toe": int(leg["foot"])}
	for role: String in ROLES:
		var bone := int(leg[role])
		var parent := int(parents[role])
		if not world.has(role) or bone < 0 or parent < 0 or not v2.final_pose.has(parent):
			continue
		var local: Basis = (v2.final_pose[parent] as Transform3D).basis.orthonormalized().inverse() \
				* (world[role] as Transform3D).basis.orthonormalized()
		var rest: Basis = skel.get_bone_rest(bone).basis.orthonormalized()
		var from_rest := rest.inverse() * local
		out[role] = {
			"local_euler_deg": _deg(local.get_euler()),
			"from_rest_euler_deg": _deg(from_rest.get_euler()),
			"from_rest_deg": snappedf(rad_to_deg(from_rest.get_rotation_quaternion().get_angle()), 0.01),
		}
	return out


static func _angles(pose: Dictionary, forward: Vector3, right: Vector3) -> Dictionary:
	var out := {}
	if not (pose.has("hip") and pose.has("knee") and pose.has("foot")):
		return out
	var hip: Vector3 = (pose["hip"] as Transform3D).origin
	var knee: Vector3 = (pose["knee"] as Transform3D).origin
	var foot: Vector3 = (pose["foot"] as Transform3D).origin
	var thigh := knee - hip
	var shank := foot - knee
	# interior angle at the knee (180 = straight leg); flexion is how far from straight it is
	var interior := rad_to_deg((-thigh).angle_to(shank))
	out["knee_interior_deg"] = snappedf(interior, 0.01)
	out["knee_flexion_deg"] = snappedf(180.0 - interior, 0.01)
	out["hip_flexion_deg"] = _swing(thigh, forward)
	out["hip_abduction_deg"] = _swing(thigh, right)
	out["shank_flexion_deg"] = _swing(shank, forward)
	out["shank_abduction_deg"] = _swing(shank, right)
	# how far the knee sits off the straight hip-foot line, and which way (forward / right)
	var line := (foot - hip)
	var off := thigh - line.normalized() * thigh.dot(line.normalized())
	out["knee_offset_m"] = snappedf(off.length(), 0.001)
	out["knee_offset_forward_m"] = snappedf(off.dot(forward), 0.001)
	out["knee_offset_right_m"] = snappedf(off.dot(right), 0.001)
	out["hip_to_foot_m"] = snappedf(line.length(), 0.001)
	if pose.has("toe"):
		var toe: Vector3 = (pose["toe"] as Transform3D).origin
		var sole := toe - foot
		# ankle: angle between the shank and the foot's own forward axis (90 = foot square to shank)
		out["ankle_interior_deg"] = snappedf(rad_to_deg((-shank).angle_to(sole)), 0.01)
		# foot pitch above the horizontal: + toes UP
		var pitch := asin(clampf(sole.normalized().y, -1.0, 1.0))
		out["foot_pitch_deg"] = snappedf(rad_to_deg(pitch), 0.01)
		var yaw := atan2(sole.dot(right), sole.dot(forward))
		out["foot_yaw_vs_facing_deg"] = snappedf(rad_to_deg(yaw), 0.01)
	return out


## Angle of `dir` from straight down, swung toward `axis` in the (axis, up) plane: + = toward axis.
static func _swing(dir: Vector3, axis: Vector3) -> float:
	return snappedf(rad_to_deg(atan2(dir.dot(axis), -dir.dot(Vector3.UP))), 0.01)


static func _len(world: Dictionary, a: String, b: String) -> float:
	if not (world.has(a) and world.has(b)):
		return -1.0
	var apart: Vector3 = (world[a] as Transform3D).origin - (world[b] as Transform3D).origin
	return snappedf(apart.length(), 0.001)


static func _deg(euler: Vector3) -> Array:
	return [snappedf(rad_to_deg(euler.x), 0.01), snappedf(rad_to_deg(euler.y), 0.01),
			snappedf(rad_to_deg(euler.z), 0.01)]
