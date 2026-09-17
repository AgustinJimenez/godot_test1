extends RefCounted
## Keeps corresponding gait phases aligned when switching looping locomotion.

const GAIT_PHASE_GROUPS := {
	&"moves/unarmed_walk": 0,
	&"moves/unarmed_stair_up": 0,
	&"moves/unarmed_stair_down": 0,
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
	var from := anim_player.current_animation
	var from_group: Variant = GAIT_PHASE_GROUPS.get(from)
	var to_group: Variant = GAIT_PHASE_GROUPS.get(full)
	if from_group != null and from_group == to_group:
		# Same gait phase group (e.g. flat walk <-> stair walk): start the new clip at the same
		# normalized phase so the feet do not snap across the switch.
		var from_length := anim_player.current_animation_length
		var from_position := anim_player.current_animation_position
		var to_length := anim_player.get_animation(full).length
		anim_player.play(full, blend_time)
		if from_length > 0.0 and to_length > 0.0:
			anim_player.seek(fposmod(from_position / from_length, 1.0) * to_length, true)
		return
	anim_player.play(full, blend_time)
