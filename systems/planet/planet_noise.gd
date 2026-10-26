class_name PlanetNoise
extends RefCounted
## The shape and climate of a planet: height, rain, warmth and biome at any direction from its
## centre. The land comes from tectonic plates (PlanetTectonics) at the scale of the planet and
## from noise below that; the climate from latitude, height and the winds (PlanetClimate). Pure
## functions of the direction and the seed, so any tile can be built alone and neighbours agree on
## their shared edge, and there are no seams or poles to pinch.

const SPAWN_ABOVE_SEA := 3.0 ## m: the lowest ground the character may start on
const SPAWN_FROM_WATER := 6.0 ## m from a river or a lake
const LAPSE := 6.5 ## degrees C lost per km of height
const EARTH_RELIEF := 8800.0 ## m: what "one relief" is on Earth

var settings: PlanetSettings
var relief := 1000.0 ## m, from the sea to the top of the highest ranges (see PlanetSettings)
var tectonics: PlanetTectonics
var climate := PlanetClimate.new()
var species: SpeciesRegistry ## the plants of this planet
var weather: PlanetWeather ## the clouds and the weather (made once the climate is)
var clock: PlanetClock ## the time of day and the season (set by PlanetWorld; null: the yearly mean)
var clearing := Vector3.ZERO ## where the player starts: trees and rocks keep off a little round it
var rock: PlanetRock ## the colour of the crust
## the native plant placement (PlanetScatterNative), or null: PlanetScatter's loops run
var scatter_native: Object
var native: Object ## the native crust (PlanetCrustNative), or null: this file is the reference
var water_native: Object ## pure native tile-water geometry; null uses PlanetTile's script fallback
var drainage: PlanetDrainage ## where the water runs (coarse), when the planet has it
## The heights of the whole planet's map passes, by the picture's size (the map's layers all
## read the same ones, so only the first of them pays for the heights)
var map_heights := {}

var _rolling := FastNoiseLite.new()
var _ranges := FastNoiseLite.new()
var _range_mask := FastNoiseLite.new()
var _hills := FastNoiseLite.new()
var _gullies := FastNoiseLite.new()
var _detail := FastNoiseLite.new()
var _massif := FastNoiseLite.new() # ranges and massifs, tens of km across on an Earth
var _chain := FastNoiseLite.new() # the mountain chains, a hundred km and more
var _valleys: Array[FastNoiseLite] = [] # three scales of valley networks (the work of erosion)
var _valley_depth: Array[float] = []
var _foothills := FastNoiseLite.new() # the ridges and spurs between them, a fifth of that
var _sea := 0.0 ## the height (units of relief) that is sea level, so the ocean covers its share


## PLANET_TIMING=1 prints how long each step of making a planet takes.
var _lap_at := 0


func _lap(what: String) -> void:
	if OS.has_environment("PLANET_TIMING"):
		var now := Time.get_ticks_msec()
		print("PLANET_TIMING %-22s %5d ms" % [what, now - _lap_at])
		_lap_at = now


func _init(planet_settings: PlanetSettings) -> void:
	_lap_at = Time.get_ticks_msec()
	settings = planet_settings
	relief = settings.relief
	if relief <= 0.0:
		relief = clampf(settings.radius * 0.0035, 300.0, 12000.0)
	tectonics = PlanetTectonics.create(settings.world_seed, settings.plates)
	rock = PlanetRock.create(tectonics, settings.world_seed, settings.radius, relief)
	_lap("plates and rock")
	species = SpeciesRegistry.new(settings.world_seed, settings.species_count)
	StarLight.apply(species.species, Star.from_mass(settings.star_mass), settings.star_readability)
	for one in species.species: # a planet has many plants: more looks of each tree
		if one.is_tree():
			one.variants = 6
		elif one.variants < 3:
			one.variants = 3
	_lap("species")
	_setup(_rolling, settings.world_seed + 2, 0.0004, 3)
	_setup(_ranges, settings.world_seed + 4, 1.0 / (settings.radius * 0.18), 5)
	_ranges.fractal_type = FastNoiseLite.FRACTAL_RIDGED
	_setup(_range_mask, settings.world_seed + 5, 1.0 / (settings.radius * 0.5), 2)
	_setup(_hills, settings.world_seed + 1, 0.0022, 4)
	_setup(_gullies, settings.world_seed + 3, 0.0018, 4)
	_gullies.fractal_type = FastNoiseLite.FRACTAL_RIDGED
	_setup(_detail, settings.world_seed + 7, 0.09, 2)
	var massif_length := clampf(settings.radius * 0.005, 800.0, 40000.0)
	_setup(_massif, settings.world_seed + 11, 1.0 / massif_length, 5)
	_massif.fractal_type = FastNoiseLite.FRACTAL_RIDGED
	var valley_length := clampf(settings.radius * 0.02, 600.0, 120000.0)
	for scale_index in 3:
		var valley := FastNoiseLite.new()
		var length := valley_length / pow(4.0, float(scale_index))
		_setup(valley, settings.world_seed + 21 + scale_index, 1.0 / maxf(length, 150.0), 3)
		_valleys.append(valley)
		_valley_depth.append(minf(length * 0.05, relief * 0.06) * pow(0.5, float(scale_index)))
	_setup(_chain, settings.world_seed + 17, 1.0 / clampf(settings.radius * 0.02, 1500.0, 200000.0), 4)
	_chain.fractal_type = FastNoiseLite.FRACTAL_RIDGED
	_setup(_foothills, settings.world_seed + 13, 5.0 / massif_length, 4)
	_foothills.fractal_type = FastNoiseLite.FRACTAL_RIDGED
	_lap("noises")
	_make_native() # (twice: the first only to find the sea level with, the second knows it)
	_find_sea_level()
	_make_native()
	_lap("sea level")
	climate.build(self)
	if native != null:
		native.call(&"set_climate", climate.temperature_grid(), PlanetClimate.WIDTH,
				PlanetClimate.HEIGHT, climate.rain_grid())
	_make_scatter()
	_lap("climate")
	weather = PlanetWeather.create(self)
	_lap("weather")
	_carve_valleys()
	_lap("drainage")


## The native plant placement, with the species and the climate it reads.
func _make_scatter() -> void:
	scatter_native = null
	if native == null or OS.has_environment("PLANET_NO_NATIVE") \
			or not ClassDB.class_exists(&"PlanetScatterNative"):
		return
	var kinds := {}
	for kind: int in FloraMeshes.VARIANTS:
		kinds[kind] = FloraMeshes.VARIANTS[kind]
	var made: Object = ClassDB.instantiate(&"PlanetScatterNative")
	made.call(&"setup", {
		"crust": native, "species": PlanetScatter.species_table(species),
		"temperature": climate.temperature_grid(), "rain": climate.rain_grid(),
		"width": PlanetClimate.WIDTH, "height": PlanetClimate.HEIGHT, "relief": relief,
		"radius": settings.radius, "plant_density": settings.plant_density,
		"rock_density": settings.rock_density, "world_seed": settings.world_seed,
		"kind_variants": kinds})
	scatter_native = made


## Fixed hot spots in the mantle (unit directions, from the seed): as a plate drifts over one, a
## chain of volcanoes is left on it (the native crust draws the seamounts and the islands).
func _hotspots() -> PackedVector3Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = settings.world_seed + 61
	var spots := PackedVector3Array()
	for index in 9:
		spots.append(Vector3(rng.randfn(), rng.randfn(), rng.randfn()).normalized())
	return spots


## Hands the crust's numbers to the native class, when its library is there (native/planet_crust,
## see its README). The GDScript below stays the reference: `PLANET_NO_NATIVE=1` turns this off and
## `planet_lab --native-check` compares the two.
func _make_native() -> void:
	native = null
	water_native = null
	if OS.has_environment("PLANET_NO_NATIVE"):
		return
	if not ClassDB.class_exists(&"PlanetCrustNative"):
		print("The native planet crust is not built here: the planet runs on the slower script and has"
				+ " no river valleys (scripts/setup_native.sh builds it).")
		return
	var valley_configs: Array = []
	for valley in _valleys:
		valley_configs.append(noise_config(valley))
	var depths := PackedFloat32Array()
	for depth in _valley_depth:
		depths.append(depth)
	var made: Object = ClassDB.instantiate(&"PlanetCrustNative")
	made.call(&"setup", {
		"seeds": tectonics._seeds, "spins": PackedVector3Array(tectonics._spin),
		"continental": PackedByteArray(tectonics._continental.map(func(land: bool) -> int:
				return 1 if land else 0)),
		"continent": PlanetTectonics.get_continent(), "ocean": PlanetTectonics.get_ocean(),
		"boundary": PlanetTectonics.get_boundary(), "soft": PlanetTectonics.get_soft(),
		"radius": settings.radius, "relief": relief, "sea": _sea,
		"shore": SHORE, "shore_flat": SHORE_FLAT, "land_curve": LAND_CURVE, "deep": DEEP,
		"massif_scale": MASSIF, "chain_scale": CHAINS, "foothill_scale": FOOTHILLS,
		"erosion": 0.0 if OS.has_environment("PLANET_NO_EROSION") else EROSION,
		"erosion_seed": settings.world_seed + 41, "erosion_octaves": EROSION_OCTAVES,
		"hotspots": _hotspots(),
		"erosion_wavelength": clampf(settings.radius * 0.005, 800.0, 40000.0) * EROSION_SCALE,
		"valley_width": VALLEY_WIDTH, "valley_depths": depths,
		"rock_boundary": PlanetRock.get_boundary(), "rock_colours": PlanetRock.colours(),
		"warp": noise_config(tectonics._warp), "ridge": noise_config(tectonics._ridge),
		"interior": noise_config(tectonics._interior), "rolling": noise_config(_rolling),
		"ranges": noise_config(_ranges), "range_mask": noise_config(_range_mask),
		"hills": noise_config(_hills), "gullies": noise_config(_gullies),
		"detail": noise_config(_detail), "massif": noise_config(_massif),
		"chain": noise_config(_chain), "foothills": noise_config(_foothills),
		"faces": _cube_faces(), "valleys": valley_configs, "craton": noise_config(rock._craton),
		"basin": noise_config(rock._basin),
	})
	native = made
	if ClassDB.class_exists(&"PlanetWaterNative"):
		water_native = ClassDB.instantiate(&"PlanetWaterNative")


func _cube_faces() -> PackedVector3Array:
	var faces := PackedVector3Array()
	for face: Array in PlanetTile.FACES:
		for axis: Vector3 in face:
			faces.append(axis)
	return faces


## The river valleys of the planet, from where its water runs: the drainage is solved on a coarse
## grid and its rivers, as curves, go to the native crust, which cuts the valleys along them.
func _carve_valleys() -> void:
	drainage = null
	if native == null or settings.drainage_cells <= 0 or OS.has_environment("PLANET_NO_DRAINAGE"):
		return
	var cell_metres := settings.radius * PI * 0.5 / float(settings.drainage_cells)
	var kept := ({} if OS.has_environment("PLANET_NO_DRAINAGE_CACHE")
			else PlanetDrainageCache.load_network(settings))
	if not kept.is_empty():
		_lap("drainage from the cache")
		native.call(&"set_rivers", settings.drainage_cells, kept, cell_metres)
		drainage = PlanetDrainage.new() # (nothing but its being there: the rivers are the crust's now)
		drainage.cells = settings.drainage_cells
		return
	var solved := PlanetDrainage.new()
	_lap("native setup")
	if not solved.build(self, settings.drainage_cells):
		return
	_lap("drainage solve")
	var network := solved.network()
	_lap("river network")
	native.call(&"set_rivers", settings.drainage_cells, network, cell_metres)
	drainage = solved
	if not OS.has_environment("PLANET_NO_DRAINAGE_CACHE"):
		PlanetDrainageCache.save_network(settings, network)
		_lap("drainage cache written")


func noise_config(source: FastNoiseLite) -> Array:
	return [source.seed, source.frequency, source.fractal_octaves, int(source.fractal_type)]


## The level of the river or lake water at `dir` where `ground` is under it, else -INF (the native
## crust knows the rivers).
func water_at(dir: Vector3, ground: float) -> float:
	if native != null and native.has_method(&"water_at"):
		var level: float = native.call(&"water_at", dir, ground)
		return level if level > -1.0e20 else -INF
	return -INF


## True if river or lake water is within `margin` metres of `dir`.
func near_water(dir: Vector3, ground: float, margin: float) -> bool:
	return native != null and native.has_method(&"near_water") 			and native.call(&"near_water", dir,
			ground, margin)


## The current of the river at `dir` (planet space, m/s), zero out of a river.
func flow_at(dir: Vector3) -> Vector3:
	if native != null and native.has_method(&"flow_at"):
		return native.call(&"flow_at", dir)
	return Vector3.ZERO


## The ground heights at many directions at once (native when it can: no rivers cut in).
func heights_of(dirs: PackedVector3Array) -> PackedFloat32Array:
	if native != null:
		return native.call(&"heights", dirs)
	var result := PackedFloat32Array()
	result.resize(dirs.size())
	for index in dirs.size():
		result[index] = height(dirs[index].x, dirs[index].y, dirs[index].z)
	return result


## The macro heights a map pixel of `pixel` metres can show (the finer detail left out).


## The heights before the rivers are cut, the sign of which says land or sea (the weather asks),
## at many directions at once (native when it can).
func macro_heights_of(dirs: PackedVector3Array, pixel := -1.0) -> PackedFloat32Array:
	if pixel >= 0.0 and native != null and native.has_method(&"broad_heights"):
		return native.call(&"broad_heights", dirs, pixel)
	if native != null:
		return native.call(&"macro_heights", dirs)
	var result := PackedFloat32Array()
	result.resize(dirs.size())
	for index in dirs.size():
		result[index] = macro_height(dirs[index].x, dirs[index].y, dirs[index].z)
	return result


## The crust colours at many directions at once, with each one's ground height and steepness.
func colours_of(dirs: PackedVector3Array, grounds: PackedFloat32Array,
		steeps: PackedFloat32Array) -> PackedColorArray:
	if native != null:
		return native.call(&"colours", dirs, grounds, steeps)
	var result := PackedColorArray()
	result.resize(dirs.size())
	for index in dirs.size():
		result[index] = _facet_color(dirs[index].x, dirs[index].y, dirs[index].z, grounds[index],
				steeps[index])
	return result


func _setup(noise: FastNoiseLite, noise_seed: int, frequency: float, octaves: int) -> void:
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.seed = noise_seed
	noise.frequency = frequency
	noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	noise.fractal_octaves = octaves


## The sea level is wherever the heights have the planet's ocean share below it (sampled over the
## sphere, every sample weighing the same area).
func _find_sea_level() -> void:
	if native != null:
		_sea = native.call(&"find_sea_level", settings.crust_samples, settings.ocean_fraction,
				settings.water_layer, relief)
		return
	var count := maxi(settings.crust_samples, 500)
	var spots := PackedVector3Array()
	for index in count:
		var y := 1.0 - 2.0 * (float(index) + 0.5) / float(count)
		var ring := sqrt(1.0 - y * y)
		var angle := float(index) * 2.399963
		spots.append(Vector3(cos(angle) * ring, y, sin(angle) * ring))
	var samples := PackedFloat32Array() # the plates' height at the spots (native when it is there)
	if native != null:
		samples = native.call(&"tectonic_heights", spots)
	else:
		for spot in spots:
			samples.append(tectonics.height(spot))
	samples.sort()
	if settings.water_layer <= 0.0:
		_sea = samples[clampi(int(settings.ocean_fraction * float(count)), 0, count - 1)]
		return
	# the planet has an amount of water: fill the low ground up to the level that holds it
	var low := samples[0]
	var high := samples[count - 1]
	for step in 40:
		var level := (low + high) * 0.5
		var depth := 0.0 # the mean depth of the water over the whole planet at this level (m)
		for value in samples:
			if value < level:
				depth -= _shore(value - level) * relief
		depth /= float(count)
		if depth < settings.water_layer:
			low = level
		else:
			high = level
	_sea = (low + high) * 0.5


## Ground height in metres above the sea, in the unit direction (x, y, z), rivers cut in.
func height(x: float, y: float, z: float) -> float:
	if native != null and native.has_method(&"height_at"):
		# (the native crust is the ground: it has the eroded ridges the script below does not)
		return native.call(&"height_at", Vector3(x, y, z))
	return base_height(x, y, z)


## The ground before the rivers are cut in.
func base_height(x: float, y: float, z: float) -> float:
	var units := _units(x, y, z)
	var p := Vector3(x, y, z) * settings.radius
	var hills := _hills.get_noise_3d(p.x, p.y, p.z) * clampf(relief * 0.04, 14.0, 45.0)
	var ground := _macro(units, p) + hills * smoothstep(0.01, 0.12, units)
	# the high ground is cut by gullies and spurs, as if water had run down it for ages
	var high := smoothstep(0.12, 0.45, units)
	var gully_depth := minf(relief * 0.05, 90.0)
	ground += _gullies.get_noise_3d(p.x, p.y, p.z) * 0.5 * gully_depth * high
	# hard and soft layers of rock weather into ledges and steps
	var layer := clampf(relief * 0.025, 8.0, 40.0)
	var steps := floorf(ground / layer) + smoothstep(0.15, 0.85, fposmod(ground / layer, 1.0))
	ground = lerpf(ground, steps * layer, smoothstep(0.3, 0.6, units) * 0.35)
	if units > 0.0 and ground < 8.0: # the hills and gullies must not dip an inland basin below the sea
		var ice := smoothstep(-2.0, -8.0, climate.sea_temperature(p / settings.radius)
				- 0.0065 * maxf(ground, 0.0))
		var bowl := 8.0 * exp((ground - 8.0) / 60.0)
		var keep := 1.0 - ice * smoothstep(0.12, 0.02, units) # (fjords stay below the sea)
		ground += (bowl - ground) * smoothstep(0.0, 0.1, units) * keep
	return ground


## How deep the valleys cut at `p` (m): where a slow noise crosses zero it makes a line, and a
## valley follows each line, three scales of them, the biggest the deepest. The lowland and the
## shelf are left alone; the upland is cut the most. (Not a simulation of water: it is the look of
## drainage, the same at any planet size and cheap enough for every vertex.)
## `glacial` (0..1): where ice has filled the valleys they are wide with a flat floor and steep
## walls (a U), not a V.
func _valley_cut(p: Vector3, units: float, glacial := 0.0) -> float:
	var upland := smoothstep(0.03, 0.25, units)
	if upland <= 0.0:
		return 0.0
	var cut := 0.0
	for index in _valleys.size():
		var line := absf(_valleys[index].get_noise_3d(p.x, p.y, p.z))
		var valley_floor := 1.0 - smoothstep(0.0, VALLEY_WIDTH * (1.0 + 1.2 * glacial), line)
		cut += _valley_depth[index] * (1.0 + 0.6 * glacial) \
				* pow(valley_floor, lerpf(1.5, 0.5, glacial))
	return cut * upland * 0.3 # (as in the native crust: shallow)


## The ground without the smallest hills: what the water sees when it picks its way to the sea.
func macro_height(x: float, y: float, z: float) -> float:
	return _macro(_units(x, y, z), Vector3(x, y, z) * settings.radius)


func _macro(units: float, p: Vector3) -> float:
	var rolling := _rolling.get_noise_3d(p.x, p.y, p.z) * clampf(relief * 0.12, 25.0, 120.0)
	# ranges of mountains inside the continents, away from the plate edges (old folded belts)
	var belt := smoothstep(0.0, 0.5, _range_mask.get_noise_3d(p.x, p.y, p.z) + 0.15)
	var ridges := (_ranges.get_noise_3d(p.x, p.y, p.z) * 0.5 + 0.5) * relief * 0.22
	ridges *= belt * smoothstep(0.08, 0.4, units)
	# the massifs and foothills: rough ground that grows with the height of the plates' uplift, so
	# the mountain belts are rugged and the old plains stay gentle
	var rugged := smoothstep(0.0, 0.25, units)
	var massifs := (_massif.get_noise_3d(p.x, p.y, p.z) * 0.5 + 0.0) * relief * MASSIF * rugged
	var chains := (_chain.get_noise_3d(p.x, p.y, p.z) * 0.5 + 0.0) * relief * CHAINS * rugged
	var spurs := (_foothills.get_noise_3d(p.x, p.y, p.z) * 0.5 + 0.0) * relief * FOOTHILLS * rugged
	# erosion has cut valley networks into the upland, small ones into big ones (the water sees them)
	var shore := _shore(units) * relief
	var coast := smoothstep(0.01, 0.12, units) # (the rolling hills fade in inland: a clean shore)
	var raised := shore + rolling * coast + ridges + chains + massifs + spurs
	# the valleys never cut below the sea: near the coast they only cut what stands above it
	# where it is cold enough for permanent ice the valleys are glaciated (see _valley_cut)
	var cold := climate.sea_temperature(p / settings.radius) - 0.0065 * maxf(raised, 0.0)
	var glacial := smoothstep(-2.0, -8.0, cold)
	# a fjord: where a glaciated valley reaches the coast it may cut below the sea
	var coastal := smoothstep(0.12, 0.02, units)
	var allowed := maxf(shore, 0.0) * 0.8 + glacial * coastal * relief * 0.12
	var result := raised - minf(_valley_cut(p, units, glacial), allowed)
	if result > 0.0: # the land's heights follow a hypsometric curve: most of it low, the peaks kept
		var pivot := relief * HYPSO_PIVOT
		result = pivot * pow(result / pivot, HYPSO)
	if units > 0.0 and result < 8.0: # a basin below the sea is a shallow bowl (no puddles inland)
		var bowl := 8.0 * exp((result - 8.0) / 60.0)
		result += (bowl - result) * smoothstep(0.0, 0.1, units) * (1.0 - glacial * coastal)
	return result


## Beaches and shallows: the ground eases toward the sea instead of dropping into it. The slope is a
## fifth of the plates' right at the sea and grows to the plates' own over `SHORE` of the relief
## (this is that slope integrated, so it never gets steeper than the plates are, as scaling the
## height by a factor does).
const SHORE := 0.2
const VALLEY_WIDTH := 0.09 ## of the noise's range either side of its zero line
const CHAINS := 0.5 ## of the relief: the chains of mountains, the broadest rough ground
const MASSIF := 0.15 ## of the relief: the height of the massifs on the roughest ground
const FOOTHILLS := 0.0 ## and of the foothills (the eroded ridges took their place)
const EROSION := 0.20 ## of the relief: the eroded ridges (native only; 0 turns them off)
const EROSION_OCTAVES := 9
const EROSION_SCALE := 1.1 ## of the massifs' length: the first wavelength of the eroded ridges
const HYPSO := 1.4 ## land heights h become pivot * (h / pivot) ^ this: low ground lower, peaks kept
const HYPSO_PIVOT := 0.5 ## of the relief
const LAND_CURVE := 1.6 ## the land's height share is raised to this: plains common, plateaus rare
const DEEP := 1.6 ## how much deeper the ocean floor is than the plates' slope alone (abyssal depth)
const SHORE_FLAT := 0.16


func _shore(units: float) -> float:
	var reach := absf(units) / SHORE
	var eased := reach * reach * reach * (1.0 - reach * 0.5) if reach < 1.0 else reach - 0.5
	var raw := signf(units) * (SHORE_FLAT * absf(units) + (1.0 - SHORE_FLAT) * SHORE * eased)
	if units > 0.0: # most of the land is low: a hypsometric curve (the high ground is the rare part)
		raw = pow(raw, LAND_CURVE)
	if units < 0.0: # the sea floor drops away past the shelf toward the abyssal plains
		raw *= 1.0 + DEEP * smoothstep(0.05, 0.3, -units)
	return raw


func _units(x: float, y: float, z: float) -> float:
	return tectonics.height(Vector3(x, y, z)) - _sea


## 0 dry .. 1 wet.
func moisture(x: float, y: float, z: float) -> float:
	return clampf(climate.sample(Vector3(x, y, z)).y / 1.2, 0.0, 1.0)


## 0 cold .. 1 hot (the temperature at `ground` metres, see `temperature`).
func heat(x: float, y: float, z: float, ground: float) -> float:
	return clampf((temperature(x, y, z, ground) + 20.0) / 55.0, 0.0, 1.0)


## Degrees C at the direction and height: the latitude's sea level warmth minus the lapse rate. A
## tall range of a small planet is as cold on top as a tall range of a big one (height is taken as
## a share of the planet's relief).
func temperature(x: float, y: float, z: float, ground: float) -> float:
	var sea_level := climate.sample(Vector3(x, y, z)).x
	return sea_level - maxf(ground, 0.0) / relief * EARTH_RELIEF / 1000.0 * LAPSE


## Degrees C right now at the direction and height: the season (the cycle PlanetSeasons made,
## read at the clock's share of the year) and the time of day (warmest in the early afternoon, more
## so over land and under a clear sky), minus the lapse rate. With no clock it is the yearly mean.
func temperature_now(x: float, y: float, z: float, ground: float,
		at_clock: PlanetClock = null, macro := NAN) -> float:
	var which := at_clock if at_clock != null else clock
	if which == null:
		return temperature(x, y, z, ground)
	var dir := Vector3(x, y, z)
	var degrees := climate.seasons.at(dir, which.year_share())
	# (`macro`: the height before the rivers, when the caller has it already, as a map row does)
	var land := (macro if not is_nan(macro) else macro_height(x, y, z)) >= 0.0
	var swing := 6.0 if land else 0.8
	var hour := which.local_hour(dir)
	var clear := clampf(which.day_length(asin(y)) * 2.0 + 0.3, 0.3, 1.0)
	degrees += swing * cos((hour - 14.5) / 24.0 * TAU) * clear
	return degrees - maxf(ground, 0.0) / relief * EARTH_RELIEF / 1000.0 * LAPSE


## Fine variation 0..1, for colour speckle.
func detail(x: float, y: float, z: float) -> float:
	var p := Vector3(x, y, z) * settings.radius
	return _detail.get_noise_3d(p.x, p.y, p.z) * 0.5 + 0.5


## Fine variation 0..1 at a made-up point (patches of one plant species).
func detail_at(point: Vector3) -> float:
	return _detail.get_noise_3d(point.x, point.y, point.z) * 0.5 + 0.5


func biome(x: float, y: float, z: float, ground: float, steepness: float) -> TerrainNoise.Biome:
	var wet := moisture(x, y, z)
	if ground < 1.4:
		return TerrainNoise.Biome.BEACH if wet < 0.5 else TerrainNoise.Biome.MARSH
	var degrees := temperature(x, y, z, ground)
	if degrees < -14.0:
		return TerrainNoise.Biome.SNOW
	if steepness > 0.62 or ground > relief * 0.5:
		return TerrainNoise.Biome.ROCKY
	if wet < 0.2 and degrees > 2.0:
		return TerrainNoise.Biome.DESERT
	return TerrainNoise.Biome.FOREST if wet > 0.5 else TerrainNoise.Biome.MEADOW


## The colour of a ground facet: the rock of the crust there (PlanetRock), nothing grows on it yet.
func _facet_color(x: float, y: float, z: float, ground: float, steep: float,
		coarse := false) -> Color:
	var speckle := 0.5 if coarse else detail(x, y, z) # (a map's pixels of many metres: no fine grain)
	var here := Vector3(x, y, z)
	return rock.colour(here, ground, steep, speckle, climate.sea_temperature(here), not coarse,
			climate.sample(here).y)


## True where a person can stand: dry land well above the sea, not in a lake or a river or at the
## edge of one, and not on a steep slope (a cliff, a bank).
func is_solid_ground(dir: Vector3) -> bool:
	var ground := height(dir.x, dir.y, dir.z)
	if ground < SPAWN_ABOVE_SEA:
		return false
	if water_at(dir, ground) > -INF or near_water(dir, ground, SPAWN_FROM_WATER):
		return false
	var up := dir.cross(Vector3.UP).normalized()
	for k in 4: # the ground a few metres round: no cliff, nothing under the sea
		var side := (dir + up.rotated(dir, float(k) * PI * 0.5) * 8.0 / settings.radius).normalized()
		var there := height(side.x, side.y, side.z)
		if there < SPAWN_ABOVE_SEA * 0.5 or absf(there - ground) > 8.0 * 0.5:
			return false
	return true


## `dir` if it is solid ground, else the nearest direction that is (searched in widening rings round
## it, out to about 30 km or the planet's own limit), else the planet's best spawn: the character is
## never put in the sea or a river.
func solid_spawn(dir: Vector3) -> Vector3:
	var from := dir.normalized()
	if is_solid_ground(from):
		return from
	var side := from.cross(Vector3.UP)
	if side.length_squared() < 0.0001:
		side = from.cross(Vector3.RIGHT)
	side = side.normalized()
	var reach := 40.0
	var limit := minf(30000.0, settings.radius * 0.45)
	while reach <= limit:
		var count := clampi(int(reach * TAU / 60.0), 8, 96) # a point every 60 m round the ring
		for step in count:
			var around := side.rotated(from, TAU * float(step) / float(count))
			var spot := (from + around * (reach / settings.radius)).normalized()
			if is_solid_ground(spot):
				return spot
		reach *= 1.35
	return find_spawn()


## A direction for the player to start on (`in_desert`: the first solid desert spot of a spiral):
## green country (mild, wet enough) that is not a dead flat
## plain: a little above the sea, with hills round it, and a river or the sea within a few
## kilometres, the best of the places found by a spiral over the planet.
func find_spawn(in_desert := false) -> Vector3:
	if in_desert:
		for index in 3000:
			var y := 1.0 - 2.0 * (float(index) + 0.5) / 3000.0
			var ring := sqrt(maxf(1.0 - y * y, 0.0))
			var angle := float(index) * 2.399963
			var dir := Vector3(cos(angle) * ring, y, sin(angle) * ring)
			var h := height(dir.x, dir.y, dir.z)
			if h < 5.0 or h > relief * 0.15:
				continue
			if biome(dir.x, dir.y, dir.z, h, 0.05) != TerrainNoise.Biome.DESERT:
				continue
			var spot := solid_spawn(dir)
			if spot.dot(dir) > 0.99999:
				return spot
	var best := Vector3(0.0, 0.0, 1.0)
	var best_score := -INF
	for index in 2500:
		var angle := float(index) * 2.399963
		var y := 0.85 * sin(float(index) * 0.7)
		var ring := sqrt(1.0 - y * y)
		var dir := Vector3(cos(angle) * ring, y, sin(angle) * ring)
		var h := height(dir.x, dir.y, dir.z)
		if h < 4.0 or h > relief * 0.1:
			continue
		if native != null and native.has_method(&"lake_surfaces"):
			var surface: float = native.call(&"lake_surfaces", PackedVector3Array([dir]))[0]
			if surface > -1.0e8: # not in a lake
				continue
		var weather := climate.sample(dir)
		if weather.x < 6.0 or weather.x > 28.0 or weather.y < 0.4:
			continue
		var up := dir.cross(Vector3.UP).normalized()
		var lowest := h
		var highest := h
		var sea := false
		var steepest := 0.0
		for k in 8:
			for metres in [60.0, 400.0, 2500.0]:
				var reach: float = metres
				var side := (dir + up.rotated(dir, float(k) * PI * 0.25) * reach
						/ settings.radius).normalized()
				var there := height(side.x, side.y, side.z)
				lowest = minf(lowest, there)
				highest = maxf(highest, there)
				sea = sea or there < 0.0
				if reach == 60.0:
					steepest = maxf(steepest, absf(there - h) / 60.0)
		if steepest > 0.3:
			continue # the foot of a cliff
		var score := minf(highest - lowest, relief * 0.2) + (relief * 0.05 if sea else 0.0)
		score += weather.y * relief * 0.03 - absf(weather.x - 17.0)
		if score > best_score:
			best_score = score
			best = dir
	return best
