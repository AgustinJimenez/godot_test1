#pragma once

// The small state machines of Foot IK v2 in native code (AGENT_TASKS/091): the joint speed limiter, the foot stepper, the foot lock, the
// body height smoother, the floor height filter, the resting knee hint and the stretch hold. The same maths as the GDScript files of
// actors/player/foot_ik_v2/ (foot_ik_v2_joint_limiter.gd, _stepper.gd, _lock.gd, _body_smoother.gd, _ground_filter.gd, _knee_hint.gd,
// _stretch_hold.gd), which stay the reference; each GDScript file has a `create()` that returns the native object when the class exists.

#include <godot_cpp/classes/character_body3d.hpp>
#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/quaternion.hpp>
#include <godot_cpp/variant/string_name.hpp>
#include <godot_cpp/variant/vector3.hpp>

namespace godot {

class FootIKV2LimiterNative : public RefCounted {
	GDCLASS(FootIKV2LimiterNative, RefCounted)
	Dictionary previous; // bone -> Quaternion at the end of the last completed frame
	Dictionary latest; // bone -> Quaternion from the latest pass
	Dictionary frame_of; // bone -> physics frame of `latest`

protected:
	static void _bind_methods();

public:
	Quaternion limit(int p_bone, int p_frame, const Quaternion &p_correction, double p_max_deg);
};

class FootIKV2StepperNative : public RefCounted {
	GDCLASS(FootIKV2StepperNative, RefCounted)
	Dictionary stepping_;
	Dictionary frame_of, was_planted, start, last, length;

protected:
	static void _bind_methods();

public:
	Dictionary get_stepping() const { return stepping_; }
	Vector3 limit(const StringName &p_side, int p_frame, const Vector3 &p_here, bool p_planted);
};

class FootIKV2LockNative : public RefCounted {
	GDCLASS(FootIKV2LockNative, RefCounted)
	Dictionary anchor;

protected:
	static void _bind_methods();

public:
	Vector3 held(const StringName &p_side, const Vector3 &p_animated, const Vector3 &p_hip, bool p_resting);
};

class FootIKV2BodySmootherNative : public RefCounted {
	GDCLASS(FootIKV2BodySmootherNative, RefCounted)
	double y = 0.0, velocity = 0.0, last_target = 0.0;

protected:
	static void _bind_methods();

public:
	double reset(double p_target);
	double follow(double p_target, double p_delta, double p_position_rate, double p_max_lag);
};

class FootIKV2GroundFilterNative : public RefCounted {
	GDCLASS(FootIKV2GroundFilterNative, RefCounted)
	Dictionary state_, pending, raw_, frame_of;

protected:
	static void _bind_methods();

public:
	Dictionary get_state() const { return state_; }
	double height(const StringName &p_side, double p_raw);
	double resample(const StringName &p_side, double p_again_y);
};

class FootIKV2KneeHintNative : public RefCounted {
	GDCLASS(FootIKV2KneeHintNative, RefCounted)
	Dictionary direction;

protected:
	static void _bind_methods();

public:
	Vector3 steady(const StringName &p_side, const Vector3 &p_hip, const Vector3 &p_knee, double p_delta, double p_walk);
};

class FootIKV2StretchHoldNative : public RefCounted {
	GDCLASS(FootIKV2StretchHoldNative, RefCounted)
	double calm_ = 0.0, yaw_ = 0.0, walk_ = 0.0;
	bool landed_ = false;
	int last_frame = 0;

protected:
	static void _bind_methods();

public:
	double get_calm() const { return calm_; }
	void set_calm(double p_calm) { calm_ = p_calm; }
	bool get_landed() const { return landed_; }
	void set_landed(bool p_landed) { landed_ = p_landed; }
	double get_walk() const { return walk_; }
	void set_walk(double p_walk) { walk_ = p_walk; }
	double update(double p_hold, double p_drop, const Array &p_legs, bool p_stretched, double p_yaw, double p_delta);
	static double shortfall(const Dictionary &p_solves, const Dictionary &p_states, const Dictionary &p_normals);
	bool rests(CharacterBody3D *p_host, double p_still_speed, const Dictionary &p_solves, const Dictionary &p_states, const Dictionary &p_normals);
	double blend_walk(bool p_moving, double p_delta);
};

} // namespace godot
