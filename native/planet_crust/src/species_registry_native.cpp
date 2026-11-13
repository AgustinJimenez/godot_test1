#include "species_registry_native.h"

#include "plant_mesh_native.h"
#include "species_generator_native.h"
#include "tree_archetypes_native.h"
#include "tree_genome_native.h"

#include <godot_cpp/classes/mesh.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/packed_vector2_array.hpp>

using namespace godot;

bool SpeciesRegistry::fine_trees = false;

// ---- PlantMeshes ----

void PlantMeshes::_bind_methods() {
	ClassDB::bind_static_method("PlantMeshes", D_METHOD("build", "species", "variant", "detailed", "leafless", "lod"), &PlantMeshes::build, DEFVAL(false), DEFVAL(0));
	ClassDB::bind_static_method("PlantMeshes", D_METHOD("build_far", "species", "variant"), &PlantMeshes::build_far);
	ClassDB::bind_static_method("PlantMeshes", D_METHOD("has_far", "species"), &PlantMeshes::has_far);
	ClassDB::bind_static_method("PlantMeshes", D_METHOD("mesh_from", "grown"), &PlantMeshes::mesh_from);
}

static int64_t dice_of(const Ref<PlantSpecies> &p_species, int p_variant) {
	return p_species->seed * 31 + (int64_t)p_variant * 104729 + 17;
}

Ref<ArrayMesh> PlantMeshes::build(const Ref<PlantSpecies> &p_species, int p_variant, bool p_detailed, bool p_leafless, int p_lod) {
	Ref<PlantMeshNative> maker;
	maker.instantiate();
	const int64_t dice = dice_of(p_species, p_variant);
	if (p_species->form == PlantSpecies::MUSHROOM) {
		Dictionary one;
		one["height"] = p_species->height;
		one["crown"] = p_species->crown;
		one["droop"] = p_species->droop;
		one["count"] = p_species->count;
		one["accent"] = p_species->accent;
		return mesh_from(maker->mushroom(one, dice, p_detailed));
	}
	// every other plant is grown by the tree grower; the small ones always in the light version
	const int level = p_species->is_tree() ? p_lod : Math::max(p_lod, p_detailed ? 0 : 1);
	Ref<TreeGenome> genome = TreeArchetypes::for_species(p_species);
	return mesh_from(maker->grow(genome->to_dictionary(), dice, p_detailed, p_leafless, level, true));
}

Ref<ArrayMesh> PlantMeshes::build_far(const Ref<PlantSpecies> &p_species, int p_variant) {
	Ref<PlantMeshNative> maker;
	maker.instantiate();
	Dictionary one;
	one["conifer"] = p_species->form == PlantSpecies::CONIFER;
	one["leaf"] = p_species->leaf;
	one["leaf_tip"] = p_species->leaf_tip;
	one["bark"] = p_species->bark;
	one["height"] = p_species->height;
	one["crown"] = p_species->crown;
	one["aspect"] = p_species->aspect;
	one["bare"] = p_species->bare;
	one["girth"] = p_species->girth;
	return mesh_from(maker->far_tree(one, dice_of(p_species, p_variant + 50)));
}

bool PlantMeshes::has_far(const Ref<PlantSpecies> &p_species) {
	return p_species->form == PlantSpecies::CONIFER || p_species->form == PlantSpecies::BROADLEAF;
}

Ref<ArrayMesh> PlantMeshes::mesh_from(const Dictionary &p_grown) {
	Ref<ArrayMesh> mesh;
	mesh.instantiate();
	if ((int64_t)p_grown["triangles"] == 0) {
		return mesh;
	}
	Array arrays;
	arrays.resize(Mesh::ARRAY_MAX);
	arrays[Mesh::ARRAY_VERTEX] = p_grown["vertices"];
	arrays[Mesh::ARRAY_NORMAL] = p_grown["normals"];
	arrays[Mesh::ARRAY_COLOR] = p_grown["colors"];
	PackedVector2Array uvs = p_grown["uvs"];
	if (!uvs.is_empty()) {
		arrays[Mesh::ARRAY_TEX_UV] = uvs;
		arrays[Mesh::ARRAY_TEX_UV2] = p_grown["uv2s"];
	}
	int64_t flags = 0;
	PackedFloat32Array branches = p_grown.get("branches", PackedFloat32Array());
	const bool bends = branches.size() > 10; // one row of ten per branch, the first is the trunk: a plant that can bend
	if (bends) {
		arrays[Mesh::ARRAY_CUSTOM0] = p_grown["branch_ids"]; // CUSTOM0.x: which branch the vertex is on (0: the trunk)
		flags |= Mesh::ARRAY_CUSTOM_R_FLOAT << Mesh::ARRAY_FORMAT_CUSTOM0_SHIFT;
	}
	mesh->add_surface_from_arrays(Mesh::PRIMITIVE_TRIANGLES, arrays, Array(), Dictionary(), flags);
	if (bends) {
		mesh->set_meta("branches", branches); // parent, level, foot, tip, radius, length of every branch (see PlantMeshNative)
	}
	if (p_grown.has("capsules")) {
		mesh->set_meta("capsules", p_grown["capsules"]); // the thick low limbs a person can walk into
	}
	return mesh;
}

// ---- SpeciesRegistry ----

void SpeciesRegistry::_bind_methods() {
	ClassDB::bind_static_method("SpeciesRegistry", D_METHOD("for_settings", "settings"), &SpeciesRegistry::for_settings);
	ClassDB::bind_static_method("SpeciesRegistry", D_METHOD("create", "seed", "count"), &SpeciesRegistry::create);
	ClassDB::bind_static_method("SpeciesRegistry", D_METHOD("set_fine_trees", "on"), &SpeciesRegistry::set_fine_trees);
	ClassDB::bind_static_method("SpeciesRegistry", D_METHOD("get_fine_trees"), &SpeciesRegistry::get_fine_trees);
	ClassDB::bind_method(D_METHOD("get_world_seed"), &SpeciesRegistry::get_world_seed);
	ClassDB::bind_method(D_METHOD("get_species"), &SpeciesRegistry::get_species);
	ClassDB::bind_method(D_METHOD("set_species", "value"), &SpeciesRegistry::set_species);
	ClassDB::bind_method(D_METHOD("get_impostors_expected"), &SpeciesRegistry::get_impostors_expected);
	ClassDB::bind_method(D_METHOD("set_impostors_expected", "on"), &SpeciesRegistry::set_impostors_expected);
	ADD_PROPERTY(PropertyInfo(Variant::INT, "world_seed"), "", "get_world_seed");
	ADD_PROPERTY(PropertyInfo(Variant::ARRAY, "species"), "set_species", "get_species");
	ADD_PROPERTY(PropertyInfo(Variant::BOOL, "impostors_expected"), "set_impostors_expected", "get_impostors_expected");
	ClassDB::bind_method(D_METHOD("in_layer", "layer"), &SpeciesRegistry::in_layer);
	ClassDB::bind_method(D_METHOD("by_id", "id"), &SpeciesRegistry::by_id);
	ClassDB::bind_method(D_METHOD("mesh", "id", "variant", "detailed_wanted", "lod"), &SpeciesRegistry::mesh, DEFVAL(0));
	ClassDB::bind_method(D_METHOD("far_mesh", "id", "variant"), &SpeciesRegistry::far_mesh);
	ClassDB::bind_method(D_METHOD("impostor", "id", "variant"), &SpeciesRegistry::impostor);
	ClassDB::bind_method(D_METHOD("set_impostor", "id", "variant", "baked"), &SpeciesRegistry::set_impostor);
	ClassDB::bind_method(D_METHOD("wait_for_impostor", "id", "variant", "instance_id", "buffer"), &SpeciesRegistry::wait_for_impostor);
	ClassDB::bind_method(D_METHOD("take_waiting", "id", "variant"), &SpeciesRegistry::take_waiting);
}

std::map<int64_t, Ref<SpeciesRegistry>> &SpeciesRegistry::registries() {
	static std::map<int64_t, Ref<SpeciesRegistry>> all;
	return all;
}

std::mutex &SpeciesRegistry::registries_lock() {
	static std::mutex lock;
	return lock;
}

void SpeciesRegistry::set_fine_trees(bool p_on) {
	fine_trees = p_on;
}

bool SpeciesRegistry::get_fine_trees() {
	return fine_trees;
}

Ref<SpeciesRegistry> SpeciesRegistry::create(int64_t p_seed, int64_t p_count) {
	Ref<SpeciesRegistry> registry;
	registry.instantiate();
	registry->world_seed = p_seed;
	registry->species = SpeciesGenerator::generate(p_seed, p_count);
	for (int i = 0; i < 5; i++) {
		registry->by_layer[i] = Array();
	}
	for (int i = 0; i < registry->species.size(); i++) {
		Ref<PlantSpecies> one = registry->species[i];
		registry->by_layer[one->layer()].append(one);
	}
	return registry;
}

Ref<SpeciesRegistry> SpeciesRegistry::for_settings(Object *p_settings) {
	const int64_t seed = p_settings->get("world_seed");
	const int64_t count = p_settings->get("species_count");
	const int64_t key = (seed << 20) ^ count;
	std::lock_guard<std::mutex> guard(registries_lock());
	auto found = registries().find(key);
	if (found != registries().end()) {
		return found->second;
	}
	Ref<SpeciesRegistry> made = create(seed, count);
	registries()[key] = made;
	while (registries().size() > 2) { // keep this world and the one before it (a seed roll rebuilds)
		registries().erase(registries().begin());
	}
	return made;
}

Array SpeciesRegistry::in_layer(int p_layer) const {
	return p_layer >= 0 && p_layer < 5 ? by_layer[p_layer] : Array();
}

Ref<PlantSpecies> SpeciesRegistry::by_id(int64_t p_id) const {
	return species[p_id - 1];
}

Ref<ArrayMesh> SpeciesRegistry::mesh(int64_t p_id, int p_variant, bool p_detailed_wanted, int p_lod) {
	// trees and shrubs are few and near, and the finer mesh (leaf cards, strips of leaflets, smoother branches) costs
	// little more than the light one: they use it from the middle ground detail up; the many small plants wait for the
	// Fine ground detail
	Ref<PlantSpecies> one = by_id(p_id);
	const bool detailed = p_detailed_wanted || (fine_trees && (one->is_tree() || one->form == PlantSpecies::SHRUB));
	const int64_t key = p_id * 100 + p_variant + (detailed ? 100000 : 0) + (int64_t)p_lod * 1000000;
	Ref<ArrayMesh> found = cached(key);
	if (found.is_valid()) {
		return found;
	}
	return keep(key, PlantMeshes::build(one, p_variant, detailed, false, p_lod));
}

Ref<ArrayMesh> SpeciesRegistry::far_mesh(int64_t p_id, int p_variant) {
	const int64_t key = -(p_id * 100 + p_variant);
	Ref<ArrayMesh> found = cached(key);
	if (found.is_valid()) {
		return found;
	}
	return keep(key, PlantMeshes::build_far(by_id(p_id), p_variant));
}

Ref<ArrayMesh> SpeciesRegistry::cached(int64_t p_key) {
	std::lock_guard<std::mutex> guard(lock);
	auto found = meshes.find(p_key);
	return found == meshes.end() ? Ref<ArrayMesh>() : found->second;
}

Ref<ArrayMesh> SpeciesRegistry::keep(int64_t p_key, Ref<ArrayMesh> p_built) {
	std::lock_guard<std::mutex> guard(lock);
	auto found = meshes.find(p_key);
	if (found != meshes.end()) {
		return found->second;
	}
	meshes[p_key] = p_built;
	return p_built;
}

Dictionary SpeciesRegistry::impostor(int64_t p_id, int p_variant) {
	std::lock_guard<std::mutex> guard(lock);
	auto found = impostor_table.find(p_id * 100 + p_variant);
	return found == impostor_table.end() ? Dictionary() : found->second;
}

void SpeciesRegistry::set_impostor(int64_t p_id, int p_variant, const Dictionary &p_baked) {
	std::lock_guard<std::mutex> guard(lock);
	impostor_table[p_id * 100 + p_variant] = p_baked;
}

void SpeciesRegistry::wait_for_impostor(int64_t p_id, int p_variant, int64_t p_instance_id, const PackedFloat32Array &p_buffer) {
	if (!impostors_expected) {
		return;
	}
	std::lock_guard<std::mutex> guard(lock);
	Dictionary entry;
	entry["instance"] = p_instance_id;
	entry["buffer"] = p_buffer;
	waiting[p_id * 100 + p_variant].append(entry);
}

Array SpeciesRegistry::take_waiting(int64_t p_id, int p_variant) {
	std::lock_guard<std::mutex> guard(lock);
	const int64_t key = p_id * 100 + p_variant;
	auto found = waiting.find(key);
	if (found == waiting.end()) {
		return Array();
	}
	Array out = found->second;
	waiting.erase(found);
	return out;
}
