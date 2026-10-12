extends RefCounted
## Where the lab's live spawn puts the player. Default: the stair edge where the feet used to flip.
## `-- --spawn=ramp-edge`: the side of the 15 degree ramp where the right foot hovered 65 cm over
## the floor while standing (live log 2026-10-11): the character must slide in until both feet have
## ground.


static func place(player: Node3D) -> void:
	if "--spawn=ramp-edge" in OS.get_cmdline_user_args():
		player.global_position = Vector3(-4.94, 0.85, 0.13)
		player.rotation = Vector3(0.0, deg_to_rad(21.8), 0.0)
	else:
		player.global_position = Vector3(3.65, 0.45, 1.22)
		player.rotation = Vector3(0.0, deg_to_rad(-174.3), 0.0)
