#include "planet_noise_native.h"

#include "planet_star_native.h"

#include <godot_cpp/classes/class_db_singleton.hpp>
#include <godot_cpp/classes/os.hpp>
#include <godot_cpp/classes/random_number_generator.hpp>
#include <godot_cpp/classes/resource_loader.hpp>
#include <godot_cpp/classes/script.hpp>
#include <godot_cpp/classes/time.hpp>
#include <godot_cpp/variant/utility_functions.hpp>

#include <algorithm>
#include <cmath>

using namespace godot;

static const double TAU_D = 6.283185307179586476925286766559;
static const double PI_D = 3.14159265358979323846;

static double smooth_step(double p_from, double p_to, double p_x) {
	if (p_from == p_to) {
		return p_x < p_from ? 0.0 : 1.0;
	}
	double s = CLAMP((p_x - p_from) / (p_to - p_from), 0.0, 1.0);
	return s * s * (3.0 - 2.0 * s);
}

// the Biome enum of terrain_noise.gd: BEACH, MEADOW, FOREST, ROCKY, SNOW, MARSH, DESERT
enum { BIOME_BEACH, BIOME_MEADOW, BIOME_FOREST, BIOME_ROCKY, BIOME_SNOW, BIOME_MARSH, BIOME_DESERT };

void PlanetNoise::_bind_methods() {
	NP_BIND_OBJ(PlanetNoise, settings, "PlanetSettings")
	NP_BIND_STATE(PlanetNoise, Variant::FLOAT, relief)
	NP_BIND_OBJ(PlanetNoise, tectonics, "PlanetTectonics")
	NP_BIND_OBJ(PlanetNoise, climate, "PlanetClimate")
	ClassDB::bind_method(D_METHOD("get_species"), &PlanetNoise::get_species);
	ClassDB::bind_method(D_METHOD("set_species", "value"), &PlanetNoise::set_species);
	ADD_PROPERTY(PropertyInfo(Variant::NIL, "species", PROPERTY_HINT_NONE, "", PROPERTY_USAGE_NO_EDITOR | PROPERTY_USAGE_NIL_IS_VARIANT), "set_species", "get_species");
	NP_BIND_OBJ(PlanetNoise, weather, "PlanetWeather")
	NP_BIND_OBJ(PlanetNoise, clock, "PlanetClock")
	NP_BIND_STATE(PlanetNoise, Variant::VECTOR3, clearing)
	NP_BIND_OBJ(PlanetNoise, rock, "PlanetRock")
	NP_BIND_OBJ(PlanetNoise, scatter_native, "RefCounted")
	NP_BIND_OBJ(PlanetNoise, native, "PlanetCrustNative")
	NP_BIND_OBJ(PlanetNoise, water_native, "PlanetWaterNative")
	NP_BIND_OBJ(PlanetNoise, drainage, "PlanetDrainage")
	NP_BIND_STATE(PlanetNoise, Variant::DICTIONARY, map_heights)
	NP_BIND_STATE(PlanetNoise, Variant::FLOAT, _sea)

	BIND_CONSTANT(EROSION_OCTAVES);
	ClassDB::bind_static_method("PlanetNoise", D_METHOD("create", "settings"), &PlanetNoise::create);
	ClassDB::bind_static_method("PlanetNoise", D_METHOD("noise_config", "source"), &PlanetNoise::noise_config);
	ClassDB::bind_static_method("PlanetNoise", D_METHOD("cube_faces"), &PlanetNoise::cube_faces);
	ClassDB::bind_method(D_METHOD("water_at", "dir", "ground"), &PlanetNoise::water_at);
	ClassDB::bind_method(D_METHOD("near_water", "dir", "ground", "margin"), &PlanetNoise::near_water);
	ClassDB::bind_method(D_METHOD("flow_at", "dir"), &PlanetNoise::flow_at);
	ClassDB::bind_method(D_METHOD("heights_of", "dirs"), &PlanetNoise::heights_of);
	ClassDB::bind_method(D_METHOD("macro_heights_of", "dirs", "pixel"), &PlanetNoise::macro_heights_of, DEFVAL(-1.0));
	ClassDB::bind_method(D_METHOD("colours_of", "dirs", "grounds", "steeps"), &PlanetNoise::colours_of);
	ClassDB::bind_method(D_METHOD("height", "x", "y", "z"), &PlanetNoise::height);
	ClassDB::bind_method(D_METHOD("macro_height", "x", "y", "z"), &PlanetNoise::macro_height);
	ClassDB::bind_method(D_METHOD("shore", "units"), &PlanetNoise::shore);
	ClassDB::bind_method(D_METHOD("moisture", "x", "y", "z"), &PlanetNoise::moisture);
	ClassDB::bind_method(D_METHOD("heat", "x", "y", "z", "ground"), &PlanetNoise::heat);
	ClassDB::bind_method(D_METHOD("temperature", "x", "y", "z", "ground"), &PlanetNoise::temperature);
	ClassDB::bind_method(D_METHOD("temperature_now", "x", "y", "z", "ground", "at_clock", "macro"), &PlanetNoise::temperature_now,
			DEFVAL(Ref<PlanetClock>()), DEFVAL(NAN));
	ClassDB::bind_method(D_METHOD("detail", "x", "y", "z"), &PlanetNoise::detail);
	ClassDB::bind_method(D_METHOD("detail_at", "point"), &PlanetNoise::detail_at);
	ClassDB::bind_method(D_METHOD("biome", "x", "y", "z", "ground", "steepness"), &PlanetNoise::biome);
	ClassDB::bind_method(D_METHOD("facet_color", "x", "y", "z", "ground", "steep", "coarse"), &PlanetNoise::facet_color, DEFVAL(false));
	ClassDB::bind_method(D_METHOD("is_solid_ground", "dir"), &PlanetNoise::is_solid_ground);
	ClassDB::bind_method(D_METHOD("solid_spawn", "dir"), &PlanetNoise::solid_spawn);
	ClassDB::bind_method(D_METHOD("find_spawn", "in_desert"), &PlanetNoise::find_spawn, DEFVAL(false));
}

// PLANET_TIMING=1 prints how long each step of making a planet takes.
void PlanetNoise::lap(const String &p_what) {
	if (OS::get_singleton()->has_environment("PLANET_TIMING")) {
		uint64_t now = Time::get_singleton()->get_ticks_msec();
		UtilityFunctions::print(vformat("PLANET_TIMING %-22s %5d ms", p_what, (int64_t)(now - lap_at)));
		lap_at = now;
	}
}

void PlanetNoise::setup_noise(const Ref<FastNoiseLite> &p_noise, int64_t p_seed, double p_frequency, int p_octaves) {
	p_noise->set_noise_type(FastNoiseLite::TYPE_SIMPLEX_SMOOTH);
	p_noise->set_seed((int32_t)p_seed);
	p_noise->set_frequency(p_frequency);
	p_noise->set_fractal_type(FastNoiseLite::FRACTAL_FBM);
	p_noise->set_fractal_octaves(p_octaves);
}

Array PlanetNoise::noise_config(const Ref<FastNoiseLite> &p_source) {
	Array config;
	config.append(p_source->get_seed());
	config.append(p_source->get_frequency());
	config.append(p_source->get_fractal_octaves());
	config.append((int)p_source->get_fractal_type());
	return config;
}

// the six cube faces: [normal, u, v] each (PlanetTile.FACES)
PackedVector3Array PlanetNoise::cube_faces() {
	static const float faces[6][3][3] = {
		{ { 1, 0, 0 }, { 0, 0, -1 }, { 0, 1, 0 } },
		{ { -1, 0, 0 }, { 0, 0, 1 }, { 0, 1, 0 } },
		{ { 0, 1, 0 }, { 1, 0, 0 }, { 0, 0, -1 } },
		{ { 0, -1, 0 }, { 1, 0, 0 }, { 0, 0, 1 } },
		{ { 0, 0, 1 }, { 1, 0, 0 }, { 0, 1, 0 } },
		{ { 0, 0, -1 }, { -1, 0, 0 }, { 0, 1, 0 } },
	};
	PackedVector3Array all;
	for (int face = 0; face < 6; face++) {
		for (int axis = 0; axis < 3; axis++) {
			all.append(Vector3(faces[face][axis][0], faces[face][axis][1], faces[face][axis][2]));
		}
	}
	return all;
}

Ref<PlanetNoise> PlanetNoise::create(const Ref<PlanetSettings> &p_settings) {
	Ref<PlanetNoise> made;
	made.instantiate();
	made->init(p_settings);
	return made;
}

static Variant load_script_call(const String &p_path, const StringName &p_method, const Variant &p_a = Variant(), const Variant &p_b = Variant(), int p_args = 0) {
	Ref<Script> script = ResourceLoader::get_singleton()->load(p_path);
	if (script.is_null()) {
		return Variant();
	}
	if (p_args == 2) {
		return script->call(p_method, p_a, p_b);
	}
	return script->call(p_method, p_a);
}

void PlanetNoise::init(const Ref<PlanetSettings> &p_settings) {
	lap_at = Time::get_singleton()->get_ticks_msec();
	settings = p_settings;
	relief = settings->get_relief();
	if (relief <= 0.0) {
		relief = CLAMP(settings->get_radius() * 0.0035, 300.0, 12000.0);
	}
	climate.instantiate();
	tectonics = PlanetTectonics::create(settings->get_world_seed(), settings->get_plates());
	rock = PlanetRock::create(tectonics, settings->get_world_seed(), settings->get_radius(), relief);
	lap("plates and rock");
	Ref<Script> registry = ResourceLoader::get_singleton()->load("res://systems/world_gen/flora/species_registry.gd");
	species = registry->call("new", settings->get_world_seed(), settings->get_species_count());
	Array all_species = ((Object *)species)->get("species");
	StarLight::apply(all_species, Star::from_mass(settings->get_star_mass()), settings->get_star_readability());
	for (int i = 0; i < all_species.size(); i++) { // a planet has many plants: more looks of each tree
		Object *one = all_species[i];
		if ((bool)one->call("is_tree")) {
			one->set("variants", 6);
		} else if ((int64_t)one->get("variants") < 3) {
			one->set("variants", 3);
		}
	}
	lap("species");
	int64_t seed = settings->get_world_seed();
	double radius = settings->get_radius();
	for (Ref<FastNoiseLite> *noise : { &rolling, &ranges, &range_mask, &hills, &gullies, &detail_noise, &massif, &chain, &foothills }) {
		noise->instantiate();
	}
	for (int i = 0; i < 3; i++) {
		valleys[i].instantiate();
	}
	setup_noise(rolling, seed + 2, 0.0004, 3);
	setup_noise(ranges, seed + 4, 1.0 / (radius * 0.18), 5);
	ranges->set_fractal_type(FastNoiseLite::FRACTAL_RIDGED);
	setup_noise(range_mask, seed + 5, 1.0 / (radius * 0.5), 2);
	setup_noise(hills, seed + 1, 0.0022, 4);
	setup_noise(gullies, seed + 3, 0.0018, 4);
	gullies->set_fractal_type(FastNoiseLite::FRACTAL_RIDGED);
	setup_noise(detail_noise, seed + 7, 0.09, 2);
	double massif_length = CLAMP(radius * 0.005, 800.0, 40000.0);
	setup_noise(massif, seed + 11, 1.0 / massif_length, 5);
	massif->set_fractal_type(FastNoiseLite::FRACTAL_RIDGED);
	double valley_length = CLAMP(radius * 0.02, 600.0, 120000.0);
	for (int scale_index = 0; scale_index < 3; scale_index++) {
		double length = valley_length / std::pow(4.0, (double)scale_index);
		setup_noise(valleys[scale_index], seed + 21 + scale_index, 1.0 / std::max(length, 150.0), 3);
		valley_depth[scale_index] = std::min(length * 0.05, relief * 0.06) * std::pow(0.5, (double)scale_index);
	}
	setup_noise(chain, seed + 17, 1.0 / CLAMP(radius * 0.02, 1500.0, 200000.0), 4);
	chain->set_fractal_type(FastNoiseLite::FRACTAL_RIDGED);
	setup_noise(foothills, seed + 13, 5.0 / massif_length, 4);
	foothills->set_fractal_type(FastNoiseLite::FRACTAL_RIDGED);
	lap("noises");
	make_native(); // (twice: the first only to find the sea level with, the second knows it)
	find_sea_level();
	make_native();
	lap("sea level");
	climate->build(this);
	native->set_climate(climate->temperature_grid(), PlanetClimate::WIDTH, PlanetClimate::HEIGHT, climate->rain_grid());
	make_scatter();
	lap("climate");
	weather = PlanetWeather::create(this);
	lap("weather");
	carve_valleys();
	lap("drainage");
}

// The native plant placement, with the species and the climate it reads.
void PlanetNoise::make_scatter() {
	scatter_native.unref();
	if (native.is_null() || OS::get_singleton()->has_environment("PLANET_NO_NATIVE") || !ClassDBSingleton::get_singleton()->class_exists("PlanetScatterNative")) {
		return;
	}
	Dictionary kinds;
	Ref<Script> flora = ResourceLoader::get_singleton()->load("res://systems/world_gen/flora_meshes.gd");
	Dictionary variants = Dictionary(flora->get_script_constant_map())["VARIANTS"];
	Array keys = variants.keys();
	for (int i = 0; i < keys.size(); i++) {
		kinds[keys[i]] = variants[keys[i]];
	}
	Ref<RefCounted> made = ClassDBSingleton::get_singleton()->instantiate("PlanetScatterNative");
	Dictionary config;
	config["crust"] = native;
	config["species"] = load_script_call("res://systems/planet/planet_scatter.gd", "species_table", species);
	config["temperature"] = climate->temperature_grid();
	config["rain"] = climate->rain_grid();
	config["width"] = PlanetClimate::WIDTH;
	config["height"] = PlanetClimate::HEIGHT;
	config["relief"] = relief;
	config["radius"] = settings->get_radius();
	config["plant_density"] = settings->get_plant_density();
	config["rock_density"] = settings->get_rock_density();
	config["world_seed"] = settings->get_world_seed();
	config["kind_variants"] = kinds;
	made->call("setup", config);
	scatter_native = made;
}

// Fixed hot spots in the mantle (unit directions, from the seed): as a plate drifts over one, a chain of volcanoes is left on it
// (the native crust draws the seamounts and the islands).
PackedVector3Array PlanetNoise::hotspots() const {
	Ref<RandomNumberGenerator> rng;
	rng.instantiate();
	rng->set_seed((uint64_t)(settings->get_world_seed() + 61));
	PackedVector3Array spots;
	for (int index = 0; index < 9; index++) {
		double x = rng->randfn();
		double y = rng->randfn();
		double z = rng->randfn();
		spots.append(Vector3(x, y, z).normalized());
	}
	return spots;
}

// Hands the crust's numbers to the native class.
void PlanetNoise::make_native() {
	native.unref();
	water_native.unref();
	Array valley_configs;
	for (int i = 0; i < 3; i++) {
		valley_configs.append(noise_config(valleys[i]));
	}
	PackedFloat32Array depths;
	for (int i = 0; i < 3; i++) {
		depths.append(valley_depth[i]);
	}
	PackedByteArray continental;
	Array land = tectonics->get__continental();
	for (int i = 0; i < land.size(); i++) {
		continental.append((bool)land[i] ? 1 : 0);
	}
	double radius = settings->get_radius();
	double massif_length = CLAMP(radius * 0.005, 800.0, 40000.0);
	Dictionary c;
	c["seeds"] = tectonics->get__seeds();
	c["spins"] = tectonics->get__spin();
	c["continental"] = continental;
	c["continent"] = PlanetTectonics::get_continent();
	c["ocean"] = PlanetTectonics::get_ocean();
	c["boundary"] = PlanetTectonics::get_boundary();
	c["soft"] = PlanetTectonics::get_soft();
	c["radius"] = radius;
	c["relief"] = relief;
	c["sea"] = sea_;
	c["shore"] = SHORE;
	c["shore_flat"] = SHORE_FLAT;
	c["land_curve"] = LAND_CURVE;
	c["deep"] = DEEP;
	c["massif_scale"] = MASSIF;
	c["chain_scale"] = CHAINS;
	c["foothill_scale"] = FOOTHILLS;
	c["erosion"] = OS::get_singleton()->has_environment("PLANET_NO_EROSION") ? 0.0 : EROSION;
	c["erosion_seed"] = settings->get_world_seed() + 41;
	c["erosion_octaves"] = EROSION_OCTAVES;
	c["hotspots"] = hotspots();
	c["erosion_wavelength"] = massif_length * EROSION_SCALE;
	c["valley_width"] = VALLEY_WIDTH;
	c["valley_depths"] = depths;
	c["rock_boundary"] = PlanetRock::get_boundary();
	c["rock_colours"] = PlanetRock::colours();
	c["warp"] = noise_config(tectonics->get__warp());
	c["ridge"] = noise_config(tectonics->get__ridge());
	c["interior"] = noise_config(tectonics->get__interior());
	c["rolling"] = noise_config(rolling);
	c["ranges"] = noise_config(ranges);
	c["range_mask"] = noise_config(range_mask);
	c["hills"] = noise_config(hills);
	c["gullies"] = noise_config(gullies);
	c["detail"] = noise_config(detail_noise);
	c["massif"] = noise_config(massif);
	c["chain"] = noise_config(chain);
	c["foothills"] = noise_config(foothills);
	c["faces"] = cube_faces();
	c["valleys"] = valley_configs;
	c["craton"] = noise_config(rock->get__craton());
	c["basin"] = noise_config(rock->get__basin());
	Ref<PlanetCrustNative> made;
	made.instantiate();
	made->setup(c);
	native = made;
	water_native.instantiate();
}

// The sea level is wherever the heights have the planet's ocean share below it (sampled over the sphere, every sample weighing the same area).
void PlanetNoise::find_sea_level() {
	sea_ = native->find_sea_level((int)settings->get_crust_samples(), settings->get_ocean_fraction(), settings->get_water_layer(), relief);
}

// The river valleys of the planet, from where its water runs: the drainage is solved on a coarse grid and its rivers, as curves, go to the
// native crust, which cuts the valleys along them.
void PlanetNoise::carve_valleys() {
	drainage.unref();
	OS *os = OS::get_singleton();
	if (native.is_null() || settings->get_drainage_cells() <= 0 || os->has_environment("PLANET_NO_DRAINAGE")) {
		return;
	}
	double cell_metres = settings->get_radius() * PI_D * 0.5 / (double)settings->get_drainage_cells();
	Dictionary kept = os->has_environment("PLANET_NO_DRAINAGE_CACHE") ? Dictionary() : PlanetDrainageCache::load_network(settings);
	if (!kept.is_empty()) {
		lap("drainage from the cache");
		native->set_rivers((int)settings->get_drainage_cells(), kept, cell_metres);
		drainage.instantiate(); // (nothing but its being there: the rivers are the crust's now)
		drainage->set_cells(settings->get_drainage_cells());
		return;
	}
	Ref<PlanetDrainage> solved;
	solved.instantiate();
	lap("native setup");
	if (!solved->build(this, settings->get_drainage_cells())) {
		return;
	}
	lap("drainage solve");
	Dictionary network = solved->network();
	lap("river network");
	native->set_rivers((int)settings->get_drainage_cells(), network, cell_metres);
	drainage = solved;
	if (!os->has_environment("PLANET_NO_DRAINAGE_CACHE")) {
		PlanetDrainageCache::save_network(settings, network);
		lap("drainage cache written");
	}
}

// The level of the river or lake water at `dir` where `ground` is under it, else -INF (the native crust knows the rivers).
double PlanetNoise::water_at(const Vector3 &p_dir, double p_ground) const {
	double level = native->water_at(p_dir, p_ground);
	return level > -1.0e20 ? level : -INFINITY;
}

// True if river or lake water is within `margin` metres of `dir`.
bool PlanetNoise::near_water(const Vector3 &p_dir, double p_ground, double p_margin) const {
	return native->near_water(p_dir, p_ground, p_margin);
}

// The current of the river at `dir` (planet space, m/s), zero out of a river.
Vector3 PlanetNoise::flow_at(const Vector3 &p_dir) const {
	return native->flow_at(p_dir);
}

PackedFloat32Array PlanetNoise::heights_of(const PackedVector3Array &p_dirs) const {
	return native->heights(p_dirs);
}

// The heights before the rivers are cut, the sign of which says land or sea (the weather asks), at many directions at once.
PackedFloat32Array PlanetNoise::macro_heights_of(const PackedVector3Array &p_dirs, double p_pixel) const {
	if (p_pixel >= 0.0) {
		return native->broad_heights(p_dirs, p_pixel);
	}
	return native->macro_heights(p_dirs);
}

// The crust colours at many directions at once, with each one's ground height and steepness.
PackedColorArray PlanetNoise::colours_of(const PackedVector3Array &p_dirs, const PackedFloat32Array &p_grounds, const PackedFloat32Array &p_steeps) const {
	return native->colours(p_dirs, p_grounds, p_steeps);
}

// Ground height in metres above the sea, in the unit direction (x, y, z), rivers cut in.
double PlanetNoise::height(double p_x, double p_y, double p_z) const {
	return native->height_at(Vector3(p_x, p_y, p_z));
}

// The ground without the smallest hills: what the water sees when it picks its way to the sea.
double PlanetNoise::macro_height(double p_x, double p_y, double p_z) const {
	PackedVector3Array one;
	one.append(Vector3(p_x, p_y, p_z));
	return native->macro_heights(one)[0];
}

// Beaches and shallows: the ground eases toward the sea instead of dropping into it. The slope is a fifth of the plates' right at the sea
// and grows to the plates' own over `SHORE` of the relief.
double PlanetNoise::shore(double p_units) const {
	double reach = std::abs(p_units) / SHORE;
	double eased = reach < 1.0 ? reach * reach * reach * (1.0 - reach * 0.5) : reach - 0.5;
	double sign = p_units > 0.0 ? 1.0 : (p_units < 0.0 ? -1.0 : 0.0);
	double raw = sign * (SHORE_FLAT * std::abs(p_units) + (1.0 - SHORE_FLAT) * SHORE * eased);
	if (p_units > 0.0) { // most of the land is low: a hypsometric curve (the high ground is the rare part)
		raw = std::pow(raw, LAND_CURVE);
	}
	if (p_units < 0.0) { // the sea floor drops away past the shelf toward the abyssal plains
		raw *= 1.0 + DEEP * smooth_step(0.05, 0.3, -p_units);
	}
	return raw;
}

// 0 dry .. 1 wet.
double PlanetNoise::moisture(double p_x, double p_y, double p_z) const {
	return CLAMP((double)climate->sample(Vector3(p_x, p_y, p_z)).y / 1.2, 0.0, 1.0);
}

// 0 cold .. 1 hot (the temperature at `ground` metres, see `temperature`).
double PlanetNoise::heat(double p_x, double p_y, double p_z, double p_ground) const {
	return CLAMP((temperature(p_x, p_y, p_z, p_ground) + 20.0) / 55.0, 0.0, 1.0);
}

// Degrees C at the direction and height: the latitude's sea level warmth minus the lapse rate. A tall range of a small planet is as cold on
// top as a tall range of a big one (height is taken as a share of the planet's relief).
double PlanetNoise::temperature(double p_x, double p_y, double p_z, double p_ground) const {
	double sea_level = climate->sample(Vector3(p_x, p_y, p_z)).x;
	return sea_level - std::max(p_ground, 0.0) / relief * EARTH_RELIEF / 1000.0 * LAPSE;
}

// Degrees C right now at the direction and height: the season (the cycle PlanetSeasons made, read at the clock's share of the year) and the
// time of day (warmest in the early afternoon, more so over land and under a clear sky), minus the lapse rate. With no clock it is the
// yearly mean.
double PlanetNoise::temperature_now(double p_x, double p_y, double p_z, double p_ground, const Ref<PlanetClock> &p_at_clock, double p_macro) const {
	Ref<PlanetClock> which = p_at_clock.is_valid() ? p_at_clock : clock;
	if (which.is_null()) {
		return temperature(p_x, p_y, p_z, p_ground);
	}
	Vector3 dir(p_x, p_y, p_z);
	double degrees = climate->get_seasons()->at(dir, which->year_share());
	// (`macro`: the height before the rivers, when the caller has it already, as a map row does)
	bool land = (!std::isnan(p_macro) ? p_macro : macro_height(p_x, p_y, p_z)) >= 0.0;
	double swing = land ? 6.0 : 0.8;
	double hour = which->local_hour(dir);
	double clear = CLAMP(which->day_length(std::asin(p_y)) * 2.0 + 0.3, 0.3, 1.0);
	degrees += swing * std::cos((hour - 14.5) / 24.0 * TAU_D) * clear;
	return degrees - std::max(p_ground, 0.0) / relief * EARTH_RELIEF / 1000.0 * LAPSE;
}

// Fine variation 0..1, for colour speckle.
double PlanetNoise::detail(double p_x, double p_y, double p_z) const {
	Vector3 p = Vector3(p_x, p_y, p_z) * settings->get_radius();
	return detail_noise->get_noise_3d(p.x, p.y, p.z) * 0.5 + 0.5;
}

// Fine variation 0..1 at a made-up point (patches of one plant species).
double PlanetNoise::detail_at(const Vector3 &p_point) const {
	return detail_noise->get_noise_3d(p_point.x, p_point.y, p_point.z) * 0.5 + 0.5;
}

int64_t PlanetNoise::biome(double p_x, double p_y, double p_z, double p_ground, double p_steepness) const {
	double wet = moisture(p_x, p_y, p_z);
	if (p_ground < 1.4) {
		return wet < 0.5 ? BIOME_BEACH : BIOME_MARSH;
	}
	double degrees = temperature(p_x, p_y, p_z, p_ground);
	if (degrees < -14.0) {
		return BIOME_SNOW;
	}
	if (p_steepness > 0.62 || p_ground > relief * 0.5) {
		return BIOME_ROCKY;
	}
	if (wet < 0.2 && degrees > 2.0) {
		return BIOME_DESERT;
	}
	return wet > 0.5 ? BIOME_FOREST : BIOME_MEADOW;
}

// The colour of a ground facet: the rock of the crust there (PlanetRock), nothing grows on it yet.
Color PlanetNoise::facet_color(double p_x, double p_y, double p_z, double p_ground, double p_steep, bool p_coarse) const {
	double speckle = p_coarse ? 0.5 : detail(p_x, p_y, p_z); // (a map's pixels of many metres: no fine grain)
	Vector3 here(p_x, p_y, p_z);
	return rock->colour(here, p_ground, p_steep, speckle, climate->sea_temperature(here), !p_coarse, climate->sample(here).y);
}

// True where a person can stand: dry land well above the sea, not in a lake or a river or at the edge of one, and not on a steep slope.
bool PlanetNoise::is_solid_ground(const Vector3 &p_dir) const {
	double ground = height(p_dir.x, p_dir.y, p_dir.z);
	if (ground < SPAWN_ABOVE_SEA) {
		return false;
	}
	if (water_at(p_dir, ground) > -INFINITY || near_water(p_dir, ground, SPAWN_FROM_WATER)) {
		return false;
	}
	Vector3 up = p_dir.cross(Vector3(0, 1, 0)).normalized();
	for (int k = 0; k < 4; k++) { // the ground a few metres round: no cliff, nothing under the sea
		Vector3 side = (p_dir + up.rotated(p_dir, (double)k * PI_D * 0.5) * 8.0 / settings->get_radius()).normalized();
		double there = height(side.x, side.y, side.z);
		if (there < SPAWN_ABOVE_SEA * 0.5 || std::abs(there - ground) > 8.0 * 0.5) {
			return false;
		}
	}
	return true;
}

// `dir` if it is solid ground, else the nearest direction that is (searched in widening rings round it, out to about 30 km or the planet's
// own limit), else the planet's best spawn: the character is never put in the sea or a river.
Vector3 PlanetNoise::solid_spawn(const Vector3 &p_dir) const {
	Vector3 from = p_dir.normalized();
	if (is_solid_ground(from)) {
		return from;
	}
	Vector3 side = from.cross(Vector3(0, 1, 0));
	if (side.length_squared() < 0.0001) {
		side = from.cross(Vector3(1, 0, 0));
	}
	side = side.normalized();
	double reach = 40.0;
	double limit = std::min(30000.0, settings->get_radius() * 0.45);
	while (reach <= limit) {
		int count = CLAMP((int)(reach * TAU_D / 60.0), 8, 96); // a point every 60 m round the ring
		for (int step = 0; step < count; step++) {
			Vector3 around = side.rotated(from, TAU_D * (double)step / (double)count);
			Vector3 spot = (from + around * (reach / settings->get_radius())).normalized();
			if (is_solid_ground(spot)) {
				return spot;
			}
		}
		reach *= 1.35;
	}
	return find_spawn();
}

// A direction for the player to start on (`in_desert`: the first solid desert spot of a spiral): green country (mild, wet enough) that is not
// a dead flat plain: a little above the sea, with hills round it, and a river or the sea within a few kilometres, the best of the places
// found by a spiral over the planet.
Vector3 PlanetNoise::find_spawn(bool p_in_desert) const {
	if (p_in_desert) {
		for (int index = 0; index < 3000; index++) {
			double y = 1.0 - 2.0 * ((double)index + 0.5) / 3000.0;
			double ring = std::sqrt(std::max(1.0 - y * y, 0.0));
			double angle = (double)index * 2.399963;
			Vector3 dir(std::cos(angle) * ring, y, std::sin(angle) * ring);
			double h = height(dir.x, dir.y, dir.z);
			if (h < 5.0 || h > relief * 0.15) {
				continue;
			}
			if (biome(dir.x, dir.y, dir.z, h, 0.05) != BIOME_DESERT) {
				continue;
			}
			Vector3 spot = solid_spawn(dir);
			if (spot.dot(dir) > 0.99999) {
				return spot;
			}
		}
	}
	Vector3 best(0.0, 0.0, 1.0);
	double best_score = -INFINITY;
	for (int index = 0; index < 2500; index++) {
		double angle = (double)index * 2.399963;
		double y = 0.85 * std::sin((double)index * 0.7);
		double ring = std::sqrt(1.0 - y * y);
		Vector3 dir(std::cos(angle) * ring, y, std::sin(angle) * ring);
		double h = height(dir.x, dir.y, dir.z);
		if (h < 4.0 || h > relief * 0.1) {
			continue;
		}
		PackedVector3Array one;
		one.append(dir);
		PackedFloat32Array surfaces = native->call("lake_surfaces", one);
		double surface = surfaces[0];
		if (surface > -1.0e8) { // not in a lake
			continue;
		}
		Vector2 weather_here = climate->sample(dir);
		if (weather_here.x < 6.0 || weather_here.x > 28.0 || weather_here.y < 0.4) {
			continue;
		}
		Vector3 up = dir.cross(Vector3(0, 1, 0)).normalized();
		double lowest = h;
		double highest = h;
		bool sea = false;
		double steepest = 0.0;
		for (int k = 0; k < 8; k++) {
			for (double reach : { 60.0, 400.0, 2500.0 }) {
				Vector3 side = (dir + up.rotated(dir, (double)k * PI_D * 0.25) * reach / settings->get_radius()).normalized();
				double there = height(side.x, side.y, side.z);
				lowest = std::min(lowest, there);
				highest = std::max(highest, there);
				sea = sea || there < 0.0;
				if (reach == 60.0) {
					steepest = std::max(steepest, std::abs(there - h) / 60.0);
				}
			}
		}
		if (steepest > 0.3) {
			continue; // the foot of a cliff
		}
		double score = std::min(highest - lowest, relief * 0.2) + (sea ? relief * 0.05 : 0.0);
		score += weather_here.y * relief * 0.03 - std::abs(weather_here.x - 17.0);
		if (score > best_score) {
			best_score = score;
			best = dir;
		}
	}
	return best;
}
