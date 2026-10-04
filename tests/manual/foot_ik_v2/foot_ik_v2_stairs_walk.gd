extends RefCounted
## The continuous stairs walks of the lab (`--stairs-walk=N[:mode]`). Modes: "" walks up from the
## bottom, "down" walks down from the top tread facing down, "back" is the live log of a leg shake:
## stand on the top tread, then walk BACKWARD down the stairs (S key) while the speed builds up.


static func replay(requested: String, dz := 0.0) -> Array:
	var mode := requested if requested in ["down", "back"] else "" # get_slice may echo the whole arg
	var walk := {"name": "stairs_walk", "input": Vector2(0.0, -1.0), "frames": 200, "grade": false,
			"mode": mode, "dz": dz}
	if mode != "back":
		return [walk]
	walk["input"] = Vector2(0.0, 1.0)
	walk["frames"] = 140
	return [{"name": "stairs_idle", "input": Vector2.ZERO, "frames": 40, "grade": false,
			"mode": mode, "dz": dz}, walk]


static func place(player: CharacterBody3D, lane_x: float, replay: Dictionary, top_y: float,
		edge_z: float, tread: float, steps: int) -> void:
	player.velocity = Vector3.ZERO
	var mode: String = replay.get("mode", "")
	if mode == "":
		player.global_position = Vector3(lane_x, 0.3, edge_z + 1.5)
		player.rotation = Vector3.ZERO
		return
	var z := edge_z - (steps - 0.5) * tread + float(replay.get("dz", 0.0))
	var x := lane_x + (0.71 if mode == "back" else 0.0)
	player.global_position = Vector3(x, top_y + (0.05 if mode == "back" else 0.3), z)
	player.rotation = Vector3(0.0, deg_to_rad(-2.18) if mode == "back" else PI, 0.0)
