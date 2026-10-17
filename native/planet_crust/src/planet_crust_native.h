#pragma once

// The planet's crust in native code: the height of the ground and the colour of its rock, the same
// maths as PlanetTectonics, PlanetNoise and PlanetRock (GDScript), which stay the reference. The
// numbers come from GDScript in `setup`, so the two cannot drift apart by a copied constant; a lab
// check compares the two on thousands of points.

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/color.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/packed_byte_array.hpp>
#include <godot_cpp/variant/packed_color_array.hpp>
#include <godot_cpp/variant/packed_float32_array.hpp>
#include <godot_cpp/variant/packed_vector3_array.hpp>
#include <godot_cpp/variant/vector3.hpp>

#include "FastNoiseLite.h"

namespace godot {

class PlanetCrustNative : public RefCounted {
	GDCLASS(PlanetCrustNative, RefCounted)

public:
	struct Noise {
		fastnoiselite::FastNoiseLite generator;
		real_t at(const Vector3 &p_point) const {
			return (real_t)generator.GetNoise(p_point.x, p_point.y, p_point.z);
		}
	};

private:
	// the plates
	PackedVector3Array seeds;
	PackedVector3Array spins;
	PackedByteArray continental;
	double continent_height = 0.1;
	double ocean_height = -0.42;
	double boundary_width = 0.08;
	double soft = 0.14;
	// the planet
	double radius = 20000.0;
	double relief = 300.0;
	double sea = 0.0;
	// the ground's shape
	double shore = 0.2, shore_flat = 0.16, land_curve = 1.6, deep = 1.6;
	double massif_scale = 0.3, chain_scale = 0.32, foothill_scale = 0.07, valley_width = 0.09;
	double valley_depth[3] = { 0.0, 0.0, 0.0 };
	// the rock
	double rock_boundary = 0.08;
	Color rock_colours[9];

	Noise warp, ridge, interior; // the plates'
	Noise rolling, ranges, range_mask, hills, gullies, detail; // the ground's
	Noise massif, chain, foothills, valleys[3]; // the rough ground and the valleys
	Noise craton, basin; // the rock's
	PackedVector3Array cube_faces; // the six cube faces: [normal, u, v] each

	static void configure(Noise &r_noise, const Array &p_config);
	Vector3 plate_shift(const Vector3 &p_dir) const;
	double tectonic_height(const Vector3 &p_dir) const;
	double boundary_effect(int p_a, int p_b, const Vector3 &p_q, double p_edge) const;
	void plate_at(const Vector3 &p_dir, int &r_plate, real_t &r_edge, bool &r_continental) const;
	double shore_curve(double p_units) const;
	double valley_cut(const Vector3 &p_point, double p_units) const;
	double macro_ground(double p_units, const Vector3 &p_point) const;
	double ground_height(const Vector3 &p_dir) const;
	Color rock_colour(const Vector3 &p_dir, double p_ground, double p_steep, double p_speckle) const;

protected:
	static void _bind_methods();

public:
	void setup(const Dictionary &p_config);
	PackedFloat32Array heights(const PackedVector3Array &p_dirs) const;
	PackedColorArray colours(const PackedVector3Array &p_dirs, const PackedFloat32Array &p_heights,
			const PackedFloat32Array &p_steeps) const;
	PackedFloat32Array tectonic_heights(const PackedVector3Array &p_dirs) const;
	// the ground of one tile (a grid of `cells + 3` points a side, one ring round the tile):
	PackedVector3Array tile_dirs(int p_face, double p_s0, double p_s1, double p_t0, double p_t1, int p_cells) const;
	PackedVector3Array local_positions(const PackedVector3Array &p_dirs, const PackedFloat32Array &p_heights,
			const PackedFloat64Array &p_origin, const Vector3 &p_e1, const Vector3 &p_up, const Vector3 &p_e3) const;
	PackedVector3Array grid_normals(const PackedVector3Array &p_positions, int p_cells) const;
	PackedColorArray ground_colours(const PackedVector3Array &p_dirs, const PackedFloat32Array &p_heights,
			const PackedVector3Array &p_normals, int p_cells) const;
	Dictionary triangles(const PackedVector3Array &p_positions, const PackedVector3Array &p_normals,
			const PackedColorArray &p_colours, int p_cells) const;
};

} // namespace godot
