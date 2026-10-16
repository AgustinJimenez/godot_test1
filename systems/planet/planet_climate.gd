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


func build(noise: PlanetNoise) -> void:
	var size := WIDTH * HEIGHT
	_temperature.resize(size)
	_rain.resize(size)
	var elevation := PackedFloat32Array() # in units of relief
	elevation.resize(size)
	var ocean := PackedByteArray()
	ocean.resize(size)
	for row in HEIGHT:
		var lat := (0.5 - (float(row) + 0.5) / float(HEIGHT)) * PI
		for column in WIDTH:
			var lon := (float(column) + 0.5) / float(WIDTH) * TAU - PI
			var dir := Vector3(cos(lat) * cos(lon), sin(lat), cos(lat) * sin(lon))
			var h := noise.height(dir.x, dir.y, dir.z)
			var index := row * WIDTH + column
			elevation[index] = h / noise.relief
			ocean[index] = 1 if h < 0.0 else 0
	var clock := PlanetClock.new() # the orbit and the tilt of this planet, for the seasons
	clock.day_seconds = noise.settings.day_seconds
	clock.year_days = noise.settings.year_days
	clock.axial_tilt = deg_to_rad(noise.settings.axial_tilt)
	seasons.build(noise, clock)
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
	var wind := 1 if (lat > 30.0 and lat < 60.0) else -1 # westerlies / trades and polar easterlies
	var itcz := 0.8 * exp(-pow(lat / 9.0, 2.0)) # the rain belt of the tropics
	var storms := 0.3 * exp(-pow((lat - 48.0) / 12.0, 2.0)) # fronts: the mid latitude storm tracks
	var dry_belt := 1.0 - 0.55 * exp(-pow((lat - 27.0) / 9.0, 2.0)) # the subtropical highs
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
