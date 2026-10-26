#pragma once

// PlanetClock (was systems/planet/planet_clock.gd): the planet's place in its star system as real geometry: the orbit, the spin, the tilt,
// and from them the star's direction, the hour, the seasons' light. The planet's frame: +Y is the north pole, longitude atan2(z, x).

#include "native_props.h"

#include <godot_cpp/classes/ref.hpp>
#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/vector3.hpp>

namespace godot {

class PlanetClock : public RefCounted {
	GDCLASS(PlanetClock, RefCounted)

	double _spin_offset = 0.0; // the spin angle (radians) at time 0: where the start asks the sun to be
	double _year_start = 0.0; // the share of the year (0..1) at time 0, 0 being the northern spring equinox

	double _sidereal_seconds() const;
	double _year_seconds() const;
	double _orbit_angle() const;
	double _true_anomaly() const;
	Vector3 _axis_inertial() const;

protected:
	static void _bind_methods();

public:
	NP_FIELD(double, day_seconds, 1440.0) // a solar day, in seconds of play (a clock day)
	NP_FIELD(double, year_days, 16.0) // solar days in a year
	NP_FIELD(double, axial_tilt, 23.4 * Math_PI / 180.0) // radians
	NP_FIELD(double, eccentricity, 0.0) // 0 a circle .. <1 an ellipse (Earth 0.017)
	NP_FIELD(double, perihelion_share, 0.0) // the share of the year at which the planet is nearest the star
	NP_FIELD(double, insolation, 1.0) // the star's light at the planet's distance, against the Earth's (L / a^2)
	NP_FIELD(double, time, 0.0) // seconds since the start
	NP_FIELD(double, month_days, 3.5) // solar days the moon takes to go round the planet (game scale, not real)
	NP_FIELD(double, moon_tilt, 5.1 * Math_PI / 180.0) // the moon's orbit against the planet's orbit
	NP_FIELD(double, node_years, 6.0) // years the moon orbit takes to turn once about the axis (Earth 18.6)

	void start(double p_year_share_at_start, double p_hour, const Vector3 &p_where);
	double absolute_days() const;
	void advance(double p_seconds);
	void set_year(double p_share, const Vector3 &p_where);
	void set_year_share(double p_share);
	Dictionary snapshot() const;
	void restore(const Dictionary &p_state);
	Ref<PlanetClock> copy() const;
	double year_share() const;
	double distance() const;
	double light_now() const;
	Vector3 star_inertial() const;
	double spin_angle() const;
	Vector3 sun_in_body() const;
	double sun_height_at(const Vector3 &p_where) const;
	double declination() const;
	double local_hour(const Vector3 &p_where) const;
	double daily_light(double p_lat) const;
	double day_length(double p_lat) const;
};

} // namespace godot
