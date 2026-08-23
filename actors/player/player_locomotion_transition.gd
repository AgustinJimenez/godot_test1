extends RefCounted
## Keeps corresponding gait phases aligned when switching looping locomotion.

const GAIT_PHASE_GROUPS := {
	&"moves/unarmed_walk": 0,
	&"moves/unarmed_sprint": 0,
	&"moves/unarmed_crouch_walk": 0,
	&"moves/unarmed_crouch_left": 1,
	&"moves/unarmed_crouch_right": 1,
	&"moves/unarmed_walk_left": 2,
	&"moves/unarmed_walk_right": 2,
	&"moves/unarmed_walk_fwd_left": 2,
	&"moves/unarmed_walk_fwd_right": 2,
}


static func play(anim_player: AnimationPlayer, target: StringName, blend_time: float) -> void:
	var full := StringName("moves/" + String(target))
	if anim_player.current_animation == full or not anim_player.has_animation(full):
		return
	anim_player.play(full, blend_time)
