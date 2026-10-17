class_name PlanetTides
extends RefCounted
## The equilibrium tide: the sea bulges toward the moon and away from it, and the star does the
## same, weaker. The pull on a point goes as (3 cos^2 a - 1) / 2, a being the angle between the
## point's direction and the body. Moon and star bulges add: at new and full moon they line up
## (spring tides), at the quarters they cross (neap). Pure functions of the clock, so a tide is a
## function of the date.

const MOON_AMPLITUDE := 0.5 ## m, the moon's bulge at the mean moon distance (Earth ~0.36)
const STAR_SHARE := 0.46 ## the star's bulge against the moon's (the Sun's on Earth)


static func _bulge(where: Vector3, toward: Vector3) -> float:
	var cosine := where.dot(toward)
	return (3.0 * cosine * cosine - 1.0) * 0.5


## The height of the tide (m) at the planet direction `where` (a unit vector in the planet's
## frame), `coast` scaling it (1 an open coast; a funnel-shaped bay is more, the open sea less).
static func height(clock: PlanetClock, where: Vector3, coast := 1.0) -> float:
	var moon := PlanetMoon.in_body(clock)
	var star := clock.sun_in_body()
	return coast * MOON_AMPLITUDE * (_bulge(where, moon) + STAR_SHARE * _bulge(where, star))
