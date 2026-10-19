class_name PlanetMotes
extends GPUParticles3D
## Dust and pollen drifting in the air round the player: tiny warm specks that catch the sun, thick
## in dry dusty places and in flowery green ones, fewer in the cold, none in rain, snow, fog, at
## night or under water. A box of air that follows the camera; the specks are in world space, so they
## hang where they were while the player walks through them. Setting `particles` (High and up).

const BOX := Vector3(26.0, 9.0, 26.0) ## m: half sizes of the air they live in
const LIFE := 14.0 ## s

var planet: PlanetWorld

var _material := ParticleProcessMaterial.new()
var _speck := StandardMaterial3D.new()


func _ready() -> void:
	amount = 700
	lifetime = LIFE
	preprocess = LIFE
	local_coords = false
	explosiveness = 0.0
	visibility_aabb = AABB(-BOX * 1.2, BOX * 2.4)
	_material.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	_material.emission_box_extents = BOX
	_material.gravity = Vector3(0.0, -0.01, 0.0)
	_material.initial_velocity_min = 0.0
	_material.initial_velocity_max = 0.05
	_material.direction = Vector3(1.0, 0.2, 0.3)
	_material.spread = 180.0
	_material.turbulence_enabled = true
	_material.turbulence_noise_strength = 0.35
	_material.turbulence_noise_scale = 6.0
	_material.turbulence_influence_min = 0.05
	_material.turbulence_influence_max = 0.12
	_material.scale_min = 0.5
	_material.scale_max = 1.6
	var fade := Gradient.new() # appear and vanish softly
	fade.set_color(0, Color(1.0, 1.0, 1.0, 0.0))
	fade.set_color(1, Color(1.0, 1.0, 1.0, 0.0))
	fade.add_point(0.15, Color(1.0, 1.0, 1.0, 1.0))
	fade.add_point(0.85, Color(1.0, 1.0, 1.0, 1.0))
	var ramp := GradientTexture1D.new()
	ramp.gradient = fade
	_material.color_ramp = ramp
	process_material = _material
	var quad := QuadMesh.new()
	quad.size = Vector2(0.025, 0.025)
	_speck.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_speck.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	_speck.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_speck.vertex_color_use_as_albedo = true
	_speck.albedo_color = Color(1.0, 0.95, 0.8, 0.55)
	_speck.distance_fade_mode = BaseMaterial3D.DISTANCE_FADE_PIXEL_ALPHA
	_speck.distance_fade_min_distance = 18.0
	_speck.distance_fade_max_distance = 2.0
	quad.material = _speck
	draw_pass_1 = quad
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	emitting = false


func _process(_delta: float) -> void:
	if planet == null or planet.target() == null:
		return
	var camera := get_viewport().get_camera_3d()
	if camera != null:
		global_position = camera.global_position
	var sun_up: float = clampf(planet.atmosphere.sun_direction.dot(
			(planet.atmosphere.global_position - planet.atmosphere.planet_centre).normalized()) * 6.0,
			0.0, 1.0)
	var calm := 1.0 - maxf(planet.atmosphere.overcast, planet.atmosphere.fog_extra * 60.0)
	var wanted := bool(GraphicsSettings.get_graphics_value(&"particles")) and sun_up > 0.05 \
			and calm > 0.3 and not planet.atmosphere.underwater and planet.altitude() < 2500.0
	emitting = wanted
	visible = wanted
	_speck.albedo_color.a = 0.55 * sun_up * calm
