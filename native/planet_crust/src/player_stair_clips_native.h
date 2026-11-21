#pragma once

// The pure logic of actors/player/player_stair_clips.gd in native code: whether the character is on an authored staircase (a ray onto the stair
// collision layer), which walk clip that earns, and the playback rate of a walk clip on the stairs. Static, no state. The retargeting of the stair
// clips onto the character stays in GDScript (it uses GDScript-only classes: PlayerBody, HumanoidRetargeter).

#include <godot_cpp/classes/node3d.hpp>
#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/string_name.hpp>

namespace godot {

class PlayerStairClipsNative : public RefCounted {
	GDCLASS(PlayerStairClipsNative, RefCounted)

protected:
	static void _bind_methods();

public:
	// FootIKStairSurfaces authors every stair tread / riser / traversal / landing collider on this layer.
	static constexpr uint32_t STAIR_CONTACT_LAYER = 1u << 5;

	// A ray straight down from the body onto the stair layer: true for the whole climb, the traversal ramp and the top landing.
	static bool on_staircase(Node3D *p_body);
	// The authored stair clip while on the staircase (only for the forward walk), else `base`.
	static StringName select_walk(Node3D *p_body, const StringName &p_base, bool p_descending);
	static bool is_stair_target(const StringName &p_target);
	// Playback rate: a stair clip plays against its own authored ground speed; everything else keeps `fallback`.
	static double walk_rate(const StringName &p_target, double p_ground_speed, double p_fallback);
	// Final playback rate of a locomotion clip: on the stairs it is clamped into a band scaled by the body's `locomotion_playback_scale` and (for the
	// flat walk clips) by the clip's loop length against the forward walk's, so every walk clip steps at the same rate.
	static double clamp_rate(Object *p_body, const StringName &p_target, double p_rate);
};

} // namespace godot
