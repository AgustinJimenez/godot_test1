class_name PlanetNoise
extends RefCounted
## The shape of a planet: height, wetness and warmth at any direction from its centre. Pure
## functions of the direction and the seed (3D noise on the sphere), so any tile can be built
## alone and neighbours agree on their shared edge, and there are no seams or poles to pinch.

var settings: PlanetSettings
var _continent := FastNoiseLite.new()
var _hills := FastNoiseLite.new()
var _ridges := FastNoiseLite.new()
var _mountain_mask := FastNoiseLite.new()
var _warp := FastNoiseLite.new()
var _moisture := FastNoiseLite.new()
var _heat := FastNoiseLite.new()
var _detail := FastNoiseLite.new()


func _init(planet_settings: PlanetSettings) -> void:
	settings = planet_settings
	var base_seed := settings.world_seed
	var big := 1.0 / (settings.radius * 0.7) # continents: a few round the planet
	_setup(_continent, base_seed, big, 3)
	_setup(_hills, base_seed + 1, 0.0022, 4)
	_setup(_ridges, base_seed + 2, 0.0008, 4)
	_ridges.fractal_type = FastNoiseLite.FRACTAL_RIDGED
	_setup(_mountain_mask, base_seed + 3, big * 3.0, 2)
	_setup(_warp, base_seed + 4, 0.004, 2)
	_setup(_moisture, base_seed + 5, big * 2.5, 3)
	_setup(_heat, base_seed + 6, big * 3.0, 2)
	_setup(_detail, base_seed + 7, 0.09, 2)


func _setup(noise: FastNoiseLite, noise_seed: int, frequency: float, octaves: int) -> void:
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.seed = noise_seed
	noise.frequency = frequency
	noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	noise.fractal_octaves = octaves


## Ground height in metres above the radius, in the unit direction (x, y, z).
func height(x: float, y: float, z: float) -> float:
	var p := Vector3(x, y, z) * settings.radius
	var warped := p + Vector3(_warp.get_noise_3d(p.x, p.y, p.z),
			_warp.get_noise_3d(p.x + 311.0, p.y - 97.0, p.z),
			_warp.get_noise_3d(p.x, p.y + 57.0, p.z - 211.0)) * 60.0
	var land := _continent.get_noise_3d(warped.x, warped.y, warped.z)
	var rolling := _hills.get_noise_3d(warped.x, warped.y, warped.z) * 0.22
	var mask := smoothstep(-0.12, 0.32, _mountain_mask.get_noise_3d(p.x, p.y, p.z))
	var peaks := _ridges.get_noise_3d(warped.x, warped.y, warped.z) * 0.5 + 0.5
	var raw := land * 0.55 + rolling + mask * peaks * 0.95 * (0.4 + maxf(land, 0.0))
	var h := settings.sea_level + (raw + 0.08) * settings.height_scale
	if h < settings.sea_level: # the sea floor is shallow near the shore
		h = settings.sea_level + (h - settings.sea_level) * 0.7
	return h


## 0 dry .. 1 wet: the tropics are wet, the dry belts lie either side of them.
func moisture(x: float, y: float, z: float) -> float:
	var p := Vector3(x, y, z) * settings.radius
	var belt := 0.22 * exp(-pow((absf(y) - 0.4) / 0.18, 2.0)) # dry subtropics
	return clampf(_moisture.get_noise_3d(p.x, p.y, p.z) * 0.9 + 0.5 - belt
			+ 0.12 * (1.0 - absf(y)), 0.0, 1.0)


## 0 cold .. 1 hot: the poles are cold, the equator hot, and the high ground colder.
func heat(x: float, y: float, z: float, ground: float) -> float:
	var p := Vector3(x, y, z) * settings.radius
	var warmth := 1.05 - pow(absf(y), 1.7) * 1.15 + _heat.get_noise_3d(p.x, p.y, p.z) * 0.25
	return clampf(warmth - maxf(ground - settings.sea_level, 0.0) / settings.height_scale * 0.9,
			0.0, 1.0)


## Fine variation 0..1, for colour speckle.
func detail(x: float, y: float, z: float) -> float:
	var p := Vector3(x, y, z) * settings.radius
	return _detail.get_noise_3d(p.x, p.y, p.z) * 0.5 + 0.5


func biome(x: float, y: float, z: float, ground: float, steepness: float) -> TerrainNoise.Biome:
	var above := ground - settings.sea_level
	var wet := moisture(x, y, z)
	if above < 1.4:
		return TerrainNoise.Biome.BEACH if wet < 0.62 else TerrainNoise.Biome.MARSH
	var warmth := heat(x, y, z, ground)
	if warmth < 0.2 or (above > settings.height_scale * 0.62 and warmth < 0.55):
		return TerrainNoise.Biome.SNOW
	if steepness > 0.62 or above > settings.height_scale * 0.5:
		return TerrainNoise.Biome.ROCKY
	if warmth > 0.52 and wet < 0.5:
		return TerrainNoise.Biome.DESERT
	return TerrainNoise.Biome.FOREST if wet > 0.5 else TerrainNoise.Biome.MEADOW


## The colour of a ground facet: the biome's palette, a speckle, rock on steep faces (the same
## palette as the flat world's TerrainColors).
func facet_color(x: float, y: float, z: float, ground: float, steep: float) -> Color:
	var kind := biome(x, y, z, ground, steep)
	var speckle := detail(x, y, z)
	var wet := moisture(x, y, z)
	var color: Color
	match kind:
		TerrainNoise.Biome.BEACH:
			color = TerrainColors.WET_SAND.lerp(TerrainColors.SAND, smoothstep(settings.sea_level,
					settings.sea_level + 1.4, ground))
		TerrainNoise.Biome.MARSH:
			color = TerrainColors.MARSH.lerp(TerrainColors.WET_SAND, speckle * 0.5)
		TerrainNoise.Biome.FOREST:
			color = TerrainColors.FOREST_DARK.lerp(TerrainColors.FOREST, speckle)
		TerrainNoise.Biome.ROCKY:
			color = TerrainColors.ROCK_DARK.lerp(TerrainColors.ROCK, speckle).lerp(
					TerrainColors.ROCK_WARM, TerrainColors.strata(ground, speckle))
		TerrainNoise.Biome.SNOW:
			color = TerrainColors.SNOW.lerp(TerrainColors.ROCK, maxf(steep - 0.35, 0.0))
		TerrainNoise.Biome.DESERT:
			color = TerrainColors.DESERT_RED.lerp(TerrainColors.DESERT, speckle).lerp(
					TerrainColors.DESERT_PALE, TerrainColors.strata(ground, speckle) * 0.6)
		_:
			color = TerrainColors.MEADOW_DRY.lerp(TerrainColors.MEADOW, wet).lerp(
					TerrainColors.MEADOW.darkened(0.12), speckle * 0.4)
	if kind != TerrainNoise.Biome.ROCKY and kind != TerrainNoise.Biome.SNOW:
		color = color.lerp(TerrainColors.ROCK.lerp(TerrainColors.ROCK_DARK, speckle),
				smoothstep(0.35, 0.6, steep))
	return color


## A direction on land with gentle ground near the equator, for a player to start on.
func find_spawn() -> Vector3:
	for index in 400:
		var angle := float(index) * 2.399963
		var y := 0.25 * sin(float(index) * 0.7)
		var ring := sqrt(1.0 - y * y)
		var dir := Vector3(cos(angle) * ring, y, sin(angle) * ring)
		var h := height(dir.x, dir.y, dir.z)
		var steep := 0.0
		for side: Vector3 in [Vector3(1, 0, 0), Vector3(0, 0, 1)]:
			var near := (dir + side * 3.0 / settings.radius).normalized()
			steep = maxf(steep, absf(height(near.x, near.y, near.z) - h) / 3.0)
		if h > settings.sea_level + 4.0 and h < settings.sea_level + 40.0 and steep < 0.12:
			return dir
	return Vector3(0.0, 0.0, 1.0)
