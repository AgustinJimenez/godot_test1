#include "planet_crust_native.h"

#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/core/math.hpp>

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
	ClassDB::bind_method(D_METHOD("heights", "dirs"), &PlanetCrustNative::heights);
	ClassDB::bind_method(D_METHOD("colours", "dirs", "heights", "steeps"), &PlanetCrustNative::colours);
	ClassDB::bind_method(D_METHOD("tectonic_heights", "dirs"), &PlanetCrustNative::tectonic_heights);
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
	configure(craton, p_config["craton"]);
	configure(basin, p_config["basin"]);
}

// The direction pushed about by the slow noise (the plate edges wander).
Vector3 PlanetCrustNative::plate_shift(const Vector3 &p_dir) const {
	Vector3 shifted = p_dir + Vector3(warp.at(p_dir),
										warp.at(Vector3(p_dir.x + 5.3f, p_dir.y - 2.1f, p_dir.z + 1.7f)),
										warp.at(Vector3(p_dir.x - 3.7f, p_dir.y + 4.4f, p_dir.z - 6.2f))) *
							(real_t)0.30;
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
	double arc_scaled = (p_edge - 0.03) / 0.03;
	double arc = 0.30 * together * std::exp(-arc_scaled * arc_scaled);
	double ridge_scaled = p_edge / 0.12;
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

double PlanetCrustNative::valley_cut(const Vector3 &p_point, double p_units) const {
	double upland = smooth(0.03, 0.25, p_units);
	if (upland <= 0.0) {
		return 0.0;
	}
	double cut = 0.0;
	for (int index = 0; index < 3; index++) {
		double line = std::abs((double)valleys[index].at(p_point));
		double floor_value = 1.0 - smooth(0.0, valley_width, line);
		cut += valley_depth[index] * floor_value * std::sqrt(floor_value);
	}
	return cut * upland;
}

double PlanetCrustNative::macro_ground(double p_units, const Vector3 &p_point) const {
	// every layer below is multiplied by a weight that is exactly 0 over the sea (and a little
	// inland), so those noises are not asked there: the same height, the sea floor much faster
	double land = smooth(-0.02, 0.05, p_units);
	double rolling_height = land > 0.0 ? rolling.at(p_point) * clampd(relief * 0.12, 25.0, 120.0) : 0.0;
	double ridges = 0.0;
	if (p_units > 0.08) {
		double belt = smooth(0.0, 0.5, (double)range_mask.at(p_point) + 0.15);
		ridges = ((double)ranges.at(p_point) * 0.5 + 0.5) * relief * 0.22;
		ridges *= belt * smooth(0.08, 0.4, p_units);
	}
	double rugged = smooth(0.02, 0.4, p_units);
	double massifs = 0.0, chains = 0.0, spurs = 0.0;
	if (rugged > 0.0) {
		massifs = ((double)massif.at(p_point) * 0.5 + 0.1) * relief * massif_scale * rugged;
		chains = ((double)chain.at(p_point) * 0.5 + 0.1) * relief * chain_scale * rugged;
		spurs = ((double)foothills.at(p_point) * 0.5 + 0.1) * relief * foothill_scale * rugged;
	}
	double shore_height = shore_curve(p_units) * relief;
	double raised = shore_height + rolling_height * land + ridges + chains + massifs + spurs;
	double cut = valley_cut(p_point, p_units);
	double limit = (shore_height > 0.0 ? shore_height : 0.0) * 0.8;
	return raised - (cut < limit ? cut : limit);
}

// The ground before any water has cut it (PlanetNoise.base_height with no hydrology).
double PlanetCrustNative::ground_height(const Vector3 &p_dir) const {
	double units = tectonic_height(p_dir) - sea;
	Vector3 p = p_dir * (real_t)radius;
	double land = smooth(-0.02, 0.05, units);
	double hill_height = land > 0.0 ? hills.at(p) * clampd(relief * 0.04, 14.0, 45.0) : 0.0;
	double ground = macro_ground(units, p) + hill_height * land;
	double high = smooth(0.12, 0.45, units);
	double gully_depth = relief * 0.05 < 90.0 ? relief * 0.05 : 90.0;
	if (high > 0.0) {
		ground += (double)gullies.at(p) * 0.5 * gully_depth * high;
	}
	double layer = clampd(relief * 0.025, 8.0, 40.0);
	double steps = std::floor(ground / layer) + smooth(0.15, 0.85, fposmod_d(ground / layer, 1.0));
	double mixed = smooth(0.3, 0.6, units) * 0.35;
	return ground + (steps * layer - ground) * mixed;
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

Color PlanetCrustNative::rock_colour(const Vector3 &p_dir, double p_ground, double p_steep, double p_speckle) const {
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
	float stripes = (float)(1.0 + (layers - 0.5) * 0.24 * sedimentary * on_land);
	rock = Color(rock.r * stripes, rock.g * stripes, rock.b * stripes, 0.0f);
	float speckle = (float)(0.94 + 0.12 * p_speckle);
	rock = Color(rock.r * speckle, rock.g * speckle, rock.b * speckle, 0.0f);
	float steep_mix = (float)smooth(0.35, 0.8, p_steep);
	Color dark(rock.r * 0.62f, rock.g * 0.62f, rock.b * 0.62f, 0.0f);
	float r = rock.r + (dark.r - rock.r) * steep_mix;
	float g = rock.g + (dark.g - rock.g) * steep_mix;
	float b = rock.b + (dark.b - rock.b) * steep_mix;
	return Color((float)clampd(r, 0.0, 1.0), (float)clampd(g, 0.0, 1.0), (float)clampd(b, 0.0, 1.0), 1.0f);
}

PackedFloat32Array PlanetCrustNative::heights(const PackedVector3Array &p_dirs) const {
	PackedFloat32Array result;
	result.resize(p_dirs.size());
	for (int index = 0; index < p_dirs.size(); index++) {
		result[index] = (float)ground_height(p_dirs[index]);
	}
	return result;
}

PackedFloat32Array PlanetCrustNative::tectonic_heights(const PackedVector3Array &p_dirs) const {
	PackedFloat32Array result;
	result.resize(p_dirs.size());
	for (int index = 0; index < p_dirs.size(); index++) {
		result[index] = (float)tectonic_height(p_dirs[index]);
	}
	return result;
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
