#pragma once

// Which tiles of a planet's quadtree the player needs (PlanetSurface's selection in native code): every cube face
// split while the player is close compared to a tile's size, and for each wanted tile its distance, whether it needs a
// collider and what plants it gets. Also a plain ascending order of numbers, for sorting the tiles to build.

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/packed_float64_array.hpp>
#include <godot_cpp/variant/packed_int32_array.hpp>

namespace godot {

class PlanetSurfaceNative : public RefCounted {
	GDCLASS(PlanetSurfaceNative, RefCounted)

protected:
	static void _bind_methods();

public:
	// params: near (planet space), height (m over the ground), radius, max_level, split_factor, tile_max,
	// collide_tiles, plants_on, coarse_level, faces (the six cube faces: [normal, u, v] each).
	// Returns {"entries": PackedInt32Array (face, level, x, y a tile), "distance": PackedFloat64Array,
	// "collides": PackedByteArray, "plants": PackedByteArray (0 none, 1 far, 2 trees, 3 all), "sort": PackedFloat64Array
	// (the build order: the ground to stand on first, then the coarse shape coarsest first, then nearest first)}.
	Dictionary select(const Dictionary &p_params) const;
	// The indices that put `p_values` in ascending order (a stable sort).
	PackedInt32Array order(const PackedFloat64Array &p_values) const;
};

} // namespace godot
