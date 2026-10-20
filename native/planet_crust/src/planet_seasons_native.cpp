#include "planet_seasons_native.h"

#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/array.hpp>

#include <algorithm>
#include <cmath>
#include <vector>

using namespace godot;

namespace {

const double PI = 3.14159265358979323846;

struct HeatParams {
	double emit, floor, snow_albedo, land_tau, sea_tau, mix, hot;
	int passes;
};

struct Grid {
	int width, height;
	const uint8_t *sea;
};

// The heat the zonal wind carries (see PlanetSeasons._carry).
void carry(std::vector<float> &r_heat, const Grid &p_grid, double p_wind, double p_wind_k) {
	if (p_wind <= 0.0) {
		return;
	}
	std::vector<float> moved = r_heat;
	for (int row = 0; row < p_grid.height; row++) {
		const double lat = (0.5 - ((double)row + 0.5) / (double)p_grid.height) * PI;
		const double push = -std::cos(p_wind_k * lat) * p_wind;
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
void mix(std::vector<float> &r_heat, const Grid &p_grid, double p_mix) {
	std::vector<float> shared = r_heat;
	for (int row = 0; row < p_grid.height; row++) {
		const int north = std::max(row - 1, 0) * p_grid.width;
		const int south = std::min(row + 1, p_grid.height - 1) * p_grid.width;
		for (int column = 0; column < p_grid.width; column++) {
			const int index = row * p_grid.width + column;
			const int west = row * p_grid.width + (column + p_grid.width - 1) % p_grid.width;
			const int east = row * p_grid.width + (column + 1) % p_grid.width;
			const double around = ((double)r_heat[west] + r_heat[east] + r_heat[north + column] + r_heat[south + column]) * 0.25;
			shared[index] = (float)((double)r_heat[index] + (around - (double)r_heat[index]) * p_mix);
		}
	}
	r_heat = shared;
}

// One step of `dt` years (PlanetSeasons._step), the rows' sunlight being `p_light`.
void step(std::vector<float> &r_heat, const float *p_light, const Grid &p_grid, double p_dt, double p_wind,
		double p_wind_k, const HeatParams &p_heat) {
	const double sea_pull = 1.0 - std::exp(-p_dt / p_heat.sea_tau);
	const double land_pull = 1.0 - std::exp(-p_dt / p_heat.land_tau);
	for (int row = 0; row < p_grid.height; row++) {
		const double sun = p_light[row];
		for (int column = 0; column < p_grid.width; column++) {
			const int index = row * p_grid.width + column;
			const double degrees = r_heat[index];
			double frozen = (2.0 - degrees) / 10.0;
			frozen = frozen < 0.0 ? 0.0 : (frozen > 1.0 ? 1.0 : frozen);
			const double absorbed = sun * (1.0 - p_heat.snow_albedo * frozen) + p_heat.floor;
			const double ratio = std::sqrt(std::sqrt(absorbed / p_heat.emit));
			double balance = 15.0 + 288.0 * (ratio - 1.0);
			// dry land (the byte of a land cell is 2 + 100 times its dryness) keeps more of its heat: a
			// desert has no water to evaporate and no cloud
			const int cell = p_grid.sea[index];
			const double dry = cell >= 2 ? (double)(cell - 2) * 0.01 : 0.0;
			const double hot = p_heat.hot + 10.0 * dry;
			if (balance > hot) {
				balance = hot + (balance - hot) * (0.35 + 0.5 * dry);
			}
			r_heat[index] = (float)(degrees + (balance - degrees) * (p_grid.sea[index] == 1 ? sea_pull : land_pull));
		}
	}
	for (int pass = 0; pass < p_heat.passes; pass++) {
		carry(r_heat, p_grid, p_wind, p_wind_k);
		mix(r_heat, p_grid, p_heat.mix);
	}
}

} // namespace

void PlanetSeasonsNative::_bind_methods() {
	ClassDB::bind_method(D_METHOD("grid_dirs", "width", "height"), &PlanetSeasonsNative::grid_dirs);
	ClassDB::bind_method(D_METHOD("mark_sea", "grounds", "width", "height", "dry"), &PlanetSeasonsNative::mark_sea);
	ClassDB::bind_method(D_METHOD("add_currents", "sea", "cycle", "mean", "width", "height", "currents"),
			&PlanetSeasonsNative::add_currents);
	ClassDB::bind_method(D_METHOD("blend", "first", "next", "weight"), &PlanetSeasonsNative::blend);
	ClassDB::bind_method(D_METHOD("light_grid", "snapshots", "height", "orbit"),
			&PlanetSeasonsNative::light_grid);
	ClassDB::bind_method(D_METHOD("elevation_and_ocean", "grounds", "relief"), &PlanetSeasonsNative::elevation_and_ocean);
	ClassDB::bind_method(D_METHOD("rain", "elevation", "ocean", "temperature", "width", "height", "rain_base",
			"rain_scale", "belts"), &PlanetSeasonsNative::rain);
	ClassDB::bind_method(D_METHOD("run", "sea", "lights", "width", "height", "snapshots", "wind", "max_years", "wind_k", "heat"),
			&PlanetSeasonsNative::run);
}

PackedFloat32Array PlanetSeasonsNative::light_grid(int p_snapshots, int p_height,
		const Dictionary &p_orbit) const {
	PackedFloat32Array out;
	if (p_snapshots <= 0 || p_height <= 0) return out;
	out.resize(p_snapshots * p_height);
	const double tilt = p_orbit.get("tilt", 0.0), eccentricity = p_orbit.get("eccentricity", 0.0);
	const double perihelion = p_orbit.get("perihelion", 0.0), insolation = p_orbit.get("insolation", 1.0);
	const double greenhouse = p_orbit.get("greenhouse", 1.0);
	for (int moment = 0; moment < p_snapshots; moment++) {
		const double share = ((double)moment + 0.5) / p_snapshots;
		const double raw_mean = 2.0 * PI * (share - perihelion);
		const double mean = raw_mean - 2.0 * PI * std::floor((raw_mean + PI) / (2.0 * PI));
		double anomaly = mean;
		if (eccentricity > 0.0) {
			anomaly = mean + eccentricity * std::sin(mean);
			for (int step = 0; step < 5; step++) {
				anomaly -= (anomaly - eccentricity * std::sin(anomaly) - mean) /
						(1.0 - eccentricity * std::cos(anomaly));
			}
			anomaly = 2.0 * std::atan2(std::sqrt(1.0 + eccentricity) * std::sin(anomaly * 0.5),
					std::sqrt(1.0 - eccentricity) * std::cos(anomaly * 0.5));
		}
		const double distance = (1.0 - eccentricity * eccentricity) /
				(1.0 + eccentricity * std::cos(anomaly));
		const double light = insolation / (distance * distance) * greenhouse;
		const double orbit_angle = PI * 0.5 + 2.0 * PI * perihelion + anomaly;
		const double dec = std::asin(std::clamp(-std::cos(orbit_angle) * std::sin(tilt), -1.0, 1.0));
		for (int row = 0; row < p_height; row++) {
			const double lat = (0.5 - ((double)row + 0.5) / p_height) * PI;
			const double cos_h0 = -std::tan(lat) * std::tan(dec);
			double daily = 0.0;
			if (cos_h0 < 1.0) {
				const double h0 = cos_h0 <= -1.0 ? PI : std::acos(cos_h0);
				daily = (h0 * std::sin(lat) * std::sin(dec) +
						std::cos(lat) * std::cos(dec) * std::sin(h0)) / PI;
			}
			out.set(moment * p_height + row, (float)(daily * light));
		}
	}
	return out;
}

PackedFloat32Array PlanetSeasonsNative::blend(const PackedFloat32Array &p_first,
		const PackedFloat32Array &p_next, double p_weight) const {
	PackedFloat32Array out;
	if (p_first.size() != p_next.size()) return out;
	out.resize(p_first.size());
	for (int i = 0; i < p_first.size(); i++) {
		out.set(i, (float)((double)p_first[i] + ((double)p_next[i] - p_first[i]) * p_weight));
	}
	return out;
}

PackedByteArray PlanetSeasonsNative::mark_sea(const PackedFloat32Array &p_grounds, int p_width, int p_height,
		const Dictionary &p_dry) const {
	PackedByteArray sea;
	const int size = p_width * p_height;
	if (p_width <= 0 || p_height <= 0 || p_grounds.size() < size) return sea;
	sea.resize(size);
	std::vector<int> far(size);
	for (int i = 0; i < size; i++) {
		sea.set(i, p_grounds[i] < 0.0f ? 1 : 0);
		far[i] = sea[i] == 1 ? 0 : (int)p_dry.get("max_distance", 99);
	}
	for (int pass = 0; pass < 2; pass++) {
		for (int row = 0; row < p_height; row++) {
			for (int step = 0; step < p_width * 2; step++) {
				const int column = step % p_width, here = row * p_width + column;
				const int west = row * p_width + (column + p_width - 1) % p_width;
				far[here] = std::min(far[here], far[west] + 1);
			}
			for (int step = 0; step < p_width * 2; step++) {
				const int column = p_width - 1 - step % p_width, here = row * p_width + column;
				const int east = row * p_width + (column + 1) % p_width;
				far[here] = std::min(far[here], far[east] + 1);
			}
		}
		for (int row = 1; row < p_height; row++) for (int column = 0; column < p_width; column++) {
			const int i = row * p_width + column;
			far[i] = std::min(far[i], far[i - p_width] + 1);
		}
		for (int row = p_height - 2; row >= 0; row--) for (int column = 0; column < p_width; column++) {
			const int i = row * p_width + column;
			far[i] = std::min(far[i], far[i + p_width] + 1);
		}
	}
	const double belt_lat = p_dry.get("belt_lat", 26.0), belt_width = p_dry.get("belt_width", 13.0);
	const double distance = p_dry.get("distance", 6.0), base = p_dry.get("base", 0.3);
	const double belt_power = p_dry.get("belt_power", 0.9), scale = p_dry.get("scale", 100.0);
	for (int row = 0; row < p_height; row++) {
		const double lat = std::abs((0.5 - ((double)row + 0.5) / p_height) * 180.0);
		const double highs = std::exp(-std::pow((lat - belt_lat) / belt_width, 2.0));
		for (int column = 0; column < p_width; column++) {
			const int i = row * p_width + column;
			if (sea[i] == 1) continue;
			const double inland = std::clamp((double)far[i] / distance, 0.0, 1.0);
			const double dry = inland * std::clamp(base + belt_power * highs, 0.0, 1.0);
			sea.set(i, 2 + (int)std::round(dry * scale));
		}
	}
	return sea;
}

Dictionary PlanetSeasonsNative::add_currents(const PackedByteArray &p_sea, const Array &p_cycle,
		const PackedFloat32Array &p_mean, int p_width, int p_height, const Dictionary &p_currents) const {
	Dictionary out;
	const int size = p_width * p_height;
	if (p_width <= 0 || p_height <= 0 || p_sea.size() < size || p_mean.size() < size) return out;
	std::vector<double> offsets(size, 0.0);
	const double cold_lat = p_currents.get("cold_lat", 22.0), cold_width = p_currents.get("cold_width", 14.0);
	const double warm_lat = p_currents.get("warm_lat", 36.0), warm_width = p_currents.get("warm_width", 16.0);
	const double cold_power = p_currents.get("cold_power", 5.0), warm_power = p_currents.get("warm_power", 4.0);
	const int reach_max = p_currents.get("reach", 3);
	for (int row = 0; row < p_height; row++) {
		const double lat = std::abs((0.5 - ((double)row + 0.5) / p_height) * 180.0);
		const double cold = std::exp(-std::pow((lat - cold_lat) / cold_width, 2.0));
		const double warm = std::exp(-std::pow((lat - warm_lat) / warm_width, 2.0));
		for (int column = 0; column < p_width; column++) {
			const int i = row * p_width + column;
			if (p_sea[i] != 1) continue;
			for (int reach = 1; reach <= reach_max; reach++) {
				if (p_sea[row * p_width + (column + reach) % p_width] != 1) {
					offsets[i] -= cold_power * cold * (1.0 - (double)(reach - 1) / reach_max);
					break;
				}
			}
			for (int reach = 1; reach <= reach_max; reach++) {
				if (p_sea[row * p_width + (column + p_width - reach % p_width) % p_width] != 1) {
					offsets[i] += warm_power * warm * (1.0 - (double)(reach - 1) / reach_max);
					break;
				}
			}
		}
	}
	Array cycle;
	cycle.resize(p_cycle.size());
	for (int at = 0; at < p_cycle.size(); at++) {
		PackedFloat32Array picture = p_cycle[at];
		if (picture.size() < size) return Dictionary();
		for (int i = 0; i < size; i++) picture.set(i, (float)((double)picture[i] + (float)offsets[i]));
		cycle[at] = picture;
	}
	PackedFloat32Array mean = p_mean;
	for (int i = 0; i < size; i++) mean.set(i, (float)((double)mean[i] + (float)offsets[i]));
	out["cycle"] = cycle;
	out["mean"] = mean;
	return out;
}

Dictionary PlanetSeasonsNative::run(const PackedByteArray &p_sea, const PackedFloat32Array &p_lights, int p_width,
		int p_height, int p_snapshots, double p_wind, int p_max_years, double p_wind_k,
		const Dictionary &p_heat) const {
	Dictionary result;
	const int size = p_width * p_height;
	if (p_width <= 0 || p_height <= 0 || p_snapshots <= 0 || p_sea.size() < size ||
			p_lights.size() < p_snapshots * p_height) {
		return result;
	}
	const Grid grid = { p_width, p_height, p_sea.ptr() };
	const HeatParams heat_params = {(double)p_heat["emit"], (double)p_heat["floor"],
			(double)p_heat["snow_albedo"], (double)p_heat["land_tau"], (double)p_heat["sea_tau"],
			(double)p_heat["mix"], (double)p_heat["hot"], (int)p_heat["passes"]};
	const float *lights = p_lights.ptr();
	const double dt = 1.0 / (double)p_snapshots;
	std::vector<float> heat(size, 15.0f);
	std::vector<float> previous = heat;
	for (int year = 0; year < p_max_years; year++) {
		for (int at = 0; at < p_snapshots; at++) {
			step(heat, lights + at * p_height, grid, dt, p_wind, p_wind_k, heat_params);
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
		step(heat, lights + at * p_height, grid, dt, p_wind, p_wind_k, heat_params);
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

PackedFloat32Array PlanetSeasonsNative::rain(const PackedFloat32Array &p_elevation, const PackedByteArray &p_ocean,
		const PackedFloat32Array &p_temperature, int p_width, int p_height, double p_rain_base,
		double p_rain_scale, const Dictionary &p_belts) const {
	// this planet's circulation (PlanetClimate.circulation): where its wet and dry belts and winds are
	const double itcz_lat = p_belts.get("itcz_lat", 0.0), itcz_width = p_belts.get("itcz_width", 9.0);
	const double itcz_power = p_belts.get("itcz_power", 0.8), storm_lat = p_belts.get("storm_lat", 48.0);
	const double storm_power = p_belts.get("storm_power", 0.3), dry_lat = p_belts.get("dry_lat", 27.0);
	const double dry_power = p_belts.get("dry_power", 0.55), wind_low = p_belts.get("wind_low", 30.0);
	const double wind_high = p_belts.get("wind_high", 60.0);
	const int size = p_width * p_height;
	PackedFloat32Array result;
	result.resize(size);
	if (p_width <= 0 || p_height <= 0 || p_elevation.size() < size || p_ocean.size() < size ||
			p_temperature.size() < size) {
		return result;
	}
	const double finer = 192.0 / (double)p_width; // (the rain is tuned for 192 columns: per-cell terms scale)
	std::vector<float> raw(size, 0.0f);
	std::vector<float> row_rain(p_width);
	for (int row = 0; row < p_height; row++) {
		const double lat = std::abs((0.5 - ((double)row + 0.5) / (double)p_height) * 180.0);
		const int wind = (lat > wind_low && lat < wind_high) ? 1 : -1;
		const double itcz = itcz_power * std::exp(-std::pow((lat - itcz_lat) / itcz_width, 2.0));
		const double storms = storm_power * std::exp(-std::pow((lat - storm_lat) / 12.0, 2.0));
		const double dry_belt = 1.0 - dry_power * std::exp(-std::pow((lat - dry_lat) / 9.0, 2.0));
		double carried = 0.0;
		std::fill(row_rain.begin(), row_rain.end(), 0.0f);
		for (int lap = 0; lap < 2; lap++) {
			for (int step = 0; step < p_width; step++) {
				const int column = wind > 0 ? step : p_width - 1 - step;
				const int behind = (((column - wind) % p_width) + p_width) % p_width;
				const int index = row * p_width + column;
				if (p_ocean[index] == 1) {
					double warmth = ((double)p_temperature[index] + 5.0) / 30.0;
					warmth = warmth < 0.1 ? 0.1 : (warmth > 1.0 ? 1.0 : warmth);
					carried = carried + (1.0 - carried) * (1.0 - std::pow(1.0 - 0.5 * warmth, finer));
					row_rain[column] = 0.0f;
				} else {
					double climb = (double)p_elevation[index] - (double)p_elevation[row * p_width + behind];
					climb = climb < 0.0 ? 0.0 : climb;
					const double fall = carried * (p_rain_base * finer + std::min(climb * 9.0, 0.55)) * dry_belt;
					carried = std::max(carried - fall * (0.5 - std::min(climb * 6.0, 0.3)), 0.0) * std::pow(0.996, finer);
					row_rain[column] = (float)(fall * p_rain_scale);
				}
			}
		}
		for (int column = 0; column < p_width; column++) {
			const double wet_belt = (itcz + storms) * (p_ocean[row * p_width + column] == 0 ? 1.0 : 0.4);
			raw[row * p_width + column] = (float)((double)row_rain[column] + wet_belt);
		}
	}
	for (int row = 0; row < p_height; row++) {
		for (int column = 0; column < p_width; column++) {
			double total = 0.0;
			double weight = 0.0;
			for (int dy = -1; dy <= 1; dy++) {
				for (int dx = -1; dx <= 1; dx++) {
					const int r = std::max(0, std::min(p_height - 1, row + dy));
					const int c = (((column + dx) % p_width) + p_width) % p_width;
					const double w = (dx == 0 && dy == 0) ? 2.0 : 1.0;
					total += (double)raw[r * p_width + c] * w;
					weight += w;
				}
			}
			double value = total / weight;
			value = value < 0.0 ? 0.0 : (value > 1.6 ? 1.6 : value);
			result.set(row * p_width + column, (float)value);
		}
	}
	return result;
}

PackedVector3Array PlanetSeasonsNative::grid_dirs(int p_width, int p_height) const {
	PackedVector3Array out;
	out.resize((int64_t)p_width * p_height);
	for (int row = 0; row < p_height; row++) {
		const double lat = (0.5 - (row + 0.5) / p_height) * PI;
		for (int column = 0; column < p_width; column++) {
			const double lon = (column + 0.5) / p_width * 2.0 * PI - PI;
			out.set(row * p_width + column, Vector3((real_t)(std::cos(lat) * std::cos(lon)), (real_t)std::sin(lat), (real_t)(std::cos(lat) * std::sin(lon))));
		}
	}
	return out;
}

Dictionary PlanetSeasonsNative::elevation_and_ocean(const PackedFloat32Array &p_grounds, double p_relief) const {
	PackedFloat32Array elevation;
	PackedByteArray ocean;
	elevation.resize(p_grounds.size());
	ocean.resize(p_grounds.size());
	for (int index = 0; index < p_grounds.size(); index++) {
		elevation.set(index, (float)(p_grounds[index] / p_relief));
		ocean.set(index, p_grounds[index] < 0.0f ? 1 : 0);
	}
	Dictionary result;
	result["elevation"] = elevation;
	result["ocean"] = ocean;
	return result;
}
