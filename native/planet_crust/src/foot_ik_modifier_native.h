#pragma once

// Foot IK v2, the node itself in native code (AGENT_TASKS/091): FootIKV2Modifier is the SkeletonModifier3D the player installs. It owns the
// exported settings (the core reads them each pass), the debug_* / final_* members the lab and the traces read (the core writes the SAME
// Dictionaries), the leg set-up and the ledge, and runs FootIKV2CoreNative once per pass. Also here: FootIKV2Solver (the pure two-bone maths with
// the old GDScript signature, returning a Dictionary) and FootIKV2Debug (the opt-in per-part CPU timer of the lab).

#include <godot_cpp/classes/skeleton_modifier3d.hpp>
#include <godot_cpp/variant/basis.hpp>
#include <godot_cpp/variant/dictionary.hpp>

#include "foot_ik_core_native.h"
#include "foot_ik_ledge_native.h"

namespace godot {

#define FIK_PROP(T, N, D) \
	T N = D; \
	T get_##N() const { return N; } \
	void set_##N(const T &p_v) { N = p_v; }

class FootIKV2Modifier : public SkeletonModifier3D {
	GDCLASS(FootIKV2Modifier, SkeletonModifier3D)

	Ref<FootIKV2CoreNative> core;

protected:
	static void _bind_methods();

public:
	FIK_PROP(bool, enabled, true)
	FIK_PROP(bool, foot_lock, false) // EXPERIMENT: a resting foot stays planted while the body turns
	FIK_PROP(double, max_knee_flexion_deg, 150.0) // v1 defaults; 0 = off
	FIK_PROP(double, max_hip_swing_deg, 140.0) // cone from down; a crouch needs >100
	FIK_PROP(double, joint_speed_deg, 60.0) // joint correction change cap per frame at rest: a flip guard
	FIK_PROP(int, ground_mask, 1 | (1 << 5))
	FIK_PROP(double, fallback_floor_max_angle_deg, 46.0)
	FIK_PROP(double, max_surface_drop, 0.45)
	FIK_PROP(double, ray_up, 0.5)
	FIK_PROP(double, ray_down, 1.2)
	FIK_PROP(double, ankle_height, -1.0) // how far the ankle sits above ground when planted; negative derives it from the rig's rest pose
	FIK_PROP(double, weight, 1.0)
	FIK_PROP(double, max_pelvis_drop, 0.40)
	FIK_PROP(double, moving_pelvis_drop, 0.06)
	FIK_PROP(double, still_speed, 0.5)
	FIK_PROP(bool, jump_counts_as_moving, true)
	FIK_PROP(bool, body_smooth, true)
	FIK_PROP(double, body_follow_rate, 12.0)
	FIK_PROP(double, body_max_lag, 0.18)
	FIK_PROP(bool, support_snap, true)
	FIK_PROP(double, support_search, 0.16)
	FIK_PROP(double, pelvis_attack_speed, 1.5)
	FIK_PROP(double, moving_pelvis_rate, 0.25)
	FIK_PROP(double, pelvis_release_speed, 0.6)
	FIK_PROP(double, max_stance_shift, 0.30)
	FIK_PROP(bool, reach_when_still, true)
	FIK_PROP(bool, reach_when_moving, true)
	FIK_PROP(bool, plant_fade, true)
	FIK_PROP(double, reach_clamp_plant_min, 0.85)
	FIK_PROP(bool, ground_filter, true)
	FIK_PROP(double, max_lift, 0.25)

	Object *player_body = nullptr; // PlayerBody (GDScript)
	Object *get_player_body() const { return player_body; }
	void set_player_body(Object *p_body) { player_body = p_body; }

	FIK_PROP(Dictionary, debug_target, Dictionary())
	FIK_PROP(Dictionary, debug_skip_reason, Dictionary())
	FIK_PROP(Dictionary, debug_ground_normal, Dictionary())
	FIK_PROP(Dictionary, debug_animated_ankle, Dictionary())
	FIK_PROP(Dictionary, debug_ground, Dictionary())
	FIK_PROP(Dictionary, debug_surface, Dictionary())
	FIK_PROP(int, debug_last_frame, -1)
	FIK_PROP(int, debug_passes, 0)
	FIK_PROP(Dictionary, final_pose, Dictionary()) // bone index -> world Transform3D as published at the end of the last pass
	FIK_PROP(int, final_frame, -1)
	FIK_PROP(Basis, final_basis, Basis())
	FIK_PROP(double, debug_pelvis_drop, 0.0)
	FIK_PROP(Dictionary, debug_solve, Dictionary())
	FIK_PROP(Dictionary, debug_reach_check, Dictionary())
	FIK_PROP(Dictionary, debug_state, Dictionary())
	FIK_PROP(Dictionary, debug_stepping, Dictionary())
	FIK_PROP(Dictionary, debug_align, Dictionary())
	FIK_PROP(Dictionary, debug_support_shift, Dictionary())
	FIK_PROP(double, debug_body_lag, 0.0)
	FIK_PROP(Dictionary, debug_plant_weight, Dictionary())
	FIK_PROP(Dictionary, debug_stance_shift, Dictionary())
	FIK_PROP(Dictionary, debug_stance_plan, Dictionary())
	FIK_PROP(Dictionary, debug_toe_lift, Dictionary())
	FIK_PROP(Dictionary, _legs, Dictionary()) // side -> {"hip", "knee", "foot", "upper", "lower", "rest_pole", ...}
	FIK_PROP(Dictionary, _sole, Dictionary()) // side -> the cached skinned sole (FootIKV2SoleNative)
	FIK_PROP(Dictionary, _base, Dictionary()) // side -> the animated hip / knee / foot poses captured once per frame (written by the core)
	FIK_PROP(int, _hips_bone, -1)
	FIK_PROP(bool, _is_moving, false) // written by the core

	Ref<FootIKV2LedgeNative> ledge; // public: the player reads its step
	Ref<FootIKV2LedgeNative> get_ledge() const { return ledge; }

	FootIKV2Modifier();
	void _ready() override;
	void _process_modification_with_delta(double p_delta) override;
	void build_legs();
	Vector3 ledge_push();
};

class FootIKV2Solver : public RefCounted {
	GDCLASS(FootIKV2Solver, RefCounted)

protected:
	static void _bind_methods();

public:
	// Pure two-bone leg maths: {"knee", "ankle", "direction", "pole", "distance"}.
	static Dictionary solve(const Vector3 &p_hip, const Vector3 &p_animated_knee, const Vector3 &p_target, double p_upper, double p_lower,
			const Vector3 &p_rest_pole, double p_max_flexion_deg, double p_max_swing_deg, const Vector3 &p_down, double p_bend_free);
};

// Opt-in per-part CPU timing (the lab's --foot-ik-v2-perf). Off by default: begin() returns -1 and end() early-outs.
class FootIKV2Debug : public RefCounted {
	GDCLASS(FootIKV2Debug, RefCounted)

protected:
	static void _bind_methods();

public:
	static void set_enabled(bool p_enabled);
	static bool is_enabled();
	static int64_t begin();
	static void end(const StringName &p_part, int64_t p_start);
	static void frame_tick();
	static String report();
	static void reset();
};

} // namespace godot
