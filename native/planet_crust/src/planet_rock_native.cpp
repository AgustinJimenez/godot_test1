#include "planet_rock_native.h"

#include <algorithm>
#include <cmath>

using namespace godot;

static const double TAU_D = 6.283185307179586476925286766559;

static double smooth_step(double p_from, double p_to, double p_x) {
	if (p_from == p_to) {
		return p_x < p_from ? 0.0 : 1.0;
	}
	double s = CLAMP((p_x - p_from) / (p_to - p_from), 0.0, 1.0);
	return s * s * (3.0 - 2.0 * s);
}

static const Color SOIL_DRY(0.64f, 0.55f, 0.38f); // the soil of a dry place
static const Color SOIL_RICH(0.27f, 0.20f, 0.13f); // and of a wet, mild one
static const Color ICE(0.72f, 0.86f, 0.96f); // glacier ice
static const Color SCREE(0.58f, 0.56f, 0.52f); // rubble on the slopes
static const Color WETLAND(0.22f, 0.30f, 0.16f); // marsh
static const Color STEPPE(0.50f, 0.46f, 0.22f); // the cover of a dry, mild place: dry grass
static const Color MEADOW(0.22f, 0.38f, 0.12f); // wet and mild: grass
static const Color FOREST(0.11f, 0.24f, 0.09f); // very wet and warm: the dark of the forest floor seen from far
static const Color SAND(0.80f, 0.72f, 0.52f); // beaches: low, level ground by the sea
static const Color SNOW(0.93f, 0.95f, 0.98f); // permanent snow and ice

static const Color COLOURS[9] = {
	Color(0.25f, 0.24f, 0.26f), // basalt
	Color(0.38f, 0.35f, 0.33f), // andesite
	Color(0.64f, 0.56f, 0.52f), // granite
	Color(0.48f, 0.48f, 0.51f), // gneiss
	Color(0.44f, 0.49f, 0.45f), // schist
	Color(0.83f, 0.80f, 0.70f), // limestone
	Color(0.74f, 0.58f, 0.40f), // sandstone
	Color(0.61f, 0.34f, 0.24f), // red sandstone
	Color(0.33f, 0.32f, 0.31f), // shale
};

void PlanetRock::_bind_methods() {
	BIND_ENUM_CONSTANT(BASALT);
	BIND_ENUM_CONSTANT(ANDESITE);
	BIND_ENUM_CONSTANT(GRANITE);
	BIND_ENUM_CONSTANT(GNEISS);
	BIND_ENUM_CONSTANT(SCHIST);
	BIND_ENUM_CONSTANT(LIMESTONE);
	BIND_ENUM_CONSTANT(SANDSTONE);
	BIND_ENUM_CONSTANT(RED_SANDSTONE);
	BIND_ENUM_CONSTANT(SHALE);
	ClassDB::bind_static_method("PlanetRock", D_METHOD("get_boundary"), &PlanetRock::get_boundary);
	ClassDB::bind_static_method("PlanetRock", D_METHOD("colours"), &PlanetRock::colours);
	ClassDB::bind_static_method("PlanetRock", D_METHOD("kind_count"), &PlanetRock::kind_count);
	ClassDB::bind_static_method("PlanetRock", D_METHOD("create", "tectonics", "world_seed", "radius", "relief"), &PlanetRock::create);
	ClassDB::bind_method(D_METHOD("get__craton"), &PlanetRock::get__craton);
	ClassDB::bind_method(D_METHOD("set__craton", "value"), &PlanetRock::set__craton);
	ADD_PROPERTY(PropertyInfo(Variant::OBJECT, "_craton", PROPERTY_HINT_RESOURCE_TYPE, "FastNoiseLite", PROPERTY_USAGE_NO_EDITOR), "set__craton", "get__craton");
	ClassDB::bind_method(D_METHOD("get__basin"), &PlanetRock::get__basin);
	ClassDB::bind_method(D_METHOD("set__basin", "value"), &PlanetRock::set__basin);
	ADD_PROPERTY(PropertyInfo(Variant::OBJECT, "_basin", PROPERTY_HINT_RESOURCE_TYPE, "FastNoiseLite", PROPERTY_USAGE_NO_EDITOR), "set__basin", "get__basin");
	ClassDB::bind_method(D_METHOD("weights", "dir", "ground"), &PlanetRock::weights);
	ClassDB::bind_method(D_METHOD("dominant", "dir", "ground"), &PlanetRock::dominant);
	ClassDB::bind_method(D_METHOD("colour", "dir", "ground", "steep", "speckle", "sea_temperature", "strata", "rain"), &PlanetRock::colour,
			DEFVAL(15.0), DEFVAL(true), DEFVAL(0.5));
}

PackedColorArray PlanetRock::colours() {
	PackedColorArray all;
	for (int i = 0; i < 9; i++) {
		all.append(COLOURS[i]);
	}
	return all;
}

Ref<PlanetRock> PlanetRock::create(const Ref<PlanetTectonics> &p_tectonics, int64_t p_world_seed, double p_radius, double p_relief) {
	Ref<PlanetRock> made;
	made.instantiate();
	made->tectonics = p_tectonics;
	made->relief = p_relief;
	made->radius = p_radius;
	made->craton_noise.instantiate();
	made->basin_noise.instantiate();
	made->craton_noise->set_noise_type(FastNoiseLite::TYPE_SIMPLEX_SMOOTH);
	made->craton_noise->set_seed((int32_t)(p_world_seed + 9));
	made->craton_noise->set_frequency(1.0 / (p_radius * 0.5));
	made->craton_noise->set_fractal_octaves(2);
	made->basin_noise->set_noise_type(FastNoiseLite::TYPE_SIMPLEX_SMOOTH);
	made->basin_noise->set_seed((int32_t)(p_world_seed + 10));
	made->basin_noise->set_frequency(1.0 / (p_radius * 0.3));
	made->basin_noise->set_fractal_octaves(3);
	return made;
}

// How much of each rock (see `Kind`) is at the unit direction `dir`, on ground `ground` (m above the sea): nine weights that add up to 1.
PackedFloat32Array PlanetRock::weights(const Vector3 &p_dir, double p_ground) const {
	Vector3 plate = tectonics->plate_at(p_dir);
	bool continental = plate.z > 0.5;
	double near_edge = std::exp(-std::pow(plate.y / BOUNDARY, 2.0));
	double tall = CLAMP(p_ground / relief, 0.0, 1.0);
	Vector3 p = p_dir * radius;
	double old = smooth_step(-0.15, 0.3, craton_noise->get_noise_3d(p.x, p.y, p.z));
	double regional = CLAMP(0.5 + 1.1 * basin_noise->get_noise_3d(p.x, p.y, p.z), 0.0, 1.0);
	PackedFloat32Array w;
	w.resize(9);
	w.fill(0.0f);
	if (!continental) {
		// young crust under a cover of sediment that thickens toward the continents' feet
		double cover = smooth_step(-0.2, 0.0, p_ground / relief);
		w[BASALT] = 0.5;
		w[SHALE] = 0.25;
		w[LIMESTONE] = 0.1 + 0.25 * cover;
		w[SANDSTONE] = 0.15 * cover;
		w[ANDESITE] = near_edge * 0.9; // the arcs and the trenches' sides
	} else {
		double high = smooth_step(0.12, 0.5, tall); // stripped to the old rock
		double basement = CLAMP(old + high, 0.0, 1.0);
		w[GRANITE] = basement * 0.55;
		w[GNEISS] = basement * 0.45;
		double sediment = 1.0 - basement;
		// which sediment: a slow regional pattern (warm sea, desert, deep water, mud)
		w[LIMESTONE] = sediment * smooth_step(0.58, 0.7, regional);
		w[RED_SANDSTONE] = sediment * smooth_step(0.3, 0.18, regional);
		w[SHALE] = sediment * smooth_step(0.1, 0.22, regional) * smooth_step(0.46, 0.34, regional);
		w[SANDSTONE] = sediment * smooth_step(0.3, 0.38, regional) * smooth_step(0.7, 0.6, regional);
		// a boundary between continents, or a coast range: metamorphic rock
		double schist = smooth_step(0.35, 0.65, regional);
		w[GNEISS] = (double)w[GNEISS] + near_edge * 0.9 * (1.0 - schist);
		w[SCHIST] = near_edge * 1.1 * schist;
		w[ANDESITE] = near_edge * 0.3;
	}
	double total = 0.0;
	for (int i = 0; i < 9; i++) {
		total += w[i];
	}
	if (total <= 0.0001) {
		w[GRANITE] = 1.0;
		total = 1.0;
	}
	for (int i = 0; i < 9; i++) {
		w[i] = (double)w[i] / total;
	}
	return w;
}

// The rock there in most amount (a `Kind`).
int64_t PlanetRock::dominant(const Vector3 &p_dir, double p_ground) const {
	PackedFloat32Array w = weights(p_dir, p_ground);
	int best = 0;
	for (int i = 0; i < w.size(); i++) {
		if (w[i] > w[best]) {
			best = i;
		}
	}
	return best;
}

// The colour of the crust at `dir` on `ground`, on a face `steep` steep (0 level .. 1 vertical), with `speckle` (0..1) the fine variation
// there. `sea_temperature` (degrees C, the year's mean at sea level there) puts permanent snow and ice where the cold keeps it.
Color PlanetRock::colour(const Vector3 &p_dir, double p_ground, double p_steep, double p_speckle, double p_sea_temperature, bool p_strata,
		double p_rain) const {
	PackedFloat32Array w = weights(p_dir, p_ground);
	Color rock(0.0f, 0.0f, 0.0f);
	for (int i = 0; i < 9; i++) {
		rock += COLOURS[i] * (float)w[i];
	}
	// the beds: bands that run level, in the sedimentary rocks
	double sedimentary = (double)w[LIMESTONE] + (double)w[SANDSTONE] + (double)w[RED_SANDSTONE] + (double)w[SHALE];
	double bed = std::max(relief * 0.03, 6.0);
	// (no fine noise in the band's phase: it would break the beds into patches one facet big)
	double layers = 0.5 + 0.5 * std::sin(p_ground / bed * TAU_D);
	// the sea floor shows no beds (they showed as contour rings)
	double on_land = smooth_step(0.0, 200.0, p_ground);
	if (p_strata) { // (a map's big pixels would only alias the beds into grain)
		rock = rock * (float)(1.0 + (layers - 0.5) * 0.24 * sedimentary * on_land);
	}
	rock = rock * (float)(0.94 + 0.12 * p_speckle);
	rock = rock.lerp(rock * 0.62f, (float)smooth_step(0.35, 0.8, p_steep));
	double cold = p_sea_temperature - LAPSE * std::max(p_ground, 0.0);
	// scree: pale rubble that has fallen on the moderately steep slopes of the high ground
	double scree = smooth_step(0.2, 0.38, p_steep) * (1.0 - smooth_step(0.55, 0.75, p_steep));
	scree *= smooth_step(150.0, 600.0, p_ground) * 0.45;
	rock = rock.lerp(SCREE, (float)scree);
	// wetland: dark green-brown on the low, flat, wet ground
	double wet_here = CLAMP(p_rain / 0.9, 0.0, 1.0);
	double wetland = smooth_step(25.0, 4.0, p_ground) * (1.0 - smooth_step(0.05, 0.2, p_steep));
	wetland *= smooth_step(0.5, 0.9, wet_here) * smooth_step(2.0, 10.0, cold);
	wetland *= smooth_step(0.0, 1.0, p_ground);
	rock = rock.lerp(WETLAND, (float)(wetland * 0.55));
	// soil: deep and dark where it is wet and mild, thin and pale where it is dry, none on steep rock
	double fertile = CLAMP(p_rain / 0.9, 0.0, 1.0) * smooth_step(-5.0, 10.0, cold);
	Color soil_colour = SOIL_DRY.lerp(SOIL_RICH, (float)fertile);
	double soil = on_land * (1.0 - smooth_step(0.2, 0.55, p_steep)) * (0.3 + 0.7 * fertile) * 0.6;
	rock = rock.lerp(soil_colour, (float)soil);
	// plant cover: dry grass, grass, the dark of forests, by rain and warmth; none on steep rock, in the desert or the cold
	double wet = CLAMP(p_rain / 0.9, 0.0, 1.0);
	// (the cover ramps up over the first few metres of land, not over 200 m like the rock stripes and the soil)
	double cover = smooth_step(0.5, 10.0, p_ground) * smooth_step(-3.0, 6.0, cold) * smooth_step(0.12, 0.55, wet);
	cover *= 1.0 - smooth_step(0.3, 0.65, p_steep);
	Color green = STEPPE.lerp(MEADOW, (float)smooth_step(0.3, 0.7, wet));
	green = green.lerp(FOREST, (float)(smooth_step(0.7, 1.0, wet) * smooth_step(8.0, 16.0, cold) * 0.8));
	rock = rock.lerp(green, (float)(cover * 0.9));
	double snow = smooth_step(-0.5, -4.5, cold) * smooth_step(0.0, 60.0, p_ground);
	snow *= 1.0 - 0.85 * smooth_step(0.5, 0.95, p_steep); // the steepest rock stays bare
	rock = rock.lerp(SNOW, (float)(snow * 0.92));
	// glacier ice: blue-white on the gentle ground where it is very cold (the ice of a valley)
	double ice = smooth_step(-7.0, -13.0, cold) * (1.0 - smooth_step(0.25, 0.6, p_steep)) * snow;
	rock = rock.lerp(ICE, (float)(ice * 0.7));
	double beach = smooth_step(4.0, 0.5, p_ground) * smooth_step(0.0, 0.5, p_ground + 0.5);
	beach *= 1.0 - smooth_step(0.15, 0.45, p_steep);
	rock = rock.lerp(SAND, (float)(beach * 0.85 * (1.0 - snow)));
	return Color(CLAMP(rock.r, 0.0f, 1.0f), CLAMP(rock.g, 0.0f, 1.0f), CLAMP(rock.b, 0.0f, 1.0f));
}
