#pragma once

// The sun, the sky and the fog of a planet, from the physics of its air (was systems/planet/planet_atmosphere.gd on top of the flat world's
// WorldAtmosphere; the planet needs none of that base: no day clock of its own, no Sky3D). The world sets where the star, the moon and the planet
// are, the weather sets the cover and the fog; every frame `_apply` turns them into the lights, the environment and the shader globals.

#include "native_props.h"
#include "planet_render_native.h"

#include <godot_cpp/classes/directional_light3d.hpp>
#include <godot_cpp/classes/environment.hpp>
#include <godot_cpp/classes/noise_texture3d.hpp>
#include <godot_cpp/classes/node3d.hpp>
#include <godot_cpp/classes/shader_material.hpp>
#include <godot_cpp/classes/world_environment.hpp>

namespace godot {

class PlanetAtmosphere : public Node3D {
	GDCLASS(PlanetAtmosphere, Node3D)

	WorldEnvironment *world_environment = nullptr;
	Ref<PlanetSunGlow> glow;
	double mist = 0.0;
	double haze = 1.0;
	double dust = 0.0;
	double night = 0.0;

	void own_every_look_setting();
	void shafts();
	void sun_glow(const Vector3 &p_sun_dir);
	void share_the_clouds(const Vector3 &p_sun_dir);
	void apply();

protected:
	static void _bind_methods();

public:
	static constexpr double UNDERWATER_FOG = 0.05;
	static constexpr double PLANET_FOG = 0.00045; // the air's own haze on a clear day, per metre
	static constexpr double HAZE_DEPTH = 0.18; // the optical depth of the whole haze layer seen straight down
	static constexpr double CLOUD_DEPTH = 700.0; // m thick, the layer of clouds

	NP_FIELD(double, time_of_day, 10.0)
	NP_FIELD(double, day_seconds, 0.0)
	NP_FIELD(Vector3, planet_centre, Vector3(0.0, -20000.0, 0.0)) // where the planet's centre is, in the world
	NP_FIELD(double, radius, 20000.0) // m
	NP_FIELD(double, air_height, 100000.0) // m above the surface where the Earth's air would end (scaled)
	NP_FIELD(double, sun_strength, 1.35)
	NP_FIELD(double, scatter_intensity, 22.0)
	NP_FIELD(double, altitude, 0.0) // m above the surface at the camera (set by the world)
	NP_FIELD(double, cloud_floor, 450.0) // m above the planet's radius where the layer of clouds begins
	NP_FIELD(double, sun_size, 1.0) // the star's disc against the Sun's seen from the Earth
	NP_FIELD(Color, star_tint, Color(1, 1, 1, 1))
	NP_FIELD(bool, clouds_hidden, false)
	NP_FIELD(double, haze_wanted, 1.0)
	NP_FIELD(double, dust_wanted, 0.0)
	NP_FIELD(double, mist_wanted, 0.0)
	NP_FIELD(double, glow_strength, 1.5)
	NP_FIELD(bool, fog_hidden, false)
	NP_FIELD(double, sun_cover, 0.0)
	NP_FIELD(double, moon_shadow, 0.0)
	NP_FIELD(double, cloud_on, 0.0)
	NP_FIELD(Vector3, cloud_drift, Vector3())
	NP_FIELD(double, overcast, 0.0)
	NP_FIELD(double, flash, 0.0)
	NP_FIELD(double, fog_extra, 0.0)
	NP_FIELD(double, cloud_cover, 0.3)
	NP_FIELD(double, cloud_dark, 0.0)
	NP_FIELD(double, realism, 0.0)
	NP_FIELD(bool, underwater, false)
	NP_FIELD(Vector3, sun_direction, Vector3())
	NP_FIELD(Vector3, moon_direction, Vector3())
	NP_FIELD(double, moon_lit, 1.0)
	NP_OBJECT_T(sun, DirectionalLight3D)
	NP_OBJECT_T(moon, DirectionalLight3D)
	Ref<Environment> environment;
	Ref<ShaderMaterial> sky_material;
	Ref<Environment> get_environment() const { return environment; }
	void set_environment(const Ref<Environment> &p_environment) { environment = p_environment; }
	Ref<ShaderMaterial> get_sky_material() const { return sky_material; }
	void set_sky_material(const Ref<ShaderMaterial> &p_material) { sky_material = p_material; }

	double air_scale() const;
	double air_top() const;
	double night_amount() const { return night; }
	void set_cloud_parameters(const Ref<ShaderMaterial> &p_material);
	static Ref<NoiseTexture3D> worley_texture();

	void _ready() override;
	void _process(double p_delta) override;
};

} // namespace godot
