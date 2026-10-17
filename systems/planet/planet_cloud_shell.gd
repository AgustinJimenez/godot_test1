class_name PlanetCloudShell
extends MeshInstance3D
## The clouds seen from in and above their layer, from a little over the ground to orbit: a sphere
## round the planet whose pixels march the layer (planet_clouds.gdshader; the sky draws the same
## clouds from under it). Where there is cloud comes from the planet's cloud cover (PlanetWeather):
## a picture made on a background thread every few seconds (and when time jumps) from the weather
## model, so it drifts and changes as time runs.

const SIZE := Vector2i(256, 128)
const REFRESH := 2.5 ## seconds between pictures

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
	var fade := 1.0 - planet.atmosphere.cloud_on # the sky has them from under the layer
	visible = fade > 0.0
	if visible:
		_place_the_shell(fade)
	_refresh_the_cover(delta)


func _place_the_shell(fade: float) -> void:
	# a sphere a little bigger than the layer (the mesh is a polygon), centred on the planet
	var top := planet.settings.radius + planet.atmosphere.cloud_floor + PlanetAtmosphere.CLOUD_DEPTH
	var centre := planet.frame.to_world(Vector3.ZERO)
	global_transform = Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * top * 1.01), centre)
	planet.atmosphere.set_cloud_parameters(_material)
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
