#pragma once

// HairSway (was components/hair_sway.gd): makes the head hair (shaders/human_hair.gdshader) swing with the character's movement.
//
// A damped spring in the hair mesh's own space: the character's acceleration and the change of its turning speed kick it (the hair lags the head), the spring pulls it back, and the hair shader bends each
// lock by the spring's offset, more toward the tips (the per-vertex work is on the GPU; this is one spring per character). The offset goes to the shader's
// `instance uniform vec3 sway` on the hair's mesh instance, so characters that share the hair material still swing on their own.
// Give it the hair's mesh instance (`hair`) and the node that moves (`target`: the character body, or the model it turns). Movement is sampled every physics
// frame (the true positions, not the interpolated ones), the spring runs every rendered frame.

#include <godot_cpp/classes/geometry_instance3d.hpp>
#include <godot_cpp/classes/node.hpp>
#include <godot_cpp/classes/node3d.hpp>
#include <godot_cpp/variant/vector3.hpp>

namespace godot {

class HairSway : public Node {
	GDCLASS(HairSway, Node)

	ObjectID hair_id;
	ObjectID target_id;
	double stiffness = 120.0; // how fast the spring pulls back (natural frequency squared)
	double damping = 5.5; // how quickly the swing dies down
	double acceleration_gain = 0.0045; // m/s of hair velocity per m/s of speed change, per 60 Hz tick (the kick is spread over ticks: see _physics_process)
	double turn_gain = 0.3; // m/s of hair velocity per rad/s of change of the turning speed (a turn that starts or stops kicks the hair; a steady turn does not)
	double max_swing = 0.07; // the most the hair may swing at the tips, in metres
	Vector3 forward = Vector3(0.0f, 0.0f, 1.0f); // the way the hair mesh faces in its own space (the humans' glb files face +Z; Godot actors face -Z)

	Vector3 offset;
	Vector3 velocity;
	Vector3 pending; // kicks sampled in the physics frame, added to the velocity in the next rendered one
	Vector3 last_position;
	Vector3 last_speed;
	double last_yaw = 0.0;
	double last_yaw_rate = 0.0;
	bool primed = false;

protected:
	static void _bind_methods();

public:
	void set_hair(Object *p_hair) { hair_id = p_hair != nullptr ? p_hair->get_instance_id() : ObjectID(); }
	Object *get_hair() const;
	void set_target(Object *p_target);
	Object *get_target() const;
	void set_stiffness(double p_value) { stiffness = p_value; }
	double get_stiffness() const { return stiffness; }
	void set_damping(double p_value) { damping = p_value; }
	double get_damping() const { return damping; }
	void set_acceleration_gain(double p_value) { acceleration_gain = p_value; }
	double get_acceleration_gain() const { return acceleration_gain; }
	void set_turn_gain(double p_value) { turn_gain = p_value; }
	double get_turn_gain() const { return turn_gain; }
	void set_max_swing(double p_value) { max_swing = p_value; }
	double get_max_swing() const { return max_swing; }
	void set_forward(const Vector3 &p_value) { forward = p_value; }
	Vector3 get_forward() const { return forward; }
	Vector3 get_offset() const { return offset; }

	// A push on the hair in the hair's own space (metres per second), for a shake or a hit.
	void kick(const Vector3 &p_impulse) { pending += p_impulse; }

	void _physics_process(double p_delta) override;
	void _process(double p_delta) override;
};

} // namespace godot
