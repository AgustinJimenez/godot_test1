#include "foot_ik_modifier_native.h"

#include "foot_ik_native.h"

#include <godot_cpp/classes/engine.hpp>
#include <godot_cpp/classes/skeleton3d.hpp>
#include <godot_cpp/classes/time.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/core/math.hpp>
#include <godot_cpp/variant/utility_functions.hpp>

#include <algorithm>
#include <map>
#include <vector>

using namespace godot;

// ---------------------------------------------------------------- modifier

#define FIK_BIND(VT, N) \
	ClassDB::bind_method(D_METHOD("get_" #N), &FootIKV2Modifier::get_##N); \
	ClassDB::bind_method(D_METHOD("set_" #N, "value"), &FootIKV2Modifier::set_##N); \
	ADD_PROPERTY(PropertyInfo(VT, #N), "set_" #N, "get_" #N);

#define FIK_BIND_HINT(VT, N, HINT, HSTR) \
	ClassDB::bind_method(D_METHOD("get_" #N), &FootIKV2Modifier::get_##N); \
	ClassDB::bind_method(D_METHOD("set_" #N, "value"), &FootIKV2Modifier::set_##N); \
	ADD_PROPERTY(PropertyInfo(VT, #N, HINT, HSTR), "set_" #N, "get_" #N);

// debug_* / final_* / _private members: readable and writable by scripts and the core, not edited or saved
#define FIK_BIND_STATE(VT, N) \
	ClassDB::bind_method(D_METHOD("get_" #N), &FootIKV2Modifier::get_##N); \
	ClassDB::bind_method(D_METHOD("set_" #N, "value"), &FootIKV2Modifier::set_##N); \
	ADD_PROPERTY(PropertyInfo(VT, #N, PROPERTY_HINT_NONE, "", PROPERTY_USAGE_NO_EDITOR), "set_" #N, "get_" #N);

void FootIKV2Modifier::_bind_methods() {
	FIK_BIND(Variant::BOOL, enabled)
	FIK_BIND(Variant::BOOL, foot_lock)
	FIK_BIND_HINT(Variant::FLOAT, max_knee_flexion_deg, PROPERTY_HINT_RANGE, "0,170,1")
	FIK_BIND_HINT(Variant::FLOAT, max_hip_swing_deg, PROPERTY_HINT_RANGE, "0,170,1")
	FIK_BIND(Variant::FLOAT, joint_speed_deg)
	FIK_BIND_HINT(Variant::INT, ground_mask, PROPERTY_HINT_LAYERS_3D_PHYSICS, "")
	FIK_BIND(Variant::FLOAT, fallback_floor_max_angle_deg)
	FIK_BIND(Variant::FLOAT, max_surface_drop)
	FIK_BIND(Variant::FLOAT, ray_up)
	FIK_BIND(Variant::FLOAT, ray_down)
	FIK_BIND(Variant::FLOAT, ankle_height)
	FIK_BIND_HINT(Variant::FLOAT, weight, PROPERTY_HINT_RANGE, "0,1")
	FIK_BIND(Variant::FLOAT, max_pelvis_drop)
	FIK_BIND(Variant::FLOAT, moving_pelvis_drop)
	FIK_BIND(Variant::FLOAT, still_speed)
	FIK_BIND(Variant::BOOL, jump_counts_as_moving)
	FIK_BIND(Variant::BOOL, body_smooth)
	FIK_BIND(Variant::FLOAT, body_follow_rate)
	FIK_BIND(Variant::FLOAT, body_max_lag)
	FIK_BIND(Variant::BOOL, support_snap)
	FIK_BIND(Variant::FLOAT, support_search)
	FIK_BIND(Variant::FLOAT, pelvis_attack_speed)
	FIK_BIND(Variant::FLOAT, moving_pelvis_rate)
	FIK_BIND(Variant::FLOAT, pelvis_release_speed)
	FIK_BIND(Variant::FLOAT, max_stance_shift)
	FIK_BIND(Variant::BOOL, reach_when_still)
	FIK_BIND(Variant::BOOL, reach_when_moving)
	FIK_BIND(Variant::BOOL, plant_fade)
	FIK_BIND_HINT(Variant::FLOAT, reach_clamp_plant_min, PROPERTY_HINT_RANGE, "0,1,0.05")
	FIK_BIND(Variant::BOOL, ground_filter)
	FIK_BIND(Variant::FLOAT, max_lift)

	ClassDB::bind_method(D_METHOD("get_player_body"), &FootIKV2Modifier::get_player_body);
	ClassDB::bind_method(D_METHOD("set_player_body", "value"), &FootIKV2Modifier::set_player_body);
	ADD_PROPERTY(PropertyInfo(Variant::OBJECT, "player_body", PROPERTY_HINT_NONE, "", PROPERTY_USAGE_NO_EDITOR), "set_player_body", "get_player_body");
	ClassDB::bind_method(D_METHOD("get_ledge"), &FootIKV2Modifier::get_ledge);
	ADD_PROPERTY(PropertyInfo(Variant::OBJECT, "ledge", PROPERTY_HINT_NONE, "", PROPERTY_USAGE_NO_EDITOR), "", "get_ledge");

	FIK_BIND_STATE(Variant::DICTIONARY, debug_target)
	FIK_BIND_STATE(Variant::DICTIONARY, debug_skip_reason)
	FIK_BIND_STATE(Variant::DICTIONARY, debug_ground_normal)
	FIK_BIND_STATE(Variant::DICTIONARY, debug_animated_ankle)
	FIK_BIND_STATE(Variant::DICTIONARY, debug_ground)
	FIK_BIND_STATE(Variant::DICTIONARY, debug_surface)
	FIK_BIND_STATE(Variant::INT, debug_last_frame)
	FIK_BIND_STATE(Variant::INT, debug_passes)
	FIK_BIND_STATE(Variant::DICTIONARY, final_pose)
	FIK_BIND_STATE(Variant::INT, final_frame)
	FIK_BIND_STATE(Variant::BASIS, final_basis)
	FIK_BIND_STATE(Variant::FLOAT, debug_pelvis_drop)
	FIK_BIND_STATE(Variant::DICTIONARY, debug_solve)
	FIK_BIND_STATE(Variant::DICTIONARY, debug_reach_check)
	FIK_BIND_STATE(Variant::DICTIONARY, debug_state)
	FIK_BIND_STATE(Variant::DICTIONARY, debug_stepping)
	FIK_BIND_STATE(Variant::DICTIONARY, debug_align)
	FIK_BIND_STATE(Variant::DICTIONARY, debug_support_shift)
	FIK_BIND_STATE(Variant::FLOAT, debug_body_lag)
	FIK_BIND_STATE(Variant::DICTIONARY, debug_plant_weight)
	FIK_BIND_STATE(Variant::DICTIONARY, debug_stance_shift)
	FIK_BIND_STATE(Variant::DICTIONARY, debug_stance_plan)
	FIK_BIND_STATE(Variant::DICTIONARY, debug_toe_lift)
	FIK_BIND_STATE(Variant::DICTIONARY, _legs)
	FIK_BIND_STATE(Variant::DICTIONARY, _sole)
	FIK_BIND_STATE(Variant::DICTIONARY, _base)
	FIK_BIND_STATE(Variant::INT, _hips_bone)
	FIK_BIND_STATE(Variant::BOOL, _is_moving)

	ClassDB::bind_method(D_METHOD("ledge_push"), &FootIKV2Modifier::ledge_push);
	ClassDB::bind_method(D_METHOD("build_legs"), &FootIKV2Modifier::build_legs);
}

FootIKV2Modifier::FootIKV2Modifier() {
	ledge.instantiate();
	ledge->bind(this);
}

void FootIKV2Modifier::_ready() {
	if (Engine::get_singleton()->is_editor_hint()) {
		return;
	}
	Skeleton3D *skel = get_skeleton();
	if (player_body == nullptr && skel != nullptr) {
		Node *parent = skel->get_parent();
		if (parent != nullptr && parent->has_method("resolve_bone_name")) {
			player_body = parent;
		}
	}
	build_legs();
	core.instantiate();
	core->reset();
}

// Humanoid roles, resolved through PlayerBody for any character.
void FootIKV2Modifier::build_legs() {
	_legs.clear();
	Skeleton3D *skel = get_skeleton();
	if (skel == nullptr || player_body == nullptr) {
		return;
	}
	_hips_bone = skel->find_bone(String(player_body->call("resolve_bone_name", StringName("Hips"))));
	Node *character = Object::cast_to<Node>((Object *)player_body->get("character"));
	struct Roles {
		const char *side, *hip, *knee, *foot, *toe;
	};
	const Roles roles[2] = { { "left", "LeftUpLeg", "LeftLeg", "LeftFoot", "LeftToeBase" }, { "right", "RightUpLeg", "RightLeg", "RightFoot", "RightToeBase" } };
	for (const Roles &role : roles) {
		const int hip = skel->find_bone(String(player_body->call("resolve_bone_name", StringName(role.hip))));
		const int knee = skel->find_bone(String(player_body->call("resolve_bone_name", StringName(role.knee))));
		const int foot = skel->find_bone(String(player_body->call("resolve_bone_name", StringName(role.foot))));
		if (hip < 0 || knee < 0 || foot < 0) {
			continue;
		}
		const Vector3 hip_rest = skel->get_bone_global_rest(hip).origin;
		const Vector3 knee_rest = skel->get_bone_global_rest(knee).origin;
		const Vector3 foot_rest = skel->get_bone_global_rest(foot).origin;
		const int toe_bone = skel->find_bone(String(player_body->call("resolve_bone_name", StringName(role.toe))));
		Ref<FootIKV2SoleNative> sole;
		sole.instantiate();
		sole->build(skel, character, foot, toe_bone);
		_sole[StringName(role.side)] = sole;
		const double sole_depth = sole->depth(skel);
		if (ankle_height < 0.0) {
			ankle_height = sole_depth;
		}
		const Vector3 rest_direction = (foot_rest - hip_rest).normalized();
		Vector3 rest_pole = knee_rest - hip_rest;
		rest_pole -= rest_direction * rest_pole.dot(rest_direction);
		Dictionary leg;
		leg["hip"] = hip;
		leg["knee"] = knee;
		leg["foot"] = foot;
		leg["toe"] = toe_bone;
		leg["toe_depth"] = std::max(0.0, (double)skel->get_bone_global_rest(toe_bone).origin.y);
		leg["upper"] = (double)hip_rest.distance_to(knee_rest);
		leg["lower"] = (double)knee_rest.distance_to(foot_rest);
		leg["rest_pole"] = rest_pole.normalized();
		leg["sole_local"] = (skel->get_bone_global_rest(foot).basis.inverse().xform(Vector3(0, -1, 0))).normalized();
		leg["heel_local"] = sole->heel_local(skel);
		_legs[StringName(role.side)] = leg;
	}
}

void FootIKV2Modifier::_process_modification_with_delta(double p_delta) {
	Skeleton3D *skel = get_skeleton();
	if (skel == nullptr || _legs.is_empty() || core.is_null()) {
		return;
	}
	const int64_t t0 = FootIKV2Debug::begin();
	core->process(skel, this, p_delta);
	FootIKV2Debug::end("total", t0);
	FootIKV2Debug::frame_tick();
}

// The horizontal way the body should walk so both feet have ground (safe zone); ZERO when they do.
Vector3 FootIKV2Modifier::ledge_push() {
	return enabled && (!_is_moving || ledge->get_stepping()) ? ledge->push() : Vector3();
}

// ---------------------------------------------------------------- solver

void FootIKV2Solver::_bind_methods() {
	ClassDB::bind_static_method("FootIKV2Solver", D_METHOD("solve", "hip", "animated_knee", "target", "upper", "lower", "rest_pole", "max_flexion_deg", "max_swing_deg", "down", "bend_free"),
			&FootIKV2Solver::solve, DEFVAL(0.0), DEFVAL(0.0), DEFVAL(Vector3(0, -1, 0)), DEFVAL(0.0));
}

Dictionary FootIKV2Solver::solve(const Vector3 &p_hip, const Vector3 &p_animated_knee, const Vector3 &p_target, double p_upper, double p_lower,
		const Vector3 &p_rest_pole, double p_max_flexion_deg, double p_max_swing_deg, const Vector3 &p_down, double p_bend_free) {
	const PackedVector3Array r = FootIKV2Native::solve(p_hip, p_animated_knee, p_target, p_upper, p_lower, p_rest_pole, p_max_flexion_deg, p_max_swing_deg, p_down, p_bend_free);
	Dictionary out;
	out["knee"] = r[0];
	out["ankle"] = r[1];
	out["direction"] = r[2];
	out["pole"] = r[3];
	out["distance"] = (double)r[4].x;
	return out;
}

// ---------------------------------------------------------------- debug timer

namespace {
bool g_debug_enabled = false;
int g_report_every = 300; // physics frames between automatic reports
std::map<String, int64_t> g_usec;
std::map<String, int64_t> g_calls;
int64_t g_frames = 0;
} // namespace

void FootIKV2Debug::_bind_methods() {
	ClassDB::bind_static_method("FootIKV2Debug", D_METHOD("set_enabled", "enabled"), &FootIKV2Debug::set_enabled);
	ClassDB::bind_static_method("FootIKV2Debug", D_METHOD("is_enabled"), &FootIKV2Debug::is_enabled);
	ClassDB::bind_static_method("FootIKV2Debug", D_METHOD("begin"), &FootIKV2Debug::begin);
	ClassDB::bind_static_method("FootIKV2Debug", D_METHOD("end", "part", "start"), &FootIKV2Debug::end);
	ClassDB::bind_static_method("FootIKV2Debug", D_METHOD("frame_tick"), &FootIKV2Debug::frame_tick);
	ClassDB::bind_static_method("FootIKV2Debug", D_METHOD("report"), &FootIKV2Debug::report);
	ClassDB::bind_static_method("FootIKV2Debug", D_METHOD("reset"), &FootIKV2Debug::reset);
}

void FootIKV2Debug::set_enabled(bool p_enabled) {
	g_debug_enabled = p_enabled;
}

bool FootIKV2Debug::is_enabled() {
	return g_debug_enabled;
}

int64_t FootIKV2Debug::begin() {
	return g_debug_enabled ? (int64_t)Time::get_singleton()->get_ticks_usec() : -1;
}

void FootIKV2Debug::end(const StringName &p_part, int64_t p_start) {
	if (p_start < 0) {
		return;
	}
	const String part = p_part;
	g_usec[part] += (int64_t)Time::get_singleton()->get_ticks_usec() - p_start;
	g_calls[part] += 1;
}

void FootIKV2Debug::frame_tick() {
	if (!g_debug_enabled) {
		return;
	}
	g_frames++;
	if (g_report_every > 0 && g_frames % g_report_every == 0) {
		UtilityFunctions::print(report());
	}
}

String FootIKV2Debug::report() {
	if (g_usec.empty()) {
		return "[FOOT_IK_V2_PERF] no samples yet";
	}
	std::vector<std::pair<String, int64_t>> parts(g_usec.begin(), g_usec.end());
	std::sort(parts.begin(), parts.end(), [](const std::pair<String, int64_t> &a, const std::pair<String, int64_t> &b) { return a.second > b.second; });
	String text = vformat("[FOOT_IK_V2_PERF] frames=%d  part: usec_total  usec/frame  calls", (int)g_frames);
	for (const auto &part : parts) {
		text += vformat("\n  %s %8d  %8.1f  %6d", part.first.rpad(14), (int)part.second, (double)part.second / (double)std::max<int64_t>(g_frames, 1), (int)g_calls[part.first]);
	}
	return text;
}

void FootIKV2Debug::reset() {
	g_usec.clear();
	g_calls.clear();
	g_frames = 0;
}
