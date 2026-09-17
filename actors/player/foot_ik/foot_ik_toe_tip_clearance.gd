class_name FootIKToeTipClearance
extends RefCounted
## Narrow, gentle toe-tip clearance for the flat-IK skip path.
##
## The flat-ground fast path (`PlayerFootIKModifier._can_skip_flat_ik`) publishes the authored
## animation unchanged. During toe-off on a flat platform the author's foot tips slightly into the
## surface, and nothing in the skipped path looks at the toe tip (the sole/ankle read clean). This
## rotates the foot bone around its own ankle just enough that the tip clears - one continuous
## pitch, no target/solve, so it cannot snap. See AGENT_TASKS/025.

const CLEARANCE_MARGIN_M := 0.012
const MAX_PITCH_DEG := 35.0
const SURFACE_UP_DOT := 0.999


static func apply_all(skel: Skeleton3D, space: PhysicsDirectSpaceState3D,
		bone_indices: Dictionary, toe_tip_margin: float, ground_sampler) -> void:
	for side: StringName in bone_indices:
		apply(skel, space, bone_indices[side], toe_tip_margin, ground_sampler)


## Returns true when the authored foot was pitched to lift its toe tip out of the surface.
static func apply(skel: Skeleton3D, space: PhysicsDirectSpaceState3D, indices: Dictionary,
		toe_tip_margin: float, ground_sampler) -> bool:
	var foot_idx: int = int(indices.get("foot", -1))
	var toe_idx: int = int(indices.get("toe", -1))
	if foot_idx < 0 or toe_idx < 0:
		return false
	var foot_pose := skel.get_bone_global_pose(foot_idx)
	var ankle: Vector3 = foot_pose.origin
	var reach: Vector3 = skel.get_bone_global_pose(toe_idx).origin - ankle
	if reach.length_squared() <= 0.000001 or toe_tip_margin <= 0.0:
		return false
	var tip: Vector3 = ankle + reach + reach.normalized() * toe_tip_margin
	var hit: Dictionary = ground_sampler.raycast_ground(
			space, skel.global_transform * tip + Vector3.UP * 0.2, 0.4)
	if not hit["hit"] or (hit["normal"] as Vector3).dot(Vector3.UP) < SURFACE_UP_DOT:
		return false
	var surface: Vector3 = skel.global_transform.affine_inverse() * (hit["position"] as Vector3)
	var tip_vec: Vector3 = tip - ankle
	var length := tip_vec.length()
	if length <= 0.000001:
		return false
	var limit := length * 0.98
	var desired_y := clampf(surface.y + CLEARANCE_MARGIN_M - ankle.y, -limit, limit)
	var current_y := clampf(tip_vec.y, -limit, limit)
	if desired_y <= current_y:
		return false
	var horizontal := Vector3(tip_vec.x, 0.0, tip_vec.z)
	if horizontal.length_squared() <= 0.000001:
		return false
	var axis := horizontal.normalized().cross(Vector3.UP).normalized()
	var angle := clampf(asin(desired_y / length) - asin(current_y / length),
			-deg_to_rad(MAX_PITCH_DEG), deg_to_rad(MAX_PITCH_DEG))
	if absf(angle) <= 0.000001:
		return false
	skel.set_bone_global_pose(foot_idx, Transform3D(Basis(axis, angle) * foot_pose.basis, ankle))
	return true
