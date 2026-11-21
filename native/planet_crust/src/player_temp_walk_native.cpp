#include "player_temp_walk_native.h"

#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/core/math.hpp>
#include <godot_cpp/variant/basis.hpp>
#include <godot_cpp/variant/node_path.hpp>
#include <godot_cpp/variant/quaternion.hpp>
#include <godot_cpp/variant/transform3d.hpp>
#include <godot_cpp/variant/vector3.hpp>

#include <cmath>

using namespace godot;

double PlayerTempWalkNative::clip_speed = 0.0;
double PlayerTempWalkNative::forward_length = 1.3333;
std::map<String, double> PlayerTempWalkNative::lengths;

void PlayerTempWalkNative::_bind_methods() {
	ClassDB::bind_static_method("PlayerTempWalkNative", D_METHOD("set_clip_speed", "speed"), &PlayerTempWalkNative::set_clip_speed);
	ClassDB::bind_static_method("PlayerTempWalkNative", D_METHOD("get_clip_speed"), &PlayerTempWalkNative::get_clip_speed);
	ClassDB::bind_static_method("PlayerTempWalkNative", D_METHOD("set_forward_length", "length"), &PlayerTempWalkNative::set_forward_length);
	ClassDB::bind_static_method("PlayerTempWalkNative", D_METHOD("set_clip_length", "clip", "length"), &PlayerTempWalkNative::set_clip_length);
	ClassDB::bind_static_method("PlayerTempWalkNative", D_METHOD("ref_speed", "target", "fallback"), &PlayerTempWalkNative::ref_speed);
	ClassDB::bind_static_method("PlayerTempWalkNative", D_METHOD("sprint_ref", "default"), &PlayerTempWalkNative::sprint_ref);
	ClassDB::bind_static_method("PlayerTempWalkNative", D_METHOD("turns_body", "input"), &PlayerTempWalkNative::turns_body);
	ClassDB::bind_static_method("PlayerTempWalkNative", D_METHOD("back_diagonal", "input"), &PlayerTempWalkNative::back_diagonal);
	ClassDB::bind_static_method("PlayerTempWalkNative", D_METHOD("body_turn", "input", "travel_angle"), &PlayerTempWalkNative::body_turn);
	ClassDB::bind_static_method("PlayerTempWalkNative", D_METHOD("in_place", "clip", "skeleton"), &PlayerTempWalkNative::in_place);
	ClassDB::bind_static_method("PlayerTempWalkNative", D_METHOD("yawed", "clip", "yaw", "skeleton", "hips_bone"), &PlayerTempWalkNative::yawed);
}

void PlayerTempWalkNative::set_clip_speed(double p_speed) { clip_speed = p_speed; }
double PlayerTempWalkNative::get_clip_speed() { return clip_speed; }
void PlayerTempWalkNative::set_forward_length(double p_length) { forward_length = p_length; }
void PlayerTempWalkNative::set_clip_length(const StringName &p_clip, double p_length) { lengths[String(p_clip)] = p_length; }

double PlayerTempWalkNative::ref_speed(const StringName &p_target, double p_fallback) {
	const double forward = clip_speed > 0.1 ? clip_speed / PLAYBACK_SCALE : 0.0;
	if (p_target == StringName("unarmed_walk") && forward > 0.0) {
		return forward;
	}
	const auto it = lengths.find(String(p_target));
	if (it != lengths.end() && forward > 0.0) {
		return forward * forward_length / it->second;
	}
	return p_fallback;
}

// No GALS sprint is in use: the game's own reference stands.
double PlayerTempWalkNative::sprint_ref(double p_default) {
	return p_default;
}

bool PlayerTempWalkNative::back_diagonal(const Vector2 &p_input) {
	return p_input.y > 0.2f && std::abs(p_input.x) > 0.2f;
}

bool PlayerTempWalkNative::turns_body(const Vector2 &p_input) {
	return p_input.y < -0.2f || back_diagonal(p_input);
}

double PlayerTempWalkNative::body_turn(const Vector2 &p_input, double p_travel_angle) {
	if (p_input.y > 0.2f) {
		const double sign = p_travel_angle > 0.0 ? 1.0 : (p_travel_angle < 0.0 ? -1.0 : 0.0);
		return p_travel_angle - sign * Math_PI;
	}
	return p_travel_angle;
}

double PlayerTempWalkNative::in_place(const Ref<Animation> &p_clip, Skeleton3D *p_skeleton) {
	if (p_clip.is_null() || p_skeleton == nullptr) {
		return 0.0;
	}
	for (int track = 0; track < p_clip->get_track_count(); track++) {
		if (p_clip->track_get_type(track) != Animation::TYPE_POSITION_3D) {
			continue;
		}
		const int bone = p_skeleton->find_bone(String(p_clip->track_get_path(track).get_subname(0)));
		const int parent = bone >= 0 ? p_skeleton->get_bone_parent(bone) : -1;
		const Basis parent_basis = parent >= 0 ? p_skeleton->get_bone_global_rest(parent).basis : Basis();
		// the vertical axis of this rig's hips: the local axis that points most along world up
		int vertical = 0;
		real_t best = 0.0;
		for (int axis = 0; axis < 3; axis++) {
			Vector3 unit;
			unit[axis] = 1.0;
			const real_t up = std::abs(parent_basis.xform(unit).y);
			if (up > best) {
				best = up;
				vertical = axis;
			}
		}
		const int count = p_clip->track_get_key_count(track);
		const Vector3 first = p_clip->track_get_key_value(track, 0);
		const Vector3 last = p_clip->track_get_key_value(track, count - 1);
		Vector3 travel = last - first;
		travel[vertical] = 0.0;
		const double length = p_clip->get_length();
		for (int key = 0; key < count; key++) {
			const real_t progress = (real_t)(p_clip->track_get_key_time(track, key) / length);
			const Vector3 value = p_clip->track_get_key_value(track, key);
			p_clip->track_set_key_value(track, key, value - travel * progress);
		}
		return (double)travel.length() / length;
	}
	return 0.0;
}

Ref<Animation> PlayerTempWalkNative::yawed(const Ref<Animation> &p_clip, double p_yaw, Skeleton3D *p_skeleton, const StringName &p_hips_bone) {
	if (p_clip.is_null() || p_skeleton == nullptr) {
		return p_clip;
	}
	Ref<Animation> turned = p_clip->duplicate();
	const NodePath hips_path = NodePath(String(p_skeleton->get_name()) + ":" + String(p_hips_bone));
	// a bone's rotation is relative to its parent, and this rig's hips hang under a rotated `root`
	const int hips = p_skeleton->find_bone(String(p_hips_bone));
	const int parent = hips >= 0 ? p_skeleton->get_bone_parent(hips) : -1;
	const Basis parent_basis = parent >= 0 ? p_skeleton->get_bone_global_rest(parent).basis : Basis();
	const Vector3 up = parent_basis.inverse().xform(p_skeleton->get_global_transform().basis.inverse().xform(Vector3(0, 1, 0))).normalized();
	const Quaternion turn = Quaternion(up, (real_t)p_yaw);
	for (int track = 0; track < turned->get_track_count(); track++) {
		if (turned->track_get_type(track) != Animation::TYPE_ROTATION_3D || turned->track_get_path(track) != hips_path) {
			continue;
		}
		for (int key = 0; key < turned->track_get_key_count(track); key++) {
			const Quaternion rotation = turned->track_get_key_value(track, key);
			turned->track_set_key_value(track, key, turn * rotation);
		}
	}
	return turned;
}
