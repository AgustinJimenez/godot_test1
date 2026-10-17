extends Node3D
## Planet lab. Plain run: the player walks a round planet.
##   -- --radius=N     planet radius in metres (default 20000)
##   -- --seed=N       planet seed
##   -- --dir=x,y,z   start there (a direction from the planet's centre) instead of the spawn
##   -- --view-alt=N   no player: a camera N metres above the ground, looking at the horizon
##   -- --view-pitch=N / --view-yaw=N degrees (negative pitch looks down; with --view-alt)
##   -- --shot=PATH    (with a window) saves a picture after the tiles have loaded, then quits
##   -- --show-map [--map-zoom=N] [--map-layer=N]   the planet map open from the start (M in play)
##   -- --time-scale=N --hour=H --year=Y   how fast time runs, the first hour (12 noon), the first
##                    share of the year (0 northern spring equinox)
##   -- --look-moon  the camera looks at the moon (with --view-alt)
##   -- --weather=rain  force a weather (clear, cloudy, rain, storm, fog, snow) from the start
##   -- --fps  print the frame rate every 300 frames
##   -- --planet-page  the Planet page of the Esc menu open from the start
##   -- --bare       no plants (to look at the ground)
##   -- --fly-check   the same in free mode at 100 m/s, 300 sprinting (the free speed slider)
##   -- --walk-check  (use --fixed-fps 60) the real player holds forward and sprint for 90 s,
##                    walking over the planet; prints one WALK_CHECK line
##   -- --planet-check (headless) stands the player on the planet, walks it in steps (turning the
##                     planet under them) and prints one PLANET_CHECK line.

const PLAYER_SCENE := preload("res://actors/player/player.tscn")

var planet: PlanetWorld
var player: Player
var _checking := false
var _walking := false
var _weather_name := "" ## a WorldWeather.State name to force from the start (rain, snow...)
var _report_fps := false ## print the frame rate now and then
var _planet_page := false ## open the Planet page of the Esc menu from the start
var _look_moon := false ## point the camera at the moon (with --view-alt)
var _show_map := false ## open the planet map (the M key) from the start
var _map_zoom := 6.0
var _map_layer := 0
var _swim_check := false ## drop the player in the sea and see them float (PlanetSwim)
var _flying := false ## the walk check in free mode (noclip) at 100 m/s
var _walk_start := Vector3.ZERO
var _walk_floor := 0
var _walk_worst := 0.0
var _stuck := false
var _side := 0
var _stuck_count := 0
var _last_here := Vector3.ZERO
var _frame := 0
var _step := 0
var _start_up := Vector3.ZERO
var _settle := 0
var _worst_height := 0.0
var _floor_misses := 0
var _walked := 0.0
var _placed := true
var _view_alt := 0.0
var _shot := ""
var _start_dir := Vector3.ZERO
var _shot_frame := 360
var _view_pitch := -18.0
var _view_yaw := 0.0


func _ready() -> void:
	var settings := PlanetSettings.new()
	if PlanetMenu.pending != null: # a new planet asked for in the Planet page of the menu
		settings = PlanetMenu.pending
		PlanetMenu.pending = null
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--radius="):
			settings.radius = arg.trim_prefix("--radius=").to_float()
		elif arg.begins_with("--seed="):
			settings.world_seed = arg.trim_prefix("--seed=").to_int()
		elif arg.begins_with("--view-alt="):
			_view_alt = arg.trim_prefix("--view-alt=").to_float()
		elif arg.begins_with("--dir="):
			var parts := arg.trim_prefix("--dir=").split(",")
			_start_dir = Vector3(parts[0].to_float(), parts[1].to_float(), parts[2].to_float()).normalized()
		elif arg.begins_with("--view-yaw="):
			_view_yaw = arg.trim_prefix("--view-yaw=").to_float()
		elif arg.begins_with("--view-pitch="):
			_view_pitch = arg.trim_prefix("--view-pitch=").to_float()
		elif arg.begins_with("--shot-frame="):
			_shot_frame = arg.trim_prefix("--shot-frame=").to_int()
		elif arg.begins_with("--shot="):
			_shot = arg.trim_prefix("--shot=")
		elif arg.begins_with("--time-scale="):
			settings.time_scale = arg.trim_prefix("--time-scale=").to_float()
		elif arg.begins_with("--hour="):
			settings.start_hour = arg.trim_prefix("--hour=").to_float()
		elif arg.begins_with("--year="):
			settings.start_year = arg.trim_prefix("--year=").to_float()
		elif arg.begins_with("--map-layer="):
			_map_layer = arg.trim_prefix("--map-layer=").to_int()
		elif arg.begins_with("--map-zoom="):
			_map_zoom = arg.trim_prefix("--map-zoom=").to_float()
		elif arg == "--show-map":
			_show_map = true
		elif arg == "--look-moon":
			_look_moon = true
		elif arg.begins_with("--weather="):
			_weather_name = arg.trim_prefix("--weather=").to_upper()
		elif arg == "--fps":
			_report_fps = true
		elif arg == "--planet-page":
			_planet_page = true
		elif arg == "--bare":
			settings.plant_density = 0.0
		elif arg == "--walk-check":
			_walking = true
		elif arg == "--swim-check":
			_swim_check = true
		elif arg == "--fly-check":
			_walking = true
			_flying = true
		elif arg == "--planet-check":
			_checking = true
	planet = PlanetWorld.new()
	planet.settings = settings
	add_child(planet)
	var started := Time.get_ticks_msec()
	if _view_alt > 0.0:
		var camera := Camera3D.new()
		camera.far = settings.radius * 4.0
		camera.near = 0.5
		add_child(camera)
		camera.make_current()
		var view_spawn := planet.start(camera, _start_dir)
		camera.global_position.y = _view_alt
		camera.rotation_degrees = Vector3(_view_pitch, _view_yaw, 0.0)
		planet.build_now(true)
		planet.update_now()
		if _look_moon:
			planet._set_the_sun()
			camera.look_at(camera.global_position + planet.atmosphere.moon_direction * 100.0)
		print("VIEW altitude %.0f m over %s" % [_view_alt, view_spawn])
		return
	player = PLAYER_SCENE.instantiate() as Player
	add_child(player)
	if _swim_check:
		_start_dir = _find_sea(planet.noise)
	var spawn := planet.start(player, _start_dir)
	planet.loaded.connect(func() -> void: print("LOADED after %d ms (%d tiles)" % [
			Time.get_ticks_msec() - started, planet.surface.tiles.size()]))
	planet.build_now(not _checking)
	print("PLANET radius %.0f m, max level %d, %d tiles in %d ms, spawn %s" % [settings.radius,
			settings.max_level(), planet.surface.tiles.size(), Time.get_ticks_msec() - started,
			spawn])
	_start_up = spawn
	if _checking:
		var found := false
		for button in player.hud.find_children("*", "Button", true, false):
			found = found or (button as Button).text == "Planet"
		print("MENU_PAGE %s" % ("found" if found else "MISSING"))
	var colliders := 0
	var nearest := INF
	for tile: PlanetTile in planet.surface.tiles.values():
		if tile.has_collider:
			colliders += 1
			nearest = minf(nearest, tile.global_position.length())
	print("colliders=%d nearest tile centre %.1f m at %s" % [colliders, nearest,
			planet.frame.origin_w])


func _physics_process(_delta: float) -> void:
	_frame += 1
	if _swim_check and _frame == 300:
		var level := planet.water_at_world(player.global_position)
		var afloat := planet.swim != null and planet.swim.swimming
		print("SWIM_CHECK %s swimming=%s water_y=%.2f player_y=%.2f" % ["PASS" if afloat and absf(
				player.global_position.y - level) < 2.5 else "FAIL", afloat, level,
				player.global_position.y])
		get_tree().quit()
	if _walking and player != null:
		_walk_step()
		return
	if _weather_name != "" and _frame == 30:
		var state: int = WorldWeather.State.keys().find(_weather_name)
		if state >= 0:
			planet.weather_override = state
			planet.weather.snap(state as WorldWeather.State)
	if _report_fps and _frame % 60 == 0: # no cap, to see what the frames cost
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
		Engine.max_fps = 0
	if _report_fps and _frame % 300 == 0:
		print("FPS frame=%d fps=%d alt=%d" % [_frame, Engine.get_frames_per_second(), planet.altitude()])
	if _planet_page and _frame == 30:
		player.hud.debug_overlay.show()
		for button in player.hud.find_children("*", "Button", true, false):
			if (button as Button).text == "Planet":
				(button as Button).pressed.emit()
	if _show_map and _frame == 30:
		planet.map.show_zoom(_map_zoom)
		planet.map.select_layer(_map_layer)
	if _shot != "" and _frame == _shot_frame:
		var animals := 0
		for animal in planet.fauna.get_children():
			if (animal as Node3D).visible:
				animals += 1
		print("ANIMALS visible: %d" % animals)
		get_viewport().get_texture().get_image().save_png(_shot)
		get_tree().quit()
	if not _checking or player == null:
		return
	# let the player land, then walk 60 m at a time along the world's +X, building as we go
	if _frame < 60:
		return
	_settle += 1
	if not _placed and _settle == 10: # the new colliders are in: stand on the ground there
		if "--verbose-check" in OS.get_cmdline_user_args():
			var near := INF
			var count := 0
			for tile: PlanetTile in planet.surface.tiles.values():
				if tile.has_collider:
					count += 1
					near = minf(near, (tile.global_position - player.global_position).length())
			print("  placing: colliders=%d nearest=%.1f m ray_y=%.2f player=%s" % [count, near,
					_ground_y(), player.global_position])
		player.global_position.y = _ground_y() + 1.0
		player.velocity = Vector3.ZERO
		_placed = true
	if _settle < 30:
		return
	# how far the player is above the planet's ground by the noise itself (not by physics): near 0
	# when the frame, the tiles and the colliders all agree
	var at := planet.planet_position().normalized()
	var above := planet.altitude() - planet.noise.height(at.x, at.y, at.z)
	_worst_height = maxf(_worst_height, absf(above))
	if not player.is_on_floor():
		_floor_misses += 1
	if "--verbose-check" in OS.get_cmdline_user_args():
		print("step %d y=%.2f vy=%.2f floor=%s alt=%.1f" % [_step, player.global_position.y,
				player.velocity.y, player.is_on_floor(), planet.altitude()])
	if _step >= 40:
		var up_error := rad_to_deg(player.global_basis.y.angle_to(Vector3.UP))
		var altitude := planet.altitude()
		var verdict := "PASS" if _worst_height < 3.0 else "FAIL"
		print("PLANET_CHECK %s steps=%d walked=%.0f m rebases=%d tiles=%d off_floor=%d" % [
				verdict, _step, _walked, planet.rebases, planet.surface.tiles.size(), _floor_misses])
		print("  worst_gap=%.2f m world_pos=%.0f up_error=%.2f deg altitude=%.1f m" % [
				_worst_height, player.global_position.length(), up_error, altitude])
		get_tree().quit()
		return
	_settle = 0
	_step += 1
	var step := Vector3(59.3, 0.0, 0.41) # not on a tile seam (a ray can slip through)
	player.global_position += step
	_walked += step.length()
	player.global_position.y += 60.0
	planet.update_now()
	planet.build_now()
	_placed = false


## The world height of the ground under the player, by asking physics (trunks are skipped).
func _ground_y() -> float:
	var query := PhysicsRayQueryParameters3D.create(player.global_position + Vector3.UP * 100.0,
			player.global_position + Vector3.DOWN * 200.0, 1)
	var skipped: Array[RID] = []
	for attempt in 12:
		query.exclude = skipped
		var hit := get_world_3d().direct_space_state.intersect_ray(query)
		if hit.is_empty():
			return player.global_position.y
		var body := hit["collider"] as Node
		if body.name != "Plants":
			return (hit["position"] as Vector3).y
		skipped.append(hit["rid"] as RID)
	return player.global_position.y


## Holds the player's forward and sprint keys and watches how the walk goes (real physics, the
## real player: the planet turns under it every 80 m).
func _walk_step() -> void:
	if _frame == 60:
		Input.action_press(&"move_forward")
		Input.action_press(&"sprint")
		if _flying:
			player.set_free_mode(true)
			player.free_mode_speed = 100.0
		_walk_start = planet.planet_position()
	if _frame <= 60:
		return
	if player.is_on_floor():
		_walk_floor += 1
	if "--verbose-check" in OS.get_cmdline_user_args() and _frame % 60 == 0:
		var touching := ""
		for index in player.get_slide_collision_count():
			var hit := player.get_slide_collision(index)
			touching += " %s n=%s" % [(hit.get_collider() as Node).name, hit.get_normal().snapped(
					Vector3.ONE * 0.01)]
		print("walk %d: pos %s floor %s%s" % [_frame, player.global_position.snapped(
				Vector3.ONE * 0.01), player.is_on_floor(), touching])
	# a tree or a rock in the way: sidestep it (left, then right, jumping), like a person would
	if _frame % 120 == 0:
		var here := planet.planet_position()
		_stuck = here.distance_to(_last_here) < 1.5
		_last_here = here
		for action in [&"move_right", &"move_left", &"jump"]:
			Input.action_release(action)
		if _stuck:
			_stuck_count += 1
			if _stuck_count % 3 == 0: # wedged between trunks: lift the player out of it
				player.global_position += Vector3(3.0, 1.0, 3.0)
			_side = 1 - _side
			Input.action_press(&"move_right" if _side == 0 else &"move_left")
			Input.action_press(&"jump")
	var at := planet.planet_position().normalized()
	var above := planet.altitude() - planet.noise.height(at.x, at.y, at.z)
	_walk_worst = maxf(_walk_worst, absf(above))
	if _frame >= 60 + 90 * 60:
		var travelled := planet.planet_position().distance_to(_walk_start)
		var verdict := "PASS" if travelled > 150.0 and _walk_worst < 4.0 else "FAIL"
		if _flying:
			verdict = "PASS" if travelled > 10000.0 else "FAIL"
		print("WALK_CHECK %s travelled=%.0f m rebases=%d on_floor=%.0f%% worst_above_ground=%.2f m "
				% [verdict, travelled, planet.rebases, 100.0 * float(_walk_floor) / float(_frame - 60),
				_walk_worst] + "world_pos=%.0f" % player.global_position.length())
		get_tree().quit()


## A direction over open sea a few metres deep, near the planet's spawn.
func _find_sea(noise: PlanetNoise) -> Vector3:
	var spawn := noise.find_spawn()
	for index in 4000:
		var angle := float(index) * 2.399963
		var reach := 0.002 + 0.0000025 * float(index)
		var around := spawn.cross(Vector3.UP).normalized() * cos(angle) + spawn.cross(
				spawn.cross(Vector3.UP)).normalized() * sin(angle)
		var dir := (spawn + around * reach * 40.0).normalized()
		var height := noise.height(dir.x, dir.y, dir.z)
		if height < -4.0 and height > -14.0:
			return dir
	return spawn
