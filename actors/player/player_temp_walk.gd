class_name PlayerTempWalk
extends RefCounted
## TEMPORARY experiment: plays another forward walk as `unarmed_walk` to compare how they look.
## CHOICE picks the clip (0 = ALS normal walk, 1 = UAL1 Walk_Formal, 2 = UAL2 Walk_Carry, 3 = UAL2
## Zombie walk, 4 = Mixamo walking); -1 or ENABLED = false keeps UAL1's `Walk`. Every clip is
## retargeted at startup onto whatever character the player wears, like the UAL clips. Delete this
## file and its call in PlayerStairClips.add_to to remove the experiment.

const ENABLED := true
const CHOICE := 4 # the user's pick (Mixamo walking at PLAYBACK_SCALE)
const ALS_PATH := "res://assets/models/als_mannequin_standalone/full_set/ALS_N_Walk_F.fbx"
const UAL1_PATH := "res://assets/models/universal_animation_library/UAL1_Standard.glb"
const UAL2_PATH := "res://assets/models/universal_animation_library_2/UAL2_Standard.glb"
const MIXAMO_PATH := "res://assets/models/action_adventure_pack/walking.fbx"
const PLAYBACK_SCALE := 0.575 # the Mixamo walk plays at this fraction of the matching speed
## [source file, clip name in it ("" = the file's only clip)]
## Walking speed (m/s at 1x playback) of the experiment clip when it has to override the walk speed
## reference (0 = use the game's): its feet must cover the ground it is played at.
static var clip_speed := 0.0
const CHOICES: Array = [
	[ALS_PATH, ""],
	[UAL1_PATH, &"Walk_Formal"],
	[UAL2_PATH, &"Walk_Carry"],
	[UAL2_PATH, &"Zombie_Walk_Fwd"],
	[MIXAMO_PATH, ""],
]


static func apply(library: AnimationLibrary, body: PlayerBody) -> void:
	if (not ENABLED or CHOICE < 0 or CHOICE >= CHOICES.size() or DisplayServer.get_name() == "headless"
			or not library.has_animation(&"unarmed_walk")): # headless checks keep the real walk
		return
	var path: String = CHOICES[CHOICE][0]
	var clip_name: StringName = CHOICES[CHOICE][1]
	var clip: Animation = _als(body) if path == ALS_PATH else _mixamo(library, body) \
			if path == MIXAMO_PATH else body._retarget_clip(
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


## The Action Pack's Mixamo walk, retargeted the way the Action Pack strafe clips are (in place, no
## arm IK): the shared helper adds it to the library under a throwaway name, taken back out.
static func _mixamo(library: AnimationLibrary, body: PlayerBody) -> Animation:
	var config := UniversalAnimationPools.mixamo_to_target_map_config(
			"mixamorig_", body._target_humanoid_map)
	PlayerDirectionalLocomotionLibrary._retarget_action_clip(library, &"temp_mixamo_walk",
			MIXAMO_PATH, body.skeleton, body.skeleton, config, library.get_animation(&"unarmed_walk"),
			false, body._target_humanoid_map, true)
	if not library.has_animation(&"temp_mixamo_walk"):
		return null
	var clip := library.get_animation(&"temp_mixamo_walk")
	clip_speed = _in_place(clip, body)
	library.remove_animation(&"temp_mixamo_walk")
	return clip


## `make_clip_in_place` assumes the hips' local Y is up, but this rig has Z up and Y forward,
## so the Mixamo walk kept its forward travel: the body walked ahead then snapped back at the loop.
## Removes the accumulated travel along the two horizontal axes and returns the speed it covered
## (m/s at 1x), which is the clip's own walking speed.
static func _in_place(clip: Animation, body: PlayerBody) -> float:
	for track in clip.get_track_count():
		if clip.track_get_type(track) != Animation.TYPE_POSITION_3D:
			continue
		var bone := body.skeleton.find_bone(StringName(clip.track_get_path(track).get_subname(0)))
		var parent := body.skeleton.get_bone_parent(bone)
		var parent_basis := body.skeleton.get_bone_global_rest(parent).basis if parent >= 0 \
				else Basis.IDENTITY
		var vertical := 0
		var best := 0.0
		for axis in 3:
			var up := absf((parent_basis * _unit(axis)).y)
			if up > best:
				best = up
				vertical = axis
		var count := clip.track_get_key_count(track)
		var first := clip.track_get_key_value(track, 0) as Vector3
		var last := clip.track_get_key_value(track, count - 1) as Vector3
		var travel := last - first
		travel[vertical] = 0.0
		for key in count:
			var progress := clip.track_get_key_time(track, key) / clip.length
			var value := clip.track_get_key_value(track, key) as Vector3
			clip.track_set_key_value(track, key, value - travel * progress)
		return travel.length() / clip.length
	return 0.0


static func _unit(axis: int) -> Vector3:
	return Vector3(1.0 if axis == 0 else 0.0, 1.0 if axis == 1 else 0.0, 1.0 if axis == 2 else 0.0)


## The speed the forward walk clip covers at 1x playback: the experiment clip's, else `fallback`.
static func ref_speed(fallback: float) -> float:
	return clip_speed / PLAYBACK_SCALE if ENABLED and clip_speed > 0.1 else fallback
