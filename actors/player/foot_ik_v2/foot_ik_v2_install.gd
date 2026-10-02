extends RefCounted
## Puts Foot IK v2 on a Player's skeleton and switches v1 off (v1 stays loaded: the player still
## reads its ground sampler for ledge safety). Opt-in: only the v2 lab calls it for now, the game
## itself still runs v1.

const MODIFIER := preload("res://actors/player/foot_ik_v2/foot_ik_v2_modifier.gd")


static func install(body: Node, skeleton: Skeleton3D, v1: PlayerFootIKModifier) -> FootIKV2Modifier:
	v1.set_debug_enabled(false) # `active = false` re-enables on every landing; this sticks
	# v1's ledge-safety airborne push (3 m/s) slid the body ~1.6 m on a ramp jump.
	v1._ground_sampler._settings.landing_correction_speed = 0.0
	var v2 := MODIFIER.new() as FootIKV2Modifier
	v2.name = &"FootIKV2"
	v2.player_body = body
	skeleton.add_child(v2) # last, so it corrects the pose every other modifier produced
	return v2
