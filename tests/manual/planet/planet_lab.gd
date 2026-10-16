extends Node3D
## Planet lab. Plain run: the player walks a round planet.
##   -- --radius=N     planet radius in metres (default 20000)
##   -- --seed=N       planet seed
##   -- --dir=x,y,z   start there (a direction from the planet's centre) instead of the spawn
##   -- --view-alt=N   no player: a camera N metres above the ground, looking at the horizon
##   -- --view-pitch=N / --view-yaw=N degrees (negative pitch looks down; with --view-alt)
##   -- --shot=PATH    (with a window) saves a picture after the tiles have loaded, then quits
##   -- --walk-check  (use --fixed-fps 60) the real player holds forward and sprint for 90 s,
##                    walking over the planet; prints one WALK_CHECK line
##   -- --planet-check (headless) stands the player on the planet, walks it in steps (turning the
##                     planet under them) and prints one PLANET_CHECK line.

const PLAYER_SCENE := preload("res://actors/player/player.tscn")

var planet: PlanetWorld
var player: Player
var _checking := false
var _walking := false
var _walk_start := Vector3.ZERO
var _walk_floor := 0
var _walk_worst := 0.0
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
		elif arg == "--walk-check":
			_walking = true
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
		print("VIEW altitude %.0f m over %s" % [_view_alt, view_spawn])
		return
	player = PLAYER_SCENE.instantiate() as Player
	add_child(player)
	var spawn := planet.start(player, _start_dir)
	planet.build_now(not _checking)
	print("PLANET radius %.0f m, max level %d, %d tiles in %d ms, spawn %s" % [settings.radius,
			settings.max_level(), planet.surface.tiles.size(), Time.get_ticks_msec() - started,
			spawn])
	_start_up = spawn
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
	if _walking and player != null:
		_walk_step()
		return
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
		_walk_start = planet.planet_position()
	if _frame <= 60:
		return
	if player.is_on_floor():
		_walk_floor += 1
	var at := planet.planet_position().normalized()
	var above := planet.altitude() - planet.noise.height(at.x, at.y, at.z)
	_walk_worst = maxf(_walk_worst, absf(above))
	if _frame >= 60 + 90 * 60:
		var travelled := planet.planet_position().distance_to(_walk_start)
		var verdict := "PASS" if travelled > 150.0 and _walk_worst < 4.0 else "FAIL"
		print("WALK_CHECK %s travelled=%.0f m rebases=%d on_floor=%.0f%% worst_above_ground=%.2f m "
				% [verdict, travelled, planet.rebases, 100.0 * float(_walk_floor) / float(_frame - 60),
				_walk_worst] + "world_pos=%.0f" % player.global_position.length())
		get_tree().quit()
