#include "planet_seasons_native.h"

#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/array.hpp>

#include <algorithm>
#include <cmath>
#include <vector>

using namespace godot;

namespace {

const double EMIT = 0.34;
const double FLOOR_HEAT = 0.11;
const double SNOW_ALBEDO = 0.3;
const double LAND_TAU = 0.05;
const double SEA_TAU = 0.2;
const double MIX = 0.3;
const int PASSES = 3;
const double HOT = 27.0;
const double PI = 3.14159265358979323846;

struct Grid {
	int width, height;
	const uint8_t *sea;
};

// The heat the zonal wind carries (see PlanetSeasons._carry).
void carry(std::vector<float> &r_heat, const Grid &p_grid, double p_wind) {
	if (p_wind <= 0.0) {
		return;
	}
	std::vector<float> moved = r_heat;
	for (int row = 0; row < p_grid.height; row++) {
		const double lat = (0.5 - ((double)row + 0.5) / (double)p_grid.height) * PI;
		const double push = -std::cos(3.0 * lat) * p_wind;
		for (int column = 0; column < p_grid.width; column++) {
			const int index = row * p_grid.width + column;
			const int side = push > 0.0 ? (column + p_grid.width - 1) % p_grid.width : (column + 1) % p_grid.width;
			const int from = row * p_grid.width + side;
			moved[index] = (float)((double)r_heat[index] + ((double)r_heat[from] - (double)r_heat[index]) * std::abs(push));
		}
	}
	r_heat = moved;
}

// The heat shared between neighbouring cells (PlanetSeasons._mix).
void mix(std::vector<float> &r_heat, const Grid &p_grid) {
	std::vector<float> shared = r_heat;
	for (int row = 0; row < p_grid.height; row++) {
		const int north = std::max(row - 1, 0) * p_grid.width;
		const int south = std::min(row + 1, p_grid.height - 1) * p_grid.width;
		for (int column = 0; column < p_grid.width; column++) {
			const int index = row * p_grid.width + column;
			const int west = row * p_grid.width + (column + p_grid.width - 1) % p_grid.width;
			const int east = row * p_grid.width + (column + 1) % p_grid.width;
			const double around = ((double)r_heat[west] + r_heat[east] + r_heat[north + column] + r_heat[south + column]) * 0.25;
			shared[index] = (float)((double)r_heat[index] + (around - (double)r_heat[index]) * MIX);
		}
	}
	r_heat = shared;
}

// One step of `dt` years (PlanetSeasons._step), the rows' sunlight being `p_light`.
void step(std::vector<float> &r_heat, const float *p_light, const Grid &p_grid, double p_dt, double p_wind) {
	const double sea_pull = 1.0 - std::exp(-p_dt / SEA_TAU);
	const double land_pull = 1.0 - std::exp(-p_dt / LAND_TAU);
	for (int row = 0; row < p_grid.height; row++) {
		const double sun = p_light[row];
		for (int column = 0; column < p_grid.width; column++) {
			const int index = row * p_grid.width + column;
			const double degrees = r_heat[index];
			double frozen = (2.0 - degrees) / 10.0;
			frozen = frozen < 0.0 ? 0.0 : (frozen > 1.0 ? 1.0 : frozen);
			const double absorbed = sun * (1.0 - SNOW_ALBEDO * frozen) + FLOOR_HEAT;
			const double ratio = std::sqrt(std::sqrt(absorbed / EMIT));
			double balance = 15.0 + 288.0 * (ratio - 1.0);
			if (balance > HOT) {
				balance = HOT + (balance - HOT) * 0.35;
			}
			r_heat[index] = (float)(degrees + (balance - degrees) * (p_grid.sea[index] == 1 ? sea_pull : land_pull));
		}
	}
	for (int pass = 0; pass < PASSES; pass++) {
		carry(r_heat, p_grid, p_wind);
		mix(r_heat, p_grid);
	}
}

} // namespace

void PlanetSeasonsNative::_bind_methods() {
	ClassDB::bind_method(D_METHOD("run", "sea", "lights", "width", "height", "snapshots", "wind", "max_years"),
			&PlanetSeasonsNative::run);
}

Dictionary PlanetSeasonsNative::run(const PackedByteArray &p_sea, const PackedFloat32Array &p_lights, int p_width,
		int p_height, int p_snapshots, double p_wind, int p_max_years) const {
	Dictionary result;
	const int size = p_width * p_height;
	if (p_width <= 0 || p_height <= 0 || p_snapshots <= 0 || p_sea.size() < size ||
			p_lights.size() < p_snapshots * p_height) {
		return result;
	}
	const Grid grid = { p_width, p_height, p_sea.ptr() };
	const float *lights = p_lights.ptr();
	const double dt = 1.0 / (double)p_snapshots;
	std::vector<float> heat(size, 15.0f);
	std::vector<float> previous = heat;
	for (int year = 0; year < p_max_years; year++) {
		for (int at = 0; at < p_snapshots; at++) {
			step(heat, lights + at * p_height, grid, dt, p_wind);
		}
		double total = 0.0;
		for (int index = 0; index < size; index++) {
			total += std::abs((double)heat[index] - (double)previous[index]);
		}
		previous = heat;
		if (year >= 2 && total / (double)size < 0.04) {
			break;
		}
	}
	// the recorded year: the picture after step s is kept as the one at s + 1 (the last one is the first)
	Array cycle;
	cycle.resize(p_snapshots);
	PackedFloat32Array mean;
	mean.resize(size);
	mean.fill(0.0f);
	for (int at = 0; at < p_snapshots; at++) {
		step(heat, lights + at * p_height, grid, dt, p_wind);
		PackedFloat32Array picture;
		picture.resize(size);
		for (int index = 0; index < size; index++) {
			picture.set(index, heat[index]);
			mean.set(index, (float)((double)mean[index] + (double)heat[index] / (double)p_snapshots));
		}
		cycle[(at + 1) % p_snapshots] = picture;
	}
	result["mean"] = mean;
	result["cycle"] = cycle;
	return result;
}
