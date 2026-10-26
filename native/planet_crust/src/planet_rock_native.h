#pragma once

// PlanetRock (was systems/planet/planet_rock.gd): the crust's rock, from the setting it formed in, and its colour. A mix of nine rocks
// weighed by what makes them (sea floor basalt, volcanic boundaries, cratons, sedimentary basins, stripped high ground), blended by weight,
// with soil, cover, snow, ice and sand over it. A pure function of the position. (The native crust has the same maths for the bulk work.)

#include "native_props.h"
#include "planet_tectonics_native.h"

#include <godot_cpp/classes/fast_noise_lite.hpp>
#include <godot_cpp/classes/ref.hpp>
#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/color.hpp>
#include <godot_cpp/variant/packed_color_array.hpp>
#include <godot_cpp/variant/packed_float32_array.hpp>
#include <godot_cpp/variant/vector3.hpp>

namespace godot {

class PlanetRock : public RefCounted {
	GDCLASS(PlanetRock, RefCounted)

	Ref<PlanetTectonics> tectonics;
	double relief = 300.0;
	double radius = 20000.0;
	Ref<FastNoiseLite> craton_noise; // where the old continental cores are
	Ref<FastNoiseLite> basin_noise; // which sedimentary rock a basin has

protected:
	static void _bind_methods();

public:
	enum Kind { BASALT, ANDESITE, GRANITE, GNEISS, SCHIST, LIMESTONE, SANDSTONE, RED_SANDSTONE, SHALE };
	static constexpr double BOUNDARY = 0.08; // radians: how far a boundary's rock reaches
	static constexpr double LAPSE = 0.0065; // degrees C the air cools a metre higher

	static double get_boundary() { return BOUNDARY; }
	static int64_t kind_count() { return 9; }
	static PackedColorArray colours();

	// `PlanetRock.new(tectonics, world_seed, radius, relief)` of the script
	static Ref<PlanetRock> create(const Ref<PlanetTectonics> &p_tectonics, int64_t p_world_seed, double p_radius, double p_relief);

	Ref<FastNoiseLite> get__craton() const { return craton_noise; }
	void set__craton(const Ref<FastNoiseLite> &p_v) { craton_noise = p_v; }
	Ref<FastNoiseLite> get__basin() const { return basin_noise; }
	void set__basin(const Ref<FastNoiseLite> &p_v) { basin_noise = p_v; }

	PackedFloat32Array weights(const Vector3 &p_dir, double p_ground) const;
	int64_t dominant(const Vector3 &p_dir, double p_ground) const;
	Color colour(const Vector3 &p_dir, double p_ground, double p_steep, double p_speckle, double p_sea_temperature = 15.0, bool p_strata = true,
			double p_rain = 0.5) const;
};

} // namespace godot

VARIANT_ENUM_CAST(PlanetRock::Kind);
