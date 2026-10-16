class_name PlanetClock
extends RefCounted
## The planet's place in its star system, as real geometry and not as a faked sky. The planet
## circles its star in a plane (the ecliptic) once a year and spins once a (sidereal) day about an
## axis that is tilted by `axial_tilt` from the ecliptic's normal and points the same way in space
## all year. From those four numbers everything follows: where the star is for anyone on the planet
## (so day and night, sunrise and sunset, the sun's height at noon by latitude and by season), the
## length of the day at each latitude (the polar day and night), and the seasons (the hemisphere
## that leans toward the star is warm). The planet's own frame is the one the rest of the planet
## code uses: +Y is the north pole, longitude is atan2(z, x). The orbit is a circle (an ellipse
## later); the star is far enough away that its light comes in parallel.
##
## Time is in seconds of play. A day is `day_seconds` long measured sun to sun (the solar day, what
## a clock shows); the year is `year_days` of them.

var day_seconds := 1440.0 ## a solar day, in seconds of play (a clock day)
var year_days := 16.0 ## solar days in a year
var axial_tilt := deg_to_rad(23.4) ## radians
var time := 0.0 ## seconds since the start

var _spin_offset := 0.0 # the spin angle (radians) at time 0: where the start asks the sun to be
var _year_start := 0.0 # the share of the year (0..1) at time 0, 0 being the northern spring equinox


## The seconds of one turn of the planet against the stars (the sidereal day): a bit shorter than
## the solar day, because the planet also goes round the star (one more turn in a year than there
## are days).
func sidereal_seconds() -> float:
	return 1.0 / (1.0 / day_seconds + 1.0 / (year_days * day_seconds))


func year_seconds() -> float:
	return year_days * day_seconds


## Sets the start: the share of the year (0 is the northern spring equinox, 0.25 the northern summer
## solstice, 0.5 the autumn equinox, 0.75 the winter solstice) and the local solar `hour` (0..24, 12
## is noon) at the planet direction `where` (a unit vector in the planet's frame).
func start(year_share_at_start: float, hour: float, where: Vector3) -> void:
	time = 0.0
	_year_start = year_share_at_start
	_spin_offset = 0.0
	# turn the planet until the sun has the wanted hour angle at `where` (the sun moves west, so the
	# hour angle, the local longitude minus the sun's, grows through the day)
	var sun := sun_in_body()
	var want := (hour - 12.0) / 24.0 * TAU
	var have := atan2(where.z, where.x) - atan2(sun.z, sun.x)
	_spin_offset = wrapf(have - want, -PI, PI)


func advance(seconds: float) -> void:
	time += seconds


## Moves the orbit to `share` of the year (0 the northern spring equinox) without moving the hour
## of day anywhere: the planet's turn is kept to the same sun hour at the direction `where`.
func set_year(share: float, where: Vector3) -> void:
	start(share, local_hour(where), where)


## Sets the share of the year only (no care for the hour; for the climate model, which does not
## look at the spin).
func set_year_share(share: float) -> void:
	_year_start = share
	time = 0.0


## A copy of this clock as it is now (a worker thread can read it while the game moves on).
func copy() -> PlanetClock:
	var other := PlanetClock.new()
	other.day_seconds = day_seconds
	other.year_days = year_days
	other.axial_tilt = axial_tilt
	other.time = time
	other._spin_offset = _spin_offset
	other._year_start = _year_start
	return other


## The share of the year (0..1, 0 the northern spring equinox).
func year_share() -> float:
	return fposmod(_year_start + time / year_seconds(), 1.0)


## The planet's angle round the star (radians).
func orbit_angle() -> float:
	return PI * 0.5 + TAU * year_share()


## The direction from the planet to its star, in the inertial frame (the orbit lies in x, z).
func star_inertial() -> Vector3:
	var angle := orbit_angle()
	return Vector3(-cos(angle), 0.0, -sin(angle))


## The planet's axis in the inertial frame: tilted from the ecliptic's normal (+Y), fixed in space.
func axis_inertial() -> Vector3:
	return Vector3(sin(axial_tilt), cos(axial_tilt), 0.0)


## The turn of the planet (radians) at the current time. Spinning the planet eastward (counter
## clockwise seen from the north pole) moves the star west across its sky.
func spin_angle() -> float:
	return _spin_offset - TAU * time / sidereal_seconds()


## The star as seen from the planet's own frame (a unit vector: toward the star).
func sun_in_body() -> Vector3:
	var tilt := Basis(Vector3.BACK, -axial_tilt) # body +Y onto the tilted axis
	var spin := Basis(Vector3.UP, spin_angle())
	var inertial_to_body := (tilt * spin).inverse()
	return inertial_to_body * star_inertial()


## How high the star stands over the horizon at planet direction `where` (the sine of the elevation:
## 1 straight up, 0 on the horizon, negative below it).
func sun_height_at(where: Vector3) -> float:
	return sun_in_body().dot(where)


## The latitude (radians) over which the star stands straight up at noon today: how far the warm
## belt has moved. It is 0 at the equinoxes and the tilt at the solstices.
func declination() -> float:
	return asin(clampf(star_inertial().dot(axis_inertial()), -1.0, 1.0))


## The local solar time at `where` in hours (12 is noon, when the star is on the local meridian).
func local_hour(where: Vector3) -> float:
	var sun := sun_in_body()
	var angle := wrapf(atan2(where.z, where.x) - atan2(sun.z, sun.x), -PI, PI)
	return fposmod(12.0 + angle / TAU * 24.0, 24.0)


## Mean sunlight (0..1 of the full vertical sun) at latitude `lat` (radians) over a whole day at
## this time of year: the daily mean of max(0, sun height). This is what warms a latitude by season.
func daily_light(lat: float) -> float:
	var dec := declination()
	var cos_h0 := -tan(lat) * tan(dec) # the hour angle of sunrise
	if cos_h0 >= 1.0:
		return 0.0 # the polar night
	var h0 := PI if cos_h0 <= -1.0 else acos(cos_h0) # the polar day lasts all round
	return (h0 * sin(lat) * sin(dec) + cos(lat) * cos(dec) * sin(h0)) / PI


## The length of the day at latitude `lat` (radians), as a share of a solar day (0 polar night, 1
## polar day).
func day_length(lat: float) -> float:
	var cos_h0 := -tan(lat) * tan(declination())
	if cos_h0 >= 1.0:
		return 0.0
	if cos_h0 <= -1.0:
		return 1.0
	return acos(cos_h0) / PI
