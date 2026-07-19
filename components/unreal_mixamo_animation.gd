class_name UnrealMixamoAnimation
extends RefCounted

## Bakes an Unreal Mannequin animation onto a Mixamo-family character.
## The output is an ordinary Animation resource, so gameplay can add it to
## the target character's AnimationPlayer without retaining the source rig.

const _CORE_BONES: Dictionary = {
	&"pelvis": "Hips",
	&"spine_01": "Spine",
	&"spine_02": "Spine1",
	&"spine_03": "Spine2",
	&"neck_01": "Neck",
	&"Head": "Head",
	&"clavicle_r": "RightShoulder",
	&"upperarm_r": "RightArm",
	&"lowerarm_r": "RightForeArm",
	&"hand_r": "RightHand",
	&"clavicle_l": "LeftShoulder",
	&"upperarm_l": "LeftArm",
	&"lowerarm_l": "LeftForeArm",
	&"hand_l": "LeftHand",
	&"thigh_r": "RightUpLeg",
	&"calf_r": "RightLeg",
	&"foot_r": "RightFoot",
	&"ball_r": "RightToeBase",
	&"thigh_l": "LeftUpLeg",
	&"calf_l": "LeftLeg",
	&"foot_l": "LeftFoot",
	&"ball_l": "LeftToeBase",
}
const _FINGERS: Dictionary = {
	"index": "Index",
	"middle": "Middle",
	"pinky": "Pinky",
	"ring": "Ring",
	"thumb": "Thumb",
}


static func retarget_clip(source_scene_path: String, source_clip: StringName,
		target_skeleton: Skeleton3D, target_bone_prefix: String,
		force_loop: bool = false) -> Animation:
	var packed_scene := load(source_scene_path) as PackedScene
	if packed_scene == null:
		push_error("Cannot load animation source: %s" % source_scene_path)
		return null
	var source_root := packed_scene.instantiate()
	var source_skeleton := source_root.find_child(
			"Skeleton3D", true, false) as Skeleton3D
	var source_player := source_root.find_child(
			"AnimationPlayer", true, false) as AnimationPlayer
	if source_skeleton == null or source_player == null:
		push_error("Animation source needs a Skeleton3D and AnimationPlayer: %s"
				% source_scene_path)
		source_root.free()
		return null
	var source_animation: Animation
	for library_name: StringName in source_player.get_animation_library_list():
		var library := source_player.get_animation_library(library_name)
		if library.has_animation(source_clip):
			source_animation = library.get_animation(source_clip)
			break
	if source_animation == null:
		push_error("Animation %s was not found in %s" % [source_clip, source_scene_path])
		source_root.free()
		return null
	var animation := HumanoidRetargeter.retarget_clip(
			source_skeleton, source_animation, target_skeleton,
			_bone_map_config(target_bone_prefix), force_loop)
	source_root.free()
	return animation


static func _bone_map_config(
		target_bone_prefix: String) -> HumanoidRetargeter.BoneMapConfig:
	var config := HumanoidRetargeter.BoneMapConfig.new()
	config.hips_source = &"pelvis"
	config.hips_target = StringName(target_bone_prefix + "Hips")
	config.head_source = &"Head"
	config.head_target = StringName(target_bone_prefix + "Head")
	config.shoulder_l_source = &"clavicle_l"
	config.shoulder_l_target = StringName(target_bone_prefix + "LeftShoulder")
	config.shoulder_r_source = &"clavicle_r"
	config.shoulder_r_target = StringName(target_bone_prefix + "RightShoulder")
	config.arm_chains = [
		{
			"source_hand": "hand_l",
			"target_shoulder": target_bone_prefix + "LeftShoulder",
			"target_arm": target_bone_prefix + "LeftArm",
			"target_forearm": target_bone_prefix + "LeftForeArm",
			"target_hand": target_bone_prefix + "LeftHand",
		},
		{
			"source_hand": "hand_r",
			"target_shoulder": target_bone_prefix + "RightShoulder",
			"target_arm": target_bone_prefix + "RightArm",
			"target_forearm": target_bone_prefix + "RightForeArm",
			"target_hand": target_bone_prefix + "RightHand",
		},
	]
	for source_bone: StringName in _CORE_BONES:
		config.bone_map[source_bone] = StringName(
				target_bone_prefix + String(_CORE_BONES[source_bone]))
	for side: String in ["r", "l"]:
		var target_side := "Right" if side == "r" else "Left"
		for source_finger: String in _FINGERS:
			var target_finger: String = _FINGERS[source_finger]
			for joint in range(1, 5):
				var source_name := StringName("%s_0%d_%s" % [source_finger, joint, side])
				if joint == 4:
					source_name = StringName(
							"%s_04_leaf_%s" % [source_finger, side])
				config.bone_map[source_name] = StringName(
						"%s%sHand%s%d" % [
							target_bone_prefix, target_side, target_finger, joint])
	return config
