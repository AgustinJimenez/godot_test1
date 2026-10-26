#include "planet_sway_native.h"

#include "planet_nodes_native.h"

#include <godot_cpp/classes/array_mesh.hpp>
#include <godot_cpp/classes/multi_mesh.hpp>
#include <godot_cpp/classes/os.hpp>
#include <godot_cpp/classes/shader_material.hpp>
#include <godot_cpp/variant/basis.hpp>
#include <godot_cpp/variant/utility_functions.hpp>

#include <algorithm>
#include <cmath>

using namespace godot;

static const double ENTERS[3] = { PlanetSway::ENTER, PlanetSway::ENTER_SMALL, PlanetSway::ENTER_TURF };
static const double LEAVES[3] = { PlanetSway::LEAVE, PlanetSway::LEAVE_SMALL, PlanetSway::LEAVE_TURF };
static const double TOUCHES[3] = { PlanetSway::TOUCH, PlanetSway::TOUCH_SMALL, PlanetSway::TOUCH_TURF };
static const int MAXES[3] = { PlanetSway::MAX_LIVE, PlanetSway::MAX_SMALL, PlanetSway::MAX_TURF };

PlanetSway::PlanetSway() {
	sway.instantiate();
}

void PlanetSway::_bind_methods() {
	BIND_CONSTANT(BIG);
	BIND_CONSTANT(SMALL);
	BIND_CONSTANT(TURF);
	NP_BIND_OBJECT(PlanetSway, planet)
	NP_BIND_OBJECT(PlanetSway, player)
	ClassDB::bind_method(D_METHOD("live_count"), &PlanetSway::live_count);
	ClassDB::bind_method(D_METHOD("most_turned"), &PlanetSway::most_turned);
	ClassDB::bind_method(D_METHOD("jitter"), &PlanetSway::jitter);
	ClassDB::bind_method(D_METHOD("pose_sum"), &PlanetSway::pose_sum);
}

void PlanetSway::_ready() {
	set_physics_process_priority(101);
}

void PlanetSway::_physics_process(double p_delta) {
	Node3D *player_node = Object::cast_to<Node3D>(get_player());
	Object *planet_object = get_planet();
	if (player_node == nullptr || planet_object == nullptr) {
		return;
	}
	Vector3 here = player_node->get_global_position();
	since += p_delta;
	if (since >= LOOK_EVERY) {
		since = 0.0;
		give_back(here);
		take(here);
		if (OS::get_singleton()->has_environment("PLANET_TIMING")) {
			int64_t sets = 0;
			Object *surface = planet_object->get("surface");
			Dictionary all = surface->get("tiles");
			Array values = all.values();
			for (int i = 0; i < values.size(); i++) {
				Object *tile = values[i];
				Node *holder = Object::cast_to<Node>((Object *)tile->get("plant_holder"));
				if (holder != nullptr && holder->has_meta("sway_sets")) {
					sets += Array(holder->get_meta("sway_sets")).size();
				}
			}
			UtilityFunctions::print(vformat("PLANET_TIMING sway live=%d kinds=%d", (int64_t)live.size(), sets));
		}
	}
	for (const Live &entry : live) {
		PlanetSwayTree *tree = Object::cast_to<PlanetSwayTree>(ObjectDB::get_instance(entry.tree)); // (a tree of a tile that has gone is a freed object)
		if (tree == nullptr || !tree->is_inside_tree()) {
			continue; // (give_back lets it go)
		}
		PackedFloat32Array body;
		if (tree->get_global_position().distance_to(here) < TOUCHES[entry.klass]) {
			body = body_in(tree, here);
		}
		tree->step(body, p_delta);
	}
}

// The walker's body as a capsule in `tree`'s own space: from the feet up, its radius made smaller or larger by the tree's scale.
PackedFloat32Array PlanetSway::body_in(PlanetSwayTree *p_tree, const Vector3 &p_feet) const {
	Node3D *player_node = Object::cast_to<Node3D>(get_player());
	Transform3D inverse = p_tree->get_global_transform().affine_inverse();
	Vector3 a = inverse.xform(p_feet);
	Vector3 b = inverse.xform(p_feet + player_node->get_global_basis().get_column(1) * BODY_HEIGHT);
	double scale = std::max((double)p_tree->get_global_basis().get_scale().x, 0.01);
	PackedFloat32Array body;
	body.append(a.x);
	body.append(a.y);
	body.append(a.z);
	body.append(b.x);
	body.append(b.y);
	body.append(b.z);
	body.append(BODY_RADIUS / scale);
	return body;
}

// Trees of the tiles round the walker that are within ENTER metres go live.
void PlanetSway::take(const Vector3 &p_here) {
	Object *planet_object = get_planet();
	Object *surface = planet_object->get("surface");
	Dictionary all = surface->get("tiles");
	Array values = all.values();
	for (int i = 0; i < values.size(); i++) {
		Object *tile = values[i];
		Node3D *holder = Object::cast_to<Node3D>((Object *)tile->get("plant_holder"));
		if (holder == nullptr || !holder->has_meta("sway_sets")) {
			continue;
		}
		Vector3 local = holder->to_local(p_here);
		double half = (double)tile->get("size") * 0.5 + ENTER;
		if (std::abs(local.x) > half || std::abs(local.z) > half) {
			continue; // (the tile's own space is centred on it)
		}
		Array kinds = holder->get_meta("sway_sets");
		for (int k = 0; k < kinds.size(); k++) {
			take_kind(holder, kinds[k], local);
		}
	}
	// the tufts of turf round the walker too (PlanetTurf keeps its chunks)
	Object *turf_object = ObjectDB::get_instance(turf);
	if (turf_object == nullptr) {
		Node *planet_node = Object::cast_to<Node>(planet_object);
		TypedArray<Node> children = planet_node->get_children();
		for (int i = 0; i < children.size(); i++) {
			Object *child = children[i];
			if (child->has_method("chunk_sets")) {
				turf = child->get_instance_id();
			}
		}
		turf_object = ObjectDB::get_instance(turf);
	}
	if (turf_object != nullptr) {
		Array sets = turf_object->call("chunk_sets");
		for (int i = 0; i < sets.size(); i++) {
			Array entry = sets[i];
			Node3D *holder = Object::cast_to<Node3D>((Object *)entry[0]);
			take_kind(holder, entry[1], holder->to_local(p_here));
		}
	}
}

// The instances of one batch `kind` ([MultiMeshInstance3D, buffer, class]) of `holder` near `local` go live.
void PlanetSway::take_kind(Node3D *p_holder, const Array &p_kind, const Vector3 &p_local) {
	MultiMeshInstance3D *instance = Object::cast_to<MultiMeshInstance3D>((Object *)p_kind[0]);
	if (instance == nullptr || instance->get_multimesh().is_null()) {
		return;
	}
	int klass = p_kind[2]; // (the plants' batches say only true for the small ones)
	PackedFloat32Array buffer = p_kind[1];
	PackedInt32Array near_ones = sway->within(buffer, p_local.x, p_local.z, ENTERS[klass]);
	for (int i = 0; i < near_ones.size(); i++) {
		if (counts[klass] >= MAXES[klass]) {
			break;
		}
		int index = near_ones[i];
		if (!keys.has(key_of(instance, index))) {
			go_live(p_holder, instance, buffer, index, klass);
		}
	}
}

void PlanetSway::go_live(Node3D *p_holder, MultiMeshInstance3D *p_instance, const PackedFloat32Array &p_buffer, int p_index, int p_klass) {
	Ref<MultiMesh> multi = p_instance->get_multimesh();
	int at = p_index * 16; // (the tile's own buffer: the renderer need not keep the instances)
	Transform3D original(Basis(Vector3(p_buffer[at], p_buffer[at + 4], p_buffer[at + 8]), Vector3(p_buffer[at + 1], p_buffer[at + 5], p_buffer[at + 9]),
								 Vector3(p_buffer[at + 2], p_buffer[at + 6], p_buffer[at + 10])),
			Vector3(p_buffer[at + 3], p_buffer[at + 7], p_buffer[at + 11]));
	PlanetSwayTree *tree = memnew(PlanetSwayTree);
	Ref<ArrayMesh> mesh = multi->get_mesh();
	Ref<ShaderMaterial> material = p_instance->get_material_override();
	if (!tree->setup(mesh, material, Color(p_buffer[at + 12], p_buffer[at + 13], p_buffer[at + 14], p_buffer[at + 15]))) {
		memdelete(tree);
		return;
	}
	tree->set_transform(original);
	tree->set_cast_shadows_setting(p_instance->get_cast_shadows_setting());
	p_holder->add_child(tree);
	multi->set_instance_transform(p_index, Transform3D(Basis::from_scale(Vector3()), original.origin));
	Live entry;
	entry.tree = tree->get_instance_id();
	entry.instance = p_instance->get_instance_id();
	entry.index = p_index;
	entry.original = original;
	entry.klass = p_klass;
	entry.key = key_of(p_instance, p_index);
	live.push_back(entry);
	counts[p_klass] += 1;
	keys[entry.key] = true;
}

// Trees the walker has left, once their branches have settled, go back into their batch.
void PlanetSway::give_back(const Vector3 &p_here) {
	for (int at = (int)live.size() - 1; at >= 0; at--) {
		Live entry = live[at];
		Object *tree_object = ObjectDB::get_instance(entry.tree);
		MultiMeshInstance3D *instance = Object::cast_to<MultiMeshInstance3D>(ObjectDB::get_instance(entry.instance));
		PlanetSwayTree *tree = Object::cast_to<PlanetSwayTree>(tree_object);
		bool gone = instance == nullptr || tree == nullptr || !tree->is_inside_tree();
		if (gone || (tree->get_global_position().distance_to(p_here) > LEAVES[entry.klass] && tree->is_at_rest())) {
			if (!gone) {
				instance->get_multimesh()->set_instance_transform(entry.index, entry.original);
			}
			if (tree_object != nullptr) {
				Object::cast_to<Node>(tree_object)->queue_free();
			}
			counts[entry.klass] -= 1;
			keys.erase(entry.key);
			live.erase(live.begin() + at);
		}
	}
}

// The most any branch of the live trees is turned (radians): for the checks.
double PlanetSway::most_turned() const {
	double worst = 0.0;
	for (const Live &entry : live) {
		PlanetSwayTree *tree = Object::cast_to<PlanetSwayTree>(ObjectDB::get_instance(entry.tree));
		if (tree != nullptr) {
			worst = std::max(worst, tree->most_turned());
		}
	}
	return worst;
}

// The most any live branch turned in the last step (radians).
double PlanetSway::jitter() const {
	double worst = 0.0;
	for (const Live &entry : live) {
		PlanetSwayTree *tree = Object::cast_to<PlanetSwayTree>(ObjectDB::get_instance(entry.tree));
		if (tree != nullptr) {
			worst = std::max(worst, tree->jitter());
		}
	}
	return worst;
}

// The turns of all the live branches added up (radians): it stops changing when everything is at rest.
double PlanetSway::pose_sum() const {
	double total = 0.0;
	for (const Live &entry : live) {
		PlanetSwayTree *tree = Object::cast_to<PlanetSwayTree>(ObjectDB::get_instance(entry.tree));
		if (tree != nullptr) {
			total += tree->turn_sum();
		}
	}
	return total;
}

void PlanetSway::_exit_tree() {
	for (const Live &entry : live) {
		MultiMeshInstance3D *instance = Object::cast_to<MultiMeshInstance3D>(ObjectDB::get_instance(entry.instance));
		if (instance != nullptr && ObjectDB::get_instance(entry.tree) != nullptr) {
			instance->get_multimesh()->set_instance_transform(entry.index, entry.original);
		}
	}
	live.clear();
}
