class_name PlanetCrustGuard
extends Node
## Keeps the player and the camera out of the planet's insides. The ground they stand on is a
## collider built tile by tile: if a tile is late, or a gap or a steep face lets them through,
## they would fall for ever. The true height of the crust is known (the noise), so a player found
## well under it is put back on top, and the camera is never let under it: it never sees the
## inside of the ground.

const PLAYER_DEPTH := 3.0 ## m under the crust before the player is lifted back
const CAMERA_CLEARANCE := 0.3 ## m the camera keeps above the crust

var planet: PlanetWorld
var target: Player
var rescues := 0 ## how many times the player was put back (a check reads it)


func _physics_process(_delta: float) -> void:
	if target == null or planet == null or planet.loading:
		return
	var here := target.global_position
	var ground_y: float = planet.ground_at(here.x, here.z, here.y)["y"]
	if here.y < ground_y - PLAYER_DEPTH:
		target.global_position = Vector3(here.x, ground_y + 1.0, here.z)
		target.velocity = Vector3.ZERO
		rescues += 1


func _process(_delta: float) -> void:
	if target == null or planet == null or planet.loading:
		return
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return
	var at := camera.global_position
	var ground_y: float = planet.ground_at(at.x, at.z, at.y)["y"]
	if at.y < ground_y + CAMERA_CLEARANCE:
		camera.global_position = Vector3(at.x, ground_y + CAMERA_CLEARANCE, at.z)
