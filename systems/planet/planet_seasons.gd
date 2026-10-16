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
const FLOOR := 0.11 ## heat the air and the ground still give off in the dark
const SNOW_ALBEDO := 0.3 ## share of the light a frozen cell reflects
const LAND_TAU := 0.05 ## years a cell of land takes to move most of the way to its balance
const SEA_TAU := 0.2 ## and a cell of sea
const MIX := 0.3 ## share of a cell's heat shared with its neighbours each pass
const PASSES := 3 ## passes a step
const HOT := 27.0 ## degrees C above which evaporation and cloud take most of the extra heat
const MAX_YEARS := 8

var mean := PackedFloat32Array() ## degrees C at sea level, averaged over the year
var _cycle: Array[PackedFloat32Array] = [] # SNAPSHOTS grids of degrees C at sea level
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


## One step of `dt` years, from the share `at` - dt/2 to at + dt/2 of the year.
func _step(heat: PackedFloat32Array, light: PackedFloat32Array, clock: PlanetClock, at: float,
		dt: float) -> void:
	clock.set_year_share(at)
	for row in HEIGHT:
		light[row] = clock.daily_light((0.5 - (float(row) + 0.5) / float(HEIGHT)) * PI)
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
			if balance > HOT: # water evaporates and clouds form: not all the extra heat is kept
				balance = HOT + (balance - HOT) * 0.35
			heat[index] = degrees + (balance - degrees) * (sea_pull if _sea[index] == 1 else land_pull)
	for pass_number in PASSES:
		_mix(heat)


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
