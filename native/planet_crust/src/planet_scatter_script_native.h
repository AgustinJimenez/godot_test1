#pragma once

// PlanetScatter (was systems/planet/planet_scatter.gd): the plants of one planet tile. The placement is PlanetScatterNative (this class sends it
// the tile's grid, gets the buffers back and hangs them on the tile: MultiMeshes, the far trees merged into one mesh, impostor cards, colliders).
// The script's own placement loops (the fallback without the library) are gone with the port. The species, their meshes and FloraMeshes are
// still GDScript and are reached through their scripts.

#include "native_props.h"
#include "planet_noise_native.h"

#include <godot_cpp/classes/material.hpp>
#include <godot_cpp/classes/mesh.hpp>
#include <godot_cpp/classes/multi_mesh_instance3d.hpp>
#include <godot_cpp/classes/node3d.hpp>
#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/classes/static_body3d.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/packed_float32_array.hpp>
#include <godot_cpp/variant/packed_int32_array.hpp>
#include <godot_cpp/variant/packed_vector3_array.hpp>
#include <godot_cpp/variant/vector2.hpp>

namespace godot {

class PlanetScatter : public RefCounted {
	GDCLASS(PlanetScatter, RefCounted)

	Node3D *tile = nullptr;
	Ref<PlanetNoise> noise;
	Object *species = nullptr;
	StaticBody3D *body = nullptr;
	PackedVector3Array packed_positions, packed_dirs;
	PackedFloat32Array heights;
	int cells = 0;
	int side = 0;
	double size = 0.0;

	void populate_native(int64_t p_key, int p_detail, bool p_collide);
	static Basis basis_of(const PackedFloat32Array &p_values, int p_at);
	void add_limb_colliders(const PackedInt32Array &p_keys, const Array &p_buffers);
	Vector2 grid_axis(int p_step) const;
	void hang(PackedInt32Array p_keys, Array p_buffers, bool p_near);
	Array tree_cells(const PackedFloat32Array &p_buffer) const;
	MultiMeshInstance3D *light_trees(const PackedFloat32Array &p_buffer, int p_id, int p_variant);
	void commit_far(const Array &p_parts, double p_begin);
	MultiMeshInstance3D *add_trees(const PackedFloat32Array &p_buffer, const Ref<Mesh> &p_mesh, bool p_shadows);
	Object *by_id(int p_id) const;

protected:
	static void _bind_methods();

public:
	static constexpr double BANK = 4.0; // m from a river edge inside which nothing grows
	static constexpr double GRASS_VISIBLE = 260.0; // m: the tall grass and the meadow flowers are gone beyond this (PLANET_GRASS_VISIBLE: another)
	static constexpr double PEBBLE_VISIBLE = 45.0; // m: small stones are gone beyond this
	static constexpr double SMALL_PLANT = 1.4; // m: plants lower than this bend only a little way from the walker
	static constexpr double TREE_FULL = 80.0; // m: beyond this a tree is drawn as its lighter version
	static constexpr double SMALL_VISIBLE = 220.0; // m: shrubs and ground cover are gone beyond this
	static constexpr double TREE_LIGHT = 500.0; // m: beyond this, as the cheap far tree; before it the impostor cards (PLANET_TREE_LIGHT: another)
	static constexpr double TREE_FADE = 6.0; // m: overlap where a tree dithers from one version to the next
	static constexpr double TREE_CELL = 64.0; // m: near trees are drawn in cells of this size, each with its own range
	static constexpr bool CELL_PLANTS = false; // shrubs and ground cover in cells too: off
	static constexpr int PLANT_KEY = 100000;
	static constexpr int FAR_KEY = 200000;

	enum Detail { NONE, FAR, TREES, ALL }; // FAR: only the cheap horizon trees, sparse

	static double tree_light();
	static double get_tree_full() { return TREE_FULL; }
	// false: no trees and no shrubs are placed, only the grass, rocks and the rest (the planet lab's `--no-trees`)
	static bool get_trees_on();
	static void set_trees_on(bool p_on);
	static Array species_table(Object *p_registry);

	void populate(Node3D *p_holder, int64_t p_key, const Ref<PlanetNoise> &p_noise, const Dictionary &p_grid, int64_t p_cells, double p_size,
			int64_t p_detail, bool p_collide);
};

} // namespace godot

VARIANT_ENUM_CAST(PlanetScatter::Detail);
