extends RefCounted
## Where the lab's live spawn puts the player. Default: the stair edge where the feet used to flip.
## `-- --spawn=ramp-edge`: the side of the 15 degree ramp where the right foot hovered 65 cm over
## the floor while standing (live log 2026-10-11): the character must slide in until both feet have
## ground. `-- --spawn=ramp-edge-turn` then turns in place (foot_ik_v2_edge_turn.gd).


const EDGE_TURN := preload("res://tests/manual/foot_ik_v2/foot_ik_v2_edge_turn.gd")


static func place(player: Node3D) -> void:
	var args := OS.get_cmdline_user_args()
	if "--spawn=ramp-edge-turn" in args or "--spawn=flat-turn" in args:
		player.get_parent().add_child(EDGE_TURN.new().setup(player))
	if "--spawn=flat-turn" in args: # the control: the same turns on open floor
		player.global_position = Vector3(0.0, 0.3, 0.0)
		player.rotation = Vector3(0.0, deg_to_rad(21.8), 0.0)
	elif "--spawn=ramp-edge" in args or "--spawn=ramp-edge-turn" in args:
		player.global_position = Vector3(-4.94, 0.85, 0.13)
		player.rotation = Vector3(0.0, deg_to_rad(21.8), 0.0)
	else:
		player.global_position = Vector3(3.65, 0.45, 1.22)
		player.rotation = Vector3(0.0, deg_to_rad(-174.3), 0.0)
