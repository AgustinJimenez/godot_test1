class_name PlayerStairClips
extends RefCounted
## Authored stair-walk clips (031), retargeted from Mixamo (tools/retarget_cli.gd). Used in place
## of the flat walk clip while the character is on the staircase, so the base pose matches the
## terrain. Kept out of player_body.gd (at the linter's line cap).

const DIR := "res://assets/models/stair_clips/"
const CLIPS: Dictionary = {
	&"unarmed_stair_up": "stair_walk_up",
	&"unarmed_stair_down": "stair_walk_down",
}
const SOURCES: Dictionary = {
	&"unarmed_stair_up": "Walking Up The Stairs.fbx",
	&"unarmed_stair_down": "Descending Stairs.fbx",
}
static var _speeds: Dictionary = {}
## FootIKStairSurfaces authors every stair tread/riser/traversal/landing collider on this layer.
const STAIR_CONTACT_LAYER := 1 << 5
## Ground distance the authored clip itself covers per second at 1x playback (0.467 m per 1.183 s
## cycle - 2 steps of ~0.23 m). The flat walk reference (1.6 m/s) is ~4x this, so playing the stair
## clip at the walk rate makes its steps cover only a quarter of the travel and the feet skate.
const REF_SPEED := 0.395


static func add_to(library: AnimationLibrary, body: PlayerBody = null) -> void:
	if body != null:
		PlayerTempWalk.apply(library, body) # the Mixamo walk (player_temp_walk.gd)
	for gameplay_name: StringName in CLIPS:
		var clip: Animation = _retargeted(library, body, gameplay_name) if body != null else null
		if clip == null: # the .res clips are named for a Mixamo-named skeleton and animate nothing on any other (the UAL one)
			clip = load(DIR + CLIPS[gameplay_name] + ".res") as Animation
		if clip != null:
			library.add_animation(gameplay_name, clip)


## The stair FBX retargeted onto this character the way the temp Mixamo walk is (in place along the ground, the climb kept).
static func _retargeted(library: AnimationLibrary, body: PlayerBody, gameplay_name: StringName) -> Animation:
	var path: String = DIR + SOURCES[gameplay_name]
	if body.skeleton == null or body.skeleton.find_bone(&"Hips") >= 0 or not library.has_animation(&"unarmed_walk"):
		return null # a Mixamo-named character plays the .res as it is
	var config := UniversalAnimationPools.mixamo_to_target_map_config("mixamorig_", body._target_humanoid_map)
	PlayerDirectionalLocomotionLibrary._retarget_action_clip(library, &"temp_stair_clip", path, body.skeleton,
			body.skeleton, config, library.get_animation(&"unarmed_walk"), false, body._target_humanoid_map, true)
	if not library.has_animation(&"temp_stair_clip"):
		return null
	var clip := library.get_animation(&"temp_stair_clip")
	library.remove_animation(&"temp_stair_clip")
	_speeds[gameplay_name] = PlayerTempWalkNative.in_place(clip, body.skeleton)
	return clip


## Ground speed (m/s at 1x) the retargeted stair clip's steps cover; the authored constant when it was not retargeted.
static func ref_speed(target: StringName) -> float:
	return maxf(float(_speeds.get(target, REF_SPEED)), 0.1)


## The logic below is native (native/planet_crust/src/player_stair_clips_native.cpp); these keep the callers' names.


## Whether the body stands on an authored staircase: a ray straight down onto the stair collision layer (true for the whole climb, the traversal ramp and the top landing).
static func on_staircase(body: Node3D) -> bool:
	return PlayerStairClipsNative.on_staircase(body)


## The authored stair clip while on the staircase (only for the forward walk), else `base`.
static func select_walk(body: Node3D, base: StringName, descending: bool) -> StringName:
	return PlayerStairClipsNative.select_walk(body, base, descending)


static func is_stair_target(target: StringName) -> bool:
	return PlayerStairClipsNative.is_stair_target(target)


## Playback rate for a walk target: stair clips use their own authored ground speed so their stride matches the distance travelled.
static func walk_rate(target: StringName, ground_speed: float, fallback: float) -> float:
	return PlayerStairClipsNative.walk_rate(target, ground_speed, fallback)


## Final playback rate of a locomotion clip (the stairs' band, scaled by the stair cadence and the clip's loop length).
static func clamp_rate(body: PlayerBody, target: StringName, rate: float) -> float:
	return PlayerStairClipsNative.clamp_rate(body, target, rate)
