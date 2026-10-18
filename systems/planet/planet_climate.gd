class_name PlanetClimate
extends RefCounted
## The climate of a planet as two low resolution maps (longitude x latitude): the temperature at sea
## level, and the rain. Warm at the equator and cold at the poles; the rain comes from the oceans on
## the prevailing winds (trade winds in the tropics, westerlies at mid latitudes, easterlies near
## the poles), falls where the air has to climb a mountain, and runs out inland, so there are rain
## shadows behind ranges, dry continental interiors and wet windward coasts. The tropics are wet
## and the belts at ~28 degrees dry. Built once from the planet's height (PlanetNoise.height).

const WIDTH := 192
const RAIN_BASE := 0.08 ## the share of the moisture in the air that falls on a flat cell
const RAIN_SCALE := 5.0
const HEIGHT := 96

var _temperature := PackedFloat32Array() ## degrees C at sea level
var _rain := PackedFloat32Array() ## 0 none .. ~1.5 a rain forest
var seasons := PlanetSeasons.new() ## the temperature through the year (the mean is `_temperature`)
## This planet's circulation, drawn from its seed: the latitude and strength of the wet belt of the
## tropics, the storm belt and the dry belt, and where the westerlies begin and end (degrees).
var circulation := {"itcz_lat": 0.0, "itcz_width": 9.0, "itcz_power": 0.8, "storm_lat": 48.0,
		"storm_power": 0.3, "dry_lat": 27.0, "dry_power": 0.55, "wind_low": 30.0, "wind_high": 60.0,
		"wind_k": 3.0}
var native_rain := true ## false: the rain is made by the script below (to compare)


func build(noise: PlanetNoise) -> void:
	_draw_circulation(noise.settings.world_seed)
	var size := WIDTH * HEIGHT
	_temperature.resize(size)
	_rain.resize(size)
	var elevation := PackedFloat32Array() # in units of relief
	elevation.resize(size)
	var ocean := PackedByteArray()
	ocean.resize(size)
	var dirs := PackedVector3Array() # (all the grid's heights in one go, on several threads)
	dirs.resize(size)
	for row in HEIGHT:
		var lat := (0.5 - (float(row) + 0.5) / float(HEIGHT)) * PI
		for column in WIDTH:
			var lon := (float(column) + 0.5) / float(WIDTH) * TAU - PI
			dirs[row * WIDTH + column] = Vector3(cos(lat) * cos(lon), sin(lat), cos(lat) * sin(lon))
	var grounds := noise.heights_of(dirs)
	for index in size:
		elevation[index] = grounds[index] / noise.relief
		ocean[index] = 1 if grounds[index] < 0.0 else 0
	var clock := PlanetClock.new() # the orbit and the tilt of this planet, for the seasons
	clock.day_seconds = noise.settings.day_seconds
	clock.year_days = noise.settings.year_days
	clock.axial_tilt = deg_to_rad(noise.settings.axial_tilt)
	clock.insolation = noise.settings.insolation
	clock.eccentricity = noise.settings.eccentricity
	clock.perihelion_share = noise.settings.perihelion_share
	seasons.wind_k = circulation["wind_k"]
	seasons.build(noise, clock)
	var native_ready := native_rain and ClassDB.class_exists(&"PlanetSeasonsNative")
	native_ready = native_ready and ClassDB.class_exists(&"PlanetDrainageNative")
	if native_ready: # the same numbers, made natively
		var sampler: RefCounted = ClassDB.instantiate(&"PlanetDrainageNative")
		_temperature = sampler.call(&"sample_grid", seasons.mean, PlanetSeasons.WIDTH,
				PlanetSeasons.HEIGHT, dirs)
		var air: RefCounted = ClassDB.instantiate(&"PlanetSeasonsNative")
		_rain = air.call(&"rain", elevation, ocean, _temperature, WIDTH, HEIGHT, RAIN_BASE,
				RAIN_SCALE, circulation)
		return
	for row in HEIGHT: # the climate's temperature is the mean of the year
		var lat := (0.5 - (float(row) + 0.5) / float(HEIGHT)) * PI
		for column in WIDTH:
			var lon := (float(column) + 0.5) / float(WIDTH) * TAU - PI
			_temperature[row * WIDTH + column] = seasons.mean_at(
					Vector3(cos(lat) * cos(lon), sin(lat), cos(lat) * sin(lon)))
	for row in HEIGHT:
		_advect_row(row, elevation, ocean)
	_smooth()


## One latitude's worth of rain: air moves along the row on the prevailing wind, picking up water
## over the sea and dropping it over land (more where the ground rises).
func _advect_row(row: int, elevation: PackedFloat32Array, ocean: PackedByteArray) -> void:
	var lat := absf((0.5 - (float(row) + 0.5) / float(HEIGHT)) * 180.0)
	var wind := 1 if (lat > circulation["wind_low"] and lat < circulation["wind_high"]) else -1 # westerlies / trades and polar easterlies
	var itcz: float = circulation["itcz_power"] * exp(-pow((lat - circulation["itcz_lat"])
			/ circulation["itcz_width"], 2.0)) # the rain belt of the tropics
	var storms: float = circulation["storm_power"] * exp(
			-pow((lat - circulation["storm_lat"]) / 12.0, 2.0)) # fronts: the mid latitude storm tracks
	var dry_belt: float = 1.0 - circulation["dry_power"] * exp(
			-pow((lat - circulation["dry_lat"]) / 9.0, 2.0)) # the subtropical highs
	var carried := 0.0
	var rain := PackedFloat32Array()
	rain.resize(WIDTH)
	for lap in 2: # two times round, so the air at the start of the row is already settled
		for step in WIDTH:
			var column := step if wind > 0 else WIDTH - 1 - step
			var behind := posmod(column - wind, WIDTH)
			var index := row * WIDTH + column
			if ocean[index] == 1:
				var warmth := clampf((_temperature[index] + 5.0) / 30.0, 0.1, 1.0)
				carried = lerpf(carried, 1.0, 0.5 * warmth)
				rain[column] = 0.0
			else:
				var climb := maxf(elevation[index] - elevation[row * WIDTH + behind], 0.0)
				var fall := carried * (RAIN_BASE + minf(climb * 9.0, 0.55)) * dry_belt
				# half of what falls is given back by the plants and the soil, so rain reaches far
				# inland on a wet coast; a mountain wrings out what it makes rise
				carried = maxf(carried - fall * (0.5 - minf(climb * 6.0, 0.3)), 0.0) * 0.996
				rain[column] = fall * RAIN_SCALE
	for column in WIDTH:
		var wet_belt := (itcz + storms) * (1.0 if ocean[row * WIDTH + column] == 0 else 0.4)
		_rain[row * WIDTH + column] = rain[column] + wet_belt


## Draws this planet's circulation from the seed (the defaults above are the Earth's: no two planets
## share one wet belt at the equator, one storm belt at 48 and one dry belt at 27).
func _draw_circulation(world_seed: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = world_seed + 50
	circulation = {
		"itcz_lat": rng.randf_range(-6.0, 6.0), "itcz_width": rng.randf_range(6.0, 13.0),
		"itcz_power": rng.randf_range(0.35, 1.0), "storm_lat": rng.randf_range(40.0, 56.0),
		"storm_power": rng.randf_range(0.15, 0.45), "dry_lat": rng.randf_range(20.0, 33.0),
		"dry_power": rng.randf_range(0.3, 0.7)}
	# the winds: -cos(k * latitude), k = how many belts of wind (a faster spinning planet has more)
	var k := rng.randf_range(2.6, 5.2)
	circulation["wind_k"] = k
	circulation["wind_low"] = rad_to_deg(PI * 0.5 / k)
	circulation["wind_high"] = minf(rad_to_deg(PI * 1.5 / k), 90.0)


func _smooth() -> void:
	var copy := _rain.duplicate()
	for row in HEIGHT:
		for column in WIDTH:
			var total := 0.0
			var weight := 0.0
			for dy in range(-1, 2):
				for dx in range(-1, 2):
					var r := clampi(row + dy, 0, HEIGHT - 1)
					var c := posmod(column + dx, WIDTH)
					var w := 2.0 if (dx == 0 and dy == 0) else 1.0
					total += copy[r * WIDTH + c] * w
					weight += w
			_rain[row * WIDTH + column] = clampf(total / weight, 0.0, 1.6)


## (sea level temperature in degrees C, averaged over the year; rain 0..1.6) at the unit direction.
## The grid of the rain (rows from the north pole, WIDTH columns from the west).
func rain_grid() -> PackedFloat32Array:
	return _rain


## The year's mean temperature at sea level at the direction (15 before the climate is built).
func sea_temperature(dir: Vector3) -> float:
	return sample(dir).x if not _temperature.is_empty() else 15.0


## The grid of the temperature at sea level (rows from the north pole, WIDTH columns from the west).
func temperature_grid() -> PackedFloat32Array:
	return _temperature

func sample(dir: Vector3) -> Vector2:
	var lat := asin(clampf(dir.y, -1.0, 1.0))
	var lon := atan2(dir.z, dir.x)
	var fx := (lon + PI) / TAU * float(WIDTH) - 0.5
	var fy := (0.5 - lat / PI) * float(HEIGHT) - 0.5
	var x0 := floori(fx)
	var y0 := floori(fy)
	var tx := fx - float(x0)
	var ty := fy - float(y0)
	var temperature := 0.0
	var rain := 0.0
	for dy in 2:
		for dx in 2:
			var weight := (tx if dx == 1 else 1.0 - tx) * (ty if dy == 1 else 1.0 - ty)
			var index := clampi(y0 + dy, 0, HEIGHT - 1) * WIDTH + posmod(x0 + dx, WIDTH)
			temperature += _temperature[index] * weight
			rain += _rain[index] * weight
	return Vector2(temperature, rain)
