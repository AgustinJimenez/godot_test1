class_name PlanetMoon
extends RefCounted
## The planet's moon, from the orbit it follows: a circle round the planet, a little tilted against
## the planet's own orbit (so eclipses are rare), once every `PlanetClock.month_days` days (game
## scale, not real). Where it is in the sky and how much of its face the star lights (its phase)
## follow from the geometry, the same as the sun.


## The direction from the planet to its moon in the inertial frame.
static func inertial(clock: PlanetClock) -> Vector3:
	var angle := 1.0 + TAU * clock.absolute_days() / clock.month_days
	var flat := Vector3(cos(angle), 0.0, sin(angle))
	return Basis(Vector3.RIGHT, clock.moon_tilt) * flat


## The moon as seen from the planet's own frame (a unit vector toward it).
static func in_body(clock: PlanetClock) -> Vector3:
	var tilt := Basis(Vector3.BACK, -clock.axial_tilt)
	var spin := Basis(Vector3.UP, clock.spin_angle())
	return ((tilt * spin).inverse() * inertial(clock)).normalized()


## The share of the moon's face the star lights, as we see it: 0 new, 1 full (the moon is a sphere
## lit from one side: it is full when it is opposite the star).
static func lit(clock: PlanetClock) -> float:
	return (1.0 - inertial(clock).dot(clock.star_inertial())) * 0.5
