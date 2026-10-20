#pragma once

// Pure tile-water geometry. Godot's scene nodes and materials stay in PlanetTile.

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/packed_float32_array.hpp>
#include <godot_cpp/variant/packed_float64_array.hpp>
#include <godot_cpp/variant/packed_vector3_array.hpp>

namespace godot {

class PlanetWaterNative : public RefCounted {
	GDCLASS(PlanetWaterNative, RefCounted)

protected:
	static void _bind_methods();

public:
	// The results are packed vertex/normal/colour arrays (and UVs for rivers), ready for ArrayMesh.
	// All geometry settings are supplied by PlanetTile; this object retains no state and is safe on workers.
	Dictionary sea_mesh(const PackedVector3Array &p_dirs, int p_cells, double p_size,
			double p_radius, double p_sea_level, const PackedFloat64Array &p_origin,
			const Vector3 &p_e1, const Vector3 &p_up, const Vector3 &p_e3) const;
	Dictionary river_mesh(const PackedVector3Array &p_dirs, const PackedFloat32Array &p_heights,
			const PackedVector3Array &p_samples, int p_cells, double p_radius, double p_sea_level,
			const PackedFloat64Array &p_origin, const Vector3 &p_e1, const Vector3 &p_up,
			const Vector3 &p_e3) const;
};

} // namespace godot
