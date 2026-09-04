class_name FootIkShortFallAnimationCheck
extends RefCounted
## Verifies that a safe-zone descent preserving the ground pose does not
## trigger the full jump landing, while an ordinary fall still does.


static func failures(body: PlayerBody) -> Array[String]:
	var result: Array[String] = []
	body.update_motion(false, false, 0.0, false, true, 0.0, 0.0, false)
	for frame in 20:
		body.update_motion(false, false, 0.0, false, false,
				-float(frame) * 0.163333, 1.0 / 60.0, false, Vector2.ZERO, true)
	if body.anim_player.current_animation.get_file().contains("jump"):
		result.append("preserved short fall entered a jump/fall animation")
	body.update_motion(false, false, 0.0, false, true, 0.0, 1.0 / 60.0, false)
	if body.anim_player.current_animation.get_file() == "unarmed_jump_land":
		result.append("preserved short fall triggered the full landing animation")
	body.update_motion(false, false, 0.0, false, false,
			-1.0, 1.0 / 60.0, false, Vector2.ZERO, false)
	body.update_motion(false, false, 0.0, false, true, 0.0, 1.0 / 60.0, false)
	if body.anim_player.current_animation.get_file() != "unarmed_jump_land":
		result.append("ordinary fall no longer triggered its landing animation")
	return result
