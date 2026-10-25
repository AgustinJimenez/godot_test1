#pragma once

// Foot IK v2: the ledge safe zone and the skinned sole of one foot in native code (AGENT_TASKS/091, the last two GDScript logic files).
// FootIKV2LedgeNative is foot_ik_v2_ledge.gd (which way the body should walk so both feet have ground, PlayerLedgeNudge reads `push()`,
// `stepping`, `step_input`); FootIKV2SoleNative is foot_ik_v2_sole.gd (every foot-mesh vertex weighted onto the foot and toe bones, cached
// once, replayed from the two bone poses). Both keep the GDScript method names so the core and the players call them unchanged.

#include <godot_cpp/classes/mesh_instance3d.hpp>
#include <godot_cpp/classes/node.hpp>
#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/classes/skeleton3d.hpp>
#include <godot_cpp/classes/skin.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/packed_float32_array.hpp>
#include <godot_cpp/variant/packed_int32_array.hpp>
#include <godot_cpp/variant/packed_vector3_array.hpp>
#include <godot_cpp/variant/transform3d.hpp>
#include <godot_cpp/variant/vector2.hpp>
#include <godot_cpp/variant/vector3.hpp>

#include <vector>

namespace godot {

class FootIKV2LedgeNative : public RefCounted {
	GDCLASS(FootIKV2LedgeNative, RefCounted)

	struct Over {
		Vector3 body, ankle, hip;
	};
	Dictionary over_; // side -> Array [body, ankle, hip]
	bool stepping_ = false;
	Vector2 step_input_;
	uint64_t owner_id = 0; // the FootIKV2Modifier shell: ray settings, skeleton and the player's body live there

	Dictionary ray(const Vector3 &p_point, const Vector3 &p_hip);
	Vector3 safe_way(const Vector3 &p_body, const Vector3 &p_ankle, const Vector3 &p_hip);

protected:
	static void _bind_methods();

public:
	void bind(Node *p_owner);
	void over_drop(const StringName &p_side, const Vector3 &p_body, const Vector3 &p_ankle, const Vector3 &p_hip);
	void on_ground(const StringName &p_side);
	Vector3 push();
	void set_step(const Vector3 &p_world_way, const Basis &p_body_basis);
	bool get_stepping() const { return stepping_; }
	void set_stepping(bool p_stepping) { stepping_ = p_stepping; }
	Vector2 get_step_input() const { return step_input_; }
	void set_step_input(const Vector2 &p_input) { step_input_ = p_input; }
};

class FootIKV2SoleNative : public RefCounted {
	GDCLASS(FootIKV2SoleNative, RefCounted)

	int foot = -1, toe = -1;
	PackedFloat32Array foot_weight, toe_weight;
	PackedVector3Array foot_local, toe_local;

	void add_mesh(Skeleton3D *p_skel, MeshInstance3D *p_part);
	void add_vertex(Skeleton3D *p_skel, const Ref<Skin> &p_skin, const Vector3 &p_vertex, const PackedInt32Array &p_bones,
			const PackedFloat32Array &p_weights, int p_first, int p_influences);
	void prune(Skeleton3D *p_skel, double p_band);

protected:
	static void _bind_methods();

public:
	void build(Skeleton3D *p_skel, Node *p_character, int p_foot, int p_toe);
	bool is_empty() const { return foot_weight.is_empty(); }
	PackedVector3Array points(Skeleton3D *p_skel, bool p_live) const;
	double depth(Skeleton3D *p_skel) const;
	Vector3 heel_local(Skeleton3D *p_skel) const;
	PackedVector3Array level_points(Skeleton3D *p_skel, const Transform3D &p_to_world, double p_band) const;
	double lowest_world_y(Skeleton3D *p_skel, const Transform3D &p_to_world) const;
};

} // namespace godot
