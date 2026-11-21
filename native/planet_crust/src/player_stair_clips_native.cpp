#include "player_stair_clips_native.h"

#include <godot_cpp/classes/animation.hpp>
#include <godot_cpp/classes/animation_player.hpp>
#include <godot_cpp/classes/collision_object3d.hpp>
#include <godot_cpp/classes/physics_direct_space_state3d.hpp>
#include <godot_cpp/classes/physics_ray_query_parameters3d.hpp>
#include <godot_cpp/classes/world3d.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/core/math.hpp>
#include <godot_cpp/variant/typed_array.hpp>

#include <algorithm>
#include <cmath>

using namespace godot;

namespace {
// Ground distance the authored clip itself covers per second at 1x playback (0.467 m per 1.183 s cycle: 2 steps of ~0.23 m).
const double REF_SPEED = 0.395;
} // namespace

void PlayerStairClipsNative::_bind_methods() {
	ClassDB::bind_static_method("PlayerStairClipsNative", D_METHOD("on_staircase", "body"), &PlayerStairClipsNative::on_staircase);
	ClassDB::bind_static_method("PlayerStairClipsNative", D_METHOD("select_walk", "body", "base", "descending"), &PlayerStairClipsNative::select_walk);
	ClassDB::bind_static_method("PlayerStairClipsNative", D_METHOD("is_stair_target", "target"), &PlayerStairClipsNative::is_stair_target);
	ClassDB::bind_static_method("PlayerStairClipsNative", D_METHOD("walk_rate", "target", "ground_speed", "fallback"), &PlayerStairClipsNative::walk_rate);
	ClassDB::bind_static_method("PlayerStairClipsNative", D_METHOD("clamp_rate", "body", "target", "rate"), &PlayerStairClipsNative::clamp_rate);
}

bool PlayerStairClipsNative::on_staircase(Node3D *p_body) {
	if (p_body == nullptr || !p_body->is_inside_tree()) {
		return false;
	}
	Ref<World3D> world = p_body->get_world_3d();
	PhysicsDirectSpaceState3D *space = world.is_valid() ? world->get_direct_space_state() : nullptr;
	if (space == nullptr) {
		return false;
	}
	const Vector3 at = p_body->get_global_position();
	Ref<PhysicsRayQueryParameters3D> query = PhysicsRayQueryParameters3D::create(at + Vector3(0, 1, 0) * (real_t)0.3, at - Vector3(0, 1, 0) * (real_t)1.2);
	query->set_collision_mask(STAIR_CONTACT_LAYER);
	CollisionObject3D *collider = Object::cast_to<CollisionObject3D>(p_body);
	if (collider != nullptr) {
		TypedArray<RID> exclude;
		exclude.push_back(collider->get_rid());
		query->set_exclude(exclude);
	}
	return !space->intersect_ray(query).is_empty();
}

StringName PlayerStairClipsNative::select_walk(Node3D *p_body, const StringName &p_base, bool p_descending) {
	if (p_base != StringName("unarmed_walk") || !on_staircase(p_body)) {
		return p_base;
	}
	return p_descending ? StringName("unarmed_stair_down") : StringName("unarmed_stair_up");
}

bool PlayerStairClipsNative::is_stair_target(const StringName &p_target) {
	return p_target == StringName("unarmed_stair_up") || p_target == StringName("unarmed_stair_down");
}

double PlayerStairClipsNative::walk_rate(const StringName &p_target, double p_ground_speed, double p_fallback) {
	return is_stair_target(p_target) ? p_ground_speed / REF_SPEED : p_fallback;
}

double PlayerStairClipsNative::clamp_rate(Object *p_body, const StringName &p_target, double p_rate) {
	if (p_body == nullptr) {
		return p_rate;
	}
	AnimationPlayer *player = Object::cast_to<AnimationPlayer>((Object *)p_body->get("anim_player"));
	const double scale = (double)p_body->get("locomotion_playback_scale");
	double factor = 1.0;
	const bool walk_clip = p_target == StringName("unarmed_walk") || p_target == StringName("unarmed_walk_left") || p_target == StringName("unarmed_walk_right");
	if (!Math::is_equal_approx(scale, 1.0) && walk_clip && player != nullptr) {
		const StringName clip = StringName(String("moves/") + String(p_target));
		const StringName forward = StringName("moves/unarmed_walk");
		if (player->has_animation(clip) && player->has_animation(forward)) {
			factor = (double)player->get_animation(clip)->get_length() / (double)player->get_animation(forward)->get_length();
			const double match = (double)p_body->get("stair_cadence_match");
			factor = 1.0 + (factor - 1.0) * match;
		}
	}
	const double low = 0.8 * scale * factor;
	const double high = 2.2 * scale * factor;
	const double sign = p_rate > 0.0 ? 1.0 : (p_rate < 0.0 ? -1.0 : 0.0);
	return sign * std::clamp(std::abs(p_rate), low, high);
}
