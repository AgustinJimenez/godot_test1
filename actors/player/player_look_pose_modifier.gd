class_name PlayerLookPoseModifier
extends SkeletonModifier3D
## Temporary post-animation look pose. SkeletonModifier3D restores the
## animation pose after each skeleton update, so these rotations cannot feed
## back into the next frame and accumulate indefinitely.

const TORSO_BEND: Dictionary = {
	&"Spine": 0.04,
	&"Spine1": 0.05,
	&"Spine2": 0.06,
}
const TORSO_YAW: Dictionary = {
	&"Spine": 0.08,
	&"Spine1": 0.10,
	&"Spine2": 0.12,
}
const TORSO_LOCOMOTION_YAW: Dictionary = {
	&"Spine": 0.60,
	&"Spine1": 0.80,
	&"Spine2": 1.00,
}
const HEAD_BEND: Dictionary = {
	&"Neck": 0.35,
	&"Head": 0.65,
}
const CACHED_BONES: PackedStringArray = [
	"Hips", "Spine", "Spine1", "Spine2", "Neck", "Head",
	"LeftShoulder", "LeftArm", "LeftForeArm", "LeftHand",
	"RightShoulder", "RightArm", "RightForeArm", "RightHand",
]
var player_body: PlayerBody
var adjusted_global_poses: Dictionary = {}


func _process_modification_with_delta(_delta: float) -> void:
	var skel := get_skeleton()
	if skel == null or player_body == null:
		return
	var pitch := player_body.clamp_head_pitch(player_body.head_pitch)
	var yaw := player_body.head_yaw
	var loco_yaw := player_body.locomotion_torso_yaw
	var combined := Vector2(yaw, pitch)
	var max_combined := deg_to_rad(player_body.MAX_BEND_UP_DEG)
	if combined.length() > max_combined:
		combined = combined.normalized() * max_combined
		yaw = combined.x
	if pitch < 0.0 or not is_zero_approx(yaw) or not is_zero_approx(loco_yaw):
		_bend_torso(skel, pitch, yaw, loco_yaw)
	if not is_zero_approx(pitch) or not is_zero_approx(yaw):
		_bend_head(skel, pitch, yaw)
	_apply_stair_balance(skel)
	_cache_adjusted_poses(skel)


func _apply_stair_balance(skel: Skeleton3D) -> void:
	if is_zero_approx(player_body.stair_balance_offset):
		return
	var spine_idx := skel.find_bone(player_body.resolve_bone_name(&"Spine"))
	if spine_idx < 0:
		return
	var pose := skel.get_bone_global_pose(spine_idx)
	pose.origin.y += player_body.stair_balance_offset
	skel.set_bone_global_pose(spine_idx, pose)


func _bend_torso(skel: Skeleton3D, pitch: float, yaw: float, loco_yaw: float = 0.0) -> void:
	# All weights are absolute offsets from the same animation pose. Taking
	# this snapshot first prevents a child from adding its correction on top
	# of an already-corrected parent pose.
	var animation_poses: Dictionary = {}
	for role: StringName in TORSO_LOCOMOTION_YAW:
		var bone_name := player_body.resolve_bone_name(role)
		var idx := skel.find_bone(bone_name)
		if idx >= 0:
			animation_poses[role] = skel.get_bone_global_pose(idx)
	for role: StringName in animation_poses:
		var bone_name := player_body.resolve_bone_name(role)
		var idx := skel.find_bone(bone_name)
		var pose: Transform3D = animation_poses[role]
		var pitch_factor: float = TORSO_BEND.get(role, 0.0) if pitch < 0.0 else 0.0
		var yaw_factor: float = TORSO_YAW.get(role, 0.0)
		var loco_factor: float = TORSO_LOCOMOTION_YAW.get(role, 0.0)
		var total_yaw: float = yaw * yaw_factor + loco_yaw * loco_factor
		if is_zero_approx(total_yaw) and is_zero_approx(pitch * pitch_factor):
			continue
		var bend_basis := (Basis(Vector3.UP, total_yaw)
				* Basis(Vector3.RIGHT, -pitch * pitch_factor))
		pose.basis = bend_basis * pose.basis
		skel.set_bone_global_pose(idx, pose)


func _bend_head(skel: Skeleton3D, pitch: float, yaw: float) -> void:
	for role: StringName in HEAD_BEND:
		var bone_name := player_body.resolve_bone_name(role)
		var idx := skel.find_bone(bone_name)
		if idx < 0:
			continue
		var portion: float = HEAD_BEND[role]
		if is_zero_approx(pitch * portion) and is_zero_approx(yaw * portion):
			continue
		var pose := skel.get_bone_global_pose(idx)
		var bend_basis := (Basis(Vector3.UP, yaw * portion)
				* Basis(Vector3.RIGHT, -pitch * portion))
		pose.basis = bend_basis * pose.basis
		skel.set_bone_global_pose(idx, pose)


func _cache_adjusted_poses(skel: Skeleton3D) -> void:
	adjusted_global_poses.clear()
	for role: String in CACHED_BONES:
		var idx := skel.find_bone(player_body.resolve_bone_name(StringName(role)))
		if idx >= 0:
			adjusted_global_poses[idx] = skel.get_bone_global_pose(idx)


func get_adjusted_global_pose(bone_idx: int) -> Transform3D:
	if adjusted_global_poses.has(bone_idx):
		return adjusted_global_poses[bone_idx]
	var skel := get_skeleton()
	return skel.get_bone_global_pose(bone_idx) if skel != null else Transform3D()
