class_name PlayerStairClips
extends RefCounted
## Authored stair-walk clips (031), retargeted from Mixamo (tools/retarget_cli.gd). Used in place
## of the flat walk clip while the stair predictor owns a foot. Kept out of player_body.gd (at cap).

const DIR := "res://assets/models/stair_clips/"
const CLIPS: Dictionary = {
	&"unarmed_stair_up": "stair_walk_up",
	&"unarmed_stair_down": "stair_walk_down",
}


## Pick the walk clip for the current terrain: the authored stair clip while the stair predictor
## owns a foot, otherwise the base clip unchanged.
static func select_walk(base: StringName, predictor) -> StringName:
	if base != &"unarmed_walk" or predictor == null or not predictor.is_active():
		return base
	return &"unarmed_stair_down" if predictor.is_descending_treads() else &"unarmed_stair_up"


static func add_to(library: AnimationLibrary) -> void:
	for gameplay_name: StringName in CLIPS:
		var clip := load(DIR + CLIPS[gameplay_name] + ".res") as Animation
		if clip != null:
			library.add_animation(gameplay_name, clip)
