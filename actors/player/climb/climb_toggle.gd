class_name ClimbToggle
extends Node
## Debug switch for climbing (F8), off by default like Foot IK v2: turns it on or off on the Player
## this node sits under. Climbing: jump = leap, W = climb up, crouch = drop.

const KEY := KEY_F8

func _unhandled_key_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo or key.keycode != KEY:
		return
	var player := get_parent() as Player
	if player == null:
		return
	if player.climb == null:
		PlayerClimbInstall.install(player)
	else:
		PlayerClimbInstall.remove(player)
	print("Climbing %s (F8)" % ("ON" if player.climb != null else "OFF"))
