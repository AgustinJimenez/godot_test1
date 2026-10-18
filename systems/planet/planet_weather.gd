class_name PlanetWeather
extends RefCounted
## The weather of the planet, from its causes. Clouds form where moist air is lifted and cooled, so
## the amount of cloud at a place is the moisture there (a warm sea gives off a lot, wet land some:
## from the temperature the seasons give, PlanetSeasons, and the rain climate) times how much the
## air is lifted: along the belt where the trade winds meet (it follows the sun north and south with
## the seasons), along the storm tracks of the middle latitudes where the cold and the warm air
## meet, and up the windward side of the mountains; and it is held down under the subtropical highs,
## where the air sinks and the deserts lie. The clouds are carried by the winds, which blow east to
## west in the tropics and the polar regions and west to east in the middle latitudes (they turn
## with the planet's spin, which is why), so a cloud pattern drifts and changes shape as time runs,
## and runs back when time does: the pattern is a function of the date, nothing is stored.
##
## From the clouds, the temperature and the moisture, the weather at a place: clear, cloudy, fog on
## a wet morning, rain when thick cloud sits on moist, lifted air, a storm where the lift and the
## heat are great, and snow where it is cold.

const SHEAR_DAYS := 2.5 ## how long the weather systems drift before they fade into a fresh copy
const WARP := 0.45 ## how far the swirls push the places the cloud pattern is read from
const WIND_TURN := 0.035 ## the share of a turn the strongest wind carries the clouds in a day

enum Kind { CLEAR, CLOUDY, RAIN, STORM, FOG, SNOW } ## the same order as WorldWeather.State

var _noise: PlanetNoise
var _big_a := FastNoiseLite.new() # the weather systems (a few thousand km across on an Earth)
var _big_b := FastNoiseLite.new() # a second pattern the first one changes into and back
var _small := FastNoiseLite.new() # the clumps inside them
## This planet's own weather: how far its belts sit from the usual latitudes, how strong each is, and
## how much longitude breaks them (all from the seed, so no two planets share one band of cloud)
var _belt_shift := 0.0 ## radians the equatorial belt sits off the equator
var _belt_power := 1.0
var _storm_shift := 0.0 ## radians the storm tracks sit from their usual latitude
var _storm_power := 1.0
var _wind_k := 4.0 ## this planet's wind profile (PlanetClimate.circulation)
var _sink_shift := 0.0 ## radians the dry highs sit from their usual latitude
var _sink_power := 1.0 ## the dry subtropical highs
var _pool_break := 1.0 ## 0 the belt is even, 1 strongly broken by the pools
var _pool := FastNoiseLite.new() # warm pools and cold tongues: the belts vary round the planet
var _warp := FastNoiseLite.new() # bends the systems into swirls and filaments


func _init(noise: PlanetNoise) -> void:
	_noise = noise
	var seed_value := noise.settings.world_seed
	_setup(_big_a, seed_value + 31, 1.7, 3)
	_setup(_big_b, seed_value + 32, 1.7, 3)
	_setup(_small, seed_value + 33, 6.5, 3)
	_setup(_warp, seed_value + 34, 2.4, 3)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value + 36
	var circulation: Dictionary = _noise.climate.circulation
	_belt_shift = deg_to_rad(float(circulation["itcz_lat"])) + rng.randf_range(-0.12, 0.12)
	_belt_power = rng.randf_range(0.08, 0.95)
	_storm_shift = deg_to_rad(float(circulation["storm_lat"]) - 48.0)
	_storm_power = rng.randf_range(0.5, 1.3)
	_sink_power = rng.randf_range(0.7, 1.2)
	_wind_k = circulation["wind_k"]
	_sink_shift = deg_to_rad(float(circulation["dry_lat"]) - 27.5)
	_pool_break = rng.randf_range(0.5, 1.4)
	_setup(_pool, seed_value + 35, rng.randf_range(0.8, 1.9), 2)


func _setup(source: FastNoiseLite, noise_seed: int, frequency: float, octaves: int) -> void:
	source.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	source.seed = noise_seed
	source.frequency = frequency
	source.fractal_type = FastNoiseLite.FRACTAL_FBM
	source.fractal_octaves = octaves


## The east-west wind at latitude `lat` (radians) as a share of the strongest: negative blows
## toward the west (the trade winds and the polar easterlies), positive toward the east (the
## westerlies of the middle latitudes).
static func zonal_wind(lat: float, wind_k := 4.0) -> float:
	return -cos(lat * wind_k)


## The planet's wind profile number (its zonal wind is `-cos(k * latitude)`).
func wind_k() -> float:
	return _wind_k


## How much cloud the air at `dir` is ready to make (0..1): moisture times lift, held down under the
## subtropical highs. The big pattern of the weather, before the clouds are placed in it.
func readiness(dir: Vector3, clock: PlanetClock, macro := NAN) -> float:
	var lat := asin(clampf(dir.y, -1.0, 1.0))
	var declination := clock.declination()
	var moisture := _moisture(dir, clock, macro)
	var south := -1.0 if lat < 0.0 else 1.0
	# the belt where the trade winds meet follows the sun, but not all the way
	# (the belt is broken up by longitude: strong over the warm pools, weak over the cold tongues)
	var pools := 0.5 + 0.5 * _pool.get_noise_3d(dir.x, dir.y, dir.z)
	var pools_factor := lerpf(1.0 - 0.65 * _pool_break, 1.0 + 0.4 * _pool_break,
			smoothstep(0.2, 0.8, pools))
	var trade_belt := 0.75 * _belt_power * pools_factor \
			* exp(-pow((lat - 0.4 * declination - _belt_shift) / 0.17, 2.0))
	# the storm tracks of the middle latitudes, a little poleward in the summer
	# the storm tracks lean: they run poleward toward the east, and wander with longitude
	var lean := 0.12 * sin(atan2(dir.z, dir.x) * 2.0 + _pool.get_noise_3d(dir.x, dir.y, dir.z) * 3.0)
	var storm_lat := south * (0.87 + lean + _storm_shift) + 0.3 * declination
	var storms := 0.55 * _storm_power * exp(-pow((lat - storm_lat) / 0.2, 2.0))
	# the subtropical highs, where the air sinks
	var high_lat := south * (0.48 + _sink_shift) + 0.3 * declination
	var sinking := _sink_power * exp(-pow((lat - high_lat) / 0.15, 2.0))
	var wet := clampf(_noise.climate.sample(dir).y / 1.2, 0.0, 1.0)
	# moisture alone makes some cloud; the trade winds' belt lifts the moist air; the storm tracks lift
	# whatever air they find (a front is a front even over dry ground)
	var ready := 0.06 + 0.3 * moisture + 0.8 * trade_belt * moisture
	ready += 0.9 * storms * (0.5 + 0.5 * moisture) + 0.2 * wet * moisture
	ready += 0.25 * smoothstep(0.9, 1.4, absf(lat)) # the cloud decks of the polar regions
	ready += _monsoon(dir, clock, wet, macro)
	# warm pools and cold tongues change the whole cloudiness, whatever made it (seed by seed)
	ready *= lerpf(1.0 - 0.4 * _pool_break, 1.0 + 0.3 * _pool_break, smoothstep(0.25, 0.75, pools))
	return clampf(ready * (1.0 - 0.65 * sinking), 0.0, 1.0)


## The monsoon: in the warm half of the year a big land mass in the low latitudes heats more than
## the sea beside it, its air rises and draws the moist air in from the sea (a wet season, more
## cloud); in the cool half the air sinks and the wind turns the other way (a dry season). Found
## from the land's own temperature against its yearly mean, so it is a function of the date and
## only the land that has a rainy climate has a wet season to speak of.
func _monsoon(dir: Vector3, clock: PlanetClock, wet: float, macro := NAN) -> float:
	if _macro(dir, macro) < 0.0:
		return 0.0
	var lat := asin(clampf(dir.y, -1.0, 1.0))
	var tropics := exp(-pow(lat / 0.6, 2.0))
	var seasons := _noise.climate.seasons
	var anomaly := seasons.at(dir, clock.year_share()) - seasons.mean_at(dir)
	var wetter := smoothstep(0.0, 8.0, anomaly)
	var drier := smoothstep(0.0, 8.0, -anomaly)
	return tropics * (0.5 * wetter * (0.3 + wet) - 0.2 * drier)


## The height before the rivers at `dir`: `macro` when the caller has it already (a map row asks
## the native crust for a whole row at once), else worked out here.
func _macro(dir: Vector3, macro: float) -> float:
	return macro if not is_nan(macro) else _noise.macro_height(dir.x, dir.y, dir.z)


## The moisture the air picks up at `dir` now (0..1): a warm sea gives off a great deal, wet land
## some, a frozen or dry place little.
func _moisture(dir: Vector3, clock: PlanetClock, macro := NAN) -> float:
	var degrees := _noise.climate.seasons.at(dir, clock.year_share())
	if _macro(dir, macro) < 0.0:
		return 0.25 + 0.75 * smoothstep(-30.0, 30.0, degrees)
	var wet := clampf(_noise.climate.sample(dir).y / 1.2, 0.0, 1.0)
	return wet * (0.25 + 0.75 * smoothstep(-30.0, 25.0, degrees))


## Where the cloud is: 0 clear sky .. 1 thick cloud, at `dir` at the clock's moment. The weather
## systems are carried east or west by the wind of the latitude and change shape slowly.
func cloud(dir: Vector3, clock: PlanetClock, macro := NAN) -> float:
	return cloud_cells(dir, clock, macro).x


## The cloud and, with it, the strength of the small clumps inside the systems (-1..1: the cells
## where a thick cloud rains hard are the high ones).
func cloud_cells(dir: Vector3, clock: PlanetClock, macro := NAN) -> Vector2:
	var ready := readiness(dir, clock, macro)
	var days := clock.absolute_days()
	var lat := asin(clampf(dir.y, -1.0, 1.0))
	var morph := 0.5 + 0.5 * sin(days * 0.45)
	# the winds carry each latitude at its own speed, which would stretch the pattern into long
	# streaks as days go by: it is drawn twice, drifted for at most SHEAR_DAYS each, and the two
	# are faded into each other (one restarts while the other is at its most visible)
	var first := fposmod(days, SHEAR_DAYS)
	var second := fposmod(days + SHEAR_DAYS * 0.5, SHEAR_DAYS)
	var weight := 1.0 - absf(2.0 * first / SHEAR_DAYS - 1.0)
	var pattern := 0.0
	var cells := 0.0
	for turn in 2:
		var drift := first if turn == 0 else second
		var shift := zonal_wind(lat, _wind_k) * WIND_TURN * TAU * drift
		var lon := atan2(dir.z, dir.x) - shift
		var carried := Vector3(cos(lat) * cos(lon), dir.y, cos(lat) * sin(lon))
		# the air swirls: the place the pattern is read from is pushed round by a slow noise
		var bend_x := _warp.get_noise_3d(carried.x, carried.y, carried.z)
		var bend_y := _warp.get_noise_3d(carried.z + 7.3, carried.x - 3.1, carried.y + 1.7)
		var bent := (carried + WARP * Vector3(bend_x, bend_y, bend_x - bend_y)).normalized()
		carried = bent
		var big := lerpf(_big_a.get_noise_3d(carried.x, carried.y, carried.z),
				_big_b.get_noise_3d(carried.x, carried.y, carried.z), morph)
		var clumps := _small.get_noise_3d(carried.x, carried.y, carried.z)
		var share := weight if turn == 0 else 1.0 - weight
		pattern += clampf(0.5 + 0.5 * (0.75 * big + 0.35 * clumps), 0.0, 1.0) * share
		cells += clumps * share
	var threshold := 0.97 - ready * 0.8
	return Vector2(smoothstep(threshold - 0.12, threshold + 0.12, pattern), cells)


## The weather at `dir` (`ground` metres above the sea) right now: {"kind", "cloud", "ready"}.
func at(dir: Vector3, ground: float, clock: PlanetClock) -> Dictionary:
	var ready := readiness(dir, clock)
	var cells := cloud_cells(dir, clock)
	var cover := cells.x
	var degrees := _noise.temperature_now(dir.x, dir.y, dir.z, ground, clock)
	var kind := Kind.CLEAR
	if cover > 0.35:
		kind = Kind.CLOUDY
	if cover > 0.8 and ready > 0.45 and cells.y > 0.05:
		kind = Kind.RAIN
		if ready > 0.8 and cells.y > 0.3 and degrees > 20.0:
			kind = Kind.STORM
		if degrees < 0.5:
			kind = Kind.SNOW
	elif cover < 0.45 and ready > 0.4:
		# fog: a still, wet morning (the air has cooled in the night)
		var hour := clock.local_hour(dir)
		if hour > 3.0 and hour < 8.5 and _moisture(dir, clock) > 0.5:
			kind = Kind.FOG
	return {"kind": kind, "cloud": cover, "ready": ready, "degrees": degrees}
