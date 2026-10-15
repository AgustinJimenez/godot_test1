class_name ErodedNoise
extends RefCounted
## Terrain that looks eroded, as a pure function of (x, z): fractal value noise where every octave's
## height is divided by how steep the ground already is (the sum of the slopes of the octaves
## before it). Steep faces stay smooth and clean, gentle ground gets all the fine detail, and the
## result has gullies, spurs and valley floors like land water has worked on. No simulation, so any
## tile can be built alone and neighbours always agree.

const OCTAVES := 6

var _seed := 0


func _init(world_seed: int) -> void:
	_seed = world_seed * 7919 + 13


## Height in -1..1 (about) at world position `p` with the first octave `wavelength` metres wide.
func height(x: float, z: float, wavelength: float) -> float:
	var sum := 0.0
	var amp := 0.5
	var slopes := Vector2.ZERO
	var scale := 1.0 / wavelength
	var px := x * scale
	var pz := z * scale
	for octave in OCTAVES:
		var n := _noised(px, pz, octave)
		slopes += Vector2(n.y, n.z)
		sum += amp * n.x / (1.0 + slopes.dot(slopes))
		amp *= 0.5
		# turn and double the lattice each octave so the grid never lines up
		var rx := px * 1.6 - pz * 1.2
		var rz := px * 1.2 + pz * 1.6
		px = rx
		pz = rz
	return sum * 2.0


## Value noise (-1..1) and its slope, smooth (quintic): Vector3(value, d/dx, d/dz).
func _noised(x: float, z: float, octave: int) -> Vector3:
	var ix := floori(x)
	var iz := floori(z)
	var fx := x - float(ix)
	var fz := z - float(iz)
	var ux := fx * fx * fx * (fx * (fx * 6.0 - 15.0) + 10.0)
	var uz := fz * fz * fz * (fz * (fz * 6.0 - 15.0) + 10.0)
	var dux := 30.0 * fx * fx * (fx * (fx - 2.0) + 1.0)
	var duz := 30.0 * fz * fz * (fz * (fz - 2.0) + 1.0)
	var a := _corner(ix, iz, octave)
	var b := _corner(ix + 1, iz, octave)
	var c := _corner(ix, iz + 1, octave)
	var d := _corner(ix + 1, iz + 1, octave)
	var k := a - b - c + d
	return Vector3(a + (b - a) * ux + (c - a) * uz + k * ux * uz,
			dux * ((b - a) + k * uz), duz * ((c - a) + k * ux))


func _corner(ix: int, iz: int, octave: int) -> float:
	var h := ix * 374761393 + iz * 668265263 + octave * 1442695041 + _seed
	h = (h ^ (h >> 13)) * 1274126177
	h = h ^ (h >> 16)
	return float(h & 0xffff) / 32767.5 - 1.0
