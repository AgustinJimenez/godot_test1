#include "plant_sway_native.h"

#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/basis.hpp>
#include <godot_cpp/variant/quaternion.hpp>
#include <godot_cpp/variant/vector3.hpp>

#include <algorithm>
#include <cmath>
#include <cstring>
#include <vector>

using namespace godot;

namespace {

const int TABLE_STRIDE = 10;
const int STATE_STRIDE = 6;

// the farthest a branch of this radius turns: twigs bend a lot, thick limbs hardly at all
double max_turn(double p_radius) {
	double turn = 0.025 / std::max(p_radius, 0.005);
	if (p_radius > 0.06) {
		turn *= 0.35;
	}
	return std::min(std::max(turn, 0.02), 1.2);
}

// how fast a branch springs back (rad/s): short and thick is quick, long and thin slow
double spring_rate(double p_radius, double p_length) {
	return std::min(std::max(60.0 * p_radius / std::max(p_length, 0.3) + 4.0, 4.0), 22.0);
}

Basis rotation_of(const Vector3 &p_vector) {
	const double angle = p_vector.length();
	if (angle < 1.0e-7) {
		return Basis();
	}
	return Basis(p_vector / (real_t)angle, (real_t)angle);
}

double clamp01(double p_value) {
	return std::min(std::max(p_value, 0.0), 1.0);
}

// the closest points of two segments (p1..q1 and p2..q2): the point on the first and the point on the second
void closest_points(const Vector3 &p1, const Vector3 &q1, const Vector3 &p2, const Vector3 &q2, Vector3 &r_on_first, Vector3 &r_on_second) {
	const Vector3 d1 = q1 - p1, d2 = q2 - p2, r = p1 - p2;
	const double a = d1.dot(d1), e = d2.dot(d2), f = d2.dot(r);
	double s = 0.0, t = 0.0;
	if (a <= 1.0e-9 && e <= 1.0e-9) {
		s = t = 0.0;
	} else if (a <= 1.0e-9) {
		t = clamp01(f / e);
	} else {
		const double c = d1.dot(r);
		if (e <= 1.0e-9) {
			s = clamp01(-c / a);
		} else {
			const double b = d1.dot(d2), denom = a * e - b * b;
			s = denom > 1.0e-9 ? clamp01((b * f - c * e) / denom) : 0.0;
			t = (b * s + f) / e;
			if (t < 0.0) {
				t = 0.0;
				s = clamp01(-c / a);
			} else if (t > 1.0) {
				t = 1.0;
				s = clamp01((b - c) / a);
			}
		}
	}
	r_on_first = p1 + d1 * (real_t)s;
	r_on_second = p2 + d2 * (real_t)t;
}

} // namespace

void PlantSwayNative::_bind_methods() {
	ClassDB::bind_method(D_METHOD("step", "table", "state", "body", "dt"), &PlantSwayNative::step);
	ClassDB::bind_method(D_METHOD("turns", "state"), &PlantSwayNative::turns);
	ClassDB::bind_method(D_METHOD("feet", "table"), &PlantSwayNative::feet);
	ClassDB::bind_method(D_METHOD("within", "buffer", "x", "z", "radius"), &PlantSwayNative::within);
}

Dictionary PlantSwayNative::step(const PackedFloat32Array &p_table, const PackedFloat32Array &p_state, const PackedFloat32Array &p_body, double p_dt) const {
	const int count = (int)(p_table.size() / TABLE_STRIDE);
	PackedFloat32Array state;
	state.resize((int64_t)count * STATE_STRIDE);
	if (p_state.size() == state.size() && count > 0) {
		memcpy(state.ptrw(), p_state.ptr(), (size_t)state.size() * sizeof(float));
	} else {
		state.fill(0.0f);
	}
	const float *table = p_table.ptr();
	float *st = state.ptrw();
	const bool body = p_body.size() >= 7;
	Vector3 body_a, body_b;
	double body_radius = 0.0;
	if (body) {
		body_a = Vector3(p_body[0], p_body[1], p_body[2]);
		body_b = Vector3(p_body[3], p_body[4], p_body[5]);
		body_radius = p_body[6];
	}
	// each branch's pose in the tree's space (an affine map: the turn about its foot after its parent's), made in the order of
	// the ids: a parent always comes before its branches
	std::vector<Basis> bases((size_t)std::max(count, 1));
	std::vector<Vector3> origins((size_t)std::max(count, 1), Vector3());
	bool awake = false;
	for (int id = 1; id < count; id++) {
		const float *row = table + id * TABLE_STRIDE;
		const int parent = std::min(std::max((int)row[0], 0), id - 1);
		const Vector3 foot(row[2], row[3], row[4]), tip(row[5], row[6], row[7]);
		const double radius = row[8], length = row[9];
		const Basis parent_basis = bases[(size_t)parent];
		const Vector3 parent_origin = origins[(size_t)parent];
		float *s = st + id * STATE_STRIDE;
		Vector3 turn(s[0], s[1], s[2]), rate(s[3], s[4], s[5]);
		const bool blade = row[1] > 8.5f; // a link of a blade or frond: ground plants give less than a tree's twigs
		const double limit = blade ? std::min(max_turn(radius), 0.45) : max_turn(radius);
		bool held = false; // resting against the body: it holds the branch where it is (the spring does not pull it back in)
		if (body) {
			// the pose before this step's turn is what the walker meets
			const Basis before = rotation_of(turn);
			const Vector3 origin = parent_basis.xform(foot - before.xform(foot)) + parent_origin;
			const Vector3 posed_foot = parent_basis.xform(foot) + parent_origin;
			const Vector3 posed_tip = (parent_basis * before).xform(tip) + origin;
			Vector3 on_body, on_branch;
			closest_points(body_a, body_b, posed_foot, posed_tip, on_body, on_branch);
			// (the leaves round a thin branch; a short link of a blade or frond has hardly any)
			const double reach = body_radius + radius + (blade ? 0.02 : (radius < 0.04 ? std::min(0.3, 0.5 * length + 0.02) : 0.05));
			const Vector3 apart = on_branch - on_body;
			const double distance = apart.length();
			held = distance < reach + 0.04;
			if (distance < reach) {
				const double depth = reach - distance;
				// the way to push is the side the branch's tip is on, not the side of the nearest point: a branch that passes
				// through the body would be pushed from one side and then the other on alternate steps
				Vector3 tip_on_body, tip_on_branch;
				closest_points(body_a, body_b, posed_tip, posed_tip, tip_on_body, tip_on_branch);
				Vector3 push = posed_tip - tip_on_body;
				if (push.length() < 1.0e-3f) {
					push = distance > 1.0e-4 ? apart : (posed_tip - posed_foot);
				}
				push = push.normalized();
				const Vector3 arm = on_branch - posed_foot;
				const double arm_length = std::max((double)arm.length(), 0.15);
				// the turn that carries the branch sideways, away from the body: about the axis across the branch and the push (a
				// branch pointing straight at the body or away from it has no sideways to turn to, and is left to its spring)
				Vector3 axis = (posed_tip - posed_foot).normalized().cross(push);
				const double sideways = axis.length();
				if (sideways > 0.25) {
					axis = parent_basis.inverse().xform(axis / (real_t)sideways); // (the turn is relative to the parent)
					// pushed out of the body, and held there: a contact only moves the branch out of the way (no kick on
					// each step: a walker standing still must leave the plants at rest, not shaking)
					const double angle = std::min(0.6 * depth / (arm_length * sideways), 0.4); // (a part of the way: it does not overshoot)
					// (turns compose: adding rotation vectors goes wrong once a branch is turned a long way)
					const Quaternion composed = (Basis(axis, (real_t)angle) * rotation_of(turn)).get_rotation_quaternion();
					turn = composed.get_axis() * composed.get_angle();
					rate = Vector3();
				}
			}
		}
		// the spring back
		const double w = spring_rate(radius, length);
		if (held) {
			rate = Vector3();
		} else {
			rate += (turn * (real_t)(-w * w) - rate * (real_t)(2.0 * 0.25 * w)) * (real_t)p_dt;
			turn += rate * (real_t)p_dt;
		}
		const double angle = turn.length();
		if (angle > limit) {
			turn *= (real_t)(limit / angle);
			const Vector3 along = turn / (real_t)limit;
			const double outward = rate.dot(along);
			if (outward > 0.0) {
				rate -= along * (real_t)outward;
			}
		}
		if (turn.length() > 0.003 || rate.length() > 0.02) {
			awake = true;
		} else {
			turn = Vector3();
			rate = Vector3();
		}
		s[0] = turn.x;
		s[1] = turn.y;
		s[2] = turn.z;
		s[3] = rate.x;
		s[4] = rate.y;
		s[5] = rate.z;
		const Basis own = rotation_of(turn);
		bases[(size_t)id] = parent_basis * own;
		origins[(size_t)id] = parent_basis.xform(foot - own.xform(foot)) + parent_origin;
	}
	Dictionary result;
	result["state"] = state;
	result["awake"] = awake || body;
	return result;
}

PackedFloat32Array PlantSwayNative::turns(const PackedFloat32Array &p_state) const {
	const int count = (int)(p_state.size() / STATE_STRIDE);
	PackedFloat32Array out;
	out.resize((int64_t)count * 4);
	for (int id = 0; id < count; id++) {
		out[(int64_t)id * 4] = p_state[(int64_t)id * STATE_STRIDE];
		out[(int64_t)id * 4 + 1] = p_state[(int64_t)id * STATE_STRIDE + 1];
		out[(int64_t)id * 4 + 2] = p_state[(int64_t)id * STATE_STRIDE + 2];
		out[(int64_t)id * 4 + 3] = 0.0f;
	}
	return out;
}

PackedFloat32Array PlantSwayNative::feet(const PackedFloat32Array &p_table) const {
	const int count = (int)(p_table.size() / TABLE_STRIDE);
	PackedFloat32Array out;
	out.resize((int64_t)count * 4);
	for (int id = 0; id < count; id++) {
		const float *row = p_table.ptr() + id * TABLE_STRIDE;
		out[(int64_t)id * 4] = row[2];
		out[(int64_t)id * 4 + 1] = row[3];
		out[(int64_t)id * 4 + 2] = row[4];
		out[(int64_t)id * 4 + 3] = row[0];
	}
	return out;
}

PackedInt32Array PlantSwayNative::within(const PackedFloat32Array &p_buffer, double p_x, double p_z, double p_radius) const {
	PackedInt32Array found;
	const int count = (int)(p_buffer.size() / 16);
	const double limit = p_radius * p_radius;
	for (int i = 0; i < count; i++) {
		const double dx = p_buffer[(int64_t)i * 16 + 3] - p_x, dz = p_buffer[(int64_t)i * 16 + 11] - p_z;
		if (dx * dx + dz * dz < limit) {
			found.push_back(i);
		}
	}
	return found;
}
