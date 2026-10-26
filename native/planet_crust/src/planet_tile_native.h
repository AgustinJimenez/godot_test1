#pragma once

// PlanetTile (was systems/planet/planet_tile.gd): one square patch of a planet's ground: a cell of one of the six cube faces, bent onto the sphere.
// The mesh is built around the patch's own centre (so its numbers stay small, however big the planet), and the node's transform places it in the
// world (see PlanetFrame). The finest tiles also get a collider. Built on worker threads from the native crust's grids; the script fallbacks that
// worked the same out without the library are gone with the port. MeshBuilder (GDScript) commits the meshes.

#include "native_props.h"
#include "planet_noise_native.h"

#include <godot_cpp/classes/mesh_instance3d.hpp>
#include <godot_cpp/classes/node3d.hpp>
#include <godot_cpp/classes/shader_material.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/basis.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/packed_float64_array.hpp>
#include <godot_cpp/variant/vector3.hpp>

namespace godot {

class PlanetTile : public Node3D {
	GDCLASS(PlanetTile, Node3D)

	Ref<PlanetNoise> noise_;
	Ref<PlanetSettings> settings_;
	Vector3 e1, e3; // the tile's axes as unit vectors

	double skirt_drop() const;
	void set_morph(MeshInstance3D *p_instance) const;
	void add_occluder(const PackedVector3Array &p_positions, int p_cells);
	void add_sea(const PackedVector3Array &p_dirs, int p_cells);
	void add_crust_rivers(const PackedVector3Array &p_dirs, const PackedFloat32Array &p_heights);
	void add_water_mesh(Object *p_builder, const Ref<ShaderMaterial> &p_material);

protected:
	static void _bind_methods();

public:
	NP_FIELD(int64_t, face, 0)
	NP_FIELD(int64_t, level, 0)
	NP_FIELD(int64_t, tile_x, 0)
	NP_FIELD(int64_t, tile_y, 0)
	NP_FIELD(Vector3, centre, Vector3()) // unit direction of the tile's middle (planet space)
	NP_FIELD(PackedFloat64Array, origin, PackedFloat64Array()) // planet space position of the tile's middle (m)
	NP_FIELD(Basis, local_basis, Basis()) // the tile's axes in planet space: y is up
	NP_FIELD(double, size, 0.0) // m, along one edge
	NP_FIELD(bool, has_collider, false)
	NP_FIELD(double, min_height, 0.0)
	NP_FIELD(int64_t, tile_key, 0) // see key_of
	NP_FIELD(Dictionary, plant_grid, Dictionary()) // the grid the plants are placed on (empty: this tile has none)
	NP_FIELD(int64_t, plant_detail, 0) // what grows on it now (PlanetScatter.Detail)
	NP_OBJECT(plant_holder)
	NP_OBJECT(ground_instance) // the ground mesh of the tile (the shell layers of the near ground copy it)

	PlanetTile();
	static Array faces(); // [normal, u, v] of the six cube faces (u x v = normal)
	static Ref<ShaderMaterial> ground_material();
	static Ref<ShaderMaterial> water_material();
	static Ref<ShaderMaterial> river_material();
	static int64_t key_of(int64_t p_f, int64_t p_lvl, int64_t p_x, int64_t p_y);
	static Vector3 direction(int64_t p_f, double p_s, double p_t);
	PlanetTile *build(int64_t p_f, int64_t p_lvl, int64_t p_x, int64_t p_y, const Ref<PlanetNoise> &p_noise, bool p_collide);
	Node3D *grow_plants(int64_t p_detail);
	void make_occluder(const PackedVector3Array &p_vertices, const PackedInt32Array &p_indices);
};

} // namespace godot
