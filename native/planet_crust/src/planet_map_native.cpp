#include "planet_map_native.h"

#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/vector2.hpp>
#include <godot_cpp/variant/vector3.hpp>

#include <algorithm>
#include <cmath>
#include <vector>

using namespace godot;

namespace {
const double PI = 3.14159265358979323846;
struct Body {
	std::vector<int> members;
	bool sea;
	double area;
};
Vector3 direction(int p_cell, int p_width, int p_height) {
	const double lat = (0.5 - ((double)(p_cell / p_width) + 0.5) / p_height) * PI;
	const double lon = ((double)(p_cell % p_width) + 0.5) / p_width * 2.0 * PI - PI;
	return Vector3(std::cos(lat) * std::cos(lon), std::sin(lat), std::cos(lat) * std::sin(lon));
}
}

void PlanetMapNative::_bind_methods() {
	ClassDB::bind_method(D_METHOD("regions", "heights", "width", "height", "min_area", "max_per_kind"),
			&PlanetMapNative::regions);
}

Array PlanetMapNative::regions(const PackedFloat32Array &p_heights, int p_width, int p_height,
		double p_min_area, int p_max_per_kind) const {
	Array out;
	const int size = p_width * p_height;
	if (p_width <= 0 || p_height <= 0 || p_heights.size() < size) return out;
	std::vector<uint8_t> seen(size, 0);
	std::vector<Body> found;
	std::vector<int> stack;
	for (int start = 0; start < size; start++) {
		if (seen[start]) continue;
		Body body;
		body.sea = p_heights[start] < 0.0f;
		body.area = 0.0;
		stack.push_back(start);
		seen[start] = 1;
		while (!stack.empty()) {
			const int at = stack.back();
			stack.pop_back();
			body.members.push_back(at);
			const int row = at / p_width, col = at % p_width;
			const int nearby[4] = {row * p_width + (col + 1) % p_width,
					row * p_width + (col + p_width - 1) % p_width,
					(row + 1) * p_width + col, (row - 1) * p_width + col};
			for (int n = 0; n < 4; n++) {
				if ((n == 2 && row + 1 >= p_height) || (n == 3 && row == 0)) continue;
				const int next = nearby[n];
				if (!seen[next] && (p_heights[next] < 0.0f) == body.sea) {
					seen[next] = 1;
					stack.push_back(next);
				}
			}
		}
		for (int member : body.members) {
			body.area += std::cos((0.5 - ((double)(member / p_width) + 0.5) / p_height) * PI);
		}
		found.push_back(std::move(body));
	}
	std::stable_sort(found.begin(), found.end(), [](const Body &a, const Body &b) { return a.area > b.area; });
	int seas = 0, lands = 0;
	for (const Body &body : found) {
		if (body.area < p_min_area || (body.sea ? seas : lands) >= p_max_per_kind) continue;
		Vector3 sum;
		for (int member : body.members) sum += direction(member, p_width, p_height);
		const Vector3 centre = sum.length() > 0.001 ? sum.normalized() : Vector3(1, 0, 0);
		int best = body.members[0];
		double best_dot = -2.0;
		for (int member : body.members) {
			const double dot = direction(member, p_width, p_height).dot(centre);
			if (dot > best_dot) {
				best_dot = dot;
				best = member;
			}
		}
		Dictionary item;
		item["sea"] = body.sea;
		item["area"] = body.area;
		item["uv"] = Vector2(((double)(best % p_width) + 0.5) / p_width,
				((double)(best / p_width) + 0.5) / p_height);
		out.append(item);
		if (body.sea) seas++; else lands++;
	}
	return out;
}
