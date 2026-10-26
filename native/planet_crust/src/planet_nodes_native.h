#pragma once

// The small nodes of the planet scene (were systems/planet/planet_crust_guard.gd, planet_undergrowth.gd, planet_shells.gd, planet_dust.gd,
// planet_motes.gd and planet_sway_tree.gd). They reach the PlanetWorld, the player and the tiles (still GDScript) through properties and calls;
// nodes of the scene are held by id.

#include "native_props.h"
#include "plant_sway_native.h"

#include <godot_cpp/classes/array_mesh.hpp>
#include <godot_cpp/classes/curve_texture.hpp>
#include <godot_cpp/classes/gpu_particles3d.hpp>
#include <godot_cpp/classes/gradient_texture1_d.hpp>
#include <godot_cpp/classes/image.hpp>
#include <godot_cpp/classes/image_texture.hpp>
#include <godot_cpp/classes/mesh_instance3d.hpp>
#include <godot_cpp/classes/node.hpp>
#include <godot_cpp/classes/node3d.hpp>
#include <godot_cpp/classes/particle_process_material.hpp>
#include <godot_cpp/classes/quad_mesh.hpp>
#include <godot_cpp/classes/shader.hpp>
#include <godot_cpp/classes/shader_material.hpp>
#include <godot_cpp/classes/standard_material3d.hpp>
#include <godot_cpp/variant/packed_byte_array.hpp>
#include <godot_cpp/variant/packed_float32_array.hpp>

namespace godot {

// Keeps the player and the camera out of the planet's insides: a player found well under the crust is put back on top, the camera is never let
// under it, and a black ball inside the crust makes what is seen through the ground dark.
class PlanetCrustGuard : public Node {
	GDCLASS(PlanetCrustGuard, Node)

	MeshInstance3D *core = nullptr; // a black ball inside the crust

protected:
	static void _bind_methods();

public:
	static constexpr double PLAYER_DEPTH = 3.0; // m under the crust before the player is lifted back
	static constexpr double CAMERA_CLEARANCE = 0.5; // m the camera keeps above the crust

	NP_OBJECT(planet)
	NP_OBJECT(target)
	NP_FIELD(int64_t, rescues, 0) // how many times the player was put back (a check reads it)

	void _ready() override;
	void _physics_process(double p_delta) override;
	void _process(double p_delta) override;
};

// Pushing through plants: they hold the walker back (the more and the thicker the undergrowth, the slower the walk).
class PlanetUndergrowth : public Node {
	GDCLASS(PlanetUndergrowth, Node)

	double drag = 0.0;
	double slow = 1.0;
	double since = 0.0;
	double drag_at(const Vector3 &p_world_position) const;

protected:
	static void _bind_methods();

public:
	static constexpr double MAX_SLOW = 0.55; // the most a thicket takes off the walking speed
	static constexpr double LOOK_EVERY = 0.1; // s between looks at the stems round the walker

	NP_OBJECT(planet)
	NP_OBJECT(player)

	void _ready() override;
	void _physics_process(double p_delta) override;
};

// The loose stones of the near ground as relief: round the walker the ground tiles get LAYERS extra copies of their mesh.
class PlanetShells : public Node {
	GDCLASS(PlanetShells, Node)

	Dictionary tiles; // tile -> Array of the MeshInstance3D layers
	Array materials;
	double since = 0.0;
	double gap(Node3D *p_tile, const Vector3 &p_here) const;
	void raise(Node3D *p_tile);
	void drop(Object *p_tile);

protected:
	static void _bind_methods();

public:
	static constexpr int LAYERS = 8;
	static constexpr double TOP = 0.06; // m: the tallest stone
	static constexpr double REACH = 7.0; // m
	static constexpr double LOOK_EVERY = 0.4; // s

	NP_OBJECT(planet)
	NP_OBJECT(player)

	void _ready() override;
	void _physics_process(double p_delta) override;
};

// Puffs of dust where something lands or steps on dry ground: a few soft round flakes that rise a little, grow and fade in a second or so.
class PlanetDust : public Node3D {
	GDCLASS(PlanetDust, Node3D)

	Ref<QuadMesh> mesh;
	Ref<GradientTexture1D> fade;
	Ref<CurveTexture> growth;

protected:
	static void _bind_methods();

public:
	static constexpr double LIFE = 1.4; // s

	void _ready() override;
	void puff(const Vector3 &p_at, const Vector3 &p_up, const Color &p_colour, double p_strength);
};

// Dust and pollen drifting in the air round the player: tiny warm specks that catch the sun.
class PlanetMotes : public GPUParticles3D {
	GDCLASS(PlanetMotes, GPUParticles3D)

	Ref<ParticleProcessMaterial> material;
	Ref<StandardMaterial3D> speck;

protected:
	static void _bind_methods();

public:
	static constexpr double LIFE = 14.0; // s

	NP_OBJECT(planet)

	void _ready() override;
	void _process(double p_delta) override;
};

// One tree whose branches bend and spring back: a tree close to the walker is taken out of its MultiMesh and drawn by one of these instead.
class PlanetSwayTree : public MeshInstance3D {
	GDCLASS(PlanetSwayTree, MeshInstance3D)

	Ref<PlantSwayNative> sway;
	PackedFloat32Array table;
	PackedFloat32Array state;
	Ref<Image> image;
	Ref<ImageTexture> texture;
	PackedByteArray feet;
	bool awake = false;
	double jitter_ = 0.0; // the most any branch turned in the last step (radians)

	static PackedFloat32Array zeros(int p_count);

protected:
	static void _bind_methods();

public:
	PlanetSwayTree();

	bool setup(const Ref<ArrayMesh> &p_tree_mesh, const Ref<ShaderMaterial> &p_material, const Color &p_tint);
	bool is_at_rest() const { return !awake; }
	void step(const PackedFloat32Array &p_body_local, double p_delta);
	double most_turned() const;
	double jitter() const { return jitter_; }
	double turn_sum() const;
};

} // namespace godot
