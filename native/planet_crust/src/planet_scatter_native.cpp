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
	auto queue = [&](int batch_key, const Vector3 &at, double scale, double yaw, const Color &tint) {
		std::vector<float> &buffer = t.batches[batch_key];
		double c = std::cos(yaw) * scale, s = std::sin(yaw) * scale;
		// Basis(UP, yaw).scaled(scale): rows (c 0 s) (0 scale 0) (-s 0 c), then the origin, then the colour
		float values[16] = { (float)c, 0.0f, (float)s, (float)at.x, 0.0f, (float)scale, 0.0f, (float)at.y, (float)-s, 0.0f, (float)c,
			(float)at.z, tint.r, tint.g, tint.b, tint.a };
		buffer.insert(buffer.end(), values, values + 16);
	};
	auto queue_kind = [&](int kind, int variant, const Vector3 &at, double scale, double yaw) {
		bool flat = kind == LITTER || kind == TWIGS;
		queue(kind * 100 + variant, at - Vector3(0, flat ? 0.0f : (real_t)(scale * 0.12), 0), scale, yaw, Color(1, 1, 1, 1));
	};
	auto add_box = [&](const Vector3 &at, double yaw, const Vector3 &size) {
		const float values[7] = { (float)at.x, (float)at.y, (float)at.z, (float)yaw, (float)size.x, (float)size.y, (float)size.z };
		t.boxes.insert(t.boxes.end(), values, values + 7);
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
		Vector3 lowered = at - Vector3(0, plant.tree ? 0.15f : 0.03f, 0);
		queue(PLANT_KEY + plant.id * 100 + variant, lowered, scale, yaw, tint);
		if (t.collide && (plant.foot_x != 0.0 || plant.foot_y != 0.0)) {
			const float values[5] = { (float)at.x, (float)(at.y + plant.foot_y * scale * 0.5), (float)at.z, (float)(plant.foot_x * scale),
				(float)(plant.foot_y * scale) };
			t.cylinders.insert(t.cylinders.end(), values, values + 5);
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
			Vector3 at = ground_at(fx, fz) - Vector3(0, 0.2f, 0);
			queue(batch_key, at, scale, t.rng.range(0.0, TAU_D), Color(1, 1, 1, 1));
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
				add_box(at + Vector3(0, (real_t)(scale * 0.2), 0), yaw, Vector3(1.7f, 1.0f, 1.5f) * (real_t)scale);
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
		}
		if (t.rng.randf() < odds * rock_density) {
			double scale = t.rng.range(0.8, 1.4);
			double yaw = t.rng.range(0.0, TAU_D);
			queue_kind(feature, t.rng.randi() % kind_variants[feature], at, scale, yaw);
			if (t.collide) {
				Vector3 box = feature == LOG ? Vector3(3.6f, 0.6f, 0.6f) : (feature == STUMP ? Vector3(0.8f, 0.8f, 0.8f) : Vector3(1.6f, 5.0f, 1.6f));
				box *= (real_t)scale;
				add_box(at + Vector3(0, (real_t)(box.y * 0.4), 0), yaw, box);
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
	return result;
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
