class_name ProceduralWorld
extends Node3D
## The whole generated world in one node: terrain tiles, sea, sun and sky. Give it a `target` (the
## player) and it keeps itself built around it. Same seed, same world.

@export var settings: WorldSettings
@export var time_of_day := 10.0
@export var day_seconds := 0.0 ## 0: the clock stands still
@export_range(0.0, 1.0) var autumn := 0.0 ## 0 summer green .. 1 autumn colours
@export_range(0.0, 1.0) var realism := 0.0 ## 0 low-poly look .. 1 realistic look

var generator: WorldGenerator
var water: WorldWater
var atmosphere: WorldAtmosphere
var weather: WorldWeather
var life: WorldLife
var ambience: WorldAmbience
var swim: WorldSwim
var fauna: WorldFauna
var splash: WaterSplash
var footprints: WorldFootprints
var _target: Node3D
var _detail_on := false
var _remesh: Array = [] # flora nodes waiting for the other mesh set


func _ready() -> void:
	if settings == null:
		settings = WorldSettings.new()
	_detail_on = realism > 0.5 # a world that starts realistic builds its plants finely at once
	FloraMeshes.detailed = _detail_on
	atmosphere = WorldAtmosphere.new()
	atmosphere.time_of_day = time_of_day
	atmosphere.day_seconds = day_seconds
	add_child(atmosphere)
	generator = WorldGenerator.new()
	generator.settings = settings
	add_child(generator)
	weather = WorldWeather.new()
	weather.atmosphere = atmosphere
	weather.noise = generator.noise if generator.noise != null else TerrainNoise.new(settings)
	add_child(weather)
	life = WorldLife.new()
	life.noise = generator.noise
	add_child(life)
	ambience = WorldAmbience.new()
	add_child(ambience)
	fauna = WorldFauna.new()
	fauna.noise = generator.noise
	fauna.settings = settings
	add_child(fauna)
	splash = WaterSplash.new()
	add_child(splash)
	footprints = WorldFootprints.new()
	footprints.noise = generator.noise
	footprints.settings = settings
	add_child(footprints)
	swim = WorldSwim.new()
	swim.splash = splash
	swim.ambience = ambience
	swim.level = settings.sea_level
	swim.noise = generator.noise
	add_child(swim)
	water = WorldWater.new()
	water.level = settings.sea_level
	water.noise = generator.noise
	add_child(water)


func _process(delta: float) -> void:
	WorldWind.set_autumn(autumn)
	WorldWind.set_realism(realism)
	atmosphere.realism = realism
	_update_detail()
	weather.clouds.visible = realism < 0.5 # the realistic sky paints its own clouds
	water.follow(_target.global_position if _target != null else Vector3.ZERO)
	atmosphere.global_position = _target.global_position if _target != null else Vector3.ZERO
	weather.update(_target.global_position if _target != null else Vector3.ZERO, delta)
	atmosphere.underwater = swim.underwater
	ambience.wind = weather.wind_strength()
	ambience.rain = weather.rain_amount() if not weather.rain.snowing else 0.0
	ambience.daylight = 1.0 - atmosphere.night_amount()
	ambience.underwater = swim.underwater
	ambience.shore = _shore_amount()
	if weather.pop_thunder():
		ambience.thunder(randf_range(0.3, 1.6))
	if _target is Player:
		footprints.update(_target as Player, weather.snow, weather.wetness, delta)
	fauna.update(_target.global_position if _target != null else Vector3.ZERO,
			1.0 - atmosphere.night_amount(), delta)
	for fire: Node in get_tree().get_nodes_in_group(&"campfire"):
		(fire as Campfire).daylight = 1.0 - atmosphere.night_amount()
		(fire as Campfire).rain = weather.rain_amount()
	life.update(_target.global_position if _target != null else Vector3.ZERO,
			1.0 - atmosphere.night_amount(), weather.rain_amount(), delta)


func set_target(target: Node3D) -> void:
	_target = target
	swim.target = target as Player
	generator.set_target(target)


## Builds the land around `center` now (labs and tests).
func build_around(center: Vector3) -> void:
	generator.build_around(center)


func ground_height(x: float, z: float) -> float:
	return generator.ground_height(x, z)


## Throws the land away and builds it again (after the settings, e.g. the seed, changed).
func rebuild() -> void:
	generator.clear()
	generator.noise = TerrainNoise.new(settings)
	weather.noise = generator.noise
	swim.noise = generator.noise
	water.noise = generator.noise
	life.noise = generator.noise
	fauna.noise = generator.noise
	footprints.noise = generator.noise


## 0 far from any water .. 1 at the water's edge (samples the ground around the target).
func _shore_amount() -> float:
	if _target == null:
		return 0.0
	var here := _target.global_position
	var lowest := INF
	for offset: Vector2 in [Vector2.ZERO, Vector2(24, 0), Vector2(-24, 0), Vector2(0, 24),
			Vector2(0, -24)]:
		lowest = minf(lowest, generator.ground_height(here.x + offset.x, here.z + offset.y))
	return clampf(1.0 - maxf(lowest - settings.sea_level, 0.0) / 10.0, 0.0, 1.0)


## Past half way to the realistic look the plants switch to their finer meshes (many per frame, so
## there is no hitch), and back again.
func _update_detail() -> void:
	var wanted := realism > 0.5
	if wanted != _detail_on:
		_detail_on = wanted
		FloraMeshes.detailed = wanted
		_remesh = get_tree().get_nodes_in_group(&"world_flora")
	var budget := 80
	while budget > 0 and not _remesh.is_empty():
		var node: Node = _remesh.pop_back()
		if is_instance_valid(node):
			var variant: int = node.get_meta(&"variant")
			var species_id: int = node.get_meta(&"species", 0)
			var multi := (node as MultiMeshInstance3D).multimesh
			if species_id > 0:
				multi.mesh = SpeciesRegistry.for_settings(settings).mesh(species_id, variant, _detail_on)
			else:
				multi.mesh = FloraMeshes.mesh(node.get_meta(&"kind"), variant, _detail_on)
		budget -= 1
