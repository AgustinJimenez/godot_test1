class_name PlanetCloudShell
extends MeshInstance3D
## The clouds seen from high up: a shell a little above the ground that shows the planet's cloud
## cover (PlanetWeather) as the sun lights it. The cover picture is made on a background thread
## every few seconds (and when time jumps) from the weather model, so it drifts and changes as time
## runs. Near the ground the shell is gone (the sky has its own clouds, WorldClouds).

const SIZE := Vector2i(256, 128)
const REFRESH := 2.5 ## seconds between pictures
const SHOW_FROM := 1500.0 ## m of altitude at which the shell begins to appear
const FULL_AT := 6000.0

var planet: PlanetWorld

var _material := ShaderMaterial.new()
var _chart: PlanetChart
var _wait := 0.0
var _drawn_time := -1.0e12


func _ready() -> void:
	_material.shader = preload("res://shaders/world/planet_clouds.gdshader")
	var sphere := SphereMesh.new()
	sphere.radius = 1.0
	sphere.height = 2.0
	sphere.radial_segments = 96
	sphere.rings = 48
	mesh = sphere
	material_override = _material
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	extra_cull_margin = 1.0e7
	visible = false


func _process(delta: float) -> void:
	if planet == null or planet.target() == null:
		return
	var altitude := planet.altitude()
	var fade := clampf((altitude - SHOW_FROM) / (FULL_AT - SHOW_FROM), 0.0, 1.0)
	visible = fade > 0.0
	if visible:
		_place_the_shell(fade)
	_refresh_the_cover(delta)


func _place_the_shell(fade: float) -> void:
	# the shell, as big as the planet plus a little, centred on the planet's centre
	var radius := planet.settings.radius + clampf(planet.noise.relief * 0.8, 150.0, 12000.0)
	var centre := planet.frame.to_world(Vector3.ZERO)
	global_transform = Transform3D(planet.frame.rot.scaled(Vector3.ONE * radius), centre)
	_material.set_shader_parameter(&"sun_toward", planet.atmosphere.sun_direction)
	_material.set_shader_parameter(&"fade", fade)


## The picture of the cloud cover: made again every few seconds on a background thread, for the
## shell and for the volumetric clouds of the sky.
func _refresh_the_cover(delta: float) -> void:
	_wait -= delta
	if _chart != null:
		if _chart.finished():
			var picture := _chart.texture()
			_material.set_shader_parameter(&"cover_map", picture)
			planet.atmosphere.sky_material.set_shader_parameter(&"cover_map", picture)
			_chart = null
	elif _wait <= 0.0 and absf(planet.clock.time - _drawn_time) > 1.0e-3:
		_wait = REFRESH if visible else REFRESH * 2.0
		_chart = PlanetChart.new()
		_chart.layer = PlanetChart.Layer.CLOUD_MASK
		_chart.size = SIZE
		_chart.clock = planet.clock.copy()
		_drawn_time = planet.clock.time
		_chart.start(planet.noise)


func _exit_tree() -> void:
	if _chart != null:
		_chart.stop()
