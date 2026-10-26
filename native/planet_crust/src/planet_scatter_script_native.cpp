#include "planet_scatter_script_native.h"

#include <godot_cpp/classes/array_mesh.hpp>
#include <godot_cpp/classes/box_shape3d.hpp>
#include <godot_cpp/classes/capsule_shape3d.hpp>
#include <godot_cpp/classes/collision_shape3d.hpp>
#include <godot_cpp/classes/cylinder_shape3d.hpp>
#include <godot_cpp/classes/engine.hpp>
#include <godot_cpp/classes/mesh.hpp>
#include <godot_cpp/classes/multi_mesh.hpp>
#include <godot_cpp/classes/mesh_instance3d.hpp>
#include <godot_cpp/classes/os.hpp>
#include <godot_cpp/classes/resource_loader.hpp>
#include <godot_cpp/classes/scene_tree.hpp>
#include <godot_cpp/classes/script.hpp>
#include <godot_cpp/classes/window.hpp>

#include <algorithm>
#include <atomic>
#include <cmath>
#include <map>

using namespace godot;

static std::atomic<bool> trees_on_flag(true);

static Ref<Script> script_of(const char *p_path) {
	return ResourceLoader::get_singleton()->load(p_path);
}
static Ref<Script> flora_script() {
	static Ref<Script> s;
	if (s.is_null()) {
		s = script_of("res://systems/world_gen/flora_meshes.gd");
	}
	return s;
}
static Ref<Script> meshes_script() {
	static Ref<Script> s;
	if (s.is_null()) {
		s = script_of("res://systems/world_gen/flora/plant_meshes.gd");
	}
	return s;
}
static Ref<Script> archetypes_script() {
	static Ref<Script> s;
	if (s.is_null()) {
		s = script_of("res://systems/world_gen/flora/tree_archetypes.gd");
	}
	return s;
}

// the graphics settings autoload's value (read where a worker thread may ask: it is a plain lookup)
static Variant graphics_value(const StringName &p_key) {
	SceneTree *tree = Object::cast_to<SceneTree>(Engine::get_singleton()->get_main_loop());
	if (tree == nullptr) {
		return Variant();
	}
	Node *settings = tree->get_root()->get_node_or_null("GraphicsSettings");
	return settings != nullptr ? settings->call("get_graphics_value", p_key) : Variant();
}

static bool flora_detailed() {
	return (bool)flora_script()->get("detailed");
}

void PlanetScatter::_bind_methods() {
	BIND_ENUM_CONSTANT(NONE);
	BIND_ENUM_CONSTANT(FAR);
	BIND_ENUM_CONSTANT(TREES);
	BIND_ENUM_CONSTANT(ALL);
	BIND_CONSTANT(PLANT_KEY);
	BIND_CONSTANT(FAR_KEY);
	ClassDB::bind_static_method("PlanetScatter", D_METHOD("tree_light"), &PlanetScatter::tree_light);
	ClassDB::bind_static_method("PlanetScatter", D_METHOD("get_tree_full"), &PlanetScatter::get_tree_full);
	ClassDB::bind_static_method("PlanetScatter", D_METHOD("get_trees_on"), &PlanetScatter::get_trees_on);
	ClassDB::bind_static_method("PlanetScatter", D_METHOD("set_trees_on", "on"), &PlanetScatter::set_trees_on);
	ClassDB::bind_static_method("PlanetScatter", D_METHOD("species_table", "registry"), &PlanetScatter::species_table);
	ClassDB::bind_method(D_METHOD("populate", "holder", "key", "noise", "grid", "cells", "size", "detail", "collide"), &PlanetScatter::populate);
}

bool PlanetScatter::get_trees_on() {
	return trees_on_flag.load();
}
void PlanetScatter::set_trees_on(bool p_on) {
	trees_on_flag.store(p_on);
}

double PlanetScatter::tree_light() {
	OS *os = OS::get_singleton();
	return os->has_environment("PLANET_TREE_LIGHT") ? os->get_environment("PLANET_TREE_LIGHT").to_float() : TREE_LIGHT;
}

Object *PlanetScatter::by_id(int p_id) const {
	return species->call("by_id", p_id);
}

// What pushing through a plant costs the walker, 0 nothing .. 1 a wall: shrubs and thickets the most, grass the least.
static double drag_of(int p_form) {
	switch (p_form) {
		case 4: // SHRUB
			return 0.5;
		case 5: // CACTUS
			return 0.6;
		case 8: // REED
			return 0.3;
		case 10: // FERN
			return 0.22;
		case 7: // TALL_GRASS
			return 0.2;
		case 6: // GRASS
			return 0.05;
		case 9: // FLOWER
			return 0.04;
	}
	return 0.0;
}

// How well a growth form lives in the shade of trees: 1 as well as anywhere, 0 not at all.
static double shade_tolerance(int p_form) {
	switch (p_form) {
		case 10: // FERN
			return 0.9;
		case 11: // MUSHROOM
			return 0.95;
		case 4: // SHRUB
			return 0.55;
		case 6:
		case 7: // GRASS, TALL_GRASS
			return 0.3;
		case 9:
		case 8: // FLOWER, REED
			return 0.2;
		case 5: // CACTUS
			return 0.0;
	}
	return 1.0;
}

// The radius and height of a tree's trunk collider: the trunk's own size (its foot flared by buttress roots, narrowed up a tapering trunk) and
// its bare height (all of it for a conifer).
static Vector2 trunk_footprint(Object *p_one) {
	if (!(bool)p_one->call("is_tree")) {
		return p_one->call("footprint");
	}
	Object *genome = archetypes_script()->call("for_species", p_one);
	double girth = genome->get("girth");
	double root_flare = genome->get("root_flare");
	bool leader = genome->get("leader");
	double height = genome->get("height");
	double trunk_part = genome->get("trunk_part");
	double taper = genome->get("taper");
	double foot = girth * (1.0 + 2.0 * root_flare);
	double up = leader ? height : height * trunk_part;
	double mid = foot * (leader ? 0.6 : (1.0 + (taper - 1.0) * 0.4));
	return Vector2(std::max(mid, 0.15), CLAMP(up, 1.5, 14.0));
}

// The species as plain numbers, for the native placement (PlanetScatterNative.setup).
Array PlanetScatter::species_table(Object *p_registry) {
	Array table;
	Array all = p_registry->get("species");
	for (int i = 0; i < all.size(); i++) {
		Object *one = all[i];
		int form = one->get("form");
		double crown = one->get("crown");
		Dictionary row;
		row["id"] = one->get("id");
		row["layer"] = one->call("layer");
		row["variants"] = one->get("variants");
		row["tree"] = one->call("is_tree");
		row["has_far"] = meshes_script()->call("has_far", one);
		row["moisture"] = one->get("moisture");
		row["moisture_tol"] = one->get("moisture_tol");
		row["heat"] = one->get("heat");
		row["heat_tol"] = one->get("heat_tol");
		row["above_min"] = one->get("above_min");
		row["above_max"] = one->get("above_max");
		row["slope_max"] = one->get("slope_max");
		row["density"] = one->get("density");
		row["patch_freq"] = one->get("patch_freq");
		row["patch_strength"] = one->get("patch_strength");
		row["size_spread"] = one->get("size_spread");
		row["patch_offset"] = one->get("patch_offset");
		row["footprint"] = trunk_footprint(one);
		row["crown"] = crown;
		row["shade_tolerance"] = shade_tolerance(form);
		row["drag"] = drag_of(form);
		row["stem_radius"] = form == 4 ? CLAMP(crown * 0.7, 0.3, 1.2) : CLAMP(crown, 0.2, 0.7);
		table.append(row);
	}
	return table;
}

// Plants a tile into `holder` (a node of its own that the tile adopts when this is done, so it can be built on a worker thread while the tile is
// already in the world). `key` is the tile's key (it seeds the dice); the grid is the tile's padded grid.
void PlanetScatter::populate(Node3D *p_holder, int64_t p_key, const Ref<PlanetNoise> &p_noise, const Dictionary &p_grid, int64_t p_cells, double p_size,
		int64_t p_detail, bool p_collide) {
	packed_positions = p_grid["packed_positions"];
	packed_dirs = p_grid["packed_dirs"];
	tile = p_holder;
	noise = p_noise;
	species = (Object *)noise->get_species();
	heights = p_grid["heights"];
	cells = (int)p_cells;
	side = cells + 3;
	size = p_size;
	if (p_collide) {
		body = memnew(StaticBody3D);
		body->set_collision_layer(1);
		body->set_name("Plants");
		p_holder->add_child(body);
	}
	if (noise->get_scatter_native().is_valid() && !packed_positions.is_empty()) {
		populate_native(p_key, (int)p_detail, p_collide);
	}
}

// The tile's own xz (metres) of one step along the grid, `step` indices along it, a metre of the grid's x or z: the grid is not lined up with
// the tile's axes.
Vector2 PlanetScatter::grid_axis(int p_step) const {
	Vector3 along = packed_positions[side + 1 + p_step] - packed_positions[side + 1];
	return Vector2(along.x, along.z) / (size / cells);
}

// The rotation stored as three rows of three numbers from `at` in `values`.
Basis PlanetScatter::basis_of(const PackedFloat32Array &p_values, int p_at) {
	return Basis(Vector3(p_values[p_at], p_values[p_at + 3], p_values[p_at + 6]), Vector3(p_values[p_at + 1], p_values[p_at + 4], p_values[p_at + 7]),
			Vector3(p_values[p_at + 2], p_values[p_at + 5], p_values[p_at + 8]));
}

void PlanetScatter::populate_native(int64_t p_key, int p_detail, bool p_collide) {
	Dictionary config;
	config["key"] = p_key;
	config["positions"] = packed_positions;
	config["dirs"] = packed_dirs;
	config["heights"] = heights;
	config["cells"] = cells;
	config["size"] = size;
	config["detail"] = p_detail;
	config["collide"] = p_collide;
	config["trees"] = get_trees_on();
	config["clearing"] = noise->get_clearing();
	config["fine"] = (int64_t)graphics_value("ground_detail") >= 2;
	config["grass_fine"] = flora_detailed();
	Dictionary placed = noise->get_scatter_native()->call("scatter", config);
	if (placed.is_empty()) {
		return;
	}
	// the undergrowth a walker pushes through (PlanetUndergrowth)
	tile->set_meta("stems", placed["stems"]);
	PackedFloat32Array turf = placed.get("turf", PackedFloat32Array());
	// where short grass grows over the ground: PlanetTurf makes the tufts round the walker from it
	if (!turf.is_empty()) {
		Dictionary grid;
		grid["positions"] = packed_positions;
		grid["field"] = turf;
		grid["cells"] = cells;
		grid["stones"] = placed.get("stones", PackedFloat32Array());
		grid["size"] = size;
		grid["key"] = p_key;
		grid["corner"] = packed_positions[side + 1];
		grid["ax"] = grid_axis(1);
		grid["az"] = grid_axis(side);
		tile->set_meta("turf", grid);
	}
	bool colliders = body != nullptr && !OS::get_singleton()->has_environment("PLANET_NO_PLANT_COLLIDERS");
	if (colliders) {
		// trunks and rocks stand where they were put: the colliders lean and sink as the things do
		PackedFloat32Array cylinders = placed["cylinders"];
		for (int index = 0; index < cylinders.size() / 14; index++) {
			int at = index * 14;
			Ref<CylinderShape3D> shape;
			shape.instantiate();
			shape->set_radius(cylinders[at + 3]);
			shape->set_height(cylinders[at + 4]);
			CollisionShape3D *collision = memnew(CollisionShape3D);
			collision->set_shape(shape);
			collision->set_transform(Transform3D(basis_of(cylinders, at + 5), Vector3(cylinders[at], cylinders[at + 1], cylinders[at + 2])));
			body->add_child(collision);
		}
		PackedFloat32Array boxes = placed["boxes"];
		for (int index = 0; index < boxes.size() / 15; index++) {
			int at = index * 15;
			Ref<BoxShape3D> box;
			box.instantiate();
			box->set_size(Vector3(boxes[at + 12], boxes[at + 13], boxes[at + 14]));
			CollisionShape3D *collision = memnew(CollisionShape3D);
			collision->set_shape(box);
			collision->set_transform(Transform3D(basis_of(boxes, at + 3), Vector3(boxes[at], boxes[at + 1], boxes[at + 2])));
			body->add_child(collision);
		}
	}
	hang(placed["keys"], placed["buffers"], p_detail == ALL);
	if (colliders) {
		add_limb_colliders(placed["keys"], placed["buffers"]);
	}
}

// The thick low limbs of the trees placed on a tile that can be walked into: a capsule collider on each, moved with its tree.
void PlanetScatter::add_limb_colliders(const PackedInt32Array &p_keys, const Array &p_buffers) {
	if (OS::get_singleton()->has_environment("PLANET_NO_LIMBS")) {
		return;
	}
	for (int at = 0; at < p_keys.size(); at++) {
		int key = p_keys[at];
		if (key < PLANT_KEY || key >= FAR_KEY) {
			continue;
		}
		Object *one = by_id((key - PLANT_KEY) / 100);
		if (!(bool)one->call("is_tree")) {
			continue;
		}
		Ref<Mesh> mesh = species->call("mesh", (int64_t)one->get("id"), key % 100, flora_detailed(), 0);
		PackedFloat32Array capsules = mesh->get_meta("capsules", PackedFloat32Array());
		if (capsules.is_empty()) {
			continue;
		}
		PackedFloat32Array buffer = p_buffers[at];
		for (int tree = 0; tree < buffer.size() / 16; tree++) {
			int i = tree * 16;
			Transform3D placed(Basis(Vector3(buffer[i], buffer[i + 4], buffer[i + 8]), Vector3(buffer[i + 1], buffer[i + 5], buffer[i + 9]),
									   Vector3(buffer[i + 2], buffer[i + 6], buffer[i + 10])),
					Vector3(buffer[i + 3], buffer[i + 7], buffer[i + 11]));
			for (int limb = 0; limb < capsules.size() / 7; limb++) {
				int c = limb * 7;
				Vector3 from = placed.xform(Vector3(capsules[c], capsules[c + 1], capsules[c + 2]));
				Vector3 to = placed.xform(Vector3(capsules[c + 3], capsules[c + 4], capsules[c + 5]));
				double length = from.distance_to(to);
				if (length < 0.05) {
					continue;
				}
				Ref<CapsuleShape3D> shape;
				shape.instantiate();
				shape->set_radius(capsules[c + 6] * placed.basis.get_scale().x);
				shape->set_height(length + 2.0 * shape->get_radius());
				CollisionShape3D *collision = memnew(CollisionShape3D);
				collision->set_shape(shape);
				Vector3 along = (to - from) / length; // the capsule's axis is its y
				Vector3 side_axis = along.cross(std::abs(along.x) < 0.9 ? Vector3(1, 0, 0) : Vector3(0, 0, -1)).normalized();
				collision->set_transform(Transform3D(Basis(side_axis, along, side_axis.cross(along)), (from + to) * 0.5));
				body->add_child(collision);
			}
		}
	}
}

// A batch of instances (16 floats each) split into the cells of the ground it stands on: each cell's instances as a buffer of their own.
Array PlanetScatter::tree_cells(const PackedFloat32Array &p_buffer) const {
	if (noise->get_scatter_native().is_null()) {
		Array one;
		one.append(p_buffer);
		return one;
	}
	return noise->get_scatter_native()->call("split_cells", p_buffer, TREE_CELL);
}

// Hangs the batches (a key and its instances' buffer each) on the tile: a multimesh for each, and the far trees merged into one mesh.
void PlanetScatter::hang(PackedInt32Array p_keys, Array p_buffers, bool p_near) {
	// near trees in cells: the distance range works on a whole node, so a tile's trees as one node were all drawn in full detail while any part of
	// the tile was near (about a third of the triangles)
	PackedInt32Array cell_keys;
	Array cell_buffers;
	for (int at = 0; at < p_keys.size(); at++) {
		int batch_key = p_keys[at];
		if (p_near && batch_key >= PLANT_KEY && batch_key < FAR_KEY && (CELL_PLANTS || (bool)by_id((batch_key - PLANT_KEY) / 100)->call("is_tree"))) {
			Array parts = tree_cells(p_buffers[at]);
			for (int i = 0; i < parts.size(); i++) {
				cell_keys.append(batch_key);
				cell_buffers.append(parts[i]);
			}
		} else {
			cell_keys.append(batch_key);
			cell_buffers.append(p_buffers[at]);
		}
	}
	Array far_parts; // [mesh, buffer] of the far trees of the near ground
	Array horizon_parts; // the same for the horizon: no range, they are all there is
	bool detailed = flora_detailed();
	Ref<Script> meshes = meshes_script();
	double light_range = tree_light();
	for (int at = 0; at < cell_keys.size(); at++) {
		int key = cell_keys[at];
		PackedFloat32Array buffer = cell_buffers[at];
		if (key >= FAR_KEY) {
			Array part;
			part.append(species->call("far_mesh", (key - FAR_KEY) / 100, key % 100));
			part.append(buffer);
			horizon_parts.append(part);
			continue;
		}
		bool plant = key >= PLANT_KEY;
		int id = (key - PLANT_KEY) / 100;
		int variant = key % 100;
		Object *one = plant ? by_id(id) : nullptr;
		int layer = plant ? (int)one->call("layer") : 0;
		bool tree = plant && (bool)one->call("is_tree");
		if (tree && !p_near) {
			// trees beyond the near ground are only ever seen from far: the lighter version
			MultiMeshInstance3D *light = light_trees(buffer, id, variant % 2);
			if ((bool)meshes->call("has_far", one)) {
				light->set_visibility_range_end(light_range);
				light->set_visibility_range_end_margin(TREE_FADE * 2.0);
				light->set_visibility_range_fade_mode(GeometryInstance3D::VISIBILITY_RANGE_FADE_SELF);
				Array part;
				part.append(species->call("far_mesh", id, variant % 2));
				part.append(buffer);
				far_parts.append(part);
			}
			continue;
		}
		Ref<ArrayMesh> mesh;
		if (plant) {
			mesh = species->call("mesh", id, variant, detailed, 0);
		} else {
			mesh = flora_script()->call("mesh", key / 100, variant, detailed);
		}
		MultiMeshInstance3D *instance = add_trees(buffer, mesh, true);
		// a tree or shrub that can bend (PlanetSway takes the ones near the walker)
		if (plant && mesh->has_meta("branches")) {
			Array sets = tile->get_meta("sway_sets", Array());
			Array entry;
			entry.append(instance);
			entry.append(buffer);
			entry.append(mesh->get_aabb().size.y < SMALL_PLANT);
			sets.append(entry);
			tile->set_meta("sway_sets", sets);
		}
		int kind = key / 100;
		if (!plant && (kind == 16 || kind == 17 || kind == 18)) { // PEBBLES, LITTER, TWIGS
			instance->set_visibility_range_end(PEBBLE_VISIBLE);
			instance->set_cast_shadows_setting(GeometryInstance3D::SHADOW_CASTING_SETTING_OFF);
		} else if (layer == 2 || layer == 3) { // GRASS, MEADOW
			OS *os = OS::get_singleton();
			instance->set_visibility_range_end(os->has_environment("PLANET_GRASS_VISIBLE") ? os->get_environment("PLANET_GRASS_VISIBLE").to_float() : GRASS_VISIBLE);
			instance->set_cast_shadows_setting(GeometryInstance3D::SHADOW_CASTING_SETTING_OFF);
		} else if (!p_near) {
			instance->set_cast_shadows_setting(GeometryInstance3D::SHADOW_CASTING_SETTING_OFF);
			instance->set_visibility_range_end(SMALL_VISIBLE);
		} else if (!tree) {
			instance->set_visibility_range_end(SMALL_VISIBLE);
		} else {
			// near trees: the full tree close up, the lighter one (no shadow) further out
			instance->set_visibility_range_end(TREE_FULL);
			instance->set_visibility_range_end_margin(TREE_FADE);
			instance->set_visibility_range_fade_mode(GeometryInstance3D::VISIBILITY_RANGE_FADE_SELF);
			MultiMeshInstance3D *light = light_trees(buffer, id, variant % 2);
			light->set_visibility_range_begin(TREE_FULL * 0.95);
			light->set_visibility_range_begin_margin(TREE_FADE);
			light->set_visibility_range_fade_mode(GeometryInstance3D::VISIBILITY_RANGE_FADE_SELF);
			if ((bool)meshes->call("has_far", one)) {
				light->set_visibility_range_end(light_range);
				light->set_visibility_range_end_margin(TREE_FADE * 2.0);
				light->set_visibility_range_fade_mode(GeometryInstance3D::VISIBILITY_RANGE_FADE_SELF);
				Array part;
				part.append(species->call("far_mesh", id, variant % 2));
				part.append(buffer);
				far_parts.append(part);
			}
		}
	}
	commit_far(far_parts, light_range * 0.95);
	commit_far(horizon_parts, 0.0);
}

// The lighter trees of a variant for the middle distance: quads that show the baked impostor when PlanetImpostors has made it, else the lighter mesh.
MultiMeshInstance3D *PlanetScatter::light_trees(const PackedFloat32Array &p_buffer, int p_id, int p_variant) {
	Dictionary baked = species->call("impostor", p_id, p_variant);
	if (baked.is_empty()) {
		Ref<Mesh> lighter = species->call("mesh", p_id, p_variant, flora_detailed(), 1);
		MultiMeshInstance3D *plain = add_trees(p_buffer, lighter, false);
		species->call("wait_for_impostor", p_id, p_variant, (int64_t)plain->get_instance_id(), p_buffer);
		return plain;
	}
	MultiMeshInstance3D *instance = add_trees(p_buffer, baked["mesh"], false);
	instance->set_material_override(baked["material"]);
	return instance;
}

// One mesh with all the far trees of the tile (parts: [mesh, instances' buffer]), drawn from `begin` metres away (0: always).
void PlanetScatter::commit_far(const Array &p_parts, double p_begin) {
	if (p_parts.is_empty()) {
		return;
	}
	std::map<uint64_t, Array> arrays_of;
	Array sources;
	for (int i = 0; i < p_parts.size(); i++) {
		Array part = p_parts[i];
		Ref<ArrayMesh> mesh = part[0];
		uint64_t id = mesh->get_instance_id();
		if (arrays_of.find(id) == arrays_of.end()) {
			arrays_of[id] = mesh->get_surface_count() > 0 ? mesh->surface_get_arrays(0) : Array();
		}
		Array arrays = arrays_of[id];
		if (arrays.is_empty()) {
			continue;
		}
		Dictionary source;
		source["vertices"] = arrays[Mesh::ARRAY_VERTEX];
		source["normals"] = arrays[Mesh::ARRAY_NORMAL];
		source["colors"] = arrays[Mesh::ARRAY_COLOR];
		source["buffer"] = part[1];
		sources.append(source);
	}
	if (sources.is_empty()) {
		return;
	}
	Dictionary merged = noise->get_scatter_native()->call("merge_far", sources);
	Array arrays;
	arrays.resize(Mesh::ARRAY_MAX);
	arrays[Mesh::ARRAY_VERTEX] = merged["vertices"];
	arrays[Mesh::ARRAY_NORMAL] = merged["normals"];
	arrays[Mesh::ARRAY_COLOR] = merged["colors"];
	Ref<ArrayMesh> mesh;
	mesh.instantiate();
	mesh->add_surface_from_arrays(Mesh::PRIMITIVE_TRIANGLES, arrays);
	MeshInstance3D *instance = memnew(MeshInstance3D);
	instance->set_mesh(mesh);
	instance->set_material_override(flora_script()->call("material"));
	instance->set_cast_shadows_setting(GeometryInstance3D::SHADOW_CASTING_SETTING_OFF);
	instance->set_visibility_range_begin(p_begin);
	instance->set_visibility_range_begin_margin(p_begin > 0.0 ? TREE_FADE * 2.0 : 0.0);
	instance->set_visibility_range_fade_mode(p_begin > 0.0 ? GeometryInstance3D::VISIBILITY_RANGE_FADE_SELF : GeometryInstance3D::VISIBILITY_RANGE_FADE_DISABLED);
	tile->add_child(instance);
}

// One multimesh of `mesh` at the instances in `buffer` (12 floats of transform and 4 of colour each), added to the tile.
MultiMeshInstance3D *PlanetScatter::add_trees(const PackedFloat32Array &p_buffer, const Ref<Mesh> &p_mesh, bool p_shadows) {
	Ref<MultiMesh> multi;
	multi.instantiate();
	multi->set_transform_format(MultiMesh::TRANSFORM_3D);
	multi->set_use_colors(true);
	multi->set_mesh(p_mesh);
	multi->set_instance_count((int)(p_buffer.size() / 16));
	multi->set_buffer(p_buffer);
	MultiMeshInstance3D *instance = memnew(MultiMeshInstance3D);
	instance->set_multimesh(multi);
	instance->set_material_override(flora_script()->call("material"));
	if (!p_shadows) {
		instance->set_cast_shadows_setting(GeometryInstance3D::SHADOW_CASTING_SETTING_OFF);
	}
	tile->add_child(instance);
	return instance;
}
