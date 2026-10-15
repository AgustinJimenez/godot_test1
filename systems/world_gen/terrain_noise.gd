class_name TerrainNoise
extends RefCounted
## The shape of the land: height, and what grows on it. Pure functions of (x, z) and the seed,
## so any chunk can be built alone and neighbours always agree on their shared edge.

enum Biome { BEACH, MEADOW, FOREST, ROCKY, SNOW, MARSH, DESERT }

var settings: WorldSettings
var _continent := FastNoiseLite.new()
var _hills := FastNoiseLite.new()
var _ridges := FastNoiseLite.new()
var _mountain_mask := FastNoiseLite.new()
var _warp := FastNoiseLite.new()
var _moisture := FastNoiseLite.new()
var _heat := FastNoiseLite.new()
var _detail := FastNoiseLite.new()
var _dunes := FastNoiseLite.new()
var _terraces := FastNoiseLite.new()
var _eroded: ErodedNoise
var rivers: WorldRivers


func _init(world_settings: WorldSettings) -> void:
	settings = world_settings
	var base_seed := settings.world_seed
	_setup(_continent, base_seed, 0.0016, 3)
	_setup(_hills, base_seed + 1, 0.009, 4)
	_setup(_ridges, base_seed + 2, 0.005, 4)
	_ridges.fractal_type = FastNoiseLite.FRACTAL_RIDGED
	_setup(_mountain_mask, base_seed + 3, 0.0021, 2)
	_setup(_warp, base_seed + 4, 0.004, 2)
	_setup(_moisture, base_seed + 5, 0.0032, 3)
	_setup(_heat, base_seed + 6, 0.0023, 2)
	_setup(_detail, base_seed + 7, 0.09, 2)
	_setup(_dunes, base_seed + 8, 0.03, 2)
	_dunes.fractal_type = FastNoiseLite.FRACTAL_RIDGED
	_setup(_terraces, base_seed + 9, 0.0028, 2)
	_eroded = ErodedNoise.new(base_seed)
	rivers = WorldRivers.new(self)
	for cz in range(-LAKE_PREPLAN, LAKE_PREPLAN + 1):
		for cx in range(-LAKE_PREPLAN, LAKE_PREPLAN + 1):
			_lakes[Vector2i(cx, cz)] = _plan_lake(Vector2i(cx, cz))
	for cz in range(-LAKE_PREPLAN + 1, LAKE_PREPLAN):
		for cx in range(-LAKE_PREPLAN + 1, LAKE_PREPLAN):
			_near_lakes[Vector2i(cx, cz)] = _gather_lakes(Vector2i(cx, cz))


func _setup(noise: FastNoiseLite, noise_seed: int, frequency: float, octaves: int) -> void:
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.seed = noise_seed
	noise.frequency = frequency
	noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	noise.fractal_octaves = octaves


const LAKE_CELL := 320.0 ## m: one cell of the lake grid holds at most one lake
const LAKE_CHANCE := 0.5
const RIM := 1.3 ## m the lake rim stands above the water
const LAKE_PREPLAN := 16 ## cells (each way) whose lakes are planned up front

var _lakes: Dictionary = {} # Vector2i cell -> {} (none) or {center, radius, level}
var _lake_lock := Mutex.new()
var _near_lakes: Dictionary = {} # cell -> its lakes and its neighbours', planned in _init


## Ground height in metres at a world position (lakes carved in).
func height(x: float, z: float) -> float:
	var h := base_height(x, z)
	for lake: Dictionary in lakes_near(x, z):
			var d := Vector2(x, z).distance_to(lake["center"] as Vector2) / float(lake["radius"])
			if d > 1.8:
				continue
			var level: float = lake["level"]
			if d <= 1.05: # the bowl: deep in the middle, rising to the rim
				h = lerpf(level - 3.0, level + RIM, smoothstep(0.35, 1.05, d))
			else: # outside: the land eases into the rim height (a berm on the downhill side)
				h = lerpf(h, maxf(level + RIM, minf(h, level + RIM + 6.0)), 1.0 - smoothstep(1.05, 1.8, d))
	return rivers.carve(x, z, h)


## Where the water stands: the sea, or the surface of a lake if (x, z) is inside one.
func water_level(x: float, z: float) -> float:
	for lake: Dictionary in lakes_near(x, z):
			if Vector2(x, z).distance_to(lake["center"] as Vector2) \
					< float(lake["radius"]) * 1.02:
				return lake["level"]
	var river := rivers.surface_at(x, z)
	return river if river > -INF else settings.sea_level


## The lakes (usually none) in the cell of (x, z) and its eight neighbours.
func lakes_near(x: float, z: float) -> Array:
	var cell := Vector2i(floori(x / LAKE_CELL), floori(z / LAKE_CELL))
	if absi(cell.x) < LAKE_PREPLAN and absi(cell.y) < LAKE_PREPLAN:
		return _near_lakes[cell]
	return _gather_lakes(cell)


func _gather_lakes(cell: Vector2i) -> Array:
	var found: Array = []
	for dz in range(-1, 2):
		for dx in range(-1, 2):
			var lake := lake_in(cell + Vector2i(dx, dz))
			if not lake.is_empty():
				found.append(lake)
	return found


## The lake of a grid cell ({} for none): a high, fairly level spot, away from the spawn.
func lake_in(cell: Vector2i) -> Dictionary:
	if absi(cell.x) <= LAKE_PREPLAN and absi(cell.y) <= LAKE_PREPLAN:
		return _lakes[cell] # planned in _init, never written again: no lock needed
	_lake_lock.lock()
	if not _lakes.has(cell):
		_lakes[cell] = _plan_lake(cell)
	var lake: Dictionary = _lakes[cell]
	_lake_lock.unlock()
	return lake


func _plan_lake(cell: Vector2i) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(Vector3i(settings.world_seed + 313, cell.x, cell.y))
	if rng.randf() > LAKE_CHANCE:
		return {}
	var center := (Vector2(cell) + Vector2(rng.randf_range(0.25, 0.75), rng.randf_range(0.25, 0.75))) \
			* LAKE_CELL
	var radius := rng.randf_range(24.0, 44.0)
	if center.length() < 90.0:
		return {}
	var rim := INF
	var middle := base_height(center.x, center.y)
	for index in 8: # the lowest point of the shore sets how high the water can stand
		var ring := center + Vector2.from_angle(TAU * float(index) / 8.0) * radius * 1.15
		rim = minf(rim, base_height(ring.x, ring.y))
	var level := minf(middle, rim) - 0.6
	if level < settings.sea_level + 4.0 or maxf(middle, rim) - minf(middle, rim) > 14.0:
		return {} # not high enough to be a mountain lake, or on a steep slope
	return {"center": center, "radius": radius, "level": level}


## The ground before lakes are carved.
func base_height(x: float, z: float) -> float:
	var warped_x := x + _warp.get_noise_2d(x, z) * 60.0
	var warped_z := z + _warp.get_noise_2d(x + 311.0, z - 97.0) * 60.0
	var land := _continent.get_noise_2d(warped_x, warped_z) # -1..1, the big shapes
	var rolling := _hills.get_noise_2d(warped_x, warped_z) * 0.22
	var mask := smoothstep(-0.12, 0.32, _mountain_mask.get_noise_2d(x, z))
	var peaks := (_ridges.get_noise_2d(warped_x, warped_z) * 0.5 + 0.5)
	var raw := land * 0.55 + rolling + mask * peaks * 0.95 * (0.4 + maxf(land, 0.0))
	var scale := settings.height_scale
	var h := settings.sea_level + (raw + 0.08) * scale
	# eroded detail: gullies and spurs, strongest in the mountains, gentle on the plains
	var relief := lerpf(0.12, 1.0, mask) * smoothstep(-2.0, 12.0, h - settings.sea_level)
	h += _eroded.height(x, z, 520.0) * settings.height_scale * 0.22 * relief
	# lakes and sea keep their shore soft, the deep parts are scooped a little
	if h < settings.sea_level:
		h = settings.sea_level + (h - settings.sea_level) * 0.7
	# deserts roll in dunes, rocky country steps up in terraces and mesas
	var inland := smoothstep(2.0, 8.0, h - settings.sea_level)
	var dry := smoothstep(0.5, 0.66, _heat.get_noise_2d(x, z) * 0.7 + 0.5) \
			* (1.0 - smoothstep(0.35, 0.55, moisture(x, z)))
	h += dry * inland * (_dunes.get_noise_2d(x, z) * 0.5 + 0.5 - 0.4) * 5.0
	var steps := smoothstep(0.1, 0.45, _terraces.get_noise_2d(x, z)) * inland
	var layer := 7.0
	var stepped := (floorf(h / layer) + smoothstep(0.3, 0.7, fposmod(h / layer, 1.0))) * layer
	h = lerpf(h, stepped, steps * 0.75)
	# a gentle, walkable area around the origin
	var spawn := 1.0 - smoothstep(settings.spawn_flat_radius * 0.5, settings.spawn_flat_radius * 2.2,
			Vector2(x, z).length())
	return lerpf(h, settings.sea_level + 3.0 + rolling * 6.0, spawn)


## Slope of the ground (0 flat .. 1 vertical) from the height around a point.
func slope(x: float, z: float, step: float = 1.5) -> float:
	var dx := height(x + step, z) - height(x - step, z)
	var dz := height(x, z + step) - height(x, z - step)
	return clampf(Vector2(dx, dz).length() / (step * 2.0), 0.0, 1.0)


## 0 dry .. 1 wet.
func moisture(x: float, z: float) -> float:
	return clampf(_moisture.get_noise_2d(x, z) * 0.9 + 0.5, 0.0, 1.0)


## 0 cold .. 1 hot (also colder with height).
func heat(x: float, z: float, ground: float) -> float:
	var warmth := _heat.get_noise_2d(x, z) * 0.7 + 0.5
	return clampf(warmth - maxf(ground - settings.sea_level, 0.0) / settings.height_scale * 0.9,
			0.0, 1.0)


## Fine variation 0..1, for colour speckle and jitter.
func detail(x: float, z: float) -> float:
	return _detail.get_noise_2d(x, z) * 0.5 + 0.5


func biome(x: float, z: float, ground: float, steepness: float) -> Biome:
	var above := ground - water_level(x, z)
	if above < 1.4:
		return Biome.BEACH if moisture(x, z) < 0.62 else Biome.MARSH
	var warmth := heat(x, z, ground)
	if above > settings.height_scale * 0.62 and warmth < 0.55:
		return Biome.SNOW
	if steepness > 0.62 or above > settings.height_scale * 0.5:
		return Biome.ROCKY
	var wet := moisture(x, z)
	if warmth > 0.52 and wet < 0.5:
		return Biome.DESERT
	return Biome.FOREST if wet > 0.5 else Biome.MEADOW
