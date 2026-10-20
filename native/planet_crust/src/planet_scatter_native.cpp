#include "planet_scatter_native.h"

#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/color.hpp>
#include <godot_cpp/variant/packed_color_array.hpp>
#include <godot_cpp/variant/packed_int32_array.hpp>
#include <godot_cpp/variant/packed_vector2_array.hpp>

#include <algorithm>
#include <cmath>
#include <cstring>
#include <map>
#include <unordered_map>
#include <vector>

using namespace godot;

namespace {

const double PI_D = 3.14159265358979323846;
const double TAU_D = 2.0 * PI_D;
const double LAPSE = 6.5;
const double EARTH_RELIEF = 8800.0;
const double BANK = 4.0;
const int PLANT_KEY = 100000;
const int FAR_KEY = 200000;

enum Layer { CANOPY = 0, UNDERSTORY = 1, GRASS = 2, MEADOW = 3, COVER = 4 };
enum Biome { BEACH = 0, MEADOW_BIOME = 1, FOREST = 2, ROCKY = 3, SNOW = 4, MARSH = 5, DESERT = 6 };
enum Kind { ROCK = 5, STUMP = 10, LOG = 14, SPIRE = 15, PEBBLES = 16, LITTER = 17, TWIGS = 18 };
enum Detail { NONE = 0, FAR = 1, TREES = 2, ALL = 3 };

const double SPACING[5] = { 6.5, 5.0, 1.7, 3.2, 2.6 };
const double MAX_CHANCE[5] = { 0.85, 0.4, 0.95, 0.7, 0.5 };
const double GRASS_FINE = 0.6;

struct Rng {
	uint64_t state = 0;
	uint64_t inc = 1442695040888963407ULL;
	void seed(uint64_t p_seed) {
		state = 0;
		next();
		state += p_seed;
		next();
	}
	uint32_t next() {
		uint64_t old = state;
		state = old * 6364136223846793005ULL + inc;
		uint32_t xor_shifted = (uint32_t)(((old >> 18u) ^ old) >> 27u);
		uint32_t rot = (uint32_t)(old >> 59u);
		return (xor_shifted >> rot) | (xor_shifted << ((-(int32_t)rot) & 31));
	}
	double randf() { return (double)(next() >> 8) / 16777216.0; }
	double range(double a, double b) { return a + (b - a) * randf(); }
	int randi() { return (int)(next() >> 1); }
};

double clampd(double v, double lo, double hi) { return v < lo ? lo : (v > hi ? hi : v); }
double smoothstep(double from, double to, double x) {
	double t = clampd((x - from) / (to - from), 0.0, 1.0);
	return t * t * (3.0 - 2.0 * t);
}

struct Climate {
	double sea_temperature = 15.0;
	double wet = 0.5;
};

} // namespace

double PlanetScatterNative::Species::fitness(double p_wet, double p_warm, double p_above, double p_steep) const {
	if (p_above < above_min - 0.5 || p_above > above_max || p_steep > slope_max) {
		return 0.0;
	}
	double dry = (p_wet - moisture) / moisture_tol;
	double cold = (p_warm - heat) / heat_tol;
	double off = dry * dry + cold * cold;
	if (off > 6.0) {
		return 0.0;
	}
	double edge = smoothstep(above_min - 0.5, above_min + 0.5, p_above) * (1.0 - smoothstep(above_max - 4.0, above_max, p_above)) *
			(1.0 - smoothstep(slope_max - 0.12, slope_max, p_steep));
	return std::exp(-off) * edge;
}

void PlanetScatterNative::_bind_methods() {
	ClassDB::bind_method(D_METHOD("setup", "config"), &PlanetScatterNative::setup);
	ClassDB::bind_method(D_METHOD("scatter", "tile"), &PlanetScatterNative::scatter);
	ClassDB::bind_method(D_METHOD("merge_far", "parts"), &PlanetScatterNative::merge_far);
	ClassDB::bind_method(D_METHOD("drag", "stems", "x", "z"), &PlanetScatterNative::drag);
	ClassDB::bind_method(D_METHOD("gravel_chunk", "positions", "field", "cells", "size", "x0", "z0", "x1", "z1", "spacing", "density", "seed", "variants"),
			&PlanetScatterNative::gravel_chunk);
	ClassDB::bind_method(D_METHOD("turf_chunk", "positions", "field", "cells", "size", "x0", "z0", "x1", "z1", "spacing", "density", "seed", "variants"),
			&PlanetScatterNative::turf_chunk);
}

void PlanetScatterNative::setup(const Dictionary &p_config) {
	crust = p_config.get("crust", Variant());
	species.clear();
	for (int i = 0; i < 5; i++) {
		by_layer[i].clear();
	}
	Array table = p_config.get("species", Array());
	for (int i = 0; i < table.size(); i++) {
		Dictionary d = table[i];
		Species s;
		s.id = d.get("id", 0);
		s.layer = d.get("layer", 0);
		s.variants = std::max((int)d.get("variants", 1), 1);
		s.tree = d.get("tree", false);
		s.has_far = d.get("has_far", false);
		s.moisture = d.get("moisture", 0.5);
		s.moisture_tol = d.get("moisture_tol", 0.3);
		s.heat = d.get("heat", 0.5);
		s.heat_tol = d.get("heat_tol", 0.3);
		s.above_min = d.get("above_min", 1.5);
		s.above_max = d.get("above_max", 60.0);
		s.slope_max = d.get("slope_max", 0.5);
		s.density = d.get("density", 0.5);
		s.patch_freq = d.get("patch_freq", 0.05);
		s.patch_strength = d.get("patch_strength", 0.0);
		s.size_spread = d.get("size_spread", 0.25);
		Vector2 patch = d.get("patch_offset", Vector2());
		s.patch_x = patch.x;
		s.patch_y = patch.y;
		Vector2 foot = d.get("footprint", Vector2());
		s.foot_x = foot.x;
		s.foot_y = foot.y;
		s.crown = d.get("crown", 2.0);
		s.drag = d.get("drag", 0.0);
		s.stem_radius = d.get("stem_radius", 0.3);
		s.shade_tolerance = d.get("shade_tolerance", 1.0);
		species.push_back(s);
		if (s.layer >= 0 && s.layer < 5) {
			by_layer[s.layer].push_back((int)species.size() - 1);
		}
	}
	temperature = p_config.get("temperature", PackedFloat32Array());
	rain = p_config.get("rain", PackedFloat32Array());
	grid_width = p_config.get("width", 0);
	grid_height = p_config.get("height", 0);
	relief = p_config.get("relief", 300.0);
	radius = p_config.get("radius", 20000.0);
	plant_density = p_config.get("plant_density", 1.0);
	rock_density = p_config.get("rock_density", 1.0);
	world_seed = p_config.get("world_seed", 1337);
	clearing = p_config.get("clearing", Vector3());
	Dictionary kinds = p_config.get("kind_variants", Dictionary());
	for (int i = 0; i < 32; i++) {
		kind_variants[i] = 1;
	}
	Array keys = kinds.keys();
	for (int i = 0; i < keys.size(); i++) {
		int kind = keys[i];
		if (kind >= 0 && kind < 32) {
			kind_variants[kind] = std::max((int)kinds[keys[i]], 1);
		}
	}
}

namespace {

// Everything one tile's scatter needs, so the helpers are short
struct Tile {
	const PlanetScatterNative *self;
	const Vector3 *positions;
	const Vector3 *dirs;
	const float *heights;
	int cells, side;
	double size;
	Rng rng;
	bool collide;
	std::map<int, std::vector<float>> batches;
	std::vector<float> cylinders, boxes;
	std::vector<float> stems; // the undergrowth a walker pushes through: x, z, reach, drag
};

} // namespace

Dictionary PlanetScatterNative::scatter(const Dictionary &p_tile) const {
	Tile t;
	t.self = this;
	int key = p_tile.get("key", 0);
	PackedVector3Array positions = p_tile.get("positions", PackedVector3Array());
	PackedVector3Array dirs = p_tile.get("dirs", PackedVector3Array());
	PackedFloat32Array heights = p_tile.get("heights", PackedFloat32Array());
	t.positions = positions.ptr();
	t.dirs = dirs.ptr();
	t.heights = heights.ptr();
	t.cells = p_tile.get("cells", 1);
	t.side = t.cells + 3;
	t.size = p_tile.get("size", 76.0);
	int detail = p_tile.get("detail", 0);
	t.collide = p_tile.get("collide", false);
	bool fine = p_tile.get("fine", false);
	bool grass_fine = p_tile.get("grass_fine", false);
	t.rng.seed((uint64_t)((int64_t)world_seed * 73856093LL) ^ ((uint64_t)(int64_t)key * 19349663ULL) ^ 0x9E3779B97F4A7C15ULL);
	if ((int)positions.size() < t.side * t.side || (int)dirs.size() < t.side * t.side || (int)heights.size() < t.side * t.side) {
		return Dictionary();
	}

	// ---- the tile's grid ----
	auto index_of = [&](double fx, double fz) { return ((int)fz + 1) * t.side + (int)fx + 1; };
	auto ground_at = [&](double fx, double fz) {
		int i = index_of(fx, fz);
		double tx = fx - std::floor(fx), tz = fz - std::floor(fz);
		Vector3 p00 = t.positions[i], p10 = t.positions[i + 1], p01 = t.positions[i + t.side], p11 = t.positions[i + t.side + 1];
		if (tx + tz <= 1.0) {
			return p00 + (p10 - p00) * (real_t)tx + (p01 - p00) * (real_t)tz;
		}
		return p11 + (p01 - p11) * (real_t)(1.0 - tx) + (p10 - p11) * (real_t)(1.0 - tz);
	};
	auto height_at = [&](double fx, double fz) {
		int i = index_of(fx, fz);
		double tx = fx - std::floor(fx), tz = fz - std::floor(fz);
		double h00 = t.heights[i], h10 = t.heights[i + 1], h01 = t.heights[i + t.side], h11 = t.heights[i + t.side + 1];
		if (tx + tz <= 1.0) {
			return h00 + (h10 - h00) * tx + (h01 - h00) * tz;
		}
		return h11 + (h01 - h11) * (1.0 - tx) + (h10 - h11) * (1.0 - tz);
	};
	auto direction_at = [&](double fx, double fz) {
		int i = index_of(fx, fz);
		return ((t.dirs[i] + t.dirs[i + 1] + t.dirs[i + t.side] + t.dirs[i + t.side + 1]) * (real_t)0.25).normalized();
	};
	auto slope_at = [&](double fx, double fz) {
		int i = index_of(fx, fz);
		double step = t.size / t.cells;
		double dx = (t.positions[i + 1].y - t.positions[i].y + t.positions[i + t.side + 1].y - t.positions[i + t.side].y) / (2.0 * step);
		double dz = (t.positions[i + t.side].y - t.positions[i].y + t.positions[i + t.side + 1].y - t.positions[i + 1].y) / (2.0 * step);
		return clampd(std::sqrt(dx * dx + dz * dz), 0.0, 1.0);
	};

	// the way the ground faces and how steep it is at the spot being looked at (set by `for_grid` before each candidate): what
	// tilts and sinks the things placed on a slope
	Vector3 spot_normal(0, 1, 0);
	double spot_gradient = 0.0;
	auto look_at_ground = [&](double fx, double fz) {
		const int i = index_of(fx, fz);
		const double step = t.size / t.cells;
		const double dx = (t.positions[i + 1].y - t.positions[i].y + t.positions[i + t.side + 1].y - t.positions[i + t.side].y) / (2.0 * step);
		const double dz = (t.positions[i + t.side].y - t.positions[i].y + t.positions[i + t.side + 1].y - t.positions[i + 1].y) / (2.0 * step);
		spot_normal = Vector3((real_t)-dx, 1.0f, (real_t)-dz).normalized();
		spot_gradient = std::sqrt(dx * dx + dz * dz);
		if (spot_gradient > 1.5) {
			spot_gradient = 1.5;
		}
	};

	// ---- the climate, the biome ----
	auto climate_at = [&](const Vector3 &dir) {
		Climate c;
		if (grid_width <= 0 || grid_height <= 0 || temperature.size() < grid_width * grid_height) {
			return c;
		}
		double lat = std::asin(clampd(dir.y, -1.0, 1.0));
		double lon = std::atan2((double)dir.z, (double)dir.x);
		double fx = (lon + PI_D) / TAU_D * grid_width - 0.5;
		double fy = (0.5 - lat / PI_D) * grid_height - 0.5;
		int x0 = (int)std::floor(fx), y0 = (int)std::floor(fy);
		double tx = fx - x0, ty = fy - y0;
		double temp = 0.0, wet = 0.0;
		for (int dy = 0; dy < 2; dy++) {
			for (int dx = 0; dx < 2; dx++) {
				double weight = (dx == 1 ? tx : 1.0 - tx) * (dy == 1 ? ty : 1.0 - ty);
				int row = std::max(0, std::min(grid_height - 1, y0 + dy));
				int column = ((x0 + dx) % grid_width + grid_width) % grid_width;
				int at = row * grid_width + column;
				temp += temperature[at] * weight;
				if (rain.size() > at) {
					wet += rain[at] * weight;
				}
			}
		}
		c.sea_temperature = temp;
		c.wet = clampd(wet / 1.2, 0.0, 1.0);
		return c;
	};
	auto degrees_at = [&](const Climate &c, double ground) {
		return c.sea_temperature - std::max(ground, 0.0) / relief * EARTH_RELIEF / 1000.0 * LAPSE;
	};
	auto biome_of = [&](const Climate &c, double ground, double steep) {
		if (ground < 1.4) {
			return c.wet < 0.5 ? (int)BEACH : (int)MARSH;
		}
		double degrees = degrees_at(c, ground);
		if (degrees < -14.0) {
			return (int)SNOW;
		}
		if (steep > 0.62 || ground > relief * 0.5) {
			return (int)ROCKY;
		}
		if (c.wet < 0.2 && degrees > 2.0) {
			return (int)DESERT;
		}
		return c.wet > 0.5 ? (int)FOREST : (int)MEADOW_BIOME;
	};
	auto near_water = [&](const Vector3 &dir, double ground, double margin) {
		return crust.is_valid() && crust->near_water(dir, ground, margin);
	};
	// how stony the ground is (the crust's odds by area: geology, slope, height, frost, dryness, river gravel, whole regions
	// with none): the placed stones and rocks follow it, as the stones the ground shader draws do
	auto stony_at = [&](const Vector3 &dir, double ground, double gradient) {
		if (!crust.is_valid()) {
			return 0.5;
		}
		return crust->stoniness_at(dir, ground, 1.0 - 1.0 / std::sqrt(1.0 + gradient * gradient));
	};
	const Vector3 spawn = p_tile.get("clearing", clearing);
	auto in_clearing = [&](const Vector3 &dir) {
		if (spawn == Vector3()) {
			return false;
		}
		return (double)dir.distance_to(spawn) * radius < 12.0;
	};

	// ---- placing ----
	// `tilt`: how far the thing leans to the ground's own normal (0 stays upright, 1 lies on the slope); `bury`: metres it sinks
	// (on a slope the downhill side of its foot would hang in the air)
	Basis last_basis; // the last thing queued: its rotation and where its foot is (the colliders follow it)
	Vector3 last_foot;
	auto queue = [&](int batch_key, const Vector3 &at, double scale, double yaw, const Color &tint, double tilt, double bury) {
		std::vector<float> &buffer = t.batches[batch_key];
		Basis basis(Vector3(0, 1, 0), (real_t)yaw);
		const Vector3 lean_to = Vector3(0, 1, 0).lerp(spot_normal, (real_t)tilt).normalized();
		const Vector3 axis = Vector3(0, 1, 0).cross(lean_to);
		if (axis.length_squared() > 1.0e-8f) {
			basis = Basis(axis.normalized(), (real_t)std::acos(clampd((double)lean_to.y, -1.0, 1.0))) * basis;
		}
		basis = basis.scaled(Vector3((real_t)scale, (real_t)scale, (real_t)scale));
		const Vector3 sunk = at - Vector3(0, (real_t)bury, 0);
		last_basis = basis.orthonormalized();
		last_foot = sunk;
		float values[16] = { (float)basis.rows[0][0], (float)basis.rows[0][1], (float)basis.rows[0][2], (float)sunk.x, (float)basis.rows[1][0],
			(float)basis.rows[1][1], (float)basis.rows[1][2], (float)sunk.y, (float)basis.rows[2][0], (float)basis.rows[2][1],
			(float)basis.rows[2][2], (float)sunk.z, tint.r, tint.g, tint.b, tint.a };
		buffer.insert(buffer.end(), values, values + 16);
	};
	auto queue_kind = [&](int kind, int variant, const Vector3 &at, double scale, double yaw) {
		double tilt = 0.5, bury = scale * (0.12 + 0.5 * spot_gradient);
		switch (kind) {
			case ROCK: tilt = 0.75; bury = scale * (0.12 + 0.8 * spot_gradient); break;
			case STUMP:
			case LOG: tilt = 0.9; bury = scale * (0.12 + 0.5 * spot_gradient); break;
			case SPIRE: tilt = 0.2; bury = scale * (0.12 + 1.0 * spot_gradient); break;
			case PEBBLES: tilt = 1.0; bury = scale * 0.03; break;
			case LITTER:
			case TWIGS: tilt = 1.0; bury = 0.0; break;
			default: break;
		}
		queue(kind * 100 + variant, at, scale, yaw, Color(1, 1, 1, 1), tilt, bury);
	};
	// a box collider (centre `lift` metres up the last thing's own axis, its size): position, the rotation's rows, size
	auto add_box = [&](double lift, const Vector3 &size) {
		const Vector3 centre = last_foot + last_basis.xform(Vector3(0, (real_t)lift, 0));
		const float values[15] = { (float)centre.x, (float)centre.y, (float)centre.z, (float)last_basis.rows[0][0], (float)last_basis.rows[0][1],
			(float)last_basis.rows[0][2], (float)last_basis.rows[1][0], (float)last_basis.rows[1][1], (float)last_basis.rows[1][2],
			(float)last_basis.rows[2][0], (float)last_basis.rows[2][1], (float)last_basis.rows[2][2], (float)size.x, (float)size.y, (float)size.z };
		t.boxes.insert(t.boxes.end(), values, values + 15);
	};

	std::vector<double> weights;
	double pick_chance = 0.0;
	double pick_wet = 0.5;
	auto pick = [&](int layer, const Climate &c, const Vector3 &dir, double ground, double steep, double x, double z) -> int {
		pick_wet = c.wet;
		double warm = clampd((degrees_at(c, ground) + 20.0) / 55.0, 0.0, 1.0);
		double above = std::min(ground, 30.0);
		const std::vector<int> &candidates = by_layer[layer];
		weights.assign(candidates.size(), 0.0);
		double total = 0.0;
		for (size_t i = 0; i < candidates.size(); i++) {
			const Species &one = species[candidates[i]];
			double weight = one.fitness(c.wet, warm, above, steep) * one.density;
			if (weight > 0.003 && one.patch_strength > 0.0 && crust.is_valid()) {
				double patch = crust->detail_at(Vector3((real_t)(x * one.patch_freq + one.patch_x), (real_t)(z * one.patch_freq + one.patch_y), (real_t)layer));
				weight *= (1.0 - one.patch_strength) + one.patch_strength * smoothstep(0.5, 0.66, patch);
			}
			weights[i] = weight;
			total += weight;
		}
		pick_chance = std::min(total, MAX_CHANCE[layer]);
		if (total <= 0.0) {
			return -1;
		}
		double roll = t.rng.randf() * total;
		for (size_t i = 0; i < candidates.size(); i++) {
			roll -= weights[i];
			if (roll <= 0.0) {
				return candidates[i];
			}
		}
		return candidates.back();
	};

	// How open the ground is: forest where it is wet, open fields where it is dry, a mosaic of groves and meadows in between
	// (the rain sets the trees' share, as it does on a real planet: more than about 900 mm a year is forest, less is savanna
	// and grassland, and fire, grazing and soil keep the edges ragged). Two large noises make the mosaic (about 300 m and
	// 1.5 km across, from the direction on the planet, so tiles agree), and steep ground is more open.
	auto closed_share = [&](const Vector3 &dir, const Climate &c, double steep) {
		if (!crust.is_valid()) {
			return 1.0;
		}
		const double groves = crust->detail_at(dir * (real_t)(radius / 27.0) + Vector3(11, 0, 0));
		const double regions = crust->detail_at(dir * (real_t)(radius / 140.0) + Vector3(0, 23, 0));
		const double cover = smoothstep(0.25, 0.7, c.wet) + 1.6 * (regions - 0.5) + 1.2 * (groves - 0.5) - 0.35 * smoothstep(0.35, 0.7, steep);
		return smoothstep(0.15, 0.55, cover);
	};

	// the crowns of the trees placed so far (a hash of 10 m cells): crowns keep apart, and shade what grows under them
	struct Crown {
		double x, z, radius;
	};
	std::vector<Crown> crowns;
	std::unordered_map<int64_t, std::vector<int>> crown_cells;
	const double CROWN_CELL = 10.0, CROWN_MAX = 14.0;
	auto cell_key = [](int cx, int cz) { return ((int64_t)cx << 32) ^ (int64_t)(uint32_t)cz; };
	auto each_crown_near = [&](double x, double z, double reach, auto &&visit) {
		const int span = (int)std::ceil((reach + CROWN_MAX) / CROWN_CELL);
		const int cx = (int)std::floor(x / CROWN_CELL), cz = (int)std::floor(z / CROWN_CELL);
		for (int dz = -span; dz <= span; dz++) {
			for (int dx = -span; dx <= span; dx++) {
				auto found = crown_cells.find(cell_key(cx + dx, cz + dz));
				if (found == crown_cells.end()) {
					continue;
				}
				for (int id : found->second) {
					if (visit(crowns[id])) {
						return;
					}
				}
			}
		}
	};
	// crowns may overlap a little at the edges, not more (distance under 70 % of the two radii together is too close)
	auto crowded = [&](double x, double z, double radius_here) {
		bool too_close = false;
		each_crown_near(x, z, radius_here, [&](const Crown &other) {
			const double dx = other.x - x, dz = other.z - z;
			const double limit = 0.7 * (other.radius + radius_here);
			too_close = dx * dx + dz * dz < limit * limit;
			return too_close;
		});
		return too_close;
	};
	// 0 in the open .. 1 under thick canopy: each crown over the spot shades it, most near its middle
	auto shade_at = [&](double x, double z) {
		if (crowns.empty()) {
			return 0.0;
		}
		double light = 1.0;
		each_crown_near(x, z, 0.0, [&](const Crown &other) {
			const double dx = other.x - x, dz = other.z - z;
			const double distance = std::sqrt(dx * dx + dz * dz);
			if (distance < other.radius) {
				light *= 1.0 - 0.85 * (1.0 - distance / other.radius);
			}
			return false;
		});
		return 1.0 - light;
	};

	auto place = [&](const Species &plant, const Vector3 &at) {
		double scale = 1.0 + t.rng.range(-plant.size_spread, plant.size_spread);
		if (plant.layer == CANOPY) { // a tree keeps its crown clear of its neighbours'
			const double radius_here = plant.crown * scale;
			if (crowded(at.x, at.z, radius_here)) {
				return;
			}
			crowns.push_back({ (double)at.x, (double)at.z, radius_here });
			crown_cells[cell_key((int)std::floor(at.x / CROWN_CELL), (int)std::floor(at.z / CROWN_CELL))].push_back((int)crowns.size() - 1);
		}
		double yaw = t.rng.range(0.0, TAU_D);
		int variant = t.rng.randi() % plant.variants;
		Color tint;
		if (plant.layer == GRASS) {
			double dry = (1.0 - pick_wet) * 0.7;
			Color lerped(1.0f + (float)(0.25 * dry), 1.0f + (float)(0.05 * dry), 1.0f - (float)(0.3 * dry), 1.0f);
			double dark = t.rng.range(0.0, 0.2);
			tint = Color((float)(lerped.r * (1.0 - dark)), (float)(lerped.g * (1.0 - dark)), (float)(lerped.b * (1.0 - dark)), 1.0f);
		} else {
			double shade = t.rng.range(0.82, 1.18);
			tint = Color((float)(shade * t.rng.range(0.92, 1.08)), (float)(shade * t.rng.range(0.95, 1.05)),
					(float)(shade * t.rng.range(0.9, 1.1)), 1.0f);
		}
		// a trunk is round and its foot flat: on a slope the downhill side would hang, so it sinks by the foot's radius times the
		// slope; trees stand nearly upright (they grow against gravity) but lean a little with the ground, low plants more
		const double bury = plant.tree ? 0.15 + spot_gradient * (1.3 * plant.foot_x * scale + 0.15) : 0.03 + spot_gradient * 0.08;
		queue(PLANT_KEY + plant.id * 100 + variant, at, scale, yaw, tint, plant.tree ? 0.3 : 0.5, bury);
		if (!plant.tree && plant.drag > 0.0) {
			const float stem[4] = { (float)at.x, (float)at.z, (float)(plant.stem_radius * scale), (float)plant.drag };
			t.stems.insert(t.stems.end(), stem, stem + 4);
		}
		if (t.collide && (plant.foot_x != 0.0 || plant.foot_y != 0.0)) {
			// the trunk's cylinder stands on the leaning tree's own axis, from its sunk foot
			const Vector3 centre = last_foot + last_basis.xform(Vector3(0, (real_t)(plant.foot_y * scale * 0.5), 0));
			const float values[14] = { (float)centre.x, (float)centre.y, (float)centre.z, (float)(plant.foot_x * scale), (float)(plant.foot_y * scale),
				(float)last_basis.rows[0][0], (float)last_basis.rows[0][1], (float)last_basis.rows[0][2], (float)last_basis.rows[1][0],
				(float)last_basis.rows[1][1], (float)last_basis.rows[1][2], (float)last_basis.rows[2][0], (float)last_basis.rows[2][1],
				(float)last_basis.rows[2][2] };
			t.cylinders.insert(t.cylinders.end(), values, values + 14);
		}
	};

	// one grid of candidate spots: the caller gets each spot's fractional grid position
	auto for_grid = [&](double spacing, auto &&body) {
		int count = (int)(t.size / spacing);
		for (int row = 0; row < count; row++) {
			for (int column = 0; column < count; column++) {
				double x = (column + t.rng.randf()) * spacing;
				double z = (row + t.rng.randf()) * spacing;
				double fx = clampd(x / t.size * t.cells, 0.0, t.cells - 0.001);
				double fz = clampd(z / t.size * t.cells, 0.0, t.cells - 0.001);
				look_at_ground(fx, fz);
				body(x, z, fx, fz);
			}
		}
	};

	auto scatter_layer = [&](int layer, double stretch) {
		double spacing = SPACING[layer] * stretch;
		if (layer == GRASS && grass_fine) {
			spacing *= GRASS_FINE;
		}
		for_grid(spacing, [&](double x, double z, double fx, double fz) {
			Vector3 at = ground_at(fx, fz);
			double ground = height_at(fx, fz);
			if (ground < 0.9) {
				return;
			}
			double steep = slope_at(fx, fz);
			Vector3 dir = direction_at(fx, fz);
			if (near_water(dir, ground, BANK)) {
				return;
			}
			if (layer <= UNDERSTORY && in_clearing(dir)) {
				return;
			}
			Climate c = climate_at(dir);
			int chosen = pick(layer, c, dir, ground, steep, x, z);
			if (chosen < 0) {
				return;
			}
			double chance = pick_chance * plant_density;
			if (layer == CANOPY) {
				chance *= closed_share(dir, c, steep); // open fields and clearings
			} else if (layer == UNDERSTORY) {
				chance *= 0.4 + 0.6 * closed_share(dir, c, steep);
			}
			if (layer >= GRASS) { // what grows in the shade of the trees (the crowns are placed first)
				chance *= 1.0 - shade_at(at.x, at.z) * (1.0 - species[chosen].shade_tolerance);
			}
			if (t.rng.randf() <= chance) {
				place(species[chosen], at);
			}
		});
	};

	auto scatter_far = [&]() {
		double spacing = clampd(t.size / 26.0, 14.0, 90.0);
		for_grid(spacing, [&](double x, double z, double fx, double fz) {
			double ground = height_at(fx, fz);
			if (ground < 0.9) {
				return;
			}
			Vector3 dir = direction_at(fx, fz);
			if (near_water(dir, ground, BANK)) {
				return;
			}
			Climate c = climate_at(dir);
			int chosen = pick(CANOPY, c, dir, ground, slope_at(fx, fz), x, z);
			if (chosen < 0 || !species[chosen].has_far) {
				return;
			}
			if (t.rng.randf() > pick_chance * plant_density * closed_share(dir, c, slope_at(fx, fz))) {
				return;
			}
			int batch_key = FAR_KEY + species[chosen].id * 100 + t.rng.randi() % 2;
			double scale = t.rng.range(1.0, 1.8);
			Vector3 at = ground_at(fx, fz);
			queue(batch_key, at, scale, t.rng.range(0.0, TAU_D), Color(1, 1, 1, 1), 0.3, 0.2 + spot_gradient * scale);
		});
	};

	auto rock_at = [&](int biome, double steep, const Vector3 &at, bool near, double stony) {
		double chance = 0.1, big = 1.0;
		switch (biome) {
			case ROCKY: chance = 0.55; big = 2.2; break;
			case SNOW: chance = 0.3; big = 1.8; break;
			case BEACH: chance = 0.1; big = 0.7; break;
			case DESERT: chance = 0.2; big = 1.4; break;
			default: break;
		}
		chance += steep * 0.3;
		chance *= 0.3 + 1.4 * stony;
		if (t.rng.randf() < chance * rock_density) {
			double scale = t.rng.range(0.5, 1.5) * big;
			double yaw = t.rng.range(0.0, TAU_D);
			queue_kind(ROCK, t.rng.randi() % kind_variants[ROCK], at, scale, yaw);
			if (t.collide) {
				add_box(scale * 0.32, Vector3(1.7f, 1.0f, 1.5f) * (real_t)scale);
			}
		}
		if (!near) {
			return;
		}
		int feature = LOG;
		double odds = 0.0;
		switch (biome) {
			case FOREST:
				odds = 0.16;
				feature = t.rng.randf() < 0.6 ? LOG : STUMP;
				break;
			case MARSH: odds = 0.1; feature = STUMP; break;
			case BEACH: odds = 0.06; break;
			case ROCKY:
			case SNOW: odds = 0.16; feature = SPIRE; break;
			case DESERT: odds = 0.1; feature = SPIRE; break;
			default: break;
		}
		if (feature == SPIRE) {
			odds *= 0.2 + 1.6 * stony; // rock formations stand where the ground is stony
		} else if (feature == LOG || feature == STUMP) {
			// dead wood lies where trees stand: the more crowns within 14 m the likelier (none in open fields)
			int trees = 0;
			each_crown_near(at.x, at.z, 14.0, [&](const Crown &other) {
				const double dx = other.x - at.x, dz = other.z - at.z;
				trees += dx * dx + dz * dz < 14.0 * 14.0 ? 1 : 0;
				return false;
			});
			odds *= std::min(trees, 5) * 0.4;
		}
		if (t.rng.randf() < odds * rock_density) {
			double scale = t.rng.range(0.8, 1.4);
			double yaw = t.rng.range(0.0, TAU_D);
			queue_kind(feature, t.rng.randi() % kind_variants[feature], at, scale, yaw);
			if (t.collide) {
				Vector3 box = feature == LOG ? Vector3(3.6f, 0.6f, 0.6f) : (feature == STUMP ? Vector3(0.8f, 0.8f, 0.8f) : Vector3(1.6f, 5.0f, 1.6f));
				box *= (real_t)scale;
				add_box(box.y * 0.4, box);
			}
		}
	};

	auto scatter_rocks = [&](bool near) {
		for_grid(near ? 10.0 : 20.0, [&](double, double, double fx, double fz) {
			double ground = height_at(fx, fz);
			if (ground < 0.9) {
				return;
			}
			Vector3 dir = direction_at(fx, fz);
			if (near_water(dir, ground, BANK) || in_clearing(dir)) {
				return;
			}
			double steep = slope_at(fx, fz);
			Climate c = climate_at(dir);
			rock_at(biome_of(c, ground, steep), steep, ground_at(fx, fz), near, stony_at(dir, ground, steep));
		});
	};

	auto scatter_pebbles = [&]() {
		for_grid(2.4, [&](double, double, double fx, double fz) {
			double ground = height_at(fx, fz);
			if (ground < 0.9) {
				return;
			}
			Vector3 dir = direction_at(fx, fz);
			if (near_water(dir, ground, BANK * 0.5)) {
				return;
			}
			double steep = slope_at(fx, fz);
			double chance = 0.08 + steep * 0.5;
			Climate c = climate_at(dir);
			switch (biome_of(c, ground, steep)) {
				case ROCKY:
				case SNOW: chance += 0.35; break;
				case DESERT:
				case BEACH: chance += 0.2; break;
				default: break;
			}
			chance *= 0.1 + 1.5 * stony_at(dir, ground, steep);
			if (t.rng.randf() < chance * rock_density) {
				queue_kind(PEBBLES, t.rng.randi() % kind_variants[PEBBLES], ground_at(fx, fz), t.rng.range(0.7, 1.5), t.rng.range(0.0, TAU_D));
			}
		});
	};

	auto scatter_debris = [&]() {
		for_grid(1.5, [&](double, double, double fx, double fz) {
			double ground = height_at(fx, fz);
			if (ground < 0.9) {
				return;
			}
			Vector3 dir = direction_at(fx, fz);
			if (near_water(dir, ground, BANK * 0.5)) {
				return;
			}
			double chance = 0.0;
			Climate c = climate_at(dir);
			switch (biome_of(c, ground, slope_at(fx, fz))) {
				case FOREST: chance = 0.5; break;
				case MEADOW_BIOME: chance = 0.12; break;
				case MARSH: chance = 0.1; break;
				default: break;
			}
			if (t.rng.randf() >= chance) {
				return;
			}
			int kind = t.rng.randf() < 0.7 ? LITTER : TWIGS;
			queue_kind(kind, t.rng.randi() % kind_variants[kind], ground_at(fx, fz), t.rng.range(0.8, 1.6), t.rng.range(0.0, TAU_D));
		});
	};

	if (detail == FAR) {
		scatter_far();
	} else {
		double stretch = detail == ALL ? 1.0 : 2.0;
		scatter_layer(CANOPY, stretch);
		scatter_layer(UNDERSTORY, stretch);
		if (detail != NONE) {
			scatter_rocks(detail == ALL);
		}
		if (detail == ALL && fine) {
			scatter_pebbles();
			scatter_debris();
		}
		if (detail == ALL) {
			scatter_layer(GRASS, 1.0);
			scatter_layer(MEADOW, 1.0);
			scatter_layer(COVER, 1.0);
		}
	}

	// how well turf (short grass all over the ground) grows at each vertex of the grid: rain and warmth, not steep, not stony,
	// less under the crowns, patchy; PlanetTurf puts the tufts round the walker from it (turf_chunk)
	PackedFloat32Array turf;
	if (detail == ALL) {
		turf.resize((int64_t)t.side * t.side);
		for (int row = 0; row < t.side; row++) {
			for (int column = 0; column < t.side; column++) {
				const int i = row * t.side + column;
				const double ground = t.heights[i];
				float value = 0.0f;
				if (ground >= 0.9) {
					const double fx = clampd(column - 1.0, 0.0, t.cells - 0.001), fz = clampd(row - 1.0, 0.0, t.cells - 0.001);
					const Vector3 dir = t.dirs[i];
					const Vector3 here = t.positions[i];
					const double steep = slope_at(fx, fz);
					const Climate c = climate_at(dir);
					const double degrees = degrees_at(c, ground);
					double grows = smoothstep(0.08, 0.38, c.wet) * smoothstep(-6.0, 3.0, degrees) * (1.0 - smoothstep(34.0, 42.0, degrees));
					grows *= 1.0 - smoothstep(0.35, 0.8, steep);
					grows *= 1.0 - 0.85 * stony_at(dir, ground, steep);
					grows *= 1.0 - 0.6 * shade_at(here.x, here.z);
					if (ground < 1.4) {
						grows *= 0.3; // the beach
					}
					const double patch = crust.is_valid() ? crust->detail_at(Vector3((real_t)(here.x * 0.045 + 11.0), (real_t)(here.z * 0.045 + 5.0), 3.0f)) : 0.5;
					value = (float)clampd(grows * (0.55 + 0.9 * patch), 0.0, 1.0);
				}
				turf.ptrw()[i] = value;
			}
		}
	}

	PackedInt32Array keys;
	Array buffers;
	for (const auto &entry : t.batches) {
		keys.push_back(entry.first);
		PackedFloat32Array buffer;
		buffer.resize((int64_t)entry.second.size());
		memcpy(buffer.ptrw(), entry.second.data(), entry.second.size() * sizeof(float));
		buffers.push_back(buffer);
	}
	PackedFloat32Array cylinders, boxes;
	cylinders.resize((int64_t)t.cylinders.size());
	if (!t.cylinders.empty()) {
		memcpy(cylinders.ptrw(), t.cylinders.data(), t.cylinders.size() * sizeof(float));
	}
	boxes.resize((int64_t)t.boxes.size());
	if (!t.boxes.empty()) {
		memcpy(boxes.ptrw(), t.boxes.data(), t.boxes.size() * sizeof(float));
	}
	Dictionary result;
	result["keys"] = keys;
	result["buffers"] = buffers;
	result["cylinders"] = cylinders;
	result["boxes"] = boxes;
	PackedFloat32Array stems;
	stems.resize((int64_t)t.stems.size());
	if (!t.stems.empty()) {
		memcpy(stems.ptrw(), t.stems.data(), t.stems.size() * sizeof(float));
	}
	result["stems"] = stems;
	result["turf"] = turf;
	return result;
}

// Small stones lying on the bare ground (PlanetTurf in its gravel form): where grass grows poorly, one stone to each spot of a jittered grid
// with the odds of how bare the ground is; each of its own size (many small, a few large), flatness, turn, tilt and colour (the soil's red,
// darker, grey, pale), sunk a little into the ground. Answers a buffer for each of `p_variants` shapes, like turf_chunk.
Array PlanetScatterNative::gravel_chunk(const PackedVector3Array &p_positions, const PackedFloat32Array &p_field, int p_cells,
		double p_size, double p_x0, double p_z0, double p_x1, double p_z1, double p_spacing, double p_density, int64_t p_seed,
		int p_variants) const {
	Array out;
	const int variants = std::max(p_variants, 1);
	const int side = p_cells + 3;
	if (p_cells < 1 || (int)p_positions.size() < side * side || (int)p_field.size() < side * side || p_spacing <= 0.0) {
		return out;
	}
	const Vector3 *positions = p_positions.ptr();
	const float *field = p_field.ptr();
	Rng rng;
	rng.seed((uint64_t)p_seed * 0x9E3779B97F4A7C15ULL + 0x7654321ULL);
	std::vector<std::vector<float>> buffers((size_t)variants);
	const double step = p_size / p_cells;
	const int columns = (int)std::ceil((p_x1 - p_x0) / p_spacing), rows = (int)std::ceil((p_z1 - p_z0) / p_spacing);
	for (int row = 0; row < rows; row++) {
		for (int column = 0; column < columns; column++) {
			const double x = p_x0 + (column + rng.randf()) * p_spacing, z = p_z0 + (row + rng.randf()) * p_spacing;
			const double dice = rng.randf(), size_dice = rng.randf(), yaw = rng.range(0.0, TAU_D), tone = rng.randf(), flat = rng.randf();
			const double tilt_dice = rng.randf(), way = rng.range(0.0, TAU_D), kind = rng.randf();
			const int variant = rng.randi() % variants;
			if (x < 0.0 || z < 0.0 || x >= p_size || z >= p_size) {
				continue;
			}
			const double fx = clampd(x / p_size * p_cells, 0.0, p_cells - 0.001), fz = clampd(z / p_size * p_cells, 0.0, p_cells - 0.001);
			const int i = ((int)fz + 1) * side + (int)fx + 1;
			const double tx = fx - std::floor(fx), tz = fz - std::floor(fz);
			const double f = (field[i] * (1 - tx) + field[i + 1] * tx) * (1 - tz) + (field[i + side] * (1 - tx) + field[i + side + 1] * tx) * tz;
			const double odds = clampd(1.0 - f * 0.6, 0.35, 1.0) * p_density;
			if (dice >= odds) {
				continue;
			}
			Vector3 at;
			const Vector3 p00 = positions[i], p10 = positions[i + 1], p01 = positions[i + side], p11 = positions[i + side + 1];
			if (tx + tz <= 1.0) {
				at = p00 + (p10 - p00) * (real_t)tx + (p01 - p00) * (real_t)tz;
			} else {
				at = p11 + (p01 - p11) * (real_t)(1.0 - tx) + (p10 - p11) * (real_t)(1.0 - tz);
			}
			const double dx = (p10.y - p00.y + p11.y - p01.y) / (2.0 * step), dz = (p01.y - p00.y + p11.y - p10.y) / (2.0 * step);
			const Vector3 normal = Vector3((real_t)-dx, 1.0f, (real_t)-dz).normalized();
			// many small stones, a few large: the radius (m) falls steeply with the dice
			// (the chip mesh is two metres across at scale 1: the scale is the stone's half size)
			const double radius = 0.5 * (0.012 + 0.2 * std::pow(size_dice, 3.4));
			const double tall = radius * (0.35 + 0.55 * flat);
			Basis basis(Vector3(0, 1, 0), (real_t)yaw);
			const Vector3 lean_to = (normal + Vector3((real_t)std::cos(way), 0, (real_t)std::sin(way)) * (real_t)(tilt_dice * 0.5)).normalized();
			const Vector3 axis = Vector3(0, 1, 0).cross(lean_to);
			if (axis.length_squared() > 1.0e-8f) {
				basis = Basis(axis.normalized(), (real_t)std::acos(clampd((double)lean_to.y, -1.0, 1.0))) * basis;
			}
			basis = basis.scaled(Vector3((real_t)radius, (real_t)tall, (real_t)(radius * (0.7 + 0.5 * flat))));
			at.y -= (real_t)(tall * 0.3 + 0.01 * std::sqrt(dx * dx + dz * dz));
			// the colour (sRGB): the soil's own red-brown mostly, some darker, a few dark grey, ochre or pale (kept near the soil: a stone of a
			// different colour is rare)
			double r, g, b;
			if (kind < 0.58) {
				const double v = 0.7 + 0.6 * tone;
				r = 0.6 * v; g = 0.33 * v; b = 0.24 * v;
			} else if (kind < 0.78) {
				const double v = 0.55 + 0.5 * tone;
				r = 0.42 * v; g = 0.21 * v; b = 0.15 * v;
			} else if (kind < 0.89) {
				const double v = 0.14 + 0.2 * tone;
				r = v; g = v * 0.96; b = v * 0.92;
			} else if (kind < 0.96) {
				const double v = 0.6 + 0.35 * tone;
				r = 0.6 * v; g = 0.42 * v; b = 0.29 * v;
			} else {
				const double v = 0.5 + 0.3 * tone;
				r = 0.55 * v; g = 0.5 * v; b = 0.44 * v;
			}
			const float values[16] = { (float)basis.rows[0][0], (float)basis.rows[0][1], (float)basis.rows[0][2], (float)at.x, (float)basis.rows[1][0],
				(float)basis.rows[1][1], (float)basis.rows[1][2], (float)at.y, (float)basis.rows[2][0], (float)basis.rows[2][1],
				(float)basis.rows[2][2], (float)at.z, (float)r, (float)g, (float)b, 1.0f };
			buffers[(size_t)variant].insert(buffers[(size_t)variant].end(), values, values + 16);
		}
	}
	for (const std::vector<float> &buffer : buffers) {
		PackedFloat32Array one;
		one.resize((int64_t)buffer.size());
		if (!buffer.empty()) {
			memcpy(one.ptrw(), buffer.data(), buffer.size() * sizeof(float));
		}
		out.push_back(one);
	}
	return out;
}

Array PlanetScatterNative::turf_chunk(const PackedVector3Array &p_positions, const PackedFloat32Array &p_field, int p_cells,
		double p_size, double p_x0, double p_z0, double p_x1, double p_z1, double p_spacing, double p_density, int64_t p_seed,
		int p_variants) const {
	Array out;
	const int variants = std::max(p_variants, 1);
	const int side = p_cells + 3;
	if (p_cells < 1 || (int)p_positions.size() < side * side || (int)p_field.size() < side * side || p_spacing <= 0.0) {
		return out;
	}
	const Vector3 *positions = p_positions.ptr();
	const float *field = p_field.ptr();
	Rng rng;
	rng.seed((uint64_t)p_seed * 0x9E3779B97F4A7C15ULL + 0x1234567ULL);
	std::vector<std::vector<float>> buffers((size_t)variants);
	const double step = p_size / p_cells;
	const int columns = (int)std::ceil((p_x1 - p_x0) / p_spacing), rows = (int)std::ceil((p_z1 - p_z0) / p_spacing);
	for (int row = 0; row < rows; row++) {
		for (int column = 0; column < columns; column++) {
			const double x = p_x0 + (column + rng.randf()) * p_spacing, z = p_z0 + (row + rng.randf()) * p_spacing;
			// the dice are thrown for every spot, so the same spots keep their tufts whatever the field says
			const double dice = rng.randf(), size_dice = rng.randf(), yaw = rng.range(0.0, TAU_D), tone = rng.randf();
			const int variant = rng.randi() % variants;
			if (x < 0.0 || z < 0.0 || x >= p_size || z >= p_size) {
				continue;
			}
			const double fx = clampd(x / p_size * p_cells, 0.0, p_cells - 0.001), fz = clampd(z / p_size * p_cells, 0.0, p_cells - 0.001);
			const int i = ((int)fz + 1) * side + (int)fx + 1;
			const double tx = fx - std::floor(fx), tz = fz - std::floor(fz);
			const double f = (field[i] * (1 - tx) + field[i + 1] * tx) * (1 - tz) + (field[i + side] * (1 - tx) + field[i + side + 1] * tx) * tz;
			if (dice >= f * p_density) {
				continue;
			}
			Vector3 at;
			const Vector3 p00 = positions[i], p10 = positions[i + 1], p01 = positions[i + side], p11 = positions[i + side + 1];
			if (tx + tz <= 1.0) {
				at = p00 + (p10 - p00) * (real_t)tx + (p01 - p00) * (real_t)tz;
			} else {
				at = p11 + (p01 - p11) * (real_t)(1.0 - tx) + (p10 - p11) * (real_t)(1.0 - tz);
			}
			const double dx = (p10.y - p00.y + p11.y - p01.y) / (2.0 * step), dz = (p01.y - p00.y + p11.y - p10.y) / (2.0 * step);
			const Vector3 normal = Vector3((real_t)-dx, 1.0f, (real_t)-dz).normalized();
			Basis basis(Vector3(0, 1, 0), (real_t)yaw);
			const Vector3 lean_to = Vector3(0, 1, 0).lerp(normal, 0.6f).normalized();
			const Vector3 axis = Vector3(0, 1, 0).cross(lean_to);
			if (axis.length_squared() > 1.0e-8f) {
				basis = Basis(axis.normalized(), (real_t)std::acos(clampd((double)lean_to.y, -1.0, 1.0))) * basis;
			}
			// taller where it grows well, shorter and drier where it hardly does; clumps a few metres across are tall or cropped, and a few
			// tufts shoot up above the rest
			const int cell_x = (int)std::floor(x / 2.5), cell_z = (int)std::floor(z / 2.5);
			uint32_t h = (uint32_t)cell_x * 73856093u ^ (uint32_t)cell_z * 19349663u ^ (uint32_t)p_seed * 83492791u;
			h ^= h >> 13;
			h *= 0x5bd1e995u;
			h ^= h >> 15;
			const double clump = 0.55 + 1.0 * ((h & 0xFFFF) / 65535.0);
			const double scale = (0.5 + 0.9 * size_dice) * (0.65 + 0.55 * f) * clump * (tone > 0.94 ? 1.6 : 1.0);
			basis = basis.scaled(Vector3((real_t)scale, (real_t)scale, (real_t)scale));
			// fresh, aged or dry: where it grows poorly the grass is dry, in patches of a few metres some of it is, and each tuft
			// is a little more or less so
			const uint32_t hd = (uint32_t)(int)std::floor(x / 5.0) * 2654435761u ^ (uint32_t)(int)std::floor(z / 5.0) * 40503u ^ (uint32_t)p_seed * 2246822519u;
			const double patch_dry = (double)((hd ^ (hd >> 15)) * 2246822519u >> 16) / 65535.0;
			const double dry = clampd((1.0 - f) * 0.9 + (tone - 0.5) * 0.5 + (patch_dry > 0.78 ? 0.45 : 0.0), 0.0, 1.0);
			const double dark = 0.82 + 0.3 * (size_dice * 13.0 - std::floor(size_dice * 13.0));
			// the tints (they multiply the green of the blade): fresh, aged (olive), dry (straw)
			const double aged = std::min(dry * 2.0, 1.0), straw = std::max(dry * 2.0 - 1.0, 0.0);
			const double tr = (1.0 + 0.5 * aged + 1.3 * straw) * dark, tg = (1.05 + 0.1 * aged + 0.15 * straw) * dark, tb = (0.95 - 0.1 * aged + 0.45 * straw) * dark;
			at.y -= (real_t)(0.02 + 0.1 * std::sqrt(dx * dx + dz * dz));
			const float values[16] = { (float)basis.rows[0][0], (float)basis.rows[0][1], (float)basis.rows[0][2], (float)at.x, (float)basis.rows[1][0],
				(float)basis.rows[1][1], (float)basis.rows[1][2], (float)at.y, (float)basis.rows[2][0], (float)basis.rows[2][1],
				(float)basis.rows[2][2], (float)at.z, (float)tr, (float)tg, (float)tb, 1.0f };
			buffers[(size_t)variant].insert(buffers[(size_t)variant].end(), values, values + 16);
		}
	}
	for (const std::vector<float> &buffer : buffers) {
		PackedFloat32Array one;
		one.resize((int64_t)buffer.size());
		if (!buffer.empty()) {
			memcpy(one.ptrw(), buffer.data(), buffer.size() * sizeof(float));
		}
		out.push_back(one);
	}
	return out;
}

Dictionary PlanetScatterNative::merge_far(const Array &p_parts) const {
	PackedVector3Array vertices, normals;
	PackedColorArray colors;
	for (int p = 0; p < p_parts.size(); p++) {
		Dictionary part = p_parts[p];
		PackedVector3Array v = part.get("vertices", PackedVector3Array());
		PackedVector3Array n = part.get("normals", PackedVector3Array());
		PackedColorArray c = part.get("colors", PackedColorArray());
		PackedFloat32Array buffer = part.get("buffer", PackedFloat32Array());
		int count = (int)buffer.size() / 16;
		int base = (int)vertices.size();
		vertices.resize(base + (int64_t)count * v.size());
		normals.resize(base + (int64_t)count * v.size());
		colors.resize(base + (int64_t)count * v.size());
		for (int i = 0; i < count; i++) {
			const float *m = buffer.ptr() + i * 16;
			// rows of the basis (scaled rotation about Y), the origin, and the tint
			double scale = m[5];
			double inv = scale > 0.0 ? 1.0 / scale : 1.0;
			for (int k = 0; k < v.size(); k++) {
				Vector3 a = v[k];
				int at = base + i * (int)v.size() + k;
				vertices.set(at, Vector3(m[0] * a.x + m[1] * a.y + m[2] * a.z + m[3], m[4] * a.x + m[5] * a.y + m[6] * a.z + m[7],
												 m[8] * a.x + m[9] * a.y + m[10] * a.z + m[11]));
				Vector3 d = n[k];
				normals.set(at, Vector3((real_t)((m[0] * d.x + m[1] * d.y + m[2] * d.z) * inv), (real_t)((m[4] * d.x + m[5] * d.y + m[6] * d.z) * inv),
												(real_t)((m[8] * d.x + m[9] * d.y + m[10] * d.z) * inv)));
				Color tint = c[k];
				colors.set(at, Color(tint.r * m[12], tint.g * m[13], tint.b * m[14], tint.a));
			}
		}
	}
	Dictionary result;
	result["vertices"] = vertices;
	result["normals"] = normals;
	result["colors"] = colors;
	return result;
}

double PlanetScatterNative::drag(const PackedFloat32Array &p_stems, double p_x, double p_z) const {
	double free = 1.0;
	const float *stems = p_stems.ptr();
	for (int i = 0; i + 3 < p_stems.size(); i += 4) {
		const double dx = stems[i] - p_x, dz = stems[i + 1] - p_z;
		const double reach = stems[i + 2];
		const double distance2 = dx * dx + dz * dz;
		if (distance2 < reach * reach) {
			const double inside = 1.0 - std::sqrt(distance2) / reach;
			free *= 1.0 - stems[i + 3] * inside;
		}
	}
	return 1.0 - free;
}
