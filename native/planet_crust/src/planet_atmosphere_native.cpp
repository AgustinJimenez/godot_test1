#include "planet_atmosphere_native.h"

#include "graphics_lookup.h"
#include "planet_sky_native.h"

#include <godot_cpp/classes/camera3d.hpp>
#include <godot_cpp/classes/compositor.hpp>
#include <godot_cpp/classes/compositor_effect.hpp>
#include <godot_cpp/classes/fast_noise_lite.hpp>
#include <godot_cpp/classes/light3d.hpp>
#include <godot_cpp/classes/os.hpp>
#include <godot_cpp/classes/rendering_server.hpp>
#include <godot_cpp/classes/resource_loader.hpp>
#include <godot_cpp/classes/shader.hpp>
#include <godot_cpp/classes/sky.hpp>
#include <godot_cpp/classes/viewport.hpp>
#include <godot_cpp/core/math.hpp>

#include <algorithm>
#include <cmath>

using namespace godot;

static double smooth_step(double p_from, double p_to, double p_x) {
	double t = CLAMP((p_x - p_from) / (p_to - p_from), 0.0, 1.0);
	return t * t * (3.0 - 2.0 * t);
}

static double lerp_d(double p_a, double p_b, double p_t) {
	return p_a + (p_b - p_a) * p_t;
}

static Variant graphics_value(const StringName &p_key) {
	Node *settings = graphics_settings_node();
	return settings != nullptr ? settings->call("get_graphics_value", p_key) : Variant();
}

static int graphics_int(const StringName &p_key) {
	Variant v = graphics_value(p_key);
	return v.get_type() == Variant::NIL ? 0 : (int)(int64_t)v;
}

static bool graphics_bool(const StringName &p_key) {
	Variant v = graphics_value(p_key);
	return v.get_type() == Variant::NIL ? false : (bool)v;
}

static Color colour_of(const Vector3 &p_v) {
	return Color((float)p_v.x, (float)p_v.y, (float)p_v.z);
}

void PlanetAtmosphere::_bind_methods() {
	NP_BIND(PlanetAtmosphere, Variant::FLOAT, time_of_day)
	NP_BIND(PlanetAtmosphere, Variant::FLOAT, day_seconds)
	NP_BIND_STATE(PlanetAtmosphere, Variant::VECTOR3, planet_centre)
	NP_BIND_STATE(PlanetAtmosphere, Variant::FLOAT, radius)
	NP_BIND_STATE(PlanetAtmosphere, Variant::FLOAT, air_height)
	NP_BIND_STATE(PlanetAtmosphere, Variant::FLOAT, sun_strength)
	NP_BIND_STATE(PlanetAtmosphere, Variant::FLOAT, scatter_intensity)
	NP_BIND_STATE(PlanetAtmosphere, Variant::FLOAT, altitude)
	NP_BIND_STATE(PlanetAtmosphere, Variant::FLOAT, cloud_floor)
	NP_BIND_STATE(PlanetAtmosphere, Variant::FLOAT, sun_size)
	NP_BIND_STATE(PlanetAtmosphere, Variant::COLOR, star_tint)
	NP_BIND_STATE(PlanetAtmosphere, Variant::BOOL, clouds_hidden)
	NP_BIND_STATE(PlanetAtmosphere, Variant::FLOAT, haze_wanted)
	NP_BIND_STATE(PlanetAtmosphere, Variant::FLOAT, dust_wanted)
	NP_BIND_STATE(PlanetAtmosphere, Variant::FLOAT, mist_wanted)
	NP_BIND_STATE(PlanetAtmosphere, Variant::FLOAT, glow_strength)
	NP_BIND_STATE(PlanetAtmosphere, Variant::BOOL, fog_hidden)
	NP_BIND_STATE(PlanetAtmosphere, Variant::FLOAT, sun_cover)
	NP_BIND_STATE(PlanetAtmosphere, Variant::FLOAT, moon_shadow)
	NP_BIND_STATE(PlanetAtmosphere, Variant::FLOAT, cloud_on)
	NP_BIND_STATE(PlanetAtmosphere, Variant::VECTOR3, cloud_drift)
	NP_BIND_STATE(PlanetAtmosphere, Variant::FLOAT, overcast)
	NP_BIND_STATE(PlanetAtmosphere, Variant::FLOAT, flash)
	NP_BIND_STATE(PlanetAtmosphere, Variant::FLOAT, fog_extra)
	NP_BIND_STATE(PlanetAtmosphere, Variant::FLOAT, cloud_cover)
	NP_BIND_STATE(PlanetAtmosphere, Variant::FLOAT, cloud_dark)
	NP_BIND_STATE(PlanetAtmosphere, Variant::FLOAT, realism)
	NP_BIND_STATE(PlanetAtmosphere, Variant::BOOL, underwater)
	NP_BIND_STATE(PlanetAtmosphere, Variant::VECTOR3, sun_direction)
	NP_BIND_STATE(PlanetAtmosphere, Variant::VECTOR3, moon_direction)
	NP_BIND_STATE(PlanetAtmosphere, Variant::FLOAT, moon_lit)
	NP_BIND_OBJECT_AS(PlanetAtmosphere, sun, "DirectionalLight3D")
	NP_BIND_OBJECT_AS(PlanetAtmosphere, moon, "DirectionalLight3D")
	NP_BIND_OBJ(PlanetAtmosphere, environment, "Environment")
	NP_BIND_OBJ(PlanetAtmosphere, sky_material, "ShaderMaterial")
	ClassDB::bind_method(D_METHOD("air_scale"), &PlanetAtmosphere::air_scale);
	ClassDB::bind_method(D_METHOD("air_top"), &PlanetAtmosphere::air_top);
	ClassDB::bind_method(D_METHOD("night_amount"), &PlanetAtmosphere::night_amount);
	ClassDB::bind_method(D_METHOD("set_cloud_parameters", "material"), &PlanetAtmosphere::set_cloud_parameters);
	ClassDB::bind_static_method("PlanetAtmosphere", D_METHOD("worley_texture"), &PlanetAtmosphere::worley_texture);
}

// The air's size against the Earth's: the planet's radius over the Earth's (see PlanetAir).
double PlanetAtmosphere::air_scale() const {
	return PlanetAir::scale_for(radius);
}

// Metres above the surface where this planet's air ends.
double PlanetAtmosphere::air_top() const {
	return air_height * air_scale();
}

void PlanetAtmosphere::_ready() {
	DirectionalLight3D *sun_light = memnew(DirectionalLight3D);
	sun_light->set_shadow(true);
	sun_light->set_param(Light3D::PARAM_SHADOW_MAX_DISTANCE, 220.0);
	sun_light->set_shadow_mode(DirectionalLight3D::SHADOW_ORTHOGONAL);
	add_child(sun_light);
	set_sun(sun_light);
	DirectionalLight3D *moon_light = memnew(DirectionalLight3D);
	moon_light->set_color(Color(0.55f, 0.65f, 1.0f));
	moon_light->set_sky_mode(DirectionalLight3D::SKY_MODE_LIGHT_ONLY);
	moon_light->set_shadow(true);
	moon_light->set_param(Light3D::PARAM_SHADOW_MAX_DISTANCE, 120.0);
	add_child(moon_light);
	set_moon(moon_light);
	sky_material.instantiate();
	sky_material->set_shader(ResourceLoader::get_singleton()->load("res://shaders/world/planet_sky.gdshader"));
	Ref<Sky> sky;
	sky.instantiate();
	sky->set_material(sky_material);
	sky->set_radiance_size(Sky::RADIANCE_SIZE_128);
	sky->set_process_mode(Sky::PROCESS_MODE_REALTIME);
	environment.instantiate();
	environment->set_background(Environment::BG_SKY);
	environment->set_sky(sky);
	environment->set_glow_enabled(true);
	environment->set_glow_intensity(0.4f);
	environment->set_glow_bloom(0.04f);
	environment->set_ssao_enabled(true);
	environment->set_fog_density(0.0032f);
	environment->set_ambient_source(Environment::AMBIENT_SOURCE_SKY);
	environment->set_reflection_source(Environment::REFLECTION_SOURCE_SKY);
	environment->set_ambient_light_sky_contribution(0.92f);
	environment->set_ambient_light_color(Color(0.1f, 0.13f, 0.25f));
	environment->set_volumetric_fog_enabled(false);
	environment->set_volumetric_fog_temporal_reprojection_enabled(true);
	environment->set_volumetric_fog_gi_inject(0.0f);
	environment->set_volumetric_fog_ambient_inject(0.3f);
	environment->set_volumetric_fog_anisotropy(0.6f); // (light shafts: the light scatters forward)
	environment->set_volumetric_fog_length(120.0f);
	environment->set_volumetric_fog_detail_spread(2.0f);
	own_every_look_setting();
	world_environment = memnew(WorldEnvironment);
	world_environment->set_environment(environment);
	add_child(world_environment);
	apply();
}

// The planet decides how it looks: every fog, tone and colour setting of the environment is set here, so no default of the engine (or of a
// version of it) leaks in. The density, the colours and the sky's share of the fog change every frame in `apply`; these stay as they are.
void PlanetAtmosphere::own_every_look_setting() {
	environment->set_fog_enabled(true);
	environment->set_fog_mode(Environment::FOG_MODE_EXPONENTIAL);
	environment->set_fog_light_energy(1.0f);
	environment->set_fog_sun_scatter(0.0f);
	environment->set_fog_height(0.0f);
	environment->set_fog_height_density(0.0f);
	environment->set_fog_depth_begin(10.0f); // (used by the depth mode only)
	environment->set_fog_depth_end(100.0f);
	environment->set_fog_depth_curve(1.0f);
	environment->set_tonemapper((Environment::ToneMapper)graphics_int("tone_mapper"));
	environment->set_tonemap_exposure(1.0f);
	environment->set_tonemap_white(2.0f); // (filmic: a white of 1 clips every highlight early and lifts the mid tones; UE5 keeps a long shoulder)
	environment->set_adjustment_enabled(false);
	environment->set_adjustment_brightness(1.0f);
	environment->set_adjustment_contrast(1.0f);
	environment->set_adjustment_saturation(1.0f);
}

void PlanetAtmosphere::_process(double p_delta) {
	if (day_seconds > 0.0) {
		time_of_day = Math::fposmod(time_of_day + p_delta * 24.0 / day_seconds, 24.0);
	}
	apply();
}

// Light shafts: volumetric fog, only near the ground (a froxel grid cannot cover a planet), fading out with the altitude, its density following
// the haze of the place (humid air shows the sun's beams, dry air hardly). Off underwater and when the setting is off.
void PlanetAtmosphere::shafts() {
	bool wanted = graphics_bool("volumetric_fog");
	double low = 1.0 - smooth_step(600.0, 2500.0, std::max(altitude, 0.0));
	bool on = wanted && !underwater && !fog_hidden && low > 0.02;
	environment->set_volumetric_fog_enabled(on);
	if (!on) {
		return;
	}
	double humid = CLAMP(haze - 0.4, 0.0, 1.8);
	// the beams show when the sun is low (dawn, dusk): more haze lit then, and the light is scattered forward, toward the eye that looks at the
	// sun (anisotropy), through a longer stretch of air
	Vector3 up_here = (get_global_position() - planet_centre).normalized();
	double low_sun = 1.0 - smooth_step(0.05, 0.6, CLAMP(sun_direction.dot(up_here), 0.0, 1.0));
	double density_here = (0.0018 + 0.0018 * humid + fog_extra * 0.3) * (1.0 + 4.0 * low_sun);
	environment->set_volumetric_fog_density((float)(density_here * low));
	environment->set_volumetric_fog_anisotropy(0.7f);
	environment->set_volumetric_fog_length(220.0f);
	environment->set_volumetric_fog_albedo(environment->get_fog_light_color().lerp(Color(1, 1, 1), 0.45f));
	environment->set_volumetric_fog_sky_affect(0.0f);
	get_sun()->set_param(Light3D::PARAM_VOLUMETRIC_FOG_ENERGY, 1.0);
}

// The glow and flare ghosts round the sun (PlanetSunGlow): fainter as clouds, an eclipse or the horizon take the sun's light, none at night or
// under water.
void PlanetAtmosphere::sun_glow(const Vector3 &p_sun_dir) {
	if (OS::get_singleton()->get_environment("NO_SUN_GLOW") != "") {
		return;
	}
	DirectionalLight3D *sun_light = get_sun();
	if (glow.is_null()) {
		glow.instantiate();
		Ref<Compositor> compositor;
		compositor.instantiate();
		TypedArray<CompositorEffect> effects;
		effects.push_back(glow);
		compositor->set_compositor_effects(effects);
		world_environment->set_compositor(compositor);
	}
	glow->set_sun_direction(p_sun_dir);
	glow->set_tint(sun_light->get_color());
	int quality = graphics_int("shadow_quality");
	bool cheap = quality < 2; // (the Off and Low presets)
	glow->set_strength(underwater || cheap ? 0.0 : glow_strength * (double)sun_light->get_param(Light3D::PARAM_ENERGY) / sun_strength);
	// the light shafts (screen space, from the depth picture): they need the sun's own strength, so they follow the glow; NO_SUN_SHAFTS turns them off
	bool shafts_off = OS::get_singleton()->get_environment("NO_SUN_SHAFTS") != "";
	String gain_text = OS::get_singleton()->get_environment("PLANET_SHAFT_GAIN");
	double gain = gain_text != "" ? gain_text.to_float() : 0.22;
	glow->set_shafts(shafts_off ? 0.0 : glow->get_strength() * gain);
}

Ref<NoiseTexture3D> PlanetAtmosphere::worley_texture() {
	// Cellular (Worley) noise as a tiling 3D picture, made once: the small billows of the clouds are its round cells (value noise gives only soft
	// smears). NoiseTexture3D makes it on a thread: until it is ready the clouds read it as black (no detail).
	static Ref<NoiseTexture3D> *held = nullptr; // (allocated late: a file-scope engine object stops the library loading)
	if (held == nullptr) {
		held = new Ref<NoiseTexture3D>();
	}
	if (held->is_null()) {
		Ref<FastNoiseLite> noise;
		noise.instantiate();
		noise->set_noise_type(FastNoiseLite::TYPE_CELLULAR);
		noise->set_cellular_return_type(FastNoiseLite::RETURN_DISTANCE);
		noise->set_frequency(0.08f); // (about 5 cells across the 64 of the picture)
		noise->set_seed(7);
		held->instantiate();
		(*held)->set_noise(noise);
		(*held)->set_width(64);
		(*held)->set_height(64);
		(*held)->set_depth(64);
		(*held)->set_seamless(true);
		(*held)->set_normalize(true);
	}
	return *held;
}

// Gives a material that draws the clouds (the sky's, the shell's) the numbers they share: where the layer is, how the wind has carried it, how
// dark it is, the star's light and the planet.
void PlanetAtmosphere::set_cloud_parameters(const Ref<ShaderMaterial> &p_material) {
	p_material->set_shader_parameter("cloud_worley", worley_texture());
	p_material->set_shader_parameter("planet_centre", planet_centre);
	p_material->set_shader_parameter("planet_radius", radius);
	p_material->set_shader_parameter("sun_toward", sun_direction != Vector3() ? sun_direction : Vector3(0, 1, 0));
	p_material->set_shader_parameter("cloud_floor", cloud_floor);
	p_material->set_shader_parameter("clouds_off", clouds_hidden ? 1.0 : 0.0);
	static const double steps[3] = { 6.0, 10.0, 16.0 };
	p_material->set_shader_parameter("cloud_steps_max", steps[CLAMP(graphics_int("cloud_quality"), 0, 2)]);
	p_material->set_shader_parameter("cloud_depth", CLOUD_DEPTH);
	p_material->set_shader_parameter("cloud_drift", cloud_drift);
	p_material->set_shader_parameter("cloud_dark", std::max(cloud_dark, overcast * 0.6));
	p_material->set_shader_parameter("cloud_least", overcast);
	p_material->set_shader_parameter("cloud_sun", sun_strength);
	p_material->set_shader_parameter("star_tint", Vector3(star_tint.r, star_tint.g, star_tint.b));
	// the sun's path through the air against the Earth's (a small planet has a short one)
	double least_radius = PlanetAir::get_min_air_scale() * PlanetAir::get_earth_radius();
	p_material->set_shader_parameter("cloud_path", std::sqrt(std::min(1.0, radius / least_radius)));
}

// The clouds' shadow on the ground: where the layer is, which way the star is, how the wind has carried the clouds (the ground shader draws the
// same clouds the sky does).
void PlanetAtmosphere::share_the_clouds(const Vector3 &p_sun_dir) {
	bool on = graphics_bool("cloud_shadows") && !clouds_hidden;
	double strength = on && cloud_on > 0.0 ? 1.0 - overcast * 0.4 : 0.0;
	RenderingServer *rs = RenderingServer::get_singleton();
	rs->global_shader_parameter_set("cloud_shadow", Color((float)strength, (float)std::max(cloud_dark, overcast * 0.6), (float)overcast, 0.0f));
	rs->global_shader_parameter_set("cloud_layer", Color((float)radius, (float)cloud_floor, (float)CLOUD_DEPTH, 0.0f));
	rs->global_shader_parameter_set("cloud_centre", planet_centre);
	rs->global_shader_parameter_set("cloud_sun_world", p_sun_dir);
	rs->global_shader_parameter_set("cloud_drift_planet", cloud_drift);
}

void PlanetAtmosphere::apply() {
	if (environment.is_null()) {
		return;
	}
	DirectionalLight3D *sun_light = get_sun();
	DirectionalLight3D *moon_light = get_moon();
	const Vector3 here = get_global_position();
	const Vector3 up = (here - planet_centre).normalized();
	const Vector3 from = here - planet_centre;
	const double scale = air_scale();
	const double top = radius + air_top();
	const Vector3 sun_dir = sun_direction != Vector3() ? sun_direction : Vector3(0, 1, 0);
	share_the_clouds(sun_dir);
	const double height = sun_dir.dot(up);
	// the light of the sun, as much of each colour as the air lets by
	Vector3 through = PlanetAir::sun_transmittance(from, sun_dir, radius, top, scale);
	double strongest = std::max(std::max(through.x, through.y), through.z);
	Color lamp_color(1, 1, 1);
	if (strongest > 0.0001) {
		lamp_color = Color((float)(through.x / strongest), (float)(through.y / strongest), (float)(through.z / strongest));
	}
	sun_light->set_color(lamp_color * star_tint);
	sun_light->set_param(Light3D::PARAM_ENERGY, sun_strength * strongest * (1.0 - overcast * 0.7) * (1.0 - sun_cover * 0.97));
	sun_light->look_at_from_position(sun_dir * 100.0, Vector3(), Vector3(0, 0, -1));
	// how dark it is for the eye: the glow of the sky after sunset goes on a while
	night = 1.0 - smooth_step(-0.25, 0.05, height);
	Vector3 moon_toward = moon_direction != Vector3() ? moon_direction : -sun_dir;
	double moon_risen = smooth_step(-0.05, 0.15, moon_toward.dot(up));
	moon_light->look_at_from_position(moon_toward * 100.0, Vector3(), Vector3(0, 0, -1));
	double moon_light_energy = 0.25 * moon_lit * moon_risen * night * (1.0 - overcast * 0.6);
	moon_light->set_param(Light3D::PARAM_ENERGY, moon_light_energy * (1.0 - moon_shadow * 0.85));
	// the sky shader's own numbers
	double star_k = 1.0 - std::max(cloud_cover * 0.5, overcast) * 0.9;
	sky_material->set_shader_parameter("planet_centre", planet_centre);
	sky_material->set_shader_parameter("planet_radius", radius);
	sky_material->set_shader_parameter("atmosphere_top", air_top());
	sky_material->set_shader_parameter("air_scale", scale);
	sky_material->set_shader_parameter("intensity", scatter_intensity * (1.0 - overcast * 0.5));
	sky_material->set_shader_parameter("sun_toward", sun_dir);
	sky_material->set_shader_parameter("moon_direction", moon_toward);
	sky_material->set_shader_parameter("sun_size", CLAMP(sun_size, 0.3, 5.0));
	sky_material->set_shader_parameter("moon_lit", moon_lit);
	sky_material->set_shader_parameter("star_k", star_k);
	sky_material->set_shader_parameter("cloud_on", cloud_on);
	set_cloud_parameters(sky_material);
	// the air thins with height, so the ambient light and the fog do too
	double air = std::exp(-std::max(altitude, 0.0) / 1500.0); // the fog thins over a game kilometre or so
	double inside = 1.0 - smooth_step(air_top() * 0.5, air_top(), std::max(altitude, 0.0));
	// a low sun lights the ground at a slant and the sky fills the shadows: a lift of the sky light at dawn and dusk (a real dawn shows the
	// shadowed side lit softly, never black)
	double low_sun_fill = (1.0 - smooth_step(0.02, 0.4, height)) * smooth_step(-0.14, 0.0, height);
	environment->set_ambient_light_energy((float)(1.0 + flash * 1.5 + 1.6 * low_sun_fill));
	// the eye adapts to the dark: a trace of starlight and airglow inside the air (none in space, where only the sun lights anything)
	environment->set_ambient_light_sky_contribution((float)lerp_d(1.0, 0.45, inside));
	environment->set_ambient_light_color(Color(0.07f, 0.09f, 0.17f) * (float)inside);
	// fog: the colour of the air at the horizon
	Vector3 along = std::abs(height) < 0.999 ? (sun_dir - up * height).normalized() : Vector3(1, 0, 0);
	Vector3 toward = (along * 0.95 + up * 0.05).normalized();
	Vector3 away = (-along * 0.95 + up * 0.05).normalized();
	Vector3 near_sun = PlanetAir::sky_color(from, toward, sun_dir, radius, top, scatter_intensity, scale);
	Vector3 far_sun = PlanetAir::sky_color(from, away, sun_dir, radius, top, scatter_intensity, scale);
	// the fog is the air's colour seen away from the sun (toward it the glare would wash it white)
	Vector3 haze_colour = far_sun * 0.85 + near_sun * 0.15;
	// (the scene is lit by the sun as the air lets it through, so haze brighter than that washes out)
	double cap = std::max(0.25, std::min(strongest * 1.3, 0.8));
	haze_colour = Vector3(std::min((double)haze_colour.x, cap), std::min((double)haze_colour.y, cap), std::min((double)haze_colour.z, cap));
	Color fog_color = colour_of(haze_colour);
	environment->set_fog_light_color(fog_color.lerp(Color(0.5f, 0.55f, 0.6f) * (float)std::max(strongest, 0.05), (float)(overcast * 0.5)));
	// the weather's fog (snow, rain, mist) lives in the low air too: it thins with the height, or from orbit the whole planet would be buried
	// under it
	haze = lerp_d(haze, haze_wanted, 0.02);
	dust = lerp_d(dust, dust_wanted, 0.02);
	mist = lerp_d(mist, mist_wanted, 0.01);
	double density = (PLANET_FOG * haze + 0.0008 * dust + 0.0028 * mist + fog_extra) * air;
	// dust tints the haze the colour of the ground it came from
	environment->set_fog_light_color(environment->get_fog_light_color().lerp(Color(0.74f, 0.62f, 0.44f) * (float)std::max(strongest, 0.05), (float)(dust * 0.45)));
	if (fog_hidden) {
		density = 0.0;
	}
	environment->set_fog_density((float)(underwater ? UNDERWATER_FOG : std::max(density, 0.0)));
	environment->set_fog_aerial_perspective(0.0f);
	// toward the sun the haze takes the sun's own colour (warm at dawn and dusk, white at noon); away from it it stays the blue of the air: the
	// warm / cool split of a real landscape
	environment->set_fog_sun_scatter(!underwater ? (float)CLAMP(0.55 * (1.0 - overcast), 0.0, 0.55) : 0.0f);
	shafts();
	sun_glow(sun_dir);
	environment->set_fog_sky_affect(altitude > air_top() ? 0.0f : 0.35f);
	if (underwater) {
		environment->set_fog_light_color(Color(0.05f, 0.3f, 0.4f) * (float)lerp_d(0.25, 1.0, 1.0 - night));
		environment->set_fog_sky_affect(1.0f);
	}
	environment->set_bg_energy_multiplier(1.0f);
	// the planet's own materials take their haze by height (planet_haze.gdshaderinc): the same density at the ground, without the thinning by the
	// camera's altitude (the shader sums the layer along each line of sight)
	double at_ground = fog_hidden ? 0.0 : PLANET_FOG * haze + 0.0008 * dust + 0.0028 * mist + fog_extra;
	// (the whole layer seen straight down is some 0.3 of optical depth: a thick fog is a low layer, thin haze a deep one)
	double layer = CLAMP(HAZE_DEPTH / std::max(at_ground, 0.000001), 60.0, 1500.0);
	if (underwater) {
		at_ground = UNDERWATER_FOG;
		layer = 1.0e9;
	}
	RenderingServer *rs = RenderingServer::get_singleton();
	rs->global_shader_parameter_set("haze_air", Color((float)at_ground, (float)layer, 0.0f, (float)radius));
	// (the haze is lit like the scene, which the filmic curve with a white of 4 darkens: the sky's own colour is not that bright where it meets
	// the ground; a dusk haze at 0.7 turned the far land milky white against a bluer sky)
	Color haze_lit = environment->get_fog_light_color();
	rs->global_shader_parameter_set("haze_colour", Color(haze_lit.r * 0.58f, haze_lit.g * 0.6f, haze_lit.b * 0.66f));
	Camera3D *eye = is_inside_tree() ? get_viewport()->get_camera_3d() : nullptr;
	rs->global_shader_parameter_set("haze_eye", (eye != nullptr ? eye->get_global_position() : here) - planet_centre);
	// toward the star the air is warmer and brighter than away from it: the difference of the two sky colours sampled for the fog, carried over a
	// wide lobe (haze_sun is added to the haze colour by the cosine to the star, cubed)
	Vector3 warm = (near_sun - far_sun) * 0.25;
	rs->global_shader_parameter_set("haze_sun", Color((float)CLAMP(warm.x, 0.0, 0.6), (float)CLAMP(warm.y, 0.0, 0.5), (float)CLAMP(warm.z, 0.0, 0.4)));
	environment->set_tonemapper((Environment::ToneMapper)graphics_int("tone_mapper"));
	sun_light->set_shadow_mode(DirectionalLight3D::SHADOW_ORTHOGONAL);
	int shadows = graphics_int("shadow_quality");
	sun_light->set_shadow(shadows > 0);
	static const double reach[4] = { 0.0, 90.0, 160.0, 300.0 };
	sun_light->set_param(Light3D::PARAM_SHADOW_MAX_DISTANCE, reach[CLAMP(shadows, 0, 3)]);
	sun_light->set_param(Light3D::PARAM_SIZE, 0.5); //(the sun is half a degree wide: shadow edges soften with the distance from what casts them, as in UE5's PCSS)
	if (shadows == 1 || shadows == 2) { // Low / Medium: two cascades, the near one for what is close (sharp), the far one out to 1.7 times the old reach
		sun_light->set_shadow_mode(DirectionalLight3D::SHADOW_PARALLEL_2_SPLITS);
		sun_light->set_param(Light3D::PARAM_SHADOW_MAX_DISTANCE, shadows == 1 ? 150.0 : 250.0);
		sun_light->set_param(Light3D::PARAM_SHADOW_SPLIT_1_OFFSET, 0.2);
	}
	if (shadows >= 3) { // High: four cascades out to 1.5 km, long dune and ridge shadows (+3 ms in forest)
		sun_light->set_shadow_mode(DirectionalLight3D::SHADOW_PARALLEL_4_SPLITS);
		sun_light->set_param(Light3D::PARAM_SHADOW_MAX_DISTANCE, 1500.0);
		sun_light->set_param(Light3D::PARAM_SHADOW_SPLIT_1_OFFSET, 0.03);
		sun_light->set_param(Light3D::PARAM_SHADOW_SPLIT_2_OFFSET, 0.12);
		sun_light->set_param(Light3D::PARAM_SHADOW_SPLIT_3_OFFSET, 0.4);
	}
}
