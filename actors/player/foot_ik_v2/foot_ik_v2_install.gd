extends RefCounted
## Puts Foot IK v2 on a Player's skeleton and switches v1 off (v1 stays loaded: the player still
## reads its ground sampler for ledge safety). PlayerBody calls it every time it builds a character,
## so v2 is the only foot IK running in the game; calling it again on the same skeleton returns the
## v2 node that is already there.

static func install(body: Node, skeleton: Skeleton3D, v1: PlayerFootIKModifier) -> FootIKV2Modifier:
	var existing := skeleton.get_node_or_null("FootIKV2") as FootIKV2Modifier
	if existing != null:
		return existing
	v1.set_debug_enabled(false) # `active = false` re-enables on every landing; this sticks
	# v1's ledge-safety airborne push (3 m/s) slid the body ~1.6 m on a ramp jump.
	v1._ground_sampler._settings.landing_correction_speed = 0.0
	var v2 := FootIKV2Modifier.new()
	v2.name = &"FootIKV2"
	v2.player_body = body
	skeleton.add_child(v2) # last, so it corrects the pose every other modifier produced
	return v2
