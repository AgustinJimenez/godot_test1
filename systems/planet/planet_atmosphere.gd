class_name PlanetAtmosphere
extends WorldAtmosphere
## The sun, the sky and the fog of a planet, from the physics of its air (PlanetAir, and the sky
## shader that does the same maths per pixel). The sun's light is what the air lets through from the
## star: white in space, yellow at noon and red low down, and none where the planet is in the way.
## The sky is the air scattering that light; above the air there is no sky, space is black and
## the only light is the sun's. The ambient light is the sky's own (the sky is rendered into the
## environment's light), so it is blue by day, red at dusk, and gone at night and in space apart
## from the moon and a trace of starlight inside the air. Sky3D is not used.

const SHADER := preload("res://shaders/world/planet_sky.gdshader")

var planet_centre := Vector3(0.0, -20000.0, 0.0) ## where the planet's centre is, in the world
var radius := 20000.0 ## m
var air_height := 100000.0 ## m above the surface where the Earth's air would end (scaled below)
var sun_strength := 1.35 ## the light energy of the unobscured sun
var scatter_intensity := 22.0
var altitude := 0.0 ## m above the surface at the camera (set by the world)


## The air's size against the Earth's: the planet's radius over the Earth's (see PlanetAir).
func air_scale() -> float:
	return radius / PlanetAir.EARTH_RADIUS


## Metres above the surface where this planet's air ends.
func air_top() -> float:
	return air_height * air_scale()


func _init() -> void:
	super()
	environment.sky.radiance_size = Sky.RADIANCE_SIZE_128
	environment.sky.process_mode = Sky.PROCESS_MODE_REALTIME
	sky_material.shader = SHADER
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	environment.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	environment.ambient_light_sky_contribution = 0.92
	environment.ambient_light_color = Color(0.1, 0.13, 0.25)
	environment.volumetric_fog_enabled = false


func _apply() -> void:
	var up := (global_position - planet_centre).normalized()
	var from := global_position - planet_centre
	var scale := air_scale()
	var top := radius + air_top()
	var sun_dir := sun_direction if sun_direction != Vector3.ZERO else Vector3.UP
	var height := sun_dir.dot(up)
	# the light of the sun, as much of each colour as the air lets by
	var through := PlanetAir.sun_transmittance(from, sun_dir, radius, top, scale)
	var strongest := maxf(maxf(through.x, through.y), through.z)
	var lamp_color := Color.WHITE
	if strongest > 0.0001:
		lamp_color = Color(through.x / strongest, through.y / strongest, through.z / strongest)
	sun.light_color = lamp_color
	sun.light_energy = sun_strength * strongest * (1.0 - overcast * 0.7)
	sun.look_at_from_position(sun_dir * 100.0, Vector3.ZERO, Vector3.FORWARD)
	# how dark it is for the eye: the glow of the sky after sunset goes on a while
	_night_amount = 1.0 - smoothstep(-0.25, 0.05, height)
	var moon_toward := moon_direction if moon_direction != Vector3.ZERO else -sun_dir
	var moon_risen := smoothstep(-0.05, 0.15, moon_toward.dot(up))
	moon.look_at_from_position(moon_toward * 100.0, Vector3.ZERO, Vector3.FORWARD)
	moon.light_energy = 0.25 * moon_lit * moon_risen * _night_amount * (1.0 - overcast * 0.6)
	# the sky shader's own numbers
	var star_k := 1.0 - maxf(cloud_cover * 0.5, overcast) * 0.9
	sky_material.set_shader_parameter(&"planet_centre", planet_centre)
	sky_material.set_shader_parameter(&"planet_radius", radius)
	sky_material.set_shader_parameter(&"atmosphere_top", air_top())
	sky_material.set_shader_parameter(&"air_scale", scale)
	sky_material.set_shader_parameter(&"intensity", scatter_intensity * (1.0 - overcast * 0.5))
	sky_material.set_shader_parameter(&"sun_toward", sun_dir)
	sky_material.set_shader_parameter(&"moon_direction", moon_toward)
	sky_material.set_shader_parameter(&"moon_lit", moon_lit)
	sky_material.set_shader_parameter(&"star_k", star_k)
	# the air thins with height, so the ambient light and the fog do too
	var air := exp(-maxf(altitude, 0.0) / 1500.0) # the fog thins over a game kilometre or so
	var inside := 1.0 - smoothstep(air_top() * 0.5, air_top(), maxf(altitude, 0.0))
	environment.ambient_light_energy = 1.0 + flash * 1.5
	# the eye adapts to the dark: a trace of starlight and airglow inside the air (none in space,
	# where only the sun lights anything)
	environment.ambient_light_sky_contribution = lerpf(1.0, 0.45, inside)
	environment.ambient_light_color = Color(0.07, 0.09, 0.17) * inside
	# fog: the colour of the air at the horizon
	var along := Vector3(sun_dir - up * height).normalized() if absf(height) < 0.999 else Vector3.RIGHT
	var toward := (along * 0.95 + up * 0.05).normalized()
	var away := (-along * 0.95 + up * 0.05).normalized()
	var near_sun := PlanetAir.sky_color(from, toward, sun_dir, radius, top, scatter_intensity, scale)
	var far_sun := PlanetAir.sky_color(from, away, sun_dir, radius, top, scatter_intensity, scale)
	# the fog is the air's colour seen away from the sun (toward it the glare would wash it white)
	var haze := far_sun * 0.85 + near_sun * 0.15
	haze = Vector3(minf(haze.x, 1.2), minf(haze.y, 1.2), minf(haze.z, 1.2))
	var fog_color := Color(haze.x, haze.y, haze.z)
	environment.fog_light_color = fog_color.lerp(Color(0.5, 0.55, 0.6) * maxf(strongest, 0.05),
			overcast * 0.5)
	var density := (BASE_FOG * air + fog_extra)
	environment.fog_density = UNDERWATER_FOG if underwater else maxf(density, 0.0)
	environment.fog_aerial_perspective = 0.0
	environment.fog_sky_affect = 0.0 if altitude > air_top() else 0.35
	if underwater:
		environment.fog_light_color = Color(0.05, 0.3, 0.4) * lerpf(0.25, 1.0, 1.0 - _night_amount)
		environment.fog_sky_affect = 1.0
	environment.background_energy_multiplier = 1.0
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	sun.directional_shadow_max_distance = 220.0
