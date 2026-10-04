class_name PlayerTempWalk
extends RefCounted
## TEMPORARY experiment: plays the ALS mannequin's normal walk (ALS_N_Walk_F) instead of UAL1's
## `Walk` as `unarmed_walk`, retargeted at startup onto whatever character the player wears (the
## same way the UAL clips are), to compare how they look.
## Set ENABLED to false (or delete this file and its call in PlayerStairClips.add_to) to go back.

const ENABLED := true
const MATCH_ARMS := true
const CLIP_PATH := "res://assets/models/als_mannequin_standalone/full_set/ALS_N_Walk_F.fbx"


static func apply(library: AnimationLibrary, body: PlayerBody) -> void:
	if not ENABLED or not library.has_animation(&"unarmed_walk"):
		return
	var source := (load(CLIP_PATH) as PackedScene).instantiate()
	var source_player := source.find_child("AnimationPlayer", true, false) as AnimationPlayer
	var source_skeleton := source.find_child("Skeleton3D", true, false) as Skeleton3D
	var clip: Animation = null
	for lib_name in source_player.get_animation_library_list():
		for candidate in source_player.get_animation_library(lib_name).get_animation_list():
			if clip == null and candidate != &"RESET":
				clip = source_player.get_animation_library(lib_name).get_animation(candidate)
	if clip == null:
		source.free()
		return
	# ALS names its head bone `head`, the bone map says `Head`: unfound, the rest facing came out
	# 180 degrees wrong and the arm IK crossed the arms (left hand on the right side).
	var config: HumanoidRetargeter.BoneMapConfig = body._retarget_config
	var old_head := config.head_source
	if source_skeleton.find_bone(old_head) < 0 and source_skeleton.find_bone(&"head") >= 0:
		config.head_source = &"head"
	var retargeted := HumanoidRetargeter.retarget_clip(
			source_skeleton, clip, body.skeleton, config, true, MATCH_ARMS)
	config.head_source = old_head
	source.free()
	library.remove_animation(&"unarmed_walk")
	library.add_animation(&"unarmed_walk", retargeted)
