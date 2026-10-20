#include "planet_water_native.h"

#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/color.hpp>
#include <godot_cpp/variant/packed_color_array.hpp>
#include <godot_cpp/variant/packed_vector2_array.hpp>

#include <algorithm>
#include <array>
#include <cstdint>
#include <cmath>
#include <vector>

using namespace godot;

namespace {

struct TileFrame {
	double radius;
	double origin[3];
	Vector3 e1, up, e3;

	Vector3 local(const Vector3 &p_dir, double p_height) const {
		const double reach = radius + p_height;
		const double x = (double)p_dir.x * reach - origin[0];
		const double y = (double)p_dir.y * reach - origin[1];
		const double z = (double)p_dir.z * reach - origin[2];
		return Vector3((real_t)(x * e1.x + y * e1.y + z * e1.z),
				(real_t)(x * up.x + y * up.y + z * up.z),
				(real_t)(x * e3.x + y * e3.y + z * e3.z));
	}
};

TileFrame frame_of(double p_radius, const PackedFloat64Array &p_origin,
		const Vector3 &p_e1, const Vector3 &p_up, const Vector3 &p_e3) {
	TileFrame frame;
	frame.radius = p_radius;
	for (int i = 0; i < 3; i++) {
		frame.origin[i] = i < p_origin.size() ? p_origin[i] : 0.0;
	}
	frame.e1 = p_e1;
	frame.up = p_up;
	frame.e3 = p_e3;
	return frame;
}

struct MeshData {
	PackedVector3Array vertices, normals;
	PackedColorArray colours;
	PackedVector2Array uvs;

	void triangle(Vector3 a, Vector3 b, Vector3 c, const Color &p_colour,
			const Vector2 &p_uv_a = Vector2(), const Vector2 &p_uv_b = Vector2(),
			const Vector2 &p_uv_c = Vector2(), bool p_uvs = false) {
		// MeshBuilder.add_tri(_uv) uses a,b,c for the normal and stores a,c,b for Godot's front face.
		const Vector3 normal = (b - a).cross(c - a).normalized();
		vertices.push_back(a);
		vertices.push_back(c);
		vertices.push_back(b);
		for (int i = 0; i < 3; i++) {
			normals.push_back(normal);
			colours.push_back(p_colour);
		}
		if (p_uvs) {
			uvs.push_back(p_uv_a);
			uvs.push_back(p_uv_c);
			uvs.push_back(p_uv_b);
		}
	}

	Dictionary result() const {
		Dictionary out;
		out["vertices"] = vertices;
		out["normals"] = normals;
		out["colours"] = colours;
		if (!uvs.is_empty()) {
			out["uvs"] = uvs;
		}
		return out;
	}
};

double smooth(double p_from, double p_to, double p_x) {
	const double t = std::clamp((p_x - p_from) / (p_to - p_from), 0.0, 1.0);
	return t * t * (3.0 - 2.0 * t);
}

} // namespace

void PlanetWaterNative::_bind_methods() {
	ClassDB::bind_method(D_METHOD("sea_mesh", "dirs", "cells", "size", "radius", "sea_level",
			"origin", "e1", "up", "e3"), &PlanetWaterNative::sea_mesh);
	ClassDB::bind_method(D_METHOD("river_mesh", "dirs", "heights", "samples", "cells", "radius",
			"sea_level", "origin", "e1", "up", "e3"), &PlanetWaterNative::river_mesh);
}

Dictionary PlanetWaterNative::sea_mesh(const PackedVector3Array &p_dirs, int p_cells, double p_size,
		double p_radius, double p_sea_level, const PackedFloat64Array &p_origin,
		const Vector3 &p_e1, const Vector3 &p_up, const Vector3 &p_e3) const {
	MeshData mesh;
	const int side = p_cells + 3;
	if (p_cells <= 0 || p_dirs.size() < side * side) {
		return mesh.result();
	}
	const int steps = std::clamp((int)(p_size / 5.0), 12, 32);
	const double facet = p_size / steps;
	const Color roll((real_t)(1.0 - smooth(6.0, 14.0, facet)), 1.0, 1.0);
	const TileFrame frame = frame_of(p_radius, p_origin, p_e1, p_up, p_e3);
	std::vector<Vector3> grid((steps + 1) * (steps + 1));
	for (int row = 0; row <= steps; row++) {
		for (int column = 0; column <= steps; column++) {
			const int at = (1 + row * p_cells / steps) * side + 1 + column * p_cells / steps;
			grid[row * (steps + 1) + column] = frame.local(p_dirs[at], p_sea_level);
		}
	}
	for (int row = 0; row < steps; row++) {
		for (int column = 0; column < steps; column++) {
			const int i00 = row * (steps + 1) + column;
			const int i01 = i00 + steps + 1;
			mesh.triangle(grid[i00], grid[i01], grid[i00 + 1], roll);
			mesh.triangle(grid[i00 + 1], grid[i01], grid[i01 + 1], roll);
		}
	}
	return mesh.result();
}

Dictionary PlanetWaterNative::river_mesh(const PackedVector3Array &p_dirs,
		const PackedFloat32Array &p_heights, const PackedVector3Array &p_samples, int p_cells,
		double p_radius, double p_sea_level, const PackedFloat64Array &p_origin,
		const Vector3 &p_e1, const Vector3 &p_up, const Vector3 &p_e3) const {
	MeshData mesh;
	const int side = p_cells + 3;
	const int count = side * side;
	if (p_cells <= 0 || p_dirs.size() < count || p_heights.size() < count || p_samples.size() < count) {
		return mesh.result();
	}
	std::vector<uint8_t> wet(count, 0);
	bool any = false;
	for (int i = 0; i < count; i++) {
		const double surface = p_samples[i].x;
		wet[i] = surface > p_sea_level && p_heights[i] < surface - 0.02
				&& p_heights[i] > p_sea_level;
		any |= wet[i] != 0;
	}
	if (!any) {
		return mesh.result();
	}
	const TileFrame frame = frame_of(p_radius, p_origin, p_e1, p_up, p_e3);
	const Color roll(0.25, 1.0, 1.0);
	for (int row = 1; row <= p_cells; row++) {
		for (int column = 1; column <= p_cells; column++) {
			const int i00 = row * side + column;
			const int corners[4] = { i00, i00 + 1, i00 + side, i00 + side + 1 };
			double surface = -1.0e30;
			for (int corner : corners) {
				if (wet[corner]) {
					surface = std::max(surface, (double)p_samples[corner].x);
				}
			}
			if (surface < -1.0e29) {
				continue;
			}
			Vector3 points[4];
			Vector2 coords[4];
			for (int k = 0; k < 4; k++) {
				const int at = corners[k];
				const double height = wet[at] ? surface : std::min((double)p_heights[at] - 0.15, surface);
				points[k] = frame.local(p_dirs[at], height);
				coords[k] = Vector2(p_samples[at].z, std::max(p_samples[at].y, (real_t)0.0));
			}
			for (const auto &tri : { std::array<int, 3>{ 0, 2, 1 }, std::array<int, 3>{ 1, 2, 3 } }) {
				int a = tri[0], b = tri[1], c = tri[2];
				if ((points[b] - points[a]).cross(points[c] - points[a]).y < 0.0) {
					std::swap(b, c);
				}
				mesh.triangle(points[a], points[b], points[c], roll, coords[a], coords[b], coords[c], true);
			}
		}
	}
	return mesh.result();
}
