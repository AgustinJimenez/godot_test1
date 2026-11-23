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
#include <godot_cpp/core/math.hpp>
#include <godot_cpp/classes/image_texture.hpp>
#include <godot_cpp/classes/node.hpp>
#include <godot_cpp/classes/node3d.hpp>
#include <godot_cpp/classes/shader_material.hpp>
#include <godot_cpp/variant/packed_byte_array.hpp>
#include <godot_cpp/variant/packed_vector3_array.hpp>
#include <godot_cpp/variant/quaternion.hpp>
#include <godot_cpp/variant/vector3.hpp>

#include <algorithm>
#include <vector>

namespace godot {

class HairSim : public Node {
	GDCLASS(HairSim, Node)

	ObjectID hair_id;
	ObjectID material_id;
	double gravity = 9.8; // m/s2
	double damping = 0.985; // the share of the velocity kept each step
	Vector3 wind; // wind as an acceleration (m/s2, world space): pushes every point like gravity does, with gusts; the body collision keeps the hair out of the head
	double wind_time = 0.0;
	double weight = 1.0; // how heavy the hair is (1 = normal): heavier sags more, is harder to pull back to its style and loses less speed to the air, so it swings longer
	double bend_stiffness = 0.0; // 0..1: how firmly each point keeps its rest distance from the point two places along the strand, so a hair resists bending sharply (0 = a loose rope)
	double max_swing = 1.0; // how far a point may leave its place in the style, as a share of the strand length up to it (1 = hardly limited, 0.3 = a short swing)
	double air_drag = 0.0; // 0..: drag of the air on the movement across a strand (quadratic in the speed): a swing slows down like real hair, tips more than roots
	double strand_damping = 0.0; // 0..1: the share of the difference in velocity between neighbouring points removed each step (stops the strand's own wobble, not the swing of the whole)
	double local_stiffness = 0.0; // 0..1: how firmly each segment keeps its angle to the previous one (TressFX "local shape"): the style's bends and curls hold along the strand
	double calm_damping = 0.8; // the share of the velocity kept per step by a point that moves slowly (small movements die out fast, like friction between hairs); 1 = no extra friction
	double calm_speed = 0.003; // metres per step: above this speed (18 cm/s) the normal damping applies, below it the damping blends toward calm_damping
	double root_stiffness = 0.55; // the pull back to the style at the root (per step)
	double tip_stiffness = 0.02; // ... and at the tip: low, so the ends swing free
	int iterations = 4; // length constraint passes per step
	int settle_steps = 30; // steps run at once when the hair starts, so it appears already hanging (no sag in view)
	double collision_margin = 0.004; // metres kept between a hair point and a collider
	double max_displacement = 0.35; // metres: a safety limit on how far a point may be from its rest place

	int guide_count = 0;
	int steps = 0;
	std::vector<Vector3> rest; // local rest points of all guides (steps each)
	std::vector<double> link; // rest length of each link (steps - 1 each)
	std::vector<double> link2; // rest distance between a point and the one two places before it (steps each; the first two are unused)
	std::vector<Vector3> pos; // world
	std::vector<int> calm_steps; // per guide: how many steps in a row it hardly moved (after a while with the head still it sleeps: a strand that creeps a fraction of a millimetre every step is seen as shaking)
	std::vector<Vector3> prev; // world
	std::vector<Vector3> snap; // world: the points before the last step (the picture is drawn between this and `pos`, so it does not jump with the step rate)
	double drawn_alpha = 1.0; // how far between the last two steps the picture is
	Transform3D step_prev_xf, step_last_xf; // the head's transform at the step before the last, and at the last one
	std::vector<Vector3> carry; // offsets from the rest places inherited from the previous hair (head frame), used when the simulation primes
	std::vector<float> capsules; // local: ax ay az bx by bz r
	// the body surface (local): points and normals, in a hash grid (cell = surface_cell), so hair is pushed out of the chest, breasts and arms
	std::vector<Vector3> surface_p;
	std::vector<Vector3> surface_n;
	// flat grid (counting sort): cell (x,y,z) holds the vertices grid_items[grid_start[c] .. grid_start[c+1]); cells outside the box are empty
	std::vector<int> grid_start;
	std::vector<int> grid_items;
	int grid_min[3] = { 0, 0, 0 };
	int grid_dim[3] = { 0, 0, 0 };
	int nearest_surface(const Vector3 &p_local, double &r_d2) const;
	// per-step data shared by the worker threads (a step is split in chunks of guides)
	struct StepData {
		Transform3D xf, inverse;
		Vector3 g_dt2;
		Vector3 wind_dt2; // wind x dt^2 (already divided by the weight)
		double time = 0.0;
		double damping = 0.985; // after the weight
		double stiffness_scale = 1.0; // 1 / weight
		struct Capsule {
			Vector3 a, b;
			double r;
		};
		std::vector<Capsule> world;
	} sd;
	static constexpr int kMaxSteps = 16; // points per guide the fixed buffers allow
	static constexpr int kChunks = 32; // pieces a step is split in for the worker threads
	void step_chunk(int p_chunk);
	void step_guide(int p_guide);
	double surface_cell = 0.04;
	bool surface_collision = true;
	double surface_margin = 0.0035; // metres kept between a hair point and the skin (a little more than the 4 mm cloth shell on top of it)
	bool capsule_collision = false; // the rough capsules (head, neck, shoulders) from the mesh: off by default, they stand out from the real body (an invisible shoulder)
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
	void upload(double p_alpha);

protected:
	static void _bind_methods();

public:
	void set_hair(Object *p_hair);
	Object *get_hair() const;
	void set_material(Object *p_material);
	Object *get_material() const;
	void set_wind(const Vector3 &p_value) { std::fill(calm_steps.begin(), calm_steps.end(), 0); wind = p_value; }
	Vector3 get_wind() const { return wind; }
	void set_weight(double p_value) { std::fill(calm_steps.begin(), calm_steps.end(), 0); weight = std::max(0.1, p_value); }
	double get_weight() const { return weight; }
	void set_bend_stiffness(double p_value) { std::fill(calm_steps.begin(), calm_steps.end(), 0); bend_stiffness = Math::clamp(p_value, 0.0, 1.0); }
	double get_bend_stiffness() const { return bend_stiffness; }
	void set_local_stiffness(double p_value) { std::fill(calm_steps.begin(), calm_steps.end(), 0); local_stiffness = Math::clamp(p_value, 0.0, 1.0); }
	double get_local_stiffness() const { return local_stiffness; }
	void set_max_swing(double p_value) { max_swing = Math::clamp(p_value, 0.02, 4.0); std::fill(calm_steps.begin(), calm_steps.end(), 0); }
	double get_max_swing() const { return max_swing; }
	void set_air_drag(double p_value) { air_drag = Math::clamp(p_value, 0.0, 1.0); std::fill(calm_steps.begin(), calm_steps.end(), 0); }
	double get_air_drag() const { return air_drag; }
	void set_strand_damping(double p_value) { strand_damping = Math::clamp(p_value, 0.0, 1.0); std::fill(calm_steps.begin(), calm_steps.end(), 0); }
	double get_strand_damping() const { return strand_damping; }
	void set_calm_damping(double p_value) { std::fill(calm_steps.begin(), calm_steps.end(), 0); calm_damping = p_value; }
	double get_calm_damping() const { return calm_damping; }
	void set_calm_speed(double p_value) { std::fill(calm_steps.begin(), calm_steps.end(), 0); calm_speed = std::max(1e-5, p_value); }
	double get_calm_speed() const { return calm_speed; }
	void set_gravity(double p_value) { std::fill(calm_steps.begin(), calm_steps.end(), 0); gravity = p_value; }
	double get_gravity() const { return gravity; }
	void set_damping(double p_value) { std::fill(calm_steps.begin(), calm_steps.end(), 0); damping = p_value; }
	double get_damping() const { return damping; }
	void set_root_stiffness(double p_value) { std::fill(calm_steps.begin(), calm_steps.end(), 0); root_stiffness = p_value; }
	double get_root_stiffness() const { return root_stiffness; }
	void set_tip_stiffness(double p_value) { std::fill(calm_steps.begin(), calm_steps.end(), 0); tip_stiffness = p_value; }
	double get_tip_stiffness() const { return tip_stiffness; }
	void set_iterations(int p_value) { std::fill(calm_steps.begin(), calm_steps.end(), 0); iterations = p_value; }
	int get_iterations() const { return iterations; }
	void set_settle_steps(int p_value) { settle_steps = p_value; }
	int get_settle_steps() const { return settle_steps; }
	void set_collisions(const PackedFloat32Array &p_capsules); // replace the colliders (local, 7 floats each)
	void set_capsule_collision(bool p_value) { capsule_collision = p_value; }
	bool get_capsule_collision() const { return capsule_collision; }
	void set_surface_collision(bool p_value) { surface_collision = p_value; }
	bool get_surface_collision() const { return surface_collision; }
	int get_penetration_count(); // hair points inside the body surface (for tests)
	Vector3 get_mean_tip_vector() const; // the mean of the absolute components of the tip offsets (head frame): the size of the swing along each axis, left and right not cancelling
	PackedVector3Array get_guide_points(int p_guide) const; // world positions of one guide (tests)
	Vector3 get_busiest_guide() const; // (largest step motion, its guide, guides still moving) for tests
	double get_mean_tip_offset() const; // metres: how far the hair tips are from their rest places on average, in the head's frame (for tests and tuning the swing)
	int get_guide_count() const { return guide_count; }
	// Re-reads the guides from the hair mesh (call after the hair mesh was replaced).
	void rebind() { bind_mesh(); }
	// A push on every point (m/s), for a shake or a hit.
	void kick(const Vector3 &p_impulse);

	void _process(double p_delta) override;
};

} // namespace godot
