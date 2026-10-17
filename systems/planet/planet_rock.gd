class_name PlanetRock
extends RefCounted
## The colour of the planet's crust, from the rock it is made of and not from what grows on it.
## Every plate has its own mix of rock (a hash of its number) that changes slowly across it, the
## young plates under the sea are basalt, high ground shows the old igneous and metamorphic rock
## under the cover, and layered rock (sandstone, limestone, shale) shows its beds as bands of light
## and dark that run level, so a hillside reads as layers. Steep faces are darker, a speckle keeps
## two facets from matching. Pure function of the position: the same planet gives the same crust.

## The rocks along one smooth scale 0..1 (it wraps: the last is the first), as (position, colour).
const STOPS: Array[Dictionary] = [
	{"at": 0.00, "colour": Color(0.17, 0.17, 0.19)}, # basalt
	{"at": 0.16, "colour": Color(0.37, 0.35, 0.32)}, # shale
	{"at": 0.32, "colour": Color(0.52, 0.51, 0.50)}, # grey granite
	{"at": 0.45, "colour": Color(0.66, 0.54, 0.49)}, # pink granite
	{"at": 0.58, "colour": Color(0.80, 0.77, 0.67)}, # limestone
	{"at": 0.74, "colour": Color(0.73, 0.57, 0.38)}, # sandstone
	{"at": 0.88, "colour": Color(0.60, 0.33, 0.23)}, # red sandstone
	{"at": 1.00, "colour": Color(0.17, 0.17, 0.19)}, # basalt again
]
const BASALT := 0.0
const GRANITE := 0.40

var _tectonics: PlanetTectonics
var _relief := 300.0
var _region := FastNoiseLite.new() # how the rock changes across a plate


func _init(tectonics: PlanetTectonics, world_seed: int, radius: float, relief: float) -> void:
	_tectonics = tectonics
	_relief = relief
	_region.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_region.seed = world_seed + 9
	_region.frequency = 1.0 / (radius * 0.45)
	_region.fractal_octaves = 3


## The rock's place on the scale (0..1) at the unit direction `dir` on ground `ground` (m above the
## sea): which rock is there before the cover and the layers.
func lithology(dir: Vector3, ground: float) -> float:
	var plate := _tectonics.plate_at(dir)
	var mix_of_rock := fposmod(_hash(int(plate.x)) + 0.28 * _region.get_noise_3d(dir.x * 1000.0,
			dir.y * 1000.0, dir.z * 1000.0), 1.0)
	if plate.z < 0.5: # sea floor plates: young basalt
		mix_of_rock = lerpf(mix_of_rock, BASALT, 0.85)
	var tall := clampf(ground / _relief, 0.0, 1.0) # the high ranges show the old rock under
	return lerpf(mix_of_rock, GRANITE, 0.65 * smoothstep(0.3, 0.7, tall))


## The colour of the crust at `dir` (a unit direction) on `ground`, on a face `steep` steep
## (0 level .. 1 vertical), with `speckle` (0..1) the fine variation there.
func colour(dir: Vector3, ground: float, steep: float, speckle: float) -> Color:
	var rock := _along(lithology(dir, ground))
	# the beds: bands that run level, strongest in the layered rocks (not basalt, not granite)
	var scale := maxf(_relief * 0.03, 6.0)
	var layers := smoothstep(0.35, 0.65, fposmod(ground / scale + speckle * 0.5, 1.0))
	rock = rock * (0.9 + 0.2 * layers)
	rock = rock * (0.88 + 0.24 * speckle)
	rock = rock.lerp(rock * 0.62, smoothstep(0.35, 0.8, steep))
	return Color(clampf(rock.r, 0.0, 1.0), clampf(rock.g, 0.0, 1.0), clampf(rock.b, 0.0, 1.0))


func _along(position: float) -> Color:
	var wrapped := fposmod(position, 1.0)
	for index in STOPS.size() - 1:
		var a: Dictionary = STOPS[index]
		var b: Dictionary = STOPS[index + 1]
		if wrapped <= float(b["at"]):
			var t := (wrapped - float(a["at"])) / (float(b["at"]) - float(a["at"]))
			return (a["colour"] as Color).lerp(b["colour"] as Color, smoothstep(0.0, 1.0, t))
	return STOPS[0]["colour"]


## A number 0..1 from a plate's number: the same plate always has the same rock.
func _hash(plate_number: int) -> float:
	return float(hash([plate_number, 7331]) & 0xffff) / 65535.0
