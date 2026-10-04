extends RefCounted
## The continuous stairs walks of the lab (`--stairs-walk=N[:mode[:dz]]`, N = staircase 0/1/2).
## "" walks up from the bottom; "down" walks down from the top tread facing down; "back" is a live
## log of a leg shake (stand on the top tread, then walk BACKWARD down while the speed builds);
## "diagl"/"diagr" climb at 45 degrees (forward + left/right), "sidel"/"sider" strafe along a tread,
## "sideup"/"sidedown" turn the body 76 degrees to the stairs and strafe up / down them (the worst
## live log). `dz` shifts the start along the treads.

## mode -> [input, frames, start x offset, start tread (-1 = in front of the stairs), yaw degrees]
const MODES := {
	"diagl": [Vector2(-0.707, -0.707), 100, 1.0, -1, 0.0],
	"diagr": [Vector2(0.707, -0.707), 100, -1.0, -1, 0.0],
	"sidel": [Vector2(-1.0, 0.0), 80, 1.0, 3, 0.0], "sider": [Vector2(1.0, 0.0), 80, -1.0, 3, 0.0],
	# the live log: body turned 76 degrees to the stairs, strafe left climbs, strafe right descends
	"sideup": [Vector2(-1.0, 0.0), 230, 0.0, -1, -76.0],
	"sidedown": [Vector2(1.0, 0.0), 130, 0.0, 11, -76.0],
}


static func replay(requested: String, dz := 0.0) -> Array:
	var mode := requested if requested in ["down", "back"] or MODES.has(requested) else ""
	var walk := {"name": "stairs_walk", "input": Vector2(0.0, -1.0), "frames": 200, "grade": false,
			"mode": mode, "dz": dz}
	if MODES.has(mode):
		walk["input"] = (MODES[mode] as Array)[0]
		walk["frames"] = (MODES[mode] as Array)[1]
	if MODES.has(mode): # settle after the start drop first
		return [{"name": "stairs_idle", "input": Vector2.ZERO, "frames": 40, "grade": false,
				"mode": mode, "dz": dz}, walk]
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
	var dz := float(replay.get("dz", 0.0))
	player.rotation = Vector3.ZERO
	if MODES.has(mode):
		player.rotation.y = deg_to_rad(float((MODES[mode] as Array)[4]))
	if MODES.has(mode):
		var data: Array = MODES[mode]
		var on_tread: int = data[3]
		var z := edge_z + 1.5 if on_tread < 0 else edge_z - (on_tread + 0.5) * tread
		var y := 0.3 if on_tread < 0 else top_y / steps * (on_tread + 1) + 0.3
		player.global_position = Vector3(lane_x + float(data[2]), y, z + dz)
	elif mode == "":
		player.global_position = Vector3(lane_x, 0.3, edge_z + 1.5)
	else:
		var back := mode == "back"
		player.global_position = Vector3(lane_x + (0.71 if back else 0.0),
				top_y + (0.05 if back else 0.3), edge_z - (steps - 0.5) * tread + dz)
		player.rotation = Vector3(0.0, deg_to_rad(-2.18) if back else PI, 0.0)
