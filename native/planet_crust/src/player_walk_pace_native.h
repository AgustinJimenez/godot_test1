#pragma once

// The walk pace of the Player in native code (it was a block in player.gd): the walk slows progressively with the uphill gradient under the feet (eased),
// the stair slowdown is an on/off switch (easing it made the stairs' IK jerk twice as large, AGENT_TASKS/098), and the walk clip's playback scale follows
// the ground speed that results. Called once per physics frame by player.gd.

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/packed_float64_array.hpp>
#include <godot_cpp/variant/vector3.hpp>

namespace godot {

class PlayerWalkPaceNative : public RefCounted {
	GDCLASS(PlayerWalkPaceNative, RefCounted)

	double uphill_scale = 1.0; // walk-speed multiplier from the uphill gradient, eased

protected:
	static void _bind_methods();

public:
	// Returns [ground speed, clip playback scale]. `wish` is the walking direction in world space (zero when there is no input), `floor_normal` the floor
	// under the feet, `stair_scale` the stair slowdown multiplier (player.gd's stair_walk_speed_scale).
	PackedFloat64Array pace(double p_speed, bool p_walking_pace, bool p_on_stairs, bool p_on_floor, const Vector3 &p_floor_normal, const Vector3 &p_wish, double p_delta, double p_stair_scale);
	double get_uphill_scale() const { return uphill_scale; }
};

} // namespace godot
