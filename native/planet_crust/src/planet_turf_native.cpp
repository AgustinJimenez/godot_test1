#include "planet_turf_native.h"

#include "planet_noise_native.h"
#include "planet_sway_native.h"

#include <godot_cpp/classes/camera3d.hpp>
#include <godot_cpp/classes/multi_mesh.hpp>
#include <godot_cpp/classes/os.hpp>
#include <godot_cpp/classes/resource_loader.hpp>
#include <godot_cpp/classes/script.hpp>
#include <godot_cpp/classes/viewport.hpp>

#include <algorithm>
#include <cmath>

using namespace godot;

// FloraMeshes (GDScript, the world's plant meshes): its static functions and constants, reached through its script
static Ref<Script> flora_script() {
	static Ref<Script> script;
	if (script.is_null()) {
		script = ResourceLoader::get_singleton()->load("res://systems/world_gen/flora_meshes.gd");
	}
	return script;
}

static int64_t flora_constant(const String &p_name) {
	return (int64_t)Dictionary(flora_script()->get_script_constant_map())[p_name];
}

void PlanetTurf::_bind_methods() {
	NP_BIND_OBJECT(PlanetTurf, planet)
	NP_BIND_OBJECT(PlanetTurf, player)
	NP_BIND(PlanetTurf, Variant::BOOL, gravel)
	ClassDB::bind_method(D_METHOD("chunk_sets"), &PlanetTurf::chunk_sets);
	ClassDB::bind_method(D_METHOD("tuft_count"), &PlanetTurf::tuft_count);
	ClassDB::bind_method(D_METHOD("far_count"), &PlanetTurf::far_count);
}

double PlanetTurf::enter() const {
	return gravel ? GRAVEL_DRAWN + 4.0 : ENTER;
}

double PlanetTurf::leave() const {
	return gravel ? GRAVEL_DRAWN + 12.0 : LEAVE;
}

// The farthest a chunk of grass is made, in the view (the stones: no farther than ever).
double PlanetTurf::far_reach() const {
	return gravel ? enter() : FAR_ENTER;
}

double PlanetTurf::spacing() {
	OS *os = OS::get_singleton();
	return os->has_environment("PLANET_TURF_SPACING") ? os->get_environment("PLANET_TURF_SPACING").to_float() : SPACING;
}

void PlanetTurf::_physics_process(double p_delta) {
	Object *planet_object = get_planet();
	Node3D *player_node = Object::cast_to<Node3D>(get_player());
	if (player_node == nullptr || planet_object == nullptr) {
		return;
	}
	Ref<PlanetNoise> noise = planet_object->get("noise");
	if (noise.is_null() || noise->get_scatter_native().is_null()) {
		return;
	}
	since += p_delta;
	if (since < LOOK_EVERY) {
		return;
	}
	since = 0.0;
	Vector3 here = player_node->get_global_position();
	Camera3D *camera = get_viewport()->get_camera_3d();
	Vector3 way; // where the camera looks, flat (the chunks it sees are made first)
	if (camera != nullptr) {
		way = -camera->get_global_transform().basis.get_column(2);
		way.y = 0.0;
		way = way.normalized();
	}
	let_go(here, way);
	// every chunk wanted and not yet made, nearest and most in view first: a walker never waits for the patch in front of them while chunks
	// behind (or off to the side) are made in the order of the grid
	struct Wanted {
		double order, distance;
		int64_t key;
		Node3D *holder;
		Dictionary grid;
		int ix, iz, level;
	};
	std::vector<Wanted> wanted;
	Object *surface = planet_object->get("surface");
	Dictionary all = surface->get("tiles");
	Array tiles = all.values();
	for (int t = 0; t < tiles.size(); t++) {
		Object *tile = tiles[t];
		Node3D *holder = Object::cast_to<Node3D>((Object *)tile->get("plant_holder"));
		if (holder == nullptr || !holder->has_meta("turf")) {
			continue;
		}
		Dictionary grid = holder->get_meta("turf");
		// (the grid's own space: metres from its corner along its x and z)
		Vector3 local = grid_of(grid, holder->to_local(here));
		double size = grid["size"];
		double reach = way != Vector3() ? far_reach() : enter(); // (the farthest a chunk may be made, in the view)
		if (local.x < -reach || local.z < -reach || local.x > size + reach || local.z > size + reach) {
			continue;
		}
		int from_x = std::max((int)std::floor((local.x - reach) / CHUNK), 0);
		int to_x = std::min((int)std::floor((local.x + reach) / CHUNK), (int)std::ceil(size / CHUNK) - 1);
		int from_z = std::max((int)std::floor((local.z - reach) / CHUNK), 0);
		int to_z = std::min((int)std::floor((local.z + reach) / CHUNK), (int)std::ceil(size / CHUNK) - 1);
		Vector2 ahead; // the camera's way in this grid's axes
		if (way != Vector3()) {
			Vector3 moved = grid_of(grid, holder->to_local(here + way));
			ahead = Vector2(moved.x - local.x, moved.z - local.z).normalized();
		}
		for (int iz = from_z; iz <= to_z; iz++) {
			for (int ix = from_x; ix <= to_x; ix++) {
				int64_t key = (int64_t)holder->get_instance_id() * 10000 + ix * 100 + iz;
				Vector2 middle((ix + 0.5) * CHUNK, (iz + 0.5) * CHUNK);
				Vector2 offset = middle - Vector2(local.x, local.z);
				double distance = offset.length();
				auto found = chunks.find(key);
				if (found != chunks.end()) {
					// (a thin chunk made for the view that the walker has come up to is made again, finer)
					if (found->second.level <= level_of(distance)) {
						continue;
					}
					drop(key);
				}
				double facing = ahead == Vector2() ? 1.0 : offset.normalized().dot(ahead);
				bool far_chunk = level_of(distance) > 0;
				if (far_chunk && (distance > reach + CHUNK * 0.4 || ahead == Vector2() || facing < FAR_COS)) {
					continue;
				}
				bool seen = distance < CHUNK || (ahead != Vector2() && facing > VIEW_COS);
				wanted.push_back({ distance - (seen ? VIEW_BONUS : 0.0), distance, key, holder, grid, ix, iz, level_of(distance) });
			}
		}
	}
	std::sort(wanted.begin(), wanted.end(), [](const Wanted &a, const Wanted &b) { return a.order < b.order; });
	int made = 0;
	for (const Wanted &item : wanted) {
		// (the chunks round the walker's feet are never held back; the rest are made a few at a look)
		if (made >= MAKE_EACH_LOOK && item.distance > NEAR) {
			break;
		}
		made += 1;
		make(item.key, item.holder, item.grid, item.ix, item.iz, item.level);
	}
}

// How fine a chunk `distance` away is made: 0 the walker's ring, 1 thinner out to MID_ENTER, 2 thinner and bigger out to FAR_ENTER (the stones: 0).
int PlanetTurf::level_of(double p_distance) const {
	if (gravel || p_distance <= enter() + CHUNK * 0.4) {
		return 0;
	}
	return p_distance <= MID_ENTER + CHUNK * 0.4 ? 1 : 2;
}

// The tufts of a buffer (16 floats each: the basis's rows with the position at 3, 7 and 11) made `factor` times bigger on the spot.
PackedFloat32Array PlanetTurf::bigger(const PackedFloat32Array &p_buffer, double p_factor) {
	PackedFloat32Array source = p_buffer;
	PackedFloat32Array made = source.duplicate();
	static const int indices[9] = { 0, 1, 2, 4, 5, 6, 8, 9, 10 };
	for (int64_t at = 0; at < made.size(); at += 16) {
		for (int index : indices) {
			made[at + index] = (double)made[at + index] * p_factor;
		}
	}
	return made;
}

// `level`: 0 the walker's ring, 1 and 2 the chunks seen from afar (thinner, drawn farther, and the farthest bigger).
void PlanetTurf::make(int64_t p_key, Node3D *p_holder, const Dictionary &p_grid, int p_ix, int p_iz, int p_level) {
	Object *planet_object = get_planet();
	Ref<PlanetNoise> noise = planet_object->get("noise");
	Object *scatter = noise->get_scatter_native().ptr();
	double size = p_grid["size"];
	Array buffers;
	double x_from = p_ix * CHUNK, z_from = p_iz * CHUNK;
	double x_to = std::min((p_ix + 1) * CHUNK, size), z_to = std::min((p_iz + 1) * CHUNK, size);
	int64_t seed = p_key ^ (int64_t)p_grid["key"];
	if (gravel) { // (none where the crust says there are no stones: a dune, a clean region)
		Variant stones = p_grid.get("stones", PackedFloat32Array());
		buffers = scatter->call("gravel_chunk", p_grid["positions"], p_grid["field"], p_grid["cells"], size, x_from, z_from, x_to, z_to, GRAVEL_SPACING, 1.0,
				seed, flora_constant("CHIP_VARIANTS"), stones);
	} else {
		static const double thin[3] = { 1.0, FAR_THIN, VERY_THIN };
		buffers = scatter->call("turf_chunk", p_grid["positions"], p_grid["field"], p_grid["cells"], size, x_from, z_from, x_to, z_to, spacing() * thin[p_level],
				DENSITY, seed, flora_constant("TURF_VARIANTS"));
		if (p_level == 2) {
			for (int variant = 0; variant < buffers.size(); variant++) {
				buffers[variant] = bigger(buffers[variant], VERY_BIG);
			}
		}
	}
	int level = gravel ? 0 : p_level;
	Chunk entry;
	entry.level = level;
	entry.holder = ObjectID(p_holder->get_instance_id());
	entry.grid = p_grid;
	entry.at = Vector2((p_ix + 0.5) * CHUNK, (p_iz + 0.5) * CHUNK);
	Ref<Script> flora = flora_script();
	static const double drawn[3] = { DRAWN, FAR_DRAWN, VERY_DRAWN };
	for (int variant = 0; variant < buffers.size(); variant++) {
		PackedFloat32Array buffer = buffers[variant];
		if (buffer.is_empty()) {
			continue;
		}
		Ref<MultiMesh> multi;
		multi.instantiate();
		multi->set_transform_format(MultiMesh::TRANSFORM_3D);
		multi->set_use_colors(true);
		multi->set_mesh(gravel ? flora->call("chip", variant) : flora->call("turf_tuft", variant));
		multi->set_instance_count((int)(buffer.size() / 16));
		multi->set_buffer(buffer);
		MultiMeshInstance3D *instance = memnew(MultiMeshInstance3D);
		instance->set_multimesh(multi);
		instance->set_material_override(gravel ? flora->call("chip_material") : flora->call("material"));
		instance->set_cast_shadows_setting(gravel ? GeometryInstance3D::SHADOW_CASTING_SETTING_ON : GeometryInstance3D::SHADOW_CASTING_SETTING_OFF);
		instance->set_visibility_range_end(gravel ? GRAVEL_DRAWN : drawn[level]);
		instance->set_visibility_range_end_margin(6.0);
		instance->set_visibility_range_fade_mode(GeometryInstance3D::VISIBILITY_RANGE_FADE_SELF);
		p_holder->add_child(instance);
		entry.nodes.push_back(ObjectID(instance->get_instance_id()));
		entry.buffers.push_back(buffer);
		if (gravel) {
			MultiMeshInstance3D *patch = Object::cast_to<MultiMeshInstance3D>((Object *)flora->call("chip_shadow", buffer));
			patch->set_visibility_range_end(GRAVEL_DRAWN);
			patch->set_visibility_range_end_margin(6.0);
			patch->set_visibility_range_fade_mode(GeometryInstance3D::VISIBILITY_RANGE_FADE_SELF);
			p_holder->add_child(patch);
			entry.shadows.push_back(ObjectID(patch->get_instance_id()));
		}
	}
	chunks[p_key] = entry;
}

// Chunks the walker has left (or whose tile has gone) are let go.
void PlanetTurf::let_go(const Vector3 &p_here, const Vector3 &p_way) {
	std::vector<int64_t> keys;
	for (const auto &pair : chunks) {
		keys.push_back(pair.first);
	}
	for (int64_t key : keys) {
		const Chunk &entry = chunks[key];
		Node3D *holder = Object::cast_to<Node3D>(ObjectDB::get_instance(entry.holder)); // (a tile that has gone is a freed object)
		bool gone = holder == nullptr || !holder->is_inside_tree();
		if (!gone) {
			Vector3 local = grid_of(entry.grid, holder->to_local(p_here));
			Vector2 offset = entry.at - Vector2(local.x, local.z);
			if (entry.level > 0 && p_way != Vector3()) {
				// (a chunk made for the view stays while it is in the wide cone of it, or close)
				Vector3 moved = grid_of(entry.grid, holder->to_local(p_here + p_way));
				Vector2 ahead = Vector2(moved.x - local.x, moved.z - local.z).normalized();
				bool in_view = offset.normalized().dot(ahead) > LEAVE_COS;
				gone = offset.length() > FAR_LEAVE + CHUNK * 0.4 || (!in_view && offset.length() > leave() + CHUNK * 0.4);
			} else {
				gone = offset.length() > leave() + CHUNK * 0.4;
			}
		}
		if (gone) {
			drop(key);
		}
	}
}

// Let the chunk go: its nodes are freed.
void PlanetTurf::drop(int64_t p_key) {
	auto found = chunks.find(p_key);
	if (found == chunks.end()) {
		return;
	}
	for (const std::vector<ObjectID> *list : { &found->second.nodes, &found->second.shadows }) {
		for (ObjectID id : *list) {
			Node *node = Object::cast_to<Node>(ObjectDB::get_instance(id));
			if (node != nullptr) {
				node->queue_free();
			}
		}
	}
	chunks.erase(found);
}

// A point of the holder's space in the grid's: x and z in metres from the grid's corner along the grid's own axes (y: unchanged).
Vector3 PlanetTurf::grid_of(const Dictionary &p_grid, const Vector3 &p_local) {
	Vector3 corner = p_grid["corner"];
	Vector2 ax = p_grid["ax"];
	Vector2 az = p_grid["az"];
	Vector2 d(p_local.x - corner.x, p_local.z - corner.z);
	double det = ax.x * az.y - ax.y * az.x;
	if (std::abs(det) < 0.0001) {
		return Vector3(d.x, p_local.y, d.y);
	}
	return Vector3((d.x * az.y - d.y * az.x) / det, p_local.y, (ax.x * d.y - ax.y * d.x) / det);
}

// The chunks as [holder, [MultiMeshInstance3D, buffer, true]] (the same as the plants' `sway_sets`): PlanetSway takes the tufts nearest the
// walker out of them and bends them.
Array PlanetTurf::chunk_sets() const {
	Array sets;
	for (const auto &pair : chunks) {
		const Chunk &entry = pair.second;
		Object *holder = ObjectDB::get_instance(entry.holder);
		if (holder == nullptr) {
			continue;
		}
		for (size_t at = 0; at < entry.nodes.size(); at++) {
			Object *node = ObjectDB::get_instance(entry.nodes[at]);
			if (node != nullptr) {
				Array kind;
				kind.append(node);
				kind.append(entry.buffers[at]);
				kind.append(PlanetSway::TURF);
				Array one;
				one.append(holder);
				one.append(kind);
				sets.append(one);
			}
		}
	}
	return sets;
}

// How many tufts are drawn now (for the checks).
int64_t PlanetTurf::tuft_count() const {
	int64_t total = 0;
	for (const auto &pair : chunks) {
		for (ObjectID id : pair.second.nodes) {
			MultiMeshInstance3D *node = Object::cast_to<MultiMeshInstance3D>(ObjectDB::get_instance(id));
			if (node != nullptr) {
				total += node->get_multimesh()->get_instance_count();
			}
		}
	}
	return total;
}

// How many chunks are the thin ones made for the view (for the checks).
int64_t PlanetTurf::far_count() const {
	int64_t total = 0;
	for (const auto &pair : chunks) {
		if (pair.second.level > 0) {
			total += 1;
		}
	}
	return total;
}
