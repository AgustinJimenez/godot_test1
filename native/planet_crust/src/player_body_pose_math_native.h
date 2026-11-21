#pragma once

// The three functions of actors/player/player_body_pose_math.gd that PlayerBody's clip baking uses, in native code (they run per bone per sample while
// the clips are retargeted at load). Pure: they only read their parameters. The script's other four (a FABRIK solver, a key setter, two skeleton
// measures) had no callers and are gone.

#include <godot_cpp/classes/animation.hpp>
#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/classes/skeleton3d.hpp>
#include <godot_cpp/variant/basis.hpp>
#include <godot_cpp/variant/string_name.hpp>
#include <godot_cpp/variant/transform3d.hpp>
#include <godot_cpp/variant/vector3.hpp>

namespace godot {

class PlayerBodyPoseMathNative : public RefCounted {
	GDCLASS(PlayerBodyPoseMathNative, RefCounted)

protected:
	static void _bind_methods();

public:
	// A bone's GLOBAL pose composed from the LOCAL pose getters by walking the parent chain (Skeleton3D.get_bone_global_pose reads a cache that is
	// not refreshed while baking offline inside _ready()).
	static Transform3D manual_global_pose(Skeleton3D *p_skeleton, int64_t p_bone);
	// The shortest-arc rotation that takes `from` to `to` (both normalised).
	static Basis swing_between(const Vector3 &p_from, const Vector3 &p_to);
	// Adds a rotation track for `held_bone` holding the first key of the held pose for the whole clip.
	static void bake_held_track(const Ref<Animation> &p_anim, const StringName &p_held_bone, const Ref<Animation> &p_held_pose, double p_length);
};

} // namespace godot
