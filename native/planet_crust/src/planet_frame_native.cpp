#include "planet_frame_native.h"

#include <godot_cpp/variant/quaternion.hpp>

#include <cmath>

using namespace godot;

static const double TAU_D = 6.283185307179586476925286766559;

static double positive_mod(double p_x, double p_y) {
	double value = std::fmod(p_x, p_y);
	if ((value < 0.0 && p_y > 0.0) || (value > 0.0 && p_y < 0.0)) {
		value += p_y;
	}
	return value;
}

PlanetFrame::PlanetFrame() {
	anchor.resize(3);
	anchor.fill(0.0);
}

void PlanetFrame::_bind_methods() {
	NP_BIND(PlanetFrame, Variant::BASIS, rot)
	NP_BIND(PlanetFrame, Variant::PACKED_FLOAT64_ARRAY, anchor)
	NP_BIND(PlanetFrame, Variant::VECTOR3, origin_w)
	ClassDB::bind_method(D_METHOD("start", "planet_position", "world_position"), &PlanetFrame::start);
	ClassDB::bind_method(D_METHOD("to_planet", "world_position"), &PlanetFrame::to_planet);
	ClassDB::bind_method(D_METHOD("to_world", "planet_position"), &PlanetFrame::to_world);
	ClassDB::bind_method(D_METHOD("rebase", "world_position"), &PlanetFrame::rebase);
	ClassDB::bind_method(D_METHOD("shift", "delta"), &PlanetFrame::shift);
	ClassDB::bind_method(D_METHOD("planet_to_world"), &PlanetFrame::planet_to_world);
	ClassDB::bind_method(D_METHOD("anchor_from_world"), &PlanetFrame::anchor_from_world);
	ClassDB::bind_method(D_METHOD("anchor_wrap"), &PlanetFrame::anchor_wrap);
	ClassDB::bind_method(D_METHOD("anchor_up"), &PlanetFrame::anchor_up);
	ClassDB::bind_method(D_METHOD("anchor_phase"), &PlanetFrame::anchor_phase);
	ClassDB::bind_method(D_METHOD("tile_transform", "tile"), &PlanetFrame::tile_transform);
}

Vector3 PlanetFrame::unit_of(const PackedFloat64Array &p_position) const {
	double length = std::sqrt(p_position[0] * p_position[0] + p_position[1] * p_position[1] + p_position[2] * p_position[2]);
	return Vector3(p_position[0] / length, p_position[1] / length, p_position[2] / length);
}

// Starts with the player at `world_position`, standing at `planet_position` of the planet.
void PlanetFrame::start(const PackedFloat64Array &p_planet_position, const Vector3 &p_world_position) {
	anchor = p_planet_position;
	origin_w = p_world_position;
	rot = Basis(Quaternion(unit_of(anchor), Vector3(0, 1, 0)));
}

// The planet space position of a world position (doubles).
PackedFloat64Array PlanetFrame::to_planet(const Vector3 &p_world_position) const {
	Vector3 offset = rot.inverse().xform(p_world_position - origin_w);
	PackedFloat64Array result;
	result.resize(3);
	result[0] = anchor[0] + offset.x;
	result[1] = anchor[1] + offset.y;
	result[2] = anchor[2] + offset.z;
	return result;
}

// The world position of a planet space position.
Vector3 PlanetFrame::to_world(const Vector3 &p_planet_position) const {
	Vector3 offset(p_planet_position.x - anchor[0], p_planet_position.y - anchor[1], p_planet_position.z - anchor[2]);
	return rot.xform(offset) + origin_w;
}

// Turns the planet about the player's feet so the ground there is level, and makes the player's spot the new anchor.
void PlanetFrame::rebase(const Vector3 &p_world_position) {
	anchor = to_planet(p_world_position);
	origin_w = p_world_position;
	Vector3 up = rot.xform(unit_of(anchor));
	rot = (Basis(Quaternion(up.normalized(), Vector3(0, 1, 0))) * rot).orthonormalized();
}

// Moves the whole world by `delta` (keeps the player's coordinates small on a long walk).
void PlanetFrame::shift(const Vector3 &p_delta) {
	origin_w += p_delta;
}

// The planet space -> world transform, for the ground shader's detail noise.
Transform3D PlanetFrame::planet_to_world() const {
	Vector3 offset(anchor[0], anchor[1], anchor[2]);
	return Transform3D(rot, origin_w - rot.xform(offset));
}

Transform3D PlanetFrame::anchor_from_world() const {
	Basis back = rot.inverse();
	return Transform3D(back, -back.xform(origin_w));
}

Vector3 PlanetFrame::anchor_wrap() const {
	return Vector3(positive_mod(anchor[0], NOISE_PERIOD), positive_mod(anchor[1], NOISE_PERIOD), positive_mod(anchor[2], NOISE_PERIOD));
}

Vector3 PlanetFrame::anchor_up() const {
	return unit_of(anchor);
}

double PlanetFrame::anchor_phase() const {
	double length = std::sqrt(anchor[0] * anchor[0] + anchor[1] * anchor[1] + anchor[2] * anchor[2]);
	return positive_mod(length * LAYER_RATE, TAU_D);
}

Transform3D PlanetFrame::tile_transform(Object *p_tile) const {
	PackedFloat64Array origin = p_tile->get("origin");
	Basis local_basis = p_tile->get("local_basis");
	Vector3 offset(origin[0] - anchor[0], origin[1] - anchor[1], origin[2] - anchor[2]);
	return Transform3D(rot * local_basis, rot.xform(offset) + origin_w);
}
