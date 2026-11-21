#pragma once

// actors/player/player_locomotion_transition.gd in native code: switching between looping locomotion clips keeps the corresponding gait phases
// aligned, so the feet do not snap across the switch (the flat walk <-> the stair walk <-> the sprint start the new clip at the same normalised phase).

#include <godot_cpp/classes/animation_player.hpp>
#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/string_name.hpp>

namespace godot {

class PlayerLocomotionTransitionNative : public RefCounted {
	GDCLASS(PlayerLocomotionTransitionNative, RefCounted)

protected:
	static void _bind_methods();

public:
	// Plays `moves/<target>` on the player with a crossfade of `blend_time`, phase-matched to the clip playing when both are in one gait group.
	static void play(AnimationPlayer *p_player, const StringName &p_target, double p_blend_time);
};

} // namespace godot
