class_name RetargetedMixamoAdapter
extends CharacterAdapter

## For Mixamo characters whose skeleton uses a numbered rig prefix
## ("mixamorig7_" for Ch08, "mixamorig5_" for Ch10 - Mixamo increments this
## per download to avoid bone-name collisions when multiple characters share
## a scene) instead of the plain "mixamorig_" MixamoCharacterAdapter's
## characters share. That numbering means action_adventure_pack's clips
## need a bone-name-prefix swap (not a straight copy) to play here, and
## Human Basic Motions FREE (a genuinely different skeleton) needs the full
## HumanoidRetargeter - see UniversalAnimationPools, which every editor-tool
## adapter pulls both pools from.
##
## Ch15_nonPBR turned out to use the plain "mixamorig_" prefix after all
## (verified by inspection, not assumed) - it belongs in
## MixamoCharacterAdapter/MIXAMO_CHARACTERS instead, not here.
##
## Baked per-character-instance rather than once and reused: even though
## e.g. two different characters might share the same numbered prefix by
## coincidence, their rest-pose proportions can still differ, and the
## retarget math reads each target skeleton's own rest transforms live
## while baking.

var _anim_player: AnimationPlayer


static func create(parent: Node3D, at_position: Vector3, model_path: String,
		character_display_name: String, bone_prefix: String) -> RetargetedMixamoAdapter:
	var instance: Node3D = (load(model_path) as PackedScene).instantiate()
	instance.position = at_position
	parent.add_child(instance)
	var adapter := RetargetedMixamoAdapter.new()
	adapter._bind(instance, character_display_name, bone_prefix)
	return adapter


func _bind(instance: Node3D, character_display_name: String, bone_prefix: String) -> void:
	node = instance
	skeleton = instance.get_node(^"Skeleton3D")
	meshes = []
	for child in skeleton.get_children():
		if child is MeshInstance3D:
			meshes.append(child)
	mesh = meshes[0] if not meshes.is_empty() else null
	_anim_player = instance.get_node(^"AnimationPlayer")
	anim_player = _anim_player
	supports_held_object = false
	supports_comparison = false
	display_name = character_display_name
	UniversalAnimationPools.build_action_pack_library(skeleton, _anim_player, bone_prefix)
	UniversalAnimationPools.build_human_basic_motions_library(skeleton, _anim_player, bone_prefix)


func get_animation_groups() -> Dictionary:
	return UniversalAnimationPools.groups()


func play_debug_anim(anim_name: StringName, blend_time: float = 0.2) -> void:
	UniversalAnimationPools.try_play(_anim_player, anim_name, blend_time)


## Human Basic Motions FREE ("B-"-prefixed, Blender-rigify convention) onto
## a numbered-prefix Mixamo skeleton (e.g. "mixamorig7_") - or onto
## MotusMan's bare names via bone_prefix="" (PlayerBodyAdapter calls this
## too, through UniversalAnimationPools). Source has 2 spine joints
## (spine/chest) versus the target's 3 (Spine/Spine1/Spine2) - the target's
## own base Spine bone is left unmapped, same kind of one-bone compromise
## player_body.gd's own BONE_MAP doc comment describes for mismatched rigs.
## Same story for fingers: the source's 3 joints per finger map onto the
## target's first 3 of 4 (the 4th is a leaf tip Mixamo itself barely
## animates), left at rest.
static func _bone_map_config(bone_prefix: String) -> HumanoidRetargeter.BoneMapConfig:
	var config := HumanoidRetargeter.BoneMapConfig.new()
	config.hips_source = &"B-hips"
	config.hips_target = StringName(bone_prefix + "Hips")
	config.head_source = &"B-head"
	config.head_target = StringName(bone_prefix + "Head")
	config.shoulder_l_source = &"B-shoulder.L"
	config.shoulder_l_target = StringName(bone_prefix + "LeftShoulder")
	config.shoulder_r_source = &"B-shoulder.R"
	config.shoulder_r_target = StringName(bone_prefix + "RightShoulder")
	config.arm_chains = [
		{
			"source_hand": "B-hand.L", "target_shoulder": bone_prefix + "LeftShoulder",
			"target_arm": bone_prefix + "LeftArm", "target_forearm": bone_prefix + "LeftForeArm",
			"target_hand": bone_prefix + "LeftHand",
		},
		{
			"source_hand": "B-hand.R", "target_shoulder": bone_prefix + "RightShoulder",
			"target_arm": bone_prefix + "RightArm", "target_forearm": bone_prefix + "RightForeArm",
			"target_hand": bone_prefix + "RightHand",
		},
	]
	config.bone_map = {
		&"B-hips": StringName(bone_prefix + "Hips"),
		&"B-spine": StringName(bone_prefix + "Spine1"),
		&"B-chest": StringName(bone_prefix + "Spine2"),
		&"B-neck": StringName(bone_prefix + "Neck"),
		&"B-head": StringName(bone_prefix + "Head"),
	}
	for side in [["L", "Left"], ["R", "Right"]]:
		var src_suffix: String = side[0]
		var t: String = side[1]
		config.bone_map[StringName("B-shoulder." + src_suffix)] = StringName(bone_prefix + t + "Shoulder")
		config.bone_map[StringName("B-upperArm." + src_suffix)] = StringName(bone_prefix + t + "Arm")
		config.bone_map[StringName("B-forearm." + src_suffix)] = StringName(bone_prefix + t + "ForeArm")
		config.bone_map[StringName("B-hand." + src_suffix)] = StringName(bone_prefix + t + "Hand")
		var finger_names := {
			"indexFinger": "Index", "middleFinger": "Middle", "ringFinger": "Ring",
			"pinky": "Pinky", "thumb": "Thumb",
		}
		for finger: String in finger_names:
			var target_finger: String = finger_names[finger]
			for joint in range(1, 4):
				config.bone_map[StringName("B-%s0%d.%s" % [finger, joint, src_suffix])] = (
						StringName("%s%sHand%s%d" % [bone_prefix, t, target_finger, joint]))
		config.bone_map[StringName("B-thigh." + src_suffix)] = StringName(bone_prefix + t + "UpLeg")
		config.bone_map[StringName("B-shin." + src_suffix)] = StringName(bone_prefix + t + "Leg")
		config.bone_map[StringName("B-foot." + src_suffix)] = StringName(bone_prefix + t + "Foot")
		config.bone_map[StringName("B-toe." + src_suffix)] = StringName(bone_prefix + t + "ToeBase")
	return config
