#pragma once

// Stateful stair traversal helper for the real Player CharacterBody3D, in native code (a port of actors/player/player_stair_controller.gd, which it
// replaced). It probes and applies stair transitions on that body; it is not a second physics node and does not own ordinary move_and_slide().
// player.gd calls it every physics frame: begin_frame, apply_step_up / apply_step_down, record_presentation_delta, update_presentation.

#include <godot_cpp/classes/character_body3d.hpp>
#include <godot_cpp/classes/kinematic_collision3d.hpp>
#include <godot_cpp/classes/node3d.hpp>
#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/transform3d.hpp>
#include <godot_cpp/variant/vector3.hpp>

#include <limits>

namespace godot {

class PlayerStairControllerNative : public RefCounted {
	GDCLASS(PlayerStairControllerNative, RefCounted)

	struct Tread {
		bool valid = false;
		double y = 0.0, rise = 0.0;
		Vector3 contact;
	};

	static constexpr double NO_VALUE = std::numeric_limits<double>::infinity();

	double hover_offset_y = 0.0, balance_offset_y = 0.0, camera_snap_y = 0.0;
	bool consumed_horizontal_motion = false, continuous_traversal_active = false;

	uint64_t host_id = 0, body_id = 0, arm_id = 0;
	double body_rest_y = 0.0, arm_rest_y = 0.0;
	double climb_start_y = -NO_VALUE, climb_target_y = -NO_VALUE, climb_duration = 0.0, climb_elapsed = 0.0, climb_acceleration_time = 0.0, climb_peak_speed = 0.0;
	bool climb_active = false;
	double last_tread_y = -NO_VALUE;
	Vector3 last_contact = Vector3(NO_VALUE, NO_VALUE, NO_VALUE);
	double pending_step_down_y = -NO_VALUE;
	bool balance_active = false;
	double balance_smoothed_root_y = 0.0, balance_strength = 0.0, balance_limit = 0.0;

	CharacterBody3D *host() const;
	Node3D *node(uint64_t p_id) const;
	Dictionary ray(const Vector3 &p_from, const Vector3 &p_to, uint32_t p_mask, bool p_bodies_only) const;
	bool uses_continuous_traversal(const Ref<KinematicCollision3D> &p_collision) const;
	double continue_step_climb(const Vector3 &p_motion, double p_delta);
	void clear_climb();
	Tread find_step_up_tread(const Vector3 &p_motion, const Ref<KinematicCollision3D> &p_wall, double p_step_height) const;
	Tread find_step_down_tread(const Vector3 &p_motion, double p_step_height) const;
	bool has_continuous_floor_contact() const;
	void apply_presentation_offsets();

protected:
	static void _bind_methods();

public:
	void setup(CharacterBody3D *p_host, Node3D *p_body, Node3D *p_third_person_arm);
	void begin_frame();
	bool is_climbing() const { return climb_active; }
	bool has_recent_transition() const;
	bool is_near_stairs() const;
	Dictionary get_debug_state() const;
	double get_body_rest_y() const { return body_rest_y; }
	double apply_step_up(const Vector3 &p_motion, double p_delta, double p_step_height, double p_step_rise_rate);
	double apply_step_down(const Vector3 &p_motion, double p_delta, double p_step_height, double p_step_fall_rate, double p_jump_velocity_threshold);
	bool is_short_step_down(double p_frame_start_y, const Vector3 &p_horizontal_motion, double p_step_height, double p_jump_velocity_threshold) const;
	void record_presentation_delta(double p_delta_y, double p_step_height, double p_balance_strength, double p_balance_limit);
	void update_presentation(double p_delta, double p_hover_speed);
	void reset();

	double get_hover_offset_y() const { return hover_offset_y; }
	void set_hover_offset_y(double p_value) { hover_offset_y = p_value; }
	double get_balance_offset_y() const { return balance_offset_y; }
	void set_balance_offset_y(double p_value) { balance_offset_y = p_value; }
	double get_camera_snap_y() const { return camera_snap_y; }
	void set_camera_snap_y(double p_value) { camera_snap_y = p_value; }
	bool get_consumed_horizontal_motion() const { return consumed_horizontal_motion; }
	void set_consumed_horizontal_motion(bool p_value) { consumed_horizontal_motion = p_value; }
	bool get_continuous_traversal_active() const { return continuous_traversal_active; }
	void set_continuous_traversal_active(bool p_value) { continuous_traversal_active = p_value; }
};

} // namespace godot
