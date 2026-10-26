#pragma once

// PlanetNoise (was systems/planet/planet_noise.gd): the shape and climate of a planet: height, rain, warmth and biome at any direction from its
// centre. The land comes from tectonic plates at the scale of the planet and from noise below that; the climate from latitude, height and the
// winds. Pure functions of the direction and the seed, so any tile can be built alone and neighbours agree on their shared edge.
// The ground itself is PlanetCrustNative (this class builds its setup from the seed and keeps the planet's other parts: plates, rock, climate,
// weather, drainage, species). The GDScript reference of the height and colour maths that this file used to carry is gone with the port.

#include "native_props.h"
#include "planet_climate_native.h"
#include "planet_clock_native.h"
#include "planet_crust_native.h"
#include "planet_drainage_script_native.h"
#include "planet_rock_native.h"
#include "planet_settings_native.h"
#include "planet_tectonics_native.h"
#include "planet_water_native.h"
#include "planet_weather_native.h"

#include <godot_cpp/classes/fast_noise_lite.hpp>
#include <godot_cpp/classes/ref.hpp>
#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/color.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/packed_color_array.hpp>
#include <godot_cpp/variant/packed_float32_array.hpp>
#include <godot_cpp/variant/packed_vector3_array.hpp>
#include <godot_cpp/variant/vector3.hpp>

namespace godot {

class PlanetNoise : public RefCounted {
	GDCLASS(PlanetNoise, RefCounted)

	Ref<FastNoiseLite> rolling, ranges, range_mask, hills, gullies, detail_noise;
	Ref<FastNoiseLite> massif, chain, foothills;
	Ref<FastNoiseLite> valleys[3]; // three scales of valley networks (the work of erosion)
	double valley_depth[3] = { 0.0, 0.0, 0.0 };
	double sea_ = 0.0; // the height (units of relief) that is sea level, so the ocean covers its share
	uint64_t lap_at = 0;

	void init(const Ref<PlanetSettings> &p_settings);
	void lap(const String &p_what);
	static void setup_noise(const Ref<FastNoiseLite> &p_noise, int64_t p_seed, double p_frequency, int p_octaves);
	void make_scatter();
	PackedVector3Array hotspots() const;
	void make_native();
	void find_sea_level();
	void carve_valleys();

protected:
	static void _bind_methods();

public:
	static constexpr double SPAWN_ABOVE_SEA = 3.0; // m: the lowest ground the character may start on
	static constexpr double SPAWN_FROM_WATER = 6.0; // m from a river or a lake
	static constexpr double LAPSE = 6.5; // degrees C lost per km of height
	static constexpr double EARTH_RELIEF = 8800.0; // m: what "one relief" is on Earth
	// Beaches and shallows: the ground eases toward the sea instead of dropping into it
	static constexpr double SHORE = 0.2;
	static constexpr double VALLEY_WIDTH = 0.09; // of the noise's range either side of its zero line
	static constexpr double CHAINS = 0.5; // of the relief: the chains of mountains, the broadest rough ground
	static constexpr double MASSIF = 0.15; // of the relief: the height of the massifs on the roughest ground
	static constexpr double FOOTHILLS = 0.0; // and of the foothills (the eroded ridges took their place)
	static constexpr double EROSION = 0.20; // of the relief: the eroded ridges (0 turns them off)
	static constexpr int EROSION_OCTAVES = 9;
	static constexpr double EROSION_SCALE = 1.1; // of the massifs' length: the first wavelength of the eroded ridges
	static constexpr double HYPSO = 1.4; // land heights h become pivot * (h / pivot) ^ this: low ground lower, peaks kept
	static constexpr double HYPSO_PIVOT = 0.5; // of the relief
	static constexpr double LAND_CURVE = 1.6; // the land's height share is raised to this: plains common, plateaus rare
	static constexpr double DEEP = 1.6; // how much deeper the ocean floor is than the plates' slope alone (abyssal depth)
	static constexpr double SHORE_FLAT = 0.16;

	NP_FIELD(Ref<PlanetSettings>, settings, Ref<PlanetSettings>())
	NP_FIELD(double, relief, 1000.0) // m, from the sea to the top of the highest ranges (see PlanetSettings)
	NP_FIELD(Ref<PlanetTectonics>, tectonics, Ref<PlanetTectonics>())
	NP_FIELD(Ref<PlanetClimate>, climate, Ref<PlanetClimate>())
	NP_FIELD(Variant, species, Variant()) // the plants of this planet (a SpeciesRegistry)
	NP_FIELD(Ref<PlanetWeather>, weather, Ref<PlanetWeather>()) // the clouds and the weather (made once the climate is)
	NP_FIELD(Ref<PlanetClock>, clock, Ref<PlanetClock>()) // the time of day and the season (set by PlanetWorld; null: the yearly mean)
	NP_FIELD(Vector3, clearing, Vector3()) // where the player starts: trees and rocks keep off a little round it
	NP_FIELD(Ref<PlanetRock>, rock, Ref<PlanetRock>()) // the colour of the crust
	NP_FIELD(Ref<RefCounted>, scatter_native, Ref<RefCounted>()) // the native plant placement (PlanetScatterNative)
	NP_FIELD(Ref<PlanetCrustNative>, native, Ref<PlanetCrustNative>()) // the native crust
	NP_FIELD(Ref<PlanetWaterNative>, water_native, Ref<PlanetWaterNative>()) // pure native tile-water geometry
	NP_FIELD(Ref<PlanetDrainage>, drainage, Ref<PlanetDrainage>()) // where the water runs (coarse), when the planet has it
	NP_FIELD(Dictionary, map_heights, Dictionary()) // the heights of the whole planet's map passes, by the picture's size

	double get__sea() const { return sea_; }
	void set__sea(double p_v) { sea_ = p_v; }

	// `PlanetNoise.new(settings)` of the script
	static Ref<PlanetNoise> create(const Ref<PlanetSettings> &p_settings);
	static Array noise_config(const Ref<FastNoiseLite> &p_source);
	static PackedVector3Array cube_faces();

	double water_at(const Vector3 &p_dir, double p_ground) const;
	bool near_water(const Vector3 &p_dir, double p_ground, double p_margin) const;
	Vector3 flow_at(const Vector3 &p_dir) const;
	PackedFloat32Array heights_of(const PackedVector3Array &p_dirs) const;
	PackedFloat32Array macro_heights_of(const PackedVector3Array &p_dirs, double p_pixel = -1.0) const;
	PackedColorArray colours_of(const PackedVector3Array &p_dirs, const PackedFloat32Array &p_grounds, const PackedFloat32Array &p_steeps) const;
	double height(double p_x, double p_y, double p_z) const;
	double macro_height(double p_x, double p_y, double p_z) const;
	double shore(double p_units) const;
	double moisture(double p_x, double p_y, double p_z) const;
	double heat(double p_x, double p_y, double p_z, double p_ground) const;
	double temperature(double p_x, double p_y, double p_z, double p_ground) const;
	double temperature_now(double p_x, double p_y, double p_z, double p_ground, const Ref<PlanetClock> &p_at_clock = Ref<PlanetClock>(), double p_macro = NAN) const;
	double detail(double p_x, double p_y, double p_z) const;
	double detail_at(const Vector3 &p_point) const;
	int64_t biome(double p_x, double p_y, double p_z, double p_ground, double p_steepness) const;
	Color facet_color(double p_x, double p_y, double p_z, double p_ground, double p_steep, bool p_coarse = false) const;
	bool is_solid_ground(const Vector3 &p_dir) const;
	Vector3 solid_spawn(const Vector3 &p_dir) const;
	Vector3 find_spawn(bool p_in_desert = false) const;
};

} // namespace godot
