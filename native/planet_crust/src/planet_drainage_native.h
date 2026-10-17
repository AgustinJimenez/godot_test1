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
	Dictionary solve(const PackedFloat32Array &p_heights, const PackedFloat32Array &p_rain,
			double p_sea_level, double p_exponent, double p_lake_depth, int p_lake_cells) const;
};

} // namespace godot
