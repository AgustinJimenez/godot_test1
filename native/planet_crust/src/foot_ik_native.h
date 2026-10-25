#pragma once

// Foot IK v2 in native code (AGENT_TASKS/091): the skinned sole of one foot (every foot-mesh vertex weighted onto the foot and
// toe bones, cached once by FootIKV2Sole in GDScript) replayed from the two bone poses, and the leg solver. The same maths as
// foot_ik_v2_sole.gd and foot_ik_v2_solver.gd, which stay the reference: the GDScript uses these when the class exists.
// Pure computation on its own data: any thread may call it.

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/packed_float32_array.hpp>
#include <godot_cpp/variant/packed_vector3_array.hpp>
#include <godot_cpp/variant/transform3d.hpp>
#include <godot_cpp/variant/vector3.hpp>

namespace godot {

class FootIKV2Native : public RefCounted {
	GDCLASS(FootIKV2Native, RefCounted)

protected:
	static void _bind_methods();

private:
	PackedFloat32Array foot_weight; // weight share on the foot bone
	PackedFloat32Array toe_weight;
	PackedVector3Array foot_local; // weighted bind-space position, foot part
	PackedVector3Array toe_local;

public:
	// The cached sole: the four arrays of FootIKV2Sole (same length).
	void set_sole(const PackedFloat32Array &p_foot_weight, const PackedFloat32Array &p_toe_weight,
			const PackedVector3Array &p_foot_local, const PackedVector3Array &p_toe_local);
	int get_count() const { return foot_weight.size(); }

	// The sole points in skeleton space from the two bone poses.
	PackedVector3Array points(const Transform3D &p_foot_pose, const Transform3D &p_toe_pose) const;
	// The sole points within `p_band` of the lowest (in world height under `p_to_world`), in WORLD space.
	PackedVector3Array level_points(const Transform3D &p_foot_pose, const Transform3D &p_toe_pose, const Transform3D &p_to_world, double p_band) const;
	// World height of the lowest sole point under `p_to_world` (INF when there is none).
	double lowest_world_y(const Transform3D &p_foot_pose, const Transform3D &p_toe_pose, const Transform3D &p_to_world) const;

	// Two-bone leg maths (foot_ik_v2_solver.gd `solve`): [knee, ankle, direction, pole, (distance, 0, 0)].
	static PackedVector3Array solve(const Vector3 &p_hip, const Vector3 &p_animated_knee, const Vector3 &p_target, double p_upper,
			double p_lower, const Vector3 &p_rest_pole, double p_max_flexion_deg, double p_max_swing_deg, const Vector3 &p_down,
			double p_bend_free);
};

} // namespace godot
