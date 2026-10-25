class_name HandPresets
## GVHMR leaves all finger joints still. This writes a constant hand pose into a retargeted clip's finger tracks:
## "relaxed" (a loose half curl) or "fist". Rig-agnostic: for each finger bone it tries a turn about each local axis and keeps
## the direction that brings the fingertip nearest to the wrist (a curl), so it needs no knowledge of the rig's bone axes.

## degrees per joint: [first, middle, last] of the four fingers, and of the thumb
const PRESETS := {
	"relaxed": {"fingers": [18.0, 28.0, 20.0], "thumb": [8.0, 12.0, 8.0]},
	"fist": {"fingers": [75.0, 95.0, 65.0], "thumb": [25.0, 35.0, 25.0]},
}
const FINGERS := ["Index", "Middle", "Ring", "Pinky"]


static func apply(animation: Animation, skeleton: Skeleton3D, humanoid_map: Dictionary, preset: String) -> int:
	if not PRESETS.has(preset):
		return 0
	var written := 0
	for side: String in ["Left", "Right"]:
		var hand := skeleton.find_bone(StringName(humanoid_map.get(side + "Hand", "")))
		if hand < 0:
			continue
		for finger: String in FINGERS + ["Thumb"]:
			var angles: Array = PRESETS[preset]["thumb" if finger == "Thumb" else "fingers"]
			var chain: Array[int] = []
			for joint in range(1, 5):
				var bone := skeleton.find_bone(StringName(humanoid_map.get("%sHand%s%d" % [side, finger, joint], "")))
				if bone >= 0:
					chain.append(bone)
			if chain.size() < 2:
				continue
			var tip := chain[chain.size() - 1]
			for index in mini(3, chain.size() - (1 if chain.size() == 4 else 0)):
				var bone: int = chain[index]
				var turn := _curl_turn(skeleton, bone, tip, hand, deg_to_rad(angles[index]))
				var rest_rotation := skeleton.get_bone_rest(bone).basis.get_rotation_quaternion()
				_set_constant(animation, skeleton, bone, rest_rotation * turn)
				written += 1
	return written


## The local-axis rotation of `bone` (of the given angle) that moves `tip` closest to `hand`.
static func _curl_turn(skeleton: Skeleton3D, bone: int, tip: int, hand: int, angle: float) -> Quaternion:
	var best := Quaternion.IDENTITY
	var best_distance := _distance(skeleton, bone, tip, hand, Quaternion.IDENTITY)
	for axis in [Vector3.RIGHT, Vector3.UP, Vector3.BACK]:
		for sign in [1.0, -1.0]:
			var candidate := Quaternion(axis, angle * sign)
			var distance := _distance(skeleton, bone, tip, hand, candidate)
			if distance < best_distance - 0.0005:
				best_distance = distance
				best = candidate
	return best


static func _distance(skeleton: Skeleton3D, bone: int, tip: int, hand: int, turn: Quaternion) -> float:
	var saved := skeleton.get_bone_pose_rotation(bone)
	skeleton.set_bone_pose_rotation(bone, skeleton.get_bone_rest(bone).basis.get_rotation_quaternion() * turn)
	var tip_position := _global(skeleton, tip).origin
	var hand_position := _global(skeleton, hand).origin
	skeleton.set_bone_pose_rotation(bone, saved)
	return tip_position.distance_to(hand_position)


static func _global(skeleton: Skeleton3D, index: int) -> Transform3D:
	var result := skeleton.get_bone_pose(index)
	var parent := skeleton.get_bone_parent(index)
	while parent >= 0:
		result = skeleton.get_bone_pose(parent) * result
		parent = skeleton.get_bone_parent(parent)
	return result


static func _set_constant(animation: Animation, skeleton: Skeleton3D, bone: int, rotation: Quaternion) -> void:
	var path := NodePath(String(skeleton.name) + ":" + String(skeleton.get_bone_name(bone)))
	var track := animation.find_track(path, Animation.TYPE_ROTATION_3D)
	if track < 0:
		track = animation.add_track(Animation.TYPE_ROTATION_3D)
		animation.track_set_path(track, path)
	else:
		for key in range(animation.track_get_key_count(track) - 1, -1, -1):
			animation.track_remove_key(track, key)
	animation.rotation_track_insert_key(track, 0.0, rotation)
	animation.rotation_track_insert_key(track, animation.length, rotation)
