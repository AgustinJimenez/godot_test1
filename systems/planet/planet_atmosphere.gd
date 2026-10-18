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
const CLOUD_DEPTH := 700.0 ## m thick, the layer of clouds
var cloud_floor := 450.0 ## m above the planet's radius where the layer of clouds begins
var sun_size := 1.0 ## the star's disc against the Sun's seen from the Earth (radius / distance)
var star_tint := Color.WHITE ## the star's light against the Sun's (Star.light_tint)
var clouds_hidden := false ## the debug switch: no clouds, in the sky or from above
## The haze of the place (set by the world from the local climate, eased toward here): how thick the
## air is against the planet's base (humid and warm thick, cold and dry clear) and how much dust
## (0..1) hangs in it (hot and dry places).
var haze_wanted := 1.0
var dust_wanted := 0.0
var _haze := 1.0
var _dust := 0.0
var fog_hidden := false ## the debug switch: no fog at all
var sun_cover := 0.0 ## 0..1 the share of the star the moon hides (a solar eclipse)
var moon_shadow := 0.0 ## 0..1 how deep the moon is in the planet's shadow (a lunar eclipse)
var cloud_on := 0.0 ## 0 no clouds in the sky (up high the cloud shell takes over) .. 1
var cloud_drift := Vector3.ZERO ## m, planet frame: how far the wind has carried the small clouds


## The air's size against the Earth's: the planet's radius over the Earth's (see PlanetAir).
func air_scale() -> float:
	return PlanetAir.scale_for(radius)


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
	_own_every_look_setting()


## The planet decides how it looks: every fog, tone and colour setting of the environment is set
## here, so no default of the engine (or of a version of it) leaks in. The density, the colours and
## the sky's share of the fog change every frame in `_apply`; these stay as they are.
func _own_every_look_setting() -> void:
	environment.fog_enabled = true
	environment.fog_mode = Environment.FOG_MODE_EXPONENTIAL
	environment.fog_light_energy = 1.0
	environment.fog_sun_scatter = 0.0
	environment.fog_height = 0.0
	environment.fog_height_density = 0.0
	environment.fog_depth_begin = 10.0 # (used by the depth mode only)
	environment.fog_depth_end = 100.0
	environment.fog_depth_curve = 1.0
	var mapper: int = GraphicsSettings.get_graphics_value(&"tone_mapper")
	environment.tonemap_mode = mapper as Environment.ToneMapper
	environment.tonemap_exposure = 1.0
	environment.tonemap_white = 1.0
	environment.adjustment_enabled = false
	environment.adjustment_brightness = 1.0
	environment.adjustment_contrast = 1.0
	environment.adjustment_saturation = 1.0


## Gives a material that draws the clouds (the sky's, the shell's) the numbers they share: where the
## layer is, how the wind has carried it, how dark it is, the star's light and the planet.
func set_cloud_parameters(material: ShaderMaterial) -> void:
	material.set_shader_parameter(&"planet_centre", planet_centre)
	material.set_shader_parameter(&"planet_radius", radius)
	material.set_shader_parameter(&"sun_toward", sun_direction if sun_direction != Vector3.ZERO \
			else Vector3.UP)
	material.set_shader_parameter(&"cloud_floor", cloud_floor)
	material.set_shader_parameter(&"clouds_off", 1.0 if clouds_hidden else 0.0)
	var cloud_quality: int = GraphicsSettings.get_graphics_value(&"cloud_quality")
	material.set_shader_parameter(&"cloud_steps_max", [6.0, 10.0, 16.0][clampi(cloud_quality, 0, 2)])
	material.set_shader_parameter(&"cloud_depth", CLOUD_DEPTH)
	material.set_shader_parameter(&"cloud_drift", cloud_drift)
	material.set_shader_parameter(&"cloud_dark", maxf(cloud_dark, overcast * 0.6))
	material.set_shader_parameter(&"cloud_least", overcast)
	material.set_shader_parameter(&"cloud_sun", sun_strength)
	material.set_shader_parameter(&"star_tint", Vector3(star_tint.r, star_tint.g, star_tint.b))
	# the sun's path through the air against the Earth's (a small planet has a short one)
	var least_radius := PlanetAir.MIN_AIR_SCALE * PlanetAir.EARTH_RADIUS
	material.set_shader_parameter(&"cloud_path", sqrt(minf(1.0, radius / least_radius)))


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
	sun.light_color = lamp_color * star_tint
	sun.light_energy = sun_strength * strongest * (1.0 - overcast * 0.7) * (1.0 - sun_cover * 0.97)
	sun.look_at_from_position(sun_dir * 100.0, Vector3.ZERO, Vector3.FORWARD)
	# how dark it is for the eye: the glow of the sky after sunset goes on a while
	_night_amount = 1.0 - smoothstep(-0.25, 0.05, height)
	var moon_toward := moon_direction if moon_direction != Vector3.ZERO else -sun_dir
	var moon_risen := smoothstep(-0.05, 0.15, moon_toward.dot(up))
	moon.look_at_from_position(moon_toward * 100.0, Vector3.ZERO, Vector3.FORWARD)
	var moon_light := 0.25 * moon_lit * moon_risen * _night_amount * (1.0 - overcast * 0.6)
	moon.light_energy = moon_light * (1.0 - moon_shadow * 0.85)
	# the sky shader's own numbers
	var star_k := 1.0 - maxf(cloud_cover * 0.5, overcast) * 0.9
	sky_material.set_shader_parameter(&"planet_centre", planet_centre)
	sky_material.set_shader_parameter(&"planet_radius", radius)
	sky_material.set_shader_parameter(&"atmosphere_top", air_top())
	sky_material.set_shader_parameter(&"air_scale", scale)
	sky_material.set_shader_parameter(&"intensity", scatter_intensity * (1.0 - overcast * 0.5))
	sky_material.set_shader_parameter(&"sun_toward", sun_dir)
	sky_material.set_shader_parameter(&"moon_direction", moon_toward)
	sky_material.set_shader_parameter(&"sun_size", clampf(sun_size, 0.3, 5.0))
	sky_material.set_shader_parameter(&"moon_lit", moon_lit)
	sky_material.set_shader_parameter(&"star_k", star_k)
	sky_material.set_shader_parameter(&"cloud_on", cloud_on)
	set_cloud_parameters(sky_material)
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
	# (the scene is lit by the sun as the air lets it through, so haze brighter than that washes out)
	var cap := maxf(0.25, minf(strongest * 1.3, 0.8))
	haze = Vector3(minf(haze.x, cap), minf(haze.y, cap), minf(haze.z, cap))
	var fog_color := Color(haze.x, haze.y, haze.z)
	environment.fog_light_color = fog_color.lerp(Color(0.5, 0.55, 0.6) * maxf(strongest, 0.05),
			overcast * 0.5)
	# the weather's fog (snow, rain, mist) lives in the low air too: it thins with the height, or from
	# orbit the whole planet would be buried under it
	_haze = lerpf(_haze, haze_wanted, 0.02)
	_dust = lerpf(_dust, dust_wanted, 0.02)
	var density := (BASE_FOG * _haze + 0.0016 * _dust + fog_extra) * air
	# dust tints the haze the colour of the ground it came from
	environment.fog_light_color = environment.fog_light_color.lerp(
			Color(0.74, 0.62, 0.44) * maxf(strongest, 0.05), _dust * 0.45)
	if fog_hidden:
		density = 0.0
	environment.fog_density = UNDERWATER_FOG if underwater else maxf(density, 0.0)
	environment.fog_aerial_perspective = 0.0
	environment.fog_sky_affect = 0.0 if altitude > air_top() else 0.35
	if underwater:
		environment.fog_light_color = Color(0.05, 0.3, 0.4) * lerpf(0.25, 1.0, 1.0 - _night_amount)
		environment.fog_sky_affect = 1.0
	environment.background_energy_multiplier = 1.0
	var chosen: int = GraphicsSettings.get_graphics_value(&"tone_mapper")
	environment.tonemap_mode = chosen as Environment.ToneMapper
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	var shadows: int = GraphicsSettings.get_graphics_value(&"shadow_quality")
	sun.shadow_enabled = shadows > 0
	sun.directional_shadow_max_distance = [0.0, 90.0, 160.0, 300.0][clampi(shadows, 0, 3)]
