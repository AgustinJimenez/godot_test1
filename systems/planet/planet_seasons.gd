class_name PlanetSeasons
extends RefCounted
## The temperature of the planet through its year, from the sunlight and the heat the ground and the
## sea can store: an energy balance on a coarse grid (longitude x latitude).
##
## Every cell is warmed by the sunlight its latitude gets (PlanetClock.daily_light: more when the
## hemisphere leans toward the star, none in the polar night) and cools by radiating heat, so left
## alone it would settle at the temperature where the two balance (the radiated heat grows with the
## fourth power of the temperature: `EMIT`). It does not follow that at once: the ground and above
## all the sea hold a great deal of heat, so a cell only moves toward its balance temperature at a
## rate set by its heat capacity (the sea slowly, the land fast). That makes the hottest days come
## after the solstice, the coasts milder than the interiors, and the sea almost steady. Snow and ice
## reflect light, so a cell that has frozen absorbs less and stays frozen (a feedback that keeps the
## ice caps). The winds and currents mix the heat across the cells (`MIX`), which is what keeps the
## poles from being as cold as the sunlight alone would make them.
##
## The planet is run through its year until the cycle repeats itself, and one year of it is kept
## (`SNAPSHOTS` pictures). The temperature at any moment, forward or backward in time, is then read
## off that cycle: nothing has to be simulated while playing, and jumping about in time is free.
## The mean of the cycle is the planet's climate (what its plants and biomes follow).

const WIDTH := 96
const HEIGHT := 48
const SNAPSHOTS := 48
const EMIT := 0.34 ## the absorbed sunlight (share of the full sun) that balances at 15 C
const FLOOR := 0.13 ## heat the air and the ground still give off in the dark
const SNOW_ALBEDO := 0.3 ## share of the light a frozen cell reflects
const LAND_TAU := 0.05 ## years a cell of land takes to move most of the way to its balance
const SEA_TAU := 0.2 ## and a cell of sea
const MIX := 0.3 ## share of a cell's heat shared with its neighbours each pass
const PASSES := 3 ## passes a step
const HOT := 27.0 ## degrees C above which evaporation and cloud take most of the extra heat
const MAX_YEARS := 8
const WIND := 0.2 ## share of a cell the zonal wind carries the heat each pass (at its strongest)

var mean := PackedFloat32Array() ## degrees C at sea level, averaged over the year
var _cycle: Array[PackedFloat32Array] = [] # SNAPSHOTS grids of degrees C at sea level
var wind := WIND ## the lab sets 0 to see the climate without the wind
var native_year := true ## false: the year is run by the script below (to compare with the native one)
var _sea := PackedByteArray() # 1 where the cell is sea


## Runs the planet through its year (`clock` carries the orbit and the tilt) until the cycle
## repeats.
func build(noise: PlanetNoise, clock: PlanetClock) -> void:
	var size := WIDTH * HEIGHT
	_sea.resize(size)
	for row in HEIGHT:
		var lat := (0.5 - (float(row) + 0.5) / float(HEIGHT)) * PI
		for column in WIDTH:
			var lon := (float(column) + 0.5) / float(WIDTH) * TAU - PI
			var h := noise.macro_height(cos(lat) * cos(lon), sin(lat), cos(lat) * sin(lon))
			_sea[row * WIDTH + column] = 1 if h < 0.0 else 0
	_mark_the_dry_land()
	if native_year and ClassDB.class_exists(&"PlanetSeasonsNative"):
		_run_native(clock)
		return
	var heat := PackedFloat32Array()
	heat.resize(size)
	var light := PackedFloat32Array() # the sunlight of each row at the moment
	light.resize(HEIGHT)
	for index in size: # the start: the balance of the average sunlight
		heat[index] = 15.0
	var previous := heat.duplicate()
	for year in MAX_YEARS:
		var total := 0.0
		for step in SNAPSHOTS:
			_step(heat, light, clock, (float(step) + 0.5) / float(SNAPSHOTS), 1.0 / float(SNAPSHOTS))
		for index in size:
			total += absf(heat[index] - previous[index])
		previous = heat.duplicate()
		if year >= 2 and total / float(size) < 0.04:
			break
	# the recorded year, from the share 1/SNAPSHOTS to the end, the last picture being the first
	_cycle.clear()
	_cycle.resize(SNAPSHOTS)
	mean.resize(size)
	for index in size:
		mean[index] = 0.0
	for step in SNAPSHOTS:
		_step(heat, light, clock, (float(step) + 0.5) / float(SNAPSHOTS), 1.0 / float(SNAPSHOTS))
		_cycle[(step + 1) % SNAPSHOTS] = heat.duplicate()
		for index in size:
			mean[index] += heat[index] / float(SNAPSHOTS)
	_add_the_currents()



## The land's byte becomes 2 + 100 times its dryness: far from the sea, and under the subtropical
## highs (the Sahara, Arabia, the Australian interior), the ground is dry and gets hotter than wet
## land does; the sea stays 1.
func _mark_the_dry_land() -> void:
	var far := PackedInt32Array() # cells to the nearest sea (east-west it wraps)
	far.resize(WIDTH * HEIGHT)
	for index in far.size():
		far[index] = 0 if _sea[index] == 1 else 99
	for pass_number in 2: # forward and backward sweeps: a cheap distance
		for row in HEIGHT:
			for step in WIDTH * 2:
				var column := step % WIDTH
				var here := row * WIDTH + column
				var west := row * WIDTH + (column + WIDTH - 1) % WIDTH
				far[here] = mini(far[here], far[west] + 1)
			for step in WIDTH * 2:
				var column := WIDTH - 1 - step % WIDTH
				var here := row * WIDTH + column
				var east := row * WIDTH + (column + 1) % WIDTH
				far[here] = mini(far[here], far[east] + 1)
		for row in range(1, HEIGHT):
			for column in WIDTH:
				far[row * WIDTH + column] = mini(far[row * WIDTH + column],
						far[(row - 1) * WIDTH + column] + 1)
		for row in range(HEIGHT - 2, -1, -1):
			for column in WIDTH:
				far[row * WIDTH + column] = mini(far[row * WIDTH + column],
						far[(row + 1) * WIDTH + column] + 1)
	for row in HEIGHT:
		var lat := absf((0.5 - (float(row) + 0.5) / float(HEIGHT)) * 180.0)
		var highs := exp(-pow((lat - 26.0) / 13.0, 2.0)) # the dry belts
		for column in WIDTH:
			var index := row * WIDTH + column
			if _sea[index] == 1:
				continue
			var inland := clampf(float(far[index]) / 6.0, 0.0, 1.0)
			var dry := inland * clampf(0.3 + 0.9 * highs, 0.0, 1.0)
			_sea[index] = 2 + int(round(dry * 100.0))


## The ocean currents, as a change of the sea's temperature next to the land: the cold ones along
## the west coasts of the continents in the subtropics (California, Peru, the Canaries, Benguela),
## the warm ones along the east coasts (the Gulf Stream, the Kuroshio, Brazil, Agulhas).
func _add_the_currents() -> void:
	var offsets := PackedFloat32Array()
	offsets.resize(WIDTH * HEIGHT)
	for row in HEIGHT:
		var lat := absf((0.5 - (float(row) + 0.5) / float(HEIGHT)) * 180.0)
		var cold := exp(-pow((lat - 22.0) / 14.0, 2.0))
		var warm := exp(-pow((lat - 36.0) / 16.0, 2.0))
		for column in WIDTH:
			var index := row * WIDTH + column
			if _sea[index] != 1:
				continue
			for reach in range(1, 4): # land close to the east: a cold current runs along it
				if _sea[row * WIDTH + (column + reach) % WIDTH] != 1:
					offsets[index] -= 5.0 * cold * (1.0 - float(reach - 1) / 3.0)
					break
			for reach in range(1, 4): # land close to the west: a warm current leaves it
				if _sea[row * WIDTH + (column + WIDTH - reach) % WIDTH] != 1:
					offsets[index] += 4.0 * warm * (1.0 - float(reach - 1) / 3.0)
					break
	for at in _cycle.size():
		var picture := _cycle[at]
		for index in picture.size():
			picture[index] += offsets[index]
		_cycle[at] = picture
	for index in mean.size():
		mean[index] += offsets[index]


## The year run natively (PlanetSeasonsNative, the same steps as below): the script only works out
## the sunlight of every row at every moment, the orbit being its own.
func _run_native(clock: PlanetClock) -> void:
	var lights := PackedFloat32Array()
	lights.resize(SNAPSHOTS * HEIGHT)
	for moment in SNAPSHOTS:
		clock.set_year_share((float(moment) + 0.5) / float(SNAPSHOTS))
		for row in HEIGHT:
			var lat := (0.5 - (float(row) + 0.5) / float(HEIGHT)) * PI
			lights[moment * HEIGHT + row] = clock.daily_light(lat) * clock.light_now()
	var year: RefCounted = ClassDB.instantiate(&"PlanetSeasonsNative")
	var made: Dictionary = year.call(&"run", _sea, lights, WIDTH, HEIGHT, SNAPSHOTS, wind, MAX_YEARS)
	mean = made["mean"]
	_cycle.clear()
	for picture: PackedFloat32Array in made["cycle"]:
		_cycle.append(picture)
	_add_the_currents()

## One step of `dt` years, from the share `at` - dt/2 to at + dt/2 of the year.
func _step(heat: PackedFloat32Array, light: PackedFloat32Array, clock: PlanetClock, at: float,
		dt: float) -> void:
	clock.set_year_share(at)
	for row in HEIGHT:
		var lat := (0.5 - (float(row) + 0.5) / float(HEIGHT)) * PI
		light[row] = clock.daily_light(lat) * clock.light_now()
	var sea_pull := 1.0 - exp(-dt / SEA_TAU)
	var land_pull := 1.0 - exp(-dt / LAND_TAU)
	for row in HEIGHT:
		var sun := light[row]
		for column in WIDTH:
			var index := row * WIDTH + column
			var degrees := heat[index]
			var frozen := clampf((2.0 - degrees) / 10.0, 0.0, 1.0) # snow and ice on the cell
			var absorbed := sun * (1.0 - SNOW_ALBEDO * frozen) + FLOOR
			var ratio := sqrt(sqrt(absorbed / EMIT))
			var balance := 15.0 + 288.0 * (ratio - 1.0)
			var dry := float(_sea[index] - 2) * 0.01 if _sea[index] >= 2 else 0.0
			var hot := HOT + 10.0 * dry
			if balance > hot: # water evaporates and clouds form: not all the extra heat is kept
				balance = hot + (balance - hot) * (0.35 + 0.5 * dry)
			heat[index] = degrees + (balance - degrees) * (sea_pull if _sea[index] == 1 else land_pull)
	for pass_number in PASSES:
		_carry(heat)
		_mix(heat)


## The heat the zonal wind carries: eastward in the middle latitudes (the westerlies), westward in
## the tropics (the trade winds), each cell taking some of the heat of the cell the wind comes from.
## So the air that crosses the sea first reaches the land warm (or cool): the west coasts of the
## continents are milder than the east ones.
func _carry(heat: PackedFloat32Array) -> void:
	if wind <= 0.0:
		return
	var moved := heat.duplicate()
	for row in HEIGHT:
		var lat := (0.5 - (float(row) + 0.5) / float(HEIGHT)) * PI
		var push := -cos(3.0 * lat) * wind # + toward the east, - toward the west
		for column in WIDTH:
			var index := row * WIDTH + column
			var side := (column + WIDTH - 1) % WIDTH if push > 0.0 else (column + 1) % WIDTH
			var from := row * WIDTH + side
			moved[index] = heat[index] + (heat[from] - heat[index]) * absf(push)
	for index in heat.size():
		heat[index] = moved[index]


## How much wider the yearly swing of temperature is on the land where the wind comes off the land
## than where it comes off the sea (degrees C, the middle latitudes of both hemispheres): the east
## coasts against the west ones, which the sea keeps mild. For the lab: it should grow with `wind`.
func coast_contrast() -> float:
	var windward := 0.0
	var leeward := 0.0
	var windward_count := 0
	var leeward_count := 0
	for row in HEIGHT:
		var lat := absf((0.5 - (float(row) + 0.5) / float(HEIGHT)) * PI)
		if lat < deg_to_rad(35.0) or lat > deg_to_rad(65.0):
			continue
		for column in WIDTH:
			var index := row * WIDTH + column
			if _sea[index] == 1:
				continue
			var west_sea := _sea[row * WIDTH + (column + WIDTH - 1) % WIDTH] == 1
			var east_sea := _sea[row * WIDTH + (column + 1) % WIDTH] == 1
			if west_sea == east_sea:
				continue
			var low := INF
			var high := -INF
			for picture in _cycle:
				low = minf(low, picture[index])
				high = maxf(high, picture[index])
			if west_sea:
				windward += high - low
				windward_count += 1
			else:
				leeward += high - low
				leeward_count += 1
	if windward_count == 0 or leeward_count == 0:
		return 0.0
	return leeward / float(leeward_count) - windward / float(windward_count)


## The heat shared between neighbouring cells (a diffusion: the sea wraps east-west, the poles are
## closed).
func _mix(heat: PackedFloat32Array) -> void:
	var shared := heat.duplicate()
	for row in HEIGHT:
		var north := maxi(row - 1, 0) * WIDTH
		var south := mini(row + 1, HEIGHT - 1) * WIDTH
		for column in WIDTH:
			var index := row * WIDTH + column
			var west := row * WIDTH + (column + WIDTH - 1) % WIDTH
			var east := row * WIDTH + (column + 1) % WIDTH
			var around := (heat[west] + heat[east] + heat[north + column] + heat[south + column]) * 0.25
			shared[index] = lerpf(heat[index], around, MIX)
	for index in heat.size():
		heat[index] = shared[index]


## Degrees C at sea level at the unit direction, `year_share` through the year (0 the northern
## spring equinox), read off the cycle. Any share works, forward or backward.
func at(dir: Vector3, year_share: float) -> float:
	var position := fposmod(year_share, 1.0) * float(SNAPSHOTS)
	var first := int(floorf(position)) % SNAPSHOTS
	var blend := position - floorf(position)
	var a := _look(_cycle[first], dir)
	var b := _look(_cycle[(first + 1) % SNAPSHOTS], dir)
	return lerpf(a, b, blend)


## The yearly mean at the direction (bilinear).
func mean_at(dir: Vector3) -> float:
	return _look(mean, dir)


func _look(grid: PackedFloat32Array, dir: Vector3) -> float:
	var lat := asin(clampf(dir.y, -1.0, 1.0))
	var lon := atan2(dir.z, dir.x)
	var fx := (lon + PI) / TAU * float(WIDTH) - 0.5
	var fy := (0.5 - lat / PI) * float(HEIGHT) - 0.5
	var x0 := floori(fx)
	var y0 := floori(fy)
	var tx := fx - float(x0)
	var ty := fy - float(y0)
	var total := 0.0
	for dy in 2:
		for dx in 2:
			var weight := (tx if dx == 1 else 1.0 - tx) * (ty if dy == 1 else 1.0 - ty)
			total += grid[clampi(y0 + dy, 0, HEIGHT - 1) * WIDTH + posmod(x0 + dx, WIDTH)] * weight
	return total
