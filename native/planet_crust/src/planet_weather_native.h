#pragma once

// PlanetWeather (was systems/planet/planet_weather.gd): the weather of the planet, from its causes. Clouds form where moist air is lifted and
// cooled (moisture from the seasons' temperature and the rain climate, lifted along the trade-wind belt, the storm tracks and up the mountains,
// held down under the subtropical highs); the winds carry them, and the pattern is a function of the date. From the clouds, the temperature and
// the moisture, the weather at a place: clear, cloudy, fog, rain, storm, snow.

#include "native_props.h"
#include "planet_climate_native.h"
#include "planet_clock_native.h"

#include <godot_cpp/classes/fast_noise_lite.hpp>
#include <godot_cpp/classes/object.hpp>
#include <godot_cpp/classes/ref.hpp>
#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/vector2.hpp>
#include <godot_cpp/variant/vector3.hpp>

namespace godot {

class PlanetWeather : public RefCounted {
	GDCLASS(PlanetWeather, RefCounted)

	ObjectID noise_id; // the PlanetNoise (not held: it holds this)
	Ref<FastNoiseLite> big_a, big_b, small, pool, warp; // the weather systems, the second pattern, the clumps, the warm pools, the swirls
	// This planet's own weather: how far its belts sit from the usual latitudes, how strong each is, and how much longitude breaks them
	double belt_shift = 0.0; // radians the equatorial belt sits off the equator
	double belt_power = 1.0;
	double storm_shift = 0.0; // radians the storm tracks sit from their usual latitude
	double storm_power = 1.0;
	double wind_k_ = 4.0; // this planet's wind profile (PlanetClimate.circulation)
	double sink_shift = 0.0; // radians the dry highs sit from their usual latitude
	double sink_power = 1.0; // the dry subtropical highs
	double pool_break = 1.0; // 0 the belt is even, 1 strongly broken by the pools

	Object *noise() const;
	Ref<PlanetClimate> climate() const;
	static void setup_noise(const Ref<FastNoiseLite> &p_source, int64_t p_seed, double p_frequency, int p_octaves);
	static Array noise_config(const Ref<FastNoiseLite> &p_source);
	double monsoon(const Vector3 &p_dir, const Ref<PlanetClock> &p_clock, double p_wet, double p_macro) const;
	double macro_of(const Vector3 &p_dir, double p_macro) const;
	double moisture(const Vector3 &p_dir, const Ref<PlanetClock> &p_clock, double p_macro) const;

protected:
	static void _bind_methods();

public:
	enum Kind { CLEAR, CLOUDY, RAIN, STORM, FOG, SNOW }; // the same order as WorldWeather.State
	static constexpr double SHEAR_DAYS = 2.5; // how long the weather systems drift before they fade into a fresh copy
	static constexpr double WARP = 0.45; // how far the swirls push the places the cloud pattern is read from
	static constexpr double WIND_TURN = 0.035; // the share of a turn the strongest wind carries the clouds in a day

	static double get_wind_turn() { return WIND_TURN; }
	// `PlanetWeather.new(noise)` of the script
	static Ref<PlanetWeather> create(Object *p_noise);

	Dictionary config() const;
	static double zonal_wind(double p_lat, double p_wind_k = 4.0);
	double wind_k() const { return wind_k_; }
	double readiness(const Vector3 &p_dir, const Ref<PlanetClock> &p_clock, double p_macro = NAN) const;
	double cloud(const Vector3 &p_dir, const Ref<PlanetClock> &p_clock, double p_macro = NAN) const;
	Vector2 cloud_cells(const Vector3 &p_dir, const Ref<PlanetClock> &p_clock, double p_macro = NAN) const;
	Dictionary at(const Vector3 &p_dir, double p_ground, const Ref<PlanetClock> &p_clock) const;
};

} // namespace godot

VARIANT_ENUM_CAST(PlanetWeather::Kind);
