#pragma once

// PlanetMoon, PlanetTides and PlanetAir (were systems/planet/planet_moon.gd, planet_tides.gd, planet_air.gd): static maths of the sky.
// The moon's orbit and eclipses, the equilibrium tide, and the atmosphere's scattering (the same maths as shaders/world/planet_sky.gdshader).

#include "planet_clock_native.h"

#include <godot_cpp/classes/ref.hpp>
#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/vector2.hpp>
#include <godot_cpp/variant/vector3.hpp>

namespace godot {

class PlanetMoon : public RefCounted {
	GDCLASS(PlanetMoon, RefCounted)

	static double overlap(double p_apart, double p_cover, double p_hidden);

protected:
	static void _bind_methods();

public:
	static constexpr double DISTANCE = 60.0; // the moon's distance in planet radii (Earth 60)
	static constexpr double MOON_RADIUS = 0.27; // the moon's radius in planet radii (Earth 0.27)
	static constexpr double STAR_ANGULAR = 0.0047; // the star's apparent radius from the planet (radians, Sun 0.0047)
	static constexpr double UMBRA = 0.72; // the planet's shadow radius at the moon's distance, in planet radii

	static Vector3 inertial(const Ref<PlanetClock> &p_clock);
	static Vector3 in_body(const Ref<PlanetClock> &p_clock);
	static double lit(const Ref<PlanetClock> &p_clock);
	static double solar_cover(const Ref<PlanetClock> &p_clock, const Vector3 &p_where);
	static double lunar_depth(const Ref<PlanetClock> &p_clock);
};

class PlanetTides : public RefCounted {
	GDCLASS(PlanetTides, RefCounted)

	static double bulge(const Vector3 &p_where, const Vector3 &p_toward);

protected:
	static void _bind_methods();

public:
	static constexpr double MOON_AMPLITUDE = 0.5; // m, the moon's bulge at the mean moon distance (Earth ~0.36)
	static constexpr double STAR_SHARE = 0.46; // the star's bulge against the moon's (the Sun's on Earth)

	static double height(const Ref<PlanetClock> &p_clock, const Vector3 &p_where, double p_coast = 1.0);
};

class PlanetAir : public RefCounted {
	GDCLASS(PlanetAir, RefCounted)

protected:
	static void _bind_methods();

public:
	static constexpr double BETA_MIE = 21e-6;
	static constexpr double OZONE_DEPTH = 1.9;
	static constexpr double SCALE_RAYLEIGH = 8000.0; // m: how fast the molecules thin out with height (the Earth's)
	static constexpr double SCALE_MIE = 1200.0; // m: the haze and dust, which hug the ground (the Earth's)
	static constexpr double EARTH_RADIUS = 6371000.0;
	static constexpr double MIN_AIR_SCALE = 0.25;

	static Vector3 beta_rayleigh() { return Vector3(5.8e-6, 13.5e-6, 33.1e-6); }
	static Vector3 beta_ozone() { return Vector3(0.65e-6, 1.881e-6, 0.085e-6); }
	static double get_earth_radius() { return EARTH_RADIUS; }
	static double get_min_air_scale() { return MIN_AIR_SCALE; }

	static double scale_for(double p_radius);
	static bool hits_planet(const Vector3 &p_from, const Vector3 &p_along, double p_radius);
	static double to_top(const Vector3 &p_from, const Vector3 &p_along, double p_top);
	static Vector3 sun_transmittance(const Vector3 &p_from, const Vector3 &p_sun, double p_radius, double p_top, double p_air_scale = 1.0);
	static Vector3 sky_color(const Vector3 &p_from, const Vector3 &p_along, const Vector3 &p_sun, double p_radius, double p_top,
			double p_intensity, double p_air_scale = 1.0);
	static Vector2 sun_transmittance_inner(const Vector3 &p_at, const Vector3 &p_sun, double p_radius, double p_top, double p_air_scale = 1.0);
};

} // namespace godot
