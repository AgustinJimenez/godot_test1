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
const HEAD_BEND: Dictionary = {
	&"Neck": 0.35,
	&"Head": 0.65,
}
const CACHED_BONES: PackedStringArray = [
	"Head", "Spine2", "LeftShoulder", "RightShoulder", "LeftArm", "RightArm",
]

var player_body: PlayerBody
var adjusted_global_poses: Dictionary = {}


func _process_modification() -> void:
	var skel := get_skeleton()
	if skel == null or player_body == null:
		return
	var pitch := player_body.clamp_head_pitch(player_body.head_pitch)
	var yaw := player_body.head_yaw
	var combined := Vector2(yaw, pitch)
	var max_combined := deg_to_rad(player_body.MAX_BEND_UP_DEG)
	if combined.length() > max_combined:
		combined = combined.normalized() * max_combined
		yaw = combined.x
		pitch = combined.y
	if pitch < 0.0:
		_bend_torso(skel, pitch)
	_bend_head(skel, pitch, yaw)
	_cache_adjusted_poses(skel)


func _bend_torso(skel: Skeleton3D, pitch: float) -> void:
	# All weights are absolute offsets from the same animation pose. Taking
	# this snapshot first prevents a child from adding its correction on top
	# of an already-corrected parent pose.
	var animation_poses: Dictionary = {}
	for bone_name: StringName in TORSO_BEND:
		var idx := skel.find_bone(bone_name)
		if idx >= 0:
			animation_poses[bone_name] = skel.get_bone_global_pose(idx)
	for bone_name: StringName in animation_poses:
		var idx := skel.find_bone(bone_name)
		var pose: Transform3D = animation_poses[bone_name]
		pose.basis = Basis(Vector3.RIGHT, -pitch * float(TORSO_BEND[bone_name])) * pose.basis
		skel.set_bone_global_pose(idx, pose)


func _bend_head(skel: Skeleton3D, pitch: float, yaw: float) -> void:
	for bone_name: StringName in HEAD_BEND:
		var idx := skel.find_bone(bone_name)
		if idx < 0:
			continue
		var portion: float = HEAD_BEND[bone_name]
		var pose := skel.get_bone_global_pose(idx)
		pose.basis = (Basis(Vector3.UP, yaw * portion)
				* Basis(Vector3.RIGHT, -pitch * portion) * pose.basis)
		skel.set_bone_global_pose(idx, pose)


func _cache_adjusted_poses(skel: Skeleton3D) -> void:
	adjusted_global_poses.clear()
	for bone_name: String in CACHED_BONES:
		var idx := skel.find_bone(StringName(bone_name))
		if idx >= 0:
			adjusted_global_poses[idx] = skel.get_bone_global_pose(idx)


func get_adjusted_global_pose(bone_idx: int) -> Transform3D:
	if adjusted_global_poses.has(bone_idx):
		return adjusted_global_poses[bone_idx]
	var skel := get_skeleton()
	return skel.get_bone_global_pose(bone_idx) if skel != null else Transform3D()
