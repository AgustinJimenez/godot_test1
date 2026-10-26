#include "planet_sky_native.h"

#include <godot_cpp/variant/basis.hpp>

#include <algorithm>
#include <cmath>

using namespace godot;

static const double TAU_D = 6.283185307179586476925286766559;
static const double PI_D = 3.14159265358979323846;

// ---- PlanetMoon ----

void PlanetMoon::_bind_methods() {
	ClassDB::bind_static_method("PlanetMoon", D_METHOD("inertial", "clock"), &PlanetMoon::inertial);
	ClassDB::bind_static_method("PlanetMoon", D_METHOD("in_body", "clock"), &PlanetMoon::in_body);
	ClassDB::bind_static_method("PlanetMoon", D_METHOD("lit", "clock"), &PlanetMoon::lit);
	ClassDB::bind_static_method("PlanetMoon", D_METHOD("solar_cover", "clock", "where"), &PlanetMoon::solar_cover);
	ClassDB::bind_static_method("PlanetMoon", D_METHOD("lunar_depth", "clock"), &PlanetMoon::lunar_depth);
}

// The direction from the planet to its moon in the inertial frame.
Vector3 PlanetMoon::inertial(const Ref<PlanetClock> &p_clock) {
	double angle = 1.0 + TAU_D * p_clock->absolute_days() / p_clock->get_month_days();
	Vector3 flat(std::cos(angle), 0.0, std::sin(angle));
	double node = TAU_D * p_clock->absolute_days() / (p_clock->get_node_years() * p_clock->get_year_days());
	Basis turned = Basis(Vector3(0, 1, 0), node) * Basis(Vector3(1, 0, 0), p_clock->get_moon_tilt());
	return turned.xform(flat);
}

// The moon as seen from the planet's own frame (a unit vector toward it).
Vector3 PlanetMoon::in_body(const Ref<PlanetClock> &p_clock) {
	Basis tilt(Vector3(0, 0, 1), -p_clock->get_axial_tilt());
	Basis spin(Vector3(0, 1, 0), p_clock->spin_angle());
	return (tilt * spin).inverse().xform(inertial(p_clock)).normalized();
}

// The share of the moon's face the star lights, as we see it: 0 new, 1 full.
double PlanetMoon::lit(const Ref<PlanetClock> &p_clock) {
	return (1.0 - inertial(p_clock).dot(p_clock->star_inertial())) * 0.5;
}

// How much of the star the moon hides from planet direction `where`: 0 none, 1 all (a total eclipse).
double PlanetMoon::solar_cover(const Ref<PlanetClock> &p_clock, const Vector3 &p_where) {
	Vector3 star = p_clock->sun_in_body();
	if (p_where.dot(star) <= 0.0) {
		return 0.0; // night: nothing to cover
	}
	Vector3 to_moon = in_body(p_clock) * DISTANCE - p_where;
	Vector3 seen = to_moon.normalized();
	double moon_angular = std::asin(MOON_RADIUS / to_moon.length());
	return overlap(seen.angle_to(star), moon_angular, STAR_ANGULAR);
}

// How deep the moon is in the planet's shadow: 0 outside it, 1 fully inside (a total lunar eclipse).
double PlanetMoon::lunar_depth(const Ref<PlanetClock> &p_clock) {
	Vector3 star = p_clock->sun_in_body();
	Vector3 spot = in_body(p_clock) * DISTANCE;
	if (spot.dot(star) >= 0.0) {
		return 0.0; // on the star's side of the planet
	}
	double off_axis = (spot - star * spot.dot(star)).length();
	return CLAMP((UMBRA + MOON_RADIUS - off_axis) / (2.0 * MOON_RADIUS), 0.0, 1.0);
}

// The share (0..1) of a disc of angular radius `hidden` that a disc of radius `cover` hides when the centres are `apart` radians apart.
double PlanetMoon::overlap(double p_apart, double p_cover, double p_hidden) {
	double reach = p_cover + p_hidden;
	if (p_apart >= reach) {
		return 0.0;
	}
	double inside = std::abs(p_cover - p_hidden);
	if (p_apart <= inside) {
		return std::min(1.0, p_cover * p_cover / (p_hidden * p_hidden));
	}
	return (reach - p_apart) / (reach - inside) * std::min(1.0, p_cover * p_cover / (p_hidden * p_hidden));
}

// ---- PlanetTides ----

void PlanetTides::_bind_methods() {
	ClassDB::bind_static_method("PlanetTides", D_METHOD("height", "clock", "where", "coast"), &PlanetTides::height, DEFVAL(1.0));
}

double PlanetTides::bulge(const Vector3 &p_where, const Vector3 &p_toward) {
	double cosine = p_where.dot(p_toward);
	return (3.0 * cosine * cosine - 1.0) * 0.5;
}

// The height of the tide (m) at the planet direction `where`, `coast` scaling it (1 an open coast).
double PlanetTides::height(const Ref<PlanetClock> &p_clock, const Vector3 &p_where, double p_coast) {
	Vector3 moon = PlanetMoon::in_body(p_clock);
	Vector3 star = p_clock->sun_in_body();
	return p_coast * MOON_AMPLITUDE * (bulge(p_where, moon) + STAR_SHARE * bulge(p_where, star));
}

// ---- PlanetAir ----

void PlanetAir::_bind_methods() {
	ClassDB::bind_static_method("PlanetAir", D_METHOD("beta_rayleigh"), &PlanetAir::beta_rayleigh);
	ClassDB::bind_static_method("PlanetAir", D_METHOD("beta_ozone"), &PlanetAir::beta_ozone);
	ClassDB::bind_static_method("PlanetAir", D_METHOD("get_earth_radius"), &PlanetAir::get_earth_radius);
	ClassDB::bind_static_method("PlanetAir", D_METHOD("get_min_air_scale"), &PlanetAir::get_min_air_scale);
	ClassDB::bind_static_method("PlanetAir", D_METHOD("scale_for", "radius"), &PlanetAir::scale_for);
	ClassDB::bind_static_method("PlanetAir", D_METHOD("hits_planet", "from", "along", "radius"), &PlanetAir::hits_planet);
	ClassDB::bind_static_method("PlanetAir", D_METHOD("to_top", "from", "along", "top"), &PlanetAir::to_top);
	ClassDB::bind_static_method("PlanetAir", D_METHOD("sun_transmittance", "from", "sun", "radius", "top", "air_scale"), &PlanetAir::sun_transmittance, DEFVAL(1.0));
	ClassDB::bind_static_method("PlanetAir", D_METHOD("sky_color", "from", "along", "sun", "radius", "top", "intensity", "air_scale"), &PlanetAir::sky_color, DEFVAL(1.0));
	ClassDB::bind_static_method("PlanetAir", D_METHOD("sun_transmittance_inner", "at", "sun", "radius", "top", "air_scale"), &PlanetAir::sun_transmittance_inner, DEFVAL(1.0));
}

// The air's size against the Earth's for a planet of `radius`.
double PlanetAir::scale_for(double p_radius) {
	return std::max(p_radius / EARTH_RADIUS, MIN_AIR_SCALE);
}

// True if the ray from `from` along `along` (a unit vector) hits the planet of `radius`.
bool PlanetAir::hits_planet(const Vector3 &p_from, const Vector3 &p_along, double p_radius) {
	double b = p_from.dot(p_along);
	if (b > 0.0) {
		return false; // pointing away from the planet's centre
	}
	double closest_sq = p_from.length_squared() - b * b;
	return closest_sq < p_radius * p_radius;
}

// The distance along the ray from `from` to where it leaves the atmosphere (radius `top`).
double PlanetAir::to_top(const Vector3 &p_from, const Vector3 &p_along, double p_top) {
	double b = p_from.dot(p_along);
	double c = p_from.length_squared() - p_top * p_top;
	return -b + std::sqrt(std::max(b * b - c, 0.0));
}

// The share of the sun's light of each colour that reaches the point `from` through the air toward `sun`: 0 where the planet is in the way.
Vector3 PlanetAir::sun_transmittance(const Vector3 &p_from, const Vector3 &p_sun, double p_radius, double p_top, double p_air_scale) {
	if (hits_planet(p_from, p_sun, p_radius)) {
		return Vector3();
	}
	double length = to_top(p_from, p_sun, p_top);
	int steps = 12;
	double step_length = length / (double)steps;
	double rayleigh = 0.0;
	double mie = 0.0;
	for (int index = 0; index < steps; index++) {
		Vector3 at = p_from + p_sun * ((double)index + 0.5) * step_length;
		double height = at.length() - p_radius;
		rayleigh += std::exp(-height / (SCALE_RAYLEIGH * p_air_scale)) * step_length;
		mie += std::exp(-height / (SCALE_MIE * p_air_scale)) * step_length;
	}
	Vector3 beta = beta_rayleigh() + beta_ozone() * OZONE_DEPTH;
	Vector3 tau = (beta * rayleigh + Vector3(1, 1, 1) * BETA_MIE * 1.1 * mie) / p_air_scale;
	return Vector3(std::exp(-tau.x), std::exp(-tau.y), std::exp(-tau.z));
}

// The colour of the sky seen from `from` along `along`, lit by `sun` (single scattering), in units where the sun's own light is 1.
Vector3 PlanetAir::sky_color(const Vector3 &p_from, const Vector3 &p_along, const Vector3 &p_sun, double p_radius, double p_top,
		double p_intensity, double p_air_scale) {
	double far_end = to_top(p_from, p_along, p_top);
	if (hits_planet(p_from, p_along, p_radius)) {
		double b = p_from.dot(p_along);
		double disc = b * b - (p_from.length_squared() - p_radius * p_radius);
		far_end = std::min(far_end, std::max(-b - std::sqrt(std::max(disc, 0.0)), 0.0));
	}
	int steps = 10;
	double mu = p_along.dot(p_sun);
	double phase_r = 3.0 / (16.0 * PI_D) * (1.0 + mu * mu);
	double g = 0.76;
	double phase_m = 3.0 / (8.0 * PI_D) * ((1.0 - g * g) * (1.0 + mu * mu)) / ((2.0 + g * g) * std::pow(1.0 + g * g - 2.0 * g * mu, 1.5));
	Vector3 sum_r, sum_m;
	double depth_r = 0.0;
	double depth_m = 0.0;
	for (int index = 0; index < steps; index++) {
		// the steps crowd toward the eye (cubed), as in the sky shader: equal steps skip the dense air near the viewer
		double u0 = std::pow((double)index / (double)steps, 3.0);
		double u1 = std::pow((double)(index + 1) / (double)steps, 3.0);
		double step_length = far_end * (u1 - u0);
		Vector3 at = p_from + p_along * far_end * 0.5 * (u0 + u1);
		double height = at.length() - p_radius;
		double hr = std::exp(-height / (SCALE_RAYLEIGH * p_air_scale)) * step_length;
		double hm = std::exp(-height / (SCALE_MIE * p_air_scale)) * step_length;
		depth_r += hr;
		depth_m += hm;
		Vector2 light = sun_transmittance_inner(at, p_sun, p_radius, p_top, p_air_scale);
		if (light.x < 0.0) {
			continue;
		}
		Vector3 tau = (beta_rayleigh() + beta_ozone() * OZONE_DEPTH) * (depth_r + light.x);
		tau += Vector3(1, 1, 1) * BETA_MIE * 1.1 * (depth_m + light.y);
		tau /= p_air_scale;
		Vector3 attenuation(std::exp(-tau.x), std::exp(-tau.y), std::exp(-tau.z));
		sum_r += attenuation * hr;
		sum_m += attenuation * hm;
	}
	return (sum_r * beta_rayleigh() * phase_r + sum_m * BETA_MIE * phase_m) * p_intensity / p_air_scale;
}

// The optical depths (Rayleigh, Mie) from `at` to the sun, or (-1, 0) if the planet blocks it.
Vector2 PlanetAir::sun_transmittance_inner(const Vector3 &p_at, const Vector3 &p_sun, double p_radius, double p_top, double p_air_scale) {
	if (hits_planet(p_at, p_sun, p_radius)) {
		return Vector2(-1.0, 0.0);
	}
	double length = to_top(p_at, p_sun, p_top);
	int steps = 4;
	double step_length = length / (double)steps;
	double rayleigh = 0.0;
	double mie = 0.0;
	for (int index = 0; index < steps; index++) {
		Vector3 point = p_at + p_sun * ((double)index + 0.5) * step_length;
		double height = point.length() - p_radius;
		rayleigh += std::exp(-height / (SCALE_RAYLEIGH * p_air_scale)) * step_length;
		mie += std::exp(-height / (SCALE_MIE * p_air_scale)) * step_length;
	}
	return Vector2(rayleigh, mie);
}
