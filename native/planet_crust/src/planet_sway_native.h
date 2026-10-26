#pragma once

// PlanetSway (was systems/planet/planet_sway.gd): the trees and shrubs round the walker bend for real. The plants of a tile are drawn in
// batches (one MultiMesh for a kind), which cannot hold a pose for each tree; so every tree within ENTER metres of the walker is taken out of
// its batch (its instance is shrunk to nothing) and drawn by a PlanetSwayTree of its own, whose branches the native springs turn when the
// walker's body touches them and let go again after. Beyond LEAVE metres, and once it has come to rest, it goes back into the batch.

#include "native_props.h"
#include "planet_nodes_native.h"
#include "plant_sway_native.h"

#include <godot_cpp/classes/multi_mesh_instance3d.hpp>
#include <godot_cpp/classes/node.hpp>
#include <godot_cpp/variant/transform3d.hpp>

#include <vector>

namespace godot {

class PlanetSway : public Node {
	GDCLASS(PlanetSway, Node)

	struct Live {
		ObjectID tree, instance;
		int index = 0;
		Transform3D original;
		int klass = 0;
		int64_t key = 0;
	};
	Ref<PlantSwayNative> sway;
	std::vector<Live> live;
	double since = 0.0;
	Dictionary keys; // the live ones by batch and index, to ask quickly
	ObjectID turf; // the PlanetTurf (grass tufts), found among the planet's children
	int counts[3] = { 0, 0, 0 }; // how many of the live ones are of each class

	PackedFloat32Array body_in(PlanetSwayTree *p_tree, const Vector3 &p_feet) const;
	void take(const Vector3 &p_here);
	void take_kind(Node3D *p_holder, const Array &p_kind, const Vector3 &p_local);
	void go_live(Node3D *p_holder, MultiMeshInstance3D *p_instance, const PackedFloat32Array &p_buffer, int p_index, int p_klass);
	void give_back(const Vector3 &p_here);
	static int64_t key_of(const Object *p_instance, int p_index) { return (int64_t)p_instance->get_instance_id() * 65536 + p_index; }

protected:
	static void _bind_methods();

public:
	static constexpr double ENTER = 8.0; // m: closer than this a tree is taken out of its batch
	static constexpr double LEAVE = 11.0; // m: farther than this (and at rest) it goes back
	static constexpr double TOUCH = 6.0; // m: the body is given to the trees within this (the others only settle)
	// the same for grass, ferns, flowers and low shrubs: there are very many, and they are touched only close
	static constexpr double ENTER_SMALL = 2.4;
	static constexpr double LEAVE_SMALL = 3.4;
	static constexpr double TOUCH_SMALL = 1.8;
	static constexpr double LOOK_EVERY = 0.25; // s between looks for trees to take or give back
	static constexpr int MAX_LIVE = 24;
	static constexpr int MAX_SMALL = 120;
	// and the tufts of the turf of the ground: hundreds a few metres round, only the ones at the feet are pushed
	static constexpr double ENTER_TURF = 1.7;
	static constexpr double LEAVE_TURF = 2.6;
	static constexpr double TOUCH_TURF = 1.4;
	static constexpr int MAX_TURF = 90;
	static constexpr int BIG = 0; // the class of a batch: trees and tall shrubs,
	static constexpr int SMALL = 1; // grass, ferns, flowers and low shrubs,
	static constexpr int TURF = 2; // the tufts of the turf
	static constexpr double BODY_HEIGHT = 1.8; // m, the walker's body: an upright capsule from the feet
	static constexpr double BODY_RADIUS = 0.4;

	NP_OBJECT(planet)
	NP_OBJECT(player)

	PlanetSway();
	void _ready() override;
	void _physics_process(double p_delta) override;
	void _exit_tree() override;
	int64_t live_count() const { return (int64_t)live.size(); }
	double most_turned() const;
	double jitter() const;
	double pose_sum() const;
};

} // namespace godot
