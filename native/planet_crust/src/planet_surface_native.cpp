#include "planet_surface_native.h"

#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/packed_byte_array.hpp>
#include <godot_cpp/variant/packed_vector3_array.hpp>

#include <algorithm>
#include <cmath>
#include <numeric>
#include <vector>

using namespace godot;

namespace {

const double PI_D = 3.14159265358979323846;

struct Selection {
	Vector3 near_dir;
	double height, radius, split_factor, tile_max, collide_tiles;
	int max_level, coarse_level;
	bool plants_on;
	PackedVector3Array faces;
	std::vector<int> entries;
	std::vector<double> distance;
	std::vector<uint8_t> collides, plants;
	std::vector<double> sort;

	Vector3 direction(int face, double s, double t) const {
		const Vector3 normal = faces[face * 3], u = faces[face * 3 + 1], v = faces[face * 3 + 2];
		const double a = std::tan(s * PI_D * 0.25), b = std::tan(t * PI_D * 0.25);
		return (normal + u * (real_t)a + v * (real_t)b).normalized();
	}
	double distance_to(int face, int level, int x, int y) const {
		const double count = (double)(1 << level);
		const double s = -1.0 + 2.0 * (x + 0.5) / count;
		const double t = -1.0 + 2.0 * (y + 0.5) / count;
		const double along = (double)direction(face, s, t).distance_to(near_dir) * radius;
		return std::sqrt(along * along + height * height);
	}
	void select(int face, int level, int x, int y) {
		const double size = radius * PI_D * 0.5 / (double)(1 << level);
		const double d = distance_to(face, level, x, y);
		if (level < max_level && d < size * split_factor) {
			for (int dy = 0; dy < 2; dy++) {
				for (int dx = 0; dx < 2; dx++) {
					select(face, level + 1, x * 2 + dx, y * 2 + dy);
				}
			}
			return;
		}
		const bool collide = level == max_level && d < tile_max * collide_tiles * 2.0 + 60.0;
		int detail = 0;
		if (plants_on) {
			if (level == max_level) {
				detail = d < tile_max * 2.0 ? 3 : 2;
			} else if (level == max_level - 1 && d < tile_max * 10.0) {
				detail = 2;
			} else if (level >= max_level - 4 && level < max_level - 1 && d < tile_max * 40.0) {
				detail = 1;
			}
		}
		entries.insert(entries.end(), { face, level, x, y });
		distance.push_back(d);
		collides.push_back(collide ? 1 : 0);
		plants.push_back((uint8_t)detail);
		const int urgency = collide ? 0 : (level <= coarse_level ? 1 : 2);
		sort.push_back(urgency * 1.0e15 + (urgency == 1 ? level * 1.0e12 : 0.0) + d);
	}
};

} // namespace

void PlanetSurfaceNative::_bind_methods() {
	ClassDB::bind_method(D_METHOD("select", "params"), &PlanetSurfaceNative::select);
	ClassDB::bind_method(D_METHOD("order", "values"), &PlanetSurfaceNative::order);
}

Dictionary PlanetSurfaceNative::select(const Dictionary &p_params) const {
	Selection s;
	Vector3 near = p_params.get("near", Vector3(0, 1, 0));
	s.near_dir = near.normalized();
	s.height = p_params.get("height", 0.0);
	s.radius = p_params.get("radius", 20000.0);
	s.max_level = p_params.get("max_level", 6);
	s.split_factor = p_params.get("split_factor", 2.0);
	s.tile_max = p_params.get("tile_max", 128.0);
	s.collide_tiles = p_params.get("collide_tiles", 1.2);
	s.plants_on = p_params.get("plants_on", true);
	s.coarse_level = p_params.get("coarse_level", 3);
	s.faces = p_params.get("faces", PackedVector3Array());
	if (s.faces.size() < 18) {
		return Dictionary();
	}
	for (int face = 0; face < 6; face++) {
		s.select(face, 0, 0, 0);
	}
	PackedInt32Array entries;
	entries.resize((int64_t)s.entries.size());
	std::copy(s.entries.begin(), s.entries.end(), entries.ptrw());
	PackedFloat64Array distance, sort;
	distance.resize((int64_t)s.distance.size());
	sort.resize((int64_t)s.sort.size());
	std::copy(s.distance.begin(), s.distance.end(), distance.ptrw());
	std::copy(s.sort.begin(), s.sort.end(), sort.ptrw());
	PackedByteArray collides, plants;
	collides.resize((int64_t)s.collides.size());
	plants.resize((int64_t)s.plants.size());
	std::copy(s.collides.begin(), s.collides.end(), collides.ptrw());
	std::copy(s.plants.begin(), s.plants.end(), plants.ptrw());
	Dictionary result;
	result["entries"] = entries;
	result["distance"] = distance;
	result["collides"] = collides;
	result["plants"] = plants;
	result["sort"] = sort;
	return result;
}

PackedInt32Array PlanetSurfaceNative::order(const PackedFloat64Array &p_values) const {
	std::vector<int> index(p_values.size());
	std::iota(index.begin(), index.end(), 0);
	std::stable_sort(index.begin(), index.end(), [&](int a, int b) { return p_values[a] < p_values[b]; });
	PackedInt32Array out;
	out.resize((int64_t)index.size());
	std::copy(index.begin(), index.end(), out.ptrw());
	return out;
}
