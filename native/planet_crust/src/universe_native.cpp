#include "universe_native.h"

#include "planet_clock_native.h"
#include "planet_map_native.h"
#include "planet_seasons_native.h"
#include "planet_sky_native.h"

#include <godot_cpp/classes/class_db_singleton.hpp>
#include <godot_cpp/classes/dir_access.hpp>
#include <godot_cpp/classes/file_access.hpp>
#include <godot_cpp/classes/json.hpp>
#include <godot_cpp/classes/time.hpp>
#include <godot_cpp/variant/utility_functions.hpp>

#include <algorithm>
#include <cmath>
#include <vector>

using namespace godot;

static const double TAU_D = 6.283185307179586476925286766559;
static const double PI_D = 3.14159265358979323846;

// ---- UniverseSave ----

void UniverseSave::_bind_methods() {
	BIND_CONSTANT(VERSION);
	ClassDB::bind_static_method("UniverseSave", D_METHOD("get_dir"), &UniverseSave::get_dir);
	ClassDB::bind_static_method("UniverseSave", D_METHOD("get_old_dir"), &UniverseSave::get_old_dir);
	ClassDB::bind_static_method("UniverseSave", D_METHOD("path_for", "save_name", "folder"), &UniverseSave::path_for, DEFVAL("user://universes"));
	ClassDB::bind_static_method("UniverseSave", D_METHOD("save", "planet", "save_name"), &UniverseSave::save);
	ClassDB::bind_static_method("UniverseSave", D_METHOD("load_data", "save_name"), &UniverseSave::load_data);
	ClassDB::bind_static_method("UniverseSave", D_METHOD("settings_from", "data"), &UniverseSave::settings_from);
	ClassDB::bind_static_method("UniverseSave", D_METHOD("list"), &UniverseSave::list);
	ClassDB::bind_static_method("UniverseSave", D_METHOD("latest"), &UniverseSave::latest);
	ClassDB::bind_static_method("UniverseSave", D_METHOD("delete", "save_name"), &UniverseSave::delete_save);
}

// The path of the save called `save_name` (anything but letters, digits, - and _ becomes _).
String UniverseSave::path_for(const String &p_save_name, const String &p_folder) {
	String clean;
	String stripped = p_save_name.strip_edges();
	for (int i = 0; i < stripped.length(); i++) {
		char32_t code = stripped[i];
		bool plain = (code >= 48 && code <= 57) || (code >= 65 && code <= 90) || (code >= 97 && code <= 122) || code == '-' || code == '_';
		clean += plain ? String::chr(code) : String("_");
	}
	return vformat("%s/%s.json", p_folder, clean != "" ? clean : String("universe"));
}

// The storable properties of the settings, as name -> value.
Dictionary UniverseSave::settings_to_dictionary(const Ref<PlanetSettings> &p_settings) {
	Dictionary stored;
	TypedArray<Dictionary> properties = ClassDBSingleton::get_singleton()->class_get_property_list("PlanetSettings", true);
	for (int i = 0; i < properties.size(); i++) {
		Dictionary property = properties[i];
		if ((int64_t)property["usage"] & PROPERTY_USAGE_STORAGE) {
			stored[property["name"]] = p_settings->get(property["name"]);
		}
	}
	return stored;
}

// Writes the universe `planet` belongs to as the save `save_name` (its planet and the moment on it; the other planets an existing save of that
// name has are kept). True if it was written.
bool UniverseSave::save(Object *p_planet, const String &p_save_name) {
	DirAccess::make_dir_recursive_absolute(get_dir());
	Dictionary kept = load_data(p_save_name);
	Array planets = kept.get("planets", Array());
	String planet_id = kept.get("current", String("planet_1"));
	Ref<PlanetSettings> settings = p_planet->get("settings");
	Dictionary entry;
	entry["id"] = planet_id;
	entry["settings"] = settings_to_dictionary(settings);
	bool replaced = false;
	for (int index = 0; index < planets.size(); index++) {
		Dictionary one = planets[index];
		if (one.get("id", String("")) == Variant(planet_id)) {
			planets[index] = entry;
			replaced = true;
		}
	}
	if (!replaced) {
		planets.append(entry);
	}
	Dictionary universe;
	universe["seed"] = settings->get_universe_seed();
	universe["systems"] = 1;
	universe["sunlike_home"] = settings->get_universe_sunlike();
	Dictionary data;
	data["version"] = VERSION;
	data["name"] = p_save_name.strip_edges();
	data["saved_at"] = (int64_t)Time::get_singleton()->get_unix_time_from_system();
	data["universe"] = universe;
	data["planets"] = planets;
	data["current"] = planet_id;
	data["state"] = p_planet->call("snapshot");
	Ref<FileAccess> file = FileAccess::open(path_for(p_save_name), FileAccess::WRITE);
	if (file.is_null()) {
		return false;
	}
	file->store_string(JSON::stringify(data, "\t"));
	return true;
}

// The contents of the save `save_name` ({} if there is none or it cannot be read). A first-version save (one planet) is brought to the universe layout.
Dictionary UniverseSave::load_data(const String &p_save_name) {
	Ref<FileAccess> file = FileAccess::open(path_for(p_save_name), FileAccess::READ);
	if (file.is_null()) {
		file = FileAccess::open(path_for(p_save_name, get_old_dir()), FileAccess::READ);
	}
	if (file.is_null()) {
		return Dictionary();
	}
	Variant parsed = JSON::parse_string(file->get_as_text());
	if (parsed.get_type() != Variant::DICTIONARY) {
		return Dictionary();
	}
	Dictionary data = parsed;
	if (!data.has("planets") && data.has("settings")) {
		Dictionary first;
		first["id"] = "planet_1";
		first["settings"] = data["settings"];
		Array planets;
		planets.append(first);
		data["planets"] = planets;
		data["current"] = "planet_1";
	}
	return data;
}

// The settings of the planet the player is on in a save (what that planet was made from).
Ref<PlanetSettings> UniverseSave::settings_from(const Dictionary &p_data) {
	Ref<PlanetSettings> settings;
	settings.instantiate();
	Dictionary stored;
	Array planets = p_data.get("planets", Array());
	for (int i = 0; i < planets.size(); i++) {
		Dictionary entry = planets[i];
		if (entry.get("id", String("")) == p_data.get("current", String("planet_1"))) {
			stored = entry.get("settings", Dictionary());
		}
	}
	TypedArray<Dictionary> properties = ClassDBSingleton::get_singleton()->class_get_property_list("PlanetSettings", true);
	for (int i = 0; i < properties.size(); i++) {
		Dictionary property = properties[i];
		String key = property["name"];
		if (!((int64_t)property["usage"] & PROPERTY_USAGE_STORAGE) || !stored.has(key)) {
			continue;
		}
		int type = (int)property["type"];
		if (type == Variant::INT) {
			settings->set(key, (int64_t)stored[key]);
		} else if (type == Variant::BOOL) {
			settings->set(key, (bool)stored[key]);
		} else {
			settings->set(key, (double)stored[key]);
		}
	}
	return settings;
}

// The saves there are, newest first: [{name, planets, seed, radius, saved_at}] (seed and radius are the ones of the planet the player is on).
TypedArray<Dictionary> UniverseSave::list() {
	std::vector<Dictionary> found;
	Dictionary seen;
	for (const String &folder : { get_dir(), get_old_dir() }) {
		PackedStringArray files = DirAccess::get_files_at(folder);
		for (int i = 0; i < files.size(); i++) {
			String file_name = files[i];
			String save_name = file_name.trim_suffix(".json");
			if (!file_name.ends_with(".json") || seen.has(save_name)) {
				continue;
			}
			Dictionary data = load_data(save_name);
			if (data.is_empty()) {
				continue;
			}
			seen[save_name] = true;
			Ref<PlanetSettings> settings = settings_from(data);
			Dictionary row;
			row["name"] = String(data.get("name", save_name));
			row["planets"] = Array(data.get("planets", Array())).size();
			row["seed"] = settings->get_world_seed();
			row["radius"] = settings->get_radius();
			row["saved_at"] = (int64_t)data.get("saved_at", 0);
			found.push_back(row);
		}
	}
	std::stable_sort(found.begin(), found.end(), [](const Dictionary &a, const Dictionary &b) { return (int64_t)a["saved_at"] > (int64_t)b["saved_at"]; });
	TypedArray<Dictionary> result;
	for (const Dictionary &row : found) {
		result.append(row);
	}
	return result;
}

// The name of the newest save ("" if there is none).
String UniverseSave::latest() {
	TypedArray<Dictionary> saves = list();
	if (saves.is_empty()) {
		return "";
	}
	Dictionary first = saves[0];
	return String(first["name"]);
}

// Removes the save `save_name`.
void UniverseSave::delete_save(const String &p_save_name) {
	DirAccess::remove_absolute(path_for(p_save_name));
	DirAccess::remove_absolute(path_for(p_save_name, get_old_dir()));
}

// ---- UniverseSettings ----

void UniverseSettings::_bind_methods() {
	NP_BIND(UniverseSettings, Variant::INT, universe_seed)
	NP_BIND(UniverseSettings, Variant::INT, system_count)
	NP_BIND(UniverseSettings, Variant::BOOL, sunlike_home)
	NP_BIND(UniverseSettings, Variant::FLOAT, region_size)
	ClassDB::bind_method(D_METHOD("system_seed", "index"), &UniverseSettings::system_seed);
	ClassDB::bind_method(D_METHOD("system", "index"), &UniverseSettings::system);
	ClassDB::bind_method(D_METHOD("planet_settings", "index", "number"), &UniverseSettings::planet_settings);
	ClassDB::bind_method(D_METHOD("home_settings", "readability"), &UniverseSettings::home_settings, DEFVAL(0.0));
	ClassDB::bind_method(D_METHOD("table", "count"), &UniverseSettings::table);
	ClassDB::bind_method(D_METHOD("self_check"), &UniverseSettings::self_check);
}

// The seed of system `index`: a mix of the universe seed and the number.
int64_t UniverseSettings::system_seed(int64_t p_index) const {
	Array both;
	both.append(universe_seed);
	both.append(p_index);
	return (int64_t)UtilityFunctions::hash(both);
}

// System `index` (0-based). Only the first one is made Sun-like when `sunlike_home` is set.
Ref<StarSystem> UniverseSettings::system(int64_t p_index) const {
	Ref<StarSystem> made = StarSystem::generate(system_seed(p_index), sunlike_home && p_index == 0);
	Ref<RandomNumberGenerator> rng;
	rng.instantiate();
	rng->set_seed((uint64_t)(system_seed(p_index) ^ 0x5eed));
	if (p_index == 0) {
		made->set_position(Vector3());
	} else {
		double x = rng->randf_range(-1.0, 1.0);
		double y = rng->randf_range(-0.3, 0.3);
		double z = rng->randf_range(-1.0, 1.0);
		made->set_position(Vector3(x, y, z) * region_size * 0.5);
	}
	return made;
}

// The settings of planet `number` (0-based) of system `index`, from the star and the orbit: the same ids always give the same planet. Game scale:
// Earth is 20,000 m; the year is the true one in local days, clamped to 6..64.
Ref<PlanetSettings> UniverseSettings::planet_settings(int64_t p_index, int64_t p_number) const {
	Ref<PlanetSettings> made;
	made.instantiate();
	Ref<StarSystem> system_data = system(p_index);
	Dictionary body = system_data->get_planets()[p_number];
	Ref<RandomNumberGenerator> rng;
	rng.instantiate();
	Array both;
	both.append(system_data->get_system_seed());
	both.append(p_number);
	rng->set_seed((uint64_t)(int64_t)UtilityFunctions::hash(both));
	made->set_world_seed((int64_t)(rng->randi() & 0x7fffffff));
	made->set_radius(20000.0 * CLAMP((double)body["radius_earth"], 0.4, 2.2));
	double day_hours = body["day_standard_hours"];
	made->set_day_seconds(day_hours * 60.0);
	made->set_year_days(CLAMP((double)body["year_standard_days"] * 24.0 / day_hours, 6.0, 64.0));
	made->set_axial_tilt(body["tilt_deg"]);
	made->set_eccentricity(body["eccentricity"]);
	made->set_perihelion_share(body["perihelion_share"]);
	made->set_universe_seed(universe_seed);
	made->set_universe_system(p_index);
	made->set_universe_planet(p_number);
	made->set_universe_sunlike(sunlike_home ? 1 : 0);
	Ref<Star> star = system_data->get_stars()[0];
	made->set_star_mass(star->get_mass());
	made->set_insolation(star->get_luminosity() / ((double)body["orbit_au"] * (double)body["orbit_au"]));
	if ((bool)body["habitable"]) {
		made->set_ocean_fraction(rng->randf_range(0.55, 0.8));
	} else {
		made->set_ocean_fraction(rng->randf_range(0.0, 0.3));
	}
	return made;
}

// The planet the player starts on: the first habitable planet of system 0, else its first rocky one. A system without any is made Sun-like instead,
// so there is always a home. `readability` is the start menu's star colour setting (0 true .. 1 readable).
Ref<PlanetSettings> UniverseSettings::home_settings(double p_readability) const {
	Ref<StarSystem> first = system(0);
	int64_t number = home_number(first);
	if (number < 0) {
		Ref<UniverseSettings> fixed;
		fixed.instantiate();
		fixed->universe_seed = universe_seed;
		fixed->sunlike_home = true;
		Ref<PlanetSettings> made = fixed->planet_settings(0, fixed->home_number(fixed->system(0)));
		made->set_star_readability(p_readability);
		made->set_universe_sunlike(1);
		return made;
	}
	Ref<PlanetSettings> home = planet_settings(0, number);
	home->set_star_readability(p_readability);
	return home;
}

int64_t UniverseSettings::home_number(const Ref<StarSystem> &p_system) const {
	int64_t rocky = -1;
	Array planets = p_system->get_planets();
	for (int64_t number = 0; number < planets.size(); number++) {
		Dictionary planet = planets[number];
		if ((bool)planet["habitable"]) {
			return number;
		}
		if (rocky < 0 && (int64_t)planet["kind"] <= StarSystem::LARGE_ROCKY) {
			rocky = number;
		}
	}
	return rocky;
}

// A text table of the first `count` systems, one line per planet, for the lab (`--universe=SEED`).
PackedStringArray UniverseSettings::table(int64_t p_count) const {
	PackedStringArray lines;
	for (int64_t index = 0; index < p_count; index++) {
		Ref<StarSystem> system_data = system(index);
		Ref<Star> star = system_data->get_stars()[0];
		Vector2 zone = star->habitable_zone();
		lines.append(vformat("SYSTEM %d seed=%d class=%s mass=%.2f L=%.3f T=%.0fK colour=%s life=%.1fGyr ", index, system_data->get_system_seed(), star->get_spectral_class(),
							 star->get_mass(), star->get_luminosity(), star->get_temperature(), star->get_colour().to_html(false), star->get_lifetime()) +
				vformat("HZ=%.2f-%.2fAU planets=%d", zone.x, zone.y, system_data->get_planets().size()));
		Array planets = system_data->get_planets();
		for (int64_t number = 0; number < planets.size(); number++) {
			Dictionary planet = planets[number];
			String notes = (bool)planet["habitable"] ? " HABITABLE" : "";
			notes += (bool)planet["locked"] ? " LOCKED" : "";
			lines.append(vformat("  planet %d %-11s a=%.2fAU r=%.1fEarth year=%.0fd day=%.0fh tilt=%.0f%s", number + 1, StarSystem::kind_name(planet["kind"]), planet["orbit_au"],
					planet["radius_earth"], planet["year_standard_days"], planet["day_standard_hours"], planet["tilt_deg"], notes));
		}
	}
	return lines;
}

// The tide's range (m) at the equator over one day: the highest minus the lowest height.
double UniverseSettings::tide_range(const Ref<PlanetClock> &p_clock) {
	double high = -INFINITY;
	double low = INFINITY;
	double start = p_clock->get_time();
	for (int step = 0; step < 48; step++) {
		p_clock->set_time(start + p_clock->get_day_seconds() * step / 48.0);
		double value = PlanetTides::height(p_clock, Vector3(1, 0, 0));
		high = std::max(high, value);
		low = std::min(low, value);
	}
	p_clock->set_time(start);
	return high - low;
}

// Eclipses from the geometry: with the moon's orbit flat they happen at new moon (the star's light covered) and full moon (the moon in the planet's
// shadow), not at the quarters, and a tilted orbit away from the nodes has none.
bool UniverseSettings::eclipse_check() {
	Ref<PlanetClock> clock;
	clock.instantiate();
	clock->set_moon_tilt(0.0);
	clock->set_year_share(0.0);
	double month = clock->get_day_seconds() * clock->get_month_days();
	double best_new = 0.0;
	double best_full = 0.0;
	double quarter = 0.0;
	for (int step = 0; step < 4000; step++) {
		clock->set_time(month * step / 4000.0);
		Vector3 sub = PlanetMoon::in_body(clock);
		double phase = PlanetMoon::lit(clock);
		if (phase < 0.0001) {
			best_new = std::max(best_new, PlanetMoon::solar_cover(clock, sub));
		} else if (phase > 0.9999) {
			best_full = std::max(best_full, PlanetMoon::lunar_depth(clock));
		} else if (std::abs(phase - 0.5) < 0.1) {
			quarter = std::max(quarter, PlanetMoon::solar_cover(clock, sub));
			quarter = std::max(quarter, PlanetMoon::lunar_depth(clock));
		}
	}
	clock->set_moon_tilt(Math::deg_to_rad(5.1));
	clock->set_year_share(0.25); // the nodes are at the equinoxes: no eclipse at the solstice
	double tilted = 0.0;
	for (int step = 0; step < 4000; step++) {
		clock->set_time(month * step / 4000.0);
		tilted = std::max(tilted, PlanetMoon::lunar_depth(clock));
		tilted = std::max(tilted, PlanetMoon::solar_cover(clock, PlanetMoon::in_body(clock)));
	}
	UtilityFunctions::print(vformat("ECLIPSES new=%.2f full=%.2f quarter=%.2f tilted=%.2f", best_new, best_full, quarter, tilted));
	return best_new > 0.5 && best_full > 0.5 && quarter == 0.0 && tilted == 0.0;
}

// Pass/fail for the lab (`UNIVERSE_CHECK`): the same ids give the same planet twice, the Sun-like start has a G or K star with a habitable planet,
// and every derived planet is playable.
bool UniverseSettings::self_check() const {
	bool ok = true;
	Ref<StarSystem> first = system(0);
	Array first_planets = first->get_planets();
	if (sunlike_home) {
		Ref<Star> star = first->get_stars()[0];
		String letter = star->get_spectral_class();
		bool any = false;
		for (int i = 0; i < first_planets.size(); i++) {
			Dictionary planet = first_planets[i];
			any = any || (bool)planet["habitable"];
		}
		ok = ok && (letter == "G" || letter == "K") && any;
	}
	for (int64_t number = 0; number < first_planets.size(); number++) {
		Ref<PlanetSettings> a = planet_settings(0, number);
		Ref<PlanetSettings> b = planet_settings(0, number);
		ok = ok && a->get_world_seed() == b->get_world_seed() && a->get_radius() == b->get_radius();
		ok = ok && a->get_year_days() == b->get_year_days() && a->get_radius() >= 8000.0 && a->get_day_seconds() > 0.0;
	}
	Ref<PlanetClock> orbit; // an ellipse: nearest at perihelion, farthest half a year later
	orbit.instantiate();
	orbit->set_eccentricity(0.2);
	orbit->set_perihelion_share(0.25);
	orbit->set_year_share(0.25);
	ok = ok && std::abs(orbit->distance() - 0.8) < 0.001;
	orbit->set_year_share(0.75);
	ok = ok && std::abs(orbit->distance() - 1.2) < 0.001 && orbit->light_now() < 1.0;
	Color green(0.26f, 0.5f, 0.18f); // leaves: the Sun's are unchanged, a red dwarf's darker
	ok = ok && StarLight::leaf_colour(green, Star::from_mass(1.0)) == green;
	ok = ok && StarLight::leaf_colour(green, Star::from_mass(0.15)).get_v() < green.get_v() * 0.7;
	ok = ok && StarLight::leaf_colour(green, Star::from_mass(0.15), 1.0) == green;
	Ref<PlanetClock> tide; // spring tides at new moon (aligned), neap at the first quarter
	tide.instantiate();
	tide->set_moon_tilt(0.0);
	tide->set_year_share(0.0);
	double spring = tide_range(tide);
	tide->set_time(tide->get_day_seconds() * tide->get_month_days() * 0.25);
	ok = ok && spring > tide_range(tide) * 1.2 && spring > 0.0;
	ok = ok && eclipse_check();
	ok = ok && Star::from_mass(0.2)->lock_distance() > Star::from_mass(0.2)->habitable_zone().y;
	ok = ok && Star::from_mass(1.0)->lock_distance() < Star::from_mass(1.0)->habitable_zone().x;
	ok = ok && system(3)->get_system_seed() == system(3)->get_system_seed() && system_seed(1) != system_seed(2);
	return ok;
}

// ---- PlanetMapLabels ----

void PlanetMapLabels::_bind_methods() {
	BIND_CONSTANT(WIDTH);
	BIND_CONSTANT(HEIGHT);
	NP_BIND(PlanetMapLabels, Variant::ARRAY, items)
	ClassDB::bind_method(D_METHOD("build", "noise"), &PlanetMapLabels::build);
	ClassDB::bind_static_method("PlanetMapLabels", D_METHOD("spaced", "text"), &PlanetMapLabels::spaced);
}

// Finds the bodies of sea and land and names them.
void PlanetMapLabels::build(const Ref<PlanetNoise> &p_noise) {
	items.clear();
	Ref<PlanetSeasonsNative> grid;
	grid.instantiate();
	PackedVector3Array dirs = grid->grid_dirs(WIDTH, HEIGHT);
	PackedFloat32Array heights = p_noise->macro_heights_of(dirs);
	Ref<RandomNumberGenerator> rng;
	rng.instantiate();
	rng->set_seed((uint64_t)(p_noise->get_settings()->get_world_seed() + 77));
	Ref<PlanetMapNative> finder;
	finder.instantiate();
	Array regions = finder->call("regions", heights, WIDTH, HEIGHT, 150.0, 6);
	for (int i = 0; i < regions.size(); i++) {
		Dictionary body = regions[i];
		String name_text = make_name(rng);
		if ((bool)body["sea"]) {
			name_text += (double)body["area"] > 2500.0 ? " OCEAN" : " SEA";
		}
		Dictionary item;
		item["uv"] = body["uv"];
		item["text"] = name_text.to_upper();
		item["sea"] = body["sea"];
		item["area"] = body["area"];
		items.append(item);
	}
}

String PlanetMapLabels::make_name(const Ref<RandomNumberGenerator> &p_rng) {
	static const char *syllables[] = { "ar", "al", "an", "ba", "bor", "cal", "dan", "el", "fen", "gar", "hal", "is", "ka", "lor", "mar", "nor", "or", "pan", "quel", "ros", "sa", "tar", "ul", "ver", "wen", "xan", "yor", "zel" };
	String text;
	int parts = p_rng->randi_range(2, 3);
	for (int part = 0; part < parts; part++) {
		text += String(syllables[p_rng->randi() % 28]);
	}
	return text.capitalize();
}

// `text` with a space between the letters (as the map writes a name).
String PlanetMapLabels::spaced(const String &p_text) {
	String out;
	for (int index = 0; index < p_text.length(); index++) {
		out += String::chr(p_text[index]) + (p_text[index] != ' ' ? String(" ") : String(""));
	}
	return out;
}
