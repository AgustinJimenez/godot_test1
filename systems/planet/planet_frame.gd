class_name PlanetFrame
extends RefCounted
## Where the planet is in the game's world. The player always stands in a flat-looking world with
## "up" along +Y and gravity pointing down, as the whole project assumes; the planet is moved around
## the player instead. A planet space point `q` (centre at the origin, metres) is at
##   world = rot * (q - anchor) + origin_w
## `anchor` is the planet space point the player was last at; `rot` turns the ground there so its
## "up" is +Y. When the player has walked a while, `rebase` turns the planet a little (the sphere
## curves away, a few tenths of a degree) so the ground under the player is level again, and the
## world coordinates stay small however far the player has walked. Nothing needs the player or the
## physics to know: the ground just tilts under them by an amount you cannot see.

var rot := Basis.IDENTITY
var anchor := PackedFloat64Array([0.0, 0.0, 0.0]) ## planet space, doubles
var origin_w := Vector3.ZERO ## where the anchor is in the world


## Starts with the player at `world_position`, standing at `planet_position` of the planet.
func start(planet_position: PackedFloat64Array, world_position: Vector3) -> void:
	anchor = planet_position
	origin_w = world_position
	rot = Basis(Quaternion(_unit(anchor), Vector3.UP))


## The planet space position of a world position (doubles).
func to_planet(world_position: Vector3) -> PackedFloat64Array:
	var offset := rot.inverse() * (world_position - origin_w)
	return PackedFloat64Array([anchor[0] + offset.x, anchor[1] + offset.y, anchor[2] + offset.z])


## The world position of a planet space position.
func to_world(planet_position: Vector3) -> Vector3:
	var offset := Vector3(planet_position.x - anchor[0], planet_position.y - anchor[1],
			planet_position.z - anchor[2])
	return rot * offset + origin_w


## Turns the planet about the player's feet so the ground there is level, and makes the player's
## spot the new anchor. The player does not move.
func rebase(world_position: Vector3) -> void:
	anchor = to_planet(world_position)
	origin_w = world_position
	var up := rot * _unit(anchor)
	rot = (Basis(Quaternion(up.normalized(), Vector3.UP)) * rot).orthonormalized()


## Moves the whole world by `delta` (keeps the player's coordinates small on a long walk).
func shift(delta: Vector3) -> void:
	origin_w += delta


func tile_transform(tile: PlanetTile) -> Transform3D:
	var offset := Vector3(tile.origin[0] - anchor[0], tile.origin[1] - anchor[1],
			tile.origin[2] - anchor[2])
	return Transform3D(rot * tile.local_basis, rot * offset + origin_w)


func _unit(position: PackedFloat64Array) -> Vector3:
	var length := sqrt(position[0] * position[0] + position[1] * position[1]
			+ position[2] * position[2])
	return Vector3(position[0] / length, position[1] / length, position[2] / length)
