#include "planet_crust_native.h"
#include "erosion_noise.h"

#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/core/math.hpp>
#include <godot_cpp/variant/packed_float64_array.hpp>

#include <algorithm>
#include <atomic>
#include <thread>
#include <vector>
#include <cmath>

using namespace godot;

namespace {

inline double smooth(double p_from, double p_to, double p_x) {
	if (p_from == p_to) {
		return p_from;
	}
	double s = (p_x - p_from) / (p_to - p_from);
	s = s < 0.0 ? 0.0 : (s > 1.0 ? 1.0 : s);
	return s * s * (3.0 - 2.0 * s);
}

inline double clampd(double p_x, double p_low, double p_high) {
	return p_x < p_low ? p_low : (p_x > p_high ? p_high : p_x);
}

inline double fposmod_d(double p_x, double p_y) {
	double value = std::fmod(p_x, p_y);
	if ((value < 0.0 && p_y > 0.0) || (value > 0.0 && p_y < 0.0)) {
		value += p_y;
	}
	return value;
}

inline double sign_d(double p_x) {
	return p_x > 0.0 ? 1.0 : (p_x < 0.0 ? -1.0 : 0.0);
}

} // namespace

void PlanetCrustNative::_bind_methods() {
	ClassDB::bind_method(D_METHOD("setup", "config"), &PlanetCrustNative::setup);
	ClassDB::bind_method(D_METHOD("river_waters", "dirs"), &PlanetCrustNative::river_waters);
	ClassDB::bind_method(D_METHOD("set_climate", "grid", "width", "height", "rain"), &PlanetCrustNative::set_climate);
	ClassDB::bind_method(D_METHOD("set_rivers", "cells", "network", "cell_metres"), &PlanetCrustNative::set_rivers);
	ClassDB::bind_method(D_METHOD("heights", "dirs"), &PlanetCrustNative::heights);
	ClassDB::bind_method(D_METHOD("lake_surfaces", "dirs"), &PlanetCrustNative::lake_surfaces);
	ClassDB::bind_method(D_METHOD("smooth_rgb", "rgb", "width", "height"), &PlanetCrustNative::smooth_rgb);
	ClassDB::bind_method(D_METHOD("coast_lines", "rgb", "land", "width", "height"), &PlanetCrustNative::coast_lines);
	ClassDB::bind_method(D_METHOD("despeckle", "rgb", "width", "height"), &PlanetCrustNative::despeckle);
	ClassDB::bind_method(D_METHOD("set_weather", "config"), &PlanetCrustNative::set_weather);
	ClassDB::bind_method(D_METHOD("data_row", "layer", "dirs", "grounds", "macros", "east", "north", "step_lon", "params"),
			&PlanetCrustNative::data_row);
	ClassDB::bind_method(D_METHOD("terrain_row", "dirs", "grounds", "east", "north", "step_lon", "calm"),
			&PlanetCrustNative::terrain_row);
	ClassDB::bind_method(D_METHOD("colours", "dirs", "heights", "steeps"), &PlanetCrustNative::colours);
	ClassDB::bind_method(D_METHOD("macro_and_tectonic_heights", "dirs"), &PlanetCrustNative::macro_and_tectonic_heights);
	ClassDB::bind_method(D_METHOD("tectonic_heights", "dirs"), &PlanetCrustNative::tectonic_heights);
	ClassDB::bind_method(D_METHOD("height_at", "dir"), &PlanetCrustNative::height_at);
	ClassDB::bind_method(D_METHOD("macro_heights", "dirs"), &PlanetCrustNative::macro_heights);
	ClassDB::bind_method(D_METHOD("broad_heights", "dirs", "pixel"), &PlanetCrustNative::broad_heights);
	ClassDB::bind_method(D_METHOD("tile_dirs", "face", "s0", "s1", "t0", "t1", "cells"), &PlanetCrustNative::tile_dirs);
	ClassDB::bind_method(D_METHOD("tile_positions", "face", "s0", "s1", "t0", "t1", "cells", "heights", "origin", "e1", "up",
			"e3"), &PlanetCrustNative::tile_positions);
	ClassDB::bind_method(D_METHOD("local_positions", "dirs", "heights", "origin", "e1", "up", "e3"),
			&PlanetCrustNative::local_positions);
	ClassDB::bind_method(D_METHOD("grid_normals", "positions", "cells"), &PlanetCrustNative::grid_normals);
	ClassDB::bind_method(D_METHOD("ground_colours", "dirs", "heights", "normals", "cells"),
			&PlanetCrustNative::ground_colours);
	ClassDB::bind_method(D_METHOD("triangles", "positions", "normals", "colours", "cells", "skirt_drop"),
			&PlanetCrustNative::triangles, DEFVAL(0.0));
}

// [seed, frequency, octaves, fractal type (0 none, 1 fbm, 2 ridged)] -> a smooth simplex noise, as
// the GDScript `_setup` makes (and Godot's FastNoiseLite sets it up).
void PlanetCrustNative::configure(Noise &r_noise, const Array &p_config) {
	fastnoiselite::FastNoiseLite &g = r_noise.generator;
	g.SetNoiseType(fastnoiselite::FastNoiseLite::NoiseType_OpenSimplex2S);
	g.SetSeed((int)p_config[0]);
	g.SetFrequency((float)(double)p_config[1]);
	g.SetFractalType((fastnoiselite::FastNoiseLite::FractalType)(int)p_config[3]);
	g.SetFractalOctaves((int)p_config[2]);
	g.SetFractalLacunarity(2.0f);
	g.SetFractalGain(0.5f);
	g.SetFractalWeightedStrength(0.0f);
	g.SetFractalPingPongStrength(2.0f);
	r_noise.octaves = (int)p_config[2] < 8 ? (int)p_config[2] : 8;
	r_noise.wavelength = 1.0 / std::max((double)(float)(double)p_config[1], 1e-12);
	for (int count = 1; count < r_noise.octaves; count++) {
		r_noise.reduced[count - 1] = g;
		r_noise.reduced[count - 1].SetFractalOctaves(count);
	}
}

void PlanetCrustNative::setup(const Dictionary &p_config) {
	seeds = p_config["seeds"];
	spins = p_config["spins"];
	continental = p_config["continental"];
	continent_height = p_config["continent"];
	ocean_height = p_config["ocean"];
	boundary_width = p_config["boundary"];
	soft = p_config["soft"];
	radius = p_config["radius"];
	relief = p_config["relief"];
	sea = p_config["sea"];
	shore = p_config["shore"];
	shore_flat = p_config["shore_flat"];
	land_curve = p_config["land_curve"];
	deep = p_config["deep"];
	massif_scale = p_config["massif_scale"];
	chain_scale = p_config["chain_scale"];
	foothill_scale = p_config["foothill_scale"];
	erosion_scale = p_config.get("erosion", 0.0);
	erosion_seed = (uint32_t)(int64_t)p_config.get("erosion_seed", 1);
	erosion_wavelength = p_config.get("erosion_wavelength", 10000.0);
	erosion_octaves = (int)(int64_t)p_config.get("erosion_octaves", 5);
	hotspots = p_config.get("hotspots", PackedVector3Array());
	valley_width = p_config["valley_width"];
	PackedFloat32Array depths = p_config["valley_depths"];
	for (int index = 0; index < 3; index++) {
		valley_depth[index] = depths[index];
	}
	rock_boundary = p_config["rock_boundary"];
	PackedColorArray colours_in = p_config["rock_colours"];
	for (int index = 0; index < 9; index++) {
		rock_colours[index] = colours_in[index];
	}
	configure(warp, p_config["warp"]);
	configure(ridge, p_config["ridge"]);
	configure(interior, p_config["interior"]);
	configure(rolling, p_config["rolling"]);
	configure(ranges, p_config["ranges"]);
	configure(range_mask, p_config["range_mask"]);
	configure(hills, p_config["hills"]);
	configure(gullies, p_config["gullies"]);
	configure(detail, p_config["detail"]);
	configure(massif, p_config["massif"]);
	configure(chain, p_config["chain"]);
	configure(foothills, p_config["foothills"]);
	Array valley_noises = p_config["valleys"];
	for (int index = 0; index < 3; index++) {
		configure(valleys[index], valley_noises[index]);
	}
	cube_faces = p_config["faces"];
	configure(craton, p_config["craton"]);
	configure(basin, p_config["basin"]);
}

// The direction pushed about by the slow noise (the plate edges wander).
Vector3 PlanetCrustNative::plate_shift(const Vector3 &p_dir) const {
	Vector3 shifted = p_dir + Vector3(warp.at(p_dir),
										warp.at(Vector3(p_dir.x + 5.3f, p_dir.y - 2.1f, p_dir.z + 1.7f)),
										warp.at(Vector3(p_dir.x - 3.7f, p_dir.y + 4.4f, p_dir.z - 6.2f))) *
							(real_t)0.20;
	return shifted.normalized();
}

double PlanetCrustNative::boundary_effect(int p_a, int p_b, const Vector3 &p_q, double p_edge) const {
	Vector3 toward = seeds[p_b] - seeds[p_a];
	toward -= p_q * p_q.dot(toward);
	double push = 0.0;
	if (toward.length_squared() > 0.000001) {
		Vector3 relative = spins[p_a].cross(p_q) - spins[p_b].cross(p_q);
		push = clampd(relative.dot(toward.normalized()), -1.0, 1.0);
	}
	double together = push > 0.0 ? push : 0.0;
	double apart = -push > 0.0 ? -push : 0.0;
	double edge_scaled = p_edge / boundary_width;
	double near = std::exp(-edge_scaled * edge_scaled);
	bool here = continental[p_a] != 0;
	bool there = continental[p_b] != 0;
	if (here && there) {
		return near * (0.62 * together - 0.12 * apart);
	}
	if (here != there) {
		double inland = here ? p_edge : -p_edge;
		double up_scaled = (inland - 0.03) / 0.045;
		double range_up = 0.26 * std::exp(-up_scaled * up_scaled);
		double down_scaled = (inland + 0.03) / 0.035;
		double trench = 0.30 * std::exp(-down_scaled * down_scaled);
		return together * (range_up - trench);
	}
	const Vector3 along_at = p_q * (real_t)1.9;
	const double along = (double)interior.at(along_at);
	const double steps = (double)interior.at(along_at + Vector3(7.0f, 3.0f, 1.0f));
	double arc_scaled = (p_edge - 0.03) / 0.03;
	double arc = 0.30 * together * smooth(-0.3, 0.25, along) * std::exp(-arc_scaled * arc_scaled);
	double ridge_scaled = (p_edge - 0.04 * clampd(steps * 3.0, -1.0, 1.0)) / 0.09;
	arc += 0.22 * apart * std::exp(-ridge_scaled * ridge_scaled);
	return arc - 0.22 * together * near;
}

// Height in units of relief, from the plates alone (PlanetTectonics.height).
double PlanetCrustNative::tectonic_height(const Vector3 &p_dir) const {
	Vector3 q = plate_shift(p_dir);
	double c0 = -2.0, c1 = -2.0, c2 = -2.0, c3 = -2.0;
	int p0 = 0, p1 = 0, p2 = 0, p3 = 0;
	const int count = seeds.size();
	for (int index = 0; index < count; index++) {
		double closeness = q.dot(seeds[index]);
		if (closeness <= c3) {
			continue;
		}
		if (closeness > c1) {
			if (closeness > c0) {
				c3 = c2; p3 = p2; c2 = c1; p2 = p1; c1 = c0; p1 = p0; c0 = closeness; p0 = index;
			} else {
				c3 = c2; p3 = p2; c2 = c1; p2 = p1; c1 = closeness; p1 = index;
			}
		} else if (closeness > c2) {
			c3 = c2; p3 = p2; c2 = closeness; p2 = index;
		} else {
			c3 = closeness; p3 = index;
		}
	}
	double a0 = std::acos(clampd(c0, -1.0, 1.0));
	double a1 = std::acos(clampd(c1, -1.0, 1.0));
	double a2 = std::acos(clampd(c2, -1.0, 1.0));
	double a3 = std::acos(clampd(c3, -1.0, 1.0));
	double w0 = 1.0;
	double w1 = std::exp(-(a1 - a0) / soft);
	double w2 = std::exp(-(a2 - a0) / soft);
	double w3 = std::exp(-(a3 - a0) / soft);
	double total = w0 + w1 + w2 + w3;
	bool land0 = continental[p0] != 0, land1 = continental[p1] != 0;
	bool land2 = continental[p2] != 0, land3 = continental[p3] != 0;
	double base = w0 * (land0 ? continent_height : ocean_height);
	base += w1 * (land1 ? continent_height : ocean_height);
	base += w2 * (land2 ? continent_height : ocean_height);
	base += w3 * (land3 ? continent_height : ocean_height);
	double variety = w0 * (land0 ? 0.11 : 0.06);
	variety += w1 * (land1 ? 0.11 : 0.06);
	variety += w2 * (land2 ? 0.11 : 0.06);
	variety += w3 * (land3 ? 0.11 : 0.06);
	base /= total;
	variety /= total;
	double scale = 1.0 / (w0 * w1);
	double rise = 0.0;
	double pair = w0 * w1 * scale;
	if (pair >= 0.002) {
		rise += pair * boundary_effect(p0, p1, q, (a1 - a0) * 0.5);
	}
	pair = w0 * w2 * scale;
	if (pair >= 0.002) {
		rise += pair * boundary_effect(p0, p2, q, (a2 - a0) * 0.5);
	}
	pair = w0 * w3 * scale;
	if (pair >= 0.002) {
		rise += pair * boundary_effect(p0, p3, q, (a3 - a0) * 0.5);
	}
	pair = w1 * w2 * scale;
	if (pair >= 0.002) {
		rise += pair * boundary_effect(p1, p2, q, (a2 - a1) * 0.5);
	}
	pair = w1 * w3 * scale;
	if (pair >= 0.002) {
		rise += pair * boundary_effect(p1, p3, q, (a3 - a1) * 0.5);
	}
	pair = w2 * w3 * scale;
	if (pair >= 0.002) {
		rise += pair * boundary_effect(p2, p3, q, (a3 - a2) * 0.5);
	}
	double ridged = ridge.at(p_dir) * 0.5 + 0.5;
	double rough = (rise > 0.0 ? rise : 0.0) * (ridged * 1.1 - 0.35);
	double inside = interior.at(p_dir) * variety;
	return base + rise + rough + inside;
}

double PlanetCrustNative::shore_curve(double p_units) const {
	double reach = std::abs(p_units) / shore;
	double eased = reach < 1.0 ? reach * reach * reach * (1.0 - reach * 0.5) : reach - 0.5;
	double raw = sign_d(p_units) * (shore_flat * std::abs(p_units) + (1.0 - shore_flat) * shore * eased);
	if (p_units > 0.0) {
		raw = std::pow(raw, land_curve);
	}
	if (p_units < 0.0) {
		raw *= 1.0 + deep * smooth(0.05, 0.3, -p_units);
	}
	return raw;
}

double PlanetCrustNative::valley_cut(const Vector3 &p_point, double p_units, double p_glacial) const {
	double upland = smooth(0.03, 0.25, p_units);
	if (upland <= 0.0) {
		return 0.0;
	}
	double cut = 0.0;
	for (int index = 0; index < 3; index++) {
		double line = std::abs((double)valleys[index].at(p_point));
		double floor_value = 1.0 - smooth(0.0, valley_width * (1.0 + 1.2 * p_glacial), line);
		cut += valley_depth[index] * (1.0 + 0.6 * p_glacial) * std::pow(floor_value, 1.5 - 1.0 * p_glacial);
	}
	return cut * upland;
}

Vector3 PlanetCrustNative::coarse_slope(const Vector3 &p_point, double p_rugged, double p_pixel) const {
	const double step = std::max(erosion_wavelength * 0.08, std::max(p_pixel * 1.5, 150.0));
	const double lod = std::max(p_pixel, step * 2.0); // (a few octaves are enough for a slope over `step`)
	const Vector3 up = p_point.normalized();
	const Vector3 axis = std::abs((double)up.y) < 0.9 ? Vector3(0, 1, 0) : Vector3(1, 0, 0);
	const Vector3 east = up.cross(axis).normalized();
	const Vector3 north = up.cross(east);
	auto broad = [&](const Vector3 &q) {
		return ((double)massif.at_lod(q, lod) * 0.5 * massif_scale + (double)chain.at_lod(q, lod) * 0.5 * chain_scale +
					   ((double)ranges.at_lod(q, lod) * 0.5 + 0.5) * 0.22) *
				relief * p_rugged;
	};
	const double h = step;
	const double dx = (broad(p_point + east * (real_t)h) - broad(p_point - east * (real_t)h)) / (2.0 * h);
	const double dy = (broad(p_point + north * (real_t)h) - broad(p_point - north * (real_t)h)) / (2.0 * h);
	return east * (real_t)dx + north * (real_t)dy;
}

// The height (m) of the seamounts and islands at a direction on the deep sea floor: the plate there drifts
// round its spin axis over the fixed hot spots, so each leaves a trail of volcanoes behind it, along the
// circle round the axis through the hot spot, smaller the older (further along) they are.
double PlanetCrustNative::seamounts(const Vector3 &p_dir, double p_units) const {
	if (hotspots.is_empty() || p_units > -0.12) {
		return 0.0;
	}
	int plate = 0;
	real_t edge = 0;
	bool is_continental = false;
	plate_at(p_dir, plate, edge, is_continental);
	if (is_continental || spins[plate].length_squared() < 1.0e-8f) {
		return 0.0;
	}
	const Vector3 axis = spins[plate].normalized();
	const Vector3 across = axis.cross(std::abs((double)axis.y) < 0.9 ? Vector3(0, 1, 0) : Vector3(1, 0, 0)).normalized();
	const Vector3 third = axis.cross(across);
	const double q_lat = std::asin(clampd((double)p_dir.dot(axis), -1.0, 1.0));
	const double q_az = std::atan2((double)p_dir.dot(third), (double)p_dir.dot(across));
	const double pi = 3.14159265358979323846;
	double best = 0.0;
	for (int index = 0; index < hotspots.size(); index++) {
		const Vector3 h = hotspots[index];
		const double d = q_lat - std::asin(clampd((double)h.dot(axis), -1.0, 1.0));
		if (std::abs(d) > 0.06) {
			continue;
		}
		double along = q_az - std::atan2((double)h.dot(third), (double)h.dot(across));
		along = std::fmod(along + 3.0 * pi, 2.0 * pi) - pi; // -pi .. pi
		const double trail = 0.9;
		if (along < 0.0 || along > trail) {
			continue;
		}
		const double age = along / trail;
		const double clump = smooth(0.0, 0.5, (double)interior.at(p_dir * (real_t)9.0) * 0.5 + 0.3);
		const double bump = std::exp(-(d / 0.018) * (d / 0.018)) * (1.0 - age) * (0.35 + 0.65 * clump);
		best = bump > best ? bump : best;
	}
	return best * relief * 0.55 * smooth(-0.12, -0.2, p_units);
}

double PlanetCrustNative::macro_ground(double p_units, const Vector3 &p_point, double p_pixel) const {
	const bool p_broad = p_pixel > 2000.0; // (huge pixels: not even the small hills' first octave)
	// every layer below is multiplied by a weight that is exactly 0 over the sea (and a little
	// inland), so those noises are not asked there: the same height, the sea floor much faster
	double land = smooth(-0.02, 0.05, p_units);
	Valley valley;
	// where it is dry and the ground is raised a river cuts a canyon: steep walls instead of a V
	double side = 0.35;
	if (!rain_grid.is_empty() && p_units > 0.12) {
		const double dry = smooth(0.35, 0.1, grid_at(rain_grid, p_point.normalized(), 0.5));
		side += 1.5 * dry * smooth(0.12, 0.3, p_units);
	}
	const bool in_valley = river_cells > 0 && valley_at(p_point.normalized(), valley, side);
	// a river's valley floor is smooth: the rough layers fade there
	const double floor_factor = in_valley ? 1.0 - 0.7 * (1.0 - smooth(valley.floor_half, valley.floor_half * 6.0, valley.distance)) : 1.0;
	double rolling_height = (land > 0.0 && !p_broad) ? rolling.at_lod(p_point, p_pixel) * clampd(relief * 0.12, 25.0, 120.0) * floor_factor : 0.0;
	double ridges = 0.0;
	if (p_units > 0.08) {
		double belt = smooth(0.0, 0.5, (double)range_mask.at(p_point) + 0.15);
		ridges = ((double)ranges.at_lod(p_point, p_pixel) * 0.5 + 0.5) * relief * 0.22;
		ridges *= belt * smooth(0.08, 0.4, p_units);
	}
	double rugged = smooth(0.0, 0.25, p_units);
	double massifs = 0.0, chains = 0.0, spurs = 0.0;
	if (rugged > 0.0) {
		massifs = ((double)massif.at_lod(p_point, p_pixel) * 0.5 + 0.0) * relief * massif_scale * rugged * floor_factor;
		chains = ((double)chain.at_lod(p_point, p_pixel) * 0.5 + 0.0) * relief * chain_scale * rugged * floor_factor;
		if (!p_broad) {
				spurs = ((double)foothills.at_lod(p_point, p_pixel) * 0.5 + 0.0) * relief * foothill_scale * rugged * floor_factor;
			}
	}
	// the eroded ridges and gullies: rugged ground only, softened in a river's valley floor
	double eroded = 0.0;
	if (erosion_scale > 0.0 && rugged > 0.0) {
		const Vector3 slope = coarse_slope(p_point, rugged, p_pixel);
		const double to_lattice = erosion_wavelength / (relief * erosion_scale * 2.0);
		eroded = erosion_noise::fbm({ (double)p_point.x, (double)p_point.y, (double)p_point.z }, erosion_wavelength, erosion_octaves, p_pixel,
						 erosion_seed, { (double)slope.x * to_lattice, (double)slope.y * to_lattice, (double)slope.z * to_lattice }) *
				relief * erosion_scale * rugged * floor_factor;
	}
	double shore_height = shore_curve(p_units) * relief;
	const double coast = smooth(0.01, 0.12, p_units); // (the rolling hills fade in inland: a clean shore)
	const double mounts = erosion_scale > 0.0 ? seamounts(p_point.normalized(), p_units) : 0.0;
	double raised = shore_height + rolling_height * coast + ridges + chains + massifs + spurs + eroded + mounts;
	// where it is cold enough for permanent ice the valleys are glaciated (PlanetNoise._valley_cut)
	const double cold_here = sea_temperature(p_point / (real_t)radius) - 0.0065 * (raised > 0.0 ? raised : 0.0);
	const double glacial = smooth(-2.0, -8.0, cold_here);
	double cut = valley_cut(p_point, p_units, glacial);
	// a fjord: where a glaciated valley reaches the coast it may cut below the sea
	const double coastal = smooth(0.12, 0.02, p_units);
	double limit = (shore_height > 0.0 ? shore_height : 0.0) * 0.8 + glacial * coastal * relief * 0.12;
	double result = raised - (cut < limit ? cut : limit);
	if (result > 0.0) { // the land's heights follow a hypsometric curve (PlanetNoise.HYPSO)
		const double pivot = relief * 0.5;
		result = pivot * std::pow(result / pivot, 1.4);
	}
	if (p_units > 0.0) { // inland ground does not dip below the sea (no puddles: lakes come from the drainage)
		// a basin below the sea becomes a shallow bowl (8 m falling off smoothly, never below 0)
		const double inland = smooth(0.0, 0.1, p_units) * (1.0 - glacial * coastal); // (fjords stay below the sea)
		if (result < 8.0) {
			const double bowl = 8.0 * std::exp((result - 8.0) / 60.0);
			result = result + (bowl - result) * inland;
		}
	}
	if (!lake_level.is_empty() && p_units > 0.0) { // the lakes of the drainage: the ground sinks under the water
		double level = -1.0e9;
		const double weight = lake_weight(p_point.normalized(), level);
		if (weight > 0.0) {
			// only the real hollow fills: ground well above the water (a hill in the cell) stays
			const double hollow = smooth(level + 30.0, level + 4.0, result);
			const double soft = smooth(0.0, 1.0, weight) * hollow;
			const double bottom = std::max(level - (1.0 + 7.0 * smooth(0.55, 1.0, weight)), 0.6);
			result = result + (std::min(result, bottom) - result) * soft;
		}
	}
	if (in_valley && result > 0.0) {
		// a river's valley (from the drainage): the ground may not stand above the river's bed
		// and the sides it allows (blended in softly), and is never cut below the sea
		const double envelope = valley.envelope > 0.5 ? valley.envelope : 0.5;
		const double soft_k = 150.0;
		const double h = std::max(soft_k - std::abs(result - envelope), 0.0) / soft_k;
		const double joined = std::min(result, envelope) - h * h * soft_k * 0.25;
		result = joined > 0.5 ? joined : 0.5;
		// a delta: where a big river meets the sea the ground spreads out into a flat, low plain
		const double share = valley.flow / river_flow;
		const double delta = smooth(0.12, 0.04, p_units) * smooth(0.25, 1.0, share) *
				smooth(valley.floor_half * 5.0, valley.floor_half * 1.5, valley.distance);
		if (delta > 0.0 && result > 3.0) {
			result += (3.0 + (result - 3.0) * 0.3 - result) * delta; // (a gentle plain, not a dead flat one)
		}
	}
	return result;
}

// The ground before any water has cut it (PlanetNoise.base_height with no hydrology).
double PlanetCrustNative::ground_height(const Vector3 &p_dir) const {
	double units = tectonic_height(p_dir) - sea;
	Vector3 p = p_dir * (real_t)radius;
	double land = smooth(-0.02, 0.05, units);
	double hill_height = land > 0.0 ? hills.at(p) * clampd(relief * 0.04, 14.0, 45.0) * valley_floor(p_dir) : 0.0;
	double ground = macro_ground(units, p) + hill_height * smooth(0.01, 0.12, units);
	double high = smooth(0.12, 0.45, units);
	double gully_depth = relief * 0.05 < 90.0 ? relief * 0.05 : 90.0;
	if (high > 0.0) {
		ground += (double)gullies.at(p) * 0.5 * gully_depth * high;
	}
	double layer = clampd(relief * 0.025, 8.0, 40.0);
	double steps = std::floor(ground / layer) + smooth(0.15, 0.85, fposmod_d(ground / layer, 1.0));
	double mixed = smooth(0.3, 0.6, units) * 0.35;
	ground += (steps * layer - ground) * mixed;
	if (units > 0.0 && ground < 8.0) { // the hills and gullies must not dip an inland basin below the sea either
		const double bowl = 8.0 * std::exp((ground - 8.0) / 60.0);
		const double ice = smooth(-2.0, -8.0, sea_temperature(p_dir) - 0.0065 * (ground > 0.0 ? ground : 0.0));
		ground += (bowl - ground) * smooth(0.0, 0.1, units) * (1.0 - ice * smooth(0.12, 0.02, units));
	}
	// dunes: low sand ridges on the flat, hot, dry ground (native only, like the eroded ridges)
	if (erosion_scale > 0.0 && ground > 3.0 && units > 0.05 && ground < relief * 0.2) {
		const double dry = smooth(0.28, 0.08, grid_at(rain_grid, p_dir, 0.5));
		const double hot = smooth(8.0, 20.0, sea_temperature(p_dir) - 0.0065 * ground);
		const double desert = dry * hot;
		if (desert > 0.0) {
			const Vector3 east = Vector3(-p_dir.z, 0.0f, p_dir.x).normalized();
			const double phase = (double)p.dot(east) / 170.0 + 2.5 * (double)hills.at(p);
			const double crest = 1.0 - std::abs(std::sin(phase));
			ground += crest * crest * 7.0 * desert;
		}
	}
	return ground;
}

void PlanetCrustNative::plate_at(const Vector3 &p_dir, int &r_plate, real_t &r_edge, bool &r_continental) const {
	Vector3 q = plate_shift(p_dir);
	int first = 0;
	double best = -2.0;
	double next = -2.0;
	const int count = seeds.size();
	for (int index = 0; index < count; index++) {
		double closeness = q.dot(seeds[index]);
		if (closeness > best) {
			next = best;
			best = closeness;
			first = index;
		} else if (closeness > next) {
			next = closeness;
		}
	}
	r_edge = (real_t)((std::acos(clampd(next, -1.0, 1.0)) - std::acos(clampd(best, -1.0, 1.0))) * 0.5);
	r_plate = first;
	r_continental = continental[first] != 0;
}

void PlanetCrustNative::set_climate(const PackedFloat32Array &p_grid, int p_width, int p_height,
		const PackedFloat32Array &p_rain) {
	climate_grid = p_grid;
	rain_grid = p_rain;
	climate_width = p_width;
	climate_height = p_height;
}

// The year's mean temperature at sea level at a direction (bilinear on the climate's grid), 15 without one.
double PlanetCrustNative::sea_temperature(const Vector3 &p_dir) const {
	return grid_at(climate_grid, p_dir, 15.0);
}

// How frozen the sea is at a direction: the mean temperature over a band of latitude (the climate's ice-albedo
// feedback makes it jump, a straight line round the planet), wobbled by noise so the edge of the ice is ragged.
double PlanetCrustNative::sea_ice(const Vector3 &p_dir) const {
	const double lat = std::asin(std::max(-1.0, std::min(1.0, (double)p_dir.y)));
	const double lon = std::atan2((double)p_dir.z, (double)p_dir.x);
	const double wobble = (double)warp.at(p_dir * (real_t)3.0) * 0.14;
	double sum = 0.0;
	for (int step = -2; step <= 2; step++) {
		const double l = std::max(-1.5, std::min(1.5, lat + wobble + (double)step * 0.06));
		sum += sea_temperature(Vector3((real_t)(std::cos(l) * std::cos(lon)), (real_t)std::sin(l), (real_t)(std::cos(l) * std::sin(lon))));
	}
	return smooth(-1.5, -8.0, sum / 5.0);
}

double PlanetCrustNative::grid_at(const PackedFloat32Array &p_grid, const Vector3 &p_dir, double p_default) const {
	if (climate_width <= 0 || climate_height <= 0 || p_grid.size() < climate_width * climate_height) {
		return p_default;
	}
	const double pi = 3.14159265358979323846;
	const double lat = std::asin(std::max(-1.0, std::min(1.0, (double)p_dir.y)));
	const double lon = std::atan2((double)p_dir.z, (double)p_dir.x);
	const double fx = (lon + pi) / (2.0 * pi) * climate_width - 0.5;
	const double fy = (0.5 - lat / pi) * climate_height - 0.5;
	const int x0 = (int)std::floor(fx);
	const int y0 = (int)std::floor(fy);
	const double tx = fx - x0;
	const double ty = fy - y0;
	double value = 0.0;
	for (int dy = 0; dy < 2; dy++) {
		for (int dx = 0; dx < 2; dx++) {
			const double weight = (dx == 1 ? tx : 1.0 - tx) * (dy == 1 ? ty : 1.0 - ty);
			const int row = std::max(0, std::min(climate_height - 1, y0 + dy));
			const int column = (((x0 + dx) % climate_width) + climate_width) % climate_width;
			value += (double)p_grid[row * climate_width + column] * weight;
		}
	}
	return value;
}

// The land as the map shows it from far: green where wet and warm, tan where dry, grey rock up the mountains,
// snow and ice where cold, sand by the sea (PlanetChart._illustrated_color).
Color PlanetCrustNative::illustrated_colour(const Vector3 &p_dir, double p_ground, double p_slope) const {
	auto mix = [](double a, double b, double t) { return a + (b - a) * t; };
	const double degrees = sea_temperature(p_dir) - (p_ground > 0.0 ? p_ground : 0.0) / relief * 8800.0 / 1000.0 * 6.5;
	const double wet = clampd(grid_at(rain_grid, p_dir, 0.5) / 0.9, 0.0, 1.0);
	const double warm = clampd((degrees + 6.0) / 16.0, 0.0, 1.0);
	double cr = mix(0.78, 0.46, wet * warm), cg = mix(0.70, 0.60, wet * warm), cb = mix(0.46, 0.27, wet * warm);
	cr = mix(cr, 0.62, 1.0 - warm);
	cg = mix(cg, 0.64, 1.0 - warm);
	cb = mix(cb, 0.50, 1.0 - warm);
	const double tall = clampd(p_ground / relief, 0.0, 1.0);
	double t = smooth(0.12, 0.4, tall);
	cr = mix(cr, 0.58, t);
	cg = mix(cg, 0.50, t);
	cb = mix(cb, 0.38, t);
	t = smooth(0.3, 0.65, tall + p_slope * 0.4);
	cr = mix(cr, 0.50, t);
	cg = mix(cg, 0.48, t);
	cb = mix(cb, 0.46, t);
	const double snow = smooth(-1.0, -5.0, degrees) * (1.0 - 0.7 * smooth(0.5, 0.95, p_slope));
	cr = mix(cr, 0.95, snow);
	cg = mix(cg, 0.97, snow);
	cb = mix(cb, 1.00, snow);
	const double ice = smooth(-8.0, -14.0, degrees) * (1.0 - smooth(0.25, 0.6, p_slope)) * snow * 0.7;
	cr = mix(cr, 0.72, ice);
	cg = mix(cg, 0.86, ice);
	cb = mix(cb, 0.96, ice);
	const double sand = smooth(1.0, 0.0, p_ground) * 0.8;
	return Color((float)mix(cr, 0.90, sand), (float)mix(cg, 0.82, sand), (float)mix(cb, 0.55, sand), 1.0f);
}

Color PlanetCrustNative::rock_colour(const Vector3 &p_dir, double p_ground, double p_steep, double p_speckle, bool p_strata) const {
	int plate = 0;
	real_t edge = 0;
	bool is_continental = false;
	plate_at(p_dir, plate, edge, is_continental);
	double near_edge = std::exp(-(edge / rock_boundary) * (edge / rock_boundary));
	double tall = clampd(p_ground / relief, 0.0, 1.0);
	Vector3 p = p_dir * (real_t)radius;
	double old = smooth(-0.15, 0.3, craton.at(p));
	double regional = clampd(0.5 + 1.1 * (double)basin.at(p), 0.0, 1.0);
	enum { BASALT, ANDESITE, GRANITE, GNEISS, SCHIST, LIMESTONE, SANDSTONE, RED_SANDSTONE, SHALE };
	float w[9] = { 0, 0, 0, 0, 0, 0, 0, 0, 0 };
	if (!is_continental) {
		double cover = smooth(-0.2, 0.0, p_ground / relief);
		w[BASALT] = 0.5f;
		w[SHALE] = 0.25f;
		w[LIMESTONE] = (float)(0.1 + 0.25 * cover);
		w[SANDSTONE] = (float)(0.15 * cover);
		w[ANDESITE] = (float)(near_edge * 0.9);
	} else {
		double high = smooth(0.12, 0.5, tall);
		double basement = clampd(old + high, 0.0, 1.0);
		w[GRANITE] = (float)(basement * 0.55);
		w[GNEISS] = (float)(basement * 0.45);
		double sediment = 1.0 - basement;
		w[LIMESTONE] = (float)(sediment * smooth(0.58, 0.7, regional));
		w[RED_SANDSTONE] = (float)(sediment * smooth(0.3, 0.18, regional));
		w[SHALE] = (float)(sediment * smooth(0.1, 0.22, regional) * smooth(0.46, 0.34, regional));
		w[SANDSTONE] = (float)(sediment * smooth(0.3, 0.38, regional) * smooth(0.7, 0.6, regional));
		double schist = smooth(0.35, 0.65, regional);
		w[GNEISS] = (float)((double)w[GNEISS] + near_edge * 0.9 * (1.0 - schist));
		w[SCHIST] = (float)(near_edge * 1.1 * schist);
		w[ANDESITE] = (float)(near_edge * 0.3);
	}
	double total = 0.0;
	for (int index = 0; index < 9; index++) {
		total += w[index];
	}
	if (total <= 0.0001) {
		w[GRANITE] = 1.0f;
		total = 1.0;
	}
	for (int index = 0; index < 9; index++) {
		w[index] = (float)((double)w[index] / total);
	}
	Color rock(0.0f, 0.0f, 0.0f, 0.0f);
	for (int index = 0; index < 9; index++) {
		rock += rock_colours[index] * w[index];
	}
	double sedimentary = (double)w[LIMESTONE] + w[SANDSTONE] + w[RED_SANDSTONE] + w[SHALE];
	double bed = relief * 0.03 > 6.0 ? relief * 0.03 : 6.0;
	double layers = 0.5 + 0.5 * std::sin(p_ground / bed * 6.283185307179586);
	double on_land = smooth(0.0, 200.0, p_ground);
	float stripes = p_strata ? (float)(1.0 + (layers - 0.5) * 0.24 * sedimentary * on_land) : 1.0f; // (a map's big pixels would only alias them)
	rock = Color(rock.r * stripes, rock.g * stripes, rock.b * stripes, 0.0f);
	float speckle = (float)(0.94 + 0.12 * p_speckle);
	rock = Color(rock.r * speckle, rock.g * speckle, rock.b * speckle, 0.0f);
	float steep_mix = (float)smooth(0.35, 0.8, p_steep);
	Color dark(rock.r * 0.62f, rock.g * 0.62f, rock.b * 0.62f, 0.0f);
	float r = rock.r + (dark.r - rock.r) * steep_mix;
	float g = rock.g + (dark.g - rock.g) * steep_mix;
	float b = rock.b + (dark.b - rock.b) * steep_mix;
	// permanent snow and ice where the cold keeps it (PlanetRock.colour)
	const double cold = sea_temperature(p_dir) - 0.0065 * (p_ground > 0.0 ? p_ground : 0.0);
	// scree: pale rubble that has fallen on the moderately steep slopes of the high ground (PlanetRock.colour)
	const double scree = smooth(0.2, 0.38, p_steep) * (1.0 - smooth(0.55, 0.75, p_steep)) * smooth(150.0, 600.0, p_ground) * 0.45;
	r += (0.58f - r) * (float)scree;
	g += (0.56f - g) * (float)scree;
	b += (0.52f - b) * (float)scree;
	// wetland: dark green-brown on the low, flat, wet ground (PlanetRock.colour)
	const double wet_here = clampd(grid_at(rain_grid, p_dir, 0.5) / 0.9, 0.0, 1.0);
	const double wetland = smooth(25.0, 4.0, p_ground) * (1.0 - smooth(0.05, 0.2, p_steep)) * smooth(0.5, 0.9, wet_here) * smooth(2.0, 10.0, cold) * smooth(0.0, 1.0, p_ground) * 0.55;
	r += (0.22f - r) * (float)wetland;
	g += (0.30f - g) * (float)wetland;
	b += (0.16f - b) * (float)wetland;
	// soil: deep and dark where it is wet and mild, thin and pale where it is dry, none on steep rock
	const double fertile = clampd(grid_at(rain_grid, p_dir, 0.5) / 0.9, 0.0, 1.0) * smooth(-5.0, 10.0, cold);
	const double soil = on_land * (1.0 - smooth(0.2, 0.55, p_steep)) * (0.3 + 0.7 * fertile) * 0.6;
	const float soil_r = (float)(0.64 + (0.27 - 0.64) * fertile), soil_g = (float)(0.55 + (0.20 - 0.55) * fertile);
	const float soil_b = (float)(0.38 + (0.13 - 0.38) * fertile);
	r += (soil_r - r) * (float)soil;
	g += (soil_g - g) * (float)soil;
	b += (soil_b - b) * (float)soil;
	double snow = smooth(-0.5, -4.5, cold) * smooth(0.0, 60.0, p_ground);
	snow *= 1.0 - 0.85 * smooth(0.5, 0.95, p_steep);
	snow *= 0.92;
	r += (0.93f - r) * (float)snow;
	g += (0.95f - g) * (float)snow;
	b += (0.98f - b) * (float)snow;
	// glacier ice: blue-white on the gentle ground where it is very cold (PlanetRock.colour)
	const double ice = smooth(-7.0, -13.0, cold) * (1.0 - smooth(0.25, 0.6, p_steep)) * snow * 0.7;
	r += (0.72f - r) * (float)ice;
	g += (0.86f - g) * (float)ice;
	b += (0.96f - b) * (float)ice;
	// beaches: low, level ground by the sea (PlanetRock.colour)
	double beach = smooth(4.0, 0.5, p_ground) * smooth(0.0, 0.5, p_ground + 0.5);
	beach *= 1.0 - smooth(0.15, 0.45, p_steep);
	beach *= 0.85 * (1.0 - snow);
	r += (0.80f - r) * (float)beach;
	g += (0.72f - g) * (float)beach;
	b += (0.52f - b) * (float)beach;
	return Color((float)clampd(r, 0.0, 1.0), (float)clampd(g, 0.0, 1.0), (float)clampd(b, 0.0, 1.0), 1.0f);
}

void PlanetCrustNative::height_chunk(int p_chunk, int64_t p_job) {
	const HeightJob *job = reinterpret_cast<const HeightJob *>((intptr_t)p_job);
	const int from = p_chunk * 4096;
	const int to = std::min(from + 4096, job->count);
	for (int index = from; index < to; index++) {
		const Vector3 dir = job->dirs[index];
		switch (job->mode) {
			case GROUND:
				job->out[index] = (float)ground_height(dir);
				break;
			case TECTONIC:
				job->out[index] = (float)tectonic_height(dir);
				break;
			case MACRO_AND_TECTONIC: {
				const double raised = tectonic_height(dir);
				job->out[index] = (float)macro_ground(raised - sea, dir * (real_t)radius);
				job->out2[index] = (float)raised;
				break;
			}
			case BROAD:
				job->out[index] = (float)macro_ground(tectonic_height(dir) - sea, dir * (real_t)radius, job->pixel);
				break;
			default:
				job->out[index] = (float)macro_ground(tectonic_height(dir) - sea, dir * (real_t)radius);
		}
	}
}

PackedFloat32Array PlanetCrustNative::heights_by(int p_mode, const PackedVector3Array &p_dirs, double p_pixel) const {
	PackedFloat32Array result;
	PackedFloat32Array second;
	return run_heights(p_mode, p_dirs, result, second, p_pixel);
}

PackedFloat32Array PlanetCrustNative::run_heights(int p_mode, const PackedVector3Array &p_dirs, PackedFloat32Array &r_result,
		PackedFloat32Array &r_second, double p_pixel) const {
	PackedFloat32Array &result = r_result;
	result.resize(p_dirs.size());
	if (p_mode == MACRO_AND_TECTONIC) {
		r_second.resize(p_dirs.size());
	}
	HeightJob job = { p_mode, p_dirs.ptr(), result.ptrw(), p_mode == MACRO_AND_TECTONIC ? r_second.ptrw() : nullptr, (int)p_dirs.size(), p_pixel };
	const int chunks = (job.count + 4095) / 4096;
	if (chunks <= 4) { // few points (a tile, a row): not worth waking the workers
		for (int chunk = 0; chunk < chunks; chunk++) {
			const_cast<PlanetCrustNative *>(this)->height_chunk(chunk, (int64_t)(intptr_t)&job);
		}
		return result;
	}
	// threads of our own, each taking the next chunk (the engine's pool would not spread this group)
	std::atomic<int> next(0);
	PlanetCrustNative *self = const_cast<PlanetCrustNative *>(this);
	auto work = [&]() {
		for (int chunk = next++; chunk < chunks; chunk = next++) {
			self->height_chunk(chunk, (int64_t)(intptr_t)&job);
		}
	};
	const int count = std::max(2, std::min(8, (int)std::thread::hardware_concurrency() - 1));
	std::vector<std::thread> threads;
	for (int index = 1; index < count && index < chunks; index++) {
		threads.emplace_back(work);
	}
	work();
	for (std::thread &thread : threads) {
		thread.join();
	}
	return result;
}

Dictionary PlanetCrustNative::macro_and_tectonic_heights(const PackedVector3Array &p_dirs) const {
	PackedFloat32Array macro;
	PackedFloat32Array raised;
	run_heights(MACRO_AND_TECTONIC, p_dirs, macro, raised);
	Dictionary result;
	result["macro"] = macro;
	result["tectonic"] = raised;
	// how far the plates have raised the ground (0 at the sea .. 1 at 0.4 relief above it)
	PackedFloat32Array uplift;
	uplift.resize(raised.size());
	float *out = uplift.ptrw();
	for (int index = 0; index < raised.size(); index++) {
		const double lift = ((double)raised[index] - sea) / 0.4;
		out[index] = (float)(lift < 0.0 ? 0.0 : (lift > 1.0 ? 1.0 : lift));
	}
	result["uplift"] = uplift;
	return result;
}

double PlanetCrustNative::height_at(const Vector3 &p_dir) const {
	return ground_height(p_dir.normalized());
}

PackedFloat32Array PlanetCrustNative::heights(const PackedVector3Array &p_dirs) const {
	return heights_by(GROUND, p_dirs);
}

PackedFloat32Array PlanetCrustNative::tectonic_heights(const PackedVector3Array &p_dirs) const {
	return heights_by(TECTONIC, p_dirs);
}

PackedByteArray PlanetCrustNative::smooth_rgb(const PackedByteArray &p_rgb, int p_width, int p_height) const {
	PackedByteArray out = p_rgb;
	if (p_width < 3 || p_height < 3 || p_rgb.size() < p_width * p_height * 3) {
		return out;
	}
	const uint8_t *in = p_rgb.ptr();
	uint8_t *result = out.ptrw();
	for (int y = 0; y < p_height; y++) {
		for (int x = 0; x < p_width; x++) {
			int total[3] = { 0, 0, 0 };
			int weight = 0;
			for (int dy = -1; dy <= 1; dy++) {
				for (int dx = -1; dx <= 1; dx++) {
					const int ny = y + dy < 0 ? 0 : (y + dy >= p_height ? p_height - 1 : y + dy);
					const int nx = (x + dx + p_width) % p_width;
					const int w = (dx == 0 && dy == 0) ? 4 : (dx == 0 || dy == 0 ? 2 : 1);
					const uint8_t *n = in + (ny * p_width + nx) * 3;
					total[0] += n[0] * w;
					total[1] += n[1] * w;
					total[2] += n[2] * w;
					weight += w;
				}
			}
			uint8_t *target = result + (y * p_width + x) * 3;
			for (int c = 0; c < 3; c++) {
				target[c] = (uint8_t)(total[c] / weight);
			}
		}
	}
	return out;
}

PackedByteArray PlanetCrustNative::coast_lines(const PackedByteArray &p_rgb, const PackedByteArray &p_land, int p_width, int p_height) const {
	PackedByteArray out = p_rgb;
	if (p_width < 2 || p_height < 2 || p_rgb.size() < p_width * p_height * 3 || p_land.size() < p_width * p_height) {
		return out;
	}
	// the land mask by a majority of the 3x3 pixels round each (the coast's own grain is not a coast)
	std::vector<uint8_t> voted((size_t)p_width * (size_t)p_height);
	for (int y = 0; y < p_height; y++) {
		for (int x = 0; x < p_width; x++) {
			int votes = 0;
			for (int dy = -1; dy <= 1; dy++) {
				for (int dx = -1; dx <= 1; dx++) {
					const int ny = y + dy < 0 ? 0 : (y + dy >= p_height ? p_height - 1 : y + dy);
					votes += p_land[ny * p_width + (x + dx + p_width) % p_width] ? 1 : 0;
				}
			}
			voted[(size_t)y * (size_t)p_width + x] = votes >= 5 ? 1 : 0;
		}
	}
	const uint8_t *land = voted.data();
	uint8_t *result = out.ptrw();
	for (int y = 0; y < p_height - 1; y++) {
		for (int x = 0; x < p_width; x++) {
			const int here = land[y * p_width + x];
			const int east = land[y * p_width + (x + 1) % p_width];
			const int south = land[(y + 1) * p_width + x];
			if (here != east || here != south) {
				uint8_t *target = result + (y * p_width + x) * 3;
				for (int c = 0; c < 3; c++) {
					target[c] = (uint8_t)(target[c] * 0.45);
				}
			}
		}
	}
	return out;
}

PackedByteArray PlanetCrustNative::despeckle(const PackedByteArray &p_rgb, int p_width, int p_height) const {
	PackedByteArray out = p_rgb;
	if (p_width < 3 || p_height < 3 || p_rgb.size() < p_width * p_height * 3) {
		return out;
	}
	const uint8_t *in = p_rgb.ptr();
	uint8_t *result = out.ptrw();
	for (int y = 1; y < p_height - 1; y++) {
		for (int x = 1; x < p_width - 1; x++) {
			double mean[3] = { 0.0, 0.0, 0.0 };
			for (int dy = -1; dy <= 1; dy++) {
				for (int dx = -1; dx <= 1; dx++) {
					if (dx != 0 || dy != 0) {
						const uint8_t *n = in + ((y + dy) * p_width + x + dx) * 3;
						mean[0] += n[0];
						mean[1] += n[1];
						mean[2] += n[2];
					}
				}
			}
			for (double &channel : mean) {
				channel /= 8.0;
			}
			double spread = 0.0;
			for (int dy = -1; dy <= 1; dy++) {
				for (int dx = -1; dx <= 1; dx++) {
					if (dx != 0 || dy != 0) {
						const uint8_t *n = in + ((y + dy) * p_width + x + dx) * 3;
						for (int c = 0; c < 3; c++) {
							spread = std::max(spread, std::abs(n[c] - mean[c]));
						}
					}
				}
			}
			const uint8_t *centre = in + (y * p_width + x) * 3;
			double gap = 0.0;
			for (int c = 0; c < 3; c++) {
				gap = std::max(gap, std::abs(centre[c] - mean[c]));
			}
			if (gap > 28.0 && spread < gap * 0.5) {
				uint8_t *target = result + (y * p_width + x) * 3;
				for (int c = 0; c < 3; c++) {
					target[c] = (uint8_t)(mean[c] + 0.5);
				}
			}
		}
	}
	return out;
}

namespace {
struct Stop {
	double at, r, g, b;
};

// The colour of `t` (0..1) along a list of stops (PlanetChart.ramp).
void along(const Stop *p_stops, int p_count, double p_t, double &r_r, double &r_g, double &r_b) {
	p_t = p_t < 0.0 ? 0.0 : (p_t > 1.0 ? 1.0 : p_t);
	for (int index = 0; index < p_count - 1; index++) {
		if (p_t <= p_stops[index + 1].at) {
			const double span = std::max(p_stops[index + 1].at - p_stops[index].at, 0.0001);
			const double k = (p_t - p_stops[index].at) / span;
			r_r = p_stops[index].r + (p_stops[index + 1].r - p_stops[index].r) * k;
			r_g = p_stops[index].g + (p_stops[index + 1].g - p_stops[index].g) * k;
			r_b = p_stops[index].b + (p_stops[index + 1].b - p_stops[index].b) * k;
			return;
		}
	}
	r_r = p_stops[p_count - 1].r;
	r_g = p_stops[p_count - 1].g;
	r_b = p_stops[p_count - 1].b;
}

const Stop ELEVATION_STOPS[] = { { 0.0, 0.05, 0.12, 0.4 }, { 0.33, 0.3, 0.6, 0.85 }, { 0.36, 0.25, 0.55, 0.25 },
	{ 0.55, 0.85, 0.8, 0.35 }, { 0.8, 0.6, 0.4, 0.25 }, { 1.0, 1.0, 1.0, 1.0 } };
const Stop TEMPERATURE_STOPS[] = { { 0.0, 0.35, 0.2, 0.75 }, { 0.2, 0.25, 0.6, 1.0 }, { 0.46, 0.45, 0.85, 0.6 },
	{ 0.67, 1.0, 0.9, 0.25 }, { 0.8, 0.98, 0.5, 0.1 }, { 0.92, 0.8, 0.12, 0.08 }, { 1.0, 0.4, 0.04, 0.02 } };
const Stop RAIN_STOPS[] = { { 0.0, 0.95, 0.85, 0.6 }, { 0.3, 0.8, 0.9, 0.7 }, { 0.65, 0.4, 0.75, 0.85 }, { 1.0, 0.1, 0.3, 0.8 } };
const Stop SLOPE_STOPS[] = { { 0.0, 0.95, 0.95, 0.9 }, { 0.4, 0.75, 0.6, 0.35 }, { 1.0, 0.3, 0.15, 0.1 } };

// A grid of width x height cells (rows from the north pole, columns from the west) read bilinearly at a direction.
double read_grid(const float *p_grid, int p_width, int p_height, const Vector3 &p_dir) {
	const double pi = 3.14159265358979323846;
	const double lat = std::asin(std::max(-1.0, std::min(1.0, (double)p_dir.y)));
	const double lon = std::atan2((double)p_dir.z, (double)p_dir.x);
	const double fx = (lon + pi) / (2.0 * pi) * p_width - 0.5;
	const double fy = (0.5 - lat / pi) * p_height - 0.5;
	const int x0 = (int)std::floor(fx), y0 = (int)std::floor(fy);
	const double tx = fx - x0, ty = fy - y0;
	double value = 0.0;
	for (int dy = 0; dy < 2; dy++) {
		for (int dx = 0; dx < 2; dx++) {
			const double w = (dx ? tx : 1.0 - tx) * (dy ? ty : 1.0 - ty);
			const int row = std::max(0, std::min(p_height - 1, y0 + dy));
			const int column = (((x0 + dx) % p_width) + p_width) % p_width;
			value += (double)p_grid[row * p_width + column] * w;
		}
	}
	return value;
}
} // namespace

void PlanetCrustNative::set_weather(const Dictionary &p_config) {
	configure(cloud_big_a, p_config["big_a"]);
	configure(cloud_big_b, p_config["big_b"]);
	configure(cloud_small, p_config["small"]);
	configure(cloud_warp, p_config["warp"]);
	configure(cloud_pool, p_config["pool"]);
	belt_shift = p_config["belt_shift"];
	belt_power = p_config["belt_power"];
	storm_shift = p_config["storm_shift"];
	storm_power = p_config["storm_power"];
	sink_shift = p_config["sink_shift"];
	sink_power = p_config["sink_power"];
	pool_break = p_config["pool_break"];
	cloud_wind_k = p_config["wind_k"];
	season_mean = p_config["season_mean"];
}

Vector2 PlanetCrustNative::cloud_cells(const Vector3 &p_dir, double p_macro, const float *p_grid, int p_gw, int p_gh,
		double p_decl, double p_days) const {
	const double pi = 3.14159265358979323846;
	const double tau = 2.0 * pi;
	const double lat = std::asin(clampd((double)p_dir.y, -1.0, 1.0));
	// the air's readiness to make cloud (PlanetWeather.readiness)
	const double degrees = read_grid(p_grid, p_gw, p_gh, p_dir);
	const double wet = clampd(grid_at(rain_grid, p_dir, 0.5) / 1.2, 0.0, 1.0);
	const double moisture = p_macro < 0.0 ? 0.25 + 0.75 * smooth(-30.0, 30.0, degrees)
										  : wet * (0.25 + 0.75 * smooth(-30.0, 25.0, degrees));
	const double south = lat < 0.0 ? -1.0 : 1.0;
	const double pool_here = (double)cloud_pool.at(p_dir);
	const double pools = 0.5 + 0.5 * pool_here;
	const double low = 1.0 - 0.65 * pool_break, high = 1.0 + 0.4 * pool_break;
	const double pools_factor = low + (high - low) * smooth(0.2, 0.8, pools);
	const double trade_x = (lat - 0.4 * p_decl - belt_shift) / 0.17;
	const double trade = 0.75 * belt_power * pools_factor * std::exp(-trade_x * trade_x);
	const double lean = 0.12 * std::sin(std::atan2((double)p_dir.z, (double)p_dir.x) * 2.0 + pool_here * 3.0);
	const double storm_lat = south * (0.87 + lean + storm_shift) + 0.3 * p_decl;
	const double storm_x = (lat - storm_lat) / 0.2;
	const double storms = 0.55 * storm_power * std::exp(-storm_x * storm_x);
	const double high_lat = south * (0.48 + sink_shift) + 0.3 * p_decl;
	const double sink_x = (lat - high_lat) / 0.15;
	const double sinking = sink_power * std::exp(-sink_x * sink_x);
	double ready = 0.06 + 0.3 * moisture + 0.8 * trade * moisture;
	ready += 0.9 * storms * (0.5 + 0.5 * moisture) + 0.2 * wet * moisture;
	ready += 0.25 * smooth(0.9, 1.4, std::abs(lat));
	if (p_macro >= 0.0 && season_mean.size() >= p_gw * p_gh) { // the monsoon
		const double tropics = std::exp(-(lat / 0.6) * (lat / 0.6));
		const double anomaly = degrees - read_grid(season_mean.ptr(), p_gw, p_gh, p_dir);
		ready += tropics * (0.5 * smooth(0.0, 8.0, anomaly) * (0.3 + wet) - 0.2 * smooth(0.0, 8.0, -anomaly));
	}
	const double lo = 1.0 - 0.4 * pool_break, hi = 1.0 + 0.3 * pool_break;
	ready *= lo + (hi - lo) * smooth(0.25, 0.75, pools);
	ready = clampd(ready * (1.0 - 0.65 * sinking), 0.0, 1.0);
	// the pattern, carried by the wind and drawn twice (PlanetWeather.cloud_cells)
	const double morph = 0.5 + 0.5 * std::sin(p_days * 0.45);
	const double shear = 2.5;
	const double first = std::fmod(std::fmod(p_days, shear) + shear, shear);
	const double second = std::fmod(std::fmod(p_days + shear * 0.5, shear) + shear, shear);
	const double weight = 1.0 - std::abs(2.0 * first / shear - 1.0);
	double pattern = 0.0, cells = 0.0;
	for (int turn = 0; turn < 2; turn++) {
		const double drift = turn == 0 ? first : second;
		const double shift = -std::cos(lat * cloud_wind_k) * 0.035 * tau * drift;
		const double lon = std::atan2((double)p_dir.z, (double)p_dir.x) - shift;
		Vector3 carried((real_t)(std::cos(lat) * std::cos(lon)), p_dir.y, (real_t)(std::cos(lat) * std::sin(lon)));
		const double bend_x = (double)cloud_warp.at(carried);
		const double bend_y = (double)cloud_warp.at(Vector3(carried.z + 7.3f, carried.x - 3.1f, carried.y + 1.7f));
		carried = (carried + Vector3((real_t)bend_x, (real_t)bend_y, (real_t)(bend_x - bend_y)) * (real_t)0.45).normalized();
		const double a = (double)cloud_big_a.at(carried), b = (double)cloud_big_b.at(carried);
		const double big = a + (b - a) * morph;
		const double clumps = (double)cloud_small.at(carried);
		const double share = turn == 0 ? weight : 1.0 - weight;
		pattern += clampd(0.5 + 0.5 * (0.75 * big + 0.35 * clumps), 0.0, 1.0) * share;
		cells += clumps * share;
	}
	const double threshold = 0.97 - ready * 0.8;
	return Vector2((real_t)smooth(threshold - 0.12, threshold + 0.12, pattern), (real_t)cells);
}

PackedByteArray PlanetCrustNative::data_row(int p_layer, const PackedVector3Array &p_dirs, const PackedFloat32Array &p_grounds,
		const PackedFloat32Array &p_macros, const PackedFloat32Array &p_east, const PackedFloat32Array &p_north,
		double p_step_lon, const Dictionary &p_params) const {
	PackedByteArray out;
	out.resize(p_dirs.size() * 3);
	uint8_t *bytes = out.ptrw();
	const double pi = 3.14159265358979323846;
	const double metres = p_step_lon * radius;
	const PackedFloat32Array grid = p_params.get("grid", PackedFloat32Array());
	const int gw = p_params.get("gw", 96), gh = p_params.get("gh", 48);
	const double sun_lon = p_params.get("sun_lon", 0.0), clear = p_params.get("clear", 1.0);
	const bool have_grid = grid.size() >= gw * gh;
	for (int index = 0; index < p_dirs.size(); index++) {
		const Vector3 dir = p_dirs[index];
		const double ground = p_grounds[index];
		const double rise_east = (double)p_east[index] - ground, rise_north = (double)p_north[index] - ground;
		const double broad = p_macros.size() > index ? (double)p_macros[index] : ground;
		double r = 1.0, g = 1.0, b = 1.0;
		switch (p_layer) {
			case 1: { // elevation
				double shown = ground;
				if (metres > 2000.0 && ground >= 0.0) {
					shown = std::max(ground + (rise_east + rise_north) * 0.25, 0.0);
				}
				double deep = ground;
				if (metres > 2000.0 && ground < 0.0) {
					deep = std::min((ground + (ground + rise_east + rise_north)) * 0.5, 0.0);
				}
				double t = ground < 0.0 ? 0.33 + (0.0 - 0.33) * clampd(-deep / (relief * 0.35), 0.0, 1.0)
										 : 0.36 + (1.0 - 0.36) * clampd(shown / relief, 0.0, 1.0);
				along(ELEVATION_STOPS, 6, t, r, g, b);
				if (ground >= 0.0 && metres <= 2000.0) { // contour lines every 5 % of the relief
					const double interval = relief * 0.05;
					const double band = std::floor(ground / interval);
					if (band != std::floor((ground + rise_east) / interval) || band != std::floor((ground + rise_north) / interval)) {
						r *= 0.7;
						g *= 0.7;
						b *= 0.7;
					}
				}
			} break;
			case 2:
			case 7: { // temperature now / mean temperature
				const double lapse = (broad > 0.0 ? broad : 0.0) / relief * 8800.0 / 1000.0 * 6.5;
				double degrees = sea_temperature(dir);
				if (p_layer == 2 && have_grid) {
					degrees = read_grid(grid.ptr(), gw, gh, dir);
					const double lon = std::atan2((double)dir.z, (double)dir.x);
					double angle = std::fmod(lon - sun_lon + 3.0 * pi, 2.0 * pi) - pi;
					const double hour = std::fmod(12.0 + angle / (2.0 * pi) * 24.0 + 24.0, 24.0);
					const double swing = broad >= 0.0 ? 6.0 : 0.8;
					degrees += swing * std::cos((hour - 14.5) / 24.0 * 2.0 * pi) * clear;
				}
				degrees -= lapse;
				along(TEMPERATURE_STOPS, 7, (degrees + 30.0) / 75.0, r, g, b);
			} break;
			case 3: { // rain
				along(RAIN_STOPS, 4, grid_at(rain_grid, dir, 0.5) / 1.2, r, g, b);
				if (ground < 0.0) {
					r *= 0.75;
					g *= 0.75;
					b *= 0.75;
				}
			} break;
			case 8:
			case 9:
			case 11: { // clouds, satellite, the cloud cover alone
				const bool ready_grid = have_grid && season_mean.size() >= gw * gh;
				double cover = 0.0;
				if (ready_grid) {
					cover = (double)cloud_cells(dir, broad, grid.ptr(), gw, gh, p_params.get("decl", 0.0), p_params.get("days", 0.0)).x;
				}
				if (p_layer == 11) {
					r = g = b = cover;
					break;
				}
				// the ground below: the sea by depth (with its ice), the land as the map shows it
				double lr, lg, lb;
				if (ground < 0.0) {
					const double depth = std::sqrt(clampd(-ground / (relief * 0.35), 0.0, 1.0));
					if (p_layer == 8) {
						const double ice = sea_ice(dir) * 0.92;
						lr = (0.32 + (0.03 - 0.32) * depth) * (1.0 - ice) + 0.90 * ice;
						lg = (0.62 + (0.12 - 0.62) * depth) * (1.0 - ice) + 0.94 * ice;
						lb = (0.78 + (0.33 - 0.78) * depth) * (1.0 - ice) + 0.98 * ice;
					} else {
						lr = 0.12 + (0.04 - 0.12) * depth;
						lg = 0.27 + (0.1 - 0.27) * depth;
						lb = 0.52 + (0.3 - 0.52) * depth;
					}
				} else if (p_layer == 8) {
					const Color land = illustrated_colour(dir, ground, 0.1);
					lr = land.r;
					lg = land.g;
					lb = land.b;
				} else { // satellite land
					const double green = clampd(grid_at(rain_grid, dir, 0.5) / 0.9, 0.0, 1.0);
					const double degrees = sea_temperature(dir) - (broad > 0.0 ? broad : 0.0) / relief * 8800.0 / 1000.0 * 6.5;
					const double warm = clampd((degrees + 8.0) / 14.0, 0.0, 1.0);
					const double mixed = green * warm;
					lr = 0.62 + (0.17 - 0.62) * mixed;
					lg = 0.56 + (0.30 - 0.56) * mixed;
					lb = 0.38 + (0.10 - 0.38) * mixed;
					lr += (0.5 - lr) * (1.0 - warm);
					lg += (0.5 - lg) * (1.0 - warm);
					lb += (0.42 - lb) * (1.0 - warm);
					const double snow = 1.0 - clampd((degrees + 6.0) / 5.0, 0.0, 1.0);
					lr += (0.95 - lr) * snow;
					lg += (0.97 - lg) * snow;
					lb += (1.0 - lb) * snow;
					const double lat_part = std::sqrt(std::max(1.0 - (double)dir.y * (double)dir.y, 0.04));
					const double shade = clampd(1.0 - 1.2 * 2.0 * 0.5 * (rise_east - rise_north) / (metres * lat_part), 0.75, 1.2);
					lr *= shade;
					lg *= shade;
					lb *= shade;
				}
				if (p_layer == 8) {
					lr *= 0.55;
					lg *= 0.55;
					lb *= 0.55;
					r = lr + (0.97 - lr) * cover * 0.92;
					g = lg + (0.98 - lg) * cover * 0.92;
					b = lb + (1.0 - lb) * cover * 0.92;
				} else {
					const double fade = 0.25 * (1.0 - cover);
					const double cr = 0.93 + (0.72 - 0.93) * fade, cg = 0.95 + (0.75 - 0.95) * fade, cb = 0.98 + (0.82 - 0.98) * fade;
					r = lr + (cr - lr) * cover * 0.92;
					g = lg + (cg - lg) * cover * 0.92;
					b = lb + (cb - lb) * cover * 0.92;
				}
			} break;
			case 10: { // the atlas: an old parchment map (flat inks, hatched mountains, pale water)
				const double pi = 3.14159265358979323846;
				const double lit = clampd(1.0 - 1.1 * (rise_east - rise_north) / metres, 0.8, 1.2);
				// the paper: a warm parchment with a slow stain
				const double lat_angle = std::asin(clampd((double)dir.y, -1.0, 1.0));
				const double lon_angle = std::atan2((double)dir.z, (double)dir.x);
				const double stain = 0.5 + 0.5 * std::sin(lon_angle * 7.0 + 2.0 * std::sin(lat_angle * 5.0));
				const double paper_r = 0.86 - 0.05 * stain, paper_g = 0.75 - 0.05 * stain, paper_b = 0.52 - 0.05 * stain;
				if (ground < 0.0) {
					const double depth = clampd(-ground / (relief * 0.35), 0.0, 1.0);
					// the sea: a grey blue wash on the paper, darker with depth
					const double wash = 0.55 + 0.25 * depth;
					r = paper_r + (0.60 - paper_r) * wash;
					g = paper_g + (0.67 - paper_g) * wash;
					b = paper_b + (0.69 - paper_b) * wash;
					const double ice = sea_ice(dir) * 0.8;
					r += (0.90 - r) * ice;
					g += (0.88 - g) * ice;
					b += (0.80 - b) * ice;
					break;
				}
				const double wet = clampd(grid_at(rain_grid, dir, 0.5) / 0.9, 0.0, 1.0);
				const double degrees = sea_temperature(dir) - (broad > 0.0 ? broad : 0.0) / relief * 8800.0 / 1000.0 * 6.5;
				const double warm = clampd((degrees + 4.0) / 16.0, 0.0, 1.0);
				const double tall = clampd(ground / (relief * 0.5), 0.0, 1.0);
				// the lowland: paper where it is dry, a soft green wash where it is wet, a deeper green in forests
				const double green = smooth(0.15, 0.7, wet) * warm;
				double lr = paper_r + (0.50 - paper_r) * green;
				double lg = paper_g + (0.62 - paper_g) * green;
				double lb = paper_b + (0.22 - paper_b) * green;
				const double forest = smooth(0.6, 0.95, wet) * warm;
				lr += (0.36 - lr) * forest;
				lg += (0.50 - lg) * forest;
				lb += (0.16 - lb) * forest;
				// the hills and mountains: a brown ink, hatched like the drawn ranges of an old map
				// only the broad ground counts (its small bumps are everywhere): real hills and ranges get ink
				const double broad_tall = clampd((broad > 0.0 ? broad : 0.0) / (relief * 0.5), 0.0, 1.0);
				const double hill = smooth(0.2, 0.5, broad_tall);
				const double step_angle = std::max(p_step_lon, 1.0e-9);
				// the strokes wander a little, like a hand's, instead of a regular grid
				const double wander = 2.5 * (double)warp.at(dir * (real_t)(6.0 / std::max(step_angle * radius / 1000.0, 0.05)));
				const double phase = (lon_angle * 0.9 + lat_angle * 1.4) / (step_angle * 7.0) + wander;
				const double hatch = 0.5 + 0.5 * std::sin(phase * 2.0 * pi);
				const double ink = hill * (0.55 + 0.45 * hatch);
				lr += (0.55 - lr) * ink;
				lg += (0.40 - lg) * ink;
				lb += (0.22 - lb) * ink;
				const double snow = smooth(-2.0, -7.0, degrees);
				lr += (0.95 - lr) * snow;
				lg += (0.92 - lg) * snow;
				lb += (0.84 - lb) * snow;
				r = lr * lit;
				g = lg * lit;
				b = lb * lit;
			} break;
			case 4: { // biome
				if (ground < 0.0) {
					const double depth = clampd(-ground / (relief * 0.35), 0.0, 1.0);
					r = 0.2 + (0.05 - 0.2) * depth;
					g = 0.4 + (0.12 - 0.4) * depth;
					b = 0.7 + (0.35 - 0.7) * depth;
					break;
				}
				const double slope = clampd(std::sqrt(rise_east * rise_east + rise_north * rise_north) / metres, 0.0, 1.0);
				const double wet = clampd(grid_at(rain_grid, dir, 0.5) / 1.2, 0.0, 1.0);
				const double degrees = sea_temperature(dir) - (ground > 0.0 ? ground : 0.0) / relief * 8800.0 / 1000.0 * 6.5;
				static const double palette[7][3] = { { 0.93, 0.85, 0.55 }, { 0.6, 0.8, 0.3 }, { 0.1, 0.45, 0.15 },
					{ 0.5, 0.5, 0.52 }, { 0.97, 0.98, 1.0 }, { 0.3, 0.55, 0.5 }, { 0.9, 0.6, 0.25 } };
				int biome = 1; // meadow
				if (ground < 1.4) {
					biome = wet < 0.5 ? 0 : 5; // beach or marsh
				} else if (degrees < -14.0) {
					biome = 4;
				} else if (slope > 0.62 || ground > relief * 0.5) {
					biome = 3;
				} else if (wet < 0.2 && degrees > 2.0) {
					biome = 6;
				} else if (wet > 0.5) {
					biome = 2;
				}
				r = palette[biome][0];
				g = palette[biome][1];
				b = palette[biome][2];
			} break;
			case 5: { // plates
				int plate = 0;
				real_t edge = 0;
				bool is_continental = false;
				plate_at(dir, plate, edge, is_continental);
				const double hue = std::fmod((double)plate * 0.61803, 1.0) * 6.0;
				const double saturation = is_continental ? 0.55 : 0.25, value = is_continental ? 0.95 : 0.6;
				const int sector = (int)hue;
				const double f = hue - sector;
				const double p = value * (1.0 - saturation), q = value * (1.0 - saturation * f), t = value * (1.0 - saturation * (1.0 - f));
				switch (sector % 6) {
					case 0: r = value; g = t; b = p; break;
					case 1: r = q; g = value; b = p; break;
					case 2: r = p; g = value; b = t; break;
					case 3: r = p; g = q; b = value; break;
					case 4: r = t; g = p; b = value; break;
					default: r = value; g = p; b = q; break;
				}
				if (ground < 0.0) {
					r *= 0.65;
					g *= 0.65;
					b *= 0.65;
				}
				if (edge < 0.012) {
					r = g = b = 0.0;
				}
			} break;
			case 6: { // slope
				if (ground < 0.0) {
					r = 0.2;
					g = 0.4;
					b = 0.7;
				} else {
					const double slope = clampd(std::sqrt(rise_east * rise_east + rise_north * rise_north) / metres, 0.0, 1.0);
					along(SLOPE_STOPS, 3, slope / 0.6, r, g, b);
				}
			} break;
			default:
				break;
		}
		bytes[index * 3] = (uint8_t)clampd((double)(int)(clampd(r, 0.0, 1.0) * 255.0), 0.0, 255.0);
		bytes[index * 3 + 1] = (uint8_t)clampd((double)(int)(clampd(g, 0.0, 1.0) * 255.0), 0.0, 255.0);
		bytes[index * 3 + 2] = (uint8_t)clampd((double)(int)(clampd(b, 0.0, 1.0) * 255.0), 0.0, 255.0);
	}
	return out;
}

PackedByteArray PlanetCrustNative::terrain_row(const PackedVector3Array &p_dirs, const PackedFloat32Array &p_grounds,
		const PackedFloat32Array &p_east, const PackedFloat32Array &p_north, double p_step_lon, double p_calm) const {
	PackedByteArray out;
	out.resize(p_dirs.size() * 3);
	uint8_t *bytes = out.ptrw();
	for (int index = 0; index < p_dirs.size(); index++) {
		const double ground = p_grounds[index];
		double r, g, b;
		double lake_level_here = -1.0e9;
		const bool in_lake = ground >= 0.0 && p_step_lon * radius <= 20.0 && lake_weight(p_dirs[index], lake_level_here) > 0.5 && ground < lake_level_here;
		if (in_lake) { // a lake: the water, darker where it is deeper
			const double depth = std::sqrt(clampd((lake_level_here - ground) / 12.0, 0.0, 1.0));
			r = 0.27 + (0.12 - 0.27) * depth;
			g = 0.52 + (0.32 - 0.52) * depth;
			b = 0.78 + (0.62 - 0.78) * depth;
		} else if (ground < 0.0) {
			const double depth = std::sqrt(clampd(-ground / (relief * 0.35), 0.0, 1.0));
			r = 0.32 + (0.03 - 0.32) * depth;
			g = 0.62 + (0.12 - 0.62) * depth;
			b = 0.78 + (0.33 - 0.78) * depth;
			// sea ice where the sea's mean temperature is below its freezing point (PlanetChart)
			const double ice = sea_ice(p_dirs[index]) * 0.92;
			r += (0.90 - r) * ice;
			g += (0.94 - g) * ice;
			b += (0.98 - b) * ice;
		} else {
			const double rise_east = ((double)p_east[index] - ground) * p_calm; // (calm < 1: a gentler relief for big pixels)
			const double rise_north = ((double)p_north[index] - ground) * p_calm;
			const double slope = clampd(std::sqrt(rise_east * rise_east + rise_north * rise_north) / (p_step_lon * radius), 0.0, 1.0);
			// the map's illustrated look (PlanetChart._illustrated_color) at every zoom: the colours must not
			// change as the pixels get smaller (the rock types are for the ground itself, not the map)
			const Color land = illustrated_colour(p_dirs[index], ground, slope);
			const double lat_part = std::sqrt(std::max(1.0 - (double)p_dirs[index].y * (double)p_dirs[index].y, 0.04));
			const double lit = clampd(1.0 - 2.0 * (rise_east - rise_north) / (p_step_lon * radius * lat_part), 0.55, 1.35);
			r = land.r * lit;
			g = land.g * lit;
			b = land.b * lit;
			// close in, the water of the rivers: a channel half the width of the valley's floor
			if (river_cells > 0 && p_step_lon * radius < 400.0) {
				Valley valley;
				if (valley_at(p_dirs[index], valley) && valley.nearest < valley.floor_half * 0.5) {
					const double edge = smooth(valley.floor_half * 0.5, valley.floor_half * 0.35, valley.nearest);
					r += (0.20 - r) * edge * 0.9;
					g += (0.45 - g) * edge * 0.9;
					b += (0.74 - b) * edge * 0.9;
				}
			}
		}
		bytes[index * 3] = (uint8_t)clampd((double)(int)(clampd(r, 0.0, 1.0) * 255.0), 0.0, 255.0);
		bytes[index * 3 + 1] = (uint8_t)clampd((double)(int)(clampd(g, 0.0, 1.0) * 255.0), 0.0, 255.0);
		bytes[index * 3 + 2] = (uint8_t)clampd((double)(int)(clampd(b, 0.0, 1.0) * 255.0), 0.0, 255.0);
	}
	return out;
}

PackedColorArray PlanetCrustNative::colours(const PackedVector3Array &p_dirs,
		const PackedFloat32Array &p_heights, const PackedFloat32Array &p_steeps) const {
	PackedColorArray result;
	result.resize(p_dirs.size());
	for (int index = 0; index < p_dirs.size(); index++) {
		Vector3 p = p_dirs[index] * (real_t)radius;
		double speckle = (double)detail.at(p) * 0.5 + 0.5;
		result[index] = rock_colour(p_dirs[index], p_heights[index], p_steeps[index], speckle);
	}
	return result;
}

// The directions of a tile's grid (PlanetTile.direction on the cube face, s and t from -1 to 1):
// `cells + 3` points a side, the first and the last being the ring round the tile.
PackedVector3Array PlanetCrustNative::tile_dirs(int p_face, double p_s0, double p_s1, double p_t0, double p_t1,
		int p_cells) const {
	const int side = p_cells + 3;
	PackedVector3Array result;
	result.resize(side * side);
	const Vector3 normal = cube_faces[p_face * 3];
	const Vector3 u = cube_faces[p_face * 3 + 1];
	const Vector3 v = cube_faces[p_face * 3 + 2];
	const double quarter_pi = 3.14159265358979323846 * 0.25;
	for (int row = 0; row < side; row++) {
		double t = p_t0 + (p_t1 - p_t0) * (double)(row - 1) / (double)p_cells;
		double b = std::tan(t * quarter_pi);
		for (int column = 0; column < side; column++) {
			double s = p_s0 + (p_s1 - p_s0) * (double)(column - 1) / (double)p_cells;
			double a = std::tan(s * quarter_pi);
			Vector3 direction = normal + u * (real_t)a + v * (real_t)b;
			result[row * side + column] = direction.normalized();
		}
	}
	return result;
}

// The grid's points as positions in the tile's own axes (PlanetTile._to_local), measured from the
// tile's middle in doubles, so a tile of a planet as big as the Earth is exact.
PackedVector3Array PlanetCrustNative::tile_positions(int p_face, double p_s0, double p_s1, double p_t0, double p_t1,
		int p_cells, const PackedFloat32Array &p_heights, const PackedFloat64Array &p_origin, const Vector3 &p_e1,
		const Vector3 &p_up, const Vector3 &p_e3) const {
	const int side = p_cells + 3;
	PackedVector3Array result;
	result.resize(side * side);
	const Vector3 normal = cube_faces[p_face * 3];
	const Vector3 u = cube_faces[p_face * 3 + 1];
	const Vector3 v = cube_faces[p_face * 3 + 2];
	const double quarter_pi = 3.14159265358979323846 * 0.25;
	for (int row = 0; row < side; row++) {
		const double b = std::tan((p_t0 + (p_t1 - p_t0) * (double)(row - 1) / (double)p_cells) * quarter_pi);
		for (int column = 0; column < side; column++) {
			const double a = std::tan((p_s0 + (p_s1 - p_s0) * (double)(column - 1) / (double)p_cells) * quarter_pi);
			const double x = (double)normal.x + (double)u.x * a + (double)v.x * b;
			const double y = (double)normal.y + (double)u.y * a + (double)v.y * b;
			const double z = (double)normal.z + (double)u.z * a + (double)v.z * b;
			const double reach = (radius + (double)p_heights[row * side + column]) / std::sqrt(x * x + y * y + z * z);
			const double dx = x * reach - p_origin[0];
			const double dy = y * reach - p_origin[1];
			const double dz = z * reach - p_origin[2];
			result.set(row * side + column, Vector3((real_t)(dx * p_e1.x + dy * p_e1.y + dz * p_e1.z),
					(real_t)(dx * p_up.x + dy * p_up.y + dz * p_up.z), (real_t)(dx * p_e3.x + dy * p_e3.y + dz * p_e3.z)));
		}
	}
	return result;
}

PackedVector3Array PlanetCrustNative::local_positions(const PackedVector3Array &p_dirs,
		const PackedFloat32Array &p_heights, const PackedFloat64Array &p_origin, const Vector3 &p_e1,
		const Vector3 &p_up, const Vector3 &p_e3) const {
	PackedVector3Array result;
	result.resize(p_dirs.size());
	for (int index = 0; index < p_dirs.size(); index++) {
		double reach = radius + (double)p_heights[index];
		double dx = (double)p_dirs[index].x * reach - p_origin[0];
		double dy = (double)p_dirs[index].y * reach - p_origin[1];
		double dz = (double)p_dirs[index].z * reach - p_origin[2];
		result[index] = Vector3((real_t)(dx * p_e1.x + dy * p_e1.y + dz * p_e1.z),
				(real_t)(dx * p_up.x + dy * p_up.y + dz * p_up.z),
				(real_t)(dx * p_e3.x + dy * p_e3.y + dz * p_e3.z));
	}
	return result;
}

// The tile's triangles, two to each square of the grid (PlanetTile._triangle and
// MeshBuilder.add_tri_smooth): three vertices a triangle with the facet's flat colour (the mean
// of its corners') and the corners' smooth colours as bytes, plus the collision faces.
Dictionary PlanetCrustNative::triangles(const PackedVector3Array &p_positions,
		const PackedVector3Array &p_normals, const PackedColorArray &p_colours, int p_cells, double p_skirt_drop) const {
	const int side = p_cells + 3;
	const int count = p_cells * p_cells * 2;
	PackedVector3Array vertices;
	PackedVector3Array normals;
	PackedColorArray flats;
	PackedByteArray custom;
	PackedVector3Array faces;
	// (a skirt: a double sided wall round the tile, hanging `p_skirt_drop` m, that hides the crack to a finer neighbour)
	const int skirt_count = p_skirt_drop > 0.0 ? p_cells * 16 : 0;
	vertices.resize((count + skirt_count) * 3);
	normals.resize((count + skirt_count) * 3);
	flats.resize((count + skirt_count) * 3);
	custom.resize((count + skirt_count) * 3 * 4);
	faces.resize(count * 3);
	int at = 0;
	for (int row = 1; row <= p_cells; row++) {
		for (int column = 1; column <= p_cells; column++) {
			const int i00 = row * side + column;
			const int i10 = i00 + 1;
			const int i01 = i00 + side;
			const int i11 = i01 + 1;
			const int quads[2][3] = { { i00, i01, i10 }, { i10, i01, i11 } };
			for (int which = 0; which < 2; which++) {
				const int *ids = quads[which];
				Vector3 a = p_positions[ids[0]];
				Vector3 b = p_positions[ids[1]];
				Vector3 c = p_positions[ids[2]];
				int first = 1;
				int second = 2;
				if ((b - a).cross(c - a).y < 0.0f) {
					b = p_positions[ids[2]];
					c = p_positions[ids[1]];
					first = 2;
					second = 1;
				}
				faces[at * 3] = a;
				faces[at * 3 + 1] = c;
				faces[at * 3 + 2] = b;
				const Color mean = (p_colours[ids[0]] + p_colours[ids[1]] + p_colours[ids[2]]) / 3.0f;
				const int corner[3] = { ids[0], ids[first], ids[second] };
				const Vector3 corner_points[3] = { a, b, c };
				// the builder wants a, c, b: its corner numbers 0, 2, 1
				const int order[3] = { 0, 2, 1 };
				for (int slot = 0; slot < 3; slot++) {
					const int k = order[slot];
					const int out = at * 3 + slot;
					vertices[out] = corner_points[k];
					normals[out] = p_normals[corner[k]];
					flats[out] = mean;
					const Color smooth = p_colours[corner[k]];
					custom[out * 4] = (uint8_t)(int)(smooth.r * 255.0f);
					custom[out * 4 + 1] = (uint8_t)(int)(smooth.g * 255.0f);
					custom[out * 4 + 2] = (uint8_t)(int)(smooth.b * 255.0f);
					custom[out * 4 + 3] = 255;
				}
				at++;
			}
		}
	}
	if (skirt_count > 0) {
		const Vector3 drop(0.0f, (real_t)-p_skirt_drop, 0.0f);
		int out_at = count * 3;
		auto put = [&](const Vector3 &p_a, const Vector3 &p_b, const Vector3 &p_c, const Vector3 &p_normal, const Color &p_colour) {
			const Vector3 points[3] = { p_a, p_c, p_b }; // (the builder's order a, c, b)
			for (int slot = 0; slot < 3; slot++) {
				vertices[out_at] = points[slot];
				normals[out_at] = p_normal;
				flats[out_at] = p_colour;
				custom[out_at * 4] = (uint8_t)(int)(p_colour.r * 255.0f);
				custom[out_at * 4 + 1] = (uint8_t)(int)(p_colour.g * 255.0f);
				custom[out_at * 4 + 2] = (uint8_t)(int)(p_colour.b * 255.0f);
				custom[out_at * 4 + 3] = 255;
				out_at++;
			}
		};
		for (int index = 0; index < p_cells; index++) {
			const int edges[4][2] = { { side + 1 + index, side + 2 + index },
					{ (p_cells + 1) * side + 1 + index, (p_cells + 1) * side + 2 + index },
					{ (1 + index) * side + 1, (2 + index) * side + 1 },
					{ (1 + index) * side + p_cells + 1, (2 + index) * side + p_cells + 1 } };
			for (int edge = 0; edge < 4; edge++) {
				const Vector3 a = p_positions[edges[edge][0]];
				const Vector3 b = p_positions[edges[edge][1]];
				const Color colour = p_colours[edges[edge][0]];
				const Vector3 wall = (b - a).cross(drop).normalized();
				put(a, b, b + drop, wall, colour);
				put(a, b + drop, a + drop, wall, colour);
				put(a, b + drop, b, -wall, colour);
				put(a, a + drop, b + drop, -wall, colour);
			}
		}
	}
	Dictionary result;
	result["vertices"] = vertices;
	result["normals"] = normals;
	result["colours"] = flats;
	result["custom"] = custom;
	result["faces"] = faces;
	return result;
}

// The smooth normal of every point inside the ring (PlanetTile's normals loop): the cross product
// of the two ways across the point, turned to face up.
PackedVector3Array PlanetCrustNative::grid_normals(const PackedVector3Array &p_positions, int p_cells) const {
	const int side = p_cells + 3;
	PackedVector3Array result;
	result.resize(side * side);
	for (int row = 1; row <= p_cells + 1; row++) {
		for (int column = 1; column <= p_cells + 1; column++) {
			Vector3 along = p_positions[row * side + column + 1] - p_positions[row * side + column - 1];
			Vector3 down = p_positions[(row + 1) * side + column] - p_positions[(row - 1) * side + column];
			Vector3 normal = along.cross(down).normalized();
			result[row * side + column] = normal.y >= 0.0f ? normal : -normal;
		}
	}
	return result;
}

// The rock colour of every point inside the ring, from its direction, height and steepness.
PackedColorArray PlanetCrustNative::ground_colours(const PackedVector3Array &p_dirs,
		const PackedFloat32Array &p_heights, const PackedVector3Array &p_normals, int p_cells) const {
	const int side = p_cells + 3;
	PackedColorArray result;
	result.resize(side * side);
	for (int row = 1; row <= p_cells + 1; row++) {
		for (int column = 1; column <= p_cells + 1; column++) {
			const int index = row * side + column;
			Vector3 p = p_dirs[index] * (real_t)radius;
			double speckle = (double)detail.at(p) * 0.5 + 0.5;
			result[index] = rock_colour(p_dirs[index], p_heights[index], 1.0 - (double)p_normals[index].y, speckle);
		}
	}
	return result;
}

// The ground without the smallest hills (PlanetNoise.macro_height): what the water sees.
PackedFloat32Array PlanetCrustNative::broad_heights(const PackedVector3Array &p_dirs, double p_pixel) const {
	return heights_by(BROAD, p_dirs, p_pixel);
}

PackedFloat32Array PlanetCrustNative::macro_heights(const PackedVector3Array &p_dirs) const {
	return heights_by(MACRO, p_dirs);
}


void PlanetCrustNative::set_rivers(int p_cells, const Dictionary &p_network, double p_cell_metres) {
	river_a = p_network["a"];
	river_b = p_network["b"];
	river_bed_a = p_network["bed_a"];
	river_bed_b = p_network["bed_b"];
	river_flow_a = p_network["flow_a"];
	river_flow_b = p_network["flow_b"];
	river_start = p_network["cell_start"];
	river_items = p_network["cell_items"];
	river_flow = p_network["river_flow"];
	river_cell_metres = p_cell_metres;
	river_cells = river_start.size() == 6 * p_cells * p_cells + 1 ? p_cells : 0;
	lake_level = p_network.get("lake_level", PackedFloat32Array());
	if (lake_level.size() != 6 * p_cells * p_cells) {
		lake_level = PackedFloat32Array();
	}
}

double PlanetCrustNative::lake_weight(const Vector3 &p_dir, double &r_level) const {
	if (river_cells <= 0 || lake_level.is_empty()) {
		return 0.0;
	}
	const double ax = std::abs((double)p_dir.x), ay = std::abs((double)p_dir.y), az = std::abs((double)p_dir.z);
	int face = 0;
	if (ax >= ay && ax >= az) {
		face = p_dir.x > 0 ? 0 : 1;
	} else if (ay >= az) {
		face = p_dir.y > 0 ? 2 : 3;
	} else {
		face = p_dir.z > 0 ? 4 : 5;
	}
	const double along = p_dir.dot(cube_faces[face * 3]);
	const double quarter_pi = 3.14159265358979323846 * 0.25;
	const double s = std::atan((double)p_dir.dot(cube_faces[face * 3 + 1]) / along) / quarter_pi;
	const double t = std::atan((double)p_dir.dot(cube_faces[face * 3 + 2]) / along) / quarter_pi;
	const double fx = (s + 1.0) * 0.5 * river_cells - 0.5;
	const double fy = (t + 1.0) * 0.5 * river_cells - 0.5;
	const int x0 = (int)std::floor(fx), y0 = (int)std::floor(fy);
	const double tx = fx - x0, ty = fy - y0;
	double weight = 0.0;
	double level_sum = 0.0, level_weight = 0.0;
	for (int dy = 0; dy < 2; dy++) {
		for (int dx = 0; dx < 2; dx++) {
			const int i = std::max(0, std::min(river_cells - 1, x0 + dx));
			const int j = std::max(0, std::min(river_cells - 1, y0 + dy));
			const double level = (double)lake_level[(face * river_cells + j) * river_cells + i];
			const double w = (dx ? tx : 1.0 - tx) * (dy ? ty : 1.0 - ty);
			if (level > -1.0e8) {
				weight += w;
				level_sum += level * w;
				level_weight += w;
			}
		}
	}
	r_level = level_weight > 0.0 ? level_sum / level_weight : -1.0e9;
	return weight;
}

PackedFloat32Array PlanetCrustNative::lake_surfaces(const PackedVector3Array &p_dirs) const {
	PackedFloat32Array out;
	out.resize(p_dirs.size());
	for (int index = 0; index < p_dirs.size(); index++) {
		double level = -1.0e9;
		const double weight = lake_weight(p_dirs[index].normalized(), level);
		out.set(index, weight > 0.5 ? (float)level : -1.0e9f);
	}
	return out;
}

// The nearest river piece to a direction, and the envelope of the valley it cuts: its bed plus the
// sides the valley allows from the edge of its floor.
bool PlanetCrustNative::valley_at(const Vector3 &p_dir, Valley &r_valley, double p_side) const {
	double ax = std::abs((double)p_dir.x);
	double ay = std::abs((double)p_dir.y);
	double az = std::abs((double)p_dir.z);
	int face = 0;
	if (ax >= ay && ax >= az) {
		face = p_dir.x > 0 ? 0 : 1;
	} else if (ay >= az) {
		face = p_dir.y > 0 ? 2 : 3;
	} else {
		face = p_dir.z > 0 ? 4 : 5;
	}
	const Vector3 normal = cube_faces[face * 3];
	const Vector3 u = cube_faces[face * 3 + 1];
	const Vector3 v = cube_faces[face * 3 + 2];
	const double along = p_dir.dot(normal);
	const double quarter_pi = 3.14159265358979323846 * 0.25;
	double s = std::atan((double)p_dir.dot(u) / along) / quarter_pi;
	double t = std::atan((double)p_dir.dot(v) / along) / quarter_pi;
	int i = (int)((s + 1.0) * 0.5 * river_cells);
	int j = (int)((t + 1.0) * 0.5 * river_cells);
	i = i < 0 ? 0 : (i > river_cells - 1 ? river_cells - 1 : i);
	j = j < 0 ? 0 : (j > river_cells - 1 ? river_cells - 1 : j);
	const int cell = (face * river_cells + j) * river_cells + i;
	const int from = river_start[cell];
	const int to = river_start[cell + 1];
	if (from == to) {
		return false;
	}
	double nearest_distance = 1.0e30;
	double best_envelope = 1.0e30;
	double best_distance = 0.0;
	double best_floor = 0.0, best_bed = 0.0, best_flow = 0.0, best_side = 1.0;
	for (int at = from; at < to; at++) {
		const int piece = river_items[at];
		const Vector3 a = river_a[piece];
		const Vector3 b = river_b[piece];
		const Vector3 ab = b - a;
		const double length_squared = (double)ab.length_squared();
		double position = length_squared > 1.0e-18 ? (double)(p_dir - a).dot(ab) / length_squared : 0.0;
		position = position < 0.0 ? 0.0 : (position > 1.0 ? 1.0 : position);
		const Vector3 nearest = a + ab * (real_t)position;
		const double distance = (double)(p_dir - nearest).length() * radius;
		const double flow = (double)river_flow_a[piece] + ((double)river_flow_b[piece] - (double)river_flow_a[piece]) * position;
		const double bed = (double)river_bed_a[piece] + ((double)river_bed_b[piece] - (double)river_bed_a[piece]) * position;
		double floor_half = 30.0 * std::sqrt(flow / river_flow);
		floor_half = floor_half < 20.0 ? 20.0 : (floor_half > 0.3 * river_cell_metres ? 0.3 * river_cell_metres : floor_half);
		const double beyond = distance - floor_half;
		const double envelope = bed + (beyond > 0.0 ? beyond : 0.0) * p_side;
		nearest_distance = distance < nearest_distance ? distance : nearest_distance;
		if (envelope < best_envelope) {
			best_envelope = envelope;
			best_distance = distance;
			best_floor = floor_half;
			best_bed = bed;
			best_flow = flow;
			best_side = ab.cross(p_dir - nearest).dot(nearest) < 0.0 ? -1.0 : 1.0;
		}
	}
	r_valley.envelope = best_envelope;
	r_valley.nearest = nearest_distance;
	r_valley.distance = best_distance;
	r_valley.floor_half = best_floor;
	r_valley.bed = best_bed;
	r_valley.flow = best_flow;
	r_valley.side = best_side;
	return true;
}

PackedVector3Array PlanetCrustNative::river_waters(const PackedVector3Array &p_dirs) const {
	PackedVector3Array out;
	out.resize(p_dirs.size());
	for (int index = 0; index < p_dirs.size(); index++) {
		Valley valley;
		const Vector3 dir = p_dirs[index].normalized();
		if (river_cells <= 0 || !valley_at(dir, valley) || valley.distance > valley.floor_half * 1.6) {
			out.set(index, Vector3(-1.0e9f, 0.0f, 0.5f));
			continue;
		}
		const double share = valley.flow / river_flow;
		const double depth = 0.6 + 1.4 * std::sqrt(share > 4.0 ? 4.0 : share);
		const double across = 0.5 + 0.5 * valley.side * clampd(valley.distance / (valley.floor_half * 1.6), 0.0, 1.0);
		out.set(index, Vector3((real_t)(valley.bed + depth), (real_t)share, (real_t)across));
	}
	return out;
}

// How rough the ground is allowed to be at `p_dir`: 1 away from the rivers, down to 0.3 on the floor
// of a valley (a river's valley is smooth between its rough sides).
double PlanetCrustNative::valley_floor(const Vector3 &p_dir) const {
	Valley valley;
	if (river_cells <= 0 || !valley_at(p_dir, valley)) {
		return 1.0;
	}
	return 1.0 - 0.7 * (1.0 - smooth(valley.floor_half, valley.floor_half * 6.0, valley.distance));
}
