extends RefCounted
## Where the continuous stairs walk starts: at the bottom (walking up) or, with `"down": true` in
## the replay entry, on the top tread facing down (the live "legs shake going down" case).


static func place(player: CharacterBody3D, lane_x: float, replay: Dictionary, top_y: float,
		edge_z: float,
		tread: float, steps: int) -> void:
	player.velocity = Vector3.ZERO
	if replay.get("down", false):
		player.global_position = Vector3(lane_x, top_y + 0.3, edge_z - (steps - 0.5) * tread)
		player.rotation = Vector3(0.0, PI, 0.0)
	else:
		player.global_position = Vector3(lane_x, 0.3, edge_z + 1.5)
		player.rotation = Vector3.ZERO
