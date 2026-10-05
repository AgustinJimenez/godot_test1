class_name PlayerTempWalk
extends RefCounted
## TEMPORARY experiment: plays another forward walk as `unarmed_walk` to compare how they look.
## CHOICE picks the clip (0 = ALS normal walk, 1 = UAL1 Walk_Formal, 2 = UAL2 Walk_Carry,
## 3 = UAL2 Zombie walk); -1 or ENABLED = false keeps UAL1's `Walk`. Every clip is retargeted at
## startup onto whatever character the player wears, like the UAL clips. Delete this file and its
## call in PlayerStairClips.add_to to remove the experiment.

const ENABLED := true
const CHOICE := 1
const ALS_PATH := "res://assets/models/als_mannequin_standalone/full_set/ALS_N_Walk_F.fbx"
const UAL1_PATH := "res://assets/models/universal_animation_library/UAL1_Standard.glb"
const UAL2_PATH := "res://assets/models/universal_animation_library_2/UAL2_Standard.glb"
## [source file, clip name in it ("" = the file's only clip)]
const CHOICES: Array = [
	[ALS_PATH, ""],
	[UAL1_PATH, &"Walk_Formal"],
	[UAL2_PATH, &"Walk_Carry"],
	[UAL2_PATH, &"Zombie_Walk_Fwd"],
]


static func apply(library: AnimationLibrary, body: PlayerBody) -> void:
	if (not ENABLED or CHOICE < 0 or CHOICE >= CHOICES.size() or DisplayServer.get_name() == "headless"
			or not library.has_animation(&"unarmed_walk")): # headless checks keep the real walk
		return
	var path: String = CHOICES[CHOICE][0]
	var clip_name: StringName = CHOICES[CHOICE][1]
	var clip: Animation = _als(body) if path == ALS_PATH else body._retarget_clip(
			path, clip_name, body._held_pose, true)
	if clip == null:
		push_warning("PlayerTempWalk: clip %s not found in %s" % [clip_name, path])
		return
	library.remove_animation(&"unarmed_walk")
	library.add_animation(&"unarmed_walk", clip)


## The ALS file has one clip; its bone names differ from the map's (`head`, not `Head`): with it
## unfound the rest facing came out 180 degrees wrong and the arm IK crossed the arms.
static func _als(body: PlayerBody) -> Animation:
	var source := (load(ALS_PATH) as PackedScene).instantiate()
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
