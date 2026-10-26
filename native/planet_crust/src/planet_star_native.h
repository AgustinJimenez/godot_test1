#pragma once

// Star, StarLight and StarSystem (were systems/planet/star.gd, star_light.gd, star_system.gd): a star as a physical object (its mass sets the
// rest), what its light does to the colour of leaves, and one star system made from a seed. Pure data: nothing here touches a scene.

#include "native_props.h"

#include <godot_cpp/classes/random_number_generator.hpp>
#include <godot_cpp/classes/ref.hpp>
#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/classes/resource.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/typed_array.hpp>
#include <godot_cpp/variant/color.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/string.hpp>
#include <godot_cpp/variant/vector2.hpp>
#include <godot_cpp/variant/vector3.hpp>

namespace godot {

class Star : public Resource {
	GDCLASS(Star, Resource)

protected:
	static void _bind_methods();

public:
	static constexpr double SUN_TEMPERATURE = 5772.0; // K
	static constexpr double ADAPTATION = 0.75; // how much of a star's colour the eye still sees

	NP_FIELD(double, mass, 1.0) // solar masses
	NP_FIELD(double, age, 4.6) // billions of years

	static double get_sun_temperature() { return SUN_TEMPERATURE; }
	static double get_adaptation() { return ADAPTATION; }
	static Ref<Star> from_mass(double p_mass, double p_age = 4.6);
	double get_luminosity() const; // solar luminosities
	double get_radius() const; // solar radii
	double get_temperature() const; // K, the surface
	double get_lifetime() const; // billions of years on the main sequence
	Color get_colour() const; // the blackbody colour, as seen (sRGB, brightest channel 1)
	String get_spectral_class() const;
	double get_flare_level() const; // 0..1: how often and how hard it flares
	Vector2 habitable_zone() const;
	double frost_line() const;
	double lock_distance() const;
	bool old_enough_for_life() const;
	Color light_tint(double p_readability = 0.0) const;
	static Color blackbody(double p_kelvin);
};

class StarLight : public RefCounted {
	GDCLASS(StarLight, RefCounted)

protected:
	static void _bind_methods();

public:
	static constexpr double COOL = 2800.0; // K below the Sun at which the cool-star look is complete (a red dwarf)
	static constexpr double HOT = 2800.0; // K above the Sun for the hot-star look (an F or A star)

	static double coolness(const Ref<Star> &p_star);
	static Color leaf_colour(const Color &p_colour, const Ref<Star> &p_star, double p_readability = 0.0);
	// `species`: the plants (PlantSpecies, GDScript objects with `leaf` and `leaf_tip`)
	static void apply(const Array &p_species, const Ref<Star> &p_star, double p_readability = 0.0);
};

class StarSystem : public Resource {
	GDCLASS(StarSystem, Resource)

	void make_planets(const Ref<RandomNumberGenerator> &p_rng, bool p_sunlike_home);
	bool has_habitable() const;
	Dictionary planet_at(const Ref<RandomNumberGenerator> &p_rng, const Ref<Star> &p_star, double p_distance, const Vector2 &p_zone) const;
	static double random_mass(const Ref<RandomNumberGenerator> &p_rng);

protected:
	static void _bind_methods();

public:
	enum Kind { ROCKY, LARGE_ROCKY, ICE_GIANT, GAS_GIANT };
	static constexpr int MAX_PLANETS = 8;

	NP_FIELD(int64_t, system_seed, 0)
	NP_FIELD(Vector3, position, Vector3()) // light years, in the universe's region
	NP_FIELD(TypedArray<Ref<Star>>, stars, TypedArray<Ref<Star>>()) // Star each
	// One dictionary per planet, inner to outer: orbit_au, radius_earth, kind (Kind), year_standard_days, day_standard_hours, tilt_deg,
	// eccentricity, perihelion_share, habitable, locked
	NP_FIELD(TypedArray<Dictionary>, planets, TypedArray<Dictionary>())

	static Ref<StarSystem> generate(int64_t p_seed_value, bool p_sunlike_home = false);
	static String kind_name(int64_t p_kind);
};

} // namespace godot

VARIANT_ENUM_CAST(StarSystem::Kind);
