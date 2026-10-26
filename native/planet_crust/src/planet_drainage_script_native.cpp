#include "planet_drainage_script_native.h"

#include "planet_climate_native.h"

#include <godot_cpp/classes/class_db_singleton.hpp>
#include <godot_cpp/classes/dir_access.hpp>
#include <godot_cpp/classes/file_access.hpp>
#include <godot_cpp/variant/utility_functions.hpp>

#include <algorithm>
#include <cmath>
#include <vector>

using namespace godot;

static const double PI_D = 3.14159265358979323846;

static double smooth_step(double p_from, double p_to, double p_x) {
	if (p_from == p_to) {
		return p_x < p_from ? 0.0 : 1.0;
	}
	double s = CLAMP((p_x - p_from) / (p_to - p_from), 0.0, 1.0);
	return s * s * (3.0 - 2.0 * s);
}

// ---- PlanetDrainage ----

void PlanetDrainage::_bind_methods() {
	NP_BIND(PlanetDrainage, Variant::INT, cells)
	NP_BIND(PlanetDrainage, Variant::PACKED_VECTOR3_ARRAY, dirs)
	NP_BIND(PlanetDrainage, Variant::PACKED_FLOAT32_ARRAY, heights)
	NP_BIND(PlanetDrainage, Variant::PACKED_FLOAT32_ARRAY, rain)
	NP_BIND(PlanetDrainage, Variant::PACKED_FLOAT32_ARRAY, filled)
	NP_BIND(PlanetDrainage, Variant::PACKED_FLOAT32_ARRAY, flow)
	NP_BIND(PlanetDrainage, Variant::PACKED_INT32_ARRAY, receiver)
	NP_BIND(PlanetDrainage, Variant::PACKED_BYTE_ARRAY, lake)
	NP_BIND(PlanetDrainage, Variant::PACKED_FLOAT32_ARRAY, uplift)
	NP_BIND(PlanetDrainage, Variant::INT, land_cells)
	ClassDB::bind_method(D_METHOD("build", "noise", "cells_per_edge", "exponent"), &PlanetDrainage::build, DEFVAL(4.0));
	ClassDB::bind_method(D_METHOD("river_threshold", "share"), &PlanetDrainage::river_threshold);
	ClassDB::bind_method(D_METHOD("network"), &PlanetDrainage::network);
	ClassDB::bind_method(D_METHOD("cell_of", "dir"), &PlanetDrainage::cell_of);
	ClassDB::bind_method(D_METHOD("cells_of", "many"), &PlanetDrainage::cells_of);
	ClassDB::bind_method(D_METHOD("areas"), &PlanetDrainage::areas);
	ClassDB::bind_method(D_METHOD("picture", "view", "threshold"), &PlanetDrainage::picture);
}

// Solves the drainage of the planet on `cells_per_edge` cells an edge. `exponent`: how much the steepest way is favoured (1 spreads the water
// over every way down, 4 and up gathers it).
bool PlanetDrainage::build(Object *p_noise, int64_t p_cells_per_edge, double p_exponent) {
	Object *crust = p_noise->get("native");
	if (crust == nullptr) {
		return false;
	}
	Ref<PlanetSettings> settings = p_noise->get("settings");
	Ref<PlanetClimate> climate = p_noise->get("climate");
	double relief = p_noise->get("relief");
	cells = p_cells_per_edge;
	native_.instantiate();
	native_->setup((int)cells, settings->get_radius(), p_noise->call("_cube_faces"));
	dirs = native_->cell_dirs();
	Dictionary both = crust->call("macro_and_tectonic_heights", dirs);
	heights = both["macro"];
	uplift = both["uplift"];
	rain = native_->sample_grid(climate->rain_grid(), PlanetClimate::WIDTH, PlanetClimate::HEIGHT, dirs);
	double lake_depth = std::max(relief * 0.015, 6.0); // a hollow this deep is a lake
	Dictionary solved = native_->solve(heights, rain, 0.0, p_exponent, lake_depth, std::max((int)(cells / 16), 4));
	filled = solved["filled"];
	flow = solved["flow"];
	receiver = solved["receiver"];
	lake = solved["lake"];
	land_cells = solved["land"];
	return true;
}

// The flow above which a land cell counts as a river: the `share` of land cells with the most.
double PlanetDrainage::river_threshold(double p_share) const {
	PackedFloat32Array land_flows;
	for (int index = 0; index < flow.size(); index++) {
		if (heights[index] >= 0.0f) {
			land_flows.append(flow[index]);
		}
	}
	land_flows.sort();
	if (land_flows.is_empty()) {
		return INFINITY;
	}
	int at = CLAMP((int)((double)land_flows.size() * (1.0 - p_share)), 0, (int)land_flows.size() - 1);
	return land_flows[at];
}

// The rivers as curves for the crust to cut its valleys along (see PlanetCrustNative.set_rivers).
Dictionary PlanetDrainage::network() const {
	double river = river_threshold(0.06);
	Dictionary made = native_->river_network(heights, filled, flow, receiver, river, 0.006, 10, 0.06, uplift);
	PackedFloat32Array levels; // the water level of every lake cell (-1e9: no lake)
	levels.resize(lake.size());
	for (int id = 0; id < lake.size(); id++) {
		levels[id] = lake[id] == 1 ? filled[id] : -1.0e9f;
	}
	made["lake_level"] = levels;
	return made;
}

// The cell that holds the unit direction `dir`.
int64_t PlanetDrainage::cell_of(const Vector3 &p_dir) const {
	return native_->cell_of(p_dir);
}

// The cells that hold many directions at once.
PackedInt32Array PlanetDrainage::cells_of(const PackedVector3Array &p_many) const {
	return native_->cells_of(p_many);
}

// Each cell's share of the sphere (1 on average).
PackedFloat32Array PlanetDrainage::areas() const {
	return native_->cell_areas();
}

// A flat map of the drainage: the sea blue by depth, the land by height, the lakes cyan and the rivers drawn bluer the more water they carry.
Ref<Image> PlanetDrainage::picture(const PackedFloat64Array &p_view, double p_threshold) const {
	const int width = 1024;
	const int height = 512;
	PackedVector3Array directions;
	double span = p_view[2];
	for (int row = 0; row < height; row++) {
		double lat = Math::deg_to_rad(p_view[1] + (0.5 - ((double)row + 0.5) / (double)height) * span * 0.5);
		for (int column = 0; column < width; column++) {
			double lon = Math::deg_to_rad(p_view[0] + (((double)column + 0.5) / (double)width - 0.5) * span);
			directions.append(Vector3(std::cos(lat) * std::cos(lon), std::sin(lat), std::cos(lat) * std::sin(lon)));
		}
	}
	PackedInt32Array found = cells_of(directions);
	PackedByteArray pixels;
	pixels.resize((int64_t)width * height * 3);
	for (int index = 0; index < directions.size(); index++) {
		int cell = found[index];
		double ground = heights[cell];
		Color colour;
		if (ground < 0.0) {
			double deep = CLAMP(1.0 + ground / 5000.0, 0.0, 1.0);
			colour = Color(0.02f, 0.1f, 0.3f).lerp(Color(0.2f, 0.45f, 0.7f), (float)deep);
		} else {
			double up = CLAMP(ground / 5000.0, 0.0, 1.0);
			colour = Color(0.28f, 0.45f, 0.22f).lerp(Color(0.6f, 0.5f, 0.35f), (float)smooth_step(0.0, 0.5, up));
			colour = colour.lerp(Color(0.95f, 0.95f, 0.95f), (float)smooth_step(0.5, 1.0, up));
			if (lake[cell] == 1) {
				colour = Color(0.2f, 0.7f, 0.85f);
			}
			double carried = flow[cell];
			if (carried >= p_threshold) {
				double strength = CLAMP(std::log(carried / p_threshold) / std::log(400.0), 0.0, 1.0);
				colour = colour.lerp(Color(0.1f, 0.3f, 1.0f), (float)(0.45 + 0.55 * strength));
			}
		}
		// (Image.set_pixel on an RGB8 image: each channel is truncated from 0..255)
		pixels[index * 3 + 0] = (uint8_t)CLAMP(colour.r * 255.0f, 0.0f, 255.0f);
		pixels[index * 3 + 1] = (uint8_t)CLAMP(colour.g * 255.0f, 0.0f, 255.0f);
		pixels[index * 3 + 2] = (uint8_t)CLAMP(colour.b * 255.0f, 0.0f, 255.0f);
	}
	return Image::create_from_data(width, height, false, Image::FORMAT_RGB8, pixels);
}

// ---- PlanetDrainageCache ----

void PlanetDrainageCache::_bind_methods() {
	ClassDB::bind_static_method("PlanetDrainageCache", D_METHOD("load_network", "settings"), &PlanetDrainageCache::load_network);
	ClassDB::bind_static_method("PlanetDrainageCache", D_METHOD("save_network", "settings", "network"), &PlanetDrainageCache::save_network);
}

// One file per world: `user://drainage_cache/<key>.bin`, the key a hash of the settings, of VERSION and of the modification time of the native
// library (a rebuilt crust makes a new key: an old file is never read for new code). RAISE `VERSION` when the drainage or the climate changes
// in a way that time would not show (an exported game has no times).
String PlanetDrainageCache::path_for(const Ref<PlanetSettings> &p_settings) {
	Dictionary stored;
	TypedArray<Dictionary> properties = ClassDBSingleton::get_singleton()->class_get_property_list("PlanetSettings", true);
	for (int i = 0; i < properties.size(); i++) {
		Dictionary property = properties[i];
		if ((int64_t)property["usage"] & PROPERTY_USAGE_STORAGE) {
			stored[property["name"]] = p_settings->get(property["name"]);
		}
	}
	int64_t stamp = 0;
	PackedStringArray files = DirAccess::get_files_at("res://native/planet_crust/bin");
	for (int i = 0; i < files.size(); i++) {
		String extension = files[i].get_extension();
		if (extension == "dll" || extension == "so" || extension == "dylib") {
			stamp = std::max(stamp, (int64_t)FileAccess::get_modified_time("res://native/planet_crust/bin/" + files[i]));
		}
	}
	String key = (UtilityFunctions::var_to_str(stored) + vformat("|drain%d|%d", (int)VERSION, stamp)).md5_text().substr(0, 16);
	return vformat("user://drainage_cache/%s.bin", key);
}

// The river network (what `PlanetCrustNative.set_rivers` takes) kept for these settings, or an empty dictionary.
Dictionary PlanetDrainageCache::load_network(const Ref<PlanetSettings> &p_settings) {
	String path = path_for(p_settings);
	if (!FileAccess::file_exists(path)) {
		return Dictionary();
	}
	Ref<FileAccess> file = FileAccess::open_compressed(path, FileAccess::READ, FileAccess::COMPRESSION_ZSTD);
	if (file.is_null()) {
		return Dictionary();
	}
	Variant network = file->get_var();
	if (network.get_type() != Variant::DICTIONARY || !Dictionary(network).has("cell_start")) {
		return Dictionary();
	}
	return network;
}

void PlanetDrainageCache::save_network(const Ref<PlanetSettings> &p_settings, const Dictionary &p_network) {
	DirAccess::make_dir_recursive_absolute("user://drainage_cache");
	String path = path_for(p_settings);
	Ref<FileAccess> file = FileAccess::open_compressed(path, FileAccess::WRITE, FileAccess::COMPRESSION_ZSTD);
	if (file.is_null()) {
		return;
	}
	file->store_var(p_network);
	file->close();
	trim();
}

void PlanetDrainageCache::trim() {
	PackedStringArray listed = DirAccess::get_files_at("user://drainage_cache");
	std::vector<String> files;
	for (int i = 0; i < listed.size(); i++) {
		files.push_back(listed[i]);
	}
	if ((int)files.size() <= MAX_FILES) {
		return;
	}
	std::sort(files.begin(), files.end(), [](const String &a, const String &b) {
		return FileAccess::get_modified_time("user://drainage_cache/" + a) < FileAccess::get_modified_time("user://drainage_cache/" + b);
	});
	for (int index = 0; index < (int)files.size() - MAX_FILES; index++) {
		DirAccess::remove_absolute("user://drainage_cache/" + files[index]);
	}
}
