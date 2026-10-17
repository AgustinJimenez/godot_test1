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
