class_name PlanetWorld
extends Node3D
## A whole planet in one node: terrain tiles, sun and sky. Give it a `target` (the player) with
## `start` and it keeps the ground built around them, turning the planet under their feet as they
## walk (PlanetFrame) so the game's flat-world assumptions (up is +Y, gravity down) keep holding.

const REBASE_DISTANCE := 80.0 ## m walked before the planet is turned level again
const RECENTER_DISTANCE := 2000.0 ## m from the world origin before everything is shifted back
const RAIN_UP_TO := 1500.0 ## m above the ground: higher up there is no rain
const LOAD_GROUND := 2000.0 ## m of ground and water built before the player is let in
const LOAD_PLANTS := 60.0 ## m round the player that must be planted before they are let in

## The ground and water round the player are ready (and the plants close by): the player may move.
signal loaded
## something occasional changed in the world (a fire, an impact): the map forgets that part. Its
## area in map fractions (x east, y south); `PlanetMap.world_changed_at` takes a place and a radius.
signal world_changed(area: Rect2)

@export var settings: PlanetSettings
@export var time_of_day := 10.0
@export var fog := 0.001 ## fog density: a planet has a far horizon (the flat world uses 0.0032)

var noise: PlanetNoise
var frame := PlanetFrame.new()
var surface: PlanetSurface
var atmosphere: PlanetAtmosphere
var fauna: PlanetFauna
var swim: PlanetSwim
var map: PlanetMap
var weather: WorldWeather ## the effects of the weather; the planet picks the state they follow
var cloud_shell: PlanetCloudShell
var weather_text := ""
var _weather_timer := 0.0
var restored := {} ## a save's moment (UniverseSave) to bring back when `start` runs
var weather_override := -1 ## a WorldWeather.State to force, or -1 to follow the planet's climate
var time_rate := 1.0 ## how fast time runs on top of `time_scale`: negative is backward, 0 stops it
var _star_disc := 1.0 ## the star's disc at the semi-major distance against the Sun from the Earth
var clock := PlanetClock.new() ## the star, the orbit, the spin: where the sun is (real geometry)
var splash: WaterSplash
var rebases := 0 ## how many times the planet has been turned (labs and tests)
## false: the character starts exactly where `start` is asked to put them, in the sea if that is where it is (the swim check)
var spawn_on_solid_ground := true
var loading := false ## the player is held still while the ground around them is made
var map_first := true ## the map opens first, the ground is built once it is closed (a window only)

var _target: Node3D
var _timer := 0.0
var _load_label: Label
var _dark: ColorRect
var _load_time := 0.0


func _ready() -> void:
	if settings == null:
		settings = PlanetSettings.new()
	# the plants are built in the finer, realistic look from the Fine ground detail (High and Ultra); the
	# light meshes cost a third of the triangles for Low and Medium
	FloraMeshes.detailed = int(GraphicsSettings.get_graphics_value(&"ground_detail")) >= 2
	noise = PlanetNoise.new(settings)
	clock.day_seconds = settings.day_seconds
	clock.year_days = settings.year_days
	clock.axial_tilt = deg_to_rad(settings.axial_tilt)
	clock.insolation = settings.insolation
	clock.eccentricity = settings.eccentricity
	clock.perihelion_share = settings.perihelion_share
	clock.month_days = settings.month_days
	atmosphere = PlanetAtmosphere.new()
	atmosphere.radius = settings.radius
	atmosphere.air_height = settings.air_height
	var star := Star.from_mass(settings.star_mass)
	atmosphere.star_tint = star.light_tint(settings.star_readability)
	_star_disc = star.radius * sqrt(settings.insolation / star.luminosity)
	atmosphere.time_of_day = time_of_day
	add_child(atmosphere)
	surface = PlanetSurface.new()
	surface.setup(noise, frame)
	add_child(surface)
	fauna = PlanetFauna.new()
	fauna.planet = self
	add_child(fauna)
	weather = WorldWeather.new()
	weather.atmosphere = atmosphere
	add_child(weather)
	cloud_shell = PlanetCloudShell.new()
	cloud_shell.planet = self
	add_child(cloud_shell)
	map = PlanetMap.new()
	map.planet = self
	add_child(map)
	var recorder := PlanetRecorder.new() # the last seconds of play, kept in a file (F9 marks)
	recorder.planet = self
	add_child(recorder)
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


## The node the world is built around (the player), or null.
func target() -> Node3D:
	return _target


## Stands `target` on the planet at the spawn spot (or `direction`, a unit vector from the centre).
## The target ends up at the world origin; returns the direction it stands in.
## Starts the planet around `target`. `direction`: the point of the planet (a unit vector) it starts
## over, or none to find a good place; `altitude`: how far above the ground there, in metres. The
## target does not have to be near the planet: for a position anywhere in space (a ship arriving)
## the point of the planet closest to it is `nearest_point(position)`, and its distance to the
## ground is the altitude: the tiles are chosen for that point and that height, so the ground
## under the target and the planet's coarse shape are what is made first, however far away.
func start(target: Node3D, direction := Vector3.ZERO, altitude := 0.0) -> Vector3:
	# the materials tiles share are made here, on the main thread: a worker thread making one
	# first could read it half made while another does (a null shader error on a river tile)
	PlanetTile.ground_material()
	PlanetTile.water_material()
	PlanetTile.river_material().set_shader_parameter(&"sea_radius",
			settings.radius + settings.sea_level)
	_target = target
	if target is Player:
		splash = WaterSplash.new()
		add_child(splash)
		swim = PlanetSwim.new()
		swim.planet = self
		swim.target = target as Player
		swim.splash = splash
		add_child(swim)
		var footprints := PlanetFootprints.new()
		footprints.planet = self
		footprints.target = target as Player
		add_child(footprints)
		var motes := PlanetMotes.new()
		motes.planet = self
		add_child(motes)
		if not OS.has_environment("PLANET_NO_UNDERGROWTH"):
			var undergrowth := PlanetUndergrowth.new() # the plants bend and hold the walker back
			undergrowth.planet = self
			undergrowth.player = target as Player
			add_child(undergrowth)
		if not OS.has_environment("PLANET_NO_SWAY"):
			var sway := PlanetSway.new() # the branches round the walker bend and spring back
			sway.planet = self
			sway.player = target as Player
			add_child(sway)
	if direction == Vector3.ZERO and restored.has("direction"):
		var saved: Array = restored["direction"]
		direction = Vector3(saved[0], saved[1], saved[2]).normalized()
	var dir := direction if direction != Vector3.ZERO else noise.find_spawn()
	if target is Player and altitude <= 0.0 and spawn_on_solid_ground:
		dir = noise.solid_spawn(dir) # the character starts on solid ground, never in the sea or a river
	var reach := settings.radius + noise.height(dir.x, dir.y, dir.z) + 1.0
	reach += maxf(altitude, 0.0)
	noise.clearing = dir
	if target is Player and (target as Player).hud != null:
		var page := PlanetMenu.new()
		page.setup(self)
		(target as Player).hud.call(&"add_menu_page", "Planet", page)
	noise.clock = clock
	clock.start(settings.start_year, settings.start_hour, dir)
	if restored.has("clock"):
		clock.restore(restored["clock"])
		time_rate = float(restored.get("time_rate", time_rate))
		weather_override = int(restored.get("weather_override", weather_override))
	_set_the_sun()
	frame.start(PackedFloat64Array([dir.x * reach, dir.y * reach, dir.z * reach]), Vector3.ZERO)
	target.global_position = Vector3.ZERO
	if altitude > 500.0 and target is Player: # up in the air there is nothing to stand on: fly
		(target as Player).set_free_mode(true)
	if restored.has("heading"):
		var saved: Array = restored["heading"]
		var along := frame.rot * Vector3(saved[0], saved[1], saved[2])
		if Vector2(along.x, along.z).length() > 0.01:
			target.rotation.y = atan2(-along.x, -along.z)
	restored = {}
	publish_frame()
	if not (target is Player and surface.is_threaded()):
		map.begin()
	# the ground and the water come first: the player stands still until the land round them is made
	# (the plants follow, starting with the ones nearest to them)
	if target is Player and surface.is_threaded():
		loading = true
		_load_time = 0.0
		target.process_mode = Node.PROCESS_MODE_DISABLED
		surface.update(planet_position())
		if map_first and DisplayServer.get_name() != "headless":
			# the world is defined before it is built: its map, every layer, comes first, and the
			# ground waits (map.paused) until the map is closed
			map.warm_up = true # (black, with its progress, until the whole map is charted)
			map.begin()
			map.show_zoom(PlanetMap.MAX_ZOOM)
			map.visibility_changed.connect(_cover_the_loading, CONNECT_ONE_SHOT)
			return dir
		_cover_the_loading()
		loaded.connect(map.begin, CONNECT_ONE_SHOT) # the map is drawn once the player is in
	return dir


## Black screen and the loading text while the ground round the player is made.
func _cover_the_loading() -> void:
	_load_label.visible = true
	_dark.modulate.a = 1.0
	_dark.visible = true


## The point of the planet closest to `position` (metres from the planet's centre, anywhere in
## space): the unit direction to start over, the way a ship that arrives far away is placed.
static func nearest_point(position: Vector3) -> Vector3:
	return position.normalized() if position.length() > 0.0 else Vector3.UP


## How far above the ground `position` is, for the direction found by `nearest_point`.
func altitude_of(position: Vector3) -> float:
	var dir := nearest_point(position)
	return position.length() - settings.radius - noise.height(dir.x, dir.y, dir.z)


## The clouds and the rain of the sky belong to the first kilometre and a half above the ground:
## the puffs ride at their height above the ground under the player (not at a height of the world,
## which would leave them hanging in space when the player flies up), and above that the rain and
## the puffs are gone (the cloud shell of the planet takes over, PlanetCloudShell).
func _keep_the_weather_near_the_ground() -> void:
	var here := planet_position().normalized()
	var ground := noise.height(here.x, here.y, here.z)
	var above := altitude() - ground
	var low := above < RAIN_UP_TO
	weather.clouds.visible = false # the planet's clouds are the sky's own (planet_sky.gdshader)
	weather.rain.visible = low
	atmosphere.cloud_floor = maxf(ground, 0.0) + 450.0
	atmosphere.cloud_on = 1.0 - smoothstep(450.0, 700.0, above) # then the shell has them
	weather.position.y = frame.to_world(here * (settings.radius + maxf(ground, 0.0))).y


## The weather at the player, from the planet's own clouds, temperature and moisture: sets the state
## the effects (clouds, rain, snow, fog, wind) ease toward.
func _pick_the_weather() -> void:
	var here := planet_position().normalized()
	var now := noise.weather.at(here, maxf(altitude(), 0.0), clock)
	var kind: int = now["kind"] if weather_override < 0 else weather_override
	var wanted: WorldWeather.State = kind as WorldWeather.State
	if weather.state != wanted:
		weather.set_state(wanted)
	weather_text = "%s  %d%% cloud  %d °C" % [WorldWeather.State.keys()[kind].capitalize(),
			int(float(now["cloud"]) * 100.0), roundi(float(now["degrees"]))]
	# the haze follows the climate here: thick and soft where it is warm and wet, clear where it is
	# cold and dry, dusty where it is hot and dry
	var local := noise.climate.sample(here)
	var humid := clampf(local.y / 0.9, 0.0, 1.0)
	var warm := smoothstep(0.0, 25.0, local.x)
	atmosphere.haze_wanted = 0.55 + 1.5 * humid * warm
	atmosphere.dust_wanted = (1.0 - humid) * smoothstep(14.0, 30.0, local.x)
	# morning mist: the night's cold leaves a fog in wet low ground until the sun burns it off
	var morning := clock.local_hour(here)
	var dawn := smoothstep(3.5, 5.5, morning) * (1.0 - smoothstep(7.0, 10.0, morning))
	var low_wet := humid * (1.0 - smoothstep(30.0, 250.0, maxf(altitude(), 0.0)))
	atmosphere.mist_wanted = dawn * low_wet * smoothstep(2.0, 12.0, local.x)
	# the wind blows along the parallel: east or west by the latitude, as the clouds are carried
	var lat := asin(clampf(here.y, -1.0, 1.0))
	var east := Vector3(-here.z, 0.0, here.x).normalized()
	var blowing := -PlanetWeather.zonal_wind(lat, noise.weather.wind_k())
	var wind := frame.rot * (east * blowing) # toward where it blows from
	weather.forced_wind = Vector2(-wind.x, -wind.z) if wind.length() > 0.01 else Vector2.ZERO


## What a save keeps of this moment: where the player stands (a unit direction from the centre) and
## which way they face (in the planet's frame, which turns under them), the clock, the speed of time
## and the weather forced, if any. UniverseSave writes it; `restored` takes it back.
func snapshot() -> Dictionary:
	var here := planet_position().normalized()
	var state := {
		"direction": [here.x, here.y, here.z],
		"clock": clock.snapshot(),
		"time_rate": time_rate,
		"weather_override": weather_override,
	}
	if _target != null:
		var forward := -_target.global_basis.z
		var along := frame.rot.inverse() * Vector3(forward.x, 0.0, forward.z).normalized()
		state["heading"] = [along.x, along.y, along.z]
	return state


## The small clouds of the sky ride the wind the planet's cloud cover is carried by (PlanetWeather).
func _drift_the_clouds(clock_seconds: float) -> void:
	var here := planet_position().normalized()
	var lat := asin(clampf(here.y, -1.0, 1.0))
	var east := Vector3(-here.z, 0.0, here.x).normalized()
	var turn := PlanetWeather.zonal_wind(lat, noise.weather.wind_k()) * PlanetWeather.WIND_TURN * TAU
	var speed := turn * settings.radius * cos(lat) / clock.day_seconds
	atmosphere.cloud_drift -= east * speed * clock_seconds


## 'Day 3, early spring' for the caption of the map.
func season_text() -> String:
	var share := clock.year_share()
	var names := ["early spring", "late spring", "early summer", "late summer", "early autumn",
			"late autumn", "early winter", "late winter"]
	# the northern seasons; the southern hemisphere has the other half of the year
	var here := planet_position().normalized()
	var shifted := share if here.y >= 0.0 else fposmod(share + 0.5, 1.0)
	var day := int(floorf(clock.time / clock.day_seconds)) + 1
	return "day %d, %s%s" % [day, names[int(shifted * 8.0) % 8],
			"" if here.y >= 0.0 else " (south)"]


## Moves time by `days` solar days (negative: backward), keeping the sun's hour as it is.
func jump_time(days: float) -> void:
	clock.advance(days * clock.day_seconds)


## Moves the sun to the local solar `hour` (0..24) at the player, leaving the day of the year.
func set_hour(hour: float) -> void:
	if _target != null:
		clock.start(clock.year_share(), hour, planet_position().normalized())


## Moves the orbit to `share` of the year, leaving the hour of day where it is.
func set_year_share(share: float) -> void:
	if _target != null:
		clock.set_year(share, planet_position().normalized())


## Puts the sun where the planet's orbit and spin put it: the direction to the star in the planet's
## frame, turned into the world by the frame (the planet is turned under the player as they walk).
func _set_the_sun() -> void:
	if atmosphere != null:
		atmosphere.planet_centre = frame.to_world(Vector3.ZERO)
		atmosphere.sun_direction = (frame.rot * clock.sun_in_body()).normalized()
		atmosphere.sun_size = _star_disc / clock.distance()
		atmosphere.moon_direction = (frame.rot * PlanetMoon.in_body(clock)).normalized()
		atmosphere.moon_lit = PlanetMoon.lit(clock)
		atmosphere.moon_shadow = PlanetMoon.lunar_depth(clock)
		if _target != null:
			atmosphere.sun_cover = PlanetMoon.solar_cover(clock, planet_position().normalized())


## Tells the ground shader where the planet is (it reads its detail noise at planet positions).
func publish_frame() -> void:
	var to_world := frame.planet_to_world()
	RenderingServer.global_shader_parameter_set(&"world_from_planet", to_world)
	RenderingServer.global_shader_parameter_set(&"planet_from_world", to_world.affine_inverse())
	RenderingServer.global_shader_parameter_set(&"anchor_from_world", frame.anchor_from_world())
	RenderingServer.global_shader_parameter_set(&"anchor_wrap", frame.anchor_wrap())
	RenderingServer.global_shader_parameter_set(&"anchor_up", frame.anchor_up())
	RenderingServer.global_shader_parameter_set(&"anchor_phase", frame.anchor_phase())


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
	if not wet:
		wet = noise.water_at(dir, h) > h - 0.3
	var up := frame.to_world(dir * (settings.radius + h))
	return {"y": up.y, "wet": wet, "biome": noise.biome(dir.x, dir.y, dir.z, h, 0.1)}


## The world height of the water at a world position (the sea, a lake or a river there), or -INF
## where the ground is dry. The player swims in it (PlanetSwim).
func water_at_world(position: Vector3) -> float:
	var here := frame.to_planet(position)
	var dir := Vector3(here[0], here[1], here[2]).normalized()
	var h := noise.height(dir.x, dir.y, dir.z)
	var level := -INF
	if h < 0.0 and settings.sea_on:
		level = 0.0
	else:
		level = noise.water_at(dir, h)
	if level == -INF:
		return -INF
	return frame.to_world(dir * (settings.radius + level)).y


## The river current at a world position, as a world vector (zero out of a river).
func flow_at_world(position: Vector3) -> Vector3:
	var here := frame.to_planet(position)
	var dir := Vector3(here[0], here[1], here[2]).normalized()
	return frame.rot * noise.flow_at(dir)


## While the player is held: keeps the tiles coming and lets the player in when the ground within
## `LOAD_GROUND` and the plants within `LOAD_PLANTS` are there.
func _wait_for_the_ground(delta: float) -> void:
	if map_first and map != null and map.visible:
		return # the map is open first: nothing is built and the 90 s of waiting do not run yet
	_load_time += delta
	_timer -= delta
	if _timer <= 0.0:
		_timer = 0.3
		surface.update(planet_position())
	surface.burst = true
	var done := surface.progress(LOAD_GROUND, LOAD_PLANTS)
	_load_label.text = "Generating the planet...  %d %%" % int(done * 100.0)
	if done >= 0.999 or _load_time > 90.0:
		if OS.has_environment("PLANET_TIMING"):
			print("PLANET_TIMING ground ready after %.1f s, %d tiles built, %d wanted" % [
					_load_time, surface.tiles.size(), surface._wanted.size()])
		_stand_on_the_ground()
		loading = false
		PlanetCloudGpu.warm_up() # (a thread of its own: the map's cloud cover runs on the GPU once this is done)
		surface.burst = false
		_load_label.visible = false
		_target.process_mode = Node.PROCESS_MODE_INHERIT
		var fade := create_tween() # the dark lifts
		fade.tween_property(_dark, "modulate:a", 0.0, 0.8)
		fade.tween_callback(_dark.hide)
		loaded.emit()


## The character is only let in once the ground under them is there: a ray from above finds the collider at the spawn spot
## and puts the character on it (a character placed from the height formula alone could start inside a hill or fall through
## ground that is not built yet). Without a hit (headless, or a ship far above) they stay where they are.
func _stand_on_the_ground() -> void:
	if not (_target is Player) or altitude() > 500.0 or not spawn_on_solid_ground:
		return
	var space := get_viewport().world_3d.direct_space_state
	var from := _target.global_position + Vector3.UP * 60.0
	var query := PhysicsRayQueryParameters3D.create(from, from + Vector3.DOWN * 160.0, 1)
	var hit := space.intersect_ray(query)
	if hit.is_empty():
		return
	_target.global_position = (hit["position"] as Vector3) + Vector3.UP * 0.05
	if OS.has_environment("PLANET_TIMING"):
		print("PLANET_TIMING stood on the ground at %.1f m" % (hit["position"] as Vector3).y)


## Metres above sea level at the target (the ground under it, not its feet).
func altitude() -> float:
	return planet_position().length() - settings.radius


## Turns/shifts the planet if the target has walked far (also done every physics frame).
func update_now() -> void:
	_physics_process(0.0)
	surface.update(planet_position())


func _exit_tree() -> void:
	PlanetCloudGpu.stop()


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
	WorldWind.set_realism(1.0) # the planet is the realistic look (smooth normals, finer plants, the sea's depth)
	_weather_timer -= delta
	if _weather_timer <= 0.0 and not loading:
		_weather_timer = 1.5
		_pick_the_weather()
	_keep_the_weather_near_the_ground()
	weather.update(_target.global_position, delta)
	if not loading:
		clock.advance(delta * settings.time_scale * time_rate)
		_drift_the_clouds(delta * settings.time_scale * time_rate)
	_set_the_sun()
	if settings.animals_on:
		fauna.update(_target.global_position, 1.0 - atmosphere.night_amount(), delta)
	if swim != null:
		atmosphere.underwater = swim.underwater
	var camera := get_viewport().get_camera_3d()
	if camera != null:
		# far enough to see the whole cap of the planet in sight: its horizon is that far away
		var high := maxf(altitude(), 0.0)
		var horizon := sqrt(high * (2.0 * settings.radius + high))
		camera.far = maxf(minf(settings.radius * 1.2, 600000.0), horizon * 1.1 + 2000.0)
		# the near plane grows with the height: the depth range stays workable (a far plane a million
		# times the near one breaks the projection and the shadow culling) and nothing is that close
		# and never under a ten-millionth of the far plane: past about 2^24 (16.7 million) the projection
		# breaks and NOTHING is drawn (a grey screen: any place under ~70 m above the sea, with a far
		# plane of 600 km, a coast, a beach, the sea)
		camera.near = maxf(clampf(high * 0.0005, 0.01, 2000.0), camera.far / 1.0e7)
	atmosphere.global_position = _target.global_position
	atmosphere.altitude = altitude()
