class_name UniverseSettings
extends Resource
## The universe: a seed and how many star systems it has. System N always comes from the seed and
## N, so no system is stored. Pure data, nothing built here.

@export var universe_seed := 1337
@export var system_count := 1 ## starts at one star system (more come with travel)
@export var sunlike_home := true ## the first system is a Sun-like star with a habitable planet
@export var region_size := 60.0 ## light years across the volume the systems sit in


## The seed of system `index`: a mix of the universe seed and the number.
func system_seed(index: int) -> int:
	return hash([universe_seed, index])


## System `index` (0-based). Only the first one is made Sun-like when `sunlike_home` is set.
func system(index: int) -> StarSystem:
	var made := StarSystem.generate(system_seed(index), sunlike_home and index == 0)
	var rng := RandomNumberGenerator.new()
	rng.seed = system_seed(index) ^ 0x5eed
	made.position = Vector3.ZERO if index == 0 else Vector3(rng.randf_range(-1.0, 1.0),
			rng.randf_range(-0.3, 0.3), rng.randf_range(-1.0, 1.0)) * region_size * 0.5
	return made


## The settings of planet `number` (0-based) of system `index`, from the star and the orbit: the
## same ids always give the same planet. Rocky planets only for now (other kinds: task 061).
## Game scale: Earth is 20,000 m; the year is the true one in local days, clamped to 6..64.
func planet_settings(index: int, number: int) -> PlanetSettings:
	var made := PlanetSettings.new()
	var system_data := system(index)
	var body: Dictionary = system_data.planets[number]
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([system_data.system_seed, number])
	made.world_seed = rng.randi() & 0x7fffffff
	made.radius = 20000.0 * clampf(body["radius_earth"], 0.4, 2.2)
	var day_hours: float = body["day_standard_hours"]
	made.day_seconds = day_hours * 60.0
	made.year_days = clampf(body["year_standard_days"] * 24.0 / day_hours, 6.0, 64.0)
	made.axial_tilt = body["tilt_deg"]
	made.eccentricity = body["eccentricity"]
	made.perihelion_share = body["perihelion_share"]
	made.universe_seed = universe_seed
	made.universe_system = index
	made.universe_planet = number
	made.universe_sunlike = 1 if sunlike_home else 0
	var star := system_data.stars[0]
	made.star_mass = star.mass
	made.insolation = star.luminosity / (body["orbit_au"] * body["orbit_au"])
	if body["habitable"]:
		made.ocean_fraction = rng.randf_range(0.55, 0.8)
	else:
		made.ocean_fraction = rng.randf_range(0.0, 0.3)
	return made


## The planet the player starts on: the first habitable planet of system 0, else its first rocky one
## (other kinds wait for task 061). A system without any is made Sun-like instead, so there is
## always a home. `readability` is the start menu's star colour setting (0 true .. 1 readable).
func home_settings(readability := 0.0) -> PlanetSettings:
	var first := system(0)
	var number := _home_number(first)
	if number < 0:
		var fixed := UniverseSettings.new()
		fixed.universe_seed = universe_seed
		fixed.sunlike_home = true
		var made := fixed.planet_settings(0, fixed._home_number(fixed.system(0)))
		made.star_readability = readability
		made.universe_sunlike = 1
		return made
	var home := planet_settings(0, number)
	home.star_readability = readability
	return home


func _home_number(system_data: StarSystem) -> int:
	var rocky := -1
	for number in system_data.planets.size():
		var planet: Dictionary = system_data.planets[number]
		if planet["habitable"]:
			return number
		if rocky < 0 and planet["kind"] <= StarSystem.Kind.LARGE_ROCKY:
			rocky = number
	return rocky


## A text table of the first `count` systems, one line per planet, for the lab (`--universe=SEED`).
func table(count: int) -> PackedStringArray:
	var lines := PackedStringArray()
	for index in count:
		var system_data := system(index)
		var star := system_data.stars[0]
		lines.append("SYSTEM %d seed=%d class=%s mass=%.2f L=%.3f T=%.0fK colour=%s life=%.1fGyr "
				% [index, system_data.system_seed, star.spectral_class, star.mass,
				star.luminosity, star.temperature, star.colour.to_html(false), star.lifetime]
				+ "HZ=%.2f-%.2fAU planets=%d" % [star.habitable_zone().x, star.habitable_zone().y,
				system_data.planets.size()])
		for number in system_data.planets.size():
			var planet: Dictionary = system_data.planets[number]
			var notes := " HABITABLE" if planet["habitable"] else ""
			notes += " LOCKED" if planet["locked"] else ""
			lines.append("  planet %d %-11s a=%.2fAU r=%.1fEarth year=%.0fd day=%.0fh tilt=%.0f%s"
					% [number + 1, StarSystem.kind_name(planet["kind"]), planet["orbit_au"],
					planet["radius_earth"], planet["year_standard_days"], planet["day_standard_hours"],
					planet["tilt_deg"], notes])
	return lines


## Pass/fail for the lab (`UNIVERSE_CHECK`): the same ids give the same planet twice, the Sun-like
## start has a G or K star with a habitable planet, and every derived planet is playable.
func self_check() -> bool:
	var ok := true
	var first := system(0)
	if sunlike_home:
		ok = ok and first.stars[0].spectral_class in ["G", "K"] and first.planets.any(
				func(planet: Dictionary) -> bool: return planet["habitable"])
	for number in first.planets.size():
		var a := planet_settings(0, number)
		var b := planet_settings(0, number)
		ok = ok and a.world_seed == b.world_seed and a.radius == b.radius
		ok = ok and a.year_days == b.year_days and a.radius >= 8000.0 and a.day_seconds > 0.0
	var orbit := PlanetClock.new() # an ellipse: nearest at perihelion, farthest half a year later
	orbit.eccentricity = 0.2
	orbit.perihelion_share = 0.25
	orbit.set_year_share(0.25)
	ok = ok and absf(orbit.distance() - 0.8) < 0.001
	orbit.set_year_share(0.75)
	ok = ok and absf(orbit.distance() - 1.2) < 0.001 and orbit.light_now() < 1.0
	var green := Color(0.26, 0.5, 0.18) # leaves: the Sun's are unchanged, a red dwarf's darker
	ok = ok and StarLight.leaf_colour(green, Star.from_mass(1.0)) == green
	ok = ok and StarLight.leaf_colour(green, Star.from_mass(0.15)).v < green.v * 0.7
	ok = ok and StarLight.leaf_colour(green, Star.from_mass(0.15), 1.0) == green
	var tide := PlanetClock.new() # spring tides at new moon (aligned), neap at the first quarter
	tide.moon_tilt = 0.0
	tide.set_year_share(0.0)
	var spring := _tide_range(tide)
	tide.time = tide.day_seconds * tide.month_days * 0.25
	ok = ok and spring > _tide_range(tide) * 1.2 and spring > 0.0
	ok = ok and _eclipse_check()
	ok = ok and Star.from_mass(0.2).lock_distance() > Star.from_mass(0.2).habitable_zone().y
	ok = ok and Star.from_mass(1.0).lock_distance() < Star.from_mass(1.0).habitable_zone().x
	ok = ok and system(3).system_seed == system(3).system_seed and system_seed(1) != system_seed(2)
	return ok


## The tide's range (m) at the equator over one day: the highest minus the lowest height.
static func _tide_range(clock: PlanetClock) -> float:
	var high := -INF
	var low := INF
	var start := clock.time
	for step in 48:
		clock.time = start + clock.day_seconds * step / 48.0
		var value: float = PlanetTides.height(clock, Vector3.RIGHT)
		high = maxf(high, value)
		low = minf(low, value)
	clock.time = start
	return high - low


## Eclipses from the geometry: with the moon's orbit flat they happen at new moon (the star's
## light covered) and full moon (the moon in the planet's shadow), not at the quarters, and a
## tilted orbit away from the nodes has none.
static func _eclipse_check() -> bool:
	var clock := PlanetClock.new()
	clock.moon_tilt = 0.0
	clock.set_year_share(0.0)
	var month := clock.day_seconds * clock.month_days
	var best_new := 0.0
	var best_full := 0.0
	var quarter := 0.0
	for step in 4000:
		clock.time = month * step / 4000.0
		var sub := PlanetMoon.in_body(clock)
		var phase := PlanetMoon.lit(clock)
		if phase < 0.0001:
			best_new = maxf(best_new, PlanetMoon.solar_cover(clock, sub))
		elif phase > 0.9999:
			best_full = maxf(best_full, PlanetMoon.lunar_depth(clock))
		elif absf(phase - 0.5) < 0.1:
			quarter = maxf(quarter, PlanetMoon.solar_cover(clock, sub))
			quarter = maxf(quarter, PlanetMoon.lunar_depth(clock))
	clock.moon_tilt = deg_to_rad(5.1)
	clock.set_year_share(0.25) # the nodes are at the equinoxes: no eclipse at the solstice
	var tilted := 0.0
	for step in 4000:
		clock.time = month * step / 4000.0
		tilted = maxf(tilted, PlanetMoon.lunar_depth(clock))
		tilted = maxf(tilted, PlanetMoon.solar_cover(clock, PlanetMoon.in_body(clock)))
	print("ECLIPSES new=%.2f full=%.2f quarter=%.2f tilted=%.2f"
			% [best_new, best_full, quarter, tilted])
	return best_new > 0.5 and best_full > 0.5 and quarter == 0.0 and tilted == 0.0
