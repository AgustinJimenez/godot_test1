#pragma once

// HairSim: a real hair simulation for the head hair (shaders/human_hair.gdshader) built by HumanHair.
//
// The hair mesh carries its guide strands (HumanHair puts them in the mesh's metadata: "hair_guides", "hair_guide_count", "hair_guide_steps", "hair_colliders") and every
// hair vertex knows which guide it follows (CUSTOM0). This node simulates the guides only (a few thousand chains of a few points) in world space, so the head's movement
// and turning, gravity, and collisions with the head, neck and shoulders all act on them; the result goes into a small texture (one row per guide, one pixel per point:
// how far the point is from its rest place, in the mesh's own space) and the hair shader moves every hair by its guide. So tens of thousands of hairs follow a few
// thousand simulated points, at no per-hair cost on the CPU.
//
// Each guide is a chain of particles: the root is pinned to the scalp (it follows the mesh's transform), the others move by Verlet integration (gravity, damping), keep
// their distance to the next one (so the hair does not stretch), are pulled softly back toward their rest place in the head's frame (the style: strong near the root,
// weak at the tip) and are pushed out of the colliders (capsules: head, neck, shoulders). Fixed steps of 1/60 s whatever the frame rate.
// Set `hair` (the MeshInstance3D of the hair) and `material` (its ShaderMaterial: it gets `sim_tex` and `use_sim`).

#include <godot_cpp/classes/geometry_instance3d.hpp>
#include <godot_cpp/classes/image_texture.hpp>
#include <godot_cpp/classes/node.hpp>
#include <godot_cpp/classes/node3d.hpp>
#include <godot_cpp/classes/shader_material.hpp>
#include <godot_cpp/variant/packed_byte_array.hpp>
#include <godot_cpp/variant/vector3.hpp>

#include <unordered_map>
#include <vector>

namespace godot {

class HairSim : public Node {
	GDCLASS(HairSim, Node)

	ObjectID hair_id;
	ObjectID material_id;
	double gravity = 9.8; // m/s2
	double damping = 0.985; // the share of the velocity kept each step
	double root_stiffness = 0.55; // the pull back to the style at the root (per step)
	double tip_stiffness = 0.02; // ... and at the tip: low, so the ends swing free
	int iterations = 4; // length constraint passes per step
	double collision_margin = 0.004; // metres kept between a hair point and a collider
	double max_displacement = 0.35; // metres: a safety limit on how far a point may be from its rest place

	int guide_count = 0;
	int steps = 0;
	std::vector<Vector3> rest; // local rest points of all guides (steps each)
	std::vector<double> link; // rest length of each link (steps - 1 each)
	std::vector<Vector3> pos; // world
	std::vector<Vector3> prev; // world
	std::vector<float> capsules; // local: ax ay az bx by bz r
	// the body surface (local): points and normals, in a hash grid (cell = surface_cell), so hair is pushed out of the chest, breasts and arms
	std::vector<Vector3> surface_p;
	std::vector<Vector3> surface_n;
	std::unordered_map<int64_t, std::vector<int>> surface_grid;
	double surface_cell = 0.04;
	bool surface_collision = true;
	double surface_margin = 0.009; // metres kept between a hair point and the skin (more than the 4 mm cloth shell on top of it)
	void build_surface_grid();
	void collide_surface(Vector3 &p_world, const Transform3D &p_xf, const Transform3D &p_inv) const;
	Transform3D last_transform;
	bool primed = false;
	double accumulator = 0.0;
	Ref<ImageTexture> texture;
	PackedByteArray bytes;
	bool bound = false;

	void bind_mesh();
	void step(double p_dt, const Transform3D &p_xf);
	void upload(const Transform3D &p_xf);

protected:
	static void _bind_methods();

public:
	void set_hair(Object *p_hair);
	Object *get_hair() const;
	void set_material(Object *p_material);
	Object *get_material() const;
	void set_gravity(double p_value) { gravity = p_value; }
	double get_gravity() const { return gravity; }
	void set_damping(double p_value) { damping = p_value; }
	double get_damping() const { return damping; }
	void set_root_stiffness(double p_value) { root_stiffness = p_value; }
	double get_root_stiffness() const { return root_stiffness; }
	void set_tip_stiffness(double p_value) { tip_stiffness = p_value; }
	double get_tip_stiffness() const { return tip_stiffness; }
	void set_iterations(int p_value) { iterations = p_value; }
	int get_iterations() const { return iterations; }
	void set_collisions(const PackedFloat32Array &p_capsules); // replace the colliders (local, 7 floats each)
	void set_surface_collision(bool p_value) { surface_collision = p_value; }
	bool get_surface_collision() const { return surface_collision; }
	int get_penetration_count(); // hair points inside the body surface (for tests)
	int get_guide_count() const { return guide_count; }
	// Re-reads the guides from the hair mesh (call after the hair mesh was replaced).
	void rebind() { bind_mesh(); }
	// A push on every point (m/s), for a shake or a hit.
	void kick(const Vector3 &p_impulse);

	void _process(double p_delta) override;
};

} // namespace godot
