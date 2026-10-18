class_name PlanetRock
extends RefCounted
## The crust's rock, from the setting it formed in, and its colour. Nothing grows on it here.
##
## Each place has a mix of nine rocks, weighed by what makes them:
##  - the sea floor (oceanic plates) is basalt with a cover of shale;
##  - a plate boundary is volcanic (andesite) where an ocean plate is involved, and metamorphic
##    (gneiss, schist) where two continents met;
##  - the old interiors of the continents (cratons) are granite and gneiss;
##  - the low basins between are sedimentary, which kind (limestone, sandstone, red sandstone,
##    shale) following a slow regional pattern, as the climate and the sea of each age laid them;
##  - high ground is stripped to the old igneous and metamorphic rock.
## The beds of the sedimentary rocks show as level bands, steep faces are darker. The rocks are
## blended by weight, so one grades into the next. A pure function of the position.

enum Kind { BASALT, ANDESITE, GRANITE, GNEISS, SCHIST, LIMESTONE, SANDSTONE, RED_SANDSTONE, SHALE }

const SOIL_DRY := Color(0.64, 0.55, 0.38) ## the soil of a dry place
const SOIL_RICH := Color(0.27, 0.20, 0.13) ## and of a wet, mild one
const SAND := Color(0.80, 0.72, 0.52) ## beaches: low, level ground by the sea
const SNOW := Color(0.93, 0.95, 0.98) ## permanent snow and ice
const LAPSE := 0.0065 ## degrees C the air cools a metre higher
const COLOURS: Array[Color] = [
	Color(0.25, 0.24, 0.26), # basalt
	Color(0.38, 0.35, 0.33), # andesite
	Color(0.64, 0.56, 0.52), # granite
	Color(0.48, 0.48, 0.51), # gneiss
	Color(0.44, 0.49, 0.45), # schist
	Color(0.83, 0.80, 0.70), # limestone
	Color(0.74, 0.58, 0.40), # sandstone
	Color(0.61, 0.34, 0.24), # red sandstone
	Color(0.33, 0.32, 0.31), # shale
]
const BOUNDARY := 0.08 ## radians: how far a boundary's rock reaches

var _tectonics: PlanetTectonics
var _relief := 300.0
var _radius := 20000.0
var _craton := FastNoiseLite.new() # where the old continental cores are
var _basin := FastNoiseLite.new() # which sedimentary rock a basin has


func _init(tectonics: PlanetTectonics, world_seed: int, radius: float, relief: float) -> void:
	_tectonics = tectonics
	_relief = relief
	_radius = radius
	_craton.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_craton.seed = world_seed + 9
	_craton.frequency = 1.0 / (radius * 0.5)
	_craton.fractal_octaves = 2
	_basin.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_basin.seed = world_seed + 10
	_basin.frequency = 1.0 / (radius * 0.3)
	_basin.fractal_octaves = 3


## How much of each rock (see `Kind`) is at the unit direction `dir`, on ground `ground` (m above
## the sea): nine weights that add up to 1.
func weights(dir: Vector3, ground: float) -> PackedFloat32Array:
	var plate := _tectonics.plate_at(dir)
	var continental := plate.z > 0.5
	var near_edge := exp(-pow(plate.y / BOUNDARY, 2.0))
	var tall := clampf(ground / _relief, 0.0, 1.0)
	var p := dir * _radius
	var old := smoothstep(-0.15, 0.3, _craton.get_noise_3d(p.x, p.y, p.z))
	var regional := clampf(0.5 + 1.1 * _basin.get_noise_3d(p.x, p.y, p.z), 0.0, 1.0)
	var w := PackedFloat32Array()
	w.resize(Kind.size())
	if not continental:
		# young crust under a cover of sediment that thickens toward the continents' feet
		var cover := smoothstep(-0.2, 0.0, ground / _relief)
		w[Kind.BASALT] = 0.5
		w[Kind.SHALE] = 0.25
		w[Kind.LIMESTONE] = 0.1 + 0.25 * cover
		w[Kind.SANDSTONE] = 0.15 * cover
		w[Kind.ANDESITE] = near_edge * 0.9 # the arcs and the trenches' sides
	else:
		var high := smoothstep(0.12, 0.5, tall) # stripped to the old rock
		var basement := clampf(old + high, 0.0, 1.0)
		w[Kind.GRANITE] = basement * 0.55
		w[Kind.GNEISS] = basement * 0.45
		var sediment := 1.0 - basement
		# which sediment: a slow regional pattern (warm sea, desert, deep water, mud)
		w[Kind.LIMESTONE] = sediment * smoothstep(0.58, 0.7, regional)
		w[Kind.RED_SANDSTONE] = sediment * smoothstep(0.3, 0.18, regional)
		w[Kind.SHALE] = sediment * smoothstep(0.1, 0.22, regional) * smoothstep(0.46, 0.34, regional)
		w[Kind.SANDSTONE] = sediment * smoothstep(0.3, 0.38, regional) * smoothstep(0.7, 0.6, regional)
		# a boundary between continents, or a coast range: metamorphic rock
		var schist := smoothstep(0.35, 0.65, regional)
		w[Kind.GNEISS] += near_edge * 0.9 * (1.0 - schist)
		w[Kind.SCHIST] = near_edge * 1.1 * schist
		w[Kind.ANDESITE] = near_edge * 0.3
	var total := 0.0
	for value in w:
		total += value
	if total <= 0.0001:
		w[Kind.GRANITE] = 1.0
		total = 1.0
	for index in w.size():
		w[index] /= total
	return w


## The rock there in most amount (a `Kind`).
func dominant(dir: Vector3, ground: float) -> int:
	var w := weights(dir, ground)
	var best := 0
	for index in w.size():
		if w[index] > w[best]:
			best = index
	return best


## The colour of the crust at `dir` (a unit direction) on `ground`, on a face `steep` steep
## (0 level .. 1 vertical), with `speckle` (0..1) the fine variation there. `sea_temperature`
## (degrees C, the year's mean at sea level there) puts permanent snow and ice where the cold
## keeps it.
func colour(dir: Vector3, ground: float, steep: float, speckle: float,
		sea_temperature := 15.0, strata := true, rain := 0.5) -> Color:
	var w := weights(dir, ground)
	var rock := Color(0.0, 0.0, 0.0)
	for index in w.size():
		rock += COLOURS[index] * w[index]
	# the beds: bands that run level, in the sedimentary rocks
	var sedimentary := w[Kind.LIMESTONE] + w[Kind.SANDSTONE] + w[Kind.RED_SANDSTONE] + w[Kind.SHALE]
	var bed := maxf(_relief * 0.03, 6.0)
	# (no fine noise in the band's phase: it would break the beds into patches one facet big)
	var layers := 0.5 + 0.5 * sin(ground / bed * TAU)
	# the sea floor shows no beds (they showed as contour rings)
	var on_land := smoothstep(0.0, 200.0, ground)
	if strata: # (a map's big pixels would only alias the beds into grain)
		rock = rock * (1.0 + (layers - 0.5) * 0.24 * sedimentary * on_land)
	rock = rock * (0.94 + 0.12 * speckle)
	rock = rock.lerp(rock * 0.62, smoothstep(0.35, 0.8, steep))
	var cold := sea_temperature - LAPSE * maxf(ground, 0.0)
	# soil: deep and dark where it is wet and mild, thin and pale where it is dry, none on steep rock
	var fertile := clampf(rain / 0.9, 0.0, 1.0) * smoothstep(-5.0, 10.0, cold)
	var soil_colour := SOIL_DRY.lerp(SOIL_RICH, fertile)
	var soil := on_land * (1.0 - smoothstep(0.2, 0.55, steep)) * (0.3 + 0.7 * fertile) * 0.6
	rock = rock.lerp(soil_colour, soil)
	var snow := smoothstep(-0.5, -4.5, cold) * smoothstep(0.0, 60.0, ground)
	snow *= 1.0 - 0.85 * smoothstep(0.5, 0.95, steep) # the steepest rock stays bare
	rock = rock.lerp(SNOW, snow * 0.92)
	var beach := smoothstep(4.0, 0.5, ground) * smoothstep(0.0, 0.5, ground + 0.5)
	beach *= 1.0 - smoothstep(0.15, 0.45, steep)
	rock = rock.lerp(SAND, beach * 0.85 * (1.0 - snow))
	return Color(clampf(rock.r, 0.0, 1.0), clampf(rock.g, 0.0, 1.0), clampf(rock.b, 0.0, 1.0))
