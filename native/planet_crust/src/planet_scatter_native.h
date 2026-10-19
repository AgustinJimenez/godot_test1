#pragma once

// Where the plants of a planet tile stand (PlanetScatter's placement loops in native code): every layer of plants on
// its jittered grid, the species whose niche fits the spot best the likeliest, the rocks, stones, fallen leaves and
// logs, and the horizon trees. It answers as packed MultiMesh buffers (16 floats an instance: the transform's 12 and
// a colour) and the colliders, ready for the script to hang on the tile. Pure computation: any thread may call it.

#include <godot_cpp/classes/ref.hpp>
#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/packed_float32_array.hpp>
#include <godot_cpp/variant/packed_vector3_array.hpp>

#include <vector>

#include "planet_crust_native.h"

namespace godot {

class PlanetScatterNative : public RefCounted {
	GDCLASS(PlanetScatterNative, RefCounted)

public:
	struct Species {
		int id = 0, layer = 0, variants = 1;
		bool tree = false, has_far = false;
		double moisture = 0.5, moisture_tol = 0.3, heat = 0.5, heat_tol = 0.3, above_min = 1.5, above_max = 60.0;
		double slope_max = 0.5, density = 0.5, patch_freq = 0.05, patch_strength = 0.0, size_spread = 0.25;
		double patch_x = 0.0, patch_y = 0.0, foot_x = 0.0, foot_y = 0.0;
		double crown = 2.0; // radius of the crown (m): trees keep their crowns apart and shade what is under them
		double shade_tolerance = 1.0; // 0 a plant of the open, 1 grows as well under a canopy
		double fitness(double p_wet, double p_warm, double p_above, double p_steep) const;
	};

private:
	Ref<PlanetCrustNative> crust;
	std::vector<Species> species;
	std::vector<int> by_layer[5];
	PackedFloat32Array temperature, rain;
	int grid_width = 0, grid_height = 0;
	double relief = 300.0, radius = 20000.0, plant_density = 1.0, rock_density = 1.0;
	int world_seed = 1337;
	Vector3 clearing;
	int kind_variants[32] = {};

protected:
	static void _bind_methods();

public:
	// config: crust (the PlanetCrustNative), species (Array of Dictionary, see PlanetScatter.species_table), climate
	// (temperature grid, rain grid, width, height), relief, radius, plant_density, rock_density, world_seed, clearing,
	// kind_variants (Dictionary kind -> variants)
	void setup(const Dictionary &p_config);
	// One tile. tile: key, positions (PackedVector3Array), dirs, heights, cells, size, detail (0 none, 1 far, 2 trees,
	// 3 all), collide, fine (the Fine ground detail: pebbles and debris), grass_fine (the realistic look's denser grass).
	// Returns {"keys": PackedInt32Array, "buffers": Array of PackedFloat32Array (the same order), "cylinders":
	// PackedFloat32Array (x, y, z, radius, height), "boxes": PackedFloat32Array (x, y, z, yaw, sx, sy, sz)}.
	Dictionary scatter(const Dictionary &p_tile) const;
	// The far trees of a tile as one mesh: parts are {vertices, normals, colors, buffer} (a mesh and the instances of it).
	Dictionary merge_far(const Array &p_parts) const;
};

} // namespace godot
