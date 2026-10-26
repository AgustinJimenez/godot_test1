#pragma once

// PlanetWorld (was systems/planet/planet_world.gd): a whole planet in one node: terrain tiles, sun and sky. Give it a `target` (the player) with
// `start` and it keeps the ground built around them, turning the planet under their feet as they walk (PlanetFrame) so the game's flat-world
// assumptions (up is +Y, gravity down) keep holding. The nodes whose scripts extend flat-world GDScript classes (the atmosphere, the fauna, the
// swimming, the weather effects) and the map and menus are made through their scripts and held by id; the baking coroutines stay a small script
// (PlanetBarkBake).

#include "native_props.h"
#include "planet_clock_native.h"
#include "planet_frame_native.h"
#include "planet_noise_native.h"
#include "planet_settings_native.h"
#include "planet_surface_script_native.h"

#include <godot_cpp/classes/color_rect.hpp>
#include <godot_cpp/classes/label.hpp>
#include <godot_cpp/classes/node3d.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/rect2.hpp>
#include <godot_cpp/variant/vector3.hpp>

namespace godot {

class PlanetWorld : public Node3D {
	GDCLASS(PlanetWorld, Node3D)

	ObjectID target_id;
	double timer = 0.0;
	Label *load_label = nullptr;
	ColorRect *dark = nullptr;
	double load_time = 0.0;
	double star_disc = 1.0; // the star's disc at the semi-major distance against the Sun from the Earth
	double weather_timer = 0.0;

	void keep_the_weather_near_the_ground();
	void pick_the_weather();
	void drift_the_clouds(double p_seconds);
	void set_the_sun();
	void follow_the_ground();
	void wait_for_the_ground(double p_delta);
	void stand_on_the_ground();
	void cover_the_loading();
	static double load_plants();
	Object *make_scripted(const char *p_path) const;

protected:
	static void _bind_methods();

public:
	static constexpr double REBASE_DISTANCE = 80.0; // m walked before the planet is turned level again
	static constexpr double RECENTER_DISTANCE = 2000.0; // m from the world origin before everything is shifted back
	static constexpr double BAKE_UP_TO = 10.0; // m above the ground: higher up the ground plates have no parallax
	static constexpr double RAIN_UP_TO = 1500.0; // m above the ground: higher up there is no rain
	static constexpr double LOAD_GROUND = 2000.0; // m of ground and water built before the player is let in
	static constexpr double LOAD_PLANTS_DEFAULT = 6000.0; // m round the player planted before they are let in

	NP_FIELD(Ref<PlanetSettings>, settings, Ref<PlanetSettings>())
	NP_FIELD(double, time_of_day, 10.0)
	NP_FIELD(double, fog, 0.001) // fog density: a planet has a far horizon
	NP_FIELD(Ref<PlanetNoise>, noise, Ref<PlanetNoise>())
	NP_FIELD(Ref<PlanetFrame>, frame, Ref<PlanetFrame>())
	NP_OBJECT_T(surface, PlanetSurface)
	NP_OBJECT(atmosphere) // PlanetAtmosphere (script)
	NP_OBJECT(ground_bake) // PlanetGroundBake, or none
	NP_FIELD(double, above_ground, 0.0) // m of the target over the ground under it (updated every frame)
	NP_OBJECT(fauna) // PlanetFauna (script)
	NP_OBJECT(swim) // PlanetSwim (script)
	NP_OBJECT(map) // PlanetMap (script)
	NP_OBJECT(weather) // WorldWeather: the effects of the weather; the planet picks the state they follow
	NP_OBJECT(cloud_shell) // PlanetCloudShell
	NP_FIELD(String, weather_text, String())
	NP_FIELD(Dictionary, restored, Dictionary()) // a save's moment (UniverseSave) to bring back when `start` runs
	NP_FIELD(int64_t, weather_override, -1) // a WorldWeather.State to force, or -1 to follow the planet's climate
	NP_FIELD(double, time_rate, 1.0) // how fast time runs on top of `time_scale`: negative is backward, 0 stops it
	NP_FIELD(Ref<PlanetClock>, clock, Ref<PlanetClock>()) // the star, the orbit, the spin: where the sun is (real geometry)
	NP_OBJECT(splash)
	NP_FIELD(int64_t, rebases, 0) // how many times the planet has been turned (labs and tests)
	NP_FIELD(bool, spawn_on_solid_ground, true) // false: the character starts exactly where `start` is asked to put them
	NP_FIELD(bool, start_in_desert, false) // true: a new game starts on the dunes, not in green country
	NP_FIELD(bool, loading, false) // the player is held still while the ground around them is made
	NP_FIELD(bool, map_first, true) // the map opens first, the ground is built once it is closed (a window only)

	PlanetWorld();
	void _ready() override;
	void _exit_tree() override;
	void _physics_process(double p_delta) override;
	Node3D *target() const;
	Vector3 start(Node3D *p_target, const Vector3 &p_direction = Vector3(), double p_altitude = 0.0);
	static Vector3 nearest_point(const Vector3 &p_position);
	double altitude_of(const Vector3 &p_position) const;
	Dictionary snapshot() const;
	String season_text() const;
	void jump_time(double p_days);
	void set_hour(double p_hour);
	void set_year_share(double p_share);
	void publish_frame();
	void build_now(bool p_near_only = false);
	Vector3 planet_position() const;
	Dictionary ground_at(double p_x, double p_z, double p_near_y) const;
	double flight_floor(const Vector3 &p_position) const;
	double water_at_world(const Vector3 &p_position) const;
	Vector3 flow_at_world(const Vector3 &p_position) const;
	double altitude() const;
	void update_now();
	void on_map_shown();
};

} // namespace godot
