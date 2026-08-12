extends RefCounted
## Keeps corresponding gait phases aligned when switching looping locomotion.

const GAIT_PHASE_GROUPS := {
	&"moves/unarmed_walk": 0,
	&"moves/unarmed_sprint": 0,
	&"moves/unarmed_crouch_walk": 0,
	&"moves/unarmed_crouch_left": 1,
	&"moves/unarmed_crouch_right": 1,
}


static func play(anim_player: AnimationPlayer, target: StringName, blend_time: float) -> void:
	var full := StringName("moves/" + String(target))
	if anim_player.current_animation == full:
		return
	var old_name := StringName(anim_player.current_animation)
	var gait_phase := -1.0
	if (GAIT_PHASE_GROUPS.has(old_name) and GAIT_PHASE_GROUPS.has(full)
			and GAIT_PHASE_GROUPS[old_name] == GAIT_PHASE_GROUPS[full]):
		var old_animation := anim_player.get_animation(old_name)
		if old_animation.length > 0.0:
			gait_phase = fposmod(
					anim_player.current_animation_position / old_animation.length, 1.0)
	anim_player.play(full, blend_time)
	if gait_phase >= 0.0:
		anim_player.seek(gait_phase * anim_player.get_animation(full).length)
