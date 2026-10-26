#include "planet_map_ui_native.h"

#include "planet_log_native.h"

#include <godot_cpp/classes/camera3d.hpp>
#include <godot_cpp/classes/display_server.hpp>
#include <godot_cpp/classes/font.hpp>
#include <godot_cpp/classes/h_box_container.hpp>
#include <godot_cpp/classes/input_event_key.hpp>
#include <godot_cpp/classes/input_event_magnify_gesture.hpp>
#include <godot_cpp/classes/input_event_mouse_button.hpp>
#include <godot_cpp/classes/input_event_mouse_motion.hpp>
#include <godot_cpp/classes/input_event_pan_gesture.hpp>
#include <godot_cpp/classes/input_map.hpp>
#include <godot_cpp/classes/os.hpp>
#include <godot_cpp/classes/panel_container.hpp>
#include <godot_cpp/classes/theme_db.hpp>
#include <godot_cpp/classes/time.hpp>
#include <godot_cpp/classes/v_box_container.hpp>
#include <godot_cpp/classes/viewport.hpp>
#include <godot_cpp/variant/utility_functions.hpp>

#include <algorithm>
#include <cmath>

using namespace godot;

static const double TAU_D = 6.283185307179586476925286766559;
static const double PI_D = 3.14159265358979323846;

static const char *ACTION_NAME = "planet_map";
static const Vector2i PASSES[4] = { Vector2i(320, 160), Vector2i(640, 320), Vector2i(1024, 512), Vector2i(2048, 1024) };
// the layers as the buttons and the keys 1.. list them (the Atlas first, the rest are extra)
static const int LAYER_ORDER[11] = { PlanetChart::ATLAS, PlanetChart::TERRAIN, PlanetChart::ELEVATION, PlanetChart::TEMPERATURE, PlanetChart::RAIN, PlanetChart::BIOME,
	PlanetChart::PLATES, PlanetChart::SLOPE, PlanetChart::MEAN_TEMPERATURE, PlanetChart::CLOUDS, PlanetChart::SATELLITE };

static double positive_mod_d(double p_x, double p_y) {
	double value = std::fmod(p_x, p_y);
	if ((value < 0.0 && p_y > 0.0) || (value > 0.0 && p_y < 0.0)) {
		value += p_y;
	}
	return value;
}

static int layer_position(int p_layer) {
	for (int i = 0; i < 11; i++) {
		if (LAYER_ORDER[i] == p_layer) {
			return i;
		}
	}
	return -1;
}

void PlanetMap::_bind_methods() {
	BIND_CONSTANT(DETAIL_MIN);
	BIND_CONSTANT(DETAIL_MAX);
	BIND_CONSTANT(MIDDLE_DETAIL);
	NP_BIND_OBJECT(PlanetMap, planet)
	NP_BIND(PlanetMap, Variant::BOOL, warm_up)
	NP_BIND_STATE(PlanetMap, Variant::FLOAT, _zoom)
	ClassDB::bind_static_method("PlanetMap", D_METHOD("get_max_zoom"), &PlanetMap::get_max_zoom);
	ClassDB::bind_method(D_METHOD("toggle"), &PlanetMap::toggle);
	ClassDB::bind_method(D_METHOD("select_layer", "layer"), &PlanetMap::select_layer);
	ClassDB::bind_method(D_METHOD("mode_selected", "position"), &PlanetMap::mode_selected);
	ClassDB::bind_method(D_METHOD("look_from_globe", "dir"), &PlanetMap::look_from_globe);
	ClassDB::bind_method(D_METHOD("zoom_by", "factor"), &PlanetMap::zoom_by);
	ClassDB::bind_method(D_METHOD("set_globe", "on"), &PlanetMap::set_globe);
	ClassDB::bind_method(D_METHOD("show_zoom", "zoom"), &PlanetMap::show_zoom);
	ClassDB::bind_method(D_METHOD("begin"), &PlanetMap::begin);
	ClassDB::bind_method(D_METHOD("draw_view"), &PlanetMap::draw_view);
	ClassDB::bind_method(D_METHOD("world_changed", "area"), &PlanetMap::world_changed);
	ClassDB::bind_method(D_METHOD("world_changed_at", "direction", "radius_metres"), &PlanetMap::world_changed_at);
	ClassDB::bind_method(D_METHOD("show_globe", "on"), &PlanetMap::show_globe, DEFVAL(true));
	ClassDB::bind_method(D_METHOD("on_screen_point", "uv"), &PlanetMap::on_screen);
}

void PlanetMap::_ready() {
	set_layer(70);
	set_visible(false);
	InputMap *input_map = InputMap::get_singleton();
	if (!input_map->has_action(ACTION_NAME)) {
		input_map->add_action(ACTION_NAME);
		Ref<InputEventKey> key;
		key.instantiate();
		key->set_physical_keycode(KEY_M);
		input_map->action_add_event(ACTION_NAME, key);
	}
	PanelContainer *panel = memnew(PanelContainer);
	panel->set_anchors_and_offsets_preset(Control::PRESET_FULL_RECT);
	panel->set_offset(SIDE_LEFT, MARGIN);
	panel->set_offset(SIDE_TOP, MARGIN);
	panel->set_offset(SIDE_RIGHT, -MARGIN);
	panel->set_offset(SIDE_BOTTOM, -MARGIN);
	add_child(panel);
	VBoxContainer *column = memnew(VBoxContainer);
	panel->add_child(column);
	view = memnew(Control);
	view->set_v_size_flags(Control::SIZE_EXPAND_FILL);
	view->set_h_size_flags(Control::SIZE_EXPAND_FILL);
	view->set_custom_minimum_size(Vector2(400.0, 300.0));
	view->set_clip_contents(true);
	view->connect("draw", Callable(this, "draw_view"));
	column->add_child(view);
	globe = memnew(PlanetMapGlobe);
	globe->set_v_size_flags(Control::SIZE_EXPAND_FILL);
	globe->set_h_size_flags(Control::SIZE_EXPAND_FILL);
	globe->set_custom_minimum_size(Vector2(400.0, 300.0));
	globe->set_visible(false);
	globe->connect("zoomed", Callable(this, "zoom_by"));
	globe->connect("moved", Callable(this, "look_from_globe"));
	column->add_child(globe);
	HBoxContainer *row = memnew(HBoxContainer);
	row->set_alignment(BoxContainer::ALIGNMENT_CENTER);
	column->add_child(row);
	modes = memnew(OptionButton);
	modes->set_focus_mode(Control::FOCUS_NONE);
	modes->set_custom_minimum_size(Vector2(190.0, 0.0));
	Array names = PlanetChart::names();
	for (int position = 0; position < 11; position++) {
		String key_name = position < 10 ? String::num_int64((position + 1) % 10) : String(" ");
		modes->add_item(vformat("%s  %s", key_name, names[LAYER_ORDER[position]]), position);
	}
	modes->select(layer_position(layer_now));
	modes->connect("item_selected", Callable(this, "mode_selected"));
	row->add_child(modes);
	globe_button = memnew(Button);
	globe_button->set_text("G  Globe");
	globe_button->set_toggle_mode(true);
	globe_button->set_focus_mode(Control::FOCUS_NONE);
	globe_button->connect("toggled", Callable(this, "set_globe"));
	row->add_child(globe_button);
	time_bar = PlanetMapTimeBar::create(get_planet());
	column->add_child(time_bar);
	hover = memnew(Label);
	hover->set_horizontal_alignment(HORIZONTAL_ALIGNMENT_CENTER);
	column->add_child(hover);
	caption = memnew(Label);
	caption->set_text("Charting the planet...");
	caption->set_horizontal_alignment(HORIZONTAL_ALIGNMENT_CENTER);
	column->add_child(caption);
}

void PlanetMap::mode_selected(int64_t p_position) {
	select_layer(LAYER_ORDER[p_position]);
}

void PlanetMap::_input(const Ref<InputEvent> &p_event) {
	if (p_event->is_action_pressed(ACTION_NAME)) {
		toggle();
		get_viewport()->set_input_as_handled();
		return;
	}
	if (is_visible() && p_event->is_action_pressed("pause")) { // Esc closes the map (not the menu behind it)
		toggle();
		get_viewport()->set_input_as_handled();
		return;
	}
	Ref<InputEventKey> key = p_event;
	if (key.is_valid() && key->is_pressed() && key->get_physical_keycode() == KEY_G) {
		globe_button->set_pressed(!globe_mode);
		get_viewport()->set_input_as_handled();
		return;
	}
	Ref<InputEventMouseButton> click = p_event;
	if (click.is_valid() && !over_the_pane(click->get_position())) {
		if (!click->is_pressed()) {
			dragging = false;
			globe->release();
		}
		return; // (a click on a button or the bars is theirs)
	}
	if (globe_mode && key.is_null() && globe->handle_input(p_event)) {
		get_viewport()->set_input_as_handled();
		return;
	}
	if (!is_visible()) {
		return;
	}
	Ref<InputEventMagnifyGesture> pinch = p_event;
	Ref<InputEventPanGesture> pan = p_event;
	Ref<InputEventMouseMotion> motion = p_event;
	if (click.is_valid()) {
		if (click->get_button_index() == MOUSE_BUTTON_WHEEL_UP && click->is_pressed()) {
			PlanetMapLog::line_every(String("input"), 0.1, "input: wheel up (zoom in)");
			zoom_at(click->get_position(), 1.25);
		} else if (click->get_button_index() == MOUSE_BUTTON_WHEEL_DOWN && click->is_pressed()) {
			PlanetMapLog::line_every(String("input"), 0.1, "input: wheel down (zoom out)");
			zoom_at(click->get_position(), 0.8);
		} else if (click->get_button_index() == MOUSE_BUTTON_LEFT) {
			if (dragging != click->is_pressed()) {
				PlanetMapLog::line(String("input: drag ") + (click->is_pressed() ? "starts" : "ends"));
			}
			dragging = click->is_pressed();
		}
		get_viewport()->set_input_as_handled();
	} else if (pinch.is_valid()) { // a pinch on a trackpad
		PlanetMapLog::line_every(String("input"), 0.1, vformat("input: pinch x%.2f", pinch->get_factor()));
		zoom_at(pinch->get_position(), CLAMP((double)pinch->get_factor(), 0.5, 2.0));
		get_viewport()->set_input_as_handled();
	} else if (pan.is_valid()) { // two fingers moving on a trackpad: the wheel
		PlanetMapLog::line_every(String("input"), 0.1, vformat("input: two fingers %.2f", pan->get_delta().y));
		zoom_at(get_viewport()->get_mouse_position(), std::pow(1.25, -(double)pan->get_delta().y));
		get_viewport()->set_input_as_handled();
	} else if (motion.is_valid() && dragging) {
		Vector2 size = visible_size();
		centre -= Vector2(motion->get_relative().x / view->get_size().x * size.x, motion->get_relative().y / view->get_size().y * size.y);
		clamp_centre();
		get_viewport()->set_input_as_handled();
	} else if (key.is_valid() && key->is_pressed()) {
		int code = key->get_physical_keycode();
		PlanetMapLog::line(String("input: key ") + OS::get_singleton()->get_keycode_string((Key)code));
		if (code == KEY_R) {
			go_home();
			if (globe_mode) {
				globe->look_at_direction(get_planet()->planet_position().normalized());
			}
			get_viewport()->set_input_as_handled();
		} else if (code == KEY_EQUAL || code == KEY_KP_ADD) { // the keyboard zooms too (+ and -)
			zoom_at(view->get_size() * 0.5, 1.25);
			get_viewport()->set_input_as_handled();
		} else if (code == KEY_MINUS || code == KEY_KP_SUBTRACT) {
			zoom_at(view->get_size() * 0.5, 0.8);
			get_viewport()->set_input_as_handled();
		} else if (code >= KEY_1 && code <= KEY_9 && code - KEY_1 < 11) {
			select_layer(LAYER_ORDER[code - KEY_1]); // (1 is the Atlas, then the extra modes)
			get_viewport()->set_input_as_handled();
		} else if (code == KEY_0 && 11 > 9) {
			select_layer(LAYER_ORDER[9]);
			get_viewport()->set_input_as_handled();
		}
	}
}

// Opens or closes the map (on the player's region).
void PlanetMap::toggle() {
	set_visible(!is_visible());
	Array names = PlanetChart::names();
	if (is_visible()) {
		PlanetMapLog::begin(vformat("layer %s, globe %s", names[layer_now], globe_mode ? "true" : "false"));
	} else {
		PlanetMapLog::end();
	}
	PlanetWorld *world = get_planet();
	if (world != nullptr && world->get_surface() != nullptr) {
		world->get_surface()->set_paused(is_visible() && started); // (not while the world is still loading)
	}
	if (is_visible()) {
		mouse_before = Input::get_singleton()->get_mouse_mode();
		Input::get_singleton()->set_mouse_mode(Input::MOUSE_MODE_VISIBLE);
		go_home();
		revealed = false; // (the loading note until the sharp picture of this view is ready)
		unsharp_time = 0.0;
		if (world != nullptr) {
			globe->look_at_direction(world->planet_position().normalized());
		}
	} else {
		Input::get_singleton()->set_mouse_mode(mouse_before);
		dragging = false;
	}
}

// Shows another layer: what was charted of it before comes back at once, the rest is charted again.
void PlanetMap::select_layer(int64_t p_layer) {
	if (p_layer == layer_now || warming) {
		return;
	}
	Array names = PlanetChart::names();
	PlanetMapLog::line(vformat("layer %s -> %s (picture kept: %s)", names[layer_now], names[p_layer], cache.has(p_layer) ? "true" : "false"));
	if (whole.is_valid()) {
		Dictionary kept;
		kept["whole"] = whole;
		kept["pass"] = whole_pass;
		cache[layer_now] = kept;
	}
	layer_now = (int)p_layer;
	modes->select(layer_position((int)p_layer));
	Dictionary kept = cache.get(p_layer, Dictionary());
	whole = Ref<ImageTexture>(kept.get("whole", Variant()));
	whole_pass = kept.get("pass", -1);
	detail.unref();
	detail_full = 0;
	revealed = false; // (a new layer: with the loading note until it is sharp)
	unsharp_time = 0.0;
	if (chart.is_valid()) {
		PlanetMapLog::line("chart given up (the layer changed)");
		chart->cancel();
		retired.push_back(chart); // its threads finish on their own; the picture is thrown away
		chart.unref();
	}
	if (started && whole_pass < last_pass()) {
		start_chart(whole_pass + 1);
	}
}

// The layers that show a moment (they are charted again as time moves on).
bool PlanetMap::is_moving(int p_layer) {
	return p_layer == PlanetChart::TEMPERATURE || p_layer == PlanetChart::CLOUDS || p_layer == PlanetChart::SATELLITE;
}

// The unit direction of the planet at the map's point `uv`.
Vector3 PlanetMap::direction_of(const Vector2 &p_uv) {
	double lat = (0.5 - p_uv.y) * PI_D;
	double lon = p_uv.x * TAU_D - PI_D;
	return Vector3(std::cos(lat) * std::cos(lon), std::sin(lat), std::cos(lat) * std::sin(lon));
}

Vector2 PlanetMap::uv_of(const Vector3 &p_dir) {
	double lon = std::atan2(p_dir.z, p_dir.x);
	double lat = std::asin(CLAMP((double)p_dir.y, -1.0, 1.0));
	return Vector2((lon + PI_D) / TAU_D, 0.5 - lat / PI_D);
}

// The globe turned: the map's centre follows where it looks (so the close chart is drawn there).
void PlanetMap::look_from_globe(const Vector3 &p_dir) {
	centre = Vector2((std::atan2(p_dir.z, p_dir.x) + PI_D) / TAU_D, 0.5 - std::asin(CLAMP((double)p_dir.y, -1.0, 1.0)) / PI_D);
	clamp_centre();
}

// The globe's wheel and pinch zoom the map (the same zoom as the flat one).
void PlanetMap::zoom_by(double p_factor) {
	zoom_now = CLAMP(zoom_now * p_factor, 1.0, MAX_ZOOM);
	clamp_centre();
}

// Shows the map as a small planet in 3D (on) or flat (off).
void PlanetMap::set_globe(bool p_on) {
	PlanetMapLog::line(String("globe ") + (p_on ? "on" : "off"));
	globe_mode = p_on;
	view->set_visible(!p_on);
	globe->set_visible(p_on);
	if (p_on) {
		globe->look_at_direction(direction_of(centre)); // (where the flat map looks)
	}
}

// Zooms to `zoom` (1: the whole planet) round the player.
void PlanetMap::show_zoom(double p_zoom) {
	if (!is_visible()) {
		toggle();
	}
	PlanetMapLog::line(vformat("show zoom %.1f on the player", p_zoom));
	zoom_now = CLAMP(p_zoom, 1.0, MAX_ZOOM);
	centre = where_is_the_player().get("uv", Vector2(0.5, 0.5));
	clamp_centre();
}

// Back to the player's region.
void PlanetMap::go_home() {
	PlanetMapLog::line("home: the player's region at the closest zoom");
	zoom_now = MAX_ZOOM;
	centre = where_is_the_player().get("uv", Vector2(0.5, 0.5));
	clamp_centre();
}

// True when the screen point is on the map itself (the flat view or the globe), not on the buttons.
bool PlanetMap::over_the_pane(const Vector2 &p_point) const {
	Control *pane_control = globe_mode ? (Control *)globe : view;
	return pane_control->get_global_rect().has_point(p_point);
}

// The size of what shows the map (the flat view, or the globe).
Vector2 PlanetMap::pane() const {
	Vector2 size = globe_mode ? globe->get_size() : view->get_size();
	return size.max(Vector2(64.0, 64.0));
}

// How many screen pixels one whole map width is at zoom 1: the whole planet just fits the view.
double PlanetMap::pixels_per_map() const {
	Vector2 size = pane();
	return std::min((double)size.x, size.y * 2.0);
}

// The part of the map the view shows, as fractions of the map (more than 1 high or wide when the map is smaller than the view: the bars round it).
Vector2 PlanetMap::visible_size() const {
	double pixels = pixels_per_map() * zoom_now;
	Vector2 size = pane();
	return Vector2(size.x / pixels, size.y / (pixels * 0.5));
}

void PlanetMap::clamp_centre() {
	centre.x = positive_mod_d(centre.x, 1.0); // the map wraps east-west
	// past a pole is the other side of the planet: the map goes on, upside down, half a turn on
	centre.y = positive_mod_d(centre.y + 0.5, 2.0) - 0.5;
}

// Zooms by `factor`, keeping the point of the map under the cursor where it is.
void PlanetMap::zoom_at(const Vector2 &p_mouse, double p_factor) {
	Vector2 local = p_mouse - view->get_global_position();
	Vector2 inside(CLAMP(local.x / view->get_size().x, 0.0, 1.0), CLAMP(local.y / view->get_size().y, 0.0, 1.0));
	Vector2 before = visible_size();
	Vector2 under = centre - before * 0.5 + inside * before;
	zoom_now = CLAMP(zoom_now * p_factor, 1.0, MAX_ZOOM);
	Vector2 after = visible_size();
	centre = under - inside * after + after * 0.5;
	clamp_centre();
}

// Starts charting the map on background threads (a no-op without a window, and the second time).
void PlanetMap::begin() {
	PlanetWorld *world = get_planet();
	if (started || world == nullptr || DisplayServer::get_singleton()->get_name() == "headless") {
		return;
	}
	started = true;
	tiles = PlanetMapTiles::create(world->get_noise());
	disk = PlanetMapCache::create(world->get_settings());
	tiles->set_disk(disk);
	if (world->has_signal("world_changed")) {
		world->connect("world_changed", Callable(this, "world_changed"));
	}
	if (warm_up) {
		warming = true;
		int count = (int)PlanetChart::names().size();
		for (int layer = 0; layer < count; layer++) {
			if (layer != layer_now) {
				warm_queue.push_back(layer);
			}
		}
		warm_total = std::max((int)warm_queue.size(), 1);
		PlanetMapLog::line("warm-up: the whole map is charted before it is shown");
	}
	start_chart(0);
}

// The finest picture of the layer: the layers that follow the clock are charted again as time moves and cost more per pixel, so they stop one pass
// short.
int PlanetMap::last_pass() const {
	if (is_moving(layer_now)) {
		return 4 - 2;
	}
	return 4 - 1;
}

void PlanetMap::start_chart(int p_pass_index) {
	PlanetWorld *world = get_planet();
	Ref<ImageTexture> kept;
	if (disk.is_valid()) {
		kept = disk->load_whole(layer_now, PASSES[p_pass_index].x);
	}
	if (kept.is_valid()) { // charted in an earlier run: no charting
		whole = kept;
		whole_pass = p_pass_index;
		chart.unref();
		if (!is_moving(layer_now)) {
			Dictionary entry;
			entry["whole"] = whole;
			entry["pass"] = whole_pass;
			cache[layer_now] = entry;
		}
		if (whole_pass < last_pass()) {
			start_chart(whole_pass + 1);
		}
		return;
	}
	chart.instantiate();
	chart->set_size(PASSES[p_pass_index]);
	chart->set_layer(layer_now);
	chart->set_use_gpu(true); // (the game is paused while the map is open: the GPU is free)
	chart->set_clock(world->get_clock()->copy());
	chart_time = world->get_clock()->get_time();
	chart_is_detail = false;
	chart_layer = layer_now;
	chart_ms = Time::get_singleton()->get_ticks_msec();
	Array names = PlanetChart::names();
	PlanetMapLog::line(vformat("chart whole pass %d: %d px, %s", p_pass_index, PASSES[p_pass_index].x, names[layer_now]));
	chart->start(world->get_noise());
}

void PlanetMap::_exit_tree() {
	if (tiles.is_valid()) {
		tiles->stop();
	}
	if (chart.is_valid()) {
		chart->cancel();
		chart->stop();
	}
	for (Ref<PlanetChart> &old : retired) {
		old->cancel();
		old->stop();
	}
}

void PlanetMap::_process(double p_delta) {
	PlanetWorld *world = get_planet();
	for (int index = (int)retired.size() - 1; index >= 0; index--) {
		if (retired[index]->finished()) {
			retired[index]->texture(); // joins the threads, the picture is not wanted
			retired.erase(retired.begin() + index);
		}
	}
	if (is_visible()) {
		drop_a_stale_chart();
		log_the_view();
		serve_the_tiles();
		if (!warming) {
			update_reveal(p_delta);
		}
		view->queue_redraw();
		if (globe_mode) {
			hover->set_text("Drag to turn the planet, wheel to come closer, G: the flat map");
			globe->set_chart(whole);
			set_the_globe_detail();
			globe->set_zoom(zoom_now);
			globe->set_sun(world->get_clock()->sun_in_body());
			Vector3 here;
			if (world != nullptr && world->target() != nullptr) {
				here = world->planet_position().normalized();
			}
			globe->set_pin(here);
		} else {
			hover->set_text(numbers_under_the_cursor());
		}
		time_bar->refresh();
		refresh_temperature(p_delta);
	}
	if (chart.is_valid()) {
		if (chart->finished()) {
			adopt_chart();
		} else if (is_visible() && whole_pass < 0) {
			caption->set_text(vformat("Charting the planet...  %d %%", (int)(100.0 * chart->progress())));
		}
	}
	// a close view is charted sharply as soon as there is a picture to look at: it does not wait for the whole planet's last passes (those go on
	// afterwards)
	if (warming) {
		drive_the_warm_up();
	}
	bool whole_is_drawing = chart.is_valid() && !chart_is_detail;
	bool by_tiles = tile_mode();
	if (is_visible() && !warming && !by_tiles && whole_pass >= 0 && (chart.is_null() || whole_is_drawing)) {
		maybe_chart_the_view(p_delta);
	}
}

// True when the flat map is drawn from tiles (close enough, and not the globe).
bool PlanetMap::tile_mode() const {
	return tiles.is_valid() && zoom_now >= TILE_ZOOM;
}

int64_t PlanetMap::tile_level() const {
	return PlanetMapTiles::level_for(pixels_per_map() * zoom_now);
}

// The part of the map the tiles are asked for: the view and a margin to pan in.
Rect2 PlanetMap::tile_view() const {
	Vector2 size = visible_size();
	if (warming) { // (the start: just what is seen)
		return Rect2(centre - size * 0.5, size);
	}
	return Rect2(centre - size * 0.6, size * 1.2);
}

// Asks for the tiles of the view and lets the chart in hand go on (a step of the tile cache).
void PlanetMap::serve_the_tiles() {
	if (tiles.is_null()) {
		return;
	}
	if (!tile_mode()) {
		tiles->ask(Rect2(), 0); // nothing wanted (the chart in hand is given up)
		return;
	}
	if (warming && whole_pass < last_pass()) {
		return; // (the whole planet's passes come first: nothing else uses the CPU)
	}
	tiles->set_layer(layer_now);
	tiles->set_clock(get_planet()->get_clock());
	tiles->ask(tile_view(), tile_level(), tile_view_beyond());
	tiles->step();
}

// Gives the globe the sharp picture it can have: the tiles round where it looks, put together (the same tiles as the flat map).
void PlanetMap::set_the_globe_detail() {
	if (!tile_mode()) {
		globe->set_detail(Ref<Texture2D>(), Rect2());
		return;
	}
	int64_t level = tile_level();
	Rect2 the_view = tile_view();
	int shown = tiles->share(the_view, level).x;
	if (shown == globe_tiles && level == globe_level && the_view.position.distance_to(globe_view.position) < the_view.size.x * 0.05) {
		return; // (nothing new since the last picture)
	}
	Dictionary made = tiles->compose(the_view, level);
	globe_tiles = shown;
	globe_level = (int)level;
	globe_view = the_view;
	if (made.is_empty()) {
		globe->set_detail(Ref<Texture2D>(), Rect2());
		return;
	}
	PlanetMapLog::line_every(String("globe"), 0.5, vformat("globe detail: %d tiles of level %d put together", shown, level));
	globe->set_detail(made["texture"], made["rect"]);
}

// The whole planet's picture under the view (the map wraps east-west).
void PlanetMap::draw_whole(const Rect2 &p_view, const Vector2 &p_size) {
	double rows = p_view.size.y; // (a view taller than the screen is the part beyond a pole, mirrored)
	double drawn = 0.0; // the map goes round east-west: its copies are drawn until the view is full
	while (drawn < p_size.x - 0.00001) {
		double first_u = positive_mod_d(p_view.position.x + drawn, 1.0);
		double width = std::min((double)p_size.x - drawn, 1.0 - first_u);
		draw_part(whole, Rect2(0.0, 0.0, 1.0, 1.0), Rect2(first_u, p_view.position.y, width, rows), drawn);
		drawn += width;
	}
}

// The warm-up: the whole planet's passes, then the sharp close view where the player stands, then a first picture of every other layer, one after the
// other; then the map is shown.
void PlanetMap::drive_the_warm_up() {
	if (chart.is_valid()) {
		return;
	}
	Vector2 size = visible_size();
	Rect2 the_view(centre - size * 0.5, size);
	if (whole_pass < last_pass()) {
		start_chart(whole_pass + 1);
	} else if (tile_mode() && !tiles->covers(the_view, tile_level())) {
		warm_close = 1; // (the tiles of the start view are being charted)
		return;
	} else if (!tile_mode() && warm_close == 0 && !sharply_covered(the_view)) {
		warm_close = 1;
		chart_close_view(the_view, size);
	} else if (!warm_queue.empty()) {
		int next = warm_queue.front();
		warm_queue.erase(warm_queue.begin());
		start_warm_layer(next);
	} else {
		warming = false;
		revealed = true;
		PlanetMapLog::line("warm-up done: the map is ready");
	}
}

// Charts a first (1024 px) picture of `layer` for later, without showing it.
void PlanetMap::start_warm_layer(int p_layer) {
	PlanetWorld *world = get_planet();
	Ref<ImageTexture> kept;
	if (disk.is_valid()) {
		kept = disk->load_whole(p_layer, PASSES[2].x);
	}
	if (kept.is_valid()) {
		Dictionary entry;
		entry["whole"] = kept;
		entry["pass"] = 2;
		cache[p_layer] = entry;
		warm_layers_done += 1;
		return;
	}
	chart.instantiate();
	chart->set_layer(p_layer);
	chart->set_size(PASSES[2]);
	chart->set_use_gpu(true);
	chart->set_clock(world->get_clock()->copy());
	chart_layer = p_layer;
	chart_is_detail = false;
	chart_ms = Time::get_singleton()->get_ticks_msec();
	Array names = PlanetChart::names();
	PlanetMapLog::line(vformat("warm-up: first picture of the %s layer", names[p_layer]));
	chart->start(world->get_noise());
}

// How far the warm-up is (0..1): the whole passes, the close view, the other layers.
double PlanetMap::warm_progress() const {
	double whole_share = CLAMP((double)(whole_pass + 1) / (double)(last_pass() + 1), 0.0, 1.0) * 0.4;
	double close = 0.0;
	if (tile_mode()) {
		Vector2i have = tiles->share(tile_view(), tile_level());
		close = 0.3 * (double)have.x / (double)std::max(have.y, 1);
	} else if (warm_close > 0) {
		close = 0.1;
		if (detail.is_valid()) {
			close = detail_preview ? 0.2 : 0.3;
		}
	}
	return whole_share + close + (double)warm_layers_done / (double)warm_total * 0.3;
}

void PlanetMap::log_the_view() {
	Vector3 now(zoom_now, centre.x, centre.y);
	if (!now.is_equal_approx(logged_view)) {
		PlanetMapLog::line_every(String("view"), 0.25, vformat("view: zoom %.1f, centre %.4f, %.4f", zoom_now, now.y, now.z));
		logged_view = now;
	}
}

// The temperature and cloud layers show a moment: when time has moved on, they are charted again (the coarse chart only, a second or so), so they
// follow the seasons, the day and the winds.
void PlanetMap::refresh_temperature(double p_delta) {
	if (!is_moving(layer_now) || chart.is_valid() || whole_pass < 0) {
		return;
	}
	Ref<PlanetClock> clock = get_planet()->get_clock();
	refresh_wait -= p_delta;
	double moved = std::abs(clock->get_time() - drawn_at);
	if (refresh_wait > 0.0 || moved < clock->get_day_seconds() * 0.04) {
		return;
	}
	refresh_wait = 0.4;
	if (tiles.is_valid()) {
		tiles->forget(layer_now);
	}
	Array names = PlanetChart::names();
	PlanetMapLog::line(vformat("time moved: charting the %s layer again", names[layer_now]));
	whole_pass = -1;
	detail.unref();
	detail_full = 0;
	start_chart(0);
}

void PlanetMap::adopt_chart() {
	Array names = PlanetChart::names();
	if (!chart_is_detail && chart_layer != layer_now) { // a layer charted ahead (the warm-up)
		Ref<ImageTexture> ahead = chart->texture();
		Dictionary entry;
		entry["whole"] = ahead;
		entry["pass"] = 2;
		cache[chart_layer] = entry;
		if (disk.is_valid()) {
			disk->save_whole(chart_layer, PASSES[2].x, ahead);
		}
		PlanetMapLog::line(vformat("chart done: first picture of the %s layer in %d ms", names[chart_layer], (int64_t)(Time::get_singleton()->get_ticks_msec() - chart_ms)));
		chart.unref();
		warm_layers_done += 1;
		return;
	}
	Ref<ImageTexture> texture = chart->texture();
	PlanetMapLog::line(vformat("chart done: %s in %d ms", chart_is_detail ? String("close view") : vformat("whole pass %d", whole_pass + 1), (int64_t)(Time::get_singleton()->get_ticks_msec() - chart_ms)));
	if (chart_is_detail) {
		detail = texture;
		detail_preview = detail_full > 0;
		detail_rect = chart->get_rect();
		Rect2 rect = chart->get_rect();
		int done_width = chart->get_size().x;
		chart.unref();
		if (detail_full > 0) { // a preview is up: now a better one over the same region
			int across = detail_full;
			if (done_width < MIDDLE_DETAIL && across > MIDDLE_DETAIL) {
				start_detail(rect, MIDDLE_DETAIL); // (still a preview: the sharp one follows)
				return;
			}
			detail_full = 0;
			start_detail(rect, across);
			return;
		}
		if (whole_pass < last_pass()) {
			start_chart(whole_pass + 1); // the passes the close view interrupted go on
		}
		return;
	}
	whole = texture;
	whole_pass += 1;
	if (disk.is_valid() && !is_moving(layer_now)) {
		disk->save_whole(layer_now, PASSES[whole_pass].x, texture);
	}
	drawn_at = chart_time;
	if (!is_moving(layer_now)) {
		Dictionary entry;
		entry["whole"] = whole;
		entry["pass"] = whole_pass;
		cache[layer_now] = entry;
	}
	chart.unref();
	if (whole_pass < last_pass()) {
		start_chart(whole_pass + 1); // the fine chart replaces the coarse one when it is done
	}
}

// A close chart of a place the view has left is no use: it is given up (the threads are free for the next view).
void PlanetMap::drop_a_stale_chart() {
	if (chart.is_null() || !chart_is_detail) {
		return;
	}
	Vector2 size = visible_size();
	if (chart->get_rect().encloses(Rect2(centre - size * 0.5, size))) {
		return;
	}
	PlanetMapLog::line("close chart given up: the view moved out of it");
	chart->cancel();
	retired.push_back(chart);
	chart.unref();
	detail_full = 0;
}

// When the view has stayed still on a close region, draws that region sharply.
void PlanetMap::maybe_chart_the_view(double p_delta) {
	Vector2 size = visible_size();
	Rect2 the_view(centre - size * 0.5, size);
	if (the_view.is_equal_approx(last_view)) {
		still += p_delta;
	} else {
		still = 0.0;
		last_view = the_view;
	}
	// (the slow layers, drawn again as time moves, wait for a closer look)
	double close = last_pass() < 4 - 1 ? 2.5 : 1.4;
	if (still < 0.5 || zoom_now < close || sharply_covered(the_view)) {
		return;
	}
	if (chart.is_valid() && !chart_is_detail && whole_pass + 1 < FIRST_BIG_PASS) {
		return; // the short whole passes (under half a second) finish first: a zoom out shows them
	}
	chart_close_view(the_view, size);
}

// Starts the close chart of `view` (a margin round it to pan in): false when the view reaches over a pole (the whole planet's chart will do).
bool PlanetMap::chart_close_view(const Rect2 &p_view, const Vector2 &p_size) {
	Rect2 rect(p_view.position - p_size * 0.25, p_size * 1.5);
	// the margin stops at the poles (east-west the map wraps, so x may run past 0 and 1)
	double top = std::max((double)rect.position.y, 0.0);
	rect = Rect2(rect.position.x, top, rect.size.x, std::min((double)rect.get_end().y, 1.0) - top);
	if (!rect.encloses(p_view)) {
		return false;
	}
	PlanetMapLog::line(vformat("view still at zoom %.1f: charting it (%s)", zoom_now, chart.is_valid() ? "a pass gives way" : "free"));
	if (chart.is_valid()) { // a whole planet pass still drawing gives way to the close view
		chart->cancel();
		retired.push_back(chart);
	}
	// about one chart pixel and a quarter for every screen pixel of the 1.5 times wider chart, so a close zoom stays sharp; a quarter of that size
	// comes first (a sixteenth of the time) so the view is better than the whole planet's picture within a second
	int across = CLAMP((int)(pane().x * 1.5 * 1.25), DETAIL_MIN, DETAIL_MAX);
	if (warming) { // (nobody looks at a preview behind a black screen: straight to the sharp one)
		detail_full = 0;
		start_detail(rect, across);
		return true;
	}
	detail_full = across;
	start_detail(rect, std::max(across / 4, 256));
	return true;
}

// Charts `rect` (fractions of the map) `across` pixels wide, the close view.
void PlanetMap::start_detail(const Rect2 &p_rect, int p_across) {
	PlanetWorld *world = get_planet();
	chart.instantiate();
	chart->set_layer(layer_now);
	chart->set_clock(world->get_clock()->copy());
	chart->set_rect(p_rect);
	chart->set_size(Vector2i(p_across, (int)(p_across * p_rect.size.y / p_rect.size.x * 0.5)));
	chart_is_detail = true;
	chart_ms = Time::get_singleton()->get_ticks_msec();
	Array names = PlanetChart::names();
	PlanetMapLog::line(vformat("chart close view (%s): %dx%d, rect %s, %s", detail_full > 0 ? "preview" : "sharp", chart->get_size().x, chart->get_size().y, String(Variant(p_rect)), names[layer_now]));
	chart->start(world->get_noise());
}

bool PlanetMap::covered_by_detail(const Rect2 &p_view) const {
	return detail.is_valid() && detail_rect.encloses(p_view);
}

// True when the close chart covers the view AND has about a pixel for every screen pixel (one made at a lower zoom contains the view too, but would
// only be a blur).
bool PlanetMap::sharply_covered(const Rect2 &p_view) const {
	if (!covered_by_detail(p_view)) {
		return false;
	}
	double chart_pixels = (double)detail->get_width() / detail_rect.size.x;
	double screen_pixels = pane().x / p_view.size.x;
	return chart_pixels >= screen_pixels * 0.7;
}

// The numbers of the planet under the mouse, as one line of text.
String PlanetMap::numbers_under_the_cursor() const {
	Vector2 local = view->get_local_mouse_position();
	if (local.x < 0.0 || local.y < 0.0 || local.x > view->get_size().x || local.y > view->get_size().y) {
		return "";
	}
	Vector2 size = visible_size();
	Vector2 uv(positive_mod_d(centre.x - size.x * 0.5 + local.x / view->get_size().x * size.x, 1.0), centre.y - size.y * 0.5 + local.y / view->get_size().y * size.y);
	if (uv.y < 0.0) { // beyond the north pole: the other side of the planet
		uv = Vector2(positive_mod_d(uv.x + 0.5, 1.0), -uv.y);
	} else if (uv.y > 1.0) {
		uv = Vector2(positive_mod_d(uv.x + 0.5, 1.0), 2.0 - uv.y);
	}
	uv.y = CLAMP((double)uv.y, 0.0, 1.0);
	return PlanetMapOverlay::describe(get_planet()->get_noise(), uv);
}

// The player's place on the map: {"uv", "lat", "lon", "heading"} (empty without a player).
Dictionary PlanetMap::where_is_the_player() const {
	PlanetWorld *world = get_planet();
	if (world == nullptr || world->target() == nullptr) {
		return Dictionary();
	}
	Vector3 here = world->planet_position().normalized();
	Vector3 east = Vector3(-here.z, 0.0, here.x).normalized();
	Vector3 north = east.cross(here);
	Vector2 heading(0.0, -1.0);
	Camera3D *camera = get_viewport()->get_camera_3d();
	if (camera != nullptr) {
		Vector3 forward = world->get_frame()->get_rot().inverse().xform(-camera->get_global_basis().get_column(2));
		heading = Vector2(forward.dot(east), -forward.dot(north)).normalized();
	}
	Dictionary result;
	result["uv"] = uv_of(here);
	result["lat"] = Math::rad_to_deg(std::asin((double)here.y));
	result["lon"] = Math::rad_to_deg(std::atan2(here.z, here.x));
	result["heading"] = heading;
	return result;
}

// Where a point of the map (fractions) is in the view (off the view when out of it).
Vector2 PlanetMap::on_screen(const Vector2 &p_uv) const {
	Vector2 size = visible_size();
	double left = centre.x - size.x * 0.5;
	double across = positive_mod_d(p_uv.x - left, 1.0);
	double down = p_uv.y - (centre.y - size.y * 0.5);
	if (across > size.x || down < 0.0 || down > size.y) {
		return Vector2(-1.0, -1.0);
	}
	return Vector2(across / size.x * view->get_size().x, down / size.y * view->get_size().y);
}

// True when the picture is as sharp as it will get for this view: the close chart (not its quick preview) covers the view, or every pass of the whole
// planet is done.
bool PlanetMap::sharp_enough(const Rect2 &p_view) {
	if (tile_mode()) {
		return tiles->covers(p_view, tile_level());
	}
	if (sharply_covered(p_view) && !detail_preview) {
		return true;
	}
	if (whole.is_null() || zoom_now >= 2.5) {
		return false;
	}
	// the whole planet's picture is sharp enough once it has about half a pixel for every screen pixel (a middle pass does at far zooms: no waiting for
	// the last, slowest one)
	double screen_width = pixels_per_map() * zoom_now;
	return (double)whole->get_width() >= screen_width * 0.4 || whole_pass >= last_pass();
}

// Lifts the note when the picture is sharp enough (or, for a view the close chart cannot cover such as one over a pole, once the whole planet is
// charted and a few seconds have passed).
void PlanetMap::update_reveal(double p_delta) {
	Vector2 size = visible_size();
	bool all_done = whole.is_valid() && whole_pass >= last_pass();
	if (sharp_enough(Rect2(centre - size * 0.5, size))) {
		if (!revealed) {
			PlanetMapLog::line("the picture is sharp: the loading note is gone");
		}
		revealed = true;
		unsharp_time = 0.0;
		return;
	}
	if (revealed) {
		PlanetMapLog::line(vformat("the view is not sharp: the loading note is back (zoom %.1f)", zoom_now));
	}
	revealed = false; // (zooming in on a place only charted blurrily brings the note back)
	unsharp_time += p_delta;
	if (all_done && unsharp_time > 6.0) {
		PlanetMapLog::line("6 s unsharp with every pass done: the note is dropped");
		revealed = true;
	}
}

void PlanetMap::draw_view() {
	PlanetWorld *world = get_planet();
	if (warming) { // the map is not shown until it is all charted: black and how far it is
		view->draw_rect(Rect2(Vector2(), view->get_size()), Color(0, 0, 0, 1));
		Ref<Font> font = ThemeDB::get_singleton()->get_fallback_font();
		String text = vformat("Charting the planet...  %d %%", (int)(100.0 * warm_progress()));
		double width = font->get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 22).x;
		view->draw_string(font, (view->get_size() - Vector2(width, -8.0)) * 0.5, text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 22, Color(0.85f, 0.9f, 1.0f));
		return;
	}
	Vector2 size = visible_size();
	Rect2 the_view(centre - size * 0.5, size);
	view->draw_rect(Rect2(Vector2(), view->get_size()), Color(0.02f, 0.05f, 0.12f));
	draw_beyond_the_poles(the_view, size);
	if (tile_mode() && whole.is_valid()) {
		draw_whole(the_view, size);
		tiles->draw(view, the_view, size, tile_level());
	} else if (covered_by_detail(the_view)) {
		draw_part(detail, detail_rect, the_view);
	} else if (whole.is_valid()) {
		draw_whole(the_view, size);
	}
	Callable on_screen_call = Callable(this, "on_screen_point");
	PlanetMapOverlay::draw_grid(view, zoom_now, centre, visible_size(), on_screen_call);
	draw_names();
	PlanetMapOverlay::draw_legend(view, layer_now, world->get_noise()->get_relief());
	if (layer_now == PlanetChart::ATLAS) { // the atlas is an old map: a burnt frame round it
		PlanetMapOverlay::draw_parchment_frame(view);
	}
	if (!revealed) {
		PlanetMapOverlay::draw_loading(view, chart.is_valid() ? chart->progress() : -1.0);
	}
	Dictionary player = where_is_the_player();
	if (player.is_empty()) {
		return;
	}
	Vector2 spot = on_screen(player["uv"]);
	if (spot.x >= 0.0) {
		PlanetMapOverlay::draw_arrow(view, spot, player["heading"]);
	}
	if (whole.is_valid()) {
		double lat = player["lat"];
		double lon = player["lon"];
		Vector3 here = world->planet_position().normalized();
		double hour = world->get_clock()->local_hour(here);
		String format = String::utf8("%.1f\xC2\xB0 %s  %.1f\xC2\xB0 %s    altitude %d m    %02d:%02d    %s    [wheel, pinch, + -] zoom  [drag] move  [R] my region  [M] close");
		caption->set_text(vformat(format, std::abs(lat), lat >= 0.0 ? "N" : "S", std::abs(lon), lon >= 0.0 ? "E" : "W", (int64_t)std::round(world->altitude()), (int)hour,
				(int)((hour - std::floor(hour)) * 60.0), world->season_text() + "  " + world->get_weather_text()));
	}
}

// Beyond the north and south edges the map goes on: over a pole is the other side of the planet, 180 degrees of longitude away, seen upside down.
// The picture is drawn again half a map to the east and mirrored in the edge it goes over.
void PlanetMap::draw_beyond_the_poles(const Rect2 &p_view, const Vector2 &p_size) {
	for (double edge : { 0.0, 1.0 }) {
		double reach = edge == 0.0 ? -p_view.position.y : p_view.get_end().y - 1.0; // how far beyond the edge
		if (reach <= 0.0 || whole.is_null()) {
			continue;
		}
		// the part of the map that shows there, mirrored: as deep into the map as the view goes beyond
		double top = edge == 0.0 ? 0.0 : 1.0 - reach;
		double least = std::min(top, (double)p_view.position.y);
		Rect2 shifted(p_view.position.x + 0.5, least, p_size.x, std::max((double)p_size.y, reach + std::abs(top - least)));
		double at = (edge - p_view.position.y) / p_size.y * view->get_size().y; // (the edge on the screen)
		view->draw_set_transform(Vector2(0.0, 2.0 * at), 0.0, Vector2(1.0, -1.0));
		draw_whole(shifted, p_size);
		if (tile_mode()) {
			tiles->draw(view, Rect2(p_view.position + Vector2(0.5, 0.0), p_size), p_size, tile_level(), shifted);
		}
		view->draw_set_transform(Vector2(), 0.0, Vector2(1, 1));
	}
}

// The parts beyond the poles that tiles are needed for (as they are in the map).
Array PlanetMap::tile_view_beyond() const {
	Vector2 size = visible_size();
	Rect2 the_view(centre - size * 0.5, size);
	Array out;
	if (the_view.position.y < 0.0) {
		out.append(Rect2(the_view.position.x + 0.5 - size.x * 0.1, 0.0, size.x * 1.2, std::min(-the_view.position.y * 1.2, 1.0)));
	}
	if (the_view.get_end().y > 1.0) {
		double depth = std::min((the_view.get_end().y - 1.0) * 1.2, 1.0);
		out.append(Rect2(the_view.position.x + 0.5 - size.x * 0.1, 1.0 - depth, size.x * 1.2, depth));
	}
	return out;
}

// Draws the part `wanted` (map fractions) of `texture`, which shows `covers` (map fractions), where it belongs in the view (`offset_u`: how far into
// the view this part starts, in map fractions).
void PlanetMap::draw_part(const Ref<ImageTexture> &p_texture, const Rect2 &p_covers, const Rect2 &p_wanted, double p_offset_u) {
	Vector2 size = visible_size();
	Rect2 part = p_wanted.intersection(p_covers);
	if (part.size.x <= 0.0 || part.size.y <= 0.0) {
		return;
	}
	Vector2 tex = Vector2(p_texture->get_size());
	Rect2 source((part.position - p_covers.position) / p_covers.size * tex, part.size / p_covers.size * tex);
	double view_top = centre.y - size.y * 0.5;
	Rect2 dest((p_offset_u + part.position.x - p_wanted.position.x) / size.x * view->get_size().x, (part.position.y - view_top) / size.y * view->get_size().y,
			part.size.x / size.x * view->get_size().x, part.size.y / size.y * view->get_size().y);
	view->draw_texture_rect_region(p_texture, dest, source);
}

// Something in the world changed around `area` (map fractions: x east, y south): the tiles that touch it are forgotten and charted again when looked
// at, and the whole-planet pictures (which showed the old state) are charted again behind the current one.
void PlanetMap::world_changed(const Rect2 &p_area) {
	if (tiles.is_null()) {
		return;
	}
	int64_t gone = tiles->invalidate(p_area);
	if (disk.is_valid()) {
		disk->forget_whole();
	}
	cache.clear();
	PlanetMapLog::line(vformat("the world changed at %s: %d tiles forgotten, the whole pictures again", String(Variant(p_area)), gone));
	if (started && !warming) {
		if (chart.is_valid()) {
			chart->cancel();
			retired.push_back(chart);
		}
		whole_pass = -1;
		start_chart(0);
	}
}

// The same, for a place on the planet: the unit direction, the radius of the change in metres.
void PlanetMap::world_changed_at(const Vector3 &p_direction, double p_radius_metres) {
	Vector2 uv = uv_of(p_direction.normalized());
	double radius = get_planet()->get_settings()->get_radius();
	Vector2 half(p_radius_metres / (radius * TAU_D), p_radius_metres / (radius * PI_D));
	world_changed(Rect2(uv - half, half * 2.0));
}

// The names of the seas and lands: built on the first look, drawn while the view is far.
void PlanetMap::draw_names() {
	PlanetWorld *world = get_planet();
	if (zoom_now > 6.0 || world == nullptr || world->get_noise().is_null()) {
		return;
	}
	if (labels.is_null()) {
		labels.instantiate();
		labels->build(world->get_noise());
	}
	PlanetMapOverlay::draw_names(view, labels, zoom_now, Callable(this, "on_screen_point"), layer_now == PlanetChart::ATLAS);
}

// Opens the map as the 3D globe (or the flat map).
void PlanetMap::show_globe(bool p_on) {
	if (!is_visible()) {
		toggle();
	}
	globe_button->set_pressed(p_on);
}
