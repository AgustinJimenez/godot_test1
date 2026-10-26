#pragma once

// PlanetMap (was systems/planet/planet_map.gd): a map of the planet on the M key, over the whole screen. It opens on the player's region (their
// arrow in the middle); the mouse wheel zooms in and out (all the way out is the whole planet), dragging moves the view, R comes back to the player.
// It is drawn from the planet's own height function (PlanetNoise) on background threads (PlanetChart): a coarse chart of the whole planet first, a
// fine one after, close views as tiles (PlanetMapTiles) or a chart of just that region. A flat (equirectangular) map or the 3D globe (G). Layers (the
// dropdown, or the keys 1 to 9): the atlas, the terrain, the elevation, the temperature, the rain, the biomes, the plates, the slope, the mean
// temperature, the clouds and the satellite view; under the cursor the exact numbers are listed.

#include "native_props.h"
#include "planet_chart_native.h"
#include "planet_map_globe_native.h"
#include "planet_map_support_native.h"
#include "planet_world_native.h"
#include "universe_native.h"

#include <godot_cpp/classes/button.hpp>
#include <godot_cpp/classes/canvas_layer.hpp>
#include <godot_cpp/classes/control.hpp>
#include <godot_cpp/classes/image_texture.hpp>
#include <godot_cpp/classes/input.hpp>
#include <godot_cpp/classes/input_event.hpp>
#include <godot_cpp/classes/label.hpp>
#include <godot_cpp/classes/option_button.hpp>
#include <godot_cpp/variant/rect2.hpp>
#include <godot_cpp/variant/vector2i.hpp>

#include <vector>

namespace godot {

class PlanetMap : public CanvasLayer {
	GDCLASS(PlanetMap, CanvasLayer)

	int layer_now = PlanetChart::ATLAS; // (the simple map to read: the others are extra modes)
	Dictionary cache; // layer -> {"whole": ImageTexture, "pass": int}: what was charted
	std::vector<Ref<PlanetChart>> retired; // charts of a layer left behind, drawing out their threads
	OptionButton *modes = nullptr; // the layers, as a dropdown (the Atlas first)
	Label *hover = nullptr;
	PlanetMapTimeBar *time_bar = nullptr;
	double drawn_at = -1.0; // the clock time the temperature chart on the screen is of
	double refresh_wait = 0.0;
	double chart_time = 0.0;
	Ref<ImageTexture> whole; // the whole planet, as sharp as it has got
	int whole_pass = -1; // the pass `whole` is from (-1: none yet)
	Ref<PlanetChart> chart; // the chart being drawn, if any
	bool chart_is_detail = false;
	Ref<ImageTexture> detail; // a close chart of `detail_rect` (fractions of the map)
	Rect2 detail_rect;
	bool revealed = false; // the picture is sharp (until then a loading note is drawn over the map)
	double unsharp_time = 0.0; // seconds the map has been unsharp since it was opened
	bool detail_preview = false; // the close chart in `detail` is the quick small one
	int detail_full = 0; // pixels across of the sharp chart that follows a quick preview (0: none)
	double still = 0.0; // seconds the view has stayed as it is
	Rect2 last_view;
	Control *view = nullptr;
	PlanetMapGlobe *globe = nullptr; // the map as a small planet in 3D (G)
	Button *globe_button = nullptr;
	bool globe_mode = false;
	Label *caption = nullptr;
	Ref<PlanetMapLabels> labels; // the names of the seas and lands (built on the first look)
	int globe_tiles = -1; // what the globe's picture was made from, to see when it needs a new one
	int globe_level = -1;
	Rect2 globe_view;
	Ref<PlanetMapCache> disk; // what was charted in an earlier run of this world
	Ref<PlanetMapTiles> tiles; // the close views as tiles (from TILE_ZOOM on, on the flat map)
	bool warming = false;
	std::vector<int> warm_queue; // the layers still to get a first picture
	int warm_total = 1;
	int warm_layers_done = 0;
	int warm_close = 0; // 0 the close view of the start is not charted yet, 1 it has been started
	int chart_layer = PlanetChart::TERRAIN; // the layer of the chart in hand (maybe not shown)
	uint64_t chart_ms = 0; // when the chart in hand was started
	Vector3 logged_view = Vector3(-1, -1, -1); // (zoom, centre) last logged
	double zoom_now = 1500.0;
	Vector2 centre = Vector2(0.5, 0.5); // in map fractions (u east, v south)
	bool dragging = false;
	Input::MouseMode mouse_before = Input::MOUSE_MODE_VISIBLE;
	bool started = false;

	static bool is_moving(int p_layer);
	static Vector3 direction_of(const Vector2 &p_uv);
	static Vector2 uv_of(const Vector3 &p_dir);
	Vector2 pane() const;
	double pixels_per_map() const;
	Vector2 visible_size() const;
	void clamp_centre();
	void zoom_at(const Vector2 &p_mouse, double p_factor);
	void go_home();
	bool over_the_pane(const Vector2 &p_point) const;
	int last_pass() const;
	void start_chart(int p_pass_index);
	bool tile_mode() const;
	int64_t tile_level() const;
	Rect2 tile_view() const;
	Array tile_view_beyond() const;
	void serve_the_tiles();
	void set_the_globe_detail();
	void draw_whole(const Rect2 &p_view, const Vector2 &p_size);
	void drive_the_warm_up();
	void start_warm_layer(int p_layer);
	double warm_progress() const;
	void log_the_view();
	void refresh_temperature(double p_delta);
	void adopt_chart();
	void drop_a_stale_chart();
	void maybe_chart_the_view(double p_delta);
	bool chart_close_view(const Rect2 &p_view, const Vector2 &p_size);
	void start_detail(const Rect2 &p_rect, int p_across);
	bool covered_by_detail(const Rect2 &p_view) const;
	bool sharply_covered(const Rect2 &p_view) const;
	String numbers_under_the_cursor() const;
	Dictionary where_is_the_player() const;
	bool sharp_enough(const Rect2 &p_view);
	void update_reveal(double p_delta);
	void draw_beyond_the_poles(const Rect2 &p_view, const Vector2 &p_size);
	void draw_part(const Ref<ImageTexture> &p_texture, const Rect2 &p_covers, const Rect2 &p_wanted, double p_offset_u = 0.0);
	void draw_names();
	Vector2 on_screen(const Vector2 &p_uv) const;

protected:
	static void _bind_methods();

public:
	static constexpr int FIRST_BIG_PASS = 3; // the whole passes before this are short: they finish first
	static constexpr int DETAIL_MIN = 768; // pixels across the close chart, at least (more for a big view)
	static constexpr int DETAIL_MAX = 2560;
	static constexpr int MIDDLE_DETAIL = 1280; // the picture between the quick one and the sharp one
	static constexpr double MAX_ZOOM = 1500.0; // a pixel of the sharpest chart is then about 15 m on an Earth
	static constexpr double MARGIN = 14.0;
	static constexpr double TILE_ZOOM = 2.0; // from this zoom on the flat map is drawn from tiles

	NP_OBJECT_T(planet, PlanetWorld)
	NP_FIELD(bool, warm_up, false) // the world sets it: the map is all charted (black meanwhile) before it shows

	static double get_max_zoom() { return MAX_ZOOM; }
	double get__zoom() const { return zoom_now; }
	void set__zoom(double p_value) { zoom_now = p_value; }

	void _ready() override;
	void _input(const Ref<InputEvent> &p_event) override;
	void _process(double p_delta) override;
	void _exit_tree() override;
	void toggle();
	void select_layer(int64_t p_layer);
	void mode_selected(int64_t p_position);
	void look_from_globe(const Vector3 &p_dir);
	void zoom_by(double p_factor);
	void set_globe(bool p_on);
	void show_zoom(double p_zoom);
	void begin();
	void draw_view();
	void world_changed(const Rect2 &p_area);
	void world_changed_at(const Vector3 &p_direction, double p_radius_metres);
	void show_globe(bool p_on = true);
};

} // namespace godot
