#include "foot_ik_helpers_native.h"

#include <godot_cpp/classes/engine.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/core/math.hpp>

#include <algorithm>
#include <cmath>

using namespace godot;

static double move_toward_d(double p_from, double p_to, double p_delta) {
	return std::abs(p_to - p_from) <= p_delta ? p_to : p_from + (p_to > p_from ? 1.0 : -1.0) * p_delta;
}

static double angle_difference_d(double p_from, double p_to) { // GDScript angle_difference: the signed shortest turn from `from` to `to`
	const double difference = std::fmod(p_to - p_from, 2.0 * Math_PI);
	return std::fmod(2.0 * difference, 2.0 * Math_PI) - difference;
}

// ---- limiter (foot_ik_v2_joint_limiter.gd) ----
void FootIKV2LimiterNative::_bind_methods() {
	ClassDB::bind_method(D_METHOD("limit", "bone", "frame", "correction", "max_deg"), &FootIKV2LimiterNative::limit);
}

Quaternion FootIKV2LimiterNative::limit(int p_bone, int p_frame, const Quaternion &p_correction, double p_max_deg) {
	const int seen = frame_of.get(p_bone, -100);
	if (seen != p_frame) {
		if (seen == p_frame - 1) {
			previous[p_bone] = latest[p_bone];
		} else {
			previous.erase(p_bone);
		}
		frame_of[p_bone] = p_frame;
	}
	Quaternion result = p_correction;
	if (p_max_deg > 0.0 && previous.has(p_bone)) {
		const Quaternion before = previous[p_bone];
		const double angle = Math::rad_to_deg((double)before.angle_to(p_correction));
		if (angle > p_max_deg) {
			result = before.slerp(p_correction, (real_t)(p_max_deg / angle));
		}
	}
	latest[p_bone] = result;
	return result;
}

// ---- stepper (foot_ik_v2_stepper.gd) ----
void FootIKV2StepperNative::_bind_methods() {
	ClassDB::bind_method(D_METHOD("get_stepping"), &FootIKV2StepperNative::get_stepping);
	ClassDB::add_property("FootIKV2StepperNative", PropertyInfo(Variant::DICTIONARY, "stepping"), "", "get_stepping");
	ClassDB::bind_method(D_METHOD("limit", "side", "frame", "here", "planted"), &FootIKV2StepperNative::limit);
}

Vector3 FootIKV2StepperNative::limit(const StringName &p_side, int p_frame, const Vector3 &p_here, bool p_planted) {
	const double SPEED = 0.025, LIFT = 0.05, TRIGGER = 0.06;
	if ((int)frame_of.get(p_side, -1) != p_frame) {
		frame_of[p_side] = p_frame;
		const bool continuing = p_planted && (bool)was_planted.get(p_side, false);
		start[p_side] = continuing ? (Vector3)last.get(p_side, p_here) : p_here;
		was_planted[p_side] = p_planted;
		const double jump = ((Vector3)start[p_side]).distance_to(p_here);
		if (!length.has(p_side) && jump > TRIGGER) {
			length[p_side] = jump;
		}
	}
	const Vector3 from = start[p_side];
	const double left = from.distance_to(p_here);
	if (!p_planted || left <= SPEED || !length.has(p_side)) {
		length.erase(p_side);
		last[p_side] = p_here;
		stepping_[p_side] = false;
		return p_here;
	}
	const Vector3 moved = from.move_toward(p_here, (real_t)SPEED);
	const double progress = 1.0 - (left - SPEED) / std::max((double)length.get(p_side, left), 0.001);
	last[p_side] = moved; // the path WITHOUT the lift
	stepping_[p_side] = true;
	return moved + Vector3(0, 1, 0) * (real_t)(LIFT * std::sin(Math_PI * Math::clamp(progress, 0.0, 1.0)));
}

// ---- lock (foot_ik_v2_lock.gd) ----
void FootIKV2LockNative::_bind_methods() {
	ClassDB::bind_method(D_METHOD("held", "side", "animated", "hip", "resting"), &FootIKV2LockNative::held);
}

Vector3 FootIKV2LockNative::held(const StringName &p_side, const Vector3 &p_animated, const Vector3 &p_hip, bool p_resting) {
	const double RELEASE = 0.25, FAR = 0.32;
	if (!p_resting) {
		anchor.erase(p_side);
		return p_animated;
	}
	if (anchor.has(p_side)) {
		const Vector3 a = anchor[p_side];
		const double apart = Vector2(p_animated.x - a.x, p_animated.z - a.z).length();
		const double reach = Vector2(p_hip.x - a.x, p_hip.z - a.z).length();
		if (apart <= RELEASE && reach <= FAR) {
			return Vector3(a.x, p_animated.y, a.z);
		}
	}
	anchor[p_side] = p_animated;
	return p_animated;
}

// ---- body smoother (foot_ik_v2_body_smoother.gd) ----
void FootIKV2BodySmootherNative::_bind_methods() {
	ClassDB::bind_method(D_METHOD("reset", "target"), &FootIKV2BodySmootherNative::reset);
	ClassDB::bind_method(D_METHOD("follow", "target", "delta", "position_rate", "max_lag"), &FootIKV2BodySmootherNative::follow);
}

double FootIKV2BodySmootherNative::reset(double p_target) {
	y = p_target;
	velocity = 0.0;
	last_target = p_target;
	return y;
}

double FootIKV2BodySmootherNative::follow(double p_target, double p_delta, double p_position_rate, double p_max_lag) {
	const double VELOCITY_RATE = 20.0;
	const double speed = (p_target - last_target) / std::max(p_delta, 0.0001);
	last_target = p_target;
	velocity += (speed - velocity) * (1.0 - std::exp(-VELOCITY_RATE * p_delta));
	y += velocity * p_delta;
	y += (p_target - y) * (1.0 - std::exp(-p_position_rate * p_delta));
	y = Math::clamp(y, p_target - p_max_lag, p_target);
	return y;
}

// ---- ground filter (foot_ik_v2_ground_filter.gd) ----
void FootIKV2GroundFilterNative::_bind_methods() {
	ClassDB::bind_method(D_METHOD("get_state"), &FootIKV2GroundFilterNative::get_state);
	ClassDB::add_property("FootIKV2GroundFilterNative", PropertyInfo(Variant::DICTIONARY, "state"), "", "get_state");
	ClassDB::bind_method(D_METHOD("height", "side", "raw"), &FootIKV2GroundFilterNative::height);
	ClassDB::bind_method(D_METHOD("resample", "side", "again_y"), &FootIKV2GroundFilterNative::resample);
}

double FootIKV2GroundFilterNative::height(const StringName &p_side, double p_raw) {
	const double RATE = 3.0, SAME_LEVEL = 0.04, FOLLOW = 0.06, SNAP = 0.45;
	const int HOLD_FRAMES = 3;
	const int frame_now = (int)Engine::get_singleton()->get_physics_frames();
	if ((int)frame_of.get(p_side, -1) == frame_now) {
		return (double)state_.get(p_side, p_raw);
	}
	frame_of[p_side] = frame_now;
	raw_[p_side] = p_raw;
	if (!state_.has(p_side)) {
		state_[p_side] = p_raw;
		return p_raw;
	}
	const double current = state_[p_side];
	const double gap = std::abs(p_raw - current);
	if (gap <= FOLLOW || gap > SNAP || p_raw > current) {
		state_[p_side] = p_raw;
		pending.erase(p_side);
		return p_raw;
	}
	Dictionary entry = pending.get(p_side, Dictionary());
	if (!entry.is_empty() && std::abs(p_raw - (double)entry["level"]) <= SAME_LEVEL) {
		entry["count"] = (int)entry["count"] + 1;
	} else {
		entry = Dictionary();
		entry["level"] = p_raw;
		entry["count"] = 1;
	}
	pending[p_side] = entry;
	if ((int)entry["count"] >= HOLD_FRAMES) {
		state_[p_side] = move_toward_d(current, p_raw, RATE / 60.0);
	}
	return (double)state_[p_side];
}

double FootIKV2GroundFilterNative::resample(const StringName &p_side, double p_again_y) {
	const double FOLLOW = 0.06;
	if (!state_.has(p_side)) {
		return p_again_y;
	}
	double difference = p_again_y - (double)raw_.get(p_side, p_again_y);
	if (std::abs(difference) > FOLLOW) {
		difference = 0.0;
	}
	return (double)state_[p_side] + difference;
}

// ---- knee hint (foot_ik_v2_knee_hint.gd) ----
void FootIKV2KneeHintNative::_bind_methods() {
	ClassDB::bind_method(D_METHOD("steady", "side", "hip", "knee", "delta", "walk"), &FootIKV2KneeHintNative::steady);
}

Vector3 FootIKV2KneeHintNative::steady(const StringName &p_side, const Vector3 &p_hip, const Vector3 &p_knee, double p_delta, double p_walk) {
	const double RATE = 0.4, WALK_RATE = 12.0;
	const Vector3 now = (p_knee - p_hip).normalized();
	Vector3 current = direction.get(p_side, now);
	const double rate = RATE + (WALK_RATE - RATE) * p_walk;
	current = (current != now) ? current.slerp(now, (real_t)(1.0 - std::exp(-rate * p_delta))) : now;
	direction[p_side] = current;
	return p_hip + current;
}

// ---- stretch hold (foot_ik_v2_stretch_hold.gd) ----
void FootIKV2StretchHoldNative::_bind_methods() {
	ClassDB::bind_method(D_METHOD("get_calm"), &FootIKV2StretchHoldNative::get_calm);
	ClassDB::bind_method(D_METHOD("set_calm", "value"), &FootIKV2StretchHoldNative::set_calm);
	ClassDB::bind_method(D_METHOD("get_landed"), &FootIKV2StretchHoldNative::get_landed);
	ClassDB::bind_method(D_METHOD("set_landed", "value"), &FootIKV2StretchHoldNative::set_landed);
	ClassDB::bind_method(D_METHOD("get_walk"), &FootIKV2StretchHoldNative::get_walk);
	ClassDB::bind_method(D_METHOD("set_walk", "value"), &FootIKV2StretchHoldNative::set_walk);
	ClassDB::add_property("FootIKV2StretchHoldNative", PropertyInfo(Variant::FLOAT, "calm"), "set_calm", "get_calm");
	ClassDB::add_property("FootIKV2StretchHoldNative", PropertyInfo(Variant::BOOL, "landed"), "set_landed", "get_landed");
	ClassDB::add_property("FootIKV2StretchHoldNative", PropertyInfo(Variant::FLOAT, "walk"), "set_walk", "get_walk");
	ClassDB::bind_method(D_METHOD("update", "hold", "drop", "legs", "stretched", "yaw", "delta"), &FootIKV2StretchHoldNative::update);
	ClassDB::bind_static_method("FootIKV2StretchHoldNative", D_METHOD("shortfall", "solves", "states", "normals"), &FootIKV2StretchHoldNative::shortfall);
	ClassDB::bind_method(D_METHOD("rests", "host", "still_speed", "solves", "states", "normals"), &FootIKV2StretchHoldNative::rests);
	ClassDB::bind_method(D_METHOD("blend_walk", "moving", "delta"), &FootIKV2StretchHoldNative::blend_walk);
}

double FootIKV2StretchHoldNative::update(double p_hold, double p_drop, const Array &p_legs, bool p_stretched, double p_yaw, double p_delta) {
	const double CALM_SECONDS = 0.5, MARGIN = 0.04, RELEASE_SPEED = 0.1;
	const double turning_angle = std::abs(angle_difference_d(yaw_, p_yaw));
	const bool turning = turning_angle > 0.004;
	yaw_ = p_yaw;
	calm_ = (p_stretched || turning) ? 0.0 : calm_ + p_delta;
	if (calm_ <= CALM_SECONDS) {
		return p_hold;
	}
	double slack = std::numeric_limits<double>::infinity();
	for (int i = 0; i < p_legs.size(); i++) {
		const Dictionary solved = p_legs[i];
		slack = std::min(slack, (double)solved.get("reach", 0.0) - (double)solved.get("needed", 0.0));
	}
	const double floor_hold = std::max(p_drop - std::max(slack - MARGIN, 0.0), 0.0);
	return std::max(std::min(p_hold, floor_hold), p_hold - RELEASE_SPEED * p_delta);
}

double FootIKV2StretchHoldNative::shortfall(const Dictionary &p_solves, const Dictionary &p_states, const Dictionary &p_normals) {
	double most = 0.0;
	const Array keys = p_solves.keys();
	for (int i = 0; i < keys.size(); i++) {
		const Variant side = keys[i];
		const Vector3 normal = p_normals.get(side, Vector3(0, 1, 0));
		const bool flat = normal.y > 0.95; // a slope is not a ledge
		const String state = String(p_states.get(side, ""));
		if (flat && state.begins_with("stretched")) {
			const Dictionary solved = p_solves[side];
			most = std::max(most, (double)solved.get("residual", 0.0));
		}
	}
	return most;
}

bool FootIKV2StretchHoldNative::rests(CharacterBody3D *p_host, double p_still_speed, const Dictionary &p_solves, const Dictionary &p_states, const Dictionary &p_normals) {
	const Vector3 velocity = p_host->get_velocity();
	const bool still = p_host->is_on_floor() && std::abs(velocity.y) < 0.5 && Vector2(velocity.x, velocity.z).length() <= p_still_speed;
	const int frame = (int)Engine::get_singleton()->get_physics_frames();
	landed_ = landed_ && frame - last_frame <= 2; // a new landing starts over
	last_frame = frame;
	landed_ = still && (landed_ || shortfall(p_solves, p_states, p_normals) > 0.03);
	return landed_;
}

double FootIKV2StretchHoldNative::blend_walk(bool p_moving, double p_delta) {
	walk_ = move_toward_d(walk_, p_moving ? 1.0 : 0.0, p_delta * 6.0);
	return walk_;
}
