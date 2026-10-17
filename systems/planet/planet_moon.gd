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


const DISTANCE := 60.0 ## the moon's distance in planet radii (Earth 60)
const MOON_RADIUS := 0.27 ## the moon's radius in planet radii (Earth 0.27)
const STAR_ANGULAR := 0.0047 ## the star's apparent radius from the planet (radians, Sun 0.0047)
const UMBRA := 0.72 ## the planet's shadow radius at the moon's distance, in planet radii


## How much of the star the moon hides from planet direction `where` (a unit vector in the planet's
## frame, on the surface): 0 none, 1 all (a total eclipse). The moon is near, so where you stand
## shifts where it appears (parallax); only the geometry decides, nothing is scripted.
static func solar_cover(clock: PlanetClock, where: Vector3) -> float:
	var star := clock.sun_in_body()
	if where.dot(star) <= 0.0:
		return 0.0 # night: nothing to cover
	var to_moon := in_body(clock) * DISTANCE - where
	var seen := to_moon.normalized()
	var moon_angular := asin(MOON_RADIUS / to_moon.length())
	return _overlap(seen.angle_to(star), moon_angular, STAR_ANGULAR)


## How deep the moon is in the planet's shadow: 0 outside it, 1 fully inside (a total lunar
## eclipse). Seen from anywhere on the night side, the same for everyone.
static func lunar_depth(clock: PlanetClock) -> float:
	var star := clock.sun_in_body()
	var spot := in_body(clock) * DISTANCE
	if spot.dot(star) >= 0.0:
		return 0.0 # on the star's side of the planet
	var off_axis := (spot - star * spot.dot(star)).length()
	return clampf((UMBRA + MOON_RADIUS - off_axis) / (2.0 * MOON_RADIUS), 0.0, 1.0)


## The share (0..1) of a disc of angular radius `hidden` that a disc of radius `cover` hides when
## the centres are `apart` radians apart (a straight blend from touching to one inside the other).
static func _overlap(apart: float, cover: float, hidden: float) -> float:
	var reach := cover + hidden
	if apart >= reach:
		return 0.0
	var inside := absf(cover - hidden)
	if apart <= inside:
		return minf(1.0, cover * cover / (hidden * hidden))
	return (reach - apart) / (reach - inside) * minf(1.0, cover * cover / (hidden * hidden))
