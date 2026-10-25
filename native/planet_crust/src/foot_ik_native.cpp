#include "foot_ik_native.h"

#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/core/math.hpp>

#include <algorithm>
#include <vector>
#include <cmath>
#include <limits>

using namespace godot;

void FootIKV2Native::_bind_methods() {
	ClassDB::bind_method(D_METHOD("set_sole", "foot_weight", "toe_weight", "foot_local", "toe_local"), &FootIKV2Native::set_sole);
	ClassDB::bind_method(D_METHOD("get_count"), &FootIKV2Native::get_count);
	ClassDB::bind_method(D_METHOD("points", "foot_pose", "toe_pose"), &FootIKV2Native::points);
	ClassDB::bind_method(D_METHOD("level_points", "foot_pose", "toe_pose", "to_world", "band"), &FootIKV2Native::level_points);
	ClassDB::bind_method(D_METHOD("lowest_world_y", "foot_pose", "toe_pose", "to_world"), &FootIKV2Native::lowest_world_y);
	ClassDB::bind_static_method("FootIKV2Native", D_METHOD("min_gap", "space", "query", "level", "hip_y", "ray_up", "ray_down", "samples", "sink_max"), &FootIKV2Native::min_gap);
	ClassDB::bind_static_method("FootIKV2Native", D_METHOD("solve", "hip", "animated_knee", "target", "upper", "lower", "rest_pole", "max_flexion_deg", "max_swing_deg", "down", "bend_free"), &FootIKV2Native::solve);
}

void FootIKV2Native::set_sole(const PackedFloat32Array &p_foot_weight, const PackedFloat32Array &p_toe_weight,
		const PackedVector3Array &p_foot_local, const PackedVector3Array &p_toe_local) {
	foot_weight = p_foot_weight;
	toe_weight = p_toe_weight;
	foot_local = p_foot_local;
	toe_local = p_toe_local;
}

PackedVector3Array FootIKV2Native::points(const Transform3D &p_foot_pose, const Transform3D &p_toe_pose) const {
	const int n = foot_weight.size();
	PackedVector3Array out;
	out.resize(n);
	const Basis fb = p_foot_pose.basis;
	const Basis tb = p_toe_pose.basis;
	for (int i = 0; i < n; i++) {
		out.set(i, fb.xform(foot_local[i]) + p_foot_pose.origin * foot_weight[i] + tb.xform(toe_local[i]) + p_toe_pose.origin * toe_weight[i]);
	}
	return out;
}

PackedVector3Array FootIKV2Native::level_points(const Transform3D &p_foot_pose, const Transform3D &p_toe_pose, const Transform3D &p_to_world, double p_band) const {
	const PackedVector3Array local = points(p_foot_pose, p_toe_pose);
	const int n = local.size();
	const Basis b = p_to_world.basis;
	const Vector3 up(b.rows[1][0], b.rows[1][1], b.rows[1][2]); // the world-Y row: a point's world height is up.dot(p)
	std::vector<real_t> heights(n);
	real_t lowest = std::numeric_limits<real_t>::infinity();
	for (int i = 0; i < n; i++) {
		heights[i] = up.dot(local[i]);
		lowest = std::min(lowest, heights[i]);
	}
	PackedVector3Array level;
	for (int i = 0; i < n; i++) {
		if (heights[i] <= lowest + p_band) {
			level.push_back(p_to_world.xform(local[i]));
		}
	}
	return level;
}

double FootIKV2Native::lowest_world_y(const Transform3D &p_foot_pose, const Transform3D &p_toe_pose, const Transform3D &p_to_world) const {
	const PackedVector3Array local = points(p_foot_pose, p_toe_pose);
	real_t lowest = std::numeric_limits<real_t>::infinity();
	for (int i = 0; i < local.size(); i++) {
		lowest = std::min(lowest, p_to_world.xform(local[i]).y);
	}
	return lowest;
}

double FootIKV2Native::min_gap(PhysicsDirectSpaceState3D *p_space, const Ref<PhysicsRayQueryParameters3D> &p_query, const PackedVector3Array &p_level,
		double p_hip_y, double p_ray_up, double p_ray_down, int p_samples, double p_sink_max) {
	double gap = std::numeric_limits<double>::infinity();
	if (p_space == nullptr || p_query.is_null()) {
		return gap;
	}
	const int n = p_level.size();
	const int stride = std::max(1, n / std::max(1, p_samples));
	for (int i = 0; i < n; i += stride) {
		const Vector3 point = p_level[i];
		p_query->set_from(Vector3(point.x, (real_t)std::max(p_hip_y, (double)point.y + p_ray_up), point.z));
		p_query->set_to(point - Vector3(0, 1, 0) * (real_t)p_ray_down);
		const Dictionary hit = p_space->intersect_ray(p_query);
		if (hit.is_empty()) {
			continue;
		}
		const Vector3 position = hit["position"];
		const double below = (double)point.y - (double)position.y;
		if (below <= p_sink_max) {
			gap = std::min(gap, below);
		}
	}
	return gap;
}

static real_t smoothstep_real(real_t e0, real_t e1, real_t x) {
	const real_t t = Math::clamp((x - e0) / (e1 - e0), (real_t)0.0, (real_t)1.0);
	return t * t * (3 - 2 * t);
}

PackedVector3Array FootIKV2Native::solve(const Vector3 &p_hip, const Vector3 &p_animated_knee, const Vector3 &p_target, double p_upper,
		double p_lower, const Vector3 &p_rest_pole, double p_max_flexion_deg, double p_max_swing_deg, const Vector3 &p_down,
		double p_bend_free) {
	const double upper = p_upper, lower = p_lower;
	const Vector3 to_target = p_target - p_hip;
	double min_distance = std::abs(upper - lower) + 0.001;
	if (p_max_flexion_deg > 0.0) {
		const double interior = Math::deg_to_rad(180.0 - p_max_flexion_deg);
		min_distance = std::max(min_distance, std::sqrt(std::max(0.0, upper * upper + lower * lower - 2.0 * upper * lower * std::cos(interior))));
	}
	const double distance = Math::clamp((double)to_target.length(), min_distance, upper + lower - 0.001);
	const Vector3 direction = to_target.normalized();
	Vector3 pole = p_animated_knee - p_hip;
	pole -= direction * pole.dot(direction);
	// A knee never bends BACKWARD: blended toward the rest pole as the animated bend swings against it (see the GDScript).
	const Vector3 rest = (p_rest_pole - direction * p_rest_pole.dot(direction)).normalized();
	if (pole.length_squared() < 0.000001) {
		pole = rest;
	} else {
		pole = pole.normalized();
		const real_t edge_x = (real_t)(-0.3 + (-0.9 - -0.3) * p_bend_free);
		const real_t edge_y = (real_t)(0.5 + (-0.5 - 0.5) * p_bend_free);
		pole = rest.lerp(pole, smoothstep_real(edge_x, edge_y, pole.dot(rest))).normalized();
	}
	const double along = (upper * upper - lower * lower + distance * distance) / (2.0 * distance);
	const double outward = std::sqrt(std::max(0.0, upper * upper - along * along));
	Vector3 knee = p_hip + direction * (real_t)along + pole * (real_t)outward;
	const Vector3 thigh = (knee - p_hip) / (real_t)upper;
	if (p_max_swing_deg > 0.0 && p_down.angle_to(thigh) > Math::deg_to_rad(p_max_swing_deg)) {
		const Vector3 axis = p_down.cross(thigh);
		if (axis.length_squared() > 0.0001) {
			knee = p_hip + p_down.rotated(axis.normalized(), (real_t)Math::deg_to_rad(p_max_swing_deg)) * (real_t)upper;
		}
	}
	PackedVector3Array out;
	out.resize(5);
	out.set(0, knee);
	out.set(1, p_hip + direction * (real_t)distance);
	out.set(2, direction);
	out.set(3, pole);
	out.set(4, Vector3((real_t)distance, 0, 0));
	return out;
}
