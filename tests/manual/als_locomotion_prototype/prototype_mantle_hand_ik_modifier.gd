class_name PrototypeMantleHandIKModifier
extends SkeletonModifier3D
## Pins both hands to the ledge's real grip point during a mantle, fading in
## and out with the position-correction curve. NOT a port of any real ALS
## mechanism - ALS has no runtime hand IK during mantling; it relies entirely
## on the animator having hand-tuned the clip against one specific skeleton
## (the real UE Mannequin), which is exactly the assumption that breaks once
## the clip is retargeted onto a differently-proportioned character (measured
## directly: the retargeted clip's hands track the ledge edge acceptably for
## roughly half the climb, then drift). This closes that gap using a
## technique already established elsewhere in this project - two-bone IK via
## an analytic solver, the same one `HumanoidRetargeter` already uses for
## arm-matching at retarget time (`_solve_two_bone_ik`/`_swing_between`,
## reused here at runtime instead of duplicated) - rather than inventing
## anything new. Deliberately far simpler than `PlayerFootIKModifier`: this
## only needs to run for one bounded, one-shot event (a mantle), not
## continuous ground contact with all the gait/stair/landing state that
## implies.

const ARMS: Dictionary = {
	&"left": {"arm": &"LeftArm", "forearm": &"LeftForeArm", "hand": &"LeftHand"},
	&"right": {"arm": &"RightArm", "forearm": &"RightForeArm", "hand": &"RightHand"},
}

var player_body: PlayerBody
## World-space point both hands reach for - set to the mantle's real ledge
## grip point (the same point the position-correction curve targets).
var target_position := Vector3.ZERO
## 0 = fully animated (this modifier does nothing), 1 = hands fully pinned
## to target_position. Driven from the mantle's own correction alphas.
var weight := 0.0

var _bone_indices: Dictionary = {} # side -> {arm, forearm, hand: int}
var _lengths: Dictionary = {} # side -> {upper, lower: float}


func _ready() -> void:
	var skel := get_skeleton()
	if skel == null or player_body == null:
		return
	for side: StringName in ARMS:
		var roles: Dictionary = ARMS[side]
		var arm_idx := skel.find_bone(player_body.resolve_bone_name(roles["arm"]))
		var forearm_idx := skel.find_bone(player_body.resolve_bone_name(roles["forearm"]))
		var hand_idx := skel.find_bone(player_body.resolve_bone_name(roles["hand"]))
		if arm_idx < 0 or forearm_idx < 0 or hand_idx < 0:
			continue
		_bone_indices[side] = {"arm": arm_idx, "forearm": forearm_idx, "hand": hand_idx}
		var arm_rest: Vector3 = skel.get_bone_global_rest(arm_idx).origin
		var forearm_rest: Vector3 = skel.get_bone_global_rest(forearm_idx).origin
		var hand_rest: Vector3 = skel.get_bone_global_rest(hand_idx).origin
		_lengths[side] = {
			"upper": arm_rest.distance_to(forearm_rest),
			"lower": forearm_rest.distance_to(hand_rest),
		}


func _process_modification_with_delta(_delta: float) -> void:
	var skel := get_skeleton()
	if skel == null or weight <= 0.0:
		return
	# Skeleton-local space throughout (matches get/set_bone_*pose's own
	# space), converted once from the world-space target passed in.
	var target_local: Vector3 = skel.global_transform.affine_inverse() * target_position
	for side: StringName in _bone_indices:
		var idx: Dictionary = _bone_indices[side]
		var lengths: Dictionary = _lengths[side]
		var arm_pose := skel.get_bone_global_pose(idx["arm"])
		var forearm_pose := skel.get_bone_global_pose(idx["forearm"])
		var hand_pose := skel.get_bone_global_pose(idx["hand"])

		# REACHABILITY GATE - measured, not assumed: an early version pinned
		# straight to the ledge point regardless of how far the shoulder
		# still was from it, and `_solve_two_bone_ik`'s own reach clamp just
		# stretched the arm toward an unreachable target instead of actually
		# gripping - confirmed directly, the right hand's distance to target
		# got WORSE (up to 1.09m) than with no IK at all. Real climbing only
		# grips once the ledge is plausibly within arm's reach of the CURRENT
		# body position, which during a mantle is still rising - correct
		# behaviour is for the pin to fade in as reach becomes physically
		# possible, not follow the curve's timing alone.
		var max_reach: float = lengths["upper"] + lengths["lower"]
		var dist := arm_pose.origin.distance_to(target_local)
		var reach_factor := clampf(1.0 - (dist - max_reach) / (max_reach * 0.5), 0.0, 1.0)
		var effective_weight := weight * reach_factor
		if effective_weight <= 0.001:
			continue

		# Current animated elbow position doubles as the pole vector, keeping
		# the solved bend in the animation's own natural direction rather
		# than an arbitrary one.
		var solved: Dictionary = HumanoidRetargeter._solve_two_bone_ik(
				arm_pose.origin, lengths["upper"], lengths["lower"],
				target_local, forearm_pose.origin)
		_aim_bone(skel, idx["arm"], forearm_pose.origin, solved["elbow"], effective_weight)
		# The upper-arm rotation just written changes the forearm's cascaded
		# global pose - re-read it before aiming the forearm itself.
		forearm_pose = skel.get_bone_global_pose(idx["forearm"])
		_aim_bone(skel, idx["forearm"], hand_pose.origin, solved["wrist"], effective_weight)


## Rotates bone_idx (blending toward `weight`) so the vector from its own
## origin to current_child_pos swings toward desired_child_pos instead -
## the same swing-then-reparent-to-local technique
## HumanoidRetargeter._aim_bone_at_direction uses at retarget time, applied
## here at runtime via get/set_bone_pose_rotation instead of writing
## Animation keys.
func _aim_bone(skel: Skeleton3D, bone_idx: int,
		current_child_pos: Vector3, desired_child_pos: Vector3, blend: float) -> void:
	var bone_pose := skel.get_bone_global_pose(bone_idx)
	var parent_idx := skel.get_bone_parent(bone_idx)
	var parent_basis := (
			skel.get_bone_global_pose(parent_idx).basis if parent_idx >= 0 else Basis())
	var current_dir := (current_child_pos - bone_pose.origin).normalized()
	var desired_dir := (desired_child_pos - bone_pose.origin).normalized()
	var swing := HumanoidRetargeter._swing_between(current_dir, desired_dir)
	var desired_global_basis := swing * bone_pose.basis
	var target_local_rot := (
			parent_basis.inverse() * desired_global_basis).get_rotation_quaternion()
	var current_local_rot := skel.get_bone_pose_rotation(bone_idx)
	skel.set_bone_pose_rotation(bone_idx, current_local_rot.slerp(target_local_rot, blend))
