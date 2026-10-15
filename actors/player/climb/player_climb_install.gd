class_name PlayerClimbInstall
extends RefCounted
## Puts climbing on a Player (opt-in, like Foot IK v2: the F8 toggle and the labs call it).


static func install(player: Player) -> PlayerClimb:
	var modifier := PlayerHandHoldIKModifier.new()
	modifier.name = &"HandHoldIK"
	modifier.player_body = player.body
	player.skeleton.add_child(modifier) # after the animation and the leg IK, before nothing else
	var climb := PlayerClimb.new().setup(player, modifier)
	player.climb = climb
	var library := player.body.anim_player.get_animation_library(&"moves")
	var idle := library.get_animation(&"unarmed_idle")
	var track := ClimbClips.hips_track(idle)
	if track >= 0 and ClimbClips.add_to(library, player.skeleton, player.body._target_humanoid_map,
			idle.track_get_key_value(track, 0), player):
		climb.use_clips()
	return climb


static func remove(player: Player) -> void:
	if player.climb != null:
		player.climb.release()
	player.climb = null
	var modifier := player.skeleton.get_node_or_null("HandHoldIK")
	if modifier != null:
		player.skeleton.remove_child(modifier)
		modifier.queue_free()
