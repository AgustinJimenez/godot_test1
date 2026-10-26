#include "foot_ik_core_native.h"

#include "foot_ik_native.h"

#include <godot_cpp/classes/animation_player.hpp>
#include <godot_cpp/classes/character_body3d.hpp>
#include <godot_cpp/classes/collision_object3d.hpp>
#include <godot_cpp/classes/engine.hpp>
#include <godot_cpp/classes/node3d.hpp>
#include <godot_cpp/classes/world3d.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/core/math.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/utility_functions.hpp>

#include <algorithm>
#include <cmath>
#include <limits>

using namespace godot;

namespace {
// constants of foot_ik_v2_modifier.gd
const double SUPPORT_STEP = 0.02, SUPPORT_RATE = 0.3, SUPPORT_TOLERANCE = 0.03, SUPPORT_MIN_PLANT = 0.9, SINK_MIN = 0.04, SINK_MAX = 0.25;
const double LEDGE_DROP = 0.25, LEDGE_PROBED = 0.16, BODY_LAG_SNAP = 0.4, MOVING_HOLD_SECONDS = 0.3, CORRECTION_STEP = 0.03, KNEE_FOLLOWS_FOOT = 0.1;
const double LEVEL_TOLERANCE = 0.03, SOFT_PELVIS_DROP = 0.10, STANCE_SHIFT_STEP = 0.05, STANCE_RELEASE_SPEED = 0.6, TOE_TIP_FORWARD = 0.035;
const double RISER_PENETRATION = 0.04, SOLE_GAP_TOLERANCE = 0.001, RISER_RETREAT_STEP = 0.012, JUMP_SPEED_EPSILON = 0.5;
const double PLANT_FADE_START = 0.03, TOE_TIP_REACH = 0.10, PLANT_FADE_END = 0.14, PLANT_RATE = 8.0, PLANT_RELEASE_BELOW = 0.02;
const double PELVIS_REACH_MARGIN = 0.012, PELVIS_PLANTED_TOLERANCE = 0.05;
const int SOLE_SINK_SAMPLES = 40, SOLE_SINK_ATTEMPTS = 2, RISER_MAX_RETREATS = 4, CLEAR_ATTEMPTS = 8;

double smoothstep_d(double e0, double e1, double x) {
	const double t = Math::clamp((x - e0) / (e1 - e0), 0.0, 1.0);
	return t * t * (3.0 - 2.0 * t);
}
double move_toward_d(double a, double b, double d) {
	return std::abs(b - a) <= d ? b : a + (b > a ? 1.0 : -1.0) * d;
}
inline int frames() {
	return (int)Engine::get_singleton()->get_physics_frames();
}
inline Vector3 up() {
	return Vector3(0, 1, 0);
}
} // namespace

void FootIKV2CoreNative::_bind_methods() {
	ClassDB::bind_method(D_METHOD("process", "skeleton", "owner", "delta"), &FootIKV2CoreNative::process);
	ClassDB::bind_method(D_METHOD("reset"), &FootIKV2CoreNative::reset);
}

void FootIKV2CoreNative::reset() {
	dicts_ready = false;
	body_bone_indices.clear();
	body_bones_skeleton = nullptr;
	frame_cache = -1;
}

Vector3 FootIKV2CoreNative::get_vec(const Dictionary &p_dict, const StringName &p_side, const Vector3 &p_default) const {
	return p_dict.get(p_side, p_default);
}

int FootIKV2CoreNative::leg_index(const StringName &p_side) const {
	for (size_t i = 0; i < legs.size(); i++) {
		if (legs[i].side == p_side) {
			return (int)i;
		}
	}
	return -1;
}

#define GETD(name, var) P.var = owner->get(name)

void FootIKV2CoreNative::read_settings() {
	GETD("enabled", enabled);
	GETD("foot_lock", foot_lock);
	GETD("max_knee_flexion_deg", max_knee_flexion_deg);
	GETD("max_hip_swing_deg", max_hip_swing_deg);
	GETD("joint_speed_deg", joint_speed_deg);
	GETD("ground_mask", ground_mask);
	GETD("fallback_floor_max_angle_deg", fallback_floor_max_angle_deg);
	GETD("max_surface_drop", max_surface_drop);
	GETD("ray_up", ray_up);
	GETD("ray_down", ray_down);
	GETD("ankle_height", ankle_height);
	GETD("weight", weight);
	GETD("max_pelvis_drop", max_pelvis_drop);
	GETD("moving_pelvis_drop", moving_pelvis_drop);
	GETD("still_speed", still_speed);
	GETD("jump_counts_as_moving", jump_counts_as_moving);
	GETD("body_smooth", body_smooth);
	GETD("body_follow_rate", body_follow_rate);
	GETD("body_max_lag", body_max_lag);
	GETD("support_snap", support_snap);
	GETD("support_search", support_search);
	GETD("pelvis_attack_speed", pelvis_attack_speed);
	GETD("moving_pelvis_rate", moving_pelvis_rate);
	GETD("pelvis_release_speed", pelvis_release_speed);
	GETD("max_stance_shift", max_stance_shift);
	GETD("reach_when_still", reach_when_still);
	GETD("reach_when_moving", reach_when_moving);
	GETD("plant_fade", plant_fade);
	GETD("reach_clamp_plant_min", reach_clamp_plant_min);
	GETD("ground_filter", ground_filter);
	GETD("max_lift", max_lift);
	player_body = owner->get("player_body");
	ledge = owner->get("ledge");
	host_node = nullptr;
	if (player_body != nullptr) {
		Node *body_node = Object::cast_to<Node>(player_body);
		host_node = body_node != nullptr ? body_node->get_parent() : nullptr;
	}
	delta_physics = owner->get_physics_process_delta_time();
	hips_bone = owner->get("_hips_bone");
	if (dicts_ready) { // the shell never replaces its Dictionaries: they are fetched once
		return;
	}
	dicts_ready = true;
	debug_target = owner->get("debug_target");
	debug_skip_reason = owner->get("debug_skip_reason");
	debug_ground_normal = owner->get("debug_ground_normal");
	debug_animated_ankle = owner->get("debug_animated_ankle");
	debug_ground = owner->get("debug_ground");
	debug_surface = owner->get("debug_surface");
	debug_solve = owner->get("debug_solve");
	debug_reach_check = owner->get("debug_reach_check");
	debug_state = owner->get("debug_state");
	debug_stepping = owner->get("debug_stepping");
	debug_align = owner->get("debug_align");
	debug_support_shift = owner->get("debug_support_shift");
	debug_plant_weight = owner->get("debug_plant_weight");
	debug_stance_shift = owner->get("debug_stance_shift");
	debug_stance_plan = owner->get("debug_stance_plan");
	debug_toe_lift = owner->get("debug_toe_lift");
	final_pose = owner->get("final_pose");
	sole_dict = owner->get("_sole");
	base_dict = owner->get("_base");
	hips_bone = owner->get("_hips_bone");
}

void FootIKV2CoreNative::read_legs() {
	legs.clear();
	const Dictionary legs_dict = owner->get("_legs");
	const Array keys = legs_dict.keys();
	for (int i = 0; i < keys.size(); i++) {
		const StringName side = keys[i];
		const Dictionary d = legs_dict[side];
		Leg leg;
		leg.side = side;
		leg.hip = d["hip"];
		leg.knee = d["knee"];
		leg.foot = d["foot"];
		leg.toe = d["toe"];
		leg.toe_depth = d["toe_depth"];
		leg.upper = d["upper"];
		leg.lower = d["lower"];
		leg.rest_pole = d["rest_pole"];
		leg.sole_local = d["sole_local"];
		leg.heel_local = d["heel_local"];
		leg.sole = sole_dict.has(side) ? (Object *)sole_dict[side] : nullptr;
		legs.push_back(leg);
	}
	base.resize(legs.size());
}

void FootIKV2CoreNative::process(Skeleton3D *p_skeleton, Node *p_owner, double p_delta) {
	skel = p_skeleton;
	owner = p_owner;
	if (skel == nullptr || owner == nullptr) {
		return;
	}
	if (hold_release.is_null()) {
		hold_release.instantiate();
		stepper.instantiate();
		lock.instantiate();
		limiter.instantiate();
		smoother.instantiate();
		ground.instantiate();
		knee_hint.instantiate();
	}
	read_settings();
	read_legs();
	if (legs.empty()) {
		return;
	}
	if (P.enabled) {
		owner->set("debug_last_frame", frames());
		owner->set("debug_passes", (int)owner->get("debug_passes") + 1);
		take_snapshot();
		if (pelvis_drop + body_lag > 0.0005 && hips_bone >= 0) {
			skel->set_bone_global_pose(hips_bone, hips_base);
		}
		for (size_t i = 0; i < legs.size(); i++) {
			place_foot((int)i);
		}
	}
	publish_final_poses();
	owner->set("_is_moving", is_moving);
	owner->set("debug_pelvis_drop", pelvis_drop);
	(void)p_delta;
}

void FootIKV2CoreNative::publish_final_poses() {
	owner->set("final_frame", frames());
	const Transform3D to_world = skel->get_global_transform();
	owner->set("final_basis", to_world.basis);
	for (const Leg &leg : legs) {
		for (int bone : { leg.hip, leg.knee, leg.foot, leg.toe }) {
			if (bone >= 0) {
				final_pose[bone] = to_world * skel->get_bone_global_pose(bone);
			}
		}
	}
	if (body_bones_skeleton != skel || body_bone_indices.empty()) {
		body_bone_indices.clear();
		body_bones_skeleton = skel;
		const char *roles[] = { "Hips", "Spine", "Spine1", "Spine2", "LeftShoulder", "RightShoulder", "LeftArm", "RightArm" };
		for (const char *role : roles) {
			const StringName bone_name = player_body != nullptr ? (StringName)player_body->call("resolve_bone_name", StringName(role)) : StringName(role);
			body_bone_indices.push_back(skel->find_bone(String(bone_name)));
		}
	}
	for (int bone : body_bone_indices) {
		if (bone >= 0) {
			final_pose[bone] = to_world * skel->get_bone_global_pose(bone);
		}
	}
}

void FootIKV2CoreNative::take_snapshot() {
	const int current = frames();
	if (current == frame_cache) {
		return;
	}
	frame_cache = current;
	base_dict.clear();
	for (size_t i = 0; i < legs.size(); i++) {
		const Leg &leg = legs[i];
		base[i].hip = skel->get_bone_global_pose(leg.hip);
		base[i].knee = skel->get_bone_global_pose(leg.knee);
		base[i].foot = skel->get_bone_global_pose(leg.foot);
	}
	update_pelvis_drop();
	for (size_t i = 0; i < legs.size(); i++) {
		Dictionary d;
		d["hip"] = base[i].hip;
		d["knee"] = base[i].knee;
		d["foot"] = base[i].foot;
		base_dict[legs[i].side] = d;
	}
}

void FootIKV2CoreNative::update_pelvis_drop() {
	CharacterBody3D *host = host_node != nullptr ? Object::cast_to<CharacterBody3D>(host_node) : nullptr;
	const double delta = delta_physics;
	bool moving = host != nullptr && Vector2(host->get_velocity().x, host->get_velocity().z).length() > P.still_speed;
	moving_hold = moving ? MOVING_HOLD_SECONDS : std::max(moving_hold - delta, 0.0);
	const bool ledge_stepping = ledge != nullptr ? (bool)ledge->get("stepping") : false;
	moving = moving || moving_hold > 0.0 || ledge_stepping; // a stair step stalls the capsule
	bool jumpish = false;
	if (P.jump_counts_as_moving) {
		if (host != nullptr && (!host->is_on_floor() || std::abs(host->get_velocity().y) > JUMP_SPEED_EPSILON)) {
			moving = true;
			jumpish = true;
		}
		AnimationPlayer *anim = player_body != nullptr ? Object::cast_to<AnimationPlayer>((Object *)player_body->get("anim_player")) : nullptr;
		if (anim != nullptr && String(anim->get_current_animation()).contains("jump")) {
			moving = true;
			jumpish = true;
			if (String(anim->get_current_animation()).contains("land") && host != nullptr &&
					hold_release->rests(host, P.still_speed, debug_solve, debug_state, debug_ground_normal)) {
				moving = false;
				jumpish = false;
			}
		}
	}
	is_moving = moving;
	hold_release->blend_walk(moving, delta);
	update_body_lag(host, jumpish, delta);
	double needed = plan_stance(moving, delta);
	needed = std::max(needed - body_lag, 0.0);
	stretch_hold = moving ? 0.0 : stretch_hold;
	bool stretched = false;
	for (size_t li = 0; li < legs.size(); li++) {
		const Leg &leg = legs[li];
		const Dictionary solved = debug_solve.get(leg.side, Dictionary());
		const bool stepping_leg = (bool)debug_stepping.get(leg.side, false);
		if (!moving && String(debug_state.get(leg.side, "")) == "stretched") {
			stretched = !stepping_leg || stretched;
			double candidate = pelvis_drop + (double)solved.get("residual", 0.0);
			if (stepping_leg) { // the stepper lags the foot behind its target, so its residual is not the reach: use how far the FINAL target (after the resample and toe clearance) is past the leg
				candidate = pelvis_drop + final_shortfall[li];
			}
			stretch_hold = std::max(stretch_hold, candidate);
		}
	}
	Array leg_solves;
	leg_solves.push_back(debug_solve.get(StringName("left"), Dictionary()));
	leg_solves.push_back(debug_solve.get(StringName("right"), Dictionary()));
	stretch_hold = hold_release->update(stretch_hold, pelvis_drop, leg_solves, stretched, skel->get_global_transform().basis.get_euler().y, delta);
	needed = std::min(std::max(needed, stretch_hold), P.max_pelvis_drop);
	if (moving) {
		needed = std::min(needed, P.moving_pelvis_drop);
	}
	const double attack = moving ? P.moving_pelvis_rate : P.pelvis_attack_speed;
	const double release = (moving && !jumpish) ? P.moving_pelvis_rate : P.pelvis_release_speed;
	if (needed > pelvis_drop) {
		pelvis_drop = std::min(needed, pelvis_drop + attack * delta);
	} else {
		pelvis_drop = std::max(needed, pelvis_drop - release * delta);
	}
	owner->set("debug_pelvis_drop", pelvis_drop);
	if (hips_bone < 0) {
		return;
	}
	hips_base = skel->get_bone_global_pose(hips_bone);
	const double total_drop = pelvis_drop + body_lag;
	if (total_drop <= 0.0005) {
		return;
	}
	const Vector3 shift = -(skel->get_global_transform().basis.inverse().xform(up())).normalized() * (real_t)total_drop;
	hips_base.origin += shift;
	for (size_t i = 0; i < legs.size(); i++) {
		base[i].hip.origin += shift;
		base[i].knee.origin += shift;
		base[i].foot.origin += shift;
	}
}

void FootIKV2CoreNative::update_body_lag(CharacterBody3D *p_host, bool p_jumpish, double p_delta) {
	if (!P.body_smooth || p_host == nullptr) {
		body_lag = 0.0;
		smoothed_y = std::numeric_limits<double>::quiet_NaN();
		owner->set("debug_body_lag", 0.0);
		return;
	}
	const double root_y = p_host->get_global_position().y;
	if (std::isnan(smoothed_y) || p_jumpish || std::abs(root_y - smoothed_y) > BODY_LAG_SNAP) {
		smoothed_y = smoother->reset(root_y);
	} else {
		smoothed_y = smoother->follow(root_y, p_delta, P.body_follow_rate, P.body_max_lag);
	}
	body_lag = root_y - smoothed_y;
	owner->set("debug_body_lag", body_lag);
}

double FootIKV2CoreNative::plan_stance(bool p_moving, double p_delta) {
	const Transform3D to_world = skel->get_global_transform();
	double worst = 0.0;
	for (size_t i = 0; i < legs.size(); i++) {
		const StringName side = legs[i].side;
		double chosen = 0.0;
		double drop = foot_drop(to_world, (int)i, 0.0);
		Array tried;
		Array first;
		first.push_back(0.0);
		first.push_back(drop);
		tried.push_back(first);
		debug_stance_plan[side] = tried;
		const double current = stance_shift.get(side, 0.0);
		if (!p_moving && drop > SOFT_PELVIS_DROP && current > 0.0) {
			const double keep = foot_drop(to_world, (int)i, current);
			if (keep <= SOFT_PELVIS_DROP) {
				chosen = current;
				drop = keep;
			}
		}
		if (!p_moving && drop > SOFT_PELVIS_DROP && P.max_stance_shift > 0.0) {
			double best_drop = drop;
			double shift = STANCE_SHIFT_STEP;
			while (shift <= P.max_stance_shift + 0.0001) {
				const double candidate = foot_drop(to_world, (int)i, shift);
				Array entry;
				entry.push_back(shift);
				entry.push_back(candidate);
				tried.push_back(entry);
				if (candidate < best_drop) {
					best_drop = candidate;
					chosen = shift;
				}
				if (candidate <= SOFT_PELVIS_DROP) {
					break;
				}
				shift += STANCE_SHIFT_STEP;
			}
			drop = best_drop;
		}
		const double held = std::max(chosen, current - STANCE_RELEASE_SPEED * p_delta);
		stance_shift[side] = held;
		debug_stance_shift[side] = held;
		worst = std::max(worst, drop);
	}
	return std::min(worst, P.max_pelvis_drop);
}

Vector3 FootIKV2CoreNative::inward(const Vector3 &p_ankle, const Vector3 &p_hip) {
	const Vector3 flat(p_hip.x - p_ankle.x, 0.0f, p_hip.z - p_ankle.z);
	return flat.length_squared() > 0.000001 ? flat.normalized() : Vector3();
}

double FootIKV2CoreNative::foot_drop(const Transform3D &p_to_world, int p_leg, double p_shift) {
	if (P.max_pelvis_drop <= 0.0) {
		return 0.0;
	}
	const Leg &leg = legs[p_leg];
	const Pose3 &b = base[p_leg];
	const Vector3 animated_ankle = p_to_world.xform(b.foot.origin);
	if (animated_ankle.y - p_to_world.origin.y > P.ankle_height + PELVIS_PLANTED_TOLERANCE) {
		return 0.0;
	}
	const Vector3 hip_world = p_to_world.xform(b.hip.origin);
	Vector3 sample = animated_ankle + inward(animated_ankle, hip_world) * (real_t)p_shift;
	sample.y -= (real_t)(pelvis_drop + body_lag);
	const Dictionary hit = ground_hit(sample, hip_world);
	if (hit.is_empty() || !is_walkable(hit["normal"])) {
		return 0.0;
	}
	const Vector3 hit_position = hit["position"];
	const Vector3 hit_normal = hit["normal"];
	Vector3 target = hit_position + hit_normal * (real_t)P.ankle_height;
	const Dictionary again = ground_hit(target, hip_world);
	if (!again.is_empty() && is_walkable(again["normal"])) {
		const Vector3 again_position = again["position"];
		const double moved = (double)again_position.y - (double)hit_position.y;
		if (std::abs(moved) >= 0.005) {
			target = again_position + (Vector3)again["normal"] * (real_t)P.ankle_height;
		}
	}
	const Vector3 to_hip = hip_world - animated_ankle.lerp(target, (real_t)P.weight);
	const double reach = leg.upper + leg.lower - PELVIS_REACH_MARGIN;
	const double excess = (double)to_hip.length_squared() - reach * reach;
	if (excess <= 0.0) {
		return 0.0;
	}
	const double discriminant = (double)to_hip.y * (double)to_hip.y - excess;
	return discriminant < 0.0 ? (double)to_hip.y : (double)to_hip.y - std::sqrt(discriminant);
}

bool FootIKV2CoreNative::is_swinging(const Vector3 &p_animated_ankle, double p_ground_y, double p_floor_y) const {
	return (p_animated_ankle.y - p_ground_y > P.max_lift) && (p_animated_ankle.y - p_floor_y > P.ankle_height + PELVIS_PLANTED_TOLERANCE);
}

void FootIKV2CoreNative::note_released(const StringName &p_side) {
	if (is_moving) {
		Dictionary record;
		record["frame"] = frames();
		record["start"] = Vector3();
		record["end"] = Vector3();
		corr_last[p_side] = record;
	}
}

// A foot given up to the animation while moving: the correction it had until now (6-16 cm at a toe-off of a jog or sprint, found by the planet soak,
// AGENT_TASKS/093) eases out at CORRECTION_STEP a frame instead of vanishing in one frame. False when there is nothing to ease.
bool FootIKV2CoreNative::ease_release(int p_leg, const Vector3 &p_animated_local) {
	const StringName side = legs[p_leg].side;
	Dictionary held = corr_last.get(side, Dictionary());
	if (!is_moving || held.is_empty() || (int)held["frame"] < frames() - 1) {
		return false;
	}
	const Vector3 last = held["end"];
	if (last.length() <= 0.001) {
		return false;
	}
	const Vector3 eased = last - last.normalized() * (real_t)std::min((double)last.length(), CORRECTION_STEP);
	held["start"] = last;
	held["end"] = eased;
	held["frame"] = frames();
	corr_last[side] = held;
	solve(p_leg, p_animated_local + eased);
	return true;
}

void FootIKV2CoreNative::place_foot(int p_leg) {
	const Leg &leg = legs[p_leg];
	const StringName side = leg.side;
	const Pose3 &b = base[p_leg];
	const Transform3D to_world = skel->get_global_transform();
	const Transform3D to_local = to_world.affine_inverse();
	Vector3 animated_ankle = to_world.xform(b.foot.origin);
	const Vector3 hip_world = to_world.xform(b.hip.origin);
	const bool rests = P.foot_lock && !is_moving && (animated_ankle.y - to_world.origin.y - P.ankle_height < PLANT_FADE_START);
	animated_ankle = lock->held(side, animated_ankle, hip_world, rests);
	debug_animated_ankle[side] = animated_ankle;
	const double shift = stance_shift.get(side, 0.0);
	const Vector3 sample = animated_ankle + inward(animated_ankle, hip_world) * (real_t)shift;
	const Dictionary hit = ground_hit(sample, hip_world);
	if (hit.is_empty()) {
		debug_skip_reason[side] = "no_ground";
		debug_target.erase(side);
		debug_state[side] = "released";
		note_released(side);
		if (ledge != nullptr) {
			ledge->call("over_drop", side, to_world.origin, animated_ankle, hip_world);
		}
		return;
	}
	Vector3 ground_pos = hit["position"];
	if (to_world.origin.y - ground_pos.y > LEDGE_DROP || Vector2(ground_pos.x - sample.x, ground_pos.z - sample.z).length() > LEDGE_PROBED) {
		if (ledge != nullptr) {
			ledge->call("over_drop", side, to_world.origin, animated_ankle, hip_world);
		}
	} else if (ledge != nullptr) {
		ledge->call("on_ground", side);
	}
	const Vector3 normal = hit["normal"];
	ground_pos.y = P.ground_filter ? (real_t)ground->height(side, ground_pos.y) : ground_pos.y;
	debug_ground[side] = ground_pos;
	Node *collider = Object::cast_to<Node>((Object *)hit.get("collider", Variant()));
	debug_surface[side] = collider != nullptr ? String(collider->get_name()) : String("");
	if (!is_walkable(normal)) {
		debug_skip_reason[side] = "not_walkable";
		debug_target.erase(side);
		debug_state[side] = "released";
		note_released(side);
		if (ledge != nullptr) {
			ledge->call("over_drop", side, to_world.origin, animated_ankle, hip_world);
		}
		return;
	}
	Vector3 target = ground_pos + normal * (real_t)P.ankle_height;
	const bool keeps = is_moving && normal.y >= 0.999 && std::abs(ground_pos.y - to_world.origin.y) < 0.03 && toe_on_flat(p_leg);
	keep_pitch[side] = keeps;
	keep_rotation[side] = keeps || (!is_moving && normal.y >= 0.999 && std::abs(ground_pos.y - to_world.origin.y) < 0.03 && toe_on_flat(p_leg));
	if (keeps) {
		target = animated_ankle + up() * (real_t)std::max(0.0, -lowest_sole_offset(p_leg, to_world) - ((double)animated_ankle.y - (double)ground_pos.y));
	}
	const bool swinging = is_swinging(animated_ankle, ground_pos.y, to_world.origin.y);
	const double lift = (double)animated_ankle.y - (double)to_world.origin.y - P.ankle_height;
	double wanted = P.plant_fade ? 1.0 - smoothstep_d(PLANT_FADE_START, PLANT_FADE_END, lift) : 1.0;
	if (swinging) {
		wanted = 0.0;
	}
	double plant = plant_state.get(side, wanted);
	const int frame_now = frames();
	if (P.plant_fade && (int)plant_frame.get(side, -1) != frame_now) {
		plant = move_toward_d(plant, wanted, PLANT_RATE / 60.0);
		plant_state[side] = plant;
		plant_frame[side] = frame_now;
	}
	plant_weight[side] = plant;
	debug_plant_weight[side] = plant;
	if (swinging && (!P.plant_fade || plant <= PLANT_RELEASE_BELOW)) {
		debug_skip_reason[side] = "mid_swing";
		debug_target.erase(side);
		debug_state[side] = "released";
		if (ease_release(p_leg, to_local.xform(animated_ankle))) {
			return;
		}
		note_released(side);
		return;
	}
	Vector3 blended = to_local.xform(animated_ankle.lerp(target, (real_t)(P.weight * plant)));
	const Vector3 hip_local = b.hip.origin;
	const double reach = leg.upper + leg.lower - 0.001;
	Dictionary reach_check;
	reach_check["hip_to_target"] = hip_local.distance_to(blended);
	reach_check["reach"] = reach;
	debug_reach_check[side] = reach_check;
	bool clamped = false;
	if (hip_local.distance_to(blended) > reach) {
		const bool trailing = plant < P.reach_clamp_plant_min;
		if (trailing || (is_moving && !P.reach_when_moving) || !P.reach_when_still) {
			const Vector3 animated_local = to_local.xform(animated_ankle);
			if (hip_local.distance_to(animated_local) > reach) {
				debug_skip_reason[side] = "out_of_reach";
				debug_target.erase(side);
				debug_state[side] = "released";
				if (ease_release(p_leg, animated_local)) {
					return;
				}
				note_released(side);
				return;
			}
			blended = FootIKV2Native::reachable(hip_local, animated_local, blended, reach);
		} else {
			clamped = true;
		}
	}
	debug_target[side] = target;
	debug_skip_reason[side] = clamped ? "reach_clamped" : "";
	debug_animated_ankle[side] = animated_ankle;
	debug_ground[side] = ground_pos;
	solve(p_leg, blended);
	align_foot(p_leg, normal);
	resample_and_correct(p_leg, hip_world);
	flatten_support(p_leg, to_world, hip_world);
	debug_toe_lift[side] = 0.0;
	if (!(bool)keep_pitch.get(side, false)) {
		clear_toe(p_leg, to_world, hip_world);
	}
	limit_step(p_leg);
	ease_correction(p_leg);
	const Vector3 landed = skel->get_bone_global_pose(leg.foot).origin;
	const Vector3 final_target = to_local.xform((Vector3)debug_target[side]);
	const double miss = landed.distance_to(final_target);
	Dictionary solved = debug_solve[side];
	solved["residual"] = miss;
	solved["clamped"] = clamped;
	debug_state[side] = miss <= 0.02 ? "at_target" : "stretched";
	debug_ground_normal[side] = normal;
	final_shortfall[p_leg] = std::max(0.0, (double)hip_local.distance_to(final_target) - reach);
}

void FootIKV2CoreNative::limit_step(int p_leg) {
	const Leg &leg = legs[p_leg];
	const Vector3 here = skel->get_bone_global_pose(leg.foot).origin;
	const bool planted = !is_moving && (double)plant_weight.get(leg.side, 1.0) >= SUPPORT_MIN_PLANT;
	const Vector3 moved = stepper->limit(leg.side, frames(), here, planted);
	debug_stepping[leg.side] = stepper->get_stepping().get(leg.side, false);
	if (!moved.is_equal_approx(here)) {
		solve(p_leg, moved);
		align_foot(p_leg, get_vec(debug_ground_normal, leg.side, up()));
	}
}

void FootIKV2CoreNative::align_foot(int p_leg, const Vector3 &p_normal) {
	const Leg &leg = legs[p_leg];
	const StringName side = leg.side;
	Transform3D pose = skel->get_bone_global_pose(leg.foot);
	const Vector3 sole = pose.basis.xform(leg.sole_local).normalized();
	const Vector3 local_normal = skel->get_global_transform().basis.orthonormalized().inverse().xform(p_normal).normalized();
	const Vector3 want = -local_normal;
	Dictionary record;
	record["before_deg"] = Math::rad_to_deg((double)sole.angle_to(want));
	record["after_deg"] = -1.0;
	record["applied"] = false;
	record["reason"] = "";
	if (p_normal.dot(up()) < 0.5) {
		record["reason"] = "too_steep";
		debug_align[side] = record;
		return;
	}
	if (sole.dot(want) < -0.999) {
		record["reason"] = "opposite";
		debug_align[side] = record;
		return;
	}
	const bool keep_pose = keep_rotation.get(side, false);
	if (keep_pose) {
		record["reason"] = "animated";
	}
	const Quaternion blended = Quaternion().slerp(Quaternion(sole, want), (real_t)(keep_pose ? 0.0 : P.weight * (double)plant_weight.get(side, 1.0)));
	if (blended.get_angle() >= 0.0001) {
		pose.basis = Basis(blended) * pose.basis;
		skel->set_bone_global_pose(leg.foot, pose);
		record["applied"] = true;
	}
	record["after_deg"] = Math::rad_to_deg((double)pose.basis.xform(leg.sole_local).normalized().angle_to(want));
	debug_align[side] = record;
}

void FootIKV2CoreNative::clear_toe(int p_leg, const Transform3D &p_to_world, const Vector3 &p_hip_world) {
	const Leg &leg = legs[p_leg];
	const StringName side = leg.side;
	int retreats = 0;
	for (int attempt = 0; attempt < CLEAR_ATTEMPTS; attempt++) {
		const Transform3D foot_pose = skel->get_bone_global_pose(leg.foot);
		const Vector3 sole = foot_pose.basis.xform(leg.sole_local).normalized();
		const Vector3 toe_world = p_to_world.xform(skel->get_bone_global_pose(leg.toe).origin);
		const Vector3 toe_point = toe_world + sole * (real_t)leg.toe_depth;
		const Transform3D foot_world = p_to_world * foot_pose;
		const Vector3 forward = (toe_world - foot_world.origin).normalized();
		const Vector3 points[3] = { toe_point, toe_point + forward * (real_t)TOE_TIP_FORWARD, foot_world.xform(leg.heel_local) };
		double penetration = 0.0;
		Vector3 worst = points[0];
		for (const Vector3 &point : points) {
			const Dictionary hit = ray(point, p_hip_world);
			if (!hit.is_empty()) {
				const double over = (double)((Vector3)hit["position"]).y - (double)point.y;
				if (over > penetration) {
					penetration = over;
					worst = point;
				}
			}
		}
		if (penetration <= 0.002) {
			if (!is_moving) {
				sink_to_true_sole(p_leg, p_to_world, p_hip_world);
			}
			return;
		}
		Vector3 target = debug_target.get(side, toe_point);
		if (attempt == 0 && (double)plant_weight.get(side, 1.0) < 0.999) {
			// a foot still fading onto the ground is only part way to its ground target: lift from where it stands, not from the full ground target
			// (the lift of 17 cm at a heel strike landed on top of the full target while the plant weight was 0.4: floor-walk IK jerk 0.209)
			target = foot_world.origin;
		}
		if (penetration > RISER_PENETRATION && retreats < RISER_MAX_RETREATS) {
			retreats++;
			const Vector3 ankle = foot_world.origin;
			const Vector3 flat(ankle.x - worst.x, 0.0f, ankle.z - worst.z);
			if (flat.length_squared() > 0.000001) {
				target += flat.normalized() * (real_t)RISER_RETREAT_STEP;
				debug_target[side] = target;
				solve(p_leg, p_to_world.affine_inverse().xform(target));
				align_foot(p_leg, get_vec(debug_ground_normal, side, up()));
				continue;
			}
		}
		target.y += (real_t)penetration;
		debug_toe_lift[side] = (double)debug_toe_lift.get(side, 0.0) + penetration;
		debug_target[side] = target;
		solve(p_leg, p_to_world.affine_inverse().xform(target));
		align_foot(p_leg, get_vec(debug_ground_normal, side, up()));
	}
}

void FootIKV2CoreNative::flatten_support(int p_leg, const Transform3D &p_to_world, const Vector3 &p_hip_world) {
	const Leg &leg = legs[p_leg];
	const StringName side = leg.side;
	debug_support_shift[side] = 0.0;
	if (!P.support_snap || (double)plant_weight.get(side, 1.0) < SUPPORT_MIN_PLANT) {
		return;
	}
	const Transform3D foot_world = p_to_world * skel->get_bone_global_pose(leg.foot);
	const Vector3 toe_world = p_to_world.xform(skel->get_bone_global_pose(leg.toe).origin);
	Vector3 forward(toe_world.x - foot_world.origin.x, 0.0f, toe_world.z - foot_world.origin.z);
	if (forward.length_squared() < 0.0001) {
		return;
	}
	forward = forward.normalized();
	const Vector3 heel = foot_world.xform(leg.heel_local);
	const Vector3 tip = toe_world + forward * (real_t)TOE_TIP_FORWARD;
	PackedVector3Array points;
	points.push_back(heel);
	points.push_back((heel + tip) * (real_t)0.5);
	points.push_back(tip);
	const Vector3 normal = get_vec(debug_ground_normal, side, up());
	const double slope = -((double)normal.x * forward.x + (double)normal.z * forward.z) / std::max((double)normal.y, 0.2);
	double shift = support_last.get(side, 0.0);
	const double wanted = wanted_support_shift(points, foot_world.origin, forward, slope, p_hip_world, shift, ((Vector3)debug_ground.get(side, Vector3())).y);
	if ((int)support_frame.get(side, -1) != frames()) {
		bool glide = !is_moving && wanted != shift;
		if (glide) {
			support_spread(points, foot_world.origin, forward, slope, wanted, p_hip_world);
			const double wanted_level = spread_level;
			const double flat = support_spread(points, foot_world.origin, forward, slope, shift, p_hip_world);
			glide = flat <= SUPPORT_TOLERANCE && std::abs(wanted_level - spread_level) <= SINK_MIN;
		}
		shift = glide ? move_toward_d(shift, wanted, SUPPORT_RATE / 60.0) : wanted;
		support_last[side] = shift;
		support_frame[side] = frames();
	}
	if (std::abs(shift) > 0.0005) {
		Vector3 target = debug_target.get(side, foot_world.origin);
		target += forward * (real_t)shift;
		debug_target[side] = target;
		debug_support_shift[side] = shift;
		solve(p_leg, p_to_world.affine_inverse().xform(target));
		align_foot(p_leg, normal);
		resample_and_correct(p_leg, p_hip_world);
		for (int index = 0; index < points.size(); index++) {
			points.set(index, points[index] + forward * (real_t)shift);
		}
	}
	if (!is_moving) {
		sink_to_sole_level(p_leg, p_to_world, points);
	}
}

void FootIKV2CoreNative::sink_to_sole_level(int p_leg, const Transform3D &p_to_world, const PackedVector3Array &p_points) {
	const Leg &leg = legs[p_leg];
	const StringName side = leg.side;
	Vector3 ground_pos = debug_ground.get(side, Vector3());
	const Vector3 normal = get_vec(debug_ground_normal, side, up());
	const Vector3 hip_world = p_to_world.xform(base[p_leg].hip.origin);
	double lowest = std::numeric_limits<double>::infinity();
	double highest = -std::numeric_limits<double>::infinity();
	for (int i = 0; i < p_points.size(); i++) {
		const Dictionary hit = ray(p_points[i], hip_world);
		if (hit.is_empty()) {
			return;
		}
		const double y = ((Vector3)hit["position"]).y;
		lowest = std::min(lowest, y);
		highest = std::max(highest, y);
	}
	if (highest - lowest > SUPPORT_TOLERANCE || normal.y < 0.95 || ground_pos.y - highest < SINK_MIN || ground_pos.y - highest > SINK_MAX) {
		return;
	}
	ground_pos.y = (real_t)highest;
	debug_ground[side] = ground_pos;
	Dictionary filter_state = ground->get_state();
	filter_state[side] = highest;
	const Vector3 landed = p_to_world.xform(skel->get_bone_global_pose(leg.foot).origin);
	const Vector3 target(landed.x, (real_t)(highest + P.ankle_height), landed.z);
	debug_target[side] = target;
	solve(p_leg, p_to_world.affine_inverse().xform(landed.lerp(target, (real_t)(P.weight * (double)plant_weight.get(side, 1.0)))));
	align_foot(p_leg, normal);
}

double FootIKV2CoreNative::wanted_support_shift(const PackedVector3Array &p_points, const Vector3 &p_ankle, const Vector3 &p_forward, double p_slope, const Vector3 &p_hip_world, double p_previous, double p_aim_y) {
	if (p_previous != 0.0 && support_spread(p_points, p_ankle, p_forward, p_slope, p_previous, p_hip_world) <= SUPPORT_TOLERANCE && std::abs(spread_level - p_aim_y) <= SINK_MIN) {
		return p_previous;
	}
	if (support_spread(p_points, p_ankle, p_forward, p_slope, 0.0, p_hip_world) <= SUPPORT_TOLERANCE) {
		return 0.0;
	}
	double fallback = 0.0;
	const int steps = (int)(P.support_search / SUPPORT_STEP);
	for (int step = 1; step <= steps; step++) {
		for (double direction : { 1.0, -1.0 }) {
			const double shift = direction * (double)step * SUPPORT_STEP;
			if (support_spread(p_points, p_ankle, p_forward, p_slope, shift, p_hip_world) > SUPPORT_TOLERANCE) {
				continue;
			}
			if (std::abs(spread_level - p_aim_y) <= SINK_MIN) {
				return shift;
			}
			fallback = fallback != 0.0 ? fallback : shift;
		}
	}
	return fallback;
}

double FootIKV2CoreNative::support_spread(const PackedVector3Array &p_points, const Vector3 &p_ankle, const Vector3 &p_forward, double p_slope, double p_shift, const Vector3 &p_hip_world) {
	double lowest = std::numeric_limits<double>::infinity();
	double highest = -std::numeric_limits<double>::infinity();
	for (int i = 0; i < p_points.size(); i++) {
		const Vector3 moved = p_points[i] + p_forward * (real_t)p_shift;
		const Dictionary hit = ray(moved, p_hip_world);
		if (hit.is_empty()) {
			return std::numeric_limits<double>::infinity();
		}
		const double along = (double)(moved - p_ankle).dot(p_forward);
		const double deviation = (double)((Vector3)hit["position"]).y - p_slope * along;
		lowest = std::min(lowest, deviation);
		highest = std::max(highest, deviation);
	}
	spread_level = highest;
	return highest - lowest;
}

void FootIKV2CoreNative::resample_and_correct(int p_leg, const Vector3 &p_hip_world) {
	const Leg &leg = legs[p_leg];
	const StringName side = leg.side;
	const Transform3D to_world = skel->get_global_transform();
	const Vector3 landed_world = to_world.xform(skel->get_bone_global_pose(leg.foot).origin);
	const Dictionary again = ground_hit(landed_world, p_hip_world);
	if (again.is_empty()) {
		return;
	}
	const Vector3 normal = again["normal"];
	if (!is_walkable(normal)) {
		return;
	}
	Vector3 again_position = again["position"];
	again_position.y = P.ground_filter ? (real_t)ground->resample(side, again_position.y) : again_position.y;
	const double moved = (double)again_position.y - (double)((Vector3)debug_ground.get(side, landed_world)).y;
	if (std::abs(moved) < 0.005) {
		return;
	}
	debug_ground[side] = again_position;
	debug_ground_normal[side] = normal;
	const Vector3 target = again_position + normal * (real_t)P.ankle_height;
	debug_target[side] = target;
	// (blended from the animated ankle, as place_foot does: from the landed foot the plant fade would be applied twice, and only on the frames the
	// ground under the foot moved 5 mm, which pulled a toeing-off foot 6 cm down and let it go in one frame: found by the planet soak, task 093)
	const Vector3 animated_world = debug_animated_ankle.get(side, landed_world);
	const Vector3 blended = to_world.affine_inverse().xform(animated_world.lerp(target, (real_t)(P.weight * (double)plant_weight.get(side, 1.0))));
	solve(p_leg, blended);
	align_foot(p_leg, normal);
}

bool FootIKV2CoreNative::is_walkable(const Vector3 &p_normal) const {
	double limit = P.fallback_floor_max_angle_deg;
	CharacterBody3D *body = host_node != nullptr ? Object::cast_to<CharacterBody3D>(host_node) : nullptr;
	if (body != nullptr) {
		limit = Math::rad_to_deg((double)body->get_floor_max_angle());
	}
	return (double)p_normal.dot(up()) >= std::cos(Math::deg_to_rad(limit));
}

bool FootIKV2CoreNative::plausible(const Dictionary &p_hit, const Vector3 &p_anchor) const {
	return !p_hit.is_empty() && (double)p_anchor.y - (double)((Vector3)p_hit["position"]).y <= P.max_surface_drop;
}

Ref<PhysicsRayQueryParameters3D> FootIKV2CoreNative::ray_params(const Vector3 &p_point, const Vector3 &p_hip) {
	if (ray_query.is_null()) {
		ray_query.instantiate();
		ray_query->set_collision_mask(P.ground_mask);
		CollisionObject3D *body = host_node != nullptr ? Object::cast_to<CollisionObject3D>(host_node) : nullptr;
		if (body != nullptr) {
			TypedArray<RID> exclude;
			exclude.push_back(body->get_rid());
			ray_query->set_exclude(exclude);
		}
	}
	ray_query->set_from(Vector3(p_point.x, (real_t)std::max((double)p_hip.y, (double)p_point.y + P.ray_up), p_point.z));
	ray_query->set_to(p_point - up() * (real_t)P.ray_down);
	return ray_query;
}

Dictionary FootIKV2CoreNative::ray(const Vector3 &p_point, const Vector3 &p_hip) {
	Ref<World3D> world = skel->get_world_3d();
	PhysicsDirectSpaceState3D *space = world.is_valid() ? world->get_direct_space_state() : nullptr;
	if (space == nullptr) {
		return Dictionary();
	}
	return space->intersect_ray(ray_params(p_point, p_hip));
}

Dictionary FootIKV2CoreNative::ground_hit(const Vector3 &p_ankle, const Vector3 &p_hip) {
	Vector3 root = p_hip;
	Node3D *host3d = host_node != nullptr ? Object::cast_to<Node3D>(host_node) : nullptr;
	if (host3d != nullptr) {
		root = host3d->get_global_position();
	}
	const Vector3 anchor(p_ankle.x, (real_t)std::max((double)p_ankle.y, (double)root.y + P.ankle_height), p_ankle.z);
	const Dictionary hit = ray(p_ankle, p_hip);
	if (plausible(hit, anchor)) {
		return hit;
	}
	const Vector3 inward_dir = Vector3(root.x - p_ankle.x, 0.0f, root.z - p_ankle.z).normalized();
	for (double step : { 0.04, 0.08, 0.12, 0.18, 0.26 }) {
		const Dictionary candidate = ray(p_ankle + inward_dir * (real_t)step, p_hip);
		if (plausible(candidate, anchor)) {
			const Dictionary deeper = ray(p_ankle + inward_dir * (real_t)(step + 0.10), p_hip);
			const double deeper_y = ((Vector3)deeper.get("position", Vector3(std::numeric_limits<real_t>::infinity(), std::numeric_limits<real_t>::infinity(), std::numeric_limits<real_t>::infinity()))).y;
			const bool same = std::abs(deeper_y - (double)((Vector3)candidate["position"]).y) < 0.03;
			return same ? deeper : candidate;
		}
	}
	return Dictionary();
}

void FootIKV2CoreNative::solve(int p_leg, const Vector3 &p_target) {
	const Leg &leg = legs[p_leg];
	const StringName side = leg.side;
	const Pose3 &b = base[p_leg];
	skel->set_bone_global_pose(leg.hip, b.hip);
	skel->set_bone_global_pose(leg.knee, b.knee);
	skel->set_bone_global_pose(leg.foot, b.foot);
	const Vector3 hip_pos = b.hip.origin;
	Dictionary record;
	record["reach"] = leg.upper + leg.lower - 0.001;
	record["needed"] = hip_pos.distance_to(p_target);
	record["target_local"] = p_target;
	debug_solve[side] = record;
	const Transform3D skel_global = skel->get_global_transform();
	const Vector3 skel_down = skel_global.basis.orthonormalized().inverse().xform(Vector3(0, -1, 0));
	const Vector3 animated_knee = b.knee.origin;
	const double walk = hold_release->get_walk();
	const Vector3 steady = knee_hint->steady(side, hip_pos, animated_knee, delta_physics, walk);
	const Basis foot_turn = b.foot.basis.orthonormalized() * skel->get_bone_global_rest(leg.foot).basis.orthonormalized().inverse();
	const Vector3 rest_hint = hip_pos + leg.rest_pole.lerp(foot_turn.xform(leg.rest_pole), (real_t)KNEE_FOLLOWS_FOOT);
	bool level = true;
	for (const Leg &other : legs) {
		level = level && std::abs((double)((Vector3)debug_ground.get(other.side, Vector3())).y - (double)skel_global.origin.y) < LEVEL_TOLERANCE;
	}
	const Vector3 knee_hint_point = (level ? steady : rest_hint).lerp(animated_knee, (real_t)walk);
	const PackedVector3Array solved = FootIKV2Native::solve(hip_pos, knee_hint_point, p_target, leg.upper, leg.lower, leg.rest_pole, P.max_knee_flexion_deg,
			P.max_hip_swing_deg, skel_down, walk);
	aim(leg.hip, leg.knee, solved[0], b.hip.basis);
	aim(leg.knee, leg.foot, solved[1], b.knee.basis);
	if ((bool)keep_rotation.get(side, false)) {
		Transform3D foot_pose = skel->get_bone_global_pose(leg.foot);
		foot_pose.basis = b.foot.basis;
		skel->set_bone_global_pose(leg.foot, foot_pose);
	}
	record["solved_ankle"] = solved[1];
	record["knee_target"] = solved[0];
	record["landed"] = skel->get_bone_global_pose(leg.foot).origin;
	record["landed_knee"] = skel->get_bone_global_pose(leg.knee).origin;
}

void FootIKV2CoreNative::sink_to_true_sole(int p_leg, const Transform3D &p_to_world, const Vector3 &p_hip_world) {
	const Leg &leg = legs[p_leg];
	const StringName side = leg.side;
	for (int attempt = 0; attempt < SOLE_SINK_ATTEMPTS; attempt++) {
		if (leg.sole == nullptr) {
			return;
		}
		const PackedVector3Array level = leg.sole->call("level_points", skel, p_to_world, 0.005);
		if (level.is_empty()) {
			return;
		}
		Ref<World3D> world = skel->get_world_3d();
		PhysicsDirectSpaceState3D *space = world.is_valid() ? world->get_direct_space_state() : nullptr;
		const double gap = FootIKV2Native::min_gap(space, ray_params(Vector3(), Vector3()), level, p_hip_world.y, P.ray_up, P.ray_down, SOLE_SINK_SAMPLES, SINK_MAX);
		if (!std::isfinite(gap) || gap <= SOLE_GAP_TOLERANCE) {
			return;
		}
		Vector3 target = debug_target.get(side, level[0]);
		target.y -= (real_t)(gap - SOLE_GAP_TOLERANCE);
		debug_target[side] = target;
		solve(p_leg, p_to_world.affine_inverse().xform(target));
		align_foot(p_leg, get_vec(debug_ground_normal, side, up()));
	}
}

void FootIKV2CoreNative::aim(int p_bone, int p_child, const Vector3 &p_target, const Basis &p_animated) {
	Transform3D pose = skel->get_bone_global_pose(p_bone);
	const Vector3 child_pos = skel->get_bone_global_pose(p_child).origin;
	const Vector3 from = child_pos - pose.origin;
	const Vector3 to = p_target - pose.origin;
	if (from.length_squared() < 0.0000001 || to.length_squared() < 0.0000001) {
		return;
	}
	pose.basis = Basis(Quaternion(from.normalized(), to.normalized())) * pose.basis;
	const Quaternion base_q = p_animated.get_rotation_quaternion();
	const Quaternion correction = limiter->limit(p_bone, frames(), pose.basis.get_rotation_quaternion() * base_q.inverse(), is_moving ? 0.0 : P.joint_speed_deg);
	pose.basis = Basis(correction * base_q);
	skel->set_bone_global_pose(p_bone, pose);
}

bool FootIKV2CoreNative::toe_on_flat(int p_leg) {
	const Leg &leg = legs[p_leg];
	const Transform3D to_world = skel->get_global_transform();
	const Vector3 ankle = to_world.xform(skel->get_bone_global_pose(leg.foot).origin);
	const Vector3 toe = to_world.xform(skel->get_bone_global_pose(leg.toe).origin);
	const Vector3 hip = to_world.xform(skel->get_bone_global_pose(leg.hip).origin);
	const Vector3 ahead = Vector3(toe.x - ankle.x, 0.0f, toe.z - ankle.z).normalized() * (real_t)TOE_TIP_REACH;
	for (const Vector3 &point : { toe, toe + ahead }) {
		const Dictionary hit = ground_hit(point, hip);
		if (hit.is_empty() || ((Vector3)hit["normal"]).y < 0.999 || std::abs((double)((Vector3)hit["position"]).y - (double)to_world.origin.y) >= 0.03) {
			return false;
		}
	}
	return true;
}

double FootIKV2CoreNative::lowest_sole_offset(int p_leg, const Transform3D &p_to_world) {
	const Leg &leg = legs[p_leg];
	const double lowest = leg.sole != nullptr ? (double)leg.sole->call("lowest_world_y", skel, p_to_world) : 0.0;
	return lowest - (double)p_to_world.xform(skel->get_bone_global_pose(leg.foot).origin).y;
}

void FootIKV2CoreNative::ease_correction(int p_leg) {
	const Leg &leg = legs[p_leg];
	const StringName side = leg.side;
	const Pose3 &b = base[p_leg];
	const int frame = frames();
	const Vector3 animated = b.foot.origin;
	const Vector3 landed = skel->get_bone_global_pose(leg.foot).origin;
	const Vector3 correction = landed - animated;
	Dictionary record = corr_last.get(side, Dictionary());
	if (record.is_empty() || (int)record["frame"] < frame - 1 || !is_moving) {
		Dictionary fresh;
		fresh["frame"] = frame;
		fresh["start"] = correction;
		fresh["end"] = correction;
		corr_last[side] = fresh;
		return;
	}
	if ((int)record["frame"] != frame) {
		record["start"] = record["end"];
		record["frame"] = frame;
	}
	const Vector3 start = record["start"];
	const Vector3 change = correction - start;
	const Vector3 normal = skel->get_global_transform().basis.orthonormalized().inverse().xform(get_vec(debug_ground_normal, side, up()));
	const Vector3 away = normal * (real_t)std::max((double)change.dot(normal), 0.0);
	Vector3 eased_part = change - away;
	if (eased_part.length() > CORRECTION_STEP) {
		eased_part = eased_part.normalized() * (real_t)CORRECTION_STEP;
	}
	Vector3 eased = start + away + eased_part;
	record["end"] = eased;
	corr_last[side] = record;
	if (!eased.is_equal_approx(correction)) {
		solve(p_leg, animated + eased);
		align_foot(p_leg, get_vec(debug_ground_normal, side, up()));
		const Transform3D to_world = skel->get_global_transform();
		clear_toe(p_leg, to_world, to_world.xform(b.hip.origin));
		Vector3 extra = skel->get_bone_global_pose(leg.foot).origin - animated - eased;
		if (extra.length() > CORRECTION_STEP) {
			eased += extra.normalized() * (real_t)CORRECTION_STEP;
			solve(p_leg, animated + eased);
			align_foot(p_leg, get_vec(debug_ground_normal, side, up()));
			extra = Vector3();
		}
		record["end"] = eased + extra;
		Dictionary solved = debug_solve[side];
		solved["eased"] = true;
	}
}
