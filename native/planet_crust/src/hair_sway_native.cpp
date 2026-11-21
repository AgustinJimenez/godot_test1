#include "hair_sway_native.h"

#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/core/math.hpp>
#include <godot_cpp/variant/basis.hpp>
#include <godot_cpp/variant/string_name.hpp>

#include <cmath>

namespace godot {

void HairSway::_bind_methods() {
	ClassDB::bind_method(D_METHOD("set_hair", "hair"), &HairSway::set_hair);
	ClassDB::bind_method(D_METHOD("get_hair"), &HairSway::get_hair);
	ClassDB::bind_method(D_METHOD("set_target", "target"), &HairSway::set_target);
	ClassDB::bind_method(D_METHOD("get_target"), &HairSway::get_target);
	ClassDB::bind_method(D_METHOD("set_stiffness", "value"), &HairSway::set_stiffness);
	ClassDB::bind_method(D_METHOD("get_stiffness"), &HairSway::get_stiffness);
	ClassDB::bind_method(D_METHOD("set_damping", "value"), &HairSway::set_damping);
	ClassDB::bind_method(D_METHOD("get_damping"), &HairSway::get_damping);
	ClassDB::bind_method(D_METHOD("set_acceleration_gain", "value"), &HairSway::set_acceleration_gain);
	ClassDB::bind_method(D_METHOD("get_acceleration_gain"), &HairSway::get_acceleration_gain);
	ClassDB::bind_method(D_METHOD("set_turn_gain", "value"), &HairSway::set_turn_gain);
	ClassDB::bind_method(D_METHOD("get_turn_gain"), &HairSway::get_turn_gain);
	ClassDB::bind_method(D_METHOD("set_max_swing", "value"), &HairSway::set_max_swing);
	ClassDB::bind_method(D_METHOD("get_max_swing"), &HairSway::get_max_swing);
	ClassDB::bind_method(D_METHOD("set_forward", "value"), &HairSway::set_forward);
	ClassDB::bind_method(D_METHOD("get_forward"), &HairSway::get_forward);
	ClassDB::bind_method(D_METHOD("get_offset"), &HairSway::get_offset);
	ClassDB::bind_method(D_METHOD("kick", "impulse"), &HairSway::kick);

	ADD_PROPERTY(PropertyInfo(Variant::OBJECT, "hair", PROPERTY_HINT_NODE_TYPE, "GeometryInstance3D"), "set_hair", "get_hair");
	ADD_PROPERTY(PropertyInfo(Variant::OBJECT, "target", PROPERTY_HINT_NODE_TYPE, "Node3D"), "set_target", "get_target");
	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "stiffness"), "set_stiffness", "get_stiffness");
	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "damping"), "set_damping", "get_damping");
	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "acceleration_gain"), "set_acceleration_gain", "get_acceleration_gain");
	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "turn_gain"), "set_turn_gain", "get_turn_gain");
	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "max_swing"), "set_max_swing", "get_max_swing");
	ADD_PROPERTY(PropertyInfo(Variant::VECTOR3, "forward"), "set_forward", "get_forward");
}

Object *HairSway::get_hair() const {
	return ObjectDB::get_instance(hair_id);
}

Object *HairSway::get_target() const {
	return ObjectDB::get_instance(target_id);
}

void HairSway::set_target(Object *p_target) {
	target_id = p_target != nullptr ? p_target->get_instance_id() : ObjectID();
	primed = false;
}

// Samples the character's movement in the physics frame: the true position, not the one the renderer interpolates between two physics frames (an
// acceleration taken from interpolated positions is noise at a render rate that is not a multiple of the physics rate).
void HairSway::_physics_process(double p_delta) {
	Node3D *target = Object::cast_to<Node3D>(get_target());
	if (p_delta <= 0.0 || target == nullptr || !target->is_inside_tree()) {
		return;
	}
	const Vector3 position = target->get_global_position();
	const double yaw = target->get_global_rotation().y;
	if (!primed) {
		last_position = position;
		last_yaw = yaw;
		last_yaw_rate = 0.0;
		last_speed = Vector3();
		primed = true;
		return;
	}
	const Vector3 speed = (position - last_position) / real_t(p_delta);
	const Vector3 acceleration = (speed - last_speed) / real_t(p_delta);
	// the hair lags behind: push it against the acceleration, in the hair's own space (the space the shader bends it in, whichever way the mesh faces)
	Node3D *hair = Object::cast_to<Node3D>(get_hair());
	const Basis space = hair != nullptr && hair->is_inside_tree() ? hair->get_global_basis() : target->get_global_basis();
	pending += space.inverse().xform(-acceleration) * real_t(acceleration_gain * p_delta * 60.0 * 0.1);
	// turning: the hair lags the head, so a turn that starts (or stops) kicks it sideways in the hair's own space, in proportion to the CHANGE of the turning speed (a steady
	// turn does not: the spring settles). The kick is toward the model's left for a positive yaw (the back of the head moves right, the hair stays behind), which for a mesh that
	// faces +Z is +X: `right` is the model's right, the kick goes against it.
	Vector3 right = forward.cross(Vector3(0.0f, 1.0f, 0.0f));
	if (right.length() < 1e-4f) {
		right = Vector3(1.0f, 0.0f, 0.0f);
	}
	const double yaw_rate = Math::wrapf(yaw - last_yaw, -Math_PI, Math_PI) / p_delta;
	pending -= right.normalized() * real_t((yaw_rate - last_yaw_rate) * turn_gain);
	last_yaw_rate = yaw_rate;
	last_position = position;
	last_speed = speed;
	last_yaw = yaw;
}

void HairSway::_process(double p_delta) {
	GeometryInstance3D *hair = Object::cast_to<GeometryInstance3D>(get_hair());
	if (p_delta <= 0.0 || hair == nullptr) {
		return;
	}
	velocity += pending;
	pending = Vector3();
	const real_t dt = real_t(p_delta);
	velocity += (-offset * real_t(stiffness) - velocity * real_t(damping)) * dt;
	offset += velocity * dt;
	if (offset.length() > real_t(max_swing)) {
		// at the limit: the hair stops there, and the part of its velocity that pushes further out is dropped (it used to pile up and hold the hair on the stop)
		const Vector3 out = offset.normalized();
		offset = out * real_t(max_swing);
		const real_t outward = velocity.dot(out);
		if (outward > 0.0f) {
			velocity -= out * outward;
		}
	}
	hair->set_instance_shader_parameter(StringName("sway"), offset);
}

} // namespace godot
