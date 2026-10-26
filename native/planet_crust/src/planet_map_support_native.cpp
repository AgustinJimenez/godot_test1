#include "planet_map_support_native.h"

#include "planet_log_native.h"
#include "planet_world_native.h"

#include <godot_cpp/classes/button.hpp>
#include <godot_cpp/classes/class_db_singleton.hpp>
#include <godot_cpp/classes/dir_access.hpp>
#include <godot_cpp/classes/file_access.hpp>
#include <godot_cpp/classes/font.hpp>
#include <godot_cpp/classes/image.hpp>
#include <godot_cpp/classes/input.hpp>
#include <godot_cpp/classes/theme_db.hpp>
#include <godot_cpp/classes/time.hpp>
#include <godot_cpp/variant/utility_functions.hpp>

#include <algorithm>
#include <cmath>
#include <map>

using namespace godot;

static const double TAU_D = 6.283185307179586476925286766559;
static const double PI_D = 3.14159265358979323846;

static double positive_mod_d(double p_x, double p_y) {
	double value = std::fmod(p_x, p_y);
	if ((value < 0.0 && p_y > 0.0) || (value > 0.0 && p_y < 0.0)) {
		value += p_y;
	}
	return value;
}

static int positive_mod_i(int p_x, int p_y) {
	int value = p_x % p_y;
	if (value < 0) {
		value += p_y;
	}
	return value;
}

// ---- PlanetMapCache ----

static const char *CACHE_ROOT = "user://map_cache";

void PlanetMapCache::_bind_methods() {
	BIND_CONSTANT(VERSION);
	BIND_CONSTANT(MAX_TILES);
	ClassDB::bind_static_method("PlanetMapCache", D_METHOD("create", "settings"), &PlanetMapCache::create);
	ClassDB::bind_method(D_METHOD("directory"), &PlanetMapCache::directory);
	ClassDB::bind_static_method("PlanetMapCache", D_METHOD("keeps", "layer"), &PlanetMapCache::keeps);
	ClassDB::bind_method(D_METHOD("save_whole", "layer", "across", "texture"), &PlanetMapCache::save_whole);
	ClassDB::bind_method(D_METHOD("load_whole", "layer", "across"), &PlanetMapCache::load_whole);
	ClassDB::bind_method(D_METHOD("save_tile", "key", "texture"), &PlanetMapCache::save_tile);
	ClassDB::bind_method(D_METHOD("load_tile", "key"), &PlanetMapCache::load_tile);
	ClassDB::bind_method(D_METHOD("forget_area", "area"), &PlanetMapCache::forget_area);
	ClassDB::bind_method(D_METHOD("forget_whole"), &PlanetMapCache::forget_whole);
}

// Opens the folder of the world with these settings.
Ref<PlanetMapCache> PlanetMapCache::create(const Ref<PlanetSettings> &p_settings) {
	Ref<PlanetMapCache> made;
	made.instantiate();
	Dictionary stored;
	TypedArray<Dictionary> properties = ClassDBSingleton::get_singleton()->class_get_property_list("PlanetSettings", true);
	for (int i = 0; i < properties.size(); i++) {
		Dictionary property = properties[i];
		if ((int64_t)property["usage"] & PROPERTY_USAGE_STORAGE) {
			stored[property["name"]] = p_settings->get(property["name"]);
		}
	}
	String key = (UtilityFunctions::var_to_str(stored) + vformat("|map%d", (int)VERSION)).md5_text().substr(0, 16);
	made->dir = vformat("%s/%s", CACHE_ROOT, key);
	DirAccess::make_dir_recursive_absolute(made->dir);
	DirAccess::make_dir_recursive_absolute(made->dir + "/tiles");
	made->touch();
	made->tile_files = (int)DirAccess::get_files_at(made->dir + "/tiles").size();
	made->trim_worlds();
	return made;
}

// Whether a layer is kept on disk (the ones that follow the clock are not).
bool PlanetMapCache::keeps(int64_t p_layer) {
	return p_layer != PlanetChart::TEMPERATURE && p_layer != PlanetChart::CLOUDS && p_layer != PlanetChart::SATELLITE && p_layer != PlanetChart::CLOUD_MASK;
}

String PlanetMapCache::whole_path(int p_layer, int p_across) const {
	return vformat("%s/whole_%d_%d.png", dir, p_layer, p_across);
}

void PlanetMapCache::save_whole(int64_t p_layer, int64_t p_across, const Ref<Texture2D> &p_texture) {
	if (keeps(p_layer) && p_texture.is_valid()) {
		p_texture->get_image()->save_png(whole_path((int)p_layer, (int)p_across));
	}
}

// The whole-planet picture of a layer at a width, or null.
Ref<ImageTexture> PlanetMapCache::load_whole(int64_t p_layer, int64_t p_across) {
	String path = whole_path((int)p_layer, (int)p_across);
	if (!keeps(p_layer) || !FileAccess::file_exists(path)) {
		return Ref<ImageTexture>();
	}
	Ref<Image> image = Image::load_from_file(path);
	return image.is_valid() ? ImageTexture::create_from_image(image) : Ref<ImageTexture>();
}

String PlanetMapCache::tile_path(const Vector4i &p_key) const {
	return vformat("%s/tiles/%d_%d_%d_%d.png", dir, p_key.x, p_key.y, p_key.z, p_key.w);
}

void PlanetMapCache::save_tile(const Vector4i &p_key, const Ref<Texture2D> &p_texture) {
	if (!keeps(p_key.x) || p_texture.is_null()) {
		return;
	}
	p_texture->get_image()->save_png(tile_path(p_key));
	tile_files += 1;
	if (tile_files > MAX_TILES) {
		trim_tiles();
	}
}

Ref<ImageTexture> PlanetMapCache::load_tile(const Vector4i &p_key) {
	if (!keeps(p_key.x) || !FileAccess::file_exists(tile_path(p_key))) {
		return Ref<ImageTexture>();
	}
	Ref<Image> image = Image::load_from_file(tile_path(p_key));
	return image.is_valid() ? ImageTexture::create_from_image(image) : Ref<ImageTexture>();
}

// Throws away the tile files whose part of the map touches `area` (fractions of the map).
int64_t PlanetMapCache::forget_area(const Rect2 &p_area) {
	int gone = 0;
	PackedStringArray files = DirAccess::get_files_at(dir + "/tiles");
	for (int i = 0; i < files.size(); i++) {
		PackedStringArray parts = files[i].get_basename().split("_");
		if (parts.size() != 4) {
			continue;
		}
		Rect2 rect = PlanetMapTiles::rect_of(parts[1].to_int(), parts[2].to_int(), parts[3].to_int());
		if (rect.intersects(p_area)) {
			DirAccess::remove_absolute(vformat("%s/tiles/%s", dir, files[i]));
			gone += 1;
		}
	}
	tile_files = std::max(tile_files - gone, 0);
	return gone;
}

// Throws away the whole-planet pictures (a change somewhere makes them old).
void PlanetMapCache::forget_whole() {
	PackedStringArray files = DirAccess::get_files_at(dir);
	for (int i = 0; i < files.size(); i++) {
		if (files[i].begins_with("whole_")) {
			DirAccess::remove_absolute(vformat("%s/%s", dir, files[i]));
		}
	}
}

void PlanetMapCache::touch() {
	Ref<FileAccess> stamp = FileAccess::open(dir + "/used", FileAccess::WRITE);
	if (stamp.is_valid()) {
		stamp->store_string(String::num(Time::get_singleton()->get_unix_time_from_system()));
	}
}

// Keeps the newest MAX_TILES tile files.
void PlanetMapCache::trim_tiles() {
	PackedStringArray files = DirAccess::get_files_at(dir + "/tiles");
	std::vector<std::pair<uint64_t, String>> dated;
	for (int i = 0; i < files.size(); i++) {
		String path = vformat("%s/tiles/%s", dir, files[i]);
		dated.push_back({ FileAccess::get_modified_time(path), path });
	}
	std::sort(dated.begin(), dated.end(), [](const auto &a, const auto &b) { return a.first < b.first; });
	int surplus = (int)dated.size() - (int)(MAX_TILES * 0.8);
	for (int index = 0; index < std::max(surplus, 0); index++) {
		DirAccess::remove_absolute(dated[index].second);
	}
	tile_files = (int)DirAccess::get_files_at(dir + "/tiles").size();
}

// Keeps the MAX_WORLDS most recently used worlds.
void PlanetMapCache::trim_worlds() {
	PackedStringArray folders = DirAccess::get_directories_at(CACHE_ROOT);
	std::vector<std::pair<uint64_t, String>> worlds;
	for (int i = 0; i < folders.size(); i++) {
		String path = vformat("%s/%s", CACHE_ROOT, folders[i]);
		worlds.push_back({ FileAccess::get_modified_time(path + "/used"), path });
	}
	if ((int)worlds.size() <= MAX_WORLDS) {
		return;
	}
	std::sort(worlds.begin(), worlds.end(), [](const auto &a, const auto &b) { return a.first < b.first; });
	for (int index = 0; index < (int)worlds.size() - MAX_WORLDS; index++) {
		remove_folder(worlds[index].second);
	}
}

void PlanetMapCache::remove_folder(const String &p_path) {
	PackedStringArray tiles = DirAccess::get_files_at(p_path + String("/tiles"));
	for (int i = 0; i < tiles.size(); i++) {
		DirAccess::remove_absolute(vformat("%s/tiles/%s", p_path, tiles[i]));
	}
	DirAccess::remove_absolute(p_path + String("/tiles"));
	PackedStringArray files = DirAccess::get_files_at(p_path);
	for (int i = 0; i < files.size(); i++) {
		DirAccess::remove_absolute(vformat("%s/%s", p_path, files[i]));
	}
	DirAccess::remove_absolute(p_path);
}

// ---- PlanetMapTiles ----

void PlanetMapTiles::_bind_methods() {
	BIND_CONSTANT(TILE);
	BIND_CONSTANT(MAX_TILES);
	BIND_CONSTANT(MAX_LEVEL);
	NP_BIND(PlanetMapTiles, Variant::INT, layer)
	NP_BIND_OBJ(PlanetMapTiles, disk, "PlanetMapCache")
	NP_BIND_OBJ(PlanetMapTiles, clock, "PlanetClock")
	NP_BIND(PlanetMapTiles, Variant::INT, finished_tiles)
	ClassDB::bind_static_method("PlanetMapTiles", D_METHOD("create", "noise"), &PlanetMapTiles::create);
	ClassDB::bind_static_method("PlanetMapTiles", D_METHOD("level_for", "screen_width"), &PlanetMapTiles::level_for);
	ClassDB::bind_static_method("PlanetMapTiles", D_METHOD("rect_of", "level", "x", "y"), &PlanetMapTiles::rect_of);
	ClassDB::bind_static_method("PlanetMapTiles", D_METHOD("tiles_of", "view", "level"), &PlanetMapTiles::tiles_of);
	ClassDB::bind_method(D_METHOD("covers", "view", "level"), &PlanetMapTiles::covers);
	ClassDB::bind_method(D_METHOD("share", "view", "level"), &PlanetMapTiles::share);
	ClassDB::bind_method(D_METHOD("ask", "view", "level", "extra"), &PlanetMapTiles::ask, DEFVAL(Array()));
	ClassDB::bind_method(D_METHOD("step"), &PlanetMapTiles::step);
	ClassDB::bind_method(D_METHOD("invalidate", "area"), &PlanetMapTiles::invalidate);
	ClassDB::bind_method(D_METHOD("forget", "which"), &PlanetMapTiles::forget);
	ClassDB::bind_method(D_METHOD("stop"), &PlanetMapTiles::stop);
	ClassDB::bind_method(D_METHOD("compose", "view", "level"), &PlanetMapTiles::compose);
	ClassDB::bind_method(D_METHOD("piece", "level", "x", "y"), &PlanetMapTiles::piece);
	ClassDB::bind_method(D_METHOD("draw", "canvas", "view", "size", "level", "area"), &PlanetMapTiles::draw, DEFVAL(Rect2()));
}

Ref<PlanetMapTiles> PlanetMapTiles::create(const Ref<PlanetNoise> &p_noise) {
	Ref<PlanetMapTiles> made;
	made.instantiate();
	made->noise_ = p_noise;
	return made;
}

// The level whose tiles are about a screen pixel each, for a map `screen_width` pixels across.
int64_t PlanetMapTiles::level_for(double p_screen_width) {
	double tiles_across = p_screen_width * DENSITY / (double)TILE;
	double steps = std::log(std::max(tiles_across / 2.0, 1.0)) / std::log(2.0);
	return CLAMP((int64_t)std::ceil(steps - 0.4), (int64_t)0, (int64_t)MAX_LEVEL);
}

// The part of the map (fractions) a tile covers.
Rect2 PlanetMapTiles::rect_of(int64_t p_level, int64_t p_x, int64_t p_y) {
	double width = 1.0 / (double)(2 << p_level);
	double height = 1.0 / (double)(1 << p_level);
	return Rect2((double)p_x * width, (double)p_y * height, width, height);
}

// The tiles of `level` that the view (fractions, x may run past 0 and 1) touches, as (x, y).
Array PlanetMapTiles::tiles_of(const Rect2 &p_view, int64_t p_level) {
	int across = 2 << p_level;
	int down = 1 << p_level;
	int first_x = (int)std::floor(p_view.position.x * across);
	int last_x = (int)std::floor(p_view.get_end().x * across - 0.0001);
	int first_y = std::max((int)std::floor(p_view.position.y * down), 0);
	int last_y = std::min((int)std::floor(p_view.get_end().y * down - 0.0001), down - 1);
	Array out;
	for (int y = first_y; y <= last_y; y++) {
		for (int x = first_x; x <= last_x; x++) {
			out.append(Vector2i(positive_mod_i(x, across), y));
		}
	}
	return out;
}

Vector4i PlanetMapTiles::key_of(int p_level, int p_x, int p_y) const {
	return Vector4i((int)layer, p_level, p_x, p_y);
}

// True when every tile the view needs is charted.
bool PlanetMapTiles::covers(const Rect2 &p_view, int64_t p_level) {
	Array all = tiles_of(p_view, p_level);
	for (int i = 0; i < all.size(); i++) {
		Vector2i tile = all[i];
		if (!textures.has(key_of((int)p_level, tile.x, tile.y))) {
			return false;
		}
	}
	return true;
}

// How many of the tiles the view needs are charted, and how many it needs.
Vector2i PlanetMapTiles::share(const Rect2 &p_view, int64_t p_level) {
	int have = 0;
	Array all = tiles_of(p_view, p_level);
	for (int i = 0; i < all.size(); i++) {
		Vector2i tile = all[i];
		if (textures.has(key_of((int)p_level, tile.x, tile.y))) {
			have += 1;
		}
	}
	return Vector2i(have, (int)all.size());
}

double PlanetMapTiles::distance(const Vector4i &p_key, const Vector2 &p_centre) const {
	Rect2 rect = rect_of(p_key.y, p_key.z, p_key.w);
	Vector2 d = rect.get_center() - p_centre;
	d.x = std::abs(d.x);
	d.x = std::min((double)d.x, 1.0 - d.x); // (the map wraps)
	return d.length();
}

String PlanetMapTiles::name_of(const Vector4i &p_key) const {
	return vformat("L%d (%d, %d)", p_key.y, p_key.z, p_key.w);
}

void PlanetMapTiles::use(const Vector4i &p_key) {
	order.erase(std::remove(order.begin(), order.end(), p_key), order.end());
	order.push_back(p_key);
}

// Asks for the tiles of the view (the missing ones, the centre first). Called every frame it changes; what was asked before and is not needed any
// more is dropped.
void PlanetMapTiles::ask(const Rect2 &p_view, int64_t p_level, const Array &p_extra) {
	Vector2 centre = p_view.get_center();
	std::vector<Vector4i> missing;
	Array wanted_tiles = tiles_of(p_view, p_level);
	for (int i = 0; i < p_extra.size(); i++) { // (the parts beyond the poles)
		wanted_tiles.append_array(tiles_of(p_extra[i], p_level));
	}
	for (int i = 0; i < wanted_tiles.size(); i++) {
		Vector2i tile = wanted_tiles[i];
		Vector4i key = key_of((int)p_level, tile.x, tile.y);
		if (textures.has(key)) {
			use(key);
		} else if (std::find(missing.begin(), missing.end(), key) == missing.end()) {
			missing.push_back(key);
		}
	}
	std::stable_sort(missing.begin(), missing.end(), [&](const Vector4i &a, const Vector4i &b) { return distance(a, centre) < distance(b, centre); });
	wanted = missing;
	if (chart.is_valid() && std::find(wanted.begin(), wanted.end(), chart_key) == wanted.end()) {
		PlanetMapLog::line(vformat("tile %s given up: the view left it", name_of(chart_key)));
		chart->cancel();
		retired.push_back(chart);
		chart.unref();
	}
}

// One step: finishes the chart in hand and starts the next tile (true when a tile was added).
bool PlanetMapTiles::step() {
	for (int index = (int)retired.size() - 1; index >= 0; index--) {
		if (retired[index]->finished()) {
			retired[index]->texture(); // (joins the threads: the picture is not wanted)
			retired.erase(retired.begin() + index);
		}
	}
	bool added = false;
	if (chart.is_valid() && chart->finished()) {
		Ref<ImageTexture> texture = chart->texture();
		if (texture.is_valid()) {
			textures[chart_key] = texture;
			if (disk.is_valid()) {
				disk->save_tile(chart_key, texture);
			}
			use(chart_key);
			finished_tiles += 1;
			added = true;
			PlanetMapLog::line_every(String("tile"), 0.5, vformat("tile %s done in %d ms (%d kept, %d asked)", name_of(chart_key), (int64_t)(Time::get_singleton()->get_ticks_msec() - chart_ms), textures.size(), (int64_t)wanted.size()));
		}
		chart.unref();
		wanted.erase(std::remove(wanted.begin(), wanted.end(), chart_key), wanted.end());
		evict();
	}
	while (chart.is_null() && !wanted.empty() && disk.is_valid()) {
		Ref<ImageTexture> kept = disk->load_tile(wanted[0]); // a tile from an earlier run: no charting
		if (kept.is_null()) {
			break;
		}
		textures[wanted[0]] = kept;
		use(wanted[0]);
		finished_tiles += 1;
		added = true;
		wanted.erase(wanted.begin());
	}
	if (chart.is_null() && !wanted.empty()) {
		chart_key = wanted[0];
		chart.instantiate();
		chart->set_layer(chart_key.x);
		chart->set_clock(clock.is_valid() ? clock->copy() : Ref<PlanetClock>());
		chart->set_rect(rect_of(chart_key.y, chart_key.z, chart_key.w));
		chart->set_size(Vector2i(TILE, TILE));
		chart_ms = Time::get_singleton()->get_ticks_msec();
		chart->start(noise_);
	}
	return added;
}

void PlanetMapTiles::evict() {
	while ((int)order.size() > MAX_TILES) {
		Vector4i old = order.front();
		order.erase(order.begin());
		textures.erase(old);
	}
}

// A change in the world touched `area` (fractions of the map): its tiles are forgotten, here and on disk, and charted again when they are looked at.
int64_t PlanetMapTiles::invalidate(const Rect2 &p_area) {
	int gone = 0;
	Array keys = textures.keys();
	for (int i = 0; i < keys.size(); i++) {
		Vector4i key = keys[i];
		if (rect_of(key.y, key.z, key.w).intersects(p_area)) {
			textures.erase(key);
			order.erase(std::remove(order.begin(), order.end(), key), order.end());
			gone += 1;
		}
	}
	if (chart.is_valid() && rect_of(chart_key.y, chart_key.z, chart_key.w).intersects(p_area)) {
		chart->cancel();
		retired.push_back(chart);
		chart.unref();
	}
	if (disk.is_valid()) {
		disk->forget_area(p_area);
	}
	return gone;
}

// Forgets the tiles of a layer (the moving ones, when time has moved on).
void PlanetMapTiles::forget(int64_t p_which) {
	Array keys = textures.keys();
	for (int i = 0; i < keys.size(); i++) {
		Vector4i key = keys[i];
		if (key.x == p_which) {
			textures.erase(key);
			order.erase(std::remove(order.begin(), order.end(), key), order.end());
		}
	}
	if (chart.is_valid() && chart_key.x == p_which) {
		chart->cancel();
		retired.push_back(chart);
		chart.unref();
	}
}

// Waits for nothing: stops the chart in hand (the map is closed or freed).
void PlanetMapTiles::stop() {
	if (chart.is_valid()) {
		chart->cancel();
		chart->stop();
		chart.unref();
	}
	for (Ref<PlanetChart> &old : retired) {
		old->cancel();
		old->stop();
	}
	retired.clear();
}

// The tiles of the view put together as one picture (for the globe, which takes one texture): the texture and the part of the map (fractions) it
// covers. Empty when the view crosses the map's seam or is too big. A tile not charted yet is filled from its finest charted ancestor.
Dictionary PlanetMapTiles::compose(const Rect2 &p_view, int64_t p_level) {
	Array all = tiles_of(p_view, p_level);
	if (all.is_empty() || all.size() > 64) {
		return Dictionary();
	}
	int across = 2 << p_level;
	int low_x = across;
	int high_x = -1;
	int low_y = 1 << p_level;
	int high_y = -1;
	for (int i = 0; i < all.size(); i++) {
		Vector2i tile = all[i];
		low_x = std::min(low_x, tile.x);
		high_x = std::max(high_x, tile.x);
		low_y = std::min(low_y, tile.y);
		high_y = std::max(high_y, tile.y);
	}
	if ((high_x - low_x + 1) * (high_y - low_y + 1) != all.size()) {
		return Dictionary(); // (the view reaches over the east-west seam)
	}
	Ref<Image> image = Image::create((high_x - low_x + 1) * TILE, (high_y - low_y + 1) * TILE, false, Image::FORMAT_RGB8);
	for (int i = 0; i < all.size(); i++) {
		Vector2i tile = all[i];
		Dictionary found = piece(p_level, tile.x, tile.y);
		if (found.is_empty()) {
			continue;
		}
		Ref<ImageTexture> texture = found["texture"];
		Ref<Image> source = texture->get_image();
		Rect2 part = found["part"];
		Rect2i region(Vector2i(part.position * Vector2(source->get_size())), Vector2i(std::max((int)(part.size.x * source->get_width()), 1), std::max((int)(part.size.y * source->get_height()), 1)));
		Ref<Image> piece_image = source->get_region(region);
		if (piece_image->get_size() != Vector2i(TILE, TILE)) {
			piece_image->resize(TILE, TILE, Image::INTERPOLATE_BILINEAR);
		}
		image->blit_rect(piece_image, Rect2i(0, 0, TILE, TILE), Vector2i((tile.x - low_x) * TILE, (tile.y - low_y) * TILE));
	}
	Rect2 first = rect_of(p_level, low_x, low_y);
	Rect2 last = rect_of(p_level, high_x, high_y);
	Dictionary result;
	result["texture"] = ImageTexture::create_from_image(image);
	result["rect"] = Rect2(first.position, last.get_end() - first.position);
	return result;
}

// What to draw for the tile (level, x, y): the texture and the part of it (fractions) that is the tile, from the tile itself or its finest charted
// ancestor. Empty when none is charted.
Dictionary PlanetMapTiles::piece(int64_t p_level, int64_t p_x, int64_t p_y) {
	for (int up = 0; up <= p_level; up++) {
		Vector4i key = key_of((int)p_level - up, (int)(p_x >> up), (int)(p_y >> up));
		if (textures.has(key)) {
			Rect2 part(0.0, 0.0, 1.0, 1.0);
			if (up > 0) {
				double side = (double)(1 << up);
				part = Rect2((double)(p_x & ((1 << up) - 1)) / side, (double)(p_y & ((1 << up) - 1)) / side, 1.0 / side, 1.0 / side);
			}
			Dictionary result;
			result["texture"] = textures[key];
			result["part"] = part;
			return result;
		}
	}
	return Dictionary();
}

// Draws the tiles of `view` (map fractions) of `level` on `canvas`, `size` being the view's size in the map's fractions (`area`: the tiles to draw
// when they are not the view's): each from its own picture, or its finest charted ancestor.
void PlanetMapTiles::draw(Control *p_canvas, const Rect2 &p_view, const Vector2 &p_size, int64_t p_level, const Rect2 &p_area) {
	Array all = tiles_of(p_area.size == Vector2() ? p_view : p_area, p_level);
	for (int i = 0; i < all.size(); i++) {
		Vector2i tile = all[i];
		Dictionary found = piece(p_level, tile.x, tile.y);
		if (found.is_empty()) {
			continue;
		}
		Rect2 rect = rect_of(p_level, tile.x, tile.y);
		double dx = positive_mod_d(rect.position.x - p_view.position.x + rect.size.x, 1.0) - rect.size.x;
		Vector2 canvas_size = p_canvas->get_size();
		Vector2 at(dx / p_size.x * canvas_size.x, (rect.position.y - p_view.position.y) / p_size.y * canvas_size.y);
		Vector2 extent(rect.size.x / p_size.x * canvas_size.x, rect.size.y / p_size.y * canvas_size.y);
		Ref<ImageTexture> texture = found["texture"];
		Rect2 part = found["part"];
		Vector2 pixels = Vector2(texture->get_size());
		p_canvas->draw_texture_rect_region(texture, Rect2(at, extent + Vector2(1, 1) * 0.5), Rect2(part.position * pixels, part.size * pixels));
	}
}

// ---- PlanetMapOverlay ----

void PlanetMapOverlay::_bind_methods() {
	ClassDB::bind_static_method("PlanetMapOverlay", D_METHOD("draw_legend", "view", "layer", "relief"), &PlanetMapOverlay::draw_legend);
	ClassDB::bind_static_method("PlanetMapOverlay", D_METHOD("draw_names", "view", "labels", "zoom", "on_screen", "parchment"), &PlanetMapOverlay::draw_names, DEFVAL(false));
	ClassDB::bind_static_method("PlanetMapOverlay", D_METHOD("draw_grid", "view", "zoom", "centre", "size", "on_screen"), &PlanetMapOverlay::draw_grid);
	ClassDB::bind_static_method("PlanetMapOverlay", D_METHOD("draw_parchment_frame", "view"), &PlanetMapOverlay::draw_parchment_frame);
	ClassDB::bind_static_method("PlanetMapOverlay", D_METHOD("draw_arrow", "view", "spot", "heading"), &PlanetMapOverlay::draw_arrow);
	ClassDB::bind_static_method("PlanetMapOverlay", D_METHOD("draw_loading", "view", "progress"), &PlanetMapOverlay::draw_loading);
	ClassDB::bind_static_method("PlanetMapOverlay", D_METHOD("describe", "noise", "uv"), &PlanetMapOverlay::describe);
}

// The scale of the layer (a bar, its two ends and, for the temperature, ticks) in the corner.
void PlanetMapOverlay::draw_legend(Control *p_view, int64_t p_layer, double p_relief) {
	Array labels = PlanetChart::scale_labels(p_layer, p_relief);
	if (labels.is_empty()) {
		return;
	}
	Vector2 origin(18.0, p_view->get_size().y - 34.0);
	double width = 260.0;
	for (int step = 0; step < (int)width; step++) {
		p_view->draw_rect(Rect2(origin + Vector2((double)step, 0.0), Vector2(1.0, 14.0)), PlanetChart::ramp(p_layer, (double)step / width));
	}
	p_view->draw_rect(Rect2(origin, Vector2(width, 14.0)), Color(1, 1, 1, 1), false, 1.0);
	Ref<Font> font = ThemeDB::get_singleton()->get_fallback_font();
	if (p_layer == PlanetChart::TEMPERATURE || p_layer == PlanetChart::MEAN_TEMPERATURE) {
		// ticks every 10 degrees C (the scale runs -30 to 45), as a weather map's legend has
		for (int degrees = -20; degrees <= 40; degrees += 10) {
			double x = ((double)degrees + 30.0) / 75.0 * width;
			p_view->draw_line(origin + Vector2(x, 10.0), origin + Vector2(x, 14.0), Color(1, 1, 1, 1), 1.0);
			p_view->draw_string(font, origin + Vector2(x - 8.0, 27.0), String::num_int64(degrees), HORIZONTAL_ALIGNMENT_LEFT, -1, 11);
		}
	}
	p_view->draw_string(font, origin + Vector2(0.0, -4.0), labels[0], HORIZONTAL_ALIGNMENT_LEFT, -1, 14);
	p_view->draw_string(font, origin + Vector2(width, -4.0), labels[1], HORIZONTAL_ALIGNMENT_RIGHT, -1, 14);
	Array names = PlanetChart::names();
	p_view->draw_string(font, origin + Vector2(width + 14.0, 12.0), names[p_layer], HORIZONTAL_ALIGNMENT_LEFT, -1, 16);
}

// The names of the seas and the lands, spaced capitals, while the view is far enough to show them.
void PlanetMapOverlay::draw_names(Control *p_view, const Ref<PlanetMapLabels> &p_labels, double p_zoom, const Callable &p_on_screen, bool p_parchment) {
	Ref<Font> font = ThemeDB::get_singleton()->get_fallback_font();
	int size = CLAMP((int)(13.0 + 3.0 * std::log(p_zoom + 1.0)), 13, 22);
	Array items = p_labels->get_items();
	for (int i = 0; i < items.size(); i++) {
		Dictionary item = items[i];
		Vector2 spot = p_on_screen.call(item["uv"]);
		if (spot.x < 0.0) {
			continue;
		}
		String text = PlanetMapLabels::spaced(item["text"]);
		double width = font->get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, size).x;
		Vector2 at = spot - Vector2(width * 0.5, 0.0);
		bool sea = item["sea"];
		Color colour = !p_parchment ? Color(0.95f, 0.82f, 0.45f, 0.95f) : Color(0.40f, 0.25f, 0.08f, 0.95f);
		if (p_parchment && sea) {
			colour = Color(0.30f, 0.38f, 0.45f, 0.9f);
		} else if (!p_parchment) {
			colour = sea ? Color(0.88f, 0.95f, 1.0f, 0.8f) : Color(1.0f, 1.0f, 1.0f, 0.85f);
		}
		p_view->draw_string_outline(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, size, 3, p_parchment ? Color(0.95f, 0.88f, 0.7f, 0.6f) : Color(0.0f, 0.0f, 0.0f, 0.55f));
		p_view->draw_string(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, size, colour);
	}
}

// The lines every `gap` degrees, finer as the view comes closer (only the ones in view).
void PlanetMapOverlay::draw_grid(Control *p_view, double p_zoom, const Vector2 &p_centre, const Vector2 &p_size, const Callable &p_on_screen) {
	double gap = 30.0;
	static const double steps[6][2] = { { 3.0, 10.0 }, { 12.0, 5.0 }, { 70.0, 1.0 }, { 140.0, 0.5 }, { 700.0, 0.1 }, { 1400.0, 0.05 } };
	for (const auto &pair : steps) { // (from this zoom on, this gap)
		if (p_zoom >= pair[0]) {
			gap = pair[1];
		}
	}
	Color line(1.0f, 1.0f, 1.0f, 0.18f);
	double lat_from = (0.5 - (p_centre.y + p_size.y * 0.5)) * 180.0;
	double lat_to = (0.5 - (p_centre.y - p_size.y * 0.5)) * 180.0;
	Vector2 view_size = p_view->get_size();
	for (int index = (int)std::floor(lat_from / gap); index <= (int)std::ceil(lat_to / gap); index++) {
		double degrees = (double)index * gap;
		Vector2 at = p_on_screen.call(Vector2(p_centre.x, 0.5 - degrees / 180.0));
		if (at.y >= 0.0 && std::abs(degrees) <= 90.0) {
			p_view->draw_line(Vector2(0.0, at.y), Vector2(view_size.x, at.y), index != 0 ? line : Color(1.0f, 1.0f, 1.0f, 0.4f));
		}
	}
	double lon_centre = (p_centre.x - 0.5) * 360.0;
	double lon_half = std::min(p_size.x * 180.0, 180.0);
	int first = (int)std::floor((lon_centre - lon_half) / gap);
	for (int index = first; index <= (int)std::ceil((lon_centre + lon_half) / gap); index++) {
		double uv = ((double)index * gap + 180.0) / 360.0;
		Vector2 at = p_on_screen.call(Vector2(positive_mod_d(uv, 1.0), p_centre.y));
		if (at.x >= 0.0) {
			p_view->draw_line(Vector2(at.x, 0.0), Vector2(at.x, view_size.y), line);
		}
	}
}

// A frame like an old map's: the corners and edges darkened as burnt paper, a thin gold border.
void PlanetMapOverlay::draw_parchment_frame(Control *p_view) {
	Vector2 size = p_view->get_size();
	Color dark(0.12f, 0.07f, 0.02f);
	for (int step = 0; step < 36; step++) {
		double share = 1.0 - (double)step / 36.0;
		Color colour(dark.r, dark.g, dark.b, (float)(0.5 * share * share));
		p_view->draw_rect(Rect2((double)step * 2.0, (double)step * 2.0, size.x - (double)step * 4.0, size.y - (double)step * 4.0), colour, false, 2.0);
	}
	Color gold(0.78f, 0.6f, 0.2f, 0.9f);
	p_view->draw_rect(Rect2(10.0, 10.0, size.x - 20.0, size.y - 20.0), gold, false, 2.0);
	for (const Vector2 &corner : { Vector2(10.0, 10.0), Vector2(size.x - 10.0, 10.0), Vector2(10.0, size.y - 10.0), Vector2(size.x - 10.0, size.y - 10.0) }) {
		p_view->draw_circle(corner, 6.0, Color(0.78f, 0.6f, 0.2f, 0.95f));
		p_view->draw_circle(corner, 3.0, Color(0.25f, 0.15f, 0.05f, 0.95f));
	}
}

// The player: an arrow at `spot` pointing along `heading`.
void PlanetMapOverlay::draw_arrow(Control *p_view, const Vector2 &p_spot, const Vector2 &p_heading) {
	Vector2 side(-p_heading.y, p_heading.x);
	PackedVector2Array points;
	points.append(p_spot + p_heading * 13.0);
	points.append(p_spot - p_heading * 7.0 + side * 7.0);
	points.append(p_spot - p_heading * 7.0 - side * 7.0);
	PackedColorArray colours;
	colours.append(Color(1.0f, 0.25f, 0.2f));
	p_view->draw_colored_polygon(points, Color(1.0f, 0.25f, 0.2f));
	PackedVector2Array outline;
	outline.append(points[0]);
	outline.append(points[1]);
	outline.append(points[2]);
	outline.append(points[0]);
	p_view->draw_polyline(outline, Color(1, 1, 1, 1), 1.5);
}

// While the picture is still the quick blurry one: a note over it says the map is being charted (`progress` 0..1 of the chart in hand, or negative
// when there is none).
void PlanetMapOverlay::draw_loading(Control *p_view, double p_progress) {
	String text = "Charting the planet... the map sharpens as it finishes";
	if (p_progress >= 0.0) {
		text = vformat("Charting the planet...  %d %%  (the map sharpens as it finishes)", (int)(100.0 * p_progress));
	}
	Ref<Font> font = ThemeDB::get_singleton()->get_fallback_font();
	double width = font->get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 18).x;
	Rect2 box((p_view->get_size().x - width) * 0.5 - 14.0, 18.0, width + 28.0, 34.0);
	p_view->draw_rect(box, Color(0.0f, 0.0f, 0.0f, 0.7f));
	p_view->draw_string(font, box.position + Vector2(14.0, 24.0), text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 18, Color(0.9f, 0.93f, 1.0f));
}

// The numbers at the map point `uv` (fractions): where, height, temperature, rain, biome, plate.
String PlanetMapOverlay::describe(const Ref<PlanetNoise> &p_noise, const Vector2 &p_uv) {
	double lat = (0.5 - p_uv.y) * PI_D;
	double lon = p_uv.x * TAU_D - PI_D;
	Vector3 dir(std::cos(lat) * std::cos(lon), std::sin(lat), std::cos(lat) * std::sin(lon));
	double ground = p_noise->height(dir.x, dir.y, dir.z);
	Vector3 plate = p_noise->get_tectonics()->plate_at(dir);
	static const char *biomes[7] = { "beach", "meadow", "forest", "rocky", "snow", "marsh", "desert" };
	String biome = "sea";
	if (ground >= 0.0) {
		biome = biomes[p_noise->biome(dir.x, dir.y, dir.z, ground, 0.1)];
	}
	String format = String::utf8("%.1f\xC2\xB0 %s %.1f\xC2\xB0 %s   height %d m   %.0f \xC2\xB0""C   rain %.2f   %s   plate %d (%s)");
	return vformat(format, std::abs(Math::rad_to_deg(lat)), lat >= 0.0 ? "N" : "S", std::abs(Math::rad_to_deg(lon)), lon >= 0.0 ? "E" : "W", (int64_t)std::round(ground),
			p_noise->temperature_now(dir.x, dir.y, dir.z, std::max(ground, 0.0)), p_noise->get_climate()->sample(dir).y, biome, (int)plate.x, plate.z > 0.5 ? "land" : "ocean");
}

// ---- PlanetMapTimeBar ----

void PlanetMapTimeBar::_bind_methods() {
	ClassDB::bind_static_method("PlanetMapTimeBar", D_METHOD("create", "planet"), &PlanetMapTimeBar::create);
	ClassDB::bind_method(D_METHOD("refresh"), &PlanetMapTimeBar::refresh);
	ClassDB::bind_method(D_METHOD("set_rate", "rate"), &PlanetMapTimeBar::set_rate);
	ClassDB::bind_method(D_METHOD("jump_days", "days"), &PlanetMapTimeBar::jump_days);
	ClassDB::bind_method(D_METHOD("jump_eighth_years", "eighths"), &PlanetMapTimeBar::jump_eighth_years);
	ClassDB::bind_method(D_METHOD("year_changed", "value"), &PlanetMapTimeBar::year_changed);
}

void PlanetMapTimeBar::add_button(const String &p_text, const StringName &p_method, const Variant &p_argument) {
	Button *button = memnew(Button);
	button->set_text(p_text);
	button->set_focus_mode(Control::FOCUS_NONE);
	button->connect("pressed", Callable(this, p_method).bind(p_argument));
	add_child(button);
}

PlanetMapTimeBar *PlanetMapTimeBar::create(Object *p_planet) {
	PlanetMapTimeBar *bar = memnew(PlanetMapTimeBar);
	bar->planet_id = p_planet->get_instance_id();
	bar->set_alignment(BoxContainer::ALIGNMENT_CENTER);
	Label *title = memnew(Label);
	title->set_text("Time:  ");
	bar->add_child(title);
	String times = String::utf8("\xC3\x97");
	for (int rate : { -1000, -100, -10, -1 }) {
		bar->add_button(vformat("%d", rate) + times, "set_rate", (double)rate);
	}
	bar->add_button("pause", "set_rate", 0.0);
	for (int rate : { 1, 10, 100, 1000 }) {
		bar->add_button(vformat("%d", rate) + times, "set_rate", (double)rate);
	}
	bar->add_button("-day", "jump_days", -1.0);
	bar->add_button("+day", "jump_days", 1.0);
	bar->add_button("-1/8 year", "jump_eighth_years", -1.0);
	bar->add_button("+1/8 year", "jump_eighth_years", 1.0);
	Label *year = memnew(Label);
	year->set_text("  year:");
	bar->add_child(year);
	bar->season_slider = memnew(HSlider);
	bar->season_slider->set_custom_minimum_size(Vector2(200.0, 0.0));
	bar->season_slider->set_max(1.0);
	bar->season_slider->set_step(0.002);
	bar->season_slider->set_focus_mode(Control::FOCUS_NONE);
	bar->season_slider->connect("value_changed", Callable(bar, "year_changed"));
	bar->add_child(bar->season_slider);
	bar->rate_label = memnew(Label);
	bar->add_child(bar->rate_label);
	return bar;
}

// Shows where the year is and how fast time runs.
void PlanetMapTimeBar::refresh() {
	Object *planet = ObjectDB::get_instance(planet_id);
	Ref<PlanetClock> clock = planet->get("clock");
	season_slider->set_value_no_signal(clock->year_share());
	double rate = planet->get("time_rate");
	rate_label->set_text("   " + (rate == 0.0 ? String("paused") : vformat("%d", (int)rate) + String::utf8("\xC3\x97")));
}

void PlanetMapTimeBar::set_rate(double p_rate) {
	ObjectDB::get_instance(planet_id)->set("time_rate", p_rate);
}

void PlanetMapTimeBar::jump_days(double p_days) {
	ObjectDB::get_instance(planet_id)->call("jump_time", p_days);
}

void PlanetMapTimeBar::jump_eighth_years(double p_eighths) {
	Object *planet = ObjectDB::get_instance(planet_id);
	Ref<PlanetClock> clock = planet->get("clock");
	planet->call("jump_time", p_eighths * clock->get_year_days() / 8.0);
}

void PlanetMapTimeBar::year_changed(double p_value) {
	if (Input::get_singleton()->is_mouse_button_pressed(MOUSE_BUTTON_LEFT)) {
		ObjectDB::get_instance(planet_id)->call("set_year_share", p_value);
	}
}
