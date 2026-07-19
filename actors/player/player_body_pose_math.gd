class_name PlayerBodyPoseMath
extends RefCounted

## Pure skeleton/pose math extracted from player_body.gd purely to keep that
## gameplay-critical file under a manageable size - every function here only
## reads its parameters, no PlayerBody state. Moved verbatim, not rewritten.
##
## tools/character_editor/humanoid_retargeter.gd has its own separate copies
## of several of these same functions, duplicated on purpose (see that
## file's own doc comment) so nothing here can ever regress the already-
## hardened, gameplay-critical player rig - do not merge the two back
## together, and do not have humanoid_retargeter.gd call into this file.


static func solve_fabrik(joints: Array[Vector3], lengths: Array[float], target: Vector3) -> void:
	var root := joints[0]
	var total_length := lengths[0] + lengths[1] + lengths[2]
	if root.distance_to(target) >= total_length:
		var direction := (target - root).normalized()
		for i in lengths.size():
			joints[i + 1] = joints[i] + direction * lengths[i]
		return
	for iteration in 12:
		joints[3] = target
		for i in range(2, -1, -1):
			joints[i] = joints[i + 1] + (joints[i] - joints[i + 1]).normalized() * lengths[i]
		joints[0] = root
		for i in lengths.size():
			joints[i + 1] = joints[i] + (joints[i + 1] - joints[i]).normalized() * lengths[i]
		if joints[3].distance_to(target) < 0.00001:
			break


static func set_latest_rotation_key(anim: Animation, out_rot_track: Dictionary,
		bone_name: StringName, rotation: Quaternion) -> void:
	if not out_rot_track.has(bone_name):
		return
	var track: int = out_rot_track[bone_name]
	anim.track_set_key_value(track, anim.track_get_key_count(track) - 1, rotation)


static func skeleton_height(skel: Skeleton3D, hips_name: StringName,
		head_name: StringName) -> float:
	var hips := skel.get_bone_global_rest(skel.find_bone(hips_name)).origin
	var head := skel.get_bone_global_rest(skel.find_bone(head_name)).origin
	return hips.distance_to(head)


static func skeleton_rest_facing(skel: Skeleton3D, hips_name: StringName,
		head_name: StringName, left_shoulder_name: StringName,
		right_shoulder_name: StringName) -> Vector3:
	var hips := skel.get_bone_global_rest(skel.find_bone(hips_name)).origin
	var head := skel.get_bone_global_rest(skel.find_bone(head_name)).origin
	var left := skel.get_bone_global_rest(skel.find_bone(left_shoulder_name)).origin
	var right := skel.get_bone_global_rest(skel.find_bone(right_shoulder_name)).origin
	var across := (right - left).normalized()
	var up := (head - hips).normalized()
	var facing := across.cross(up)
	facing.y = 0.0
	return facing.normalized()


## Composes a bone's GLOBAL pose from the LOCAL pose getters directly,
## walking the parent chain by hand - Skeleton3D.get_bone_global_pose()
## reads from a cache that's only refreshed on the engine's own per-frame
## update, which never happens while baking offline inside _ready() (no
## amount of set_bone_pose_rotation/position calls made it budge, even with
## force_update_all_bone_transforms()). get_bone_pose() is a plain getter
## with no such caching, so composing the chain from that manually is what
## actually reflects poses just set this same sample.
static func manual_global_pose(skel: Skeleton3D, idx: int) -> Transform3D:
	var t := skel.get_bone_pose(idx)
	var parent := skel.get_bone_parent(idx)
	while parent >= 0:
		t = skel.get_bone_pose(parent) * t
		parent = skel.get_bone_parent(parent)
	return t


## Shortest-arc rotation that takes `from` to `to` (both must be normalized).
static func swing_between(from: Vector3, to: Vector3) -> Basis:
	var axis := from.cross(to)
	var len := axis.length()
	if len < 0.0001:
		if from.dot(to) > 0.0:
			return Basis.IDENTITY
		var perp := from.cross(Vector3.UP)
		if perp.length() < 0.0001:
			perp = from.cross(Vector3.RIGHT)
		return Basis(perp.normalized(), PI)
	return Basis(axis / len, from.angle_to(to))


## Adds a rotation track for held_bone holding a single fixed pose (its
## value from held_pose's first keyframe) for the whole clip duration.
static func bake_held_track(
		anim: Animation, held_bone: StringName, held_pose: Animation, length: float) -> void:
	for t in held_pose.get_track_count():
		var path := held_pose.track_get_path(t)
		if (path.get_subname_count() > 0 and StringName(path.get_subname(0)) == held_bone
				and held_pose.track_get_type(t) == Animation.TYPE_ROTATION_3D):
			var value = held_pose.track_get_key_value(t, 0)
			var new_track := anim.add_track(Animation.TYPE_ROTATION_3D)
			anim.track_set_path(new_track, NodePath("Skeleton3D:" + String(held_bone)))
			anim.track_insert_key(new_track, 0.0, value)
			anim.track_insert_key(new_track, length, value)
			return
