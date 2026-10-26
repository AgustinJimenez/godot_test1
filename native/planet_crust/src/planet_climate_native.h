#pragma once

// PlanetSeasons and PlanetClimate (were systems/planet/planet_seasons.gd and planet_climate.gd): the planet's temperature through its year
// (an energy balance on a coarse grid, run by PlanetSeasonsNative until the cycle repeats) and its climate as two low resolution maps, the
// temperature at sea level and the rain. The script-only fallbacks of the old files (the year and the rain run in GDScript, "to compare")
// are gone: PlanetSeasonsNative / PlanetDrainageNative are the one implementation.

#include "native_props.h"
#include "planet_clock_native.h"

#include <godot_cpp/classes/object.hpp>
#include <godot_cpp/classes/ref.hpp>
#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/packed_byte_array.hpp>
#include <godot_cpp/variant/packed_float32_array.hpp>
#include <godot_cpp/variant/vector2.hpp>
#include <godot_cpp/variant/vector3.hpp>

namespace godot {

class PlanetSeasons : public RefCounted {
	GDCLASS(PlanetSeasons, RefCounted)

	Array cycle_; // SNAPSHOTS grids (PackedFloat32Array) of degrees C at sea level
	PackedByteArray sea_; // 1 where the cell is sea (2 + 100 times the dryness on land)

	static double look(const PackedFloat32Array &p_grid, const Vector3 &p_dir);

protected:
	static void _bind_methods();

public:
	static constexpr int WIDTH = 96;
	static constexpr int HEIGHT = 48;
	static constexpr int SNAPSHOTS = 48;
	static constexpr double EMIT = 0.34; // the absorbed sunlight (share of the full sun) that balances at 15 C
	static constexpr double FLOOR = 0.13; // heat the air and the ground still give off in the dark
	static constexpr double SNOW_ALBEDO = 0.3; // share of the light a frozen cell reflects
	static constexpr double LAND_TAU = 0.05; // years a cell of land takes to move most of the way to its balance
	static constexpr double SEA_TAU = 0.2; // and a cell of sea
	static constexpr double MIX = 0.3; // share of a cell's heat shared with its neighbours each pass
	static constexpr int PASSES = 3; // passes a step
	static constexpr double HOT = 27.0; // degrees C above which evaporation and cloud take most of the extra heat
	static constexpr int MAX_YEARS = 8;
	static constexpr double WIND = 0.2; // share of a cell the zonal wind carries the heat each pass (at its strongest)

	static Dictionary dry();
	static Dictionary currents();
	static Dictionary heat();

	NP_FIELD(PackedFloat32Array, mean, PackedFloat32Array()) // degrees C at sea level, averaged over the year
	NP_FIELD(double, greenhouse, 1.0) // how much heat the air holds in (1: Earth's)
	NP_FIELD(double, wind_k, 3.0) // the planet's wind profile: -cos(wind_k * latitude)
	NP_FIELD(double, wind, WIND) // the lab sets 0 to see the climate without the wind
	NP_FIELD(bool, native_year, true) // (kept for the scripts that set it; the year is always run natively now)

	// `noise`: a PlanetNoise (macro_heights_of); `clock` carries the orbit and the tilt
	void build(Object *p_noise, const Ref<PlanetClock> &p_clock);
	double coast_contrast() const;
	double at(const Vector3 &p_dir, double p_year_share) const;
	PackedFloat32Array blended(double p_year_share) const;
	double mean_at(const Vector3 &p_dir) const;
};

class PlanetClimate : public RefCounted {
	GDCLASS(PlanetClimate, RefCounted)

	PackedFloat32Array temperature_; // degrees C at sea level
	PackedFloat32Array rain_; // 0 none .. ~1.5 a rain forest
	Ref<PlanetSeasons> seasons_;
	Dictionary circulation_;

	void draw_circulation(int64_t p_world_seed);

protected:
	static void _bind_methods();

public:
	static constexpr int WIDTH = 384; // (the rain below is tuned for 192: its per-cell terms scale by WIDTH / 192)
	static constexpr int HEIGHT = 192;
	static constexpr double RAIN_BASE = 0.08; // the share of the moisture in the air that falls on a flat cell
	static constexpr double RAIN_SCALE = 5.0;

	PlanetClimate();

	Ref<PlanetSeasons> get_seasons() const { return seasons_; }
	void set_seasons(const Ref<PlanetSeasons> &p_v) { seasons_ = p_v; }
	Dictionary get_circulation() const { return circulation_; }
	void set_circulation(const Dictionary &p_v) { circulation_ = p_v; }
	NP_FIELD(bool, native_rain, true) // (kept for the scripts that set it; the rain is always made natively now)

	void build(Object *p_noise);
	PackedFloat32Array rain_grid() const { return rain_; }
	PackedFloat32Array temperature_grid() const { return temperature_; }
	double sea_temperature(const Vector3 &p_dir) const;
	Vector2 sample(const Vector3 &p_dir) const;
};

} // namespace godot
