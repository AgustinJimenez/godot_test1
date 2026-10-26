#include "planet_world_native.h"

#include "planet_ground_bake_native.h"
#include "planet_sky_native.h"
#include "planet_nodes_native.h"
#include "planet_prints_native.h"
#include "planet_recorder_native.h"
#include "planet_render_native.h"
#include "planet_sky_nodes_native.h"
#include "planet_star_native.h"
#include "planet_sway_native.h"
#include "planet_turf_native.h"

#include <godot_cpp/classes/camera3d.hpp>
#include <godot_cpp/classes/canvas_layer.hpp>
#include <godot_cpp/classes/display_server.hpp>
#include <godot_cpp/classes/engine.hpp>
#include <godot_cpp/classes/scene_tree.hpp>
#include <godot_cpp/classes/window.hpp>
#include <godot_cpp/classes/file_access.hpp>
#include <godot_cpp/classes/os.hpp>
#include <godot_cpp/classes/physics_direct_space_state3d.hpp>
#include <godot_cpp/classes/physics_ray_query_parameters3d.hpp>
#include <godot_cpp/classes/rendering_server.hpp>
#include <godot_cpp/classes/resource_loader.hpp>
#include <godot_cpp/classes/script.hpp>
#include <godot_cpp/classes/callback_tweener.hpp>
#include <godot_cpp/classes/property_tweener.hpp>
#include <godot_cpp/classes/tween.hpp>
#include <godot_cpp/classes/viewport.hpp>
#include <godot_cpp/classes/world3d.hpp>
#include <godot_cpp/variant/utility_functions.hpp>

#include <algorithm>
#include <cmath>

using namespace godot;

static const double TAU_D = 6.283185307179586476925286766559;

static double smooth_step(double p_from, double p_to, double p_x) {
	if (p_from == p_to) {
		return p_x < p_from ? 0.0 : 1.0;
	}
	double s = CLAMP((p_x - p_from) / (p_to - p_from), 0.0, 1.0);
	return s * s * (3.0 - 2.0 * s);
}

static Ref<Script> script_of(const char *p_path) {
	return ResourceLoader::get_singleton()->load(p_path);
}

static int64_t graphics_int(const StringName &p_key) {
	SceneTree *tree = Object::cast_to<SceneTree>(Engine::get_singleton()->get_main_loop());
	Node *graphics = tree != nullptr ? tree->get_root()->get_node_or_null("GraphicsSettings") : nullptr;
	return graphics != nullptr ? (int64_t)graphics->call("get_graphics_value", p_key) : 0;
}

void PlanetWorld::_bind_methods() {
	NP_BIND_OBJ(PlanetWorld, settings, "PlanetSettings")
	ClassDB::bind_method(D_METHOD("get_time_of_day"), &PlanetWorld::get_time_of_day);
	ClassDB::bind_method(D_METHOD("set_time_of_day", "value"), &PlanetWorld::set_time_of_day);
	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "time_of_day"), "set_time_of_day", "get_time_of_day");
	NP_BIND(PlanetWorld, Variant::FLOAT, fog)
	NP_BIND_OBJ(PlanetWorld, noise, "PlanetNoise")
	NP_BIND_OBJ(PlanetWorld, frame, "PlanetFrame")
	NP_BIND_OBJECT(PlanetWorld, surface)
	NP_BIND_OBJECT(PlanetWorld, atmosphere)
	NP_BIND_OBJECT(PlanetWorld, ground_bake)
	NP_BIND_STATE(PlanetWorld, Variant::FLOAT, above_ground)
	NP_BIND_OBJECT(PlanetWorld, fauna)
	NP_BIND_OBJECT(PlanetWorld, swim)
	NP_BIND_OBJECT(PlanetWorld, map)
	NP_BIND_OBJECT(PlanetWorld, weather)
	NP_BIND_OBJECT(PlanetWorld, cloud_shell)
	NP_BIND_STATE(PlanetWorld, Variant::STRING, weather_text)
	NP_BIND_STATE(PlanetWorld, Variant::DICTIONARY, restored)
	NP_BIND_STATE(PlanetWorld, Variant::INT, weather_override)
	NP_BIND_STATE(PlanetWorld, Variant::FLOAT, time_rate)
	NP_BIND_OBJ(PlanetWorld, clock, "PlanetClock")
	NP_BIND_OBJECT(PlanetWorld, splash)
	NP_BIND_STATE(PlanetWorld, Variant::INT, rebases)
	NP_BIND_STATE(PlanetWorld, Variant::BOOL, spawn_on_solid_ground)
	NP_BIND_STATE(PlanetWorld, Variant::BOOL, start_in_desert)
	NP_BIND_STATE(PlanetWorld, Variant::BOOL, loading)
	NP_BIND_STATE(PlanetWorld, Variant::BOOL, map_first)
	ADD_SIGNAL(MethodInfo("loaded"));
	ADD_SIGNAL(MethodInfo("world_changed", PropertyInfo(Variant::RECT2, "area")));
	ClassDB::bind_method(D_METHOD("target"), &PlanetWorld::target);
	ClassDB::bind_method(D_METHOD("start", "target", "direction", "altitude"), &PlanetWorld::start, DEFVAL(Vector3()), DEFVAL(0.0));
	ClassDB::bind_static_method("PlanetWorld", D_METHOD("nearest_point", "position"), &PlanetWorld::nearest_point);
	ClassDB::bind_method(D_METHOD("altitude_of", "position"), &PlanetWorld::altitude_of);
	ClassDB::bind_method(D_METHOD("snapshot"), &PlanetWorld::snapshot);
	ClassDB::bind_method(D_METHOD("season_text"), &PlanetWorld::season_text);
	ClassDB::bind_method(D_METHOD("jump_time", "days"), &PlanetWorld::jump_time);
	ClassDB::bind_method(D_METHOD("set_hour", "hour"), &PlanetWorld::set_hour);
	ClassDB::bind_method(D_METHOD("set_year_share", "share"), &PlanetWorld::set_year_share);
	ClassDB::bind_method(D_METHOD("publish_frame"), &PlanetWorld::publish_frame);
	ClassDB::bind_method(D_METHOD("build_now", "near_only"), &PlanetWorld::build_now, DEFVAL(false));
	ClassDB::bind_method(D_METHOD("planet_position"), &PlanetWorld::planet_position);
	ClassDB::bind_method(D_METHOD("ground_at", "x", "z", "near_y"), &PlanetWorld::ground_at);
	ClassDB::bind_method(D_METHOD("flight_floor", "position"), &PlanetWorld::flight_floor);
	ClassDB::bind_method(D_METHOD("water_at_world", "position"), &PlanetWorld::water_at_world);
	ClassDB::bind_method(D_METHOD("flow_at_world", "position"), &PlanetWorld::flow_at_world);
	ClassDB::bind_method(D_METHOD("altitude"), &PlanetWorld::altitude);
	ClassDB::bind_method(D_METHOD("update_now"), &PlanetWorld::update_now);
	ClassDB::bind_method(D_METHOD("cover_the_loading"), &PlanetWorld::cover_the_loading);
}

PlanetWorld::PlanetWorld() {
	frame.instantiate();
	clock.instantiate();
}

// A node made from a GDScript class (the flat world's classes the planet builds on), not yet in the tree.
Object *PlanetWorld::make_scripted(const char *p_path) const {
	Ref<Script> script = script_of(p_path);
	ERR_FAIL_COND_V_MSG(script.is_null(), nullptr, String("PlanetWorld: the script ") + p_path + " did not load");
	Object *made = script->call("new");
	ERR_FAIL_COND_V_MSG(made == nullptr, nullptr, String("PlanetWorld: ") + p_path + " could not be made");
	return made;
}

Node3D *PlanetWorld::target() const {
	return Object::cast_to<Node3D>(ObjectDB::get_instance(target_id));
}

void PlanetWorld::_ready() {
	if (settings.is_null()) {
		settings.instantiate();
	}
	// the plants are built in the finer, realistic look from the Fine ground detail (High and Ultra); the light meshes cost a third of the triangles
	// for Low and Medium
	Ref<Script> flora = script_of("res://systems/world_gen/flora_meshes.gd");
	flora->set("detailed", graphics_int("ground_detail") >= 2);
	flora->set("fine_trees", graphics_int("ground_detail") >= 1 && !OS::get_singleton()->has_environment("PLANET_LIGHT_TREES"));
	Node *bark = Object::cast_to<Node>(make_scripted("res://systems/planet/planet_bark_bake.gd"));
	add_child(bark);
	bark->call("run"); // (a coroutine: it carries on over the next frames)
	noise = PlanetNoise::create(settings);
	clock->set_day_seconds(settings->get_day_seconds());
	clock->set_year_days(settings->get_year_days());
	clock->set_axial_tilt(Math::deg_to_rad(settings->get_axial_tilt()));
	clock->set_insolation(settings->get_insolation());
	clock->set_eccentricity(settings->get_eccentricity());
	clock->set_perihelion_share(settings->get_perihelion_share());
	clock->set_month_days(settings->get_month_days());
	Node *air = Object::cast_to<Node>(make_scripted("res://systems/planet/planet_atmosphere.gd"));
	air->set("radius", settings->get_radius());
	air->set("air_height", settings->get_air_height());
	Ref<Star> star = Star::from_mass(settings->get_star_mass());
	air->set("star_tint", star->light_tint(settings->get_star_readability()));
	star_disc = star->get_radius() * std::sqrt(settings->get_insolation() / star->get_luminosity());
	air->set("time_of_day", time_of_day);
	add_child(air);
	atmosphere_id = air->get_instance_id();
	PlanetSurface *ground = memnew(PlanetSurface);
	ground->setup(noise, frame);
	add_child(ground);
	surface_id = ground->get_instance_id();
	Node *animals = Object::cast_to<Node>(make_scripted("res://systems/planet/planet_fauna.gd"));
	animals->set("planet", this);
	add_child(animals);
	fauna_id = animals->get_instance_id();
	Node *effects = Object::cast_to<Node>(make_scripted("res://systems/world_gen/world_weather.gd"));
	effects->set("atmosphere", air);
	add_child(effects);
	weather_id = effects->get_instance_id();
	PlanetCloudShell *shell = memnew(PlanetCloudShell);
	shell->set_planet(this);
	add_child(shell);
	cloud_shell_id = shell->get_instance_id();
	Node *chart_map = Object::cast_to<Node>(make_scripted("res://systems/planet/planet_map.gd"));
	chart_map->set("planet", this);
	add_child(chart_map);
	map_id = chart_map->get_instance_id();
	PlanetRecorder *recorder = memnew(PlanetRecorder); // the last seconds of play, kept in a file (F9 marks)
	recorder->set_planet(this);
	add_child(recorder);
	CanvasLayer *layer = memnew(CanvasLayer);
	layer->set_layer(80);
	add_child(layer);
	dark = memnew(ColorRect); // the screen stays black while the planet is made
	dark->set_color(Color(0, 0, 0, 1));
	dark->set_anchors_preset(Control::PRESET_FULL_RECT);
	dark->set_mouse_filter(Control::MOUSE_FILTER_IGNORE);
	dark->set_visible(false);
	layer->add_child(dark);
	load_label = memnew(Label);
	load_label->set_anchors_and_offsets_preset(Control::PRESET_CENTER);
	load_label->set_h_grow_direction(Control::GROW_DIRECTION_BOTH);
	load_label->set_visible(false);
	layer->add_child(load_label);
}

// Stands `target` on the planet at the spawn spot (or `direction`, a unit vector from the centre). Starts the planet around `target`.
// `direction`: the point of the planet (a unit vector) it starts over, or none to find a good place; `altitude`: how far above the ground there,
// in metres. The target ends up at the world origin; returns the direction it stands in.
Vector3 PlanetWorld::start(Node3D *p_target, const Vector3 &p_direction, double p_altitude) {
	Vector3 direction = p_direction;
	// the materials tiles share are made here, on the main thread: a worker thread making one first could read it half made while another does
	PlanetTile::ground_material();
	PlanetTile::water_material();
	PlanetTile::river_material()->set_shader_parameter("sea_radius", settings->get_radius() + settings->get_sea_level());
	target_id = p_target->get_instance_id();
	bool headless = DisplayServer::get_singleton()->get_name() == "headless";
	OS *os = OS::get_singleton();
	if (graphics_int("ground_detail") >= 1 && !os->has_environment("PLANET_NO_BAKE") && !headless) {
		PlanetGroundBake *bake = memnew(PlanetGroundBake); // the parallax of the ground plates reads a picture
		// (8 bits look the same as 16 and take half the memory)
		bake->set_hdr(os->has_environment("PLANET_BAKE_16BIT"));
		add_child(bake);
		bake->setup(PlanetTile::ground_material());
		ground_bake_id = bake->get_instance_id();
	}
	PlanetImpostors *impostors = memnew(PlanetImpostors); // far trees as pictures (081)
	add_child(impostors);
	impostors->start((Object *)noise->get_species());
	bool is_player = p_target->has_method("set_free_mode");
	if (is_player) {
		Node *water_splash = Object::cast_to<Node>(make_scripted("res://systems/world_gen/water_splash.gd"));
		add_child(water_splash);
		splash_id = water_splash->get_instance_id();
		Node *swimming = Object::cast_to<Node>(make_scripted("res://systems/planet/planet_swim.gd"));
		swimming->set("planet", this);
		swimming->set("target", p_target);
		swimming->set("splash", water_splash);
		add_child(swimming);
		swim_id = swimming->get_instance_id();
		PlanetFootprints *footprints = memnew(PlanetFootprints);
		footprints->set_planet(this);
		footprints->set_target(p_target);
		add_child(footprints);
		PlanetCrustGuard *guard = memnew(PlanetCrustGuard); // the player and the camera never go inside the crust
		guard->set_planet(this);
		guard->set_target(p_target);
		add_child(guard);
		PlanetMotes *motes = memnew(PlanetMotes);
		motes->set_planet(this);
		add_child(motes);
		if (!os->has_environment("PLANET_NO_UNDERGROWTH")) {
			PlanetUndergrowth *undergrowth = memnew(PlanetUndergrowth); // the plants bend and hold the walker back
			undergrowth->set_planet(this);
			undergrowth->set_player(p_target);
			add_child(undergrowth);
		}
		if (!os->has_environment("PLANET_NO_SWAY")) {
			PlanetSway *sway = memnew(PlanetSway); // the branches round the walker bend and spring back
			sway->set_planet(this);
			sway->set_player(p_target);
			add_child(sway);
		}
		if (!os->has_environment("PLANET_NO_TURF")) {
			PlanetTurf *turf = memnew(PlanetTurf); // short grass all over the ground where it grows
			turf->set_planet(this);
			turf->set_player(p_target);
			if (!os->has_environment("PLANET_NO_GRASS")) {
				add_child(turf);
			} else {
				memdelete(turf);
			}
			if (os->has_environment("PLANET_SHELLS")) { // (off: it cost 1.5 ms and showed little)
				// the loose stones of the near ground as relief (layers of the ground mesh)
				PlanetShells *shells = memnew(PlanetShells);
				shells->set_planet(this);
				shells->set_player(p_target);
				add_child(shells);
			}
			if (!os->has_environment("PLANET_NO_GRAVEL")) {
				// and small stones on the bare ground, real ones that cast shadows
				PlanetTurf *gravel = memnew(PlanetTurf);
				gravel->set_gravel(true);
				gravel->set_planet(this);
				gravel->set_player(p_target);
				add_child(gravel);
			}
		}
	}
	if (direction == Vector3() && restored.has("direction")) {
		Array saved = restored["direction"];
		direction = Vector3(saved[0], saved[1], saved[2]).normalized();
	}
	Vector3 dir = direction;
	if (dir == Vector3()) {
		dir = noise->find_spawn(start_in_desert);
	}
	if (is_player && p_altitude <= 0.0 && spawn_on_solid_ground) {
		dir = noise->solid_spawn(dir); // the character starts on solid ground, never in the sea or a river
	}
	double reach = settings->get_radius() + noise->height(dir.x, dir.y, dir.z) + 1.0;
	reach += std::max(p_altitude, 0.0);
	noise->set_clearing(dir);
	Object *hud = is_player ? (Object *)p_target->get("hud") : nullptr;
	if (hud != nullptr) {
		Control *page = Object::cast_to<Control>(make_scripted("res://systems/planet/planet_menu.gd"));
		page->call("setup", this);
		hud->call("add_menu_page", "Planet", page);
	}
	noise->set_clock(clock);
	clock->start(settings->get_start_year(), settings->get_start_hour(), dir);
	if (restored.has("clock")) {
		clock->restore(restored["clock"]);
		time_rate = restored.get("time_rate", time_rate);
		weather_override = restored.get("weather_override", weather_override);
	}
	set_the_sun();
	PackedFloat64Array anchor;
	anchor.append(dir.x * reach);
	anchor.append(dir.y * reach);
	anchor.append(dir.z * reach);
	frame->start(anchor, Vector3());
	p_target->set("global_position", Vector3());
	if (is_player) {
		p_target->set("flight_floor", Callable(this, "flight_floor"));
	}
	if (p_altitude > 500.0 && is_player) { // up in the air there is nothing to stand on: fly
		p_target->call("set_free_mode", true);
	}
	if (restored.has("heading")) {
		Array saved = restored["heading"];
		Vector3 along = frame->get_rot().xform(Vector3(saved[0], saved[1], saved[2]));
		if (Vector2(along.x, along.z).length() > 0.01) {
			p_target->set_rotation(Vector3(p_target->get_rotation().x, std::atan2(-along.x, -along.z), p_target->get_rotation().z));
		}
	}
	restored = Dictionary();
	publish_frame();
	PlanetSurface *ground = get_surface();
	Object *chart_map = get_map();
	if (!(is_player && ground->is_threaded())) {
		chart_map->call("begin");
	}
	// the ground and the water come first: the player stands still until the land round them is made (the plants follow, starting with the ones
	// nearest to them)
	if (is_player && ground->is_threaded()) {
		loading = true;
		load_time = 0.0;
		p_target->set_process_mode(Node::PROCESS_MODE_DISABLED);
		ground->update(planet_position());
		if (map_first && !headless) {
			// the world is defined before it is built: its map, every layer, comes first, and the ground waits (map.paused) until the map is closed
			chart_map->set("warm_up", true); // (black, with its progress, until the whole map is charted)
			chart_map->call("begin");
			Ref<Script> map_script = chart_map->get_script();
			chart_map->call("show_zoom", map_script->get_script_constant_map()["MAX_ZOOM"]);
			chart_map->connect("visibility_changed", Callable(this, "cover_the_loading"), CONNECT_ONE_SHOT);
			return dir;
		}
		cover_the_loading();
		connect("loaded", Callable(chart_map, "begin"), CONNECT_ONE_SHOT); // the map is drawn once the player is in
	}
	return dir;
}

// Black screen and the loading text while the ground round the player is made.
void PlanetWorld::cover_the_loading() {
	load_label->set_visible(true);
	Color colour = dark->get_modulate();
	colour.a = 1.0;
	dark->set_modulate(colour);
	dark->set_visible(true);
}

// The point of the planet closest to `position` (metres from the planet's centre, anywhere in space): the unit direction to start over.
Vector3 PlanetWorld::nearest_point(const Vector3 &p_position) {
	return p_position.length() > 0.0 ? p_position.normalized() : Vector3(0, 1, 0);
}

// How far above the ground `position` is, for the direction found by `nearest_point`.
double PlanetWorld::altitude_of(const Vector3 &p_position) const {
	Vector3 dir = nearest_point(p_position);
	return p_position.length() - settings->get_radius() - noise->height(dir.x, dir.y, dir.z);
}

// The clouds and the rain of the sky belong to the first kilometre and a half above the ground: the puffs ride at their height above the ground
// under the player, and above that the rain and the puffs are gone (the cloud shell of the planet takes over).
void PlanetWorld::keep_the_weather_near_the_ground() {
	Vector3 here = planet_position().normalized();
	double ground = noise->height(here.x, here.y, here.z);
	double above = altitude() - ground;
	above_ground = above;
	bool low = above < RAIN_UP_TO;
	Object *effects = get_weather();
	Object *air = get_atmosphere();
	Object *clouds = effects->get("clouds");
	clouds->set("visible", false); // the planet's clouds are the sky's own (planet_sky.gdshader)
	Object *rain = effects->get("rain");
	rain->set("visible", low);
	air->set("cloud_floor", std::max(ground, 0.0) + 450.0);
	air->set("cloud_on", 1.0 - smooth_step(450.0, 700.0, above)); // then the shell has them
	Node3D *effects_node = Object::cast_to<Node3D>(effects);
	Vector3 at = effects_node->get_position();
	at.y = frame->to_world(here * (settings->get_radius() + std::max(ground, 0.0))).y;
	effects_node->set_position(at);
}

// The weather at the player, from the planet's own clouds, temperature and moisture: sets the state the effects (clouds, rain, snow, fog, wind)
// ease toward.
void PlanetWorld::pick_the_weather() {
	Vector3 here = planet_position().normalized();
	Dictionary now = noise->get_weather()->at(here, std::max(altitude(), 0.0), clock);
	int64_t kind = weather_override < 0 ? (int64_t)now["kind"] : weather_override;
	Object *effects = get_weather();
	Object *air = get_atmosphere();
	if ((int64_t)effects->get("state") != kind) {
		effects->call("set_state", kind);
	}
	Ref<Script> weather_script = effects->get_script();
	Dictionary states = weather_script->get_script_constant_map()["State"];
	String format = String::utf8("%s  %d%% cloud  %d \xC2\xB0""C");
	weather_text = vformat(format, String(states.keys()[kind]).capitalize(), (int)((double)now["cloud"] * 100.0), (int)std::round((double)now["degrees"]));
	// the haze follows the climate here: thick and soft where it is warm and wet, clear where it is cold and dry, dusty where it is hot and dry
	Vector2 local = noise->get_climate()->sample(here);
	double humid = CLAMP((double)local.y / 0.9, 0.0, 1.0);
	double warm = smooth_step(0.0, 25.0, local.x);
	air->set("haze_wanted", 0.55 + 1.5 * humid * warm);
	air->set("dust_wanted", (1.0 - humid) * smooth_step(14.0, 30.0, local.x));
	// morning mist: the night's cold leaves a fog in wet low ground until the sun burns it off
	double morning = clock->local_hour(here);
	double dawn = smooth_step(3.5, 5.5, morning) * (1.0 - smooth_step(7.0, 10.0, morning));
	double low_wet = humid * (1.0 - smooth_step(30.0, 250.0, std::max(altitude(), 0.0)));
	air->set("mist_wanted", dawn * low_wet * smooth_step(2.0, 12.0, local.x));
	// the wind blows along the parallel: east or west by the latitude, as the clouds are carried
	double lat = std::asin(CLAMP((double)here.y, -1.0, 1.0));
	Vector3 east = Vector3(-here.z, 0.0, here.x).normalized();
	double blowing = -PlanetWeather::zonal_wind(lat, noise->get_weather()->wind_k());
	Vector3 wind = frame->get_rot().xform(east * blowing); // toward where it blows from
	effects->set("forced_wind", wind.length() > 0.01 ? Vector2(-wind.x, -wind.z) : Vector2());
}

// What a save keeps of this moment: where the player stands, which way they face (in the planet's frame), the clock, the speed of time and the
// weather forced, if any.
Dictionary PlanetWorld::snapshot() const {
	Vector3 here = planet_position().normalized();
	Dictionary state;
	Array direction;
	direction.append(here.x);
	direction.append(here.y);
	direction.append(here.z);
	state["direction"] = direction;
	state["clock"] = clock->snapshot();
	state["time_rate"] = time_rate;
	state["weather_override"] = weather_override;
	Node3D *player = target();
	if (player != nullptr) {
		Vector3 forward = -player->get_global_basis().get_column(2);
		Vector3 along = frame->get_rot().inverse().xform(Vector3(forward.x, 0.0, forward.z).normalized());
		Array heading;
		heading.append(along.x);
		heading.append(along.y);
		heading.append(along.z);
		state["heading"] = heading;
	}
	return state;
}

// The small clouds of the sky ride the wind the planet's cloud cover is carried by (PlanetWeather).
void PlanetWorld::drift_the_clouds(double p_seconds) {
	Vector3 here = planet_position().normalized();
	double lat = std::asin(CLAMP((double)here.y, -1.0, 1.0));
	Vector3 east = Vector3(-here.z, 0.0, here.x).normalized();
	double turn = PlanetWeather::zonal_wind(lat, noise->get_weather()->wind_k()) * PlanetWeather::get_wind_turn() * TAU_D;
	double speed = turn * settings->get_radius() * std::cos(lat) / clock->get_day_seconds();
	Object *air = get_atmosphere();
	Vector3 drift = air->get("cloud_drift");
	air->set("cloud_drift", drift - east * speed * p_seconds);
}

// 'Day 3, early spring' for the caption of the map.
String PlanetWorld::season_text() const {
	double share = clock->year_share();
	static const char *names[8] = { "early spring", "late spring", "early summer", "late summer", "early autumn", "late autumn", "early winter", "late winter" };
	// the northern seasons; the southern hemisphere has the other half of the year
	Vector3 here = planet_position().normalized();
	double shifted = here.y >= 0.0 ? share : std::fmod(share + 0.5, 1.0);
	int day = (int)std::floor(clock->get_time() / clock->get_day_seconds()) + 1;
	return vformat("day %d, %s%s", day, names[(int)(shifted * 8.0) % 8], here.y >= 0.0 ? "" : " (south)");
}

// Moves time by `days` solar days (negative: backward), keeping the sun's hour as it is.
void PlanetWorld::jump_time(double p_days) {
	clock->advance(p_days * clock->get_day_seconds());
}

// Moves the sun to the local solar `hour` (0..24) at the player, leaving the day of the year.
void PlanetWorld::set_hour(double p_hour) {
	if (target() != nullptr) {
		clock->start(clock->year_share(), p_hour, planet_position().normalized());
	}
}

// Moves the orbit to `share` of the year, leaving the hour of day where it is.
void PlanetWorld::set_year_share(double p_share) {
	if (target() != nullptr) {
		clock->set_year(p_share, planet_position().normalized());
	}
}

// Puts the sun where the planet's orbit and spin put it: the direction to the star in the planet's frame, turned into the world by the frame.
void PlanetWorld::set_the_sun() {
	Object *air = get_atmosphere();
	if (air == nullptr) {
		return;
	}
	air->set("planet_centre", frame->to_world(Vector3()));
	air->set("sun_direction", frame->get_rot().xform(clock->sun_in_body()).normalized());
	air->set("sun_size", star_disc / clock->distance());
	air->set("moon_direction", frame->get_rot().xform(PlanetMoon::in_body(clock)).normalized());
	air->set("moon_lit", PlanetMoon::lit(clock));
	air->set("moon_shadow", PlanetMoon::lunar_depth(clock));
	if (target() != nullptr) {
		air->set("sun_cover", PlanetMoon::solar_cover(clock, planet_position().normalized()));
	}
}

// Tells the ground shader where the planet is (it reads its detail noise at planet positions).
void PlanetWorld::publish_frame() {
	Transform3D to_world = frame->planet_to_world();
	RenderingServer *server = RenderingServer::get_singleton();
	server->global_shader_parameter_set("world_from_planet", to_world);
	server->global_shader_parameter_set("planet_from_world", to_world.affine_inverse());
	server->global_shader_parameter_set("anchor_from_world", frame->anchor_from_world());
	server->global_shader_parameter_set("anchor_wrap", frame->anchor_wrap());
	server->global_shader_parameter_set("anchor_up", frame->anchor_up());
	server->global_shader_parameter_set("anchor_phase", frame->anchor_phase());
	follow_the_ground();
}

// Keeps the baked heights of the ground plates (PlanetGroundBake) round the camera, in the ground shader's own coordinates. A new anchor (each
// rebase) turns those coordinates, so the picture is drawn again then, the same frame the shader gets the new anchor.
void PlanetWorld::follow_the_ground() {
	PlanetGroundBake *bake = Object::cast_to<PlanetGroundBake>(get_ground_bake());
	Node3D *player = target();
	if (bake == nullptr || player == nullptr) {
		return;
	}
	if (above_ground > BAKE_UP_TO) { // (the parallax fades out within 4 m of the camera)
		bake->pause();
		return;
	}
	Camera3D *camera = get_viewport()->get_camera_3d();
	Vector3 at = camera != nullptr ? camera->get_global_position() : player->get_global_position();
	PackedFloat64Array anchor = frame->get_anchor();
	Vector3 anchor_vector(anchor[0], anchor[1], anchor[2]);
	int64_t key = (int64_t)UtilityFunctions::hash(Variant(frame->get_rot())) ^ (int64_t)UtilityFunctions::hash(Variant(anchor_vector));
	bake->follow(PlanetGroundBake::flat_of(frame, at), key);
}

// Builds the ground around the target now, no waiting for the worker. `near_only`: only the ground the target can stand on.
void PlanetWorld::build_now(bool p_near_only) {
	get_surface()->build_all(planet_position(), p_near_only);
}

// The target's place on the planet (metres from its centre).
Vector3 PlanetWorld::planet_position() const {
	PackedFloat64Array at = frame->to_planet(target()->get_global_position());
	return Vector3(at[0], at[1], at[2]);
}

// The ground under the world position (x, z), found near the world height `near_y`: its world height, the biome there and whether it is under
// water (sea, river or lake).
Dictionary PlanetWorld::ground_at(double p_x, double p_z, double p_near_y) const {
	PackedFloat64Array here = frame->to_planet(Vector3(p_x, p_near_y, p_z));
	Vector3 dir = Vector3(here[0], here[1], here[2]).normalized();
	double h = noise->height(dir.x, dir.y, dir.z);
	bool wet = h < 0.6;
	if (!wet) {
		wet = noise->water_at(dir, h) > h - 0.3;
	}
	Vector3 up = frame->to_world(dir * (settings->get_radius() + h));
	Dictionary result;
	result["y"] = up.y;
	result["wet"] = wet;
	result["biome"] = noise->biome(dir.x, dir.y, dir.z, h, 0.1);
	return result;
}

// The world height of the ground (or of the sea, where it is deeper) under a world position: what free flight is kept above.
double PlanetWorld::flight_floor(const Vector3 &p_position) const {
	PackedFloat64Array here = frame->to_planet(p_position);
	Vector3 dir = Vector3(here[0], here[1], here[2]).normalized();
	double h = noise->height(dir.x, dir.y, dir.z);
	if (settings->get_sea_on()) {
		h = std::max(h, 0.0);
	}
	return frame->to_world(dir * (settings->get_radius() + h)).y;
}

// The world height of the water at a world position (the sea, a lake or a river there), or -INF where the ground is dry.
double PlanetWorld::water_at_world(const Vector3 &p_position) const {
	PackedFloat64Array here = frame->to_planet(p_position);
	Vector3 dir = Vector3(here[0], here[1], here[2]).normalized();
	double h = noise->height(dir.x, dir.y, dir.z);
	double level = -INFINITY;
	if (h < 0.0 && settings->get_sea_on()) {
		level = 0.0;
	} else {
		level = noise->water_at(dir, h);
	}
	if (level == -INFINITY) {
		return -INFINITY;
	}
	return frame->to_world(dir * (settings->get_radius() + level)).y;
}

// The river current at a world position, as a world vector (zero out of a river).
Vector3 PlanetWorld::flow_at_world(const Vector3 &p_position) const {
	PackedFloat64Array here = frame->to_planet(p_position);
	Vector3 dir = Vector3(here[0], here[1], here[2]).normalized();
	return frame->get_rot().xform(noise->flow_at(dir));
}

// m round the player that must be planted first (PLANET_LOAD_PLANTS: another, to try)
double PlanetWorld::load_plants() {
	OS *os = OS::get_singleton();
	return os->has_environment("PLANET_LOAD_PLANTS") ? os->get_environment("PLANET_LOAD_PLANTS").to_float() : LOAD_PLANTS_DEFAULT;
}

// While the player is held: keeps the tiles coming and lets the player in when the ground within `LOAD_GROUND` and the plants within
// `LOAD_PLANTS` are there.
void PlanetWorld::wait_for_the_ground(double p_delta) {
	Object *chart_map = get_map();
	if (map_first && chart_map != nullptr && (bool)chart_map->get("visible")) {
		return; // the map is open first: nothing is built and the 90 s of waiting do not run yet
	}
	load_time += p_delta;
	timer -= p_delta;
	PlanetSurface *ground = get_surface();
	if (timer <= 0.0) {
		timer = 0.3;
		ground->update(planet_position());
	}
	ground->set_burst(true);
	double done = ground->progress(LOAD_GROUND, load_plants());
	load_label->set_text(vformat("Generating the planet...  %d %%", (int)(done * 100.0)));
	if (done >= 0.999 || load_time > 90.0) {
		if (OS::get_singleton()->has_environment("PLANET_TIMING")) {
			UtilityFunctions::print(vformat("PLANET_TIMING ground ready after %.1f s, %d tiles built, %d wanted", load_time, (int64_t)ground->get_tiles().size(), ground->wanted_count()));
		}
		stand_on_the_ground();
		loading = false;
		// (a thread of its own: the map's cloud cover runs on the GPU once this is done)
		PlanetCloudGpu::warm_up();
		ground->set_burst(false);
		load_label->set_visible(false);
		target()->set_process_mode(Node::PROCESS_MODE_INHERIT);
		Ref<Tween> fade = create_tween(); // the dark lifts
		fade->tween_property(dark, "modulate:a", 0.0, 0.8);
		fade->tween_callback(Callable(dark, "hide"));
		emit_signal("loaded");
	}
}

// The character is only let in once the ground under them is there: a ray from above finds the collider at the spawn spot and puts the
// character on it. Without a hit (headless, or a ship far above) they stay where they are.
void PlanetWorld::stand_on_the_ground() {
	Node3D *player = target();
	if (!player->has_method("set_free_mode") || altitude() > 500.0 || !spawn_on_solid_ground) {
		return;
	}
	PhysicsDirectSpaceState3D *space = get_viewport()->get_world_3d()->get_direct_space_state();
	Vector3 from = player->get_global_position() + Vector3(0, 1, 0) * 60.0;
	Ref<PhysicsRayQueryParameters3D> query = PhysicsRayQueryParameters3D::create(from, from + Vector3(0, -1, 0) * 160.0, 1);
	Dictionary hit = space->intersect_ray(query);
	if (hit.is_empty()) {
		return;
	}
	Vector3 position = hit["position"];
	player->set_global_position(position + Vector3(0, 1, 0) * 0.05);
	if (OS::get_singleton()->has_environment("PLANET_TIMING")) {
		UtilityFunctions::print(vformat("PLANET_TIMING stood on the ground at %.1f m", position.y));
	}
}

// Metres above sea level at the target (the ground under it, not its feet).
double PlanetWorld::altitude() const {
	return planet_position().length() - settings->get_radius();
}

// Turns/shifts the planet if the target has walked far (also done every physics frame).
void PlanetWorld::update_now() {
	_physics_process(0.0);
	get_surface()->update(planet_position());
}

void PlanetWorld::_exit_tree() {
	PlanetCloudGpu::stop();
}

void PlanetWorld::_physics_process(double p_delta) {
	Node3D *player = target();
	if (player == nullptr) {
		return;
	}
	if (loading) {
		wait_for_the_ground(p_delta);
		return;
	}
	Vector3 here = player->get_global_position();
	bool moved = false;
	if ((here - frame->get_origin_w()).length() > REBASE_DISTANCE) {
		frame->rebase(here);
		rebases += 1;
		moved = true;
	}
	if (here.length() > RECENTER_DISTANCE) {
		Vector3 back = -here;
		frame->shift(back);
		player->set_global_position(player->get_global_position() + back);
		moved = true;
	}
	PlanetSurface *ground = get_surface();
	if (moved) {
		ground->place_all();
		publish_frame();
	}
	timer -= p_delta;
	if (timer <= 0.0 || moved) {
		timer = 0.3;
		ground->update(planet_position());
	}
	// the planet is the realistic look (smooth normals, finer plants, the sea's depth)
	script_of("res://systems/world_gen/world_wind.gd")->call("set_realism", 1.0);
	weather_timer -= p_delta;
	if (weather_timer <= 0.0 && !loading) {
		weather_timer = 1.5;
		pick_the_weather();
	}
	keep_the_weather_near_the_ground();
	follow_the_ground();
	Object *effects = get_weather();
	effects->call("update", player->get_global_position(), p_delta);
	if (!loading) {
		clock->advance(p_delta * settings->get_time_scale() * time_rate);
		drift_the_clouds(p_delta * settings->get_time_scale() * time_rate);
	}
	set_the_sun();
	Object *air = get_atmosphere();
	if (settings->get_animals_on()) {
		get_fauna()->call("update", player->get_global_position(), 1.0 - (double)air->call("night_amount"), p_delta);
	}
	Object *swimming = get_swim();
	if (swimming != nullptr) {
		air->set("underwater", swimming->get("underwater"));
	}
	Camera3D *camera = get_viewport()->get_camera_3d();
	if (camera != nullptr) {
		// far enough to see the whole cap of the planet in sight: its horizon is that far away
		double high = std::max(altitude(), 0.0);
		double horizon = std::sqrt(high * (2.0 * settings->get_radius() + high));
		camera->set_far(std::max(std::min(settings->get_radius() * 1.2, 600000.0), horizon * 1.1 + 2000.0));
		// the near plane grows with the height: the depth range stays workable and nothing is that close; and never under a ten-millionth of the
		// far plane: past about 2^24 the projection breaks and NOTHING is drawn
		camera->set_near(std::max(CLAMP(high * 0.0005, 0.01, 2000.0), (double)camera->get_far() / 1.0e7));
	}
	Object::cast_to<Node3D>(air)->set_global_position(player->get_global_position());
	air->set("altitude", altitude());
}
