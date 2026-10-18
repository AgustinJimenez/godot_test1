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
	// the rivers (from the drainage): pieces of curve with their bed and flow, listed by coarse cell
	int river_cells = 0; // cells along a cube face of the grid they are listed on (0: no rivers)
	double river_flow = 1.0;
	double river_cell_metres = 1.0;
	PackedVector3Array river_a, river_b;
	PackedFloat32Array river_bed_a, river_bed_b, river_flow_a, river_flow_b;
	PackedInt32Array river_start, river_items;
	struct Valley {
		double envelope = 0.0; // the highest the ground may stand here: the bed and the valley's sides
		double distance = 0.0; // metres to the nearest river
		double floor_half = 0.0; // half the width of that river's valley floor
		double bed = 0.0; // that river's bed height there (m)
		double flow = 0.0; // its flow there
		double side = 1.0; // +1 or -1: which bank of the river the point is on
	};
	bool valley_at(const Vector3 &p_dir, Valley &r_valley) const;
	double valley_floor(const Vector3 &p_dir) const; // 1 away from the rivers, less on a valley floor

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
	// The river water at each direction: x the water level (m; -1e9 where there is no river), y the
	// river's flow as a share of a big river's, z 0..1 across the river (0.5 in the middle).
	PackedVector3Array river_waters(const PackedVector3Array &p_dirs) const;
	void set_rivers(int p_cells, const Dictionary &p_network, double p_cell_metres);
	PackedFloat32Array heights(const PackedVector3Array &p_dirs) const;
	PackedColorArray colours(const PackedVector3Array &p_dirs, const PackedFloat32Array &p_heights,
			const PackedFloat32Array &p_steeps) const;
	PackedFloat32Array tectonic_heights(const PackedVector3Array &p_dirs) const;
	PackedFloat32Array macro_heights(const PackedVector3Array &p_dirs) const;
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
