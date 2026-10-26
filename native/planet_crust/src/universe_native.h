#pragma once

// UniverseSave, UniverseSettings and PlanetMapLabels (were systems/planet/universe_save.gd, universe_settings.gd and planet_map_labels.gd).
// Saved universes (a JSON file in user://universes/ with each planet's settings, the planet the player is on and the moment on it); the universe's
// seed and how many star systems it has (system N always comes from the seed and N); and the names of the seas and the lands of a planet for the map.

#include "native_props.h"
#include "planet_noise_native.h"
#include "planet_settings_native.h"
#include "planet_star_native.h"

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/classes/resource.hpp>
#include <godot_cpp/classes/random_number_generator.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/packed_string_array.hpp>
#include <godot_cpp/variant/typed_array.hpp>

namespace godot {

class PlanetWorld;

class UniverseSave : public RefCounted {
	GDCLASS(UniverseSave, RefCounted)

	static Dictionary settings_to_dictionary(const Ref<PlanetSettings> &p_settings);

protected:
	static void _bind_methods();

public:
	static constexpr int VERSION = 3; // 3 adds the universe block (2: planets only; both are read)

	static String get_dir() { return "user://universes"; }
	static String get_old_dir() { return "user://planets"; } // the first saves (one planet, no universe): still read
	static String path_for(const String &p_save_name, const String &p_folder = "user://universes");
	static bool save(Object *p_planet, const String &p_save_name);
	static Dictionary load_data(const String &p_save_name);
	static Ref<PlanetSettings> settings_from(const Dictionary &p_data);
	static TypedArray<Dictionary> list();
	static String latest();
	static void delete_save(const String &p_save_name);
};

class UniverseSettings : public Resource {
	GDCLASS(UniverseSettings, Resource)

	int64_t home_number(const Ref<StarSystem> &p_system) const;
	static double tide_range(const Ref<PlanetClock> &p_clock);
	static bool eclipse_check();

protected:
	static void _bind_methods();

public:
	NP_FIELD(int64_t, universe_seed, 1337)
	NP_FIELD(int64_t, system_count, 1) // starts at one star system (more come with travel)
	NP_FIELD(bool, sunlike_home, true) // the first system is a Sun-like star with a habitable planet
	NP_FIELD(double, region_size, 60.0) // light years across the volume the systems sit in

	int64_t system_seed(int64_t p_index) const;
	Ref<StarSystem> system(int64_t p_index) const;
	Ref<PlanetSettings> planet_settings(int64_t p_index, int64_t p_number) const;
	Ref<PlanetSettings> home_settings(double p_readability = 0.0) const;
	PackedStringArray table(int64_t p_count) const;
	bool self_check() const;
};

class PlanetMapLabels : public RefCounted {
	GDCLASS(PlanetMapLabels, RefCounted)

	static String make_name(const Ref<RandomNumberGenerator> &p_rng);

protected:
	static void _bind_methods();

public:
	static constexpr int WIDTH = 192;
	static constexpr int HEIGHT = 96;

	NP_FIELD(Array, items, Array()) // {uv, text, sea, area} of each name

	void build(const Ref<PlanetNoise> &p_noise);
	static String spaced(const String &p_text);
};

} // namespace godot
