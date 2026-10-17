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
##   -- --climb=N  (with the player) lift them N metres at frame 600, looking down
##   -- --no-shadow  the sun casts no shadows
##   -- --hide=trees|plants|ground|water  not drawn (what each costs)
##   -- --fps  print the frame rate every 300 frames
##   -- --start-menu  the start menu first (saved planets, a new one); no arguments does it too
##   -- --world=NAME / --continue  open a saved universe (Planet page of the Esc menu saves them)
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
var _climb := 0.0 ## lift the player this many metres once the planet has loaded (they hang there)
var _hide := "" ## trees, plants, ground or water: not drawn (to see what each costs)
var _no_shadow := false ## the sun casts no shadows (to see what they cost)
var _report_fps := false ## print the frame rate now and then
var restored_state := {} ## the moment of a save to go back to (--world=, --continue, the menu)
var _save_as := "" ## save the planet under this name right after it starts
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
var _worst_frame := 0.0 ## the longest frame (s) since the last report
var _slow_frames := 0 ## frames over 33 ms since the last report
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


## Hides one kind of thing (`--hide=`), the new tiles too: trees, plants, ground or water.
func _hide_kind() -> void:
	for node in planet.find_children("*", "GeometryInstance3D", true, false):
		var tris := 0
		if node is MultiMeshInstance3D and node.multimesh != null and node.multimesh.mesh != null:
			tris = _mesh_triangles(node.multimesh.mesh)
		var kind := "ground"
		if node is MultiMeshInstance3D:
			kind = "trees" if tris >= 1500 else "plants"
			var begin: float = node.visibility_range_begin
			var finish: float = node.visibility_range_end
			if tris >= 1500 and is_equal_approx(finish, 100.0):
				kind = "full"
			elif tris >= 1500 and is_equal_approx(begin, 95.0):
				kind = "light"
			elif is_equal_approx(begin, 209.0):
				kind = "far"
			elif is_equal_approx(finish, 110.0):
				kind = "grass"
			elif tris < 1500 and begin == 0.0 and finish == 0.0:
				kind = "horizon"
		elif "ater" in str(node.name) or "ater" in str(node.get_parent().name):
			kind = "water"
		if kind == _hide or (_hide == "trees" and kind in ["full", "light", "midtrees"]):
			node.visible = false


## The triangles the scene holds, by kind of node (a mesh's, times its instances for a multimesh):
## where a frame's geometry comes from.
func _print_triangle_groups() -> void:
	var groups := {}
	for node in planet.find_children("*", "VisualInstance3D", true, false):
		var tris := 0
		var key := node.get_class()
		if node is MultiMeshInstance3D and node.multimesh != null and node.multimesh.mesh != null:
			var each := _mesh_triangles(node.multimesh.mesh)
			var count: int = node.multimesh.visible_instance_count
			tris = each * (node.multimesh.instance_count if count < 0 else count)
			var kind := "plants" if each < 1500 else "trees (%dk+ tris each)" % (each / 1000)
			key = "multimesh of %s" % kind
		elif node is MeshInstance3D and node.mesh != null:
			tris = _mesh_triangles(node.mesh)
			var parent_name := node.get_parent().name.rstrip("0123456789").trim_prefix("@")
			key = "mesh %s" % parent_name.get_slice("@", 0)
		var camera := get_viewport().get_camera_3d()
		var drawn: bool = node.is_visible_in_tree() and tris > 0
		if drawn and camera != null and node is GeometryInstance3D:
			var distance := camera.global_position.distance_to(node.global_position)
			var range_end: float = node.visibility_range_end
			var in_range := range_end <= 0.0 or distance < range_end
			in_range = in_range and distance >= node.visibility_range_begin
			var in_view := camera.is_position_in_frustum(node.global_position + Vector3.UP * 5.0)
			drawn = in_range and in_view
			var limited: bool = range_end > 0.0 or node.visibility_range_begin > 0.0
			key += " (range-limited)" if limited else " (always)"
		if drawn:
			var entry: Array = groups.get(key, [0, 0])
			entry[0] += tris
			entry[1] += 1
			groups[key] = entry
	var by_level := {}
	for tile: PlanetTile in planet.surface.tiles.values():
		var label := "level %d plants %d" % [tile.level, tile.plant_detail]
		by_level[label] = int(by_level.get(label, 0)) + 1
	print("TILES %s" % [by_level])
	var keys := groups.keys()
	keys.sort_custom(func(a: String, b: String) -> bool: return groups[a][0] > groups[b][0])
	for key: String in keys.slice(0, 14):
		print("TRIS %10d in %5d nodes  %s" % [groups[key][0], groups[key][1], key])


func _mesh_triangles(mesh: Mesh) -> int:
	var total := 0
	for surface in mesh.get_surface_count():
		if mesh is ArrayMesh:
			var indices := (mesh as ArrayMesh).surface_get_array_index_len(surface)
			total += (indices if indices > 0 else (mesh as ArrayMesh).surface_get_array_len(surface)) / 3
	return total


## Saves the planet, reads the save back and compares: the settings, the place and the clock.
func _check_saving() -> void:
	var before := planet.snapshot()
	var ok := UniverseSave.save(planet, "_check")
	var data := UniverseSave.load_data("_check")
	var settings := UniverseSave.settings_from(data)
	ok = ok and settings.world_seed == planet.settings.world_seed
	ok = ok and is_equal_approx(settings.radius, planet.settings.radius)
	ok = ok and is_equal_approx(settings.axial_tilt, planet.settings.axial_tilt)
	var state: Dictionary = data.get("state", {})
	var here: Array = state.get("direction", [0, 0, 0])
	var was: Array = before["direction"]
	for index in 3:
		ok = ok and absf(float(here[index]) - float(was[index])) < 1.0e-6
	var clock := PlanetClock.new()
	clock.restore(state.get("clock", {}))
	ok = ok and absf(clock.time - planet.clock.time) < 1.0e-3
	ok = ok and UniverseSave.list().size() > 0
	UniverseSave.delete("_check")
	print("SAVE_CHECK %s" % ("PASS" if ok else "FAIL"))


func _ready() -> void:
	var asked := PlanetMenu.pending != null
	var user_args := OS.get_cmdline_user_args()
	var menu_first := UniverseStartMenu.requested or user_args.is_empty()
	menu_first = menu_first or "--start-menu" in user_args
	if not asked and menu_first:
		add_child(UniverseStartMenu.new()) # the saved planets and a new one, before anything is built
		for arg in user_args:
			if arg.begins_with("--shot="):
				var path := arg.trim_prefix("--shot=")
				get_tree().create_timer(1.0).timeout.connect(func() -> void:
					get_viewport().get_texture().get_image().save_png(path)
					get_tree().quit())
		return
	var settings := PlanetSettings.new()
	if PlanetMenu.pending != null: # a new planet asked for in the Planet page of the menu
		settings = PlanetMenu.pending
		PlanetMenu.pending = null
		restored_state = PlanetMenu.pending_state
		PlanetMenu.pending_state = {}
	for arg in OS.get_cmdline_user_args():
		if arg == "--continue" or arg.begins_with("--world="):
			var save_name := UniverseSave.latest() if arg == "--continue" \
					else arg.trim_prefix("--world=")
			var data := UniverseSave.load_data(save_name)
			if data.is_empty():
				print("NO_SAVE '%s'" % save_name)
			else:
				settings = UniverseSave.settings_from(data)
				restored_state = data.get("state", {})
		elif arg.begins_with("--save-as="):
			_save_as = arg.trim_prefix("--save-as=")
		elif arg.begins_with("--radius="):
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
		elif arg.begins_with("--climb="):
			_climb = arg.trim_prefix("--climb=").to_float()
		elif arg.begins_with("--hide="):
			_hide = arg.trim_prefix("--hide=")
		elif arg == "--no-shadow":
			_no_shadow = true
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
	planet.restored = restored_state
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
	if _save_as != "":
		print("SAVED %s %s" % [_save_as, UniverseSave.save(planet, _save_as)])
	var here := planet.planet_position().normalized()
	print("LOCAL_HOUR %.2f year %.3f" % [planet.clock.local_hour(here), planet.clock.year_share()])
	if _checking:
		_check_saving()
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


func _process(delta: float) -> void:
	if _frame == 700: # the loading screen is over
		_worst_frame = 0.0
		_slow_frames = 0
	_worst_frame = maxf(_worst_frame, delta)
	if delta > 0.033:
		_slow_frames += 1


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
	if _climb > 0.0 and _frame == 600 and player != null:
		player.process_mode = Node.PROCESS_MODE_DISABLED
		player.global_position.y += _climb
		player.head.rotation.x = -1.0 # look down
	if _hide != "" and _frame % 60 == 0:
		_hide_kind()
	if _no_shadow and _frame % 60 == 0:
		planet.atmosphere.sun.shadow_enabled = false
	if _report_fps and _frame == 900:
		_print_triangle_groups()
	if _report_fps and _frame % 300 == 0:
		var vp := get_viewport().get_viewport_rid()
		var visible := RenderingServer.VIEWPORT_RENDER_INFO_TYPE_VISIBLE
		var calls := RenderingServer.viewport_get_render_info(vp, visible,
				RenderingServer.VIEWPORT_RENDER_INFO_DRAW_CALLS_IN_FRAME)
		var prims := RenderingServer.viewport_get_render_info(vp, visible,
				RenderingServer.VIEWPORT_RENDER_INFO_PRIMITIVES_IN_FRAME)
		var cpu := Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
		print("FPS frame=%d fps=%d alt=%d tiles=%d draw_calls=%d primitives=%d process_ms=%.1f" % [
				_frame, Engine.get_frames_per_second(), planet.altitude(), planet.surface.tiles.size(),
				calls, prims, cpu])
		print("HITCH worst_frame=%.1f ms, frames over 33 ms: %d" % [_worst_frame * 1000.0,
				_slow_frames])
		_worst_frame = 0.0
		_slow_frames = 0
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
		print("HITCH worst_frame=%.1f ms, frames over 33 ms: %d" % [_worst_frame * 1000.0, _slow_frames])
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
