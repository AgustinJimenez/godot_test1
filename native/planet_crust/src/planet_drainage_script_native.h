#pragma once

// PlanetDrainage and PlanetDrainageCache (were systems/planet/planet_drainage.gd and planet_drainage_cache.gd): where the water of the planet
// runs on a coarse grid of the cube sphere (the heavy part is PlanetDrainageNative; this keeps the arrays and answers questions about them),
// and the river network kept on disk between runs.

#include "native_props.h"
#include "planet_drainage_native.h"
#include "planet_settings_native.h"

#include <godot_cpp/classes/image.hpp>
#include <godot_cpp/classes/object.hpp>
#include <godot_cpp/classes/ref.hpp>
#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/packed_byte_array.hpp>
#include <godot_cpp/variant/packed_float32_array.hpp>
#include <godot_cpp/variant/packed_float64_array.hpp>
#include <godot_cpp/variant/packed_int32_array.hpp>
#include <godot_cpp/variant/packed_vector3_array.hpp>

namespace godot {

class PlanetDrainage : public RefCounted {
	GDCLASS(PlanetDrainage, RefCounted)

	Ref<PlanetDrainageNative> native_;

protected:
	static void _bind_methods();

public:
	NP_FIELD(int64_t, cells, 0) // cells along an edge of a cube face
	NP_FIELD(PackedVector3Array, dirs, PackedVector3Array()) // the middle of every cell
	NP_FIELD(PackedFloat32Array, heights, PackedFloat32Array()) // the crust there without the smallest hills (m above the sea)
	NP_FIELD(PackedFloat32Array, rain, PackedFloat32Array()) // the climate's rain there
	NP_FIELD(PackedFloat32Array, filled, PackedFloat32Array()) // the ground with its hollows filled up to where they spill (m)
	NP_FIELD(PackedFloat32Array, flow, PackedFloat32Array()) // the water that passes through the cell (rain x area)
	NP_FIELD(PackedInt32Array, receiver, PackedInt32Array()) // the main cell it runs on to (-1: the sea)
	NP_FIELD(PackedByteArray, lake, PackedByteArray()) // 1 where the hollow is a lake
	NP_FIELD(PackedFloat32Array, uplift, PackedFloat32Array()) // 0..1 how far the plates have raised the ground there
	NP_FIELD(int64_t, land_cells, 0)

	// `noise`: a PlanetNoise (settings, native crust, climate, _cube_faces()). Solves on `cells_per_edge` cells an edge.
	bool build(Object *p_noise, int64_t p_cells_per_edge, double p_exponent = 4.0);
	double river_threshold(double p_share) const;
	Dictionary network() const;
	int64_t cell_of(const Vector3 &p_dir) const;
	PackedInt32Array cells_of(const PackedVector3Array &p_many) const;
	PackedFloat32Array areas() const;
	Ref<Image> picture(const PackedFloat64Array &p_view, double p_threshold) const;
};

class PlanetDrainageCache : public RefCounted {
	GDCLASS(PlanetDrainageCache, RefCounted)

	static String path_for(const Ref<PlanetSettings> &p_settings);
	static void trim();

protected:
	static void _bind_methods();

public:
	static constexpr int VERSION = 1;
	static constexpr int MAX_FILES = 8; // worlds kept (the least recently written go)

	static Dictionary load_network(const Ref<PlanetSettings> &p_settings);
	static void save_network(const Ref<PlanetSettings> &p_settings, const Dictionary &p_network);
};

} // namespace godot
