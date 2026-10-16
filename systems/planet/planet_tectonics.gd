class_name PlanetTectonics
extends RefCounted
## The plates of a planet and the land they make. A handful of plates (continental or oceanic) move
## over the sphere; where two meet the ground is pushed up into mountain ranges, island arcs and
## mid-ocean ridges, or pulled down into trenches and rift valleys, and each plate has its own
## base height (continents stand above the sea floor). Heights come in units of the planet's
## `relief` (1 is roughly an Everest above the sea), so the same code makes every size of planet.
## A pure function of the direction and the seed: any tile can ask for any point.

const CONTINENT := 0.10 ## base height of a continental plate (units of relief)
const OCEAN := -0.42 ## base height of an oceanic plate
const BOUNDARY := 0.08 ## radians: how wide a boundary's effect is (about 500 km on Earth)

var _seeds := PackedVector3Array() ## the middle of each plate
var _spin: Array[Vector3] = [] ## each plate's rotation (its velocity at p is spin x p)
var _continental: Array[bool] = []
var _warp := FastNoiseLite.new()
var _ridge := FastNoiseLite.new()
var _interior := FastNoiseLite.new()


func _init(world_seed: int, plates: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(Vector2i(world_seed, 4242))
	# plate centres: a Fibonacci spread (even over the sphere) nudged at random, so plates differ
	# in size
	for index in plates:
		var y := 1.0 - 2.0 * (float(index) + 0.5) / float(plates)
		var ring := sqrt(1.0 - y * y)
		var angle := float(index) * 2.399963 + rng.randf_range(-0.5, 0.5)
		var spot := Vector3(cos(angle) * ring, y, sin(angle) * ring)
		spot += Vector3(rng.randf_range(-1.0, 1.0), rng.randf_range(-1.0, 1.0),
				rng.randf_range(-1.0, 1.0)) * 0.28
		_seeds.append(spot.normalized())
		var axis := Vector3(rng.randf_range(-1.0, 1.0), rng.randf_range(-1.0, 1.0),
				rng.randf_range(-1.0, 1.0)).normalized()
		_spin.append(axis * rng.randf_range(0.4, 1.0))
		# the poles are mostly sea, as on Earth (Antarctica is the exception)
		_continental.append(rng.randf() < (0.42 if absf(spot.y) < 0.75 else 0.2))
	_setup(_warp, world_seed + 11, 1.4, 3)
	_setup(_ridge, world_seed + 12, 6.0, 5)
	_ridge.fractal_type = FastNoiseLite.FRACTAL_RIDGED
	_setup(_interior, world_seed + 13, 2.2, 4)


func _setup(noise: FastNoiseLite, noise_seed: int, frequency: float, octaves: int) -> void:
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.seed = noise_seed
	noise.frequency = frequency
	noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	noise.fractal_octaves = octaves


## Height in units of relief at the unit direction `dir`.
func height(dir: Vector3) -> float:
	# plate edges wander: look the plate up at a direction pushed about by a slow noise
	var shifted := dir + Vector3(_warp.get_noise_3d(dir.x, dir.y, dir.z),
			_warp.get_noise_3d(dir.x + 5.3, dir.y - 2.1, dir.z + 1.7),
			_warp.get_noise_3d(dir.x - 3.7, dir.y + 4.4, dir.z - 6.2)) * 0.30
	var q := shifted.normalized()
	var first := -1
	var second := -1
	var best := -2.0
	var next := -2.0
	for index in _seeds.size():
		var closeness := q.dot(_seeds[index])
		if closeness > best:
			next = best
			second = first
			best = closeness
			first = index
		elif closeness > next:
			next = closeness
			second = index
	# how far (radians) from the boundary between the two nearest plates
	var edge := (acos(clampf(next, -1.0, 1.0)) - acos(clampf(best, -1.0, 1.0))) * 0.5
	var here: bool = _continental[first]
	var there: bool = _continental[second]
	# the base height blends across the boundary (a continental shelf, not a cliff)
	var other := 0.5 * exp(-edge / 0.035)
	var base := lerpf(CONTINENT if here else OCEAN, CONTINENT if there else OCEAN, other)
	# how hard the two plates push on each other here: + together, - apart
	var toward := _seeds[second] - _seeds[first]
	toward -= q * q.dot(toward)
	var push := 0.0
	if toward.length_squared() > 0.000001:
		var relative := _spin[first].cross(q) - _spin[second].cross(q)
		push = clampf(relative.dot(toward.normalized()), -1.0, 1.0)
	var near := exp(-pow(edge / BOUNDARY, 2.0))
	var rise := 0.0 # the mountains, beyond the base height
	var together := maxf(push, 0.0)
	var apart := maxf(-push, 0.0)
	if here and there:
		rise = near * (0.62 * together - 0.12 * apart) # a collision: the highest ranges
	elif here != there:
		if here: # the continental side of a subduction coast: a coastal range
			rise = near * 0.42 * together
		else: # the ocean side: a trench
			rise = -near * 0.30 * together
	else:
		rise = 0.30 * together * exp(-pow((edge - 0.03) / 0.03, 2.0)) # an island arc
		rise += 0.22 * apart * exp(-pow(edge / 0.12, 2.0)) # a mid-ocean ridge
		rise -= 0.22 * together * near # and the trench beside it
	# the ranges are rough: ridged noise rides on the uplift
	var ridged := _ridge.get_noise_3d(dir.x, dir.y, dir.z) * 0.5 + 0.5
	var rough := maxf(rise, 0.0) * (ridged * 1.1 - 0.35)
	# the plate interiors are not flat either: cratons, basins, plateaus
	var inside := _interior.get_noise_3d(dir.x, dir.y, dir.z) * (0.11 if here else 0.06)
	return base + rise + rough + inside
