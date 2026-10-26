#include "planet_tectonics_native.h"

#include <godot_cpp/variant/utility_functions.hpp>
#include <godot_cpp/variant/vector2i.hpp>

#include <algorithm>
#include <cmath>

using namespace godot;

static double smooth_step(double p_from, double p_to, double p_x) {
	if (p_from == p_to) {
		return p_x < p_from ? 0.0 : 1.0;
	}
	double s = CLAMP((p_x - p_from) / (p_to - p_from), 0.0, 1.0);
	return s * s * (3.0 - 2.0 * s);
}

void PlanetTectonics::_bind_methods() {
	ClassDB::bind_static_method("PlanetTectonics", D_METHOD("get_continent"), &PlanetTectonics::get_continent);
	ClassDB::bind_static_method("PlanetTectonics", D_METHOD("get_ocean"), &PlanetTectonics::get_ocean);
	ClassDB::bind_static_method("PlanetTectonics", D_METHOD("get_boundary"), &PlanetTectonics::get_boundary);
	ClassDB::bind_static_method("PlanetTectonics", D_METHOD("get_soft"), &PlanetTectonics::get_soft);
	ClassDB::bind_static_method("PlanetTectonics", D_METHOD("create", "world_seed", "plates"), &PlanetTectonics::create);

	NP_BIND_STATE(PlanetTectonics, Variant::PACKED_VECTOR3_ARRAY, _seeds)
	NP_BIND_STATE(PlanetTectonics, Variant::PACKED_VECTOR3_ARRAY, _spin)
	NP_BIND_STATE(PlanetTectonics, Variant::ARRAY, _continental)
	ClassDB::bind_method(D_METHOD("get__warp"), &PlanetTectonics::get__warp);
	ClassDB::bind_method(D_METHOD("set__warp", "value"), &PlanetTectonics::set__warp);
	ADD_PROPERTY(PropertyInfo(Variant::OBJECT, "_warp", PROPERTY_HINT_RESOURCE_TYPE, "FastNoiseLite", PROPERTY_USAGE_NO_EDITOR), "set__warp", "get__warp");
	ClassDB::bind_method(D_METHOD("get__ridge"), &PlanetTectonics::get__ridge);
	ClassDB::bind_method(D_METHOD("set__ridge", "value"), &PlanetTectonics::set__ridge);
	ADD_PROPERTY(PropertyInfo(Variant::OBJECT, "_ridge", PROPERTY_HINT_RESOURCE_TYPE, "FastNoiseLite", PROPERTY_USAGE_NO_EDITOR), "set__ridge", "get__ridge");
	ClassDB::bind_method(D_METHOD("get__interior"), &PlanetTectonics::get__interior);
	ClassDB::bind_method(D_METHOD("set__interior", "value"), &PlanetTectonics::set__interior);
	ADD_PROPERTY(PropertyInfo(Variant::OBJECT, "_interior", PROPERTY_HINT_RESOURCE_TYPE, "FastNoiseLite", PROPERTY_USAGE_NO_EDITOR), "set__interior", "get__interior");

	ClassDB::bind_method(D_METHOD("height", "dir"), &PlanetTectonics::height);
	ClassDB::bind_method(D_METHOD("plate_at", "dir"), &PlanetTectonics::plate_at);
}

// A number between `low` and `high` from the generator's integers: the same on every build of the engine (its own `randf_range` is not:
// the double precision build draws other numbers, so the same seed made another planet there).
double PlanetTectonics::between(const Ref<RandomNumberGenerator> &p_rng, double p_low, double p_high) {
	return p_low + (p_high - p_low) * (double)(p_rng->randi() >> 8) / 16777216.0;
}

void PlanetTectonics::setup_noise(const Ref<FastNoiseLite> &p_noise, int64_t p_seed, double p_frequency, int p_octaves) {
	p_noise->set_noise_type(FastNoiseLite::TYPE_SIMPLEX_SMOOTH);
	p_noise->set_seed((int32_t)p_seed);
	p_noise->set_frequency(p_frequency);
	p_noise->set_fractal_type(FastNoiseLite::FRACTAL_FBM);
	p_noise->set_fractal_octaves(p_octaves);
}

Ref<PlanetTectonics> PlanetTectonics::create(int64_t p_world_seed, int64_t p_plates) {
	Ref<PlanetTectonics> made;
	made.instantiate();
	PlanetTectonics &self = **made;
	self.warp_noise.instantiate();
	self.ridge_noise.instantiate();
	self.interior_noise.instantiate();
	Ref<RandomNumberGenerator> rng;
	rng.instantiate();
	rng->set_seed((uint64_t)(int64_t)UtilityFunctions::hash(Vector2i((int32_t)p_world_seed, 4242)));
	// plate centres: a Fibonacci spread (even over the sphere) nudged at random, so plates differ in size
	for (int64_t index = 0; index < p_plates; index++) {
		double y = 1.0 - 2.0 * ((double)index + 0.5) / (double)p_plates;
		double ring = std::sqrt(1.0 - y * y);
		double angle = (double)index * 2.399963 + between(rng, -0.5, 0.5);
		Vector3 spot(std::cos(angle) * ring, y, std::sin(angle) * ring);
		double nx = between(rng, -1.0, 1.0);
		double ny = between(rng, -1.0, 1.0);
		double nz = between(rng, -1.0, 1.0);
		spot += Vector3(nx, ny, nz) * 0.28;
		self.seeds.append(spot.normalized());
		double ax = between(rng, -1.0, 1.0);
		double ay = between(rng, -1.0, 1.0);
		double az = between(rng, -1.0, 1.0);
		Vector3 axis = Vector3(ax, ay, az).normalized();
		self.spin.append(axis * between(rng, 0.4, 1.0));
		// the poles are mostly sea, as on Earth (Antarctica is the exception)
		self.continental_.append(between(rng, 0.0, 1.0) < (std::abs(spot.y) < 0.75 ? 0.42 : 0.2));
	}
	setup_noise(self.warp_noise, p_world_seed + 11, 1.4, 3);
	setup_noise(self.ridge_noise, p_world_seed + 12, 6.0, 5);
	self.ridge_noise->set_fractal_type(FastNoiseLite::FRACTAL_RIDGED);
	setup_noise(self.interior_noise, p_world_seed + 13, 2.2, 4);
	return made;
}

// plate edges wander: look the plate up at a direction pushed about by a slow noise
Vector3 PlanetTectonics::plate_shift(const Vector3 &p_dir) const {
	Vector3 shifted = p_dir + Vector3(warp_noise->get_noise_3d(p_dir.x, p_dir.y, p_dir.z),
										  warp_noise->get_noise_3d(p_dir.x + 5.3, p_dir.y - 2.1, p_dir.z + 1.7),
										  warp_noise->get_noise_3d(p_dir.x - 3.7, p_dir.y + 4.4, p_dir.z - 6.2)) *
			WARP;
	return shifted.normalized();
}

// Height in units of relief at the unit direction `dir`. Every plate near enough has a say, with a smooth weight (the nearest has all of
// it, a plate further by a few hundredths of a radian has almost none), and every pair of the near plates adds its own boundary effect,
// weighted the same way: so nothing jumps where the second nearest plate changes.
double PlanetTectonics::height(const Vector3 &p_dir) const {
	Vector3 q = plate_shift(p_dir);
	// the four nearest plates, nearest first
	double c0 = -2.0, c1 = -2.0, c2 = -2.0, c3 = -2.0;
	int p0 = 0, p1 = 0, p2 = 0, p3 = 0;
	int index = -1;
	for (int i = 0; i < seeds.size(); i++) {
		index += 1;
		double closeness = q.dot(seeds[i]);
		if (closeness <= c3) {
			continue;
		}
		if (closeness > c1) {
			if (closeness > c0) {
				c3 = c2;
				p3 = p2;
				c2 = c1;
				p2 = p1;
				c1 = c0;
				p1 = p0;
				c0 = closeness;
				p0 = index;
			} else {
				c3 = c2;
				p3 = p2;
				c2 = c1;
				p2 = p1;
				c1 = closeness;
				p1 = index;
			}
		} else if (closeness > c2) {
			c3 = c2;
			p3 = p2;
			c2 = closeness;
			p2 = index;
		} else {
			c3 = closeness;
			p3 = index;
		}
	}
	double a0 = std::acos(CLAMP(c0, -1.0, 1.0));
	double a1 = std::acos(CLAMP(c1, -1.0, 1.0));
	double a2 = std::acos(CLAMP(c2, -1.0, 1.0));
	double a3 = std::acos(CLAMP(c3, -1.0, 1.0));
	double w0 = 1.0; // exp(-(a0 - a0) / SOFT)
	double w1 = std::exp(-(a1 - a0) / SOFT);
	double w2 = std::exp(-(a2 - a0) / SOFT);
	double w3 = std::exp(-(a3 - a0) / SOFT);
	double total = w0 + w1 + w2 + w3;
	bool land0 = land(p0), land1 = land(p1), land2 = land(p2), land3 = land(p3);
	double base = w0 * (land0 ? CONTINENT : OCEAN);
	base += w1 * (land1 ? CONTINENT : OCEAN);
	base += w2 * (land2 ? CONTINENT : OCEAN);
	base += w3 * (land3 ? CONTINENT : OCEAN);
	double variety = w0 * (land0 ? 0.11 : 0.06);
	variety += w1 * (land1 ? 0.11 : 0.06);
	variety += w2 * (land2 ? 0.11 : 0.06);
	variety += w3 * (land3 ? 0.11 : 0.06);
	base /= total;
	variety /= total;
	// the mountains, beyond the base height: every pair of the near plates adds its boundary, weighed by the two plates' say
	double scale = 1.0 / (w0 * w1);
	double rise = 0.0;
	double pair = w0 * w1 * scale;
	if (pair > 0.002) { // (the weight starts from 0 at the cutoff: no step where a pair drops out)
		rise += (pair - 0.002) * boundary(p0, p1, q, (a1 - a0) * 0.5);
	}
	pair = w0 * w2 * scale;
	if (pair > 0.002) {
		rise += (pair - 0.002) * boundary(p0, p2, q, (a2 - a0) * 0.5);
	}
	pair = w0 * w3 * scale;
	if (pair > 0.002) {
		rise += (pair - 0.002) * boundary(p0, p3, q, (a3 - a0) * 0.5);
	}
	pair = w1 * w2 * scale;
	if (pair > 0.002) {
		rise += (pair - 0.002) * boundary(p1, p2, q, (a2 - a1) * 0.5);
	}
	pair = w1 * w3 * scale;
	if (pair > 0.002) {
		rise += (pair - 0.002) * boundary(p1, p3, q, (a3 - a1) * 0.5);
	}
	pair = w2 * w3 * scale;
	if (pair > 0.002) {
		rise += (pair - 0.002) * boundary(p2, p3, q, (a3 - a2) * 0.5);
	}
	// the ranges are rough: ridged noise rides on the uplift
	double ridged = ridge_noise->get_noise_3d(p_dir.x, p_dir.y, p_dir.z) * 0.5 + 0.5;
	double rough = std::max(rise, 0.0) * (ridged * 1.1 - 0.35);
	// the plate interiors are not flat either: cratons, basins, plateaus
	double inside = interior_noise->get_noise_3d(p_dir.x, p_dir.y, p_dir.z) * variety;
	return base + rise + rough + inside;
}

// What the boundary between plates `a` (the nearer to `q`) and `b` does at `q`, which is `edge` radians from the line between them.
double PlanetTectonics::boundary(int p_a, int p_b, const Vector3 &p_q, double p_edge) const {
	Vector3 toward = seeds[p_b] - seeds[p_a];
	toward -= p_q * p_q.dot(toward);
	double push = 0.0;
	if (toward.length_squared() > 0.000001) {
		Vector3 relative = spin[p_a].cross(p_q) - spin[p_b].cross(p_q);
		push = CLAMP((double)relative.dot(toward.normalized()), -1.0, 1.0);
	}
	double together = std::max(push, 0.0);
	double apart = std::max(-push, 0.0);
	double edge_scaled = p_edge / BOUNDARY;
	double near = std::exp(-edge_scaled * edge_scaled);
	bool here = land(p_a);
	bool there = land(p_b);
	if (here && there) {
		return near * (0.62 * together - 0.12 * apart); // a collision: the highest ranges
	}
	if (here != there) {
		// a coast where one plate dives under the other: a coastal range on the land side and a trench off shore
		double inland = here ? p_edge : -p_edge;
		double up_scaled = (inland - 0.03) / 0.045;
		double range_up = 0.26 * std::exp(-up_scaled * up_scaled);
		double down_scaled = (inland + 0.03) / 0.035;
		double trench = 0.30 * std::exp(-down_scaled * down_scaled);
		return together * (range_up - trench);
	}
	// along a boundary the slow noise breaks the island arc into chains with gaps, and shifts the mid-ocean ridge sideways in steps
	double along = interior_noise->get_noise_3d(p_q.x * 1.9, p_q.y * 1.9, p_q.z * 1.9);
	double steps = interior_noise->get_noise_3d(p_q.x * 1.9 + 7.0, p_q.y * 1.9 + 3.0, p_q.z * 1.9 + 1.0);
	double arc_scaled = (p_edge - 0.03) / 0.03;
	double chain = smooth_step(-0.3, 0.25, along);
	double arc = 0.30 * together * chain * std::exp(-arc_scaled * arc_scaled); // an island arc
	double ridge_scaled = (p_edge - 0.04 * CLAMP(steps * 3.0, -1.0, 1.0)) / 0.09;
	arc += 0.22 * apart * std::exp(-ridge_scaled * ridge_scaled); // a mid-ocean ridge
	return arc - 0.22 * together * near; // and the trench beside it
}

// Which plate is at `dir` (for the map): (its number, radians to the nearest boundary, 1 if it is a continental plate else 0).
Vector3 PlanetTectonics::plate_at(const Vector3 &p_dir) const {
	Vector3 q = plate_shift(p_dir);
	int first = 0;
	double best = -2.0;
	double next = -2.0;
	for (int index = 0; index < seeds.size(); index++) {
		double closeness = q.dot(seeds[index]);
		if (closeness > best) {
			next = best;
			best = closeness;
			first = index;
		} else if (closeness > next) {
			next = closeness;
		}
	}
	double edge = (std::acos(CLAMP(next, -1.0, 1.0)) - std::acos(CLAMP(best, -1.0, 1.0))) * 0.5;
	return Vector3(first, edge, land(first) ? 1.0 : 0.0);
}
