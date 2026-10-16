class_name PlanetSwim
extends WorldSwim
## The flat world's swimming (wading slows the walk, deeper than a metre you float, jump rises,
## crouch dives, rivers carry you) on a planet: the water level and the current come from the planet
## (the sea, a river or a lake at the player's spot) instead of a flat world's height function.

var planet: PlanetWorld


func _water_level(player: Player) -> float:
	if planet == null:
		return level
	var at := planet.water_at_world(player.global_position)
	return at if at > -INF else player.global_position.y - 100.0


func _flow(player: Player) -> Vector2:
	if planet == null:
		return Vector2.ZERO
	var current := planet.flow_at_world(player.global_position)
	return Vector2(current.x, current.z)
