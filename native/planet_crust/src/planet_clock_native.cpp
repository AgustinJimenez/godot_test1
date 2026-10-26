#include "planet_clock_native.h"

#include <godot_cpp/variant/basis.hpp>
#include <godot_cpp/variant/utility_functions.hpp>

#include <cmath>

using namespace godot;

static const double TAU_D = 6.283185307179586476925286766559;
static const double PI_D = 3.14159265358979323846;

// wrapf of GDScript: into [min, max)
static double wrap_range(double p_value, double p_min, double p_max) {
	double range = p_max - p_min;
	if (range == 0.0) {
		return p_min;
	}
	double result = p_value - range * std::floor((p_value - p_min) / range);
	if (result == p_max) {
		return p_min;
	}
	return result;
}

static double positive_mod(double p_x, double p_y) {
	double value = std::fmod(p_x, p_y);
	if ((value < 0.0 && p_y > 0.0) || (value > 0.0 && p_y < 0.0)) {
		value += p_y;
	}
	return value;
}

void PlanetClock::_bind_methods() {
#define B(VT, N) NP_BIND(PlanetClock, VT, N)
	B(Variant::FLOAT, day_seconds)
	B(Variant::FLOAT, year_days)
	B(Variant::FLOAT, axial_tilt)
	B(Variant::FLOAT, eccentricity)
	B(Variant::FLOAT, perihelion_share)
	B(Variant::FLOAT, insolation)
	B(Variant::FLOAT, time)
	B(Variant::FLOAT, month_days)
	B(Variant::FLOAT, moon_tilt)
	B(Variant::FLOAT, node_years)
#undef B
	ClassDB::bind_method(D_METHOD("start", "year_share_at_start", "hour", "where"), &PlanetClock::start);
	ClassDB::bind_method(D_METHOD("absolute_days"), &PlanetClock::absolute_days);
	ClassDB::bind_method(D_METHOD("advance", "seconds"), &PlanetClock::advance);
	ClassDB::bind_method(D_METHOD("set_year", "share", "where"), &PlanetClock::set_year);
	ClassDB::bind_method(D_METHOD("set_year_share", "share"), &PlanetClock::set_year_share);
	ClassDB::bind_method(D_METHOD("snapshot"), &PlanetClock::snapshot);
	ClassDB::bind_method(D_METHOD("restore", "state"), &PlanetClock::restore);
	ClassDB::bind_method(D_METHOD("copy"), &PlanetClock::copy);
	ClassDB::bind_method(D_METHOD("year_share"), &PlanetClock::year_share);
	ClassDB::bind_method(D_METHOD("distance"), &PlanetClock::distance);
	ClassDB::bind_method(D_METHOD("light_now"), &PlanetClock::light_now);
	ClassDB::bind_method(D_METHOD("star_inertial"), &PlanetClock::star_inertial);
	ClassDB::bind_method(D_METHOD("spin_angle"), &PlanetClock::spin_angle);
	ClassDB::bind_method(D_METHOD("sun_in_body"), &PlanetClock::sun_in_body);
	ClassDB::bind_method(D_METHOD("sun_height_at", "where"), &PlanetClock::sun_height_at);
	ClassDB::bind_method(D_METHOD("declination"), &PlanetClock::declination);
	ClassDB::bind_method(D_METHOD("local_hour", "where"), &PlanetClock::local_hour);
	ClassDB::bind_method(D_METHOD("daily_light", "lat"), &PlanetClock::daily_light);
	ClassDB::bind_method(D_METHOD("day_length", "lat"), &PlanetClock::day_length);
}

// The seconds of one turn of the planet against the stars (the sidereal day): a bit shorter than the solar day, because the planet also
// goes round the star (one more turn in a year than there are days).
double PlanetClock::_sidereal_seconds() const {
	return 1.0 / (1.0 / day_seconds + 1.0 / (year_days * day_seconds));
}

double PlanetClock::_year_seconds() const {
	return year_days * day_seconds;
}

// Sets the start: the share of the year (0 the northern spring equinox ... 0.75 the winter solstice) and the local solar `hour` (12 is
// noon) at the planet direction `where` (a unit vector in the planet's frame).
void PlanetClock::start(double p_year_share_at_start, double p_hour, const Vector3 &p_where) {
	time = 0.0;
	_year_start = p_year_share_at_start;
	_spin_offset = 0.0;
	// turn the planet until the sun has the wanted hour angle at `where` (the sun moves west, so the hour angle, the local longitude
	// minus the sun's, grows through the day)
	Vector3 sun = sun_in_body();
	double want = (p_hour - 12.0) / 24.0 * TAU_D;
	double have = std::atan2(p_where.z, p_where.x) - std::atan2(sun.z, sun.x);
	_spin_offset = wrap_range(have - want, -PI_D, PI_D);
}

// The days gone by since the start of the year the clock began in (solar days): what the winds, the clouds and the moon follow.
double PlanetClock::absolute_days() const {
	return _year_start * year_days + time / day_seconds;
}

void PlanetClock::advance(double p_seconds) {
	time += p_seconds;
}

// Moves the orbit to `share` of the year without moving the hour of day anywhere.
void PlanetClock::set_year(double p_share, const Vector3 &p_where) {
	start(p_share, local_hour(p_where), p_where);
}

// Sets the share of the year only (no care for the hour; for the climate model, which does not look at the spin).
void PlanetClock::set_year_share(double p_share) {
	_year_start = p_share;
	time = 0.0;
}

// The numbers a save keeps to bring the clock back exactly.
Dictionary PlanetClock::snapshot() const {
	Dictionary state;
	state["time"] = time;
	state["year_start"] = _year_start;
	state["spin_offset"] = _spin_offset;
	return state;
}

void PlanetClock::restore(const Dictionary &p_state) {
	time = (double)p_state.get("time", time);
	_year_start = (double)p_state.get("year_start", _year_start);
	_spin_offset = (double)p_state.get("spin_offset", _spin_offset);
}

// A copy of this clock as it is now (a worker thread can read it while the game moves on).
Ref<PlanetClock> PlanetClock::copy() const {
	Ref<PlanetClock> other;
	other.instantiate();
	other->day_seconds = day_seconds;
	other->year_days = year_days;
	other->axial_tilt = axial_tilt;
	other->insolation = insolation;
	other->eccentricity = eccentricity;
	other->perihelion_share = perihelion_share;
	other->time = time;
	other->month_days = month_days;
	other->moon_tilt = moon_tilt;
	other->node_years = node_years;
	other->_spin_offset = _spin_offset;
	other->_year_start = _year_start;
	return other;
}

// The share of the year (0..1, 0 the northern spring equinox).
double PlanetClock::year_share() const {
	return positive_mod(_year_start + time / _year_seconds(), 1.0);
}

// The planet's angle round the star (radians): on a circle it grows evenly with the year; on an ellipse it goes faster near the star.
double PlanetClock::_orbit_angle() const {
	return PI_D * 0.5 + TAU_D * perihelion_share + _true_anomaly();
}

// The angle from the nearest point of the orbit (radians, -PI..PI) at this time of year.
double PlanetClock::_true_anomaly() const {
	double mean = wrap_range(TAU_D * (year_share() - perihelion_share), -PI_D, PI_D);
	if (eccentricity <= 0.0) {
		return mean;
	}
	double anomaly = mean + eccentricity * std::sin(mean); // a first guess, then Newton's steps
	for (int step = 0; step < 5; step++) {
		anomaly -= (anomaly - eccentricity * std::sin(anomaly) - mean) / (1.0 - eccentricity * std::cos(anomaly));
	}
	return 2.0 * std::atan2(std::sqrt(1.0 + eccentricity) * std::sin(anomaly * 0.5), std::sqrt(1.0 - eccentricity) * std::cos(anomaly * 0.5));
}

// The distance to the star now, in the orbit's semi-major axes (1 on a circle).
double PlanetClock::distance() const {
	return (1.0 - eccentricity * eccentricity) / (1.0 + eccentricity * std::cos(_true_anomaly()));
}

// The star's light at the planet now against the Earth's mean: it falls with the distance squared.
double PlanetClock::light_now() const {
	double away = distance();
	return insolation / (away * away);
}

// The direction from the planet to its star, in the inertial frame (the orbit lies in x, z).
Vector3 PlanetClock::star_inertial() const {
	double angle = _orbit_angle();
	return Vector3(-std::cos(angle), 0.0, -std::sin(angle));
}

// The planet's axis in the inertial frame: tilted from the ecliptic's normal (+Y), fixed in space.
Vector3 PlanetClock::_axis_inertial() const {
	return Vector3(std::sin(axial_tilt), std::cos(axial_tilt), 0.0);
}

// The turn of the planet (radians) at the current time. Spinning eastward moves the star west across its sky.
double PlanetClock::spin_angle() const {
	return _spin_offset - TAU_D * time / _sidereal_seconds();
}

// The star as seen from the planet's own frame (a unit vector: toward the star).
Vector3 PlanetClock::sun_in_body() const {
	Basis tilt(Vector3(0, 0, 1), -axial_tilt); // body +Y onto the tilted axis
	Basis spin(Vector3(0, 1, 0), spin_angle());
	Basis inertial_to_body = (tilt * spin).inverse();
	return inertial_to_body.xform(star_inertial());
}

// How high the star stands over the horizon at planet direction `where` (the sine of the elevation).
double PlanetClock::sun_height_at(const Vector3 &p_where) const {
	return sun_in_body().dot(p_where);
}

// The latitude (radians) over which the star stands straight up at noon today.
double PlanetClock::declination() const {
	return std::asin(CLAMP(star_inertial().dot(_axis_inertial()), -1.0, 1.0));
}

// The local solar time at `where` in hours (12 is noon, when the star is on the local meridian).
double PlanetClock::local_hour(const Vector3 &p_where) const {
	Vector3 sun = sun_in_body();
	double angle = wrap_range(std::atan2(p_where.z, p_where.x) - std::atan2(sun.z, sun.x), -PI_D, PI_D);
	return positive_mod(12.0 + angle / TAU_D * 24.0, 24.0);
}

// Mean sunlight (0..1 of the full vertical sun) at latitude `lat` (radians) over a whole day at this time of year.
double PlanetClock::daily_light(double p_lat) const {
	double dec = declination();
	double cos_h0 = -std::tan(p_lat) * std::tan(dec); // the hour angle of sunrise
	if (cos_h0 >= 1.0) {
		return 0.0; // the polar night
	}
	double h0 = cos_h0 <= -1.0 ? PI_D : std::acos(cos_h0); // the polar day lasts all round
	return (h0 * std::sin(p_lat) * std::sin(dec) + std::cos(p_lat) * std::cos(dec) * std::sin(h0)) / PI_D;
}

// The length of the day at latitude `lat` (radians), as a share of a solar day (0 polar night, 1 polar day).
double PlanetClock::day_length(double p_lat) const {
	double cos_h0 = -std::tan(p_lat) * std::tan(declination());
	if (cos_h0 >= 1.0) {
		return 0.0;
	}
	if (cos_h0 <= -1.0) {
		return 1.0;
	}
	return std::acos(cos_h0) / PI_D;
}
