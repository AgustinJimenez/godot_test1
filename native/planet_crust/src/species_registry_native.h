#pragma once

// The species of one world and the meshes they have made so far (was systems/world_gen/flora/species_registry.gd and
// plant_meshes.gd). One registry per seed (found with for_settings); it is read from the tile worker threads and the
// main thread, so the mesh cache and the impostor tables sit behind a lock and the species list is never changed.

#include "plant_species_native.h"

#include <godot_cpp/classes/array_mesh.hpp>
#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/packed_float32_array.hpp>

#include <map>
#include <mutex>

namespace godot {

// Turns a PlantSpecies into a mesh: picks the builder of its growth form and runs it with the dice of that species
// and variant (so a variant is always the same mesh, and no two variants match).
class PlantMeshes : public RefCounted {
	GDCLASS(PlantMeshes, RefCounted)

protected:
	static void _bind_methods();

public:
	// `lod` 1: the lighter version of a tree for trees at a distance.
	static Ref<ArrayMesh> build(const Ref<PlantSpecies> &p_species, int p_variant, bool p_detailed, bool p_leafless = false, int p_lod = 0);
	// The cheap horizon version; only trees have one (the others are never drawn that far).
	static Ref<ArrayMesh> build_far(const Ref<PlantSpecies> &p_species, int p_variant);
	static bool has_far(const Ref<PlantSpecies> &p_species);
	// The mesh of the arrays a PlantMeshNative call answers with.
	static Ref<ArrayMesh> mesh_from(const Dictionary &p_grown);
};

class SpeciesRegistry : public RefCounted {
	GDCLASS(SpeciesRegistry, RefCounted)

	static std::map<int64_t, Ref<SpeciesRegistry>> &registries();
	static std::mutex &registries_lock();

	int64_t world_seed = 0;
	Array species; // PlantSpecies, in generation order
	Array by_layer[5]; // PlantSpecies.Layer -> PlantSpecies
	bool impostors_expected = false; // true once PlanetImpostors is baking
	std::map<int64_t, Ref<ArrayMesh>> meshes;
	std::map<int64_t, Dictionary> impostor_table;
	std::map<int64_t, Array> waiting;
	std::mutex lock;
	static bool fine_trees; // the finer tree mesh from the middle ground detail up (was FloraMeshes.fine_trees)

protected:
	static void _bind_methods();

public:
	// The registry of a world (WorldSettings: world_seed, species_count): one per seed, the last two kept.
	static Ref<SpeciesRegistry> for_settings(Object *p_settings);
	static Ref<SpeciesRegistry> create(int64_t p_seed, int64_t p_count);
	static void set_fine_trees(bool p_on);
	static bool get_fine_trees();

	int64_t get_world_seed() const { return world_seed; }
	Array get_species() const { return species; }
	void set_species(const Array &) {}
	bool get_impostors_expected() const { return impostors_expected; }
	void set_impostors_expected(bool p_on) { impostors_expected = p_on; }

	Array in_layer(int p_layer) const;
	Ref<PlantSpecies> by_id(int64_t p_id) const;

	// `lod` 1 is the lighter version of a tree; other plants have only one. A mesh is built outside the lock (several
	// threads build different ones at once; two that want the same one both build it and the first to finish is kept).
	Ref<ArrayMesh> mesh(int64_t p_id, int p_variant, bool p_detailed_wanted, int p_lod = 0);
	Ref<ArrayMesh> far_mesh(int64_t p_id, int p_variant);

	// The impostor of a tree variant (PlanetImpostors bakes it): {"mesh", "material"}, or empty until it is baked.
	Dictionary impostor(int64_t p_id, int p_variant);
	void set_impostor(int64_t p_id, int p_variant, const Dictionary &p_baked);
	// Tile instances showing the lighter mesh of a tree variant until its impostor is baked: {"instance": id, "buffer"}.
	void wait_for_impostor(int64_t p_id, int p_variant, int64_t p_instance_id, const PackedFloat32Array &p_buffer);
	Array take_waiting(int64_t p_id, int p_variant);

private:
	Ref<ArrayMesh> cached(int64_t p_key);
	Ref<ArrayMesh> keep(int64_t p_key, Ref<ArrayMesh> p_built);
};

} // namespace godot
