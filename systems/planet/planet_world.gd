class_name PlanetWorld
extends Node3D
## A whole planet in one node: terrain tiles, sun and sky. Give it a `target` (the player) with
## `start` and it keeps the ground built around them, turning the planet under their feet as they
## walk (PlanetFrame) so the game's flat-world assumptions (up is +Y, gravity down) keep holding.

const REBASE_DISTANCE := 80.0 ## m walked before the planet is turned level again
const RECENTER_DISTANCE := 2000.0 ## m from the world origin before everything is shifted back
const LOAD_GROUND := 2000.0 ## m of ground and water built before the player is let in
const LOAD_PLANTS := 60.0 ## m round the player that must be planted before they are let in

## The ground and water round the player are ready (and the plants close by): the player may move.
signal loaded

@export var settings: PlanetSettings
@export var time_of_day := 10.0
@export var fog := 0.001 ## fog density: a planet has a far horizon (the flat world uses 0.0032)

var noise: PlanetNoise
var frame := PlanetFrame.new()
var surface: PlanetSurface
var atmosphere: WorldAtmosphere
var fauna: PlanetFauna
var swim: PlanetSwim
var splash: WaterSplash
var rebases := 0 ## how many times the planet has been turned (labs and tests)
var loading := false ## the player is held still while the ground around them is made

var _target: Node3D
var _timer := 0.0
var _load_label: Label
var _dark: ColorRect
var _load_time := 0.0


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
	var layer := CanvasLayer.new()
	layer.layer = 80
	add_child(layer)
	_dark = ColorRect.new() # the screen stays black while the planet is made
	_dark.color = Color.BLACK
	_dark.set_anchors_preset(Control.PRESET_FULL_RECT)
	_dark.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_dark.visible = false
	layer.add_child(_dark)
	_load_label = Label.new()
	_load_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_load_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_load_label.visible = false
	layer.add_child(_load_label)


## Stands `target` on the planet at the spawn spot (or `direction`, a unit vector from the centre).
## The target ends up at the world origin; returns the direction it stands in.
func start(target: Node3D, direction := Vector3.ZERO) -> Vector3:
	_target = target
	if target is Player:
		splash = WaterSplash.new()
		add_child(splash)
		swim = PlanetSwim.new()
		swim.planet = self
		swim.target = target as Player
		swim.splash = splash
		add_child(swim)
	var dir := direction if direction != Vector3.ZERO else noise.find_spawn()
	var reach := settings.radius + noise.height(dir.x, dir.y, dir.z) + 1.0
	noise.clearing = dir
	frame.start(PackedFloat64Array([dir.x * reach, dir.y * reach, dir.z * reach]), Vector3.ZERO)
	target.global_position = Vector3.ZERO
	publish_frame()
	# the ground and the water come first: the player stands still until the land round them is made
	# (the plants follow, starting with the ones nearest to them)
	if target is Player and surface.is_threaded():
		loading = true
		_load_time = 0.0
		target.process_mode = Node.PROCESS_MODE_DISABLED
		_load_label.visible = true
		_dark.modulate.a = 1.0
		_dark.visible = true
		surface.update(planet_position())
	return dir


## Tells the ground shader where the planet is (it reads its detail noise at planet positions).
func publish_frame() -> void:
	var to_world := frame.planet_to_world()
	RenderingServer.global_shader_parameter_set(&"world_from_planet", to_world)
	RenderingServer.global_shader_parameter_set(&"planet_from_world", to_world.affine_inverse())


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


## The world height of the water at a world position (the sea, a lake or a river there), or -INF
## where the ground is dry. The player swims in it (PlanetSwim).
func water_at_world(position: Vector3) -> float:
	var here := frame.to_planet(position)
	var dir := Vector3(here[0], here[1], here[2]).normalized()
	var h := noise.height(dir.x, dir.y, dir.z)
	var level := -INF
	if h < 0.0:
		level = 0.0
	elif noise.hydrology != null:
		level = noise.hydrology.water_at(dir, h)
	if level == -INF:
		return -INF
	return frame.to_world(dir * (settings.radius + level)).y


## The river current at a world position, as a world vector (zero out of a river).
func flow_at_world(position: Vector3) -> Vector3:
	if noise.hydrology == null:
		return Vector3.ZERO
	var here := frame.to_planet(position)
	var dir := Vector3(here[0], here[1], here[2]).normalized()
	return frame.rot * noise.hydrology.flow_at(dir)


## While the player is held: keeps the tiles coming and lets the player in when the ground within
## `LOAD_GROUND` and the plants within `LOAD_PLANTS` are there.
func _wait_for_the_ground(delta: float) -> void:
	_load_time += delta
	_timer -= delta
	if _timer <= 0.0:
		_timer = 0.3
		surface.update(planet_position())
	var done := surface.progress(LOAD_GROUND, LOAD_PLANTS)
	_load_label.text = "Generating the planet...  %d %%" % int(done * 100.0)
	if done >= 0.999 or _load_time > 90.0:
		loading = false
		_load_label.visible = false
		_target.process_mode = Node.PROCESS_MODE_INHERIT
		var fade := create_tween() # the dark lifts
		fade.tween_property(_dark, "modulate:a", 0.0, 0.8)
		fade.tween_callback(_dark.hide)
		loaded.emit()


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
	if loading:
		_wait_for_the_ground(delta)
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
		publish_frame()
	_timer -= delta
	if _timer <= 0.0 or moved:
		_timer = 0.3
		surface.update(planet_position())
	WorldWind.set_realism(0.0)
	fauna.update(_target.global_position, 1.0 - atmosphere.night_amount(), delta)
	if swim != null:
		atmosphere.underwater = swim.underwater
	# the air thins with height: no fog in space
	var thin := fog * exp(-maxf(altitude(), 0.0) / 1200.0)
	atmosphere.fog_extra = thin - WorldAtmosphere.BASE_FOG
	var camera := get_viewport().get_camera_3d()
	if camera != null and camera.far < settings.radius:
		camera.far = settings.radius * 1.2
	atmosphere.global_position = _target.global_position
