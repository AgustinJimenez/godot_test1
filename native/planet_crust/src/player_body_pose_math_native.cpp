#include "player_body_pose_math_native.h"

#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/core/math.hpp>
#include <godot_cpp/variant/node_path.hpp>

using namespace godot;

void PlayerBodyPoseMathNative::_bind_methods() {
	ClassDB::bind_static_method("PlayerBodyPoseMathNative", D_METHOD("manual_global_pose", "skeleton", "bone"), &PlayerBodyPoseMathNative::manual_global_pose);
	ClassDB::bind_static_method("PlayerBodyPoseMathNative", D_METHOD("swing_between", "from", "to"), &PlayerBodyPoseMathNative::swing_between);
	ClassDB::bind_static_method("PlayerBodyPoseMathNative", D_METHOD("bake_held_track", "anim", "held_bone", "held_pose", "length"), &PlayerBodyPoseMathNative::bake_held_track);
}

Transform3D PlayerBodyPoseMathNative::manual_global_pose(Skeleton3D *p_skeleton, int64_t p_bone) {
	if (p_skeleton == nullptr) {
		return Transform3D();
	}
	Transform3D t = p_skeleton->get_bone_pose((int)p_bone);
	int parent = p_skeleton->get_bone_parent((int)p_bone);
	while (parent >= 0) {
		t = p_skeleton->get_bone_pose(parent) * t;
		parent = p_skeleton->get_bone_parent(parent);
	}
	return t;
}

Basis PlayerBodyPoseMathNative::swing_between(const Vector3 &p_from, const Vector3 &p_to) {
	const Vector3 axis = p_from.cross(p_to);
	const real_t len = axis.length();
	if (len < (real_t)0.0001) {
		if (p_from.dot(p_to) > 0.0f) {
			return Basis();
		}
		Vector3 perp = p_from.cross(Vector3(0, 1, 0));
		if (perp.length() < (real_t)0.0001) {
			perp = p_from.cross(Vector3(1, 0, 0));
		}
		return Basis(perp.normalized(), (real_t)Math_PI);
	}
	return Basis(axis / len, p_from.angle_to(p_to));
}

void PlayerBodyPoseMathNative::bake_held_track(const Ref<Animation> &p_anim, const StringName &p_held_bone, const Ref<Animation> &p_held_pose, double p_length) {
	if (p_anim.is_null() || p_held_pose.is_null()) {
		return;
	}
	for (int t = 0; t < p_held_pose->get_track_count(); t++) {
		const NodePath path = p_held_pose->track_get_path(t);
		if (path.get_subname_count() > 0 && StringName(path.get_subname(0)) == p_held_bone && p_held_pose->track_get_type(t) == Animation::TYPE_ROTATION_3D) {
			const Variant value = p_held_pose->track_get_key_value(t, 0);
			const int new_track = p_anim->add_track(Animation::TYPE_ROTATION_3D);
			p_anim->track_set_path(new_track, NodePath(String("Skeleton3D:") + String(p_held_bone)));
			p_anim->track_insert_key(new_track, 0.0, value);
			p_anim->track_insert_key(new_track, p_length, value);
			return;
		}
	}
}
