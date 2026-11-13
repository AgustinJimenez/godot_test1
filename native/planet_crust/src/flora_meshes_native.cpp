#include "flora_meshes_native.h"

#include "plant_mesh_native.h"
#include "species_registry_native.h"

#include <godot_cpp/classes/mesh.hpp>
#include <godot_cpp/classes/multi_mesh.hpp>
#include <godot_cpp/classes/plane_mesh.hpp>
#include <godot_cpp/classes/random_number_generator.hpp>
#include <godot_cpp/classes/resource_loader.hpp>
#include <godot_cpp/classes/shader.hpp>
#include <godot_cpp/classes/texture2d.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/core/math.hpp>
#include <godot_cpp/variant/packed_color_array.hpp>
#include <godot_cpp/variant/packed_vector2_array.hpp>
#include <godot_cpp/variant/packed_vector3_array.hpp>
#include <godot_cpp/variant/utility_functions.hpp>

#include <cmath>
#include <map>
#include <mutex>
#include <vector>

using namespace godot;

namespace {

std::mutex &state_lock() {
	static std::mutex lock;
	return lock;
}

struct State {
	Ref<ShaderMaterial> material;
	Ref<ShaderMaterial> structure_material;
	Ref<ShaderMaterial> chip_material;
	Ref<ShaderMaterial> chip_shadow_material;
	Ref<PlaneMesh> chip_shadow_mesh;
	std::map<int, Ref<ArrayMesh>> scenery;
	Ref<ArrayMesh> turf[FloraMeshes::TURF_VARIANTS];
	Ref<ArrayMesh> chips[FloraMeshes::CHIP_VARIANTS];
	bool detailed = false;
};

State &state() {
	static State s;
	return s;
}

Ref<RandomNumberGenerator> dice(int64_t p_seed) {
	Ref<RandomNumberGenerator> rng;
	rng.instantiate();
	rng->set_seed(p_seed);
	return rng;
}

Ref<Shader> load_shader(const char *p_path) {
	return ResourceLoader::get_singleton()->load(p_path);
}

} // namespace

void FloraMeshes::_bind_methods() {
	BIND_ENUM_CONSTANT(ROCK);
	BIND_ENUM_CONSTANT(STUMP);
	BIND_ENUM_CONSTANT(LOG);
	BIND_ENUM_CONSTANT(SPIRE);
	BIND_ENUM_CONSTANT(PEBBLES);
	BIND_ENUM_CONSTANT(LITTER);
	BIND_ENUM_CONSTANT(TWIGS);
	BIND_CONSTANT(TURF_VARIANTS);
	BIND_CONSTANT(TURF_BLADES);
	BIND_CONSTANT(CHIP_VARIANTS);
	ClassDB::bind_static_method("FloraMeshes", D_METHOD("material"), &FloraMeshes::material);
	ClassDB::bind_static_method("FloraMeshes", D_METHOD("structure_material"), &FloraMeshes::structure_material);
	ClassDB::bind_static_method("FloraMeshes", D_METHOD("mesh", "kind", "variant", "detailed"), &FloraMeshes::mesh, DEFVAL(false));
	ClassDB::bind_static_method("FloraMeshes", D_METHOD("variant_count", "kind"), &FloraMeshes::variant_count);
	ClassDB::bind_static_method("FloraMeshes", D_METHOD("variants"), &FloraMeshes::variants);
	ClassDB::bind_static_method("FloraMeshes", D_METHOD("get_detailed"), &FloraMeshes::get_detailed);
	ClassDB::bind_static_method("FloraMeshes", D_METHOD("set_detailed", "on"), &FloraMeshes::set_detailed);
	ClassDB::bind_static_method("FloraMeshes", D_METHOD("turf_tuft", "variant"), &FloraMeshes::turf_tuft);
	ClassDB::bind_static_method("FloraMeshes", D_METHOD("chip_material"), &FloraMeshes::chip_material);
	ClassDB::bind_static_method("FloraMeshes", D_METHOD("chip_shadow", "buffer"), &FloraMeshes::chip_shadow);
	ClassDB::bind_static_method("FloraMeshes", D_METHOD("chip", "variant"), &FloraMeshes::chip);
}

Ref<ShaderMaterial> FloraMeshes::material() {
	std::lock_guard<std::mutex> guard(state_lock());
	State &s = state();
	if (s.material.is_null()) {
		Ref<ShaderMaterial> made;
		made.instantiate();
		made->set_shader(load_shader("res://shaders/world/flora_wind.gdshader"));
		Ref<Texture2D> bark = ResourceLoader::get_singleton()->load("res://assets/textures/bark/bark_atlas.png");
		made->set_shader_parameter("bark_photo", bark);
		Ref<Texture2D> rocks = ResourceLoader::get_singleton()->load("res://assets/textures/rock/rock_atlas.png");
		made->set_shader_parameter("rock_photo", rocks);
		s.material = made;
	}
	return s.material;
}

Ref<ShaderMaterial> FloraMeshes::structure_material() {
	Ref<ShaderMaterial> base = material();
	std::lock_guard<std::mutex> guard(state_lock());
	State &s = state();
	if (s.structure_material.is_null()) {
		Ref<ShaderMaterial> made = base->duplicate();
		made->set_shader_parameter("planks", true);
		s.structure_material = made;
	}
	return s.structure_material;
}

int FloraMeshes::variant_count(int p_kind) {
	switch (p_kind) {
		case ROCK:
			return 6;
		case STUMP:
			return 2;
		case LOG:
			return 3;
		case SPIRE:
			return 3;
		case PEBBLES:
			return 4;
		case LITTER:
			return 5;
		case TWIGS:
			return 4;
		default:
			return 1;
	}
}

Dictionary FloraMeshes::variants() {
	Dictionary out;
	for (int kind : { ROCK, STUMP, LOG, SPIRE, PEBBLES, LITTER, TWIGS }) {
		out[kind] = variant_count(kind);
	}
	return out;
}

bool FloraMeshes::get_detailed() {
	std::lock_guard<std::mutex> guard(state_lock());
	return state().detailed;
}

void FloraMeshes::set_detailed(bool p_on) {
	std::lock_guard<std::mutex> guard(state_lock());
	state().detailed = p_on;
}

Ref<ArrayMesh> FloraMeshes::mesh(int p_kind, int p_variant, bool p_detailed) {
	const int key = p_kind * 100 + p_variant + (p_detailed ? 10000 : 0);
	{
		std::lock_guard<std::mutex> guard(state_lock());
		auto found = state().scenery.find(key);
		if (found != state().scenery.end()) {
			return found->second;
		}
	}
	Ref<PlantMeshNative> maker;
	maker.instantiate();
	Ref<ArrayMesh> built = PlantMeshes::mesh_from(maker->scenery(p_kind, p_variant, p_detailed));
	std::lock_guard<std::mutex> guard(state_lock());
	auto found = state().scenery.find(key);
	if (found != state().scenery.end()) {
		return found->second;
	}
	state().scenery[key] = built;
	return built;
}

// ---- the tufts of the turf ----

namespace {

struct BladeRow {
	Vector3 at;
	double uv_y;
	double sway;
	double link;
};

Ref<ArrayMesh> make_tuft(int p_variant) {
	Ref<RandomNumberGenerator> rng = dice(7919 * (int64_t)(p_variant + 1));
	PackedVector3Array vertices;
	PackedVector3Array normals;
	PackedColorArray colors;
	PackedVector2Array uvs;
	PackedVector2Array uv2s;
	PackedFloat32Array links;
	// the root (the ground): never moves
	PackedFloat32Array table;
	for (int i = 0; i < 10; i++) {
		table.push_back(0.0f);
	}
	for (int blade = 0; blade < FloraMeshes::TURF_BLADES; blade++) {
		// at its own place (within a hand breadth, more of them near the middle), turned any way, leaning out and over
		const double around = rng->randf() * Math_TAU;
		const double reach = 0.14 * Math::sqrt((double)rng->randf());
		const Vector3 root(Math::cos(around) * reach, 0.0, Math::sin(around) * reach);
		const double yaw = rng->randf() * Math_TAU;
		const double lean_way = around + rng->randf_range(-0.8, 0.8);
		const double lean = rng->randf_range(0.0, 0.3);
		const double arch = rng->randf_range(0.15, 0.75); // how much further the upper part leans over
		const double tall = rng->randf_range(0.14, 0.34);
		const double wide = rng->randf_range(0.03, 0.055);
		const Vector3 side(Math::cos(lean_way), 0.0, Math::sin(lean_way));
		const Vector3 low_up = (Vector3(0, 1, 0) * Math::cos(lean) + side * Math::sin(lean)).normalized();
		const Vector3 high_up = (Vector3(0, 1, 0) * Math::cos(lean + arch) + side * Math::sin(lean + arch)).normalized();
		Vector3 across(Math::cos(yaw), 0.0, Math::sin(yaw));
		across = (across - low_up * across.dot(low_up)).normalized();
		const Vector3 middle = root + low_up * tall * 0.5;
		const Vector3 tip = middle + high_up * tall * 0.55;
		const int low_id = 1 + blade * 2;
		const float first[10] = { 0, 9, (float)root.x, (float)root.y, (float)root.z, (float)middle.x, (float)middle.y, (float)middle.z, 0.01f, (float)(tall * 0.5) };
		const float second[10] = { (float)low_id, 9, (float)middle.x, (float)middle.y, (float)middle.z, (float)tip.x, (float)tip.y, (float)tip.z, 0.01f, (float)(tall * 0.55) };
		for (int i = 0; i < 10; i++) {
			table.push_back(first[i]);
		}
		for (int i = 0; i < 10; i++) {
			table.push_back(second[i]);
		}
		const double blade_dice = rng->randf();
		// three rows of the blade (root, middle, tip), its width kept; the shader tapers it to a point
		const BladeRow rows[3] = { { root, 0.0, 0.0, (double)low_id }, { middle, 0.5, 0.35, (double)low_id }, { tip, 1.0, 0.8, (double)(low_id + 1) } };
		for (int part = 0; part < 2; part++) {
			const BladeRow &from = rows[part];
			const BladeRow &to = rows[part + 1];
			const Vector3 quad_at[4] = { from.at - across * wide * 0.5, from.at + across * wide * 0.5, to.at + across * wide * 0.5, to.at - across * wide * 0.5 };
			const BladeRow *quad_row[4] = { &from, &from, &to, &to };
			const Vector2 quad_uv[4] = { Vector2(0, from.uv_y), Vector2(1, from.uv_y), Vector2(1, to.uv_y), Vector2(0, to.uv_y) };
			for (int index : { 0, 1, 2, 0, 2, 3 }) {
				const BladeRow &row = *quad_row[index];
				vertices.push_back(quad_at[index]);
				normals.push_back(Vector3(0, 1, 0));
				colors.push_back(Color(0.22f, 0.34f, 0.12f, (float)row.sway)); // (alpha: how much the wind moves it)
				uvs.push_back(quad_uv[index]);
				uv2s.push_back(Vector2((float)blade_dice, 8.0f));
				links.push_back((float)row.link);
			}
		}
	}
	Array arrays;
	arrays.resize(Mesh::ARRAY_MAX);
	arrays[Mesh::ARRAY_VERTEX] = vertices;
	arrays[Mesh::ARRAY_NORMAL] = normals;
	arrays[Mesh::ARRAY_COLOR] = colors;
	arrays[Mesh::ARRAY_TEX_UV] = uvs;
	arrays[Mesh::ARRAY_TEX_UV2] = uv2s;
	arrays[Mesh::ARRAY_CUSTOM0] = links;
	Ref<ArrayMesh> mesh;
	mesh.instantiate();
	mesh->add_surface_from_arrays(Mesh::PRIMITIVE_TRIANGLES, arrays, Array(), Dictionary(), (int64_t)Mesh::ARRAY_CUSTOM_R_FLOAT << Mesh::ARRAY_FORMAT_CUSTOM0_SHIFT);
	mesh->set_meta("branches", table);
	return mesh;
}

Ref<ArrayMesh> make_chip(int p_variant) {
	Ref<RandomNumberGenerator> rng = dice(104729 * (int64_t)(p_variant + 3));
	const double golden = (1.0 + Math::sqrt(5.0)) * 0.5;
	std::vector<Vector3> corners = { Vector3(-1, golden, 0), Vector3(1, golden, 0), Vector3(-1, -golden, 0), Vector3(1, -golden, 0),
		Vector3(0, -1, golden), Vector3(0, 1, golden), Vector3(0, -1, -golden), Vector3(0, 1, -golden),
		Vector3(golden, 0, -1), Vector3(golden, 0, 1), Vector3(-golden, 0, -1), Vector3(-golden, 0, 1) };
	const double shape_x = rng->randf_range(0.8, 1.15);
	const double shape_y = rng->randf_range(0.7, 1.0);
	const double shape_z = rng->randf_range(0.8, 1.15);
	for (size_t index = 0; index < corners.size(); index++) {
		// (knocked about: no two corners as far)
		Vector3 point = corners[index].normalized() * rng->randf_range(0.72, 1.08);
		point = Vector3(point.x * shape_x, point.y * shape_y, point.z * shape_z);
		point.y = Math::max((double)point.y, -0.35); // (the underside is flat: it is in the ground)
		corners[index] = point;
	}
	std::vector<std::vector<int>> faces = { { 0, 11, 5 }, { 0, 5, 1 }, { 0, 1, 7 }, { 0, 7, 10 }, { 0, 10, 11 }, { 1, 5, 9 }, { 5, 11, 4 },
		{ 11, 10, 2 }, { 10, 7, 6 }, { 7, 1, 8 },
		{ 3, 9, 4 }, { 3, 4, 2 }, { 3, 2, 6 }, { 3, 6, 8 }, { 3, 8, 9 }, { 4, 9, 5 }, { 2, 4, 11 }, { 6, 2, 10 },
		{ 8, 6, 7 }, { 9, 8, 1 } };
	// each triangle in four (80 in all): the new points pushed in or out, so that a stone has more than twenty flat
	// faces; the odd variants are rounder (smaller pushes) than the even (angular)
	const double push = p_variant % 2 == 1 ? 0.05 : 0.14;
	std::map<int, int> midpoints;
	std::vector<std::vector<int>> split;
	for (const std::vector<int> &face : faces) {
		int mids[3];
		const int pairs[3][2] = { { face[0], face[1] }, { face[1], face[2] }, { face[2], face[0] } };
		for (int k = 0; k < 3; k++) {
			const int a = pairs[k][0];
			const int b = pairs[k][1];
			const int edge_key = Math::min(a, b) * 64 + Math::max(a, b);
			auto found = midpoints.find(edge_key);
			if (found == midpoints.end()) {
				Vector3 middle = (corners[a] + corners[b]) * 0.5;
				middle *= 1.0 + rng->randf_range(-push, push) + 0.08;
				middle.y = Math::max((double)middle.y, -0.35);
				corners.push_back(middle);
				midpoints[edge_key] = (int)corners.size() - 1;
				mids[k] = (int)corners.size() - 1;
			} else {
				mids[k] = found->second;
			}
		}
		split.push_back({ face[0], mids[0], mids[2] });
		split.push_back({ mids[0], face[1], mids[1] });
		split.push_back({ mids[2], mids[1], face[2] });
		split.push_back({ mids[0], mids[1], mids[2] });
	}
	PackedVector3Array vertices;
	PackedVector3Array normals;
	PackedColorArray colors;
	for (const std::vector<int> &face : split) {
		Vector3 a = corners[face[0]];
		Vector3 b = corners[face[1]];
		Vector3 c = corners[face[2]];
		Vector3 normal = (b - a).cross(c - a).normalized();
		if (normal.dot((a + b + c) / 3.0) < 0.0) { // outward
			Vector3 swap_point = b;
			b = c;
			c = swap_point;
			normal = -normal;
		}
		for (const Vector3 &point : { a, c, b }) { // (Godot wants clockwise)
			vertices.push_back(point);
			normals.push_back(normal);
			colors.push_back(Color(1, 1, 1, 0.0f)); // (alpha 0: a stone does not sway)
		}
	}
	Array arrays;
	arrays.resize(Mesh::ARRAY_MAX);
	arrays[Mesh::ARRAY_VERTEX] = vertices;
	arrays[Mesh::ARRAY_NORMAL] = normals;
	arrays[Mesh::ARRAY_COLOR] = colors;
	Ref<ArrayMesh> mesh;
	mesh.instantiate();
	mesh->add_surface_from_arrays(Mesh::PRIMITIVE_TRIANGLES, arrays);
	return mesh;
}

} // namespace

Ref<ArrayMesh> FloraMeshes::turf_tuft(int p_variant) {
	const int at = ((p_variant % TURF_VARIANTS) + TURF_VARIANTS) % TURF_VARIANTS;
	{
		std::lock_guard<std::mutex> guard(state_lock());
		if (state().turf[at].is_valid()) {
			return state().turf[at];
		}
	}
	Ref<ArrayMesh> built = make_tuft(at);
	std::lock_guard<std::mutex> guard(state_lock());
	if (state().turf[at].is_null()) {
		state().turf[at] = built;
	}
	return state().turf[at];
}

Ref<ArrayMesh> FloraMeshes::chip(int p_variant) {
	const int at = ((p_variant % CHIP_VARIANTS) + CHIP_VARIANTS) % CHIP_VARIANTS;
	{
		std::lock_guard<std::mutex> guard(state_lock());
		if (state().chips[at].is_valid()) {
			return state().chips[at];
		}
	}
	Ref<ArrayMesh> built = make_chip(at);
	std::lock_guard<std::mutex> guard(state_lock());
	if (state().chips[at].is_null()) {
		state().chips[at] = built;
	}
	return state().chips[at];
}

Ref<ShaderMaterial> FloraMeshes::chip_material() {
	std::lock_guard<std::mutex> guard(state_lock());
	State &s = state();
	if (s.chip_material.is_null()) {
		Ref<ShaderMaterial> made;
		made.instantiate();
		made->set_shader(load_shader("res://shaders/world/planet_chip.gdshader"));
		s.chip_material = made;
	}
	return s.chip_material;
}

MultiMeshInstance3D *FloraMeshes::chip_shadow(const PackedFloat32Array &p_buffer) {
	Ref<ShaderMaterial> shadow_material;
	Ref<PlaneMesh> shadow_mesh;
	{
		std::lock_guard<std::mutex> guard(state_lock());
		State &s = state();
		if (s.chip_shadow_material.is_null()) {
			Ref<ShaderMaterial> made;
			made.instantiate();
			made->set_shader(load_shader("res://shaders/world/planet_chip_shadow.gdshader"));
			s.chip_shadow_material = made;
			Ref<PlaneMesh> plane;
			plane.instantiate();
			plane->set_size(Vector2(2.0, 2.0));
			s.chip_shadow_mesh = plane;
		}
		shadow_material = s.chip_shadow_material;
		shadow_mesh = s.chip_shadow_mesh;
	}
	Ref<MultiMesh> multi;
	multi.instantiate();
	multi->set_transform_format(MultiMesh::TRANSFORM_3D);
	multi->set_use_colors(true);
	multi->set_mesh(shadow_mesh);
	multi->set_instance_count((int)(p_buffer.size() / 16));
	multi->set_buffer(p_buffer);
	MultiMeshInstance3D *instance = memnew(MultiMeshInstance3D);
	instance->set_multimesh(multi);
	instance->set_material_override(shadow_material);
	instance->set_cast_shadows_setting(GeometryInstance3D::SHADOW_CASTING_SETTING_OFF);
	return instance;
}
