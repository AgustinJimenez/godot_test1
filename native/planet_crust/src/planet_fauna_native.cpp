#include "planet_fauna_native.h"

#include "flora_meshes_native.h"
#include "planet_world_native.h"

#include <godot_cpp/classes/mesh_instance3d.hpp>
#include <godot_cpp/classes/resource_loader.hpp>
#include <godot_cpp/classes/script.hpp>
#include <godot_cpp/core/math.hpp>

#include <algorithm>
#include <cmath>

using namespace godot;

static const double TAU_D = 6.283185307179586476925286766559;
static const double PI_D = 3.14159265358979323846;

// MeshBuilder (GDScript, the world's mesh maker): made through its script
static Ref<RefCounted> new_builder() {
	static Ref<Script> script;
	if (script.is_null()) {
		script = ResourceLoader::get_singleton()->load("res://systems/world_gen/mesh_builder.gd");
	}
	return script->call("new");
}

static Color rgb(double p_r, double p_g, double p_b) {
	return Color((float)p_r, (float)p_g, (float)p_b, 0.0f);
}

static Ref<RandomNumberGenerator> seeded(int64_t p_seed) {
	Ref<RandomNumberGenerator> r;
	r.instantiate();
	r->set_seed(p_seed);
	return r;
}

void PlanetFauna::_bind_methods() {
	NP_BIND_OBJECT(PlanetFauna, planet)
	ClassDB::bind_method(D_METHOD("update", "target", "daylight", "delta"), &PlanetFauna::update);
}

Ref<ArrayMesh> PlanetFauna::make_deer() const {
	Ref<RefCounted> builder = new_builder();
	Ref<RandomNumberGenerator> r = seeded(7);
	const Color fur = rgb(0.55, 0.38, 0.22);
	const Color belly = rgb(0.82, 0.72, 0.55);
	builder->call("add_blob", Vector3(0.0, 1.1, 0.0), Vector3(0.75, 0.38, 0.3), fur.darkened(0.15f), fur, r, 0.06);
	builder->call("add_blob", Vector3(0.0, 0.95, 0.0), Vector3(0.6, 0.2, 0.26), belly, belly, r, 0.04);
	// neck and head lean forward (+X), antlers on top
	builder->set("xf", Transform3D(Basis(Vector3(0, 0, 1), -0.9), Vector3(0.6, 1.2, 0.0)));
	builder->call("add_frustum", Vector3(), 0.6, 0.17, 0.11, 5, fur.darkened(0.1f), fur);
	builder->set("xf", Transform3D());
	builder->call("add_blob", Vector3(1.08, 1.68, 0.0), Vector3(0.22, 0.14, 0.12), fur, fur.lightened(0.1f), r, 0.05);
	builder->call("add_blob", Vector3(-0.72, 1.18, 0.0), Vector3(0.1, 0.1, 0.1), belly, belly, r, 0.05);
	for (double side : { -1.0, 1.0 }) {
		builder->set("xf", Transform3D(Basis(Vector3(1, 0, 0), side * 0.45) * Basis(Vector3(0, 0, 1), 0.2), Vector3(1.0, 1.78, side * 0.07)));
		builder->call("add_frustum", Vector3(), 0.5, 0.025, 0.01, 4, rgb(0.8, 0.75, 0.6), rgb(0.9, 0.85, 0.7));
	}
	builder->set("xf", Transform3D());
	return builder->call("commit");
}

Ref<ArrayMesh> PlanetFauna::make_leg() const {
	Ref<RefCounted> builder = new_builder();
	builder->call("add_frustum", Vector3(0.0, -0.95, 0.0), 0.95, 0.04, 0.07, 5, rgb(0.2, 0.15, 0.1), rgb(0.45, 0.31, 0.18));
	return builder->call("commit");
}

Ref<ArrayMesh> PlanetFauna::make_rabbit() const {
	Ref<RefCounted> builder = new_builder();
	Ref<RandomNumberGenerator> r = seeded(11);
	const Color fur = rgb(0.62, 0.55, 0.45);
	builder->call("add_blob", Vector3(0.0, 0.17, 0.0), Vector3(0.2, 0.15, 0.13), fur.darkened(0.1f), fur, r, 0.05);
	builder->call("add_blob", Vector3(0.2, 0.26, 0.0), Vector3(0.1, 0.09, 0.08), fur, fur.lightened(0.1f), r, 0.05);
	for (double side : { -1.0, 1.0 }) {
		builder->set("xf", Transform3D(Basis(Vector3(1, 0, 0), side * 0.15) * Basis(Vector3(0, 0, 1), -0.2), Vector3(0.18, 0.31, side * 0.035)));
		builder->call("add_frustum", Vector3(), 0.2, 0.025, 0.012, 4, fur, fur.lightened(0.2f));
	}
	builder->set("xf", Transform3D());
	builder->call("add_blob", Vector3(-0.22, 0.2, 0.0), Vector3(0.05, 0.05, 0.05), Color(1, 1, 1), Color(1, 1, 1), r, 0.0);
	return builder->call("commit");
}

void PlanetFauna::_ready() {
	rng.instantiate();
	rng->set_seed(5150);
	deer_mesh = make_deer();
	leg_mesh = make_leg();
	rabbit_mesh = make_rabbit();
	for (int index = 0; index < DEER + RABBITS; index++) {
		Animal animal = make_animal(index < DEER);
		add_child(animal.node);
		animal.node->set_visible(false);
		animals.push_back(animal);
	}
}

PlanetFauna::Animal PlanetFauna::make_animal(bool p_deer) {
	Animal animal;
	animal.is_deer = p_deer;
	animal.node = memnew(Node3D);
	animal.body = memnew(Node3D);
	animal.node->add_child(animal.body);
	MeshInstance3D *instance = memnew(MeshInstance3D);
	instance->set_mesh(p_deer ? deer_mesh : rabbit_mesh);
	instance->set_material_override(FloraMeshes::material());
	animal.body->add_child(instance);
	if (p_deer) {
		static const double corners[4][2] = { { 0.55, 0.16 }, { 0.55, -0.16 }, { -0.5, 0.16 }, { -0.5, -0.16 } };
		for (const auto &corner : corners) {
			Node3D *pivot = memnew(Node3D);
			pivot->set_position(Vector3(corner[0], 0.95, corner[1]));
			MeshInstance3D *leg = memnew(MeshInstance3D);
			leg->set_mesh(leg_mesh);
			leg->set_material_override(FloraMeshes::material());
			pivot->add_child(leg);
			animal.body->add_child(pivot);
			animal.legs.push_back(pivot);
		}
	}
	animal.heading = rng->randf() * TAU_D;
	animal.timer = rng->randf_range(1.0, 5.0);
	return animal;
}

void PlanetFauna::update(const Vector3 &p_target, double p_daylight, double p_delta) {
	PlanetWorld *world = Object::cast_to<PlanetWorld>(get_planet());
	if (world == nullptr || world->get_noise().is_null()) {
		return;
	}
	for (Animal &animal : animals) {
		Vector3 at = animal.node->get_global_position();
		Vector2 away((real_t)(at.x - p_target.x), (real_t)(at.z - p_target.z));
		if (!animal.node->is_visible() || away.length() > FAR) {
			place(animal, p_target);
			continue;
		}
		animal.node->set_visible(p_daylight > 0.25);
		think(animal, away, p_delta);
		move(animal, p_delta);
	}
}

void PlanetFauna::place(Animal &p_animal, const Vector3 &p_target) {
	PlanetWorld *world = Object::cast_to<PlanetWorld>(get_planet());
	for (int attempt = 0; attempt < 12; attempt++) {
		double angle = rng->randf() * TAU_D;
		double distance = rng->randf_range(NEAR, FAR * 0.9);
		double x = p_target.x + std::cos(angle) * distance;
		double z = p_target.z + std::sin(angle) * distance;
		Dictionary ground = world->ground_at(x, z, p_target.y);
		if ((bool)ground["wet"]) {
			continue;
		}
		int biome = ground["biome"];
		if (biome != 1 && biome != 2) { // MEADOW, FOREST (TerrainNoise.Biome)
			continue;
		}
		p_animal.node->set_global_position(Vector3(x, (double)ground["y"], z));
		p_animal.state = IDLE;
		p_animal.timer = rng->randf_range(1.0, 6.0);
		p_animal.node->set_visible(true);
		return;
	}
	p_animal.node->set_visible(false); // nowhere suitable this time; try again next frame
}

void PlanetFauna::think(Animal &p_animal, const Vector2 &p_away, double p_delta) {
	double scared = p_animal.is_deer ? FLEE_DEER : FLEE_RABBIT;
	if (p_away.length() < scared) {
		p_animal.state = FLEE;
		p_animal.heading = std::atan2((double)p_away.y, (double)p_away.x);
		p_animal.timer = 1.2;
		return;
	}
	p_animal.timer -= p_delta;
	if (p_animal.timer > 0.0) {
		return;
	}
	if (p_animal.state == IDLE) {
		p_animal.state = WALK;
		p_animal.heading += rng->randf_range(-1.5, 1.5);
		p_animal.timer = rng->randf_range(2.0, 6.0);
	} else {
		p_animal.state = IDLE;
		p_animal.timer = rng->randf_range(2.0, 7.0);
	}
}

void PlanetFauna::move(Animal &p_animal, double p_delta) {
	PlanetWorld *world = Object::cast_to<PlanetWorld>(get_planet());
	double speed = 0.0;
	if (p_animal.state == WALK) {
		speed = p_animal.is_deer ? 1.3 : 0.7;
	} else if (p_animal.state == FLEE) {
		speed = p_animal.is_deer ? 7.0 : 5.0;
	}
	const double step_x = std::cos(p_animal.heading) * speed * p_delta;
	const double step_z = std::sin(p_animal.heading) * speed * p_delta;
	Vector3 here = p_animal.node->get_global_position();
	Dictionary ground = world->ground_at(here.x + step_x, here.z + step_z, here.y);
	Vector3 next(here.x + step_x, (double)ground["y"], here.z + step_z);
	// water ahead or a cliff: turn instead of going on
	bool jump = std::abs((double)next.y - (double)here.y) > 0.9 * std::max(speed * p_delta, 0.01) + 0.15;
	if ((bool)ground["wet"] || jump) {
		p_animal.heading += PI_D * 0.6;
		next = here;
	}
	p_animal.node->set_global_position(next);
	p_animal.node->set_rotation(Vector3(0.0, -p_animal.heading + PI_D * 0.5, 0.0));
	p_animal.phase += speed * p_delta * (p_animal.is_deer ? 3.2 : 4.0);
	if (p_animal.is_deer) {
		double swing = std::min(speed, 4.0) * 0.14;
		for (size_t index = 0; index < p_animal.legs.size(); index++) {
			p_animal.legs[index]->set_rotation(Vector3(std::sin(p_animal.phase + (index % 3 != 0 ? PI_D : 0.0)) * swing, 0.0, 0.0));
		}
		p_animal.body->set_position(Vector3(0.0, std::abs(std::sin(p_animal.phase)) * 0.04 * std::min(speed, 3.0), 0.0));
	} else {
		double hop = speed > 0.1 ? std::max(std::sin(p_animal.phase), 0.0) : 0.0;
		p_animal.body->set_position(Vector3(0.0, hop * 0.28, 0.0));
		p_animal.body->set_rotation(Vector3(-hop * 0.3, 0.0, 0.0));
	}
}
