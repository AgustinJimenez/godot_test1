extends RefCounted
## Puts Foot IK v2 on a Player's skeleton: the foot IK of the game (v1 is gone). PlayerBody calls it
## every time it builds a character; calling it again on the same skeleton returns the node that is
## already there.

static func install(body: Node, skeleton: Skeleton3D) -> FootIKV2Modifier:
	var existing := skeleton.get_node_or_null("FootIKV2") as FootIKV2Modifier
	if existing != null:
		return existing
	var v2 := FootIKV2Modifier.new()
	v2.name = &"FootIKV2"
	v2.player_body = body
	skeleton.add_child(v2) # last, so it corrects the pose every other modifier produced
	return v2
