class_name PlayerTempWalk
extends RefCounted
## The walk set the player plays: the Action Pack's Mixamo walking as `unarmed_walk` (at PlayerTempWalkNative.PLAYBACK_SCALE) and the ALS N_Walk_LF / RF
## as the A / D sideways walks, both retargeted at startup onto whatever character the player wears. Only the loading lives here (HumanoidRetargeter
## and the action-pack helper are GDScript); the speed reference, the body-turn rules and the clip edits are native (PlayerTempWalkNative).
## The other walks tried while choosing this one (UAL1 Walk_Formal, UAL2 Walk_Carry / Zombie, Human Basic Motions, GALS, the ALS diagonals and backward
## walks, the Action Pack strafes) are in git history before the native conversion.

const MIXAMO_PATH := "res://assets/models/action_adventure_pack/walking.fbx"
const ALS_DIR := "res://assets/models/als_mannequin_standalone/full_set/"
const SIDE_YAW_DEG := 0.0 # ALS LF/RF already swing the feet sideways; 45 made a diagonal
## A / D alone: the ALS forward-left / forward-right walks, played as the sideways walks. [source clip, side of the hip turn]
const SIDE_CLIPS := {
	&"unarmed_walk_left": ["ALS_N_Walk_LF", 1.0], &"unarmed_walk_right": ["ALS_N_Walk_RF", -1.0],
}

## A headless check can ask for the Mixamo walk (the comparison scene's --temp-walk); it keeps the real UAL walk otherwise.
static var use_in_headless := false


static func _skip_headless() -> bool:
	return DisplayServer.get_name() == "headless" and not use_in_headless


## Replaces `unarmed_walk` with the Mixamo walk and records its speed and length for the native reference.
static func apply(library: AnimationLibrary, body: PlayerBody) -> void:
	if _skip_headless() or not library.has_animation(&"unarmed_walk"):
		return
	var clip := _mixamo(library, body)
	if clip == null:
		push_warning("PlayerTempWalk: clip %s did not load" % MIXAMO_PATH)
		return
	library.remove_animation(&"unarmed_walk")
	PlayerTempWalkNative.set_forward_length(clip.length)
	library.add_animation(&"unarmed_walk", clip)


## The ALS file has one clip; its bone names differ from the map's (`head`, not `Head`): with it unfound the rest facing came out 180 degrees wrong
## and the arm IK crossed the arms.
static func _als(body: PlayerBody, path: String) -> Animation:
	var source := (load(path) as PackedScene).instantiate()
	var source_player := source.find_child("AnimationPlayer", true, false) as AnimationPlayer
	var source_skeleton := source.find_child("Skeleton3D", true, false) as Skeleton3D
	var clip: Animation = null
	for lib_name in source_player.get_animation_library_list():
		for candidate in source_player.get_animation_library(lib_name).get_animation_list():
			if clip == null and candidate != &"RESET":
				clip = source_player.get_animation_library(lib_name).get_animation(candidate)
	var result: Animation = null
	if clip != null:
		var config: HumanoidRetargeter.BoneMapConfig = body._retarget_config
		var old_head := config.head_source
		if source_skeleton.find_bone(old_head) < 0 and source_skeleton.find_bone(&"head") >= 0:
			config.head_source = &"head"
		result = HumanoidRetargeter.retarget_clip(
				source_skeleton, clip, body.skeleton, config, true, true)
		config.head_source = old_head
	source.free()
	return result


## The Action Pack's Mixamo walk, retargeted the way the Action Pack strafe clips are (in place, no arm IK): the shared helper adds it to the library
## under a throwaway name, taken back out.
static func _mixamo(library: AnimationLibrary, body: PlayerBody) -> Animation:
	var config := UniversalAnimationPools.mixamo_to_target_map_config(
			"mixamorig_", body._target_humanoid_map)
	PlayerDirectionalLocomotionLibrary._retarget_action_clip(library, &"temp_mixamo_walk",
			MIXAMO_PATH, body.skeleton, body.skeleton, config, library.get_animation(&"unarmed_walk"),
			false, body._target_humanoid_map, true)
	if not library.has_animation(&"temp_mixamo_walk"):
		return null
	var clip := library.get_animation(&"temp_mixamo_walk")
	PlayerTempWalkNative.set_clip_speed(PlayerTempWalkNative.in_place(clip, body.skeleton))
	library.remove_animation(&"temp_mixamo_walk")
	return clip


## Called after the Action Pack strafe clips are built (they would overwrite these). Headless checks keep the old strafes, like the forward walk.
static func apply_side(library: AnimationLibrary, body: PlayerBody) -> void:
	if _skip_headless():
		return
	for clip_name: StringName in SIDE_CLIPS:
		var clip := _als(body, ALS_DIR + String(SIDE_CLIPS[clip_name][0]) + ".fbx")
		if clip != null:
			clip = PlayerTempWalkNative.yawed(clip, deg_to_rad(SIDE_YAW_DEG) * float(SIDE_CLIPS[clip_name][1]),
					body.skeleton, StringName(body._retarget_config.hips_target))
		if clip == null:
			push_warning("PlayerTempWalk: side clip %s did not load" % clip_name)
			continue
		if library.has_animation(clip_name):
			library.remove_animation(clip_name)
		library.add_animation(clip_name, clip)
		PlayerTempWalkNative.set_clip_length(clip_name, clip.length)
