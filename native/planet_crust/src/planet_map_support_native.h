#pragma once

// The map's helpers (were systems/planet/planet_map_cache.gd, planet_map_tiles.gd, planet_map_overlay.gd and planet_map_time_bar.gd):
// PlanetMapCache keeps the map's pictures on disk between runs; PlanetMapTiles cuts the close views into tiles like a web map's (each charted once,
// kept, drawn from the tiles a view needs); PlanetMapOverlay draws over the picture (legend, names, grid, arrow, frame, the numbers at a point);
// PlanetMapTimeBar is the row of buttons that move time.

#include "native_props.h"
#include "planet_chart_native.h"
#include "planet_clock_native.h"
#include "planet_noise_native.h"
#include "planet_settings_native.h"
#include "universe_native.h"

#include <godot_cpp/classes/control.hpp>
#include <godot_cpp/classes/h_box_container.hpp>
#include <godot_cpp/classes/h_slider.hpp>
#include <godot_cpp/classes/image_texture.hpp>
#include <godot_cpp/classes/label.hpp>
#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/classes/texture2d.hpp>
#include <godot_cpp/variant/callable.hpp>
#include <godot_cpp/variant/rect2.hpp>
#include <godot_cpp/variant/vector2i.hpp>
#include <godot_cpp/variant/vector4i.hpp>

#include <vector>

namespace godot {

class PlanetMapCache : public RefCounted {
	GDCLASS(PlanetMapCache, RefCounted)

	String dir;
	int tile_files = 0;

	String whole_path(int p_layer, int p_across) const;
	String tile_path(const Vector4i &p_key) const;
	void touch();
	void trim_tiles();
	void trim_worlds();
	static void remove_folder(const String &p_path);

protected:
	static void _bind_methods();

public:
	static constexpr int VERSION = 6; // raise whenever the crust, the climate or the way a layer is drawn changes
	static constexpr int MAX_TILES = 900; // tile files kept per world (the oldest go first)
	static constexpr int MAX_WORLDS = 6; // worlds kept (the least recently used go)

	// `PlanetMapCache.new(settings)` of the script: opens the folder of the world with these settings
	static Ref<PlanetMapCache> create(const Ref<PlanetSettings> &p_settings);
	String directory() const { return dir; }
	static bool keeps(int64_t p_layer);
	void save_whole(int64_t p_layer, int64_t p_across, const Ref<Texture2D> &p_texture);
	Ref<ImageTexture> load_whole(int64_t p_layer, int64_t p_across);
	void save_tile(const Vector4i &p_key, const Ref<Texture2D> &p_texture);
	Ref<ImageTexture> load_tile(const Vector4i &p_key);
	int64_t forget_area(const Rect2 &p_area);
	void forget_whole();
};

class PlanetMapTiles : public RefCounted {
	GDCLASS(PlanetMapTiles, RefCounted)

	Ref<PlanetNoise> noise_;
	Dictionary textures; // Vector4i(layer, level, x, y) -> ImageTexture
	std::vector<Vector4i> order; // the keys, the least recently used first
	std::vector<Vector4i> wanted; // what the view needs and is missing, nearest the centre first
	Ref<PlanetChart> chart;
	Vector4i chart_key;
	uint64_t chart_ms = 0;
	std::vector<Ref<PlanetChart>> retired;

	Vector4i key_of(int p_level, int p_x, int p_y) const;
	double distance(const Vector4i &p_key, const Vector2 &p_centre) const;
	String name_of(const Vector4i &p_key) const;
	void use(const Vector4i &p_key);
	void evict();

protected:
	static void _bind_methods();

public:
	static constexpr int TILE = 256; // pixels a side
	static constexpr int MAX_TILES = 360;
	static constexpr int MAX_LEVEL = 14;
	static constexpr double DENSITY = 0.85; // tile pixels per screen pixel (a little under one is sharp enough)

	NP_FIELD(int64_t, layer, PlanetChart::TERRAIN)
	NP_FIELD(Ref<PlanetMapCache>, disk, Ref<PlanetMapCache>()) // the tiles kept between runs (null: none)
	NP_FIELD(Ref<PlanetClock>, clock, Ref<PlanetClock>()) // the moment the moving layers (temperature, clouds) show
	NP_FIELD(int64_t, finished_tiles, 0) // how many were charted this session (for the log)

	// `PlanetMapTiles.new(noise)` of the script
	static Ref<PlanetMapTiles> create(const Ref<PlanetNoise> &p_noise);
	static int64_t level_for(double p_screen_width);
	static Rect2 rect_of(int64_t p_level, int64_t p_x, int64_t p_y);
	static Array tiles_of(const Rect2 &p_view, int64_t p_level);
	bool covers(const Rect2 &p_view, int64_t p_level);
	Vector2i share(const Rect2 &p_view, int64_t p_level);
	void ask(const Rect2 &p_view, int64_t p_level, const Array &p_extra = Array());
	bool step();
	int64_t invalidate(const Rect2 &p_area);
	void forget(int64_t p_which);
	void stop();
	Dictionary compose(const Rect2 &p_view, int64_t p_level);
	Dictionary piece(int64_t p_level, int64_t p_x, int64_t p_y);
	void draw(Control *p_canvas, const Rect2 &p_view, const Vector2 &p_size, int64_t p_level, const Rect2 &p_area = Rect2());
};

class PlanetMapOverlay : public RefCounted {
	GDCLASS(PlanetMapOverlay, RefCounted)

protected:
	static void _bind_methods();

public:
	static void draw_legend(Control *p_view, int64_t p_layer, double p_relief);
	static void draw_names(Control *p_view, const Ref<PlanetMapLabels> &p_labels, double p_zoom, const Callable &p_on_screen, bool p_parchment = false);
	static void draw_grid(Control *p_view, double p_zoom, const Vector2 &p_centre, const Vector2 &p_size, const Callable &p_on_screen);
	static void draw_parchment_frame(Control *p_view);
	static void draw_arrow(Control *p_view, const Vector2 &p_spot, const Vector2 &p_heading);
	static void draw_loading(Control *p_view, double p_progress);
	static String describe(const Ref<PlanetNoise> &p_noise, const Vector2 &p_uv);
};

class PlanetMapTimeBar : public HBoxContainer {
	GDCLASS(PlanetMapTimeBar, HBoxContainer)

	ObjectID planet_id;
	HSlider *season_slider = nullptr;
	Label *rate_label = nullptr;

	void add_button(const String &p_text, const StringName &p_method, const Variant &p_argument);

protected:
	static void _bind_methods();

public:
	// `PlanetMapTimeBar.new(planet)` of the script
	static PlanetMapTimeBar *create(Object *p_planet);
	void refresh();
	void set_rate(double p_rate);
	void jump_days(double p_days);
	void jump_eighth_years(double p_eighths);
	void year_changed(double p_value);
};

} // namespace godot
