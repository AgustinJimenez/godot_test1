#pragma once

// The plants' meshes grown natively: the tree grower, the leaf shapes and the tube builder of
// TreeGrower / PlantLeafShapes / PlantTreeBuilders / MeshBuilder (scripts in systems/world_gen), the same
// steps in C++. A first planted tile used to wait 1-4 s while the script grew the meshes of its species.
// Pure computation on its own data, so any thread may call it.

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/dictionary.hpp>

namespace godot {

class PlantMeshNative : public RefCounted {
	GDCLASS(PlantMeshNative, RefCounted)

protected:
	static void _bind_methods();

public:
	// Grows one tree (or any plant TreeGrower grows) from `genome` (TreeGenome.to_dictionary()) with the dice
	// `seed`. Returns {"vertices", "normals", "colors", "uvs", "uv2s" (empty without leaves), "capped": the
	// triangle budget ran out even at the thinnest, "triangles"}: three vertices a triangle, like MeshBuilder.
	Dictionary grow(const Dictionary &p_genome, int64_t p_seed, bool p_detailed, bool p_leafless, int p_lod,
			bool p_leaf_cards) const;
};

} // namespace godot
