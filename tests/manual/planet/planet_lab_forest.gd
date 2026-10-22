class_name PlanetLabForest
extends RefCounted
## `-- --plants --grounded --forest-walk[=SECONDS] --fixed-fps 60` (SECONDS: 60): the performance
## test of a person walking round the forest in a gusty wind (`--calm`: none; `--run`: jogging).
## The real player walks with the real physics; every frame it looks ahead with rays at chest
## height, steers round trunks and rocks as a person would (to the side with the most room),
## wanders a little now and then so the path is not a line,
## and when it does not get on it turns round and jumps. After the plants have come in (WARM frames)
## it records the real time of every frame and the GPU time, and at the end prints FOREST_WALK with
## the average and 1 % low fps, the frame time percentiles, the slow frames and the distance walked.
## Run it three times and compare the middle values: a single run is noisy.

const WARM := 420 ## frames: the plants round the start come in during the first seconds
const LOOK := 4.5 ## m: how far ahead the person looks
## degrees from the heading
const FEELERS: Array[float] = [0.0, 22.0, -22.0, 50.0, -50.0, 85.0, -85.0]

static var _seconds := -1.0
static var _frame_ms := PackedFloat32Array()
static var _gpu_ms := PackedFloat32Array()
static var _last_us := 0
static var _last_drawn := -1
static var _start := Vector3.ZERO
static var _mark := Vector3.ZERO
static var _mark_frame := 0
static var _stuck := 0
static var _side := 1.0
static var _drift := 0.0
static var _steers := 0
static var _calls := 0.0
static var _prims := 0.0
static var _path := 0.0
static var _render_cpu := 0.0
static var _process_ms := 0.0
static var _physics_ms := 0.0
static var _prev := Vector3.ZERO


static func step(planet: PlanetWorld, player: Player, frame: int) -> void:
	if frame == 1:
		_seconds = _argument_seconds()
		seed(1234) # (the same wander every run: the runs are compared)
		_bark_switches()
	if _seconds < 0.0 or player == null:
		return
	if frame == 2:
		var viewport := player.get_viewport().get_viewport_rid()
		RenderingServer.viewport_set_measure_render_time(viewport, true)
	if frame % 60 == 2:
		Engine.max_fps = 0 # (no cap: the times are what the frames cost; set again, something resets it)
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	if frame % 30 == 0 and not "--calm" in OS.get_cmdline_user_args():
		_wind(frame)
	if frame < 60:
		return
	if frame == 60:
		Input.action_press(&"move_forward")
		if "--run" in OS.get_cmdline_user_args():
			Input.action_press(&"sprint")
		_start = planet.planet_position()
		_mark = _start
		_prev = _start
	_look_ahead(player, frame)
	if frame % 20 == 0:
		var here := planet.planet_position()
		_path += here.distance_to(_prev)
		_prev = here
	if frame < WARM:
		return
	if Engine.get_frames_drawn() == _last_drawn:
		return # (a second physics step of the same picture: not a frame)
	_last_drawn = Engine.get_frames_drawn()
	var now := Time.get_ticks_usec()
	if _last_us > 0:
		_frame_ms.append(float(now - _last_us) / 1000.0)
		var viewport := player.get_viewport().get_viewport_rid()
		_gpu_ms.append(RenderingServer.viewport_get_measured_render_time_gpu(viewport))
		_render_cpu += RenderingServer.viewport_get_measured_render_time_cpu(viewport)
		_process_ms += Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
		_physics_ms += Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0
		var visible := RenderingServer.VIEWPORT_RENDER_INFO_TYPE_VISIBLE
		_calls += RenderingServer.viewport_get_render_info(viewport, visible,
				RenderingServer.VIEWPORT_RENDER_INFO_DRAW_CALLS_IN_FRAME)
		_prims += RenderingServer.viewport_get_render_info(viewport, visible,
				RenderingServer.VIEWPORT_RENDER_INFO_PRIMITIVES_IN_FRAME)
	_last_us = now
	if _frame_ms.size() >= int(_seconds * 60.0):
		_report(player)


## A steady breeze with gusts that come and go, and a direction that slowly turns (`--calm`: none).
static func _wind(frame: int) -> void:
	var seconds := float(frame) / 60.0
	var strength := 0.4 + 0.25 * sin(seconds / 9.0 * TAU) + 0.1 * sin(seconds / 3.1 * TAU)
	WorldWind.set_wind(strength, Vector2.from_angle(0.5 + seconds * 0.03))

## Turns the person away from what is in the way (the mouse's own turn, so the camera follows).
static func _look_ahead(player: Player, frame: int) -> void:
	var space := player.get_world_3d().direct_space_state
	var heading := -player.global_basis.z
	heading.y = 0.0
	heading = heading.normalized()
	var chest := player.global_position + Vector3.UP * 1.0
	var room: Array[float] = []
	for degrees in FEELERS:
		var way := heading.rotated(Vector3.UP, deg_to_rad(degrees))
		var query := PhysicsRayQueryParameters3D.create(chest, chest + way * LOOK)
		query.exclude = [player.get_rid()]
		var hit := space.intersect_ray(query)
		var free := LOOK
		if not hit.is_empty() and (hit["normal"] as Vector3).y < 0.65: # (a slope is not a wall)
			free = chest.distance_to(hit["position"])
		room.append(free)
	var turn := 0.0
	if room[0] < 2.8:
		# something ahead: toward the side with the most room (the nearer to the heading wins a tie)
		var best := 1
		for index in range(1, room.size()):
			if room[index] > room[best] + 0.3:
				best = index
		turn = deg_to_rad(FEELERS[best]) * 0.12
		_steers += 1
	else:
		# open: a slow wander, a turn one way for a while then the other
		if frame % 300 == 0:
			_side = -_side
			_drift = _side * randf_range(0.0, 0.25)
		turn = _drift * 0.02
	if absf(turn) > 0.0001:
		player.call(&"_apply_yaw", turn)
	# no progress for two seconds: turn round and jump out of it
	if frame % 120 == 0:
		var here := player.global_position
		if here.distance_to(_mark) < 0.8:
			_stuck += 1
			player.call(&"_apply_yaw", deg_to_rad(120.0 * _side))
			Input.action_press(&"jump")
		else:
			Input.action_release(&"jump")
		_mark = here


static func _report(player: Player) -> void:
	var count := _frame_ms.size()
	var sorted := _frame_ms.duplicate()
	sorted.sort()
	var gpu := _gpu_ms.duplicate()
	gpu.sort()
	var total := 0.0
	var slow := 0
	var gpu_total := 0.0
	for index in count:
		total += _frame_ms[index]
		gpu_total += _gpu_ms[index]
		if _frame_ms[index] > 33.3:
			slow += 1
	var worst_one_percent := sorted.slice(int(count * 0.99))
	var one_percent_total := 0.0
	for value in worst_one_percent:
		one_percent_total += value
	var low_fps := 1000.0 / maxf(one_percent_total / maxf(float(worst_one_percent.size()), 1.0), 0.001)
	var travelled := _path
	var verdict := "PASS" if travelled > 40.0 and count > 100 else "FAIL"
	print("FOREST_WALK %s frames=%d travelled=%.0f m steers=%d stuck=%d" % [verdict, count,
			travelled, _steers, _stuck])
	print(("FOREST_WALK fps avg=%.1f 1%%low=%.1f | frame ms p50=%.1f p95=%.1f p99=%.1f "
			+ "worst=%.1f | over 33 ms: %d") % [
			1000.0 * count / maxf(total, 0.001), low_fps, sorted[count / 2], sorted[int(count * 0.95)],
			sorted[int(count * 0.99)], sorted[count - 1], slow])
	print("FOREST_WALK gpu ms avg=%.1f p95=%.1f | draw calls avg=%.0f primitives avg=%.0f" % [
			gpu_total / count, gpu[int(count * 0.95)], _calls / count, _prims / count])
	print(("FOREST_WALK cpu ms per frame: render %.1f | scripts %.1f | physics %.1f  "
			+ "(a frame is %.1f ms: gpu busy %.0f %%)") % [
			_render_cpu / count, _process_ms / count, _physics_ms / count, total / count,
			100.0 * gpu_total / maxf(total, 0.001)])
	player.get_tree().quit(0 if verdict == "PASS" else 1)


## `--bark=pom-off` (no parallax march), `--bark=photo-off` (the procedural bark): what they cost.
static func _bark_switches() -> void:
	var material := FloraMeshes.material()
	for argument in OS.get_cmdline_user_args():
		if argument == "--bark=pom-off":
			material.set_shader_parameter(&"bark_pom", 0.0)
		if argument == "--bark=photo-off":
			material.set_shader_parameter(&"bark_photo_on", 0.0)


static func _argument_seconds() -> float:
	for argument in OS.get_cmdline_user_args():
		if argument == "--forest-walk":
			return 60.0
		if argument.begins_with("--forest-walk="):
			return argument.trim_prefix("--forest-walk=").to_float()
	return -1.0
