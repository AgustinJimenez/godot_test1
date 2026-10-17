class_name StarSystem
extends Resource
## One star system: a list of stars (one for now; a binary is a later step) and the planets on
## their orbits. Everything comes from the system's seed, so the same seed is always the same
## system. Orbits follow Kepler's third law from the star's mass. Pure data.

## What a planet is made of, from the size and the distance to the star.
enum Kind { ROCKY, LARGE_ROCKY, ICE_GIANT, GAS_GIANT }

const MAX_PLANETS := 8

@export var system_seed := 0
@export var position := Vector3.ZERO ## light years, in the universe's region
@export var stars: Array[Star] = []
## One dictionary per planet, inner to outer: orbit_au, radius_earth, kind (Kind),
## year_standard_days, day_standard_hours, tilt_deg, habitable (rocky, inside the water zone),
## locked (tidally locked: one side always faces the star; flagged only, the clock still spins it).
@export var planets: Array[Dictionary] = []


## The system a seed makes. `sunlike_home` makes it a Sun-like star with a rocky planet in its
## habitable zone (the start menu's "sun-like and habitable"); false is any star and any planets.
static func generate(seed_value: int, sunlike_home := false) -> StarSystem:
	var system := StarSystem.new()
	system.system_seed = seed_value
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var star_mass := _random_mass(rng)
	if sunlike_home:
		star_mass = rng.randf_range(0.9, 1.1)
	var star := Star.from_mass(star_mass, rng.randf_range(2.5, 8.0))
	star.age = minf(star.age, star.lifetime * 0.9)
	system.stars.append(star)
	system._make_planets(rng, sunlike_home)
	return system


## Stars are mostly small: a mass from a power law (many red dwarfs, a few bright ones).
static func _random_mass(rng: RandomNumberGenerator) -> float:
	return clampf(0.1 * pow(1.0 - rng.randf() * 0.9, -0.9), 0.1, 3.0)


func _make_planets(rng: RandomNumberGenerator, sunlike_home: bool) -> void:
	var star := stars[0]
	var zone := star.habitable_zone()
	var count := rng.randi_range(0, MAX_PLANETS)
	var distance := rng.randf_range(0.1, 0.4) * maxf(sqrt(star.luminosity), 0.3)
	for index in count:
		planets.append(_planet_at(rng, star, distance, zone))
		distance *= rng.randf_range(1.4, 2.0)
	if sunlike_home and not _has_habitable():
		var home := _planet_at(rng, star, rng.randf_range(zone.x * 1.05, zone.y * 0.9), zone)
		home["kind"] = Kind.ROCKY
		home["radius_earth"] = rng.randf_range(0.8, 1.3)
		home["habitable"] = true
		planets.append(home)
		planets.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			return a["orbit_au"] < b["orbit_au"])


func _has_habitable() -> bool:
	for planet in planets:
		if planet["habitable"]:
			return true
	return false


func _planet_at(rng: RandomNumberGenerator, star: Star, distance: float,
		zone: Vector2) -> Dictionary:
	var kind := Kind.ROCKY
	var radius_earth := rng.randf_range(0.4, 1.5)
	if distance > star.frost_line():
		var roll := rng.randf()
		kind = Kind.GAS_GIANT if roll < 0.5 else Kind.ICE_GIANT
		radius_earth = rng.randf_range(3.5, 11.0)
		if roll >= 0.85:
			kind = Kind.LARGE_ROCKY
			radius_earth = rng.randf_range(1.5, 2.2)
	elif rng.randf() < 0.25:
		kind = Kind.LARGE_ROCKY
		radius_earth = rng.randf_range(1.5, 2.2)
	var rocky := kind == Kind.ROCKY or kind == Kind.LARGE_ROCKY
	return {
		"orbit_au": distance,
		"radius_earth": radius_earth,
		"kind": kind,
		"year_standard_days": 365.25 * sqrt(pow(distance, 3.0) / star.mass),
		"day_standard_hours": rng.randf_range(10.0, 40.0),
		"tilt_deg": rng.randf_range(0.0, 40.0),
		"eccentricity": rng.randf_range(0.0, 0.2) * rng.randf(),
		"perihelion_share": rng.randf(),
		"habitable": rocky and distance >= zone.x and distance <= zone.y,
		"locked": distance < star.lock_distance(),
	}


static func kind_name(kind: int) -> String:
	return ["rocky", "large rocky", "ice giant", "gas giant"][kind]
