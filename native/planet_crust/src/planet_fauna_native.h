#pragma once

// The flat world's deer and rabbits (was systems/planet/planet_fauna.gd on top of WorldFauna: same animals, same wandering, fleeing and sleeping) on a
// planet: they look the ground up through the planet (PlanetWorld::ground_at) instead of a flat height function, so they stand on its meadows and
// forests and keep out of the sea, rivers and lakes. A small pool of animals is kept round the target: each one idles, walks or flees (deer at 25 m,
// rabbits at 10 m), follows the ground, and is moved to a fresh spot when the player has left it far behind. They sleep (are hidden) at night.

#include "native_props.h"

#include <godot_cpp/classes/array_mesh.hpp>
#include <godot_cpp/classes/node3d.hpp>
#include <godot_cpp/classes/random_number_generator.hpp>

#include <vector>

namespace godot {

class PlanetFauna : public Node3D {
	GDCLASS(PlanetFauna, Node3D)

	enum State { IDLE, WALK, FLEE };
	struct Animal {
		Node3D *node = nullptr;
		Node3D *body = nullptr;
		std::vector<Node3D *> legs;
		bool is_deer = true;
		State state = IDLE;
		double timer = 0.0;
		double heading = 0.0;
		double phase = 0.0;
	};
	std::vector<Animal> animals;
	Ref<RandomNumberGenerator> rng;
	Ref<ArrayMesh> deer_mesh, leg_mesh, rabbit_mesh;

	Ref<ArrayMesh> make_deer() const;
	Ref<ArrayMesh> make_leg() const;
	Ref<ArrayMesh> make_rabbit() const;
	Animal make_animal(bool p_deer);
	void place(Animal &p_animal, const Vector3 &p_target);
	void think(Animal &p_animal, const Vector2 &p_away, double p_delta);
	void move(Animal &p_animal, double p_delta);

protected:
	static void _bind_methods();

public:
	static constexpr int DEER = 9;
	static constexpr int RABBITS = 14;
	static constexpr double NEAR = 55.0; // m: closest an animal is placed to the target
	static constexpr double FAR = 150.0; // m: farther than this it is moved
	static constexpr double FLEE_DEER = 25.0;
	static constexpr double FLEE_RABBIT = 11.0;

	NP_OBJECT(planet) // the PlanetWorld

	void _ready() override;
	void update(const Vector3 &p_target, double p_daylight, double p_delta);
};

} // namespace godot
