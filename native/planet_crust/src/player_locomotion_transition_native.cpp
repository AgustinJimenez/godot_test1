#include "player_locomotion_transition_native.h"

#include <godot_cpp/classes/animation.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/core/math.hpp>

using namespace godot;

namespace {
// Clips that share a gait cycle share a group: -1 for a clip with none.
int gait_group(const StringName &p_clip) {
	static const struct {
		const char *name;
		int group;
	} GROUPS[] = {
		{ "moves/unarmed_walk", 0 }, { "moves/unarmed_stair_up", 0 }, { "moves/unarmed_stair_down", 0 }, { "moves/unarmed_sprint", 0 },
		{ "moves/unarmed_crouch_walk", 0 }, { "moves/unarmed_crouch_left", 1 }, { "moves/unarmed_crouch_right", 1 },
		{ "moves/unarmed_walk_left", 2 }, { "moves/unarmed_walk_right", 2 }, { "moves/unarmed_walk_fwd_left", 2 }, { "moves/unarmed_walk_fwd_right", 2 },
	};
	for (const auto &entry : GROUPS) {
		if (p_clip == StringName(entry.name)) {
			return entry.group;
		}
	}
	return -1;
}
} // namespace

void PlayerLocomotionTransitionNative::_bind_methods() {
	ClassDB::bind_static_method("PlayerLocomotionTransitionNative", D_METHOD("play", "player", "target", "blend_time"), &PlayerLocomotionTransitionNative::play);
}

void PlayerLocomotionTransitionNative::play(AnimationPlayer *p_player, const StringName &p_target, double p_blend_time) {
	if (p_player == nullptr) {
		return;
	}
	const StringName full = StringName(String("moves/") + String(p_target));
	if (p_player->get_current_animation() == String(full) || !p_player->has_animation(full)) {
		return;
	}
	const StringName from = StringName(p_player->get_current_animation());
	const int from_group = gait_group(from);
	const int to_group = gait_group(full);
	if (from_group >= 0 && from_group == to_group) {
		// the same gait group: start the new clip at the same normalised phase
		const double from_length = p_player->get_current_animation_length();
		const double from_position = p_player->get_current_animation_position();
		const double to_length = (double)p_player->get_animation(full)->get_length();
		p_player->play(full, p_blend_time);
		if (from_length > 0.0 && to_length > 0.0) {
			p_player->seek(Math::fposmod(from_position / from_length, 1.0) * to_length, true);
		}
		return;
	}
	p_player->play(full, p_blend_time);
}
