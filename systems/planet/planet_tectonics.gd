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
const WARP := 0.20 ## how far the plate edges are bent (a unit sphere; 0.3 made loops in the sea)
const NEAR := 4 ## how many of the nearest plates are looked at
const SOFT := 0.14 ## radians: how fast a plate's say fades as it gets further than the nearest

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
		var angle := float(index) * 2.399963 + _between(rng, -0.5, 0.5)
		var spot := Vector3(cos(angle) * ring, y, sin(angle) * ring)
		spot += Vector3(_between(rng, -1.0, 1.0), _between(rng, -1.0, 1.0),
				_between(rng, -1.0, 1.0)) * 0.28
		_seeds.append(spot.normalized())
		var axis := Vector3(_between(rng, -1.0, 1.0), _between(rng, -1.0, 1.0),
				_between(rng, -1.0, 1.0)).normalized()
		_spin.append(axis * _between(rng, 0.4, 1.0))
		# the poles are mostly sea, as on Earth (Antarctica is the exception)
		_continental.append(_between(rng, 0.0, 1.0) < (0.42 if absf(spot.y) < 0.75 else 0.2))
	_setup(_warp, world_seed + 11, 1.4, 3)
	_setup(_ridge, world_seed + 12, 6.0, 5)
	_ridge.fractal_type = FastNoiseLite.FRACTAL_RIDGED
	_setup(_interior, world_seed + 13, 2.2, 4)


## A number between `low` and `high` from the generator's integers: the same on every build of the
## engine (its own `randf_range` is not: the double precision build draws other numbers, so the
## same seed made another planet there).
func _between(rng: RandomNumberGenerator, low: float, high: float) -> float:
	return low + (high - low) * float(rng.randi() >> 8) / 16777216.0


func _setup(noise: FastNoiseLite, noise_seed: int, frequency: float, octaves: int) -> void:
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.seed = noise_seed
	noise.frequency = frequency
	noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	noise.fractal_octaves = octaves


## Height in units of relief at the unit direction `dir`. Every plate near enough has a say, with a
## smooth weight (the nearest has all of it, a plate that is further by a few hundredths of a
## radian has almost none), and every pair of the near plates adds its own boundary effect, weighted
## the same way: so nothing jumps where the second nearest plate changes (a line through a plate
## that made 50 m walls when only the two nearest plates counted).
func height(dir: Vector3) -> float:
	# plate edges wander: look the plate up at a direction pushed about by a slow noise
	var shifted := dir + Vector3(_warp.get_noise_3d(dir.x, dir.y, dir.z),
			_warp.get_noise_3d(dir.x + 5.3, dir.y - 2.1, dir.z + 1.7),
			_warp.get_noise_3d(dir.x - 3.7, dir.y + 4.4, dir.z - 6.2)) * WARP
	var q := shifted.normalized()
	# the four nearest plates, nearest first (kept in plain variables: this runs for every vertex of
	# the ground, from several threads, and arrays made per call were most of its cost)
	var c0 := -2.0
	var c1 := -2.0
	var c2 := -2.0
	var c3 := -2.0
	var p0 := 0
	var p1 := 0
	var p2 := 0
	var p3 := 0
	var index := -1
	for centre: Vector3 in _seeds:
		index += 1
		var closeness := q.dot(centre)
		if closeness <= c3:
			continue
		if closeness > c1:
			if closeness > c0:
				c3 = c2
				p3 = p2
				c2 = c1
				p2 = p1
				c1 = c0
				p1 = p0
				c0 = closeness
				p0 = index
			else:
				c3 = c2
				p3 = p2
				c2 = c1
				p2 = p1
				c1 = closeness
				p1 = index
		elif closeness > c2:
			c3 = c2
			p3 = p2
			c2 = closeness
			p2 = index
		else:
			c3 = closeness
			p3 = index
	var a0 := acos(clampf(c0, -1.0, 1.0))
	var a1 := acos(clampf(c1, -1.0, 1.0))
	var a2 := acos(clampf(c2, -1.0, 1.0))
	var a3 := acos(clampf(c3, -1.0, 1.0))
	var w0 := 1.0 # exp(-(a0 - a0) / SOFT)
	var w1 := exp(-(a1 - a0) / SOFT)
	var w2 := exp(-(a2 - a0) / SOFT)
	var w3 := exp(-(a3 - a0) / SOFT)
	var total := w0 + w1 + w2 + w3
	var land0: bool = _continental[p0]
	var land1: bool = _continental[p1]
	var land2: bool = _continental[p2]
	var land3: bool = _continental[p3]
	var base := w0 * (CONTINENT if land0 else OCEAN)
	base += w1 * (CONTINENT if land1 else OCEAN)
	base += w2 * (CONTINENT if land2 else OCEAN)
	base += w3 * (CONTINENT if land3 else OCEAN)
	var variety := w0 * (0.11 if land0 else 0.06)
	variety += w1 * (0.11 if land1 else 0.06)
	variety += w2 * (0.11 if land2 else 0.06)
	variety += w3 * (0.11 if land3 else 0.06)
	base /= total
	variety /= total
	# the mountains, beyond the base height: every pair of the near plates adds its boundary, weighed
	# by the two plates' say (a pair matters while both are among the nearest)
	var scale := 1.0 / (w0 * w1)
	var rise := 0.0
	var pair := w0 * w1 * scale
	if pair >= 0.002:
		rise += pair * _boundary(p0, p1, q, (a1 - a0) * 0.5)
	pair = w0 * w2 * scale
	if pair >= 0.002:
		rise += pair * _boundary(p0, p2, q, (a2 - a0) * 0.5)
	pair = w0 * w3 * scale
	if pair >= 0.002:
		rise += pair * _boundary(p0, p3, q, (a3 - a0) * 0.5)
	pair = w1 * w2 * scale
	if pair >= 0.002:
		rise += pair * _boundary(p1, p2, q, (a2 - a1) * 0.5)
	pair = w1 * w3 * scale
	if pair >= 0.002:
		rise += pair * _boundary(p1, p3, q, (a3 - a1) * 0.5)
	pair = w2 * w3 * scale
	if pair >= 0.002:
		rise += pair * _boundary(p2, p3, q, (a3 - a2) * 0.5)
	# the ranges are rough: ridged noise rides on the uplift
	var ridged := _ridge.get_noise_3d(dir.x, dir.y, dir.z) * 0.5 + 0.5
	var rough := maxf(rise, 0.0) * (ridged * 1.1 - 0.35)
	# the plate interiors are not flat either: cratons, basins, plateaus
	var inside := _interior.get_noise_3d(dir.x, dir.y, dir.z) * variety
	return base + rise + rough + inside


## What the boundary between plates `a` (the nearer to `q`) and `b` does at `q`, which is `edge`
## radians from the line between them (on a's side).
func _boundary(a: int, b: int, q: Vector3, edge: float) -> float:
	var toward := _seeds[b] - _seeds[a]
	toward -= q * q.dot(toward)
	var push := 0.0
	if toward.length_squared() > 0.000001:
		var relative := _spin[a].cross(q) - _spin[b].cross(q)
		push = clampf(relative.dot(toward.normalized()), -1.0, 1.0)
	var together := maxf(push, 0.0)
	var apart := maxf(-push, 0.0)
	var edge_scaled := edge / BOUNDARY
	var near := exp(-edge_scaled * edge_scaled)
	var here: bool = _continental[a]
	var there: bool = _continental[b]
	if here and there:
		return near * (0.62 * together - 0.12 * apart) # a collision: the highest ranges
	if here != there:
		# a coast where one plate dives under the other: a coastal range on the land side and a
		# trench off shore, one smooth profile across the boundary
		var inland := edge if here else -edge
		var up_scaled := (inland - 0.03) / 0.045
		var range_up := 0.26 * exp(-up_scaled * up_scaled)
		var down_scaled := (inland + 0.03) / 0.035
		var trench := 0.30 * exp(-down_scaled * down_scaled)
		return together * (range_up - trench)
	# along a boundary the slow noise breaks the island arc into chains with gaps, and shifts the
	# mid-ocean ridge sideways in steps (the transform faults), so they are not one long clean line
	var along := _interior.get_noise_3d(q.x * 1.9, q.y * 1.9, q.z * 1.9)
	var steps := _interior.get_noise_3d(q.x * 1.9 + 7.0, q.y * 1.9 + 3.0, q.z * 1.9 + 1.0)
	var arc_scaled := (edge - 0.03) / 0.03
	var chain := smoothstep(-0.3, 0.25, along)
	var arc := 0.30 * together * chain * exp(-arc_scaled * arc_scaled) # an island arc
	var ridge_scaled := (edge - 0.04 * clampf(steps * 3.0, -1.0, 1.0)) / 0.09
	arc += 0.22 * apart * exp(-ridge_scaled * ridge_scaled) # a mid-ocean ridge
	return arc - 0.22 * together * near # and the trench beside it


## Which plate is at `dir` (for the map): (its number, radians to the nearest boundary, 1 if it is a
## continental plate else 0).
func plate_at(dir: Vector3) -> Vector3:
	var shifted := dir + Vector3(_warp.get_noise_3d(dir.x, dir.y, dir.z),
			_warp.get_noise_3d(dir.x + 5.3, dir.y - 2.1, dir.z + 1.7),
			_warp.get_noise_3d(dir.x - 3.7, dir.y + 4.4, dir.z - 6.2)) * WARP
	var q := shifted.normalized()
	var first := 0
	var best := -2.0
	var next := -2.0
	for index in _seeds.size():
		var closeness := q.dot(_seeds[index])
		if closeness > best:
			next = best
			best = closeness
			first = index
		elif closeness > next:
			next = closeness
	var edge := (acos(clampf(next, -1.0, 1.0)) - acos(clampf(best, -1.0, 1.0))) * 0.5
	return Vector3(first, edge, 1.0 if _continental[first] else 0.0)
