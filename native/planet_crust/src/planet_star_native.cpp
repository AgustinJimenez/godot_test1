#include "planet_star_native.h"

#include <godot_cpp/variant/utility_functions.hpp>

#include <algorithm>
#include <cmath>
#include <vector>

using namespace godot;

static const double TAU_D = 6.283185307179586476925286766559;

static double lerp_angle_d(double p_from, double p_to, double p_weight) {
	double difference = std::fmod(p_to - p_from, TAU_D);
	double distance = std::fmod(2.0 * difference, TAU_D) - difference;
	return p_from + distance * p_weight;
}

static double positive_mod_d(double p_x, double p_y) {
	double value = std::fmod(p_x, p_y);
	if ((value < 0.0 && p_y > 0.0) || (value > 0.0 && p_y < 0.0)) {
		value += p_y;
	}
	return value;
}

// ---- Star ----

void Star::_bind_methods() {
	ClassDB::bind_static_method("Star", D_METHOD("get_sun_temperature"), &Star::get_sun_temperature);
	ClassDB::bind_static_method("Star", D_METHOD("get_adaptation"), &Star::get_adaptation);
	NP_BIND(Star, Variant::FLOAT, mass)
	NP_BIND(Star, Variant::FLOAT, age)
	ClassDB::bind_static_method("Star", D_METHOD("from_mass", "star_mass", "star_age"), &Star::from_mass, DEFVAL(4.6));
	ClassDB::bind_method(D_METHOD("get_luminosity"), &Star::get_luminosity);
	ClassDB::bind_method(D_METHOD("get_radius"), &Star::get_radius);
	ClassDB::bind_method(D_METHOD("get_temperature"), &Star::get_temperature);
	ClassDB::bind_method(D_METHOD("get_lifetime"), &Star::get_lifetime);
	ClassDB::bind_method(D_METHOD("get_colour"), &Star::get_colour);
	ClassDB::bind_method(D_METHOD("get_spectral_class"), &Star::get_spectral_class);
	ClassDB::bind_method(D_METHOD("get_flare_level"), &Star::get_flare_level);
	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "luminosity", PROPERTY_HINT_NONE, "", PROPERTY_USAGE_NO_EDITOR), "", "get_luminosity");
	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "radius", PROPERTY_HINT_NONE, "", PROPERTY_USAGE_NO_EDITOR), "", "get_radius");
	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "temperature", PROPERTY_HINT_NONE, "", PROPERTY_USAGE_NO_EDITOR), "", "get_temperature");
	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "lifetime", PROPERTY_HINT_NONE, "", PROPERTY_USAGE_NO_EDITOR), "", "get_lifetime");
	ADD_PROPERTY(PropertyInfo(Variant::COLOR, "colour", PROPERTY_HINT_NONE, "", PROPERTY_USAGE_NO_EDITOR), "", "get_colour");
	ADD_PROPERTY(PropertyInfo(Variant::STRING, "spectral_class", PROPERTY_HINT_NONE, "", PROPERTY_USAGE_NO_EDITOR), "", "get_spectral_class");
	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "flare_level", PROPERTY_HINT_NONE, "", PROPERTY_USAGE_NO_EDITOR), "", "get_flare_level");
	ClassDB::bind_method(D_METHOD("habitable_zone"), &Star::habitable_zone);
	ClassDB::bind_method(D_METHOD("frost_line"), &Star::frost_line);
	ClassDB::bind_method(D_METHOD("lock_distance"), &Star::lock_distance);
	ClassDB::bind_method(D_METHOD("old_enough_for_life"), &Star::old_enough_for_life);
	ClassDB::bind_method(D_METHOD("light_tint", "readability"), &Star::light_tint, DEFVAL(0.0));
	ClassDB::bind_static_method("Star", D_METHOD("blackbody", "kelvin"), &Star::blackbody);
}

Ref<Star> Star::from_mass(double p_mass, double p_age) {
	Ref<Star> star;
	star.instantiate();
	star->mass = p_mass;
	star->age = p_age;
	return star;
}

double Star::get_luminosity() const {
	if (mass < 0.43) {
		return 0.23 * std::pow(mass, 2.3);
	}
	if (mass < 2.0) {
		return std::pow(mass, 4.0);
	}
	return 1.4 * std::pow(mass, 3.5);
}

double Star::get_radius() const {
	return mass < 1.0 ? std::pow(mass, 0.8) : std::pow(mass, 0.57);
}

double Star::get_temperature() const {
	double r = get_radius();
	return SUN_TEMPERATURE * std::pow(get_luminosity() / (r * r), 0.25);
}

double Star::get_lifetime() const {
	return 10.0 * mass / get_luminosity();
}

// The inner and outer edge of the zone where water can be liquid, in AU (a rough single-planet estimate from the flux an Earth-like
// world would need: 1.1 and 0.53 of what Earth gets).
Vector2 Star::habitable_zone() const {
	double l = get_luminosity();
	return Vector2(std::sqrt(l / 1.1), std::sqrt(l / 0.53));
}

// The distance (AU) beyond which ice survives in the system's youth.
double Star::frost_line() const {
	return 2.7 * std::sqrt(get_luminosity());
}

// The distance (AU) inside which a planet is tidally locked to the star.
double Star::lock_distance() const {
	return 0.3 * std::pow(mass, 1.0 / 3.0);
}

// True if complex life has had the time to appear (the star's age against a few billion years).
bool Star::old_enough_for_life() const {
	return age >= 2.5 && age < get_lifetime();
}

String Star::get_spectral_class() const {
	double t = get_temperature();
	String letter = "M";
	if (t >= 30000.0) {
		letter = "O";
	} else if (t >= 10000.0) {
		letter = "B";
	} else if (t >= 7500.0) {
		letter = "A";
	} else if (t >= 6000.0) {
		letter = "F";
	} else if (t >= 5200.0) {
		letter = "G";
	} else if (t >= 3700.0) {
		letter = "K";
	}
	return letter;
}

double Star::get_flare_level() const {
	return CLAMP((0.6 - mass) / 0.5, 0.0, 1.0);
}

// The multiplier on the Sun's light that this star's light is: (1, 1, 1) for the Sun, orange for a red dwarf, bluer for an F or A star.
// The eye adapts to a colour it lives under, so only `ADAPTATION` of the difference is seen; `readability` (0 true .. 1 readable)
// blends to white.
Color Star::light_tint(double p_readability) const {
	Color sun = blackbody(SUN_TEMPERATURE);
	Color mine = get_colour();
	Vector3 ratio(mine.r / sun.r, mine.g / sun.g, mine.b / sun.b);
	double strongest = std::max((double)ratio.x, std::max((double)ratio.y, (double)ratio.z));
	Vector3 tint(std::pow(ratio.x / strongest, ADAPTATION), std::pow(ratio.y / strongest, ADAPTATION),
			std::pow(ratio.z / strongest, ADAPTATION));
	Color seen(tint.x, tint.y, tint.z);
	return seen.lerp(Color(1, 1, 1, 1), CLAMP(p_readability, 0.0, 1.0));
}

// Blackbody colour for a temperature (Tanner Helland's fit, good from 1000 K to 40000 K).
Color Star::blackbody(double p_kelvin) {
	double t = CLAMP(p_kelvin, 1000.0, 40000.0) / 100.0;
	double red = 255.0;
	if (t > 66.0) {
		red = 329.698727446 * std::pow(t - 60.0, -0.1332047592);
	}
	double green = 255.0;
	if (t <= 66.0) {
		green = 99.4708025861 * std::log(t) - 161.1195681661;
	} else {
		green = 288.1221695283 * std::pow(t - 60.0, -0.0755148492);
	}
	double blue = 255.0;
	if (t < 66.0) {
		blue = t <= 19.0 ? 0.0 : 138.5177312231 * std::log(t - 10.0) - 305.0447927307;
	}
	return Color(CLAMP(red, 0.0, 255.0) / 255.0, CLAMP(green, 0.0, 255.0) / 255.0, CLAMP(blue, 0.0, 255.0) / 255.0);
}

Color Star::get_colour() const {
	return blackbody(get_temperature());
}

// ---- StarLight ----

void StarLight::_bind_methods() {
	ClassDB::bind_static_method("StarLight", D_METHOD("coolness", "star"), &StarLight::coolness);
	ClassDB::bind_static_method("StarLight", D_METHOD("leaf_colour", "colour", "star", "readability"), &StarLight::leaf_colour, DEFVAL(0.0));
	ClassDB::bind_static_method("StarLight", D_METHOD("apply", "species", "star", "readability"), &StarLight::apply, DEFVAL(0.0));
}

// How far the star's colour is from the Sun's: +1 a red dwarf (cool), 0 the Sun, -1 a hot star.
double StarLight::coolness(const Ref<Star> &p_star) {
	double shift = Star::SUN_TEMPERATURE - p_star->get_temperature();
	return CLAMP(shift / (shift > 0.0 ? COOL : HOT), -1.0, 1.0);
}

// The leaf colour a plant of Earth-like green `colour` has under `star`.
Color StarLight::leaf_colour(const Color &p_colour, const Ref<Star> &p_star, double p_readability) {
	double k = coolness(p_star) * (1.0 - CLAMP(p_readability, 0.0, 1.0));
	if (UtilityFunctions::is_zero_approx(k)) {
		return p_colour;
	}
	double hue = p_colour.get_h();
	double saturation = p_colour.get_s();
	double value = p_colour.get_v();
	if (k > 0.0) { // cool star: toward dark purple and red
		hue = lerp_angle_d(hue * TAU_D, 0.82 * TAU_D, 0.6 * k) / TAU_D;
		saturation *= 1.0 - 0.2 * k;
		value *= 1.0 - 0.55 * k;
	} else { // hot star: paler, yellower, a little lighter
		hue = lerp_angle_d(hue * TAU_D, 0.17 * TAU_D, -0.5 * k) / TAU_D;
		saturation *= 1.0 + 0.25 * k;
		value = std::min(value * (1.0 - 0.15 * k), 1.0);
	}
	return Color::from_hsv(positive_mod_d(hue, 1.0), CLAMP(saturation, 0.0, 1.0), CLAMP(value, 0.0, 1.0), p_colour.a);
}

// Recolours the leaves (and their tips) of `species` for `star`.
void StarLight::apply(const Array &p_species, const Ref<Star> &p_star, double p_readability) {
	for (int i = 0; i < p_species.size(); i++) {
		Object *one = p_species[i];
		if (one == nullptr) {
			continue;
		}
		one->set("leaf", leaf_colour(one->get("leaf"), p_star, p_readability));
		one->set("leaf_tip", leaf_colour(one->get("leaf_tip"), p_star, p_readability));
	}
}

// ---- StarSystem ----

void StarSystem::_bind_methods() {
	BIND_ENUM_CONSTANT(ROCKY);
	BIND_ENUM_CONSTANT(LARGE_ROCKY);
	BIND_ENUM_CONSTANT(ICE_GIANT);
	BIND_ENUM_CONSTANT(GAS_GIANT);
	BIND_CONSTANT(MAX_PLANETS);
	NP_BIND(StarSystem, Variant::INT, system_seed)
	NP_BIND(StarSystem, Variant::VECTOR3, position)
	ClassDB::bind_method(D_METHOD("get_stars"), &StarSystem::get_stars);
	ClassDB::bind_method(D_METHOD("set_stars", "value"), &StarSystem::set_stars);
	ADD_PROPERTY(PropertyInfo(Variant::ARRAY, "stars", PROPERTY_HINT_ARRAY_TYPE, "Star"), "set_stars", "get_stars");
	ClassDB::bind_method(D_METHOD("get_planets"), &StarSystem::get_planets);
	ClassDB::bind_method(D_METHOD("set_planets", "value"), &StarSystem::set_planets);
	ADD_PROPERTY(PropertyInfo(Variant::ARRAY, "planets", PROPERTY_HINT_ARRAY_TYPE, "Dictionary"), "set_planets", "get_planets");
	ClassDB::bind_static_method("StarSystem", D_METHOD("generate", "seed_value", "sunlike_home"), &StarSystem::generate, DEFVAL(false));
	ClassDB::bind_static_method("StarSystem", D_METHOD("kind_name", "kind"), &StarSystem::kind_name);
}

// The system a seed makes. `sunlike_home` makes it a Sun-like star with a rocky planet in its habitable zone.
Ref<StarSystem> StarSystem::generate(int64_t p_seed_value, bool p_sunlike_home) {
	Ref<StarSystem> system;
	system.instantiate();
	system->system_seed = p_seed_value;
	Ref<RandomNumberGenerator> rng;
	rng.instantiate();
	rng->set_seed((uint64_t)p_seed_value);
	double star_mass = random_mass(rng);
	if (p_sunlike_home) {
		star_mass = rng->randf_range(0.9, 1.1);
	}
	Ref<Star> star = Star::from_mass(star_mass, rng->randf_range(2.5, 8.0));
	star->age = std::min(star->age, star->get_lifetime() * 0.9);
	system->stars.append(star);
	system->make_planets(rng, p_sunlike_home);
	return system;
}

// Stars are mostly small: a mass from a power law (many red dwarfs, a few bright ones).
double StarSystem::random_mass(const Ref<RandomNumberGenerator> &p_rng) {
	return CLAMP(0.1 * std::pow(1.0 - p_rng->randf() * 0.9, -0.9), 0.1, 3.0);
}

void StarSystem::make_planets(const Ref<RandomNumberGenerator> &p_rng, bool p_sunlike_home) {
	Ref<Star> star = stars[0];
	Vector2 zone = star->habitable_zone();
	int count = p_rng->randi_range(0, MAX_PLANETS);
	double distance = p_rng->randf_range(0.1, 0.4) * std::max(std::sqrt(star->get_luminosity()), 0.3);
	for (int index = 0; index < count; index++) {
		planets.append(planet_at(p_rng, star, distance, zone));
		distance *= p_rng->randf_range(1.4, 2.0);
	}
	if (p_sunlike_home && !has_habitable()) {
		double home_distance = p_rng->randf_range(zone.x * 1.05, zone.y * 0.9);
		Dictionary home = planet_at(p_rng, star, home_distance, zone);
		home["kind"] = ROCKY;
		home["radius_earth"] = p_rng->randf_range(0.8, 1.3);
		home["habitable"] = true;
		planets.append(home);
		std::vector<Dictionary> sorted;
		for (int i = 0; i < planets.size(); i++) {
			sorted.push_back(planets[i]);
		}
		std::stable_sort(sorted.begin(), sorted.end(), [](const Dictionary &a, const Dictionary &b) {
			return (double)a["orbit_au"] < (double)b["orbit_au"];
		});
		planets.clear();
		for (const Dictionary &one : sorted) {
			planets.append(one);
		}
	}
}

bool StarSystem::has_habitable() const {
	for (int i = 0; i < planets.size(); i++) {
		Dictionary planet = planets[i];
		if ((bool)planet["habitable"]) {
			return true;
		}
	}
	return false;
}

Dictionary StarSystem::planet_at(const Ref<RandomNumberGenerator> &p_rng, const Ref<Star> &p_star, double p_distance, const Vector2 &p_zone) const {
	int kind = ROCKY;
	double radius_earth = p_rng->randf_range(0.4, 1.5);
	if (p_distance > p_star->frost_line()) {
		double roll = p_rng->randf();
		kind = roll < 0.5 ? GAS_GIANT : ICE_GIANT;
		radius_earth = p_rng->randf_range(3.5, 11.0);
		if (roll >= 0.85) {
			kind = LARGE_ROCKY;
			radius_earth = p_rng->randf_range(1.5, 2.2);
		}
	} else if (p_rng->randf() < 0.25) {
		kind = LARGE_ROCKY;
		radius_earth = p_rng->randf_range(1.5, 2.2);
	}
	bool rocky = kind == ROCKY || kind == LARGE_ROCKY;
	Dictionary planet;
	planet["orbit_au"] = p_distance;
	planet["radius_earth"] = radius_earth;
	planet["kind"] = kind;
	planet["year_standard_days"] = 365.25 * std::sqrt(std::pow(p_distance, 3.0) / p_star->mass);
	planet["day_standard_hours"] = p_rng->randf_range(10.0, 40.0);
	planet["tilt_deg"] = p_rng->randf_range(0.0, 40.0);
	double ecc_range = p_rng->randf_range(0.0, 0.2);
	planet["eccentricity"] = ecc_range * p_rng->randf();
	planet["perihelion_share"] = p_rng->randf();
	planet["habitable"] = rocky && p_distance >= p_zone.x && p_distance <= p_zone.y;
	planet["locked"] = p_distance < p_star->lock_distance();
	return planet;
}

String StarSystem::kind_name(int64_t p_kind) {
	static const char *names[] = { "rocky", "large rocky", "ice giant", "gas giant" };
	return String(names[CLAMP(p_kind, (int64_t)0, (int64_t)3)]);
}
