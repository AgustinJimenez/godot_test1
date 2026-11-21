#pragma once

// The pure part of actors/player/player_temp_walk.gd in native code: the state the chosen walk leaves behind (its ground speed, loop lengths), the
// walk-speed reference the body plays each clip against, which inputs turn the body, and the two clip edits (making a clip in place, turning the hips).
// The script keeps only the loading and retargeting of the Mixamo / ALS clips (HumanoidRetargeter and the action-pack helper are GDScript).

#include <godot_cpp/classes/animation.hpp>
#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/classes/skeleton3d.hpp>
#include <godot_cpp/variant/string_name.hpp>
#include <godot_cpp/variant/vector2.hpp>

#include <map>

namespace godot {

class PlayerTempWalkNative : public RefCounted {
	GDCLASS(PlayerTempWalkNative, RefCounted)

protected:
	static void _bind_methods();

public:
	// The Mixamo walk plays at this fraction of its matching speed (the user's pick).
	static constexpr double PLAYBACK_SCALE = 0.575;

	// State, set by the script as it builds the clips.
	static void set_clip_speed(double p_speed);
	static double get_clip_speed();
	static void set_forward_length(double p_length);
	static void set_clip_length(const StringName &p_clip, double p_length);

	// The ground speed (m/s at 1x) a walk clip is played against: the forward clip's own, a sideways clip gets the forward step rate; `p_fallback`
	// when no experiment clip is in play (a headless run keeps the real walk).
	static double ref_speed(const StringName &p_target, double p_fallback);
	static double sprint_ref(double p_default);

	// W, W+A, W+D and the back diagonals (S+A, S+D) turn the body; plain S and A / D alone keep it facing the camera.
	static bool turns_body(const Vector2 &p_input);
	static bool back_diagonal(const Vector2 &p_input);
	// The body yaw offset for a travel angle: toward the travel for forward input, the opposite way round for the back diagonals.
	static double body_turn(const Vector2 &p_input, double p_travel_angle);

	// Removes the travel the clip accumulates along the two horizontal axes (the first position track), returns the speed it covered (m/s at 1x).
	static double in_place(const Ref<Animation> &p_clip, Skeleton3D *p_skeleton);
	// A copy of the clip with the hips turned `yaw` radians about the world up axis (+ = left).
	static Ref<Animation> yawed(const Ref<Animation> &p_clip, double p_yaw, Skeleton3D *p_skeleton, const StringName &p_hips_bone);

private:
	static double clip_speed;
	static double forward_length;
	static std::map<String, double> lengths;
};

} // namespace godot
