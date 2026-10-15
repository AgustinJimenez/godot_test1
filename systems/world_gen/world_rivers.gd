class_name WorldRivers
extends RefCounted
## Rivers that run downhill. Each "source" (at most one per 512 m cell, in the high ground) is
## followed down the steepest way, with a little wandering, until it reaches the sea, a hollow, or
## 1.8 km. The water surface of a river never rises along its way, it widens downstream, and the
## land around it is carved into a channel with banks. Everything comes from the terrain function
## and the seed, so any tile can ask "is there a river here?" and always get the same answer; the
## traces are made on first use and kept.

const CELL := 512.0 ## m: one possible source per cell
const REACH := 4 ## cells around a tile whose sources can reach it
const STEP := 18.0 ## m between points of a trace
const MAX_STEPS := 100
const BUCKET := 64.0
const CHANCE := 0.7
const DEPTH := 0.7 ## m the bed lies under the water surface
const FLOW_SPEED := 1.6 ## m/s of the current at the river's mouth

var _noise: TerrainNoise
var _lock := Mutex.new()
var _traced: Dictionary = {} # source cell -> true
var _ensured: Dictionary = {} # cell -> true once every source around it is traced
var _buckets: Dictionary = {} # Vector2i -> Array of segments
# a segment: [a Vector2, b Vector2, surface_a, surface_b, width_a, width_b]


func _init(noise: TerrainNoise) -> void:
	_noise = noise


## `h` (the land height at x, z) with the river channel cut into it, if a river is near.
func carve(x: float, z: float, h: float) -> float:
	var near := nearest(x, z)
	if near.is_empty():
		return h
	var width: float = near["width"]
	var distance: float = near["distance"]
	if distance > width * 2.6:
		return h
	var surface: float = near["surface"]
	var bed := surface - DEPTH
	var bank := smoothstep(width, width * 2.6, distance)
	return lerpf(bed, maxf(h, surface + 0.45), bank) if distance > width else bed


## Where the water stands at (x, z) if it is on a river, else -INF.
func surface_at(x: float, z: float) -> float:
	var near := nearest(x, z)
	if not near.is_empty() and float(near["distance"]) < float(near["width"]):
		return near["surface"]
	return -INF


## Direction and speed of the current at (x, z) (zero off the river).
func flow_at(x: float, z: float) -> Vector2:
	var near := nearest(x, z)
	if near.is_empty() or float(near["distance"]) > float(near["width"]):
		return Vector2.ZERO
	return (near["direction"] as Vector2) * FLOW_SPEED * clampf(float(near["width"]) / 8.0, 0.4, 1.2)


## The closest river point: {distance, surface, width, direction} or {} when none is within 40 m.
func nearest(x: float, z: float) -> Dictionary:
	_lock.lock()
	_ensure(Vector2i(floori(x / CELL), floori(z / CELL)))
	var best := {}
	var best_distance := INF
	var point := Vector2(x, z)
	# every segment is filed under all buckets within 40 m of it, so the own bucket is enough
	var segments: Array = _buckets.get(Vector2i(floori(x / BUCKET), floori(z / BUCKET)), [])
	for segment: Array in segments:
				var a: Vector2 = segment[0]
				var b: Vector2 = segment[1]
				var along := clampf((point - a).dot(b - a) / maxf((b - a).length_squared(), 0.0001),
						0.0, 1.0)
				var distance := point.distance_to(a.lerp(b, along))
				if distance < best_distance:
					best_distance = distance
					best = {"distance": distance,
							"surface": lerpf(float(segment[2]), float(segment[3]), along),
							"width": lerpf(float(segment[4]), float(segment[5]), along),
							"direction": (b - a).normalized()}
	_lock.unlock()
	return best


## Every segment in the square tile at `origin` of `size` metres (for building its water).
func segments_in(origin: Vector2, size: float) -> Array:
	_lock.lock()
	_ensure(Vector2i(floori((origin.x + size * 0.5) / CELL), floori((origin.y + size * 0.5) / CELL)))
	var found: Array = []
	var seen := {}
	for bz in range(floori(origin.y / BUCKET) - 1, floori((origin.y + size) / BUCKET) + 2):
		for bx in range(floori(origin.x / BUCKET) - 1, floori((origin.x + size) / BUCKET) + 2):
			for segment: Array in _buckets.get(Vector2i(bx, bz), []):
				if not seen.has(segment):
					seen[segment] = true
					found.append(segment)
	_lock.unlock()
	return found


## Called with the lock held: traces every source that could reach `cell`.
func _ensure(cell: Vector2i) -> void:
	if _ensured.has(cell):
		return
	for dz in range(-REACH, REACH + 1):
		for dx in range(-REACH, REACH + 1):
			var source := cell + Vector2i(dx, dz)
			if not _traced.has(source):
				_traced[source] = true
				_trace(source)
	_ensured[cell] = true


func _trace(cell: Vector2i) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(Vector3i(_noise.settings.world_seed + 4001, cell.x, cell.y))
	if rng.randf() > CHANCE:
		return
	var position := (Vector2(cell) + Vector2(rng.randf_range(0.1, 0.9), rng.randf_range(0.1, 0.9))) \
			* CELL
	var sea := _noise.settings.sea_level
	var height := _noise.base_height(position.x, position.y)
	if height < sea + 10.0 or height > sea + 80.0 or position.length() < 60.0:
		return
	var heading := Vector2.ZERO
	var surface := height - 0.4
	var width := 2.2
	for step in MAX_STEPS:
		# downhill: the slope from three samples, plus a little wander so rivers meander
		var h1 := _noise.base_height(position.x + 8.0, position.y)
		var h2 := _noise.base_height(position.x, position.y + 8.0)
		var gradient := Vector2(h1 - height, h2 - height) / 8.0
		if gradient.length() < 0.004 and step > 4:
			break # flat: a hollow, the river ends
		var down := -gradient.normalized() if gradient.length() > 0.0001 else heading
		var wander := Vector2(-down.y, down.x) * sin(float(step) * 0.55 + rng.randf() * 0.2) * 0.35
		heading = (heading * 0.55 + (down + wander) * 0.45).normalized() if heading != Vector2.ZERO \
				else down
		var next := position + heading * STEP
		var next_height := _noise.base_height(next.x, next.y)
		var next_surface := minf(surface, next_height - 0.35)
		width = minf(width + 0.07, 10.0)
		_add_segment(position, next, surface, next_surface, width - 0.07, width)
		position = next
		height = next_height
		surface = next_surface
		if height <= sea + 0.3:
			break # reached the sea


func _add_segment(a: Vector2, b: Vector2, surface_a: float, surface_b: float, width_a: float,
		width_b: float) -> void:
	var segment := [a, b, surface_a, surface_b, width_a, width_b]
	var margin := 40.0
	var low := Vector2i(floori((minf(a.x, b.x) - margin) / BUCKET),
			floori((minf(a.y, b.y) - margin) / BUCKET))
	var high := Vector2i(floori((maxf(a.x, b.x) + margin) / BUCKET),
			floori((maxf(a.y, b.y) + margin) / BUCKET))
	for bz in range(low.y, high.y + 1):
		for bx in range(low.x, high.x + 1):
			var key := Vector2i(bx, bz)
			if not _buckets.has(key):
				_buckets[key] = []
			(_buckets[key] as Array).append(segment)
