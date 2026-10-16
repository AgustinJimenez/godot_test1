class_name PlanetNoise
extends RefCounted
## The shape and climate of a planet: height, rain, warmth and biome at any direction from its
## centre. The land comes from tectonic plates (PlanetTectonics) at the scale of the planet and
## from noise below that; the climate from latitude, height and the winds (PlanetClimate). Pure
## functions of the direction and the seed, so any tile can be built alone and neighbours agree on
## their shared edge, and there are no seams or poles to pinch.

const LAPSE := 6.5 ## degrees C lost per km of height
const EARTH_RELIEF := 8800.0 ## m: what "one relief" is on Earth

var settings: PlanetSettings
var relief := 1000.0 ## m, from the sea to the top of the highest ranges (see PlanetSettings)
var tectonics: PlanetTectonics
var climate := PlanetClimate.new()
var species: SpeciesRegistry ## the plants of this planet
var hydrology: PlanetHydrology ## rivers and lakes (null while it is being built)

var _rolling := FastNoiseLite.new()
var _hills := FastNoiseLite.new()
var _gullies := FastNoiseLite.new()
var _detail := FastNoiseLite.new()
var _sea := 0.0 ## the height (units of relief) that is sea level, so the ocean covers its share


func _init(planet_settings: PlanetSettings) -> void:
	settings = planet_settings
	relief = settings.relief
	if relief <= 0.0:
		relief = clampf(settings.radius * 0.0035, 300.0, 9000.0)
	tectonics = PlanetTectonics.new(settings.world_seed, settings.plates)
	species = SpeciesRegistry.new(settings.world_seed, settings.species_count)
	_setup(_rolling, settings.world_seed + 2, 0.0004, 3)
	_setup(_hills, settings.world_seed + 1, 0.0022, 4)
	_setup(_gullies, settings.world_seed + 3, 0.0018, 4)
	_gullies.fractal_type = FastNoiseLite.FRACTAL_RIDGED
	_setup(_detail, settings.world_seed + 7, 0.09, 2)
	_find_sea_level()
	climate.build(self)
	if settings.hydrology_cells > 0:
		var water := PlanetHydrology.new()
		water.build(self, settings.hydrology_cells)
		hydrology = water


func _setup(noise: FastNoiseLite, noise_seed: int, frequency: float, octaves: int) -> void:
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.seed = noise_seed
	noise.frequency = frequency
	noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	noise.fractal_octaves = octaves


## The sea level is wherever the heights have the planet's ocean share below it (sampled over the
## sphere, every sample weighing the same area).
func _find_sea_level() -> void:
	var count := 6000
	var samples := PackedFloat32Array()
	for index in count:
		var y := 1.0 - 2.0 * (float(index) + 0.5) / float(count)
		var ring := sqrt(1.0 - y * y)
		var angle := float(index) * 2.399963
		samples.append(tectonics.height(Vector3(cos(angle) * ring, y, sin(angle) * ring)))
	samples.sort()
	_sea = samples[clampi(int(settings.ocean_fraction * float(count)), 0, count - 1)]


## Ground height in metres above the sea, in the unit direction (x, y, z), rivers cut in.
func height(x: float, y: float, z: float) -> float:
	var ground := base_height(x, y, z)
	if hydrology == null:
		return ground
	return hydrology.carve(Vector3(x, y, z), ground)


## The ground before the rivers are cut in.
func base_height(x: float, y: float, z: float) -> float:
	var units := _units(x, y, z)
	var p := Vector3(x, y, z) * settings.radius
	var land := smoothstep(-0.02, 0.05, units)
	var hills := _hills.get_noise_3d(p.x, p.y, p.z) * clampf(relief * 0.01, 12.0, 45.0)
	var ground := _macro(units, p) + hills * land
	# the high ground is cut by gullies and spurs, as if water had run down it for ages
	var high := smoothstep(0.12, 0.45, units)
	ground += (_gullies.get_noise_3d(p.x, p.y, p.z) * 0.5 + 0.5 - 0.5) * relief * 0.05 * high
	# and by the water that has run down the valleys (stream power erosion, see PlanetHydrology)
	if hydrology != null:
		ground -= hydrology.erosion_at(Vector3(x, y, z)) * high
	# hard and soft layers of rock weather into ledges and steps
	var layer := maxf(relief * 0.025, 8.0)
	var steps := floorf(ground / layer) + smoothstep(0.15, 0.85, fposmod(ground / layer, 1.0))
	return lerpf(ground, steps * layer, smoothstep(0.3, 0.6, units) * 0.35)


## The ground without the smallest hills: what the water sees when it picks its way to the sea.
func macro_height(x: float, y: float, z: float) -> float:
	return _macro(_units(x, y, z), Vector3(x, y, z) * settings.radius)


func _macro(units: float, p: Vector3) -> float:
	var land := smoothstep(-0.02, 0.05, units)
	var rolling := _rolling.get_noise_3d(p.x, p.y, p.z) * clampf(relief * 0.04, 25.0, 140.0)
	# beaches and shallows: the ground eases toward the sea instead of dropping into it
	var shore := lerpf(0.3, 1.0, smoothstep(0.0, 0.06, absf(units)))
	return units * shore * relief + rolling * land


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
	if wet < 0.12 and degrees > 2.0:
		return TerrainNoise.Biome.DESERT
	return TerrainNoise.Biome.FOREST if wet > 0.4 else TerrainNoise.Biome.MEADOW


## The colour of a ground facet. Every ingredient is a smooth weight, so the biomes blend into one
## another instead of changing at a line: the ground cover by warmth and rain (tundra, taiga,
## forest, grass, savanna, rain forest), sand where it is dry, bare rock on steep faces and high
## ground, snow where it is cold, wet sand at the shore, marsh on the wet low land.
func facet_color(x: float, y: float, z: float, ground: float, steep: float) -> Color:
	var speckle := detail(x, y, z)
	var dir := Vector3(x, y, z)
	var degrees := temperature(x, y, z, ground)
	var rain := climate.sample(dir).y
	var color := _vegetation(degrees, rain, speckle)
	# dry and not frozen: sand and red earth
	var dry := (1.0 - smoothstep(0.08, 0.28, rain)) * smoothstep(-4.0, 8.0, degrees)
	var sand := TerrainColors.DESERT_RED.lerp(TerrainColors.DESERT, speckle)
	sand = sand.lerp(TerrainColors.DESERT_PALE, smoothstep(0.55, 0.9, speckle) * 0.5)
	color = color.lerp(sand, dry)
	# bare rock: steep faces and the ground above the trees, layered like real cliffs
	var tall := ground / relief
	var bare := maxf(smoothstep(0.36, 0.7, steep), smoothstep(0.3, 0.6, tall))
	var band := ground / maxf(relief * 0.03, 6.0) + speckle * 0.5
	var layers := smoothstep(0.35, 0.65, fposmod(band, 1.0))
	var rock := TerrainColors.ROCK_DARK.lerp(TerrainColors.ROCK, speckle)
	rock = rock.lerp(TerrainColors.ROCK_WARM, layers * 0.6)
	color = color.lerp(rock, bare)
	# snow where it is cold, thinner on steep faces
	var frozen := 1.0 - smoothstep(-16.0, -8.0, degrees)
	frozen *= 1.0 - smoothstep(0.5, 0.95, steep) * 0.75
	color = color.lerp(TerrainColors.SNOW.lerp(TerrainColors.ROCK, steep * 0.25), frozen)
	# the shore: wet sand, a beach, then marsh where the low land is wet
	var marsh := (1.0 - smoothstep(1.5, 6.0, ground)) * smoothstep(0.55, 0.8, rain / 1.2)
	color = color.lerp(TerrainColors.MARSH.lerp(TerrainColors.WET_SAND, speckle * 0.5), marsh * 0.8)
	var beach := 1.0 - smoothstep(0.8, 2.6, ground)
	var sand_beach := TerrainColors.WET_SAND.lerp(TerrainColors.SAND, smoothstep(0.0, 1.4, ground))
	return color.lerp(sand_beach, beach)


## Ground cover by warmth and rain: tundra, taiga, forest, grassland, savanna, rain forest.
func _vegetation(degrees: float, rain: float, speckle: float) -> Color:
	var tundra := Color(0.52, 0.56, 0.44)
	var taiga := Color(0.14, 0.30, 0.2)
	var forest := TerrainColors.FOREST_DARK.lerp(TerrainColors.FOREST, speckle)
	var grass := TerrainColors.MEADOW_DRY.lerp(TerrainColors.MEADOW, clampf(rain, 0.0, 1.0))
	var savanna := Color(0.72, 0.64, 0.3)
	var jungle := Color(0.09, 0.34, 0.12).lerp(Color(0.14, 0.42, 0.16), speckle)
	var color := grass
	var wet := smoothstep(0.35, 0.7, rain)
	if degrees > 18.0: # tropics: savanna to rain forest by rain
		color = savanna.lerp(grass, smoothstep(0.2, 0.45, rain)).lerp(jungle, smoothstep(0.7, 1.1, rain))
	else:
		color = grass.lerp(forest, wet)
	var cold := smoothstep(10.0, -2.0, degrees) # the cold north: forest turns to taiga, then tundra
	color = color.lerp(taiga, cold * wet).lerp(tundra, smoothstep(3.0, -10.0, degrees))
	return color.lerp(color.darkened(0.15), speckle * 0.3)


## A direction on lowland in a mild, wet-enough climate, for a player to start on.
func find_spawn() -> Vector3:
	var fallback := Vector3(0.0, 0.0, 1.0)
	for index in 1500:
		var angle := float(index) * 2.399963
		var y := 0.8 * sin(float(index) * 0.7)
		var ring := sqrt(1.0 - y * y)
		var dir := Vector3(cos(angle) * ring, y, sin(angle) * ring)
		var h := height(dir.x, dir.y, dir.z)
		if h < 3.0 or h > relief * 0.04:
			continue
		var climate_here := climate.sample(dir)
		if climate_here.x < 8.0 or climate_here.x > 27.0 or climate_here.y < 0.35:
			continue
		var steep := 0.0
		for side: Vector3 in [Vector3(1, 0, 0), Vector3(0, 0, 1)]:
			var near := (dir + side * 3.0 / settings.radius).normalized()
			steep = maxf(steep, absf(height(near.x, near.y, near.z) - h) / 3.0)
		if steep < 0.12:
			return dir
	return fallback
