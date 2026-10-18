#pragma once

// Where the water of a planet runs, on a coarse grid of the cube sphere (the same cells as the
// tiles' cube faces): every hollow is filled up to the level it would spill over, and the rain of
// every cell runs down the filled ground to the sea, split between the lower neighbours by the
// steepness (a multiple flow direction: rivers wind and branch instead of following the eight
// directions of a grid). The result is, per cell, the water that passes through it and where it
// goes next. GDScript decides what a river is and what to cut; this is only the heavy part.

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/packed_byte_array.hpp>
#include <godot_cpp/variant/packed_float32_array.hpp>
#include <godot_cpp/variant/packed_int32_array.hpp>
#include <godot_cpp/variant/packed_vector3_array.hpp>
#include <godot_cpp/variant/vector3.hpp>

namespace godot {

class PlanetDrainageNative : public RefCounted {
	GDCLASS(PlanetDrainageNative, RefCounted)

	int cells = 0; // along a cube face's edge
	double radius = 1.0;
	PackedVector3Array cube_faces; // [normal, u, v] for each of the six faces
	PackedVector3Array dirs;
	PackedFloat32Array areas; // each cell's share of the sphere, 1 on average
	PackedInt32Array neighbours; // 8 a cell, -1 where there is none

	int cell_at(const Vector3 &p_dir) const;

protected:
	static void _bind_methods();

public:
	void setup(int p_cells, double p_radius, const PackedVector3Array &p_faces);
	PackedVector3Array cell_dirs() const { return dirs; }
	PackedFloat32Array cell_areas() const { return areas; }
	PackedInt32Array cell_neighbours() const { return neighbours; }
	int cell_of(const Vector3 &p_dir) const { return cell_at(p_dir); }
	PackedInt32Array cells_of(const PackedVector3Array &p_dirs) const;
	// How deep the river valleys are cut (m, per cell): from the sea inland, a cell's river bed is
	// no higher than the bed below it plus the slope the water allows (steep for a trickle,
	// gentle for a big river), so the ground above that is cut away; the valley is then widened a
	// cell round.
	PackedFloat32Array carve(const PackedFloat32Array &p_heights, const PackedFloat32Array &p_filled,
			const PackedFloat32Array &p_flow, const PackedInt32Array &p_receiver, double p_river_flow,
			double p_base_slope, double p_max_cut) const;
	// The rivers as curves: every river cell sends a smooth, winding curve (a Hermite curve through
	// the cells' directions, with a meander) to the cell its water runs on to, cut into `samples`
	// pieces; each piece has its bed height and its flow, and is listed under the cells near it.
	Dictionary river_network(const PackedFloat32Array &p_heights, const PackedFloat32Array &p_filled,
			const PackedFloat32Array &p_flow, const PackedInt32Array &p_receiver, double p_river_flow,
			double p_base_slope, int p_samples, double p_meander, const PackedFloat32Array &p_uplift) const;
	Dictionary solve(const PackedFloat32Array &p_heights, const PackedFloat32Array &p_rain,
			double p_sea_level, double p_exponent, double p_lake_depth, int p_lake_cells) const;
};

} // namespace godot
