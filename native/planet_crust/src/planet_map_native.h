#pragma once

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/packed_float32_array.hpp>

namespace godot {

class PlanetMapNative : public RefCounted {
	GDCLASS(PlanetMapNative, RefCounted)

protected:
	static void _bind_methods();

public:
	// The largest connected sea and land bodies, with the UV of each body's central cell.
	Array regions(const PackedFloat32Array &p_heights, int p_width, int p_height,
			double p_min_area, int p_max_per_kind) const;
};

} // namespace godot
