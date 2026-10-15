class_name WorldAtmosphere
extends Node3D
## Sun, sky and fog over the world, with a day that goes round. `time_of_day` is in hours (0..24);
## a day lasts `day_seconds` (0 = the clock stands still). The sky colours, the light and the fog
## all follow the sun's height, so dawn and dusk go orange and the night goes blue.

const BASE_FOG := 0.0032
const UNDERWATER_FOG := 0.05

@export var time_of_day := 10.0
@export var day_seconds := 0.0

var sun: DirectionalLight3D
var environment: Environment
var sky_material: ShaderMaterial
var moon: DirectionalLight3D

var overcast := 0.0 # 0 clear .. 1 heavy cloud: greys the sky, dims the sun
var flash := 0.0 # lightning, 0..1
var fog_extra := 0.0 # added fog density (weather)
var cloud_cover := 0.3 # for the realistic sky's clouds (weather sets these two)
var cloud_dark := 0.0
var realism := 0.0 # 0 low-poly .. 1 realistic (the world sets it)
var underwater := false # the camera is under the sea

var _night_amount := 0.0 # 0 day .. 1 deep night (weather reads it)


func _init() -> void:
	sun = DirectionalLight3D.new()
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 220.0
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	add_child(sun)
	moon = DirectionalLight3D.new()
	moon.light_color = Color(0.55, 0.65, 1.0)
	moon.sky_mode = DirectionalLight3D.SKY_MODE_LIGHT_ONLY
	moon.shadow_enabled = true
	moon.directional_shadow_max_distance = 120.0
	add_child(moon)
	sky_material = ShaderMaterial.new()
	sky_material.shader = preload("res://shaders/world/world_sky.gdshader")
	var sky := Sky.new()
	sky.sky_material = sky_material
	environment = Environment.new()
	environment.background_mode = Environment.BG_SKY
	environment.sky = sky
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment.fog_enabled = true
	environment.fog_density = BASE_FOG
	environment.fog_sky_affect = 0.35
	environment.glow_enabled = true
	environment.glow_intensity = 0.4
	environment.glow_bloom = 0.04
	environment.ssao_enabled = true
	var world_environment := WorldEnvironment.new()
	world_environment.environment = environment
	add_child(world_environment)


func _ready() -> void:
	_apply()


func _process(delta: float) -> void:
	if day_seconds > 0.0:
		time_of_day = fposmod(time_of_day + delta * 24.0 / day_seconds, 24.0)
	_apply()


## 1 at noon, 0 at the horizon, negative below it.
func sun_height() -> float:
	return sin((time_of_day - 6.0) / 24.0 * TAU)


func night_amount() -> float:
	return _night_amount


func _apply() -> void:
	var height := sun_height()
	var angle := (time_of_day - 6.0) / 24.0 * TAU
	# the sun climbs in the east (+x), crosses the south and sets in the west
	var direction := Vector3(cos(angle), sin(angle), 0.35).normalized()
	sun.look_at_from_position(direction * 100.0, Vector3.ZERO, Vector3.FORWARD)
	var day := smoothstep(-0.05, 0.35, height)
	var dusk := 1.0 - smoothstep(0.0, 0.35, absf(height))
	_night_amount = 1.0 - smoothstep(-0.25, 0.05, height)
	sun.light_energy = lerpf(0.0, 0.95, smoothstep(-0.02, 0.2, height)) * (1.0 - overcast * 0.7)
	sun.light_color = Color(1.0, 0.95, 0.85).lerp(Color(1.0, 0.55, 0.3), dusk * (1.0 - day * 0.6))
	var top_day := Color(0.25, 0.47, 0.86)
	var top_night := Color(0.015, 0.025, 0.07)
	var horizon_day := Color(0.66, 0.78, 0.92)
	var horizon_dusk := Color(0.95, 0.52, 0.32)
	var horizon_night := Color(0.05, 0.07, 0.14)
	var top := top_night.lerp(top_day, day)
	var horizon := horizon_night.lerp(horizon_day, day).lerp(horizon_dusk, dusk * 0.8)
	var grey_top := Color(0.38, 0.4, 0.45) * day + Color(0.02, 0.02, 0.03)
	var grey_horizon := Color(0.55, 0.57, 0.6) * day + Color(0.03, 0.03, 0.04)
	top = top.lerp(grey_top, overcast * 0.9)
	horizon = horizon.lerp(grey_horizon, overcast * 0.9)
	top = top.lerp(Color(0.8, 0.82, 1.0), flash * 0.6)
	horizon = horizon.lerp(Color(0.85, 0.87, 1.0), flash * 0.6)
	sky_material.set_shader_parameter(&"top_color", top)
	sky_material.set_shader_parameter(&"horizon_color", horizon)
	sky_material.set_shader_parameter(&"ground_color", horizon.darkened(0.12))
	sky_material.set_shader_parameter(&"night", _night_amount)
	sky_material.set_shader_parameter(&"overcast", overcast)
	sky_material.set_shader_parameter(&"moon_direction", -direction)
	sky_material.set_shader_parameter(&"sun_toward", direction)
	sky_material.set_shader_parameter(&"cloud_cover", cloud_cover)
	sky_material.set_shader_parameter(&"cloud_dark", cloud_dark)
	moon.look_at_from_position(-direction * 100.0, Vector3.ZERO, Vector3.FORWARD)
	moon.light_energy = _night_amount * 0.32 * (1.0 - overcast * 0.6)
	environment.fog_light_color = horizon.lerp(Color(0.5, 0.55, 0.6), 0.2)
	# the realistic sky and the volumetric fog add haze of their own
	var fog_scale := 1.0 - realism * 0.45
	environment.fog_aerial_perspective = realism * 0.7
	environment.fog_density = UNDERWATER_FOG if underwater else (BASE_FOG + fog_extra) * fog_scale
	environment.volumetric_fog_enabled = realism > 0.5 and not underwater
	environment.volumetric_fog_density = 0.0016 + fog_extra * 0.4
	environment.volumetric_fog_albedo = horizon.lerp(Color(1, 1, 1), 0.5)
	environment.volumetric_fog_length = 140.0
	var real := realism > 0.5
	environment.tonemap_mode = (Environment.TONE_MAPPER_ACES if real
			else Environment.TONE_MAPPER_FILMIC)
	sun.light_volumetric_fog_energy = 1.0 if real else 0.0
	sun.directional_shadow_mode = (DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS if real
			else DirectionalLight3D.SHADOW_ORTHOGONAL)
	if underwater:
		environment.fog_light_color = Color(0.05, 0.3, 0.4) * lerpf(0.25, 1.0, day)
	environment.fog_sky_affect = 1.0 if underwater else 0.35
	environment.ambient_light_color = Color(0.2, 0.28, 0.5).lerp(Color(0.62, 0.7, 0.82), day)
	environment.ambient_light_energy = lerpf(0.7, 0.75, day) * (1.0 - overcast * 0.1) + flash * 1.5
	environment.background_energy_multiplier = lerpf(0.25, 1.0, day)
