#pragma once

// PlanetMenu and UniverseStartMenu (were systems/planet/planet_menu.gd and universe_start_menu.gd).
// PlanetMenu is the "Planet" page of the Esc menu (the time, the weather, the seed and the size of the planet, the saved universes, the map);
// UniverseStartMenu is the menu in front of the universe: the saved universes (open one, delete one) and a new universe. Choosing sets what the next
// planet is made from (PlanetMenu's pending settings and state) and makes the scene again, which builds it. The script's static vars are static
// getters and setters now.

#include "native_props.h"
#include "planet_settings_native.h"

#include <godot_cpp/classes/canvas_layer.hpp>
#include <godot_cpp/classes/check_box.hpp>
#include <godot_cpp/classes/h_slider.hpp>
#include <godot_cpp/classes/item_list.hpp>
#include <godot_cpp/classes/label.hpp>
#include <godot_cpp/classes/line_edit.hpp>
#include <godot_cpp/classes/option_button.hpp>
#include <godot_cpp/classes/v_box_container.hpp>
#include <godot_cpp/variant/dictionary.hpp>

namespace godot {

class PlanetMenu : public VBoxContainer {
	GDCLASS(PlanetMenu, VBoxContainer)

	ObjectID planet_id;
	Label *info = nullptr;
	Label *star_info = nullptr;
	Label *rate_label = nullptr;
	HSlider *hour_slider = nullptr;
	HSlider *year_slider = nullptr;
	OptionButton *weather = nullptr;
	CheckBox *clouds = nullptr;
	CheckBox *fog = nullptr;
	LineEdit *seed_field = nullptr;
	LineEdit *radius_field = nullptr;
	LineEdit *save_name = nullptr;
	OptionButton *saves = nullptr;
	Label *save_note = nullptr;

	Object *planet() const { return ObjectDB::get_instance(planet_id); }
	void sync_values();
	String star_text() const;
	void add_time_rows();
	void add_weather_row();
	void add_new_planet_rows();
	void add_save_rows();
	void fill_saves();
	String selected_save() const;
	void new_planet(const String &p_seed_text, const String &p_radius_text);
	Label *make_label(const String &p_text);
	Button *add_button(Node *p_parent, const String &p_text, const StringName &p_method, const Variant &p_argument = Variant());

protected:
	static void _bind_methods();

public:
	static Ref<PlanetSettings> get_pending();
	static void set_pending(const Ref<PlanetSettings> &p_settings);
	static Dictionary get_pending_state();
	static void set_pending_state(const Dictionary &p_state);

	void setup(Object *p_planet);
	void refresh();
	void _process(double p_delta) override;
	void set_rate(double p_rate);
	void jump(double p_step);
	void hour_changed(double p_hours);
	void year_changed(double p_share);
	void weather_picked(int64_t p_index);
	void clouds_toggled(bool p_shown);
	void fog_toggled(bool p_shown);
	void make_this_planet();
	void make_random_planet();
	void save_here();
	void open_selected();
	void delete_selected();
	void main_menu();
	void open_map();
};

class UniverseStartMenu : public CanvasLayer {
	GDCLASS(UniverseStartMenu, CanvasLayer)

	ItemList *saves = nullptr;
	LineEdit *seed_field = nullptr;
	LineEdit *radius_field = nullptr;
	OptionButton *home = nullptr;
	HSlider *readability = nullptr;
	Label *note = nullptr;

	void fill_saves();
	String selected_save() const;
	void begin(const Ref<PlanetSettings> &p_settings, const Dictionary &p_state);
	void create(const String &p_seed_text);
	Label *add_label(Node *p_parent, const String &p_text, int p_size);
	Button *add_button(Node *p_parent, const String &p_text, const StringName &p_method);

protected:
	static void _bind_methods();

public:
	static bool get_requested();
	static void set_requested(bool p_value);

	void _ready() override;
	void open_selected();
	void delete_selected();
	void create_typed();
	void create_random();
	void quick_start();
	void new_earth();
	void saves_activated(int64_t p_index);
};

} // namespace godot
