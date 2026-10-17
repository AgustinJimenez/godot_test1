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
			lines.append("  planet %d %-11s a=%.2fAU r=%.1fEarth year=%.0fd day=%.0fh tilt=%.0f%s"
					% [number + 1, StarSystem.kind_name(planet["kind"]), planet["orbit_au"],
					planet["radius_earth"], planet["year_standard_days"], planet["day_standard_hours"],
					planet["tilt_deg"], " HABITABLE" if planet["habitable"] else ""])
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
	ok = ok and system(3).system_seed == system(3).system_seed and system_seed(1) != system_seed(2)
	return ok
