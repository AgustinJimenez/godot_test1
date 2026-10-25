#pragma once

// Foot IK v2, the whole per-frame pass in native code (AGENT_TASKS/091): FootIKV2CoreNative is what FootIKV2Modifier (GDScript, a thin shell
// that keeps the exported settings, the debug_* members the lab and the trace tools read, the leg set-up and the ledge) calls from
// `_process_modification_with_delta`. A line-by-line port of foot_ik_v2_modifier.gd, which stays as the reference path: the shell runs it when
// the library is not loaded or PLANET_NO_NATIVE=1. The shell's Dictionaries (debug_*, _base, _legs, final_pose...) are SHARED with this class
// (a Dictionary is a reference), so a trace or a check reads exactly what the native pass wrote.

#include <godot_cpp/classes/node.hpp>
#include <godot_cpp/classes/physics_direct_space_state3d.hpp>
#include <godot_cpp/classes/physics_ray_query_parameters3d.hpp>
#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/classes/skeleton3d.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/packed_vector3_array.hpp>
#include <godot_cpp/variant/transform3d.hpp>
#include <godot_cpp/variant/vector3.hpp>

#include <vector>

#include "foot_ik_helpers_native.h"

namespace godot {

class FootIKV2CoreNative : public RefCounted {
	GDCLASS(FootIKV2CoreNative, RefCounted)

protected:
	static void _bind_methods();

public:
	// One pass. `p_owner` is the shell (a SkeletonModifier3D node): its exported settings and shared Dictionaries are read from it.
	void process(Skeleton3D *p_skeleton, Node *p_owner, double p_delta);
	// The shell calls this after (re)building the legs: forgets the cached bone indices.
	void reset();

private:
	struct Leg {
		StringName side;
		int hip = -1, knee = -1, foot = -1, toe = -1;
		double toe_depth = 0, upper = 0, lower = 0;
		Vector3 rest_pole, sole_local, heel_local;
		Object *sole = nullptr; // FootIKV2Sole (GDScript, with the native sole inside)
	};
	struct Pose3 {
		Transform3D hip, knee, foot;
	};
	struct Params {
		bool enabled = true, foot_lock = false, jump_counts_as_moving = true, body_smooth = true, support_snap = true, reach_when_still = true,
			 reach_when_moving = true, plant_fade = true, ground_filter = true;
		double max_knee_flexion_deg = 150, max_hip_swing_deg = 140, joint_speed_deg = 60, fallback_floor_max_angle_deg = 46, max_surface_drop = 0.45,
			   ray_up = 0.5, ray_down = 1.2, ankle_height = -1, weight = 1, max_pelvis_drop = 0.4, moving_pelvis_drop = 0.06, still_speed = 0.5,
			   body_follow_rate = 12, body_max_lag = 0.18, support_search = 0.16, pelvis_attack_speed = 1.5, moving_pelvis_rate = 0.25,
			   pelvis_release_speed = 0.6, max_stance_shift = 0.3, reach_clamp_plant_min = 0.85, max_lift = 0.25;
		int ground_mask = 1 | (1 << 5);
	};

	Params P;
	Node *owner = nullptr;
	Skeleton3D *skel = nullptr;
	Object *player_body = nullptr;
	Object *ledge = nullptr;
	Node *host_node = nullptr; // player_body's parent
	double delta_physics = 1.0 / 60.0;
	std::vector<Leg> legs;
	std::vector<StringName> body_bones_names;
	std::vector<int> body_bone_indices;
	Skeleton3D *body_bones_skeleton = nullptr;
	Dictionary base_dict; // shared with the shell: side -> {hip, knee, foot}
	std::vector<Pose3> base; // the same poses, native copy (index = leg)

	// shared Dictionaries (the shell's debug_* members)
	Dictionary debug_target, debug_skip_reason, debug_ground_normal, debug_animated_ankle, debug_ground, debug_surface, debug_solve, debug_reach_check,
			debug_state, debug_stepping, debug_align, debug_support_shift, debug_plant_weight, debug_stance_shift, debug_stance_plan, debug_toe_lift,
			final_pose, sole_dict;

	// the state of the pass
	int frame_cache = -1;
	double final_shortfall[2] = { 0.0, 0.0 };
	bool dicts_ready = false;
	int hips_bone = -1;
	Transform3D hips_base;
	double pelvis_drop = 0.0, body_lag = 0.0, stretch_hold = 0.0, smoothed_y = std::numeric_limits<double>::quiet_NaN(), moving_hold = 0.0, spread_level = 0.0;
	bool is_moving = false;
	Dictionary stance_shift, plant_weight, plant_state, plant_frame, support_last, support_frame, keep_pitch, keep_rotation, corr_last;

	Ref<FootIKV2StretchHoldNative> hold_release;
	Ref<FootIKV2StepperNative> stepper;
	Ref<FootIKV2LockNative> lock;
	Ref<FootIKV2LimiterNative> limiter;
	Ref<FootIKV2BodySmootherNative> smoother;
	Ref<FootIKV2GroundFilterNative> ground;
	Ref<FootIKV2KneeHintNative> knee_hint;
	Ref<PhysicsRayQueryParameters3D> ray_query;

	// ---- port of foot_ik_v2_modifier.gd (same names) ----
	void read_settings();
	void read_legs();
	int leg_index(const StringName &p_side) const;
	void publish_final_poses();
	void take_snapshot();
	void update_pelvis_drop();
	void update_body_lag(CharacterBody3D *p_host, bool p_jumpish, double p_delta);
	double plan_stance(bool p_moving, double p_delta);
	double foot_drop(const Transform3D &p_to_world, int p_leg, double p_shift);
	static Vector3 inward(const Vector3 &p_ankle, const Vector3 &p_hip);
	bool is_swinging(const Vector3 &p_animated_ankle, double p_ground_y, double p_floor_y) const;
	void place_foot(int p_leg);
	void limit_step(int p_leg);
	void align_foot(int p_leg, const Vector3 &p_normal);
	void clear_toe(int p_leg, const Transform3D &p_to_world, const Vector3 &p_hip_world);
	void flatten_support(int p_leg, const Transform3D &p_to_world, const Vector3 &p_hip_world);
	void sink_to_sole_level(int p_leg, const Transform3D &p_to_world, const PackedVector3Array &p_points);
	double wanted_support_shift(const PackedVector3Array &p_points, const Vector3 &p_ankle, const Vector3 &p_forward, double p_slope, const Vector3 &p_hip_world, double p_previous, double p_aim_y);
	double support_spread(const PackedVector3Array &p_points, const Vector3 &p_ankle, const Vector3 &p_forward, double p_slope, double p_shift, const Vector3 &p_hip_world);
	void resample_and_correct(int p_leg, const Vector3 &p_hip_world);
	bool is_walkable(const Vector3 &p_normal) const;
	Dictionary ground_hit(const Vector3 &p_ankle, const Vector3 &p_hip);
	Dictionary ray(const Vector3 &p_point, const Vector3 &p_hip);
	Ref<PhysicsRayQueryParameters3D> ray_params(const Vector3 &p_point, const Vector3 &p_hip);
	bool plausible(const Dictionary &p_hit, const Vector3 &p_anchor) const;
	void solve(int p_leg, const Vector3 &p_target);
	void sink_to_true_sole(int p_leg, const Transform3D &p_to_world, const Vector3 &p_hip_world);
	void aim(int p_bone, int p_child, const Vector3 &p_target, const Basis &p_animated);
	bool toe_on_flat(int p_leg);
	double lowest_sole_offset(int p_leg, const Transform3D &p_to_world);
	void ease_correction(int p_leg);
	void note_released(const StringName &p_side);
	Vector3 get_vec(const Dictionary &p_dict, const StringName &p_side, const Vector3 &p_default) const;
};

} // namespace godot
