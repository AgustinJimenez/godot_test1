#include "planet_menu_native.h"

#include "planet_clock_native.h"
#include "planet_map_ui_native.h"
#include "planet_star_native.h"
#include "universe_native.h"

#include <godot_cpp/classes/button.hpp>
#include <godot_cpp/classes/center_container.hpp>
#include <godot_cpp/classes/color_rect.hpp>
#include <godot_cpp/classes/h_box_container.hpp>
#include <godot_cpp/classes/h_separator.hpp>
#include <godot_cpp/classes/input.hpp>
#include <godot_cpp/classes/os.hpp>
#include <godot_cpp/classes/resource_loader.hpp>
#include <godot_cpp/classes/scene_tree.hpp>
#include <godot_cpp/classes/script.hpp>
#include <godot_cpp/classes/time.hpp>
#include <godot_cpp/variant/utility_functions.hpp>

#include <algorithm>
#include <cmath>

using namespace godot;

// the settings the next planet is made with, and the moment of a save to go back to (kept in plain objects: an engine type must not be built
// before the library is initialised)
struct MenuState {
	Ref<PlanetSettings> pending;
	Dictionary pending_state;
	bool requested = false;
};
static MenuState *menu_state() {
	static MenuState *state = new MenuState();
	return state;
}

static String times_sign() {
	return String::utf8("\xC3\x97");
}

// ---- PlanetMenu ----

void PlanetMenu::_bind_methods() {
	ClassDB::bind_static_method("PlanetMenu", D_METHOD("get_pending"), &PlanetMenu::get_pending);
	ClassDB::bind_static_method("PlanetMenu", D_METHOD("set_pending", "settings"), &PlanetMenu::set_pending);
	ClassDB::bind_static_method("PlanetMenu", D_METHOD("get_pending_state"), &PlanetMenu::get_pending_state);
	ClassDB::bind_static_method("PlanetMenu", D_METHOD("set_pending_state", "state"), &PlanetMenu::set_pending_state);
	ClassDB::bind_method(D_METHOD("setup", "planet"), &PlanetMenu::setup);
	ClassDB::bind_method(D_METHOD("refresh"), &PlanetMenu::refresh);
	ClassDB::bind_method(D_METHOD("set_rate", "rate"), &PlanetMenu::set_rate);
	ClassDB::bind_method(D_METHOD("jump", "step"), &PlanetMenu::jump);
	ClassDB::bind_method(D_METHOD("hour_changed", "hours"), &PlanetMenu::hour_changed);
	ClassDB::bind_method(D_METHOD("year_changed", "share"), &PlanetMenu::year_changed);
	ClassDB::bind_method(D_METHOD("weather_picked", "index"), &PlanetMenu::weather_picked);
	ClassDB::bind_method(D_METHOD("clouds_toggled", "shown"), &PlanetMenu::clouds_toggled);
	ClassDB::bind_method(D_METHOD("fog_toggled", "shown"), &PlanetMenu::fog_toggled);
	ClassDB::bind_method(D_METHOD("make_this_planet"), &PlanetMenu::make_this_planet);
	ClassDB::bind_method(D_METHOD("make_random_planet"), &PlanetMenu::make_random_planet);
	ClassDB::bind_method(D_METHOD("save_here"), &PlanetMenu::save_here);
	ClassDB::bind_method(D_METHOD("open_selected"), &PlanetMenu::open_selected);
	ClassDB::bind_method(D_METHOD("delete_selected"), &PlanetMenu::delete_selected);
	ClassDB::bind_method(D_METHOD("main_menu"), &PlanetMenu::main_menu);
	ClassDB::bind_method(D_METHOD("open_map"), &PlanetMenu::open_map);
}

Ref<PlanetSettings> PlanetMenu::get_pending() {
	return menu_state()->pending;
}
void PlanetMenu::set_pending(const Ref<PlanetSettings> &p_settings) {
	menu_state()->pending = p_settings;
}
Dictionary PlanetMenu::get_pending_state() {
	return menu_state()->pending_state;
}
void PlanetMenu::set_pending_state(const Dictionary &p_state) {
	menu_state()->pending_state = p_state;
}

Label *PlanetMenu::make_label(const String &p_text) {
	Label *label = memnew(Label);
	label->set_text(p_text);
	add_child(label);
	return label;
}

Button *PlanetMenu::add_button(Node *p_parent, const String &p_text, const StringName &p_method, const Variant &p_argument) {
	Button *button = memnew(Button);
	button->set_text(p_text);
	button->set_h_size_flags(Control::SIZE_EXPAND_FILL);
	Callable action(this, p_method);
	button->connect("pressed", p_argument.get_type() == Variant::NIL ? action : action.bind(p_argument));
	p_parent->add_child(button);
	return button;
}

void PlanetMenu::setup(Object *p_planet) {
	planet_id = p_planet->get_instance_id();
	set_custom_minimum_size(Vector2(420, 0));
	info = make_label("");
	star_info = make_label(star_text());
	add_time_rows();
	add_weather_row();
	add_new_planet_rows();
	add_save_rows();
	Button *main_button = memnew(Button);
	main_button->set_text("Main menu (saved universes, a new one)");
	main_button->connect("pressed", Callable(this, "main_menu"));
	add_child(main_button);
	Button *map_button = memnew(Button);
	map_button->set_text("Open the map (M)");
	map_button->connect("pressed", Callable(this, "open_map"));
	add_child(map_button);
}

void PlanetMenu::main_menu() {
	menu_state()->requested = true;
	get_tree()->set_pause(false);
	get_tree()->reload_current_scene();
}

void PlanetMenu::open_map() {
	PlanetMap *map = Object::cast_to<PlanetMap>((Object *)planet()->get("map"));
	map->toggle();
	map->show_zoom(PlanetMap::MAX_ZOOM);
}

void PlanetMenu::refresh() {
	Ref<PlanetSettings> settings = planet()->get("settings");
	seed_field->set_text(String::num_int64(settings->get_world_seed()));
	radius_field->set_text(String::num_int64((int64_t)settings->get_radius()));
	weather->select((int)((int64_t)planet()->get("weather_override") + 1));
	Object *atmosphere = planet()->get("atmosphere");
	clouds->set_pressed_no_signal(!(bool)atmosphere->get("clouds_hidden"));
	fog->set_pressed_no_signal(!(bool)atmosphere->get("fog_hidden"));
	fill_saves();
	sync_values();
}

void PlanetMenu::_process(double) {
	if (is_visible_in_tree() && planet() != nullptr) {
		sync_values();
	}
}

void PlanetMenu::sync_values() {
	Object *world = planet();
	Vector3 here = ((Vector3)world->call("planet_position")).normalized();
	Ref<PlanetClock> clock = world->get("clock");
	double hour = clock->local_hour(here);
	info->set_text(vformat("%02d:%02d   %s\n%s", (int)hour, (int)((hour - std::floor(hour)) * 60.0), String(world->call("season_text")), String(world->get("weather_text"))));
	hour_slider->set_value_no_signal(hour);
	year_slider->set_value_no_signal(clock->year_share());
	double time_rate = world->get("time_rate");
	String rate = time_rate == 0.0 ? String("paused") : vformat("%d", (int)time_rate) + times_sign();
	rate_label->set_text(vformat("Speed: %s   (a day lasts %d s at 1", rate, (int)clock->get_day_seconds()) + times_sign() + ")");
}

// The star and the orbit in a few lines (read-only: travel to other planets comes later).
String PlanetMenu::star_text() const {
	Ref<PlanetSettings> settings = planet()->get("settings");
	Ref<Star> star = Star::from_mass(settings->get_star_mass());
	String text = vformat("Star: class %s, %.2f solar masses, %d K, %.2f times the Earth's light here", star->get_spectral_class(), star->get_mass(), (int)star->get_temperature(), settings->get_insolation());
	if (settings->get_eccentricity() > 0.005) {
		text += vformat("\nOrbit: eccentricity %.2f (the light varies %d%% over the year)", settings->get_eccentricity(), (int)std::round(400.0 * settings->get_eccentricity()));
	}
	if (settings->get_universe_seed() != 0) {
		text += vformat("\nUniverse %d, system %d, planet %d", settings->get_universe_seed(), settings->get_universe_system(), settings->get_universe_planet() + 1);
	}
	return text;
}

void PlanetMenu::add_time_rows() {
	rate_label = make_label("");
	HBoxContainer *row = memnew(HBoxContainer);
	add_child(row);
	for (int rate : { -1000, -100, -10, -1, 0, 1, 10, 100, 1000 }) {
		add_button(row, rate == 0 ? String("pause") : vformat("%d", rate) + times_sign(), "set_rate", (double)rate);
	}
	HBoxContainer *jumps = memnew(HBoxContainer);
	add_child(jumps);
	add_button(jumps, "-1/8 year", "jump", -0.125);
	add_button(jumps, "-day", "jump", -1.0);
	add_button(jumps, "+day", "jump", 1.0);
	add_button(jumps, "+1/8 year", "jump", 0.125);
	make_label("Hour of the day");
	hour_slider = memnew(HSlider);
	hour_slider->set_max(24.0);
	hour_slider->set_step(0.05);
	hour_slider->connect("value_changed", Callable(this, "hour_changed"));
	add_child(hour_slider);
	make_label("Day of the year (0: northern spring equinox)");
	year_slider = memnew(HSlider);
	year_slider->set_max(1.0);
	year_slider->set_step(0.002);
	year_slider->connect("value_changed", Callable(this, "year_changed"));
	add_child(year_slider);
}

void PlanetMenu::set_rate(double p_rate) {
	planet()->set("time_rate", p_rate);
}

// a day, or a share of the year
void PlanetMenu::jump(double p_step) {
	Ref<PlanetClock> clock = planet()->get("clock");
	planet()->call("jump_time", std::abs(p_step) >= 1.0 ? p_step : p_step * clock->get_year_days());
}

void PlanetMenu::hour_changed(double p_hours) {
	if (hour_slider->get_global_rect().has_point(hour_slider->get_global_mouse_position())) {
		planet()->call("set_hour", p_hours);
	}
}

void PlanetMenu::year_changed(double p_share) {
	if (year_slider->get_global_rect().has_point(year_slider->get_global_mouse_position())) {
		planet()->call("set_year_share", p_share);
	}
}

void PlanetMenu::add_weather_row() {
	make_label("Weather");
	weather = memnew(OptionButton);
	weather->add_item("Follow the planet's climate");
	Ref<Script> weather_script = ResourceLoader::get_singleton()->load("res://systems/world_gen/world_weather.gd");
	Dictionary states = weather_script->get_script_constant_map()["State"];
	Array names = states.keys();
	for (int i = 0; i < names.size(); i++) {
		weather->add_item("Force " + String(names[i]).to_lower());
	}
	weather->connect("item_selected", Callable(this, "weather_picked"));
	add_child(weather);
	clouds = memnew(CheckBox);
	clouds->set_text("Show the clouds");
	clouds->set_pressed(true);
	clouds->connect("toggled", Callable(this, "clouds_toggled"));
	add_child(clouds);
	fog = memnew(CheckBox);
	fog->set_text("Show the fog");
	fog->set_pressed(true);
	fog->connect("toggled", Callable(this, "fog_toggled"));
	add_child(fog);
}

void PlanetMenu::weather_picked(int64_t p_index) {
	planet()->set("weather_override", p_index - 1);
}

void PlanetMenu::clouds_toggled(bool p_shown) {
	Object *atmosphere = planet()->get("atmosphere");
	atmosphere->set("clouds_hidden", !p_shown);
}

void PlanetMenu::fog_toggled(bool p_shown) {
	Object *atmosphere = planet()->get("atmosphere");
	atmosphere->set("fog_hidden", !p_shown);
}

void PlanetMenu::add_new_planet_rows() {
	make_label("A new planet (the scene is reloaded)");
	HBoxContainer *row = memnew(HBoxContainer);
	add_child(row);
	Label *seed_label = memnew(Label);
	seed_label->set_text("seed");
	row->add_child(seed_label);
	seed_field = memnew(LineEdit);
	seed_field->set_h_size_flags(Control::SIZE_EXPAND_FILL);
	row->add_child(seed_field);
	Label *radius_label = memnew(Label);
	radius_label->set_text("  radius (m)");
	row->add_child(radius_label);
	radius_field = memnew(LineEdit);
	radius_field->set_h_size_flags(Control::SIZE_EXPAND_FILL);
	row->add_child(radius_field);
	HBoxContainer *buttons = memnew(HBoxContainer);
	add_child(buttons);
	add_button(buttons, "Make this planet", "make_this_planet");
	add_button(buttons, "Random seed", "make_random_planet");
}

void PlanetMenu::make_this_planet() {
	new_planet(seed_field->get_text(), radius_field->get_text());
}

void PlanetMenu::make_random_planet() {
	new_planet(String::num_int64((int64_t)(UtilityFunctions::randi() % 100000)), radius_field->get_text());
}

void PlanetMenu::add_save_rows() {
	make_label("Saved universes (the land is made again from the seed)");
	HBoxContainer *row = memnew(HBoxContainer);
	add_child(row);
	save_name = memnew(LineEdit);
	save_name->set_text("universe");
	save_name->set_h_size_flags(Control::SIZE_EXPAND_FILL);
	row->add_child(save_name);
	Button *save = memnew(Button);
	save->set_text("Save here");
	save->connect("pressed", Callable(this, "save_here"));
	row->add_child(save);
	saves = memnew(OptionButton);
	add_child(saves);
	HBoxContainer *buttons = memnew(HBoxContainer);
	add_child(buttons);
	add_button(buttons, "Open", "open_selected");
	add_button(buttons, "Delete", "delete_selected");
	save_note = make_label("");
	fill_saves();
}

void PlanetMenu::fill_saves() {
	saves->clear();
	TypedArray<Dictionary> all = UniverseSave::list();
	for (int i = 0; i < all.size(); i++) {
		Dictionary entry = all[i];
		saves->add_item(vformat("%s   (seed %d, radius %d m)", entry["name"], entry["seed"], (int)(double)entry["radius"]));
		saves->set_item_metadata(saves->get_item_count() - 1, entry["name"]);
	}
}

String PlanetMenu::selected_save() const {
	if (saves->get_item_count() == 0 || saves->get_selected() < 0) {
		return "";
	}
	return String(saves->get_item_metadata(saves->get_selected()));
}

void PlanetMenu::save_here() {
	String name = save_name->get_text().strip_edges();
	if (name == "") {
		name = "universe";
	}
	bool written = UniverseSave::save(planet(), name);
	save_note->set_text(written ? vformat("Saved '%s'", name) : vformat("Could not save '%s'", name));
	fill_saves();
}

void PlanetMenu::open_selected() {
	String name = selected_save();
	Dictionary data = UniverseSave::load_data(name);
	if (data.is_empty()) {
		save_note->set_text("Nothing to open");
		return;
	}
	menu_state()->pending = UniverseSave::settings_from(data);
	menu_state()->pending_state = data.get("state", Dictionary());
	get_tree()->set_pause(false);
	get_tree()->reload_current_scene();
}

void PlanetMenu::delete_selected() {
	String name = selected_save();
	if (name != "") {
		UniverseSave::delete_save(name);
		save_note->set_text(vformat("Deleted '%s'", name));
	}
	fill_saves();
}

void PlanetMenu::new_planet(const String &p_seed_text, const String &p_radius_text) {
	Ref<PlanetSettings> current = planet()->get("settings");
	Ref<PlanetSettings> settings = current->duplicate();
	String text = p_seed_text.strip_edges();
	settings->set_world_seed(text.is_valid_int() ? text.to_int() : (int64_t)UtilityFunctions::hash(Variant(text)));
	if (p_radius_text.strip_edges().is_valid_float()) {
		settings->set_radius(CLAMP(p_radius_text.to_float(), 2000.0, 6.4e6));
	}
	menu_state()->pending = settings;
	get_tree()->set_pause(false);
	get_tree()->reload_current_scene();
}

// ---- UniverseStartMenu ----

void UniverseStartMenu::_bind_methods() {
	ClassDB::bind_static_method("UniverseStartMenu", D_METHOD("get_requested"), &UniverseStartMenu::get_requested);
	ClassDB::bind_static_method("UniverseStartMenu", D_METHOD("set_requested", "value"), &UniverseStartMenu::set_requested);
	ClassDB::bind_method(D_METHOD("open_selected"), &UniverseStartMenu::open_selected);
	ClassDB::bind_method(D_METHOD("delete_selected"), &UniverseStartMenu::delete_selected);
	ClassDB::bind_method(D_METHOD("create_typed"), &UniverseStartMenu::create_typed);
	ClassDB::bind_method(D_METHOD("create_random"), &UniverseStartMenu::create_random);
	ClassDB::bind_method(D_METHOD("quick_start"), &UniverseStartMenu::quick_start);
	ClassDB::bind_method(D_METHOD("new_earth"), &UniverseStartMenu::new_earth);
	ClassDB::bind_method(D_METHOD("saves_activated", "index"), &UniverseStartMenu::saves_activated);
}

// True when the next start of the scene should show this menu (set by "Main menu" in the Planet page); a start with no arguments shows it too.
bool UniverseStartMenu::get_requested() {
	return menu_state()->requested;
}
void UniverseStartMenu::set_requested(bool p_value) {
	menu_state()->requested = p_value;
}

Label *UniverseStartMenu::add_label(Node *p_parent, const String &p_text, int p_size) {
	Label *label = memnew(Label);
	label->set_text(p_text);
	label->add_theme_font_size_override("font_size", p_size);
	p_parent->add_child(label);
	return label;
}

Button *UniverseStartMenu::add_button(Node *p_parent, const String &p_text, const StringName &p_method) {
	Button *button = memnew(Button);
	button->set_text(p_text);
	button->set_h_size_flags(Control::SIZE_EXPAND_FILL);
	button->connect("pressed", Callable(this, p_method));
	p_parent->add_child(button);
	return button;
}

void UniverseStartMenu::_ready() {
	Input::get_singleton()->set_mouse_mode(Input::MOUSE_MODE_VISIBLE);
	ColorRect *backdrop = memnew(ColorRect);
	backdrop->set_color(Color(0.03f, 0.04f, 0.07f));
	backdrop->set_anchors_preset(Control::PRESET_FULL_RECT);
	add_child(backdrop);
	CenterContainer *centre = memnew(CenterContainer);
	centre->set_anchors_preset(Control::PRESET_FULL_RECT);
	add_child(centre);
	VBoxContainer *column = memnew(VBoxContainer);
	column->set_custom_minimum_size(Vector2(520, 0));
	column->add_theme_constant_override("separation", 8);
	centre->add_child(column);
	add_label(column, "Universe", 32);
	add_label(column, "Saved universes", 16);
	saves = memnew(ItemList);
	saves->set_custom_minimum_size(Vector2(0, 190));
	saves->connect("item_activated", Callable(this, "saves_activated"));
	column->add_child(saves);
	HBoxContainer *row = memnew(HBoxContainer);
	column->add_child(row);
	add_button(row, "Open", "open_selected");
	add_button(row, "Delete", "delete_selected");
	column->add_child(memnew(HSeparator));
	add_label(column, "New universe (it starts on one planet)", 16);
	HBoxContainer *fields = memnew(HBoxContainer);
	column->add_child(fields);
	add_label(fields, "seed", 16);
	seed_field = memnew(LineEdit);
	Ref<PlanetSettings> defaults;
	defaults.instantiate();
	seed_field->set_text(String::num_int64(defaults->get_world_seed()));
	seed_field->set_h_size_flags(Control::SIZE_EXPAND_FILL);
	fields->add_child(seed_field);
	add_label(fields, "  radius (m)", 16);
	radius_field = memnew(LineEdit);
	radius_field->set_placeholder("from the planet");
	radius_field->set_h_size_flags(Control::SIZE_EXPAND_FILL);
	fields->add_child(radius_field);
	HBoxContainer *home_row = memnew(HBoxContainer);
	column->add_child(home_row);
	add_label(home_row, "home planet ", 16);
	home = memnew(OptionButton);
	home->add_item("Sun-like star, habitable planet");
	home->add_item("Any star and planet");
	home->set_h_size_flags(Control::SIZE_EXPAND_FILL);
	home_row->add_child(home);
	HBoxContainer *colour_row = memnew(HBoxContainer);
	column->add_child(colour_row);
	add_label(colour_row, "star colours: physical ", 16);
	readability = memnew(HSlider);
	readability->set_max(1.0);
	readability->set_step(0.05);
	readability->set_h_size_flags(Control::SIZE_EXPAND_FILL);
	colour_row->add_child(readability);
	add_label(colour_row, " readable", 16);
	HBoxContainer *buttons = memnew(HBoxContainer);
	column->add_child(buttons);
	add_button(buttons, "Create", "create_typed");
	add_button(buttons, "Random seed", "create_random");
	add_button(buttons, "Quick start (default universe)", "quick_start");
	add_button(buttons, "New Earth (real size, day, year)", "new_earth");
	note = add_label(column, "", 14);
	if (!OS::get_singleton()->has_feature("double")) {
		note->set_text("Single precision build: an Earth-size planet jitters (it needs the double build)");
	}
	fill_saves();
}

void UniverseStartMenu::fill_saves() {
	saves->clear();
	TypedArray<Dictionary> all = UniverseSave::list();
	for (int i = 0; i < all.size(); i++) {
		Dictionary entry = all[i];
		String when = Time::get_singleton()->get_datetime_string_from_unix_time((int64_t)entry["saved_at"], true);
		int count = (int)(int64_t)entry["planets"];
		saves->add_item(vformat("%s    %d planet%s, seed %d, radius %d m    %s", entry["name"], count, count == 1 ? "" : "s", entry["seed"], (int)(double)entry["radius"], when));
		saves->set_item_metadata(saves->get_item_count() - 1, entry["name"]);
	}
	if (saves->get_item_count() > 0) {
		saves->select(0);
	} else {
		saves->add_item("(no saved universe yet)");
		saves->set_item_disabled(0, true);
	}
}

String UniverseStartMenu::selected_save() const {
	PackedInt32Array chosen = saves->get_selected_items();
	if (chosen.is_empty() || saves->is_item_disabled(chosen[0])) {
		return "";
	}
	return String(saves->get_item_metadata(chosen[0]));
}

void UniverseStartMenu::saves_activated(int64_t) {
	open_selected();
}

void UniverseStartMenu::open_selected() {
	String name = selected_save();
	Dictionary data = UniverseSave::load_data(name);
	if (data.is_empty()) {
		note->set_text("Choose a saved universe to open");
		return;
	}
	begin(UniverseSave::settings_from(data), data.get("state", Dictionary()));
}

void UniverseStartMenu::delete_selected() {
	String name = selected_save();
	if (name != "") {
		UniverseSave::delete_save(name);
		note->set_text(vformat("Deleted '%s'", name));
	}
	fill_saves();
}

void UniverseStartMenu::create(const String &p_seed_text) {
	Ref<UniverseSettings> universe;
	universe.instantiate();
	String text = p_seed_text.strip_edges();
	universe->set_universe_seed(text.is_valid_int() ? text.to_int() : (int64_t)UtilityFunctions::hash(Variant(text)));
	universe->set_sunlike_home(home->get_selected() == 0);
	Ref<PlanetSettings> settings = universe->home_settings(readability->get_value());
	if (radius_field->get_text().strip_edges().is_valid_float()) {
		settings->set_radius(CLAMP(radius_field->get_text().to_float(), 2000.0, 6.4e6));
	}
	begin(settings, Dictionary());
}

void UniverseStartMenu::create_typed() {
	create(seed_field->get_text());
}

void UniverseStartMenu::create_random() {
	create(String::num_int64((int64_t)(UtilityFunctions::randi() % 100000)));
}

void UniverseStartMenu::quick_start() {
	Ref<PlanetSettings> settings;
	settings.instantiate();
	begin(settings, Dictionary());
}

void UniverseStartMenu::new_earth() {
	begin(PlanetSettings::earth(), Dictionary());
}

void UniverseStartMenu::begin(const Ref<PlanetSettings> &p_settings, const Dictionary &p_state) {
	menu_state()->pending = p_settings;
	menu_state()->pending_state = p_state;
	menu_state()->requested = false;
	get_tree()->reload_current_scene();
}
