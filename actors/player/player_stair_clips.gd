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


## Same, but only allow the flat<->stair swap near the current clip's loop seam, where both clips
## restart: the two cycles differ, so swapping mid-stride snaps the feet and a mid-stride swap
## clipped 12cm in the lab (031). Waiting for the seam gives the clips a shared phase to meet at.
static func select_walk_gated(base: StringName, modifier,
		anim_player: AnimationPlayer) -> StringName:
	if modifier == null or modifier.player_body == null:
		return base
	var root: Node = modifier.player_body.get_parent()
	var on_stairs := false
	if root != null and root.has_method("get_stair_debug_state"):
		on_stairs = bool((root.get_stair_debug_state() as Dictionary).get(
				"recent_transition", false))
	if base != &"unarmed_walk" or not on_stairs:
		return base
	var descending: bool = (modifier._stair_predictor != null
			and modifier._stair_predictor.is_descending_treads())
	var stair: StringName = &"unarmed_stair_down" if descending else &"unarmed_stair_up"
	var length := anim_player.current_animation_length
	if length <= 0.0:
		return base
	if anim_player.current_animation_position > 0.10 * length:
		return base
	return stair


static func add_to(library: AnimationLibrary) -> void:
	for gameplay_name: StringName in CLIPS:
		var clip := load(DIR + CLIPS[gameplay_name] + ".res") as Animation
		if clip != null:
			library.add_animation(gameplay_name, clip)
