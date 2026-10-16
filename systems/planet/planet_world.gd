class_name PlanetWorld
extends Node3D
## A whole planet in one node: terrain tiles, sun and sky. Give it a `target` (the player) with
## `start` and it keeps the ground built around them, turning the planet under their feet as they
## walk (PlanetFrame) so the game's flat-world assumptions (up is +Y, gravity down) keep holding.

const REBASE_DISTANCE := 80.0 ## m walked before the planet is turned level again
const RECENTER_DISTANCE := 2000.0 ## m from the world origin before everything is shifted back

@export var settings: PlanetSettings
@export var time_of_day := 10.0
@export var fog := 0.001 ## fog density: a planet has a far horizon (the flat world uses 0.0032)

var noise: PlanetNoise
var frame := PlanetFrame.new()
var surface: PlanetSurface
var atmosphere: WorldAtmosphere
var fauna: PlanetFauna
var rebases := 0 ## how many times the planet has been turned (labs and tests)

var _target: Node3D
var _timer := 0.0


func _ready() -> void:
	if settings == null:
		settings = PlanetSettings.new()
	noise = PlanetNoise.new(settings)
	atmosphere = WorldAtmosphere.new()
	atmosphere.time_of_day = time_of_day
	add_child(atmosphere)
	surface = PlanetSurface.new()
	surface.setup(noise, frame)
	add_child(surface)
	fauna = PlanetFauna.new()
	fauna.planet = self
	add_child(fauna)


## Stands `target` on the planet at the spawn spot (or `direction`, a unit vector from the centre).
## The target ends up at the world origin; returns the direction it stands in.
func start(target: Node3D, direction := Vector3.ZERO) -> Vector3:
	_target = target
	var dir := direction if direction != Vector3.ZERO else noise.find_spawn()
	var reach := settings.radius + noise.height(dir.x, dir.y, dir.z) + 1.0
	noise.clearing = dir
	frame.start(PackedFloat64Array([dir.x * reach, dir.y * reach, dir.z * reach]), Vector3.ZERO)
	target.global_position = Vector3.ZERO
	return dir


## Builds the ground around the target now, no waiting for the worker. `near_only`: only the ground
## the target can stand on (the rest follows in a few seconds).
func build_now(near_only := false) -> void:
	surface.build_all(planet_position(), near_only)


## The target's place on the planet (metres from its centre).
func planet_position() -> Vector3:
	var at := frame.to_planet(_target.global_position)
	return Vector3(at[0], at[1], at[2])


## The ground under the world position (x, z), found near the world height `near_y`: its world
## height, the biome there and whether it is under water (sea, river or lake).
func ground_at(x: float, z: float, near_y: float) -> Dictionary:
	var here := frame.to_planet(Vector3(x, near_y, z))
	var dir := Vector3(here[0], here[1], here[2]).normalized()
	var h := noise.height(dir.x, dir.y, dir.z)
	var wet := h < 0.6
	if not wet and noise.hydrology != null:
		wet = noise.hydrology.water_at(dir, h) > h - 0.3
	var up := frame.to_world(dir * (settings.radius + h))
	return {"y": up.y, "wet": wet, "biome": noise.biome(dir.x, dir.y, dir.z, h, 0.1)}


## Metres above sea level at the target (the ground under it, not its feet).
func altitude() -> float:
	return planet_position().length() - settings.radius


## Turns/shifts the planet if the target has walked far (also done every physics frame).
func update_now() -> void:
	_physics_process(0.0)
	surface.update(planet_position())


func _physics_process(delta: float) -> void:
	if _target == null:
		return
	var here := _target.global_position
	var moved := false
	if (here - frame.origin_w).length() > REBASE_DISTANCE:
		frame.rebase(here)
		rebases += 1
		moved = true
	if here.length() > RECENTER_DISTANCE:
		var back := -here
		frame.shift(back)
		_target.global_position += back
		moved = true
	if moved:
		surface.place_all()
	_timer -= delta
	if _timer <= 0.0 or moved:
		_timer = 0.3
		surface.update(planet_position())
	WorldWind.set_realism(0.0)
	fauna.update(_target.global_position, 1.0 - atmosphere.night_amount(), delta)
	# the air thins with height: no fog in space
	var thin := fog * exp(-maxf(altitude(), 0.0) / 1200.0)
	atmosphere.fog_extra = thin - WorldAtmosphere.BASE_FOG
	var camera := get_viewport().get_camera_3d()
	if camera != null and camera.far < settings.radius:
		camera.far = settings.radius * 1.2
	atmosphere.global_position = _target.global_position
