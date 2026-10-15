class_name TerrainColors
extends RefCounted
## What colour each ground facet gets: the biome's palette, a speckle so no two facets match, and
## rock showing through on steep faces.

const SAND := Color(0.84, 0.76, 0.54)
const WET_SAND := Color(0.66, 0.6, 0.44)
const MEADOW := Color(0.42, 0.62, 0.26)
const MEADOW_DRY := Color(0.62, 0.66, 0.3)
const FOREST := Color(0.24, 0.45, 0.2)
const FOREST_DARK := Color(0.18, 0.34, 0.18)
const MARSH := Color(0.36, 0.45, 0.3)
const ROCK := Color(0.47, 0.45, 0.43)
const ROCK_DARK := Color(0.33, 0.32, 0.32)
const SNOW := Color(0.93, 0.95, 0.98)
const DESERT := Color(0.8, 0.62, 0.36)
const DESERT_RED := Color(0.72, 0.45, 0.28)
const ROCK_WARM := Color(0.58, 0.46, 0.38)
const DESERT_PALE := Color(0.9, 0.78, 0.55)


static func facet(noise: TerrainNoise, x: float, z: float, ground: float, steep: float) -> Color:
	var biome := noise.biome(x, z, ground, steep)
	var speckle := noise.detail(x, z)
	var wet := noise.moisture(x, z)
	var color: Color
	match biome:
		TerrainNoise.Biome.BEACH:
			color = WET_SAND.lerp(SAND, smoothstep(noise.settings.sea_level, noise.settings.sea_level + 1.4,
					ground))
		TerrainNoise.Biome.MARSH:
			color = MARSH.lerp(WET_SAND, speckle * 0.5)
		TerrainNoise.Biome.FOREST:
			color = FOREST_DARK.lerp(FOREST, speckle)
		TerrainNoise.Biome.ROCKY:
			color = ROCK_DARK.lerp(ROCK, speckle).lerp(ROCK_WARM, strata(ground, speckle))
		TerrainNoise.Biome.SNOW:
			color = SNOW.lerp(ROCK, maxf(steep - 0.35, 0.0))
		TerrainNoise.Biome.DESERT:
			color = DESERT_RED.lerp(DESERT, speckle).lerp(DESERT_PALE, strata(ground, speckle) * 0.6)
		_:
			color = MEADOW_DRY.lerp(MEADOW, wet).lerp(MEADOW.darkened(0.12), speckle * 0.4)
	# steep faces of any biome show the rock under it
	if biome != TerrainNoise.Biome.ROCKY and biome != TerrainNoise.Biome.SNOW:
		color = color.lerp(ROCK.lerp(ROCK_DARK, speckle), smoothstep(0.35, 0.6, steep))
	return color


## Bands of colour by height (0..1): the layers of rock and sand you see in cliffs and mesas.
static func strata(ground: float, speckle: float) -> float:
	return smoothstep(0.35, 0.65, fposmod(ground * 0.37 + speckle * 0.15, 1.0))
