class_name UniversalAnimationPools
extends RefCounted

## Two animation pools every character in the editor tool can preview,
## regardless of its own native skeleton - purely a tool convenience so any
## character can play any animation, per the user's explicit ask. Actual
## gameplay code (player_body.gd, humanoid_actor.gd) is untouched and keeps using
## its own specific, hand-picked animations; this only ever adds extra
## libraries onto a character's AnimationPlayer inside the editor tool.
##
## - Action Adventure Pack: cheap bone-name-prefix swap, no real
##   retargeting math needed - every Mixamo-family character (any
##   "mixamorig_"/"mixamorig5_"/"mixamorig7_" prefix, or MotusMan's bare
##   names, prefix "") shares the exact same bone hierarchy and rest-pose
##   orientation, so swapping the prefix on each track's bone name is
##   enough (see _prefix_swap_clip).
## - Human Basic Motions FREE: a genuinely different (Blender-rigify,
##   "B-"-prefixed) skeleton, so this goes through the full
##   HumanoidRetargeter/RetargetedMixamoAdapter bone map instead.

const ACTION_PACK_SOURCE_PREFIX := "mixamorig_"
const ACTION_PACK_SOURCE_ANIM_NAME := &"mixamo_com"
## Any clip in the pack works as the skeleton/rest-pose reference for
## retargeting - they're all exports of the same rig.
const ACTION_PACK_SOURCE_MODEL_PATH := "res://assets/models/action_adventure_pack/idle.fbx"
const ACTION_PACK_CLIPS: Dictionary = {
	&"pack_idle": "res://assets/models/action_adventure_pack/idle.fbx",
	&"pack_walking": "res://assets/models/action_adventure_pack/walking.fbx",
	&"pack_running": "res://assets/models/action_adventure_pack/running.fbx",
}
const ACTION_PACK_DEATH_CLIP := "res://assets/models/action_adventure_pack/hard landing.fbx"
const ACTION_PACK_LIBRARY := &"pack"
const ACTION_PACK_GROUP := &"Action Adventure Pack"
## Core chain + all 4 finger joints per finger, mirrored L/R - matches
## standard Mixamo naming exactly (confirmed by inspection: Ch08/10's
## numbered-prefix rigs and action_adventure_pack's own clips both use
## these same suffixes). Skips "Neck1", a bone action_adventure_pack's
## source has that most targets don't - same one-bone compromise as the
## spine mismatch RetargetedMixamoAdapter's own doc comment describes.
const _ACTION_PACK_BONE_SUFFIXES: PackedStringArray = [
	"Hips", "Spine", "Spine1", "Spine2", "Neck", "Head",
]
const _ACTION_PACK_SIDED_SUFFIXES: PackedStringArray = [
	"Shoulder", "Arm", "ForeArm", "Hand",
	"HandThumb1", "HandThumb2", "HandThumb3", "HandThumb4",
	"HandIndex1", "HandIndex2", "HandIndex3", "HandIndex4",
	"HandMiddle1", "HandMiddle2", "HandMiddle3", "HandMiddle4",
	"HandRing1", "HandRing2", "HandRing3", "HandRing4",
	"HandPinky1", "HandPinky2", "HandPinky3", "HandPinky4",
	"UpLeg", "Leg", "Foot", "ToeBase",
]

const HBM_SOURCE_MODEL_PATH := "res://assets/models/human_basic_motions/HumanM_Model.fbx"
const HBM_CLIPS: Dictionary = {
	&"hbm_idle": ["res://assets/models/human_basic_motions/HumanM@Idle01.fbx", "HumanM_Idle01"],
	&"hbm_walk": [
		"res://assets/models/human_basic_motions/HumanM@Walk01_Forward.fbx", "HumanM_Walk01_Forward"],
	&"hbm_run": [
		"res://assets/models/human_basic_motions/HumanM@Run01_Forward.fbx", "HumanM_Run01_Forward"],
}
const HBM_LIBRARY := &"hbm"
const HBM_GROUP := &"Human Basic Motions FREE"


## Group name -> clip names, ready to merge into any adapter's
## get_animation_groups() return value.
static func groups() -> Dictionary:
	var pack_clips: Array[StringName] = []
	for key: StringName in ACTION_PACK_CLIPS:
		pack_clips.append(key)
	pack_clips.append(&"pack_death")
	var hbm_clips: Array[StringName] = []
	for key: StringName in HBM_CLIPS:
		hbm_clips.append(key)
	return {ACTION_PACK_GROUP: pack_clips, HBM_GROUP: hbm_clips}


## Tries anim_name against both pool libraries; returns true and starts
## playback if found, false (no-op) otherwise, so callers can fall through
## to their own character-specific library.
static func try_play(
		anim_player: AnimationPlayer, anim_name: StringName, blend_time: float) -> bool:
	for library in [ACTION_PACK_LIBRARY, HBM_LIBRARY]:
		var path := String(library) + "/" + String(anim_name)
		if anim_player.has_animation(path):
			anim_player.play(path, blend_time)
			return true
	return false


## Goes through the full HumanoidRetargeter, same as Human Basic Motions
## FREE - NOT a cheap bone-name-prefix swap, despite every Mixamo-family
## character sharing action_adventure_pack's exact bone names/hierarchy.
## Confirmed by testing: MotusMan's bone NAMES happen to follow Mixamo's
## naming convention, but its rest-pose bone ORIENTATIONS don't (it isn't a
## Mixamo export) - a raw name-prefix swap onto MotusMan produced a
## grotesquely contorted pose (leg wrenched straight up past the head).
## Real Mixamo-exported rigs (The Boss/Brute/Ch08/10/etc.) all share
## Mixamo's own rest-orientation convention, so a swap WOULD have worked
## for those specifically - but using the same correct-in-general retarget
## path for every target, instead of a swap that's only safe for a subset
## of targets, avoids that footgun for whatever character gets added next.
static func build_action_pack_library(target_skeleton: Skeleton3D,
		target_anim_player: AnimationPlayer, target_bone_prefix: String) -> void:
	var source_root: Node = (load(ACTION_PACK_SOURCE_MODEL_PATH) as PackedScene).instantiate()
	var source_skeleton: Skeleton3D = source_root.get_node(^"Skeleton3D")
	var config := _action_pack_bone_map_config(target_bone_prefix)
	var lib := AnimationLibrary.new()
	for clip_name: StringName in ACTION_PACK_CLIPS:
		var anim := _retarget_action_pack_clip(
				ACTION_PACK_CLIPS[clip_name], source_skeleton, target_skeleton, config, true)
		if anim != null:
			lib.add_animation(clip_name, anim)
	var death_anim := _retarget_action_pack_clip(
			ACTION_PACK_DEATH_CLIP, source_skeleton, target_skeleton, config, false)
	if death_anim != null:
		lib.add_animation(&"pack_death", death_anim)
	source_root.free()
	target_anim_player.add_animation_library(ACTION_PACK_LIBRARY, lib)


static func _retarget_action_pack_clip(fbx_path: String, source_skeleton: Skeleton3D,
		target_skeleton: Skeleton3D, config: HumanoidRetargeter.BoneMapConfig,
		force_loop: bool) -> Animation:
	var clip_root: Node = (load(fbx_path) as PackedScene).instantiate()
	var clip_ap: AnimationPlayer = clip_root.find_child("AnimationPlayer", true, false)
	if not clip_ap.has_animation(ACTION_PACK_SOURCE_ANIM_NAME):
		clip_root.free()
		return null
	var src_animation := clip_ap.get_animation(ACTION_PACK_SOURCE_ANIM_NAME)
	var anim := HumanoidRetargeter.retarget_clip(
			source_skeleton, src_animation, target_skeleton, config, force_loop)
	clip_root.free()
	return anim


static func _action_pack_bone_map_config(
		target_bone_prefix: String) -> HumanoidRetargeter.BoneMapConfig:
	return mixamo_family_bone_map_config(ACTION_PACK_SOURCE_PREFIX, target_bone_prefix)


## Every core+finger+leg bone maps 1:1 by suffix between any two
## Mixamo-family skeletons (standard Mixamo naming, any numbered or empty
## prefix) - the prefixes are the only difference in name. Public/generic
## (not just for action_adventure_pack) so ImportAnimation can build the
## same kind of map for an arbitrary imported clip that turns out to be
## another Mixamo-family export.
static func mixamo_family_bone_map_config(
		source_bone_prefix: String, target_bone_prefix: String) -> HumanoidRetargeter.BoneMapConfig:
	var config := HumanoidRetargeter.BoneMapConfig.new()
	config.hips_source = StringName(source_bone_prefix + "Hips")
	config.hips_target = StringName(target_bone_prefix + "Hips")
	config.head_source = StringName(source_bone_prefix + "Head")
	config.head_target = StringName(target_bone_prefix + "Head")
	config.shoulder_l_source = StringName(source_bone_prefix + "LeftShoulder")
	config.shoulder_l_target = StringName(target_bone_prefix + "LeftShoulder")
	config.shoulder_r_source = StringName(source_bone_prefix + "RightShoulder")
	config.shoulder_r_target = StringName(target_bone_prefix + "RightShoulder")
	config.arm_chains = [
		{
			"source_hand": source_bone_prefix + "LeftHand",
			"target_shoulder": target_bone_prefix + "LeftShoulder",
			"target_arm": target_bone_prefix + "LeftArm",
			"target_forearm": target_bone_prefix + "LeftForeArm",
			"target_hand": target_bone_prefix + "LeftHand",
		},
		{
			"source_hand": source_bone_prefix + "RightHand",
			"target_shoulder": target_bone_prefix + "RightShoulder",
			"target_arm": target_bone_prefix + "RightArm",
			"target_forearm": target_bone_prefix + "RightForeArm",
			"target_hand": target_bone_prefix + "RightHand",
		},
	]
	config.bone_map = {}
	for suffix in _ACTION_PACK_BONE_SUFFIXES:
		config.bone_map[StringName(source_bone_prefix + suffix)] = (
				StringName(target_bone_prefix + suffix))
	for side in ["Left", "Right"]:
		for suffix in _ACTION_PACK_SIDED_SUFFIXES:
			config.bone_map[StringName(source_bone_prefix + side + suffix)] = (
					StringName(target_bone_prefix + side + suffix))
	return config


## Best-effort lookup of "the" motion animation inside an arbitrary
## imported clip file's AnimationPlayer: prefers the Mixamo convention name
## ("mixamo_com") if present, otherwise falls back to the first non-empty
## animation found in any library - imported files won't reliably follow
## any one packaging convention the way action_adventure_pack/Human Basic
## Motions FREE do.
static func find_primary_animation(anim_player: AnimationPlayer) -> Animation:
	if anim_player.has_animation(ACTION_PACK_SOURCE_ANIM_NAME):
		return anim_player.get_animation(ACTION_PACK_SOURCE_ANIM_NAME)
	for lib_name in anim_player.get_animation_library_list():
		var lib := anim_player.get_animation_library(lib_name)
		var clip_names := lib.get_animation_list()
		if not clip_names.is_empty():
			return lib.get_animation(clip_names[0])
	return null


static func build_human_basic_motions_library(target_skeleton: Skeleton3D,
		target_anim_player: AnimationPlayer, target_bone_prefix: String) -> void:
	var source_root: Node = (load(HBM_SOURCE_MODEL_PATH) as PackedScene).instantiate()
	var source_skeleton: Skeleton3D = source_root.get_node(^"Skeleton3D")
	var config := RetargetedMixamoAdapter._bone_map_config(target_bone_prefix)
	var lib := AnimationLibrary.new()
	for clip_name: StringName in HBM_CLIPS:
		var clip_info: Array = HBM_CLIPS[clip_name]
		var clip_root: Node = (load(clip_info[0]) as PackedScene).instantiate()
		var clip_ap: AnimationPlayer = clip_root.find_child("AnimationPlayer", true, false)
		var src_animation: Animation = null
		for lib_name in clip_ap.get_animation_library_list():
			var candidate := clip_ap.get_animation_library(lib_name)
			if candidate.has_animation(StringName(clip_info[1])):
				src_animation = candidate.get_animation(StringName(clip_info[1]))
				break
		if src_animation != null:
			lib.add_animation(clip_name, HumanoidRetargeter.retarget_clip(
					source_skeleton, src_animation, target_skeleton, config, true))
		clip_root.free()
	source_root.free()
	target_anim_player.add_animation_library(HBM_LIBRARY, lib)
