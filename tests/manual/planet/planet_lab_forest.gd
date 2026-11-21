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
static var _video_peak := 0.0 ## (task 101) peaks over the walk, bytes
static var _texture_peak := 0.0
static var _buffer_peak := 0.0
static var _static_peak := 0.0
static var _prev := Vector3.ZERO
static var _walk_frame := -1 ## the frame the person stood on the ground and set off
static var _floor_frames := 0
static var _best_run := 0.0
static var _wet_samples := 0 ## samples (every 20 frames after the warm-up) with the person in water: a walk over the sea measures nothing
static var _samples := 0
static var _above_sum := 0.0 ## m: the person's height over the ground, summed over the samples
static var _above_max := 0.0


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
	if _walk_frame < 0:
		# the person must STAND on the ground first (the plants and the ground come in over the first seconds), and then look at the map before choosing a direction
		if player.is_on_floor():
			_floor_frames += 1
		else:
			_floor_frames = 0
		if _floor_frames < 30:
			if frame > 4000:
				print("FOREST_WALK FAIL never reached the ground (height over the ground %.0f m)" % [_height_over_ground(planet, player)])
				player.get_tree().quit(1)
			return
		_walk_frame = frame
		var bearing := _survey(planet, player)
		print("FOREST_WALK survey: head %.0f degrees toward the longest dry run (%.0f m of land)" % [rad_to_deg(bearing), _best_run])
		player.call(&"_apply_yaw", bearing)
		if not "--stand" in OS.get_cmdline_user_args(): # (task 101: --stand: the same place and frames without walking, to see what walking costs; the verdict is FAIL then)
			Input.action_press(&"move_forward")
		if "--run" in OS.get_cmdline_user_args():
			Input.action_press(&"sprint")
		_start = planet.planet_position()
		_mark = _start
		_prev = _start
		return
	frame -= _walk_frame - 60 # (the walk's own frame count: the warm-up and the recording count from the moment it stands up)
	var standing := "--stand" in OS.get_cmdline_user_args() # (task 101: standing means the view stays too: the steering was swinging the camera, and the triangles in view with it, 3 M to 20 M)
	if frame % 90 == 0 and not standing:
		# water or a drop 14 m ahead: look at the map again and turn toward the longest dry run
		var ahead := player.global_position + (-player.global_basis.z * Vector3(1, 0, 1)).normalized() * 14.0
		var ahead_y: float = planet.ground_at(ahead.x, ahead.z, player.global_position.y)["y"]
		var ahead_water := planet.water_at_world(Vector3(ahead.x, ahead_y, ahead.z))
		if ahead_water > -INF and ahead_water > ahead_y - 1.5:
			player.call(&"_apply_yaw", _survey(planet, player))
	if not standing:
		_look_ahead(player, frame)
	if frame % 20 == 0:
		var here := planet.planet_position()
		_path += here.distance_to(_prev)
		_prev = here
		if frame >= WARM:
			_samples += 1
			var ground_y: float = planet.ground_at(player.global_position.x, player.global_position.z, player.global_position.y)["y"]
			var above := player.global_position.y - ground_y
			_above_sum += above
			_above_max = maxf(_above_max, above)
			var water := planet.water_at_world(player.global_position)
			if water > -INF and water > player.global_position.y - 0.9: # (the water reaches the waist: wading or swimming)
				_wet_samples += 1
	if frame < WARM:
		return
	if Engine.get_frames_drawn() == _last_drawn:
		return # (a second physics step of the same picture: not a frame)
	_last_drawn = Engine.get_frames_drawn()
	var now := Time.get_ticks_usec()
	if _last_us > 0:
		_frame_ms.append(float(now - _last_us) / 1000.0)
		if OS.has_environment("LAB_LEAN"): # (task 101) frame times only: the render-info and GPU-time reads below may wait for the render thread
			_gpu_ms.append(0.0)
			_last_us = now
			if _frame_ms.size() >= int(_seconds * 60.0):
				_report(player)
			return
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
	if _frame_ms.size() % 60 == 0: # (task 101) the video memory at its highest during the walk
		_video_peak = maxf(_video_peak, Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED))
		_texture_peak = maxf(_texture_peak, Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED))
		_buffer_peak = maxf(_buffer_peak, Performance.get_monitor(Performance.RENDER_BUFFER_MEM_USED))
		_static_peak = maxf(_static_peak, Performance.get_monitor(Performance.MEMORY_STATIC))
	if _frame_ms.size() >= int(_seconds * 60.0):
		_report(player)


## A steady breeze with gusts that come and go, and a direction that slowly turns (`--calm`: none).
static func _wind(frame: int) -> void:
	var seconds := float(frame) / 60.0
	var strength := 0.4 + 0.25 * sin(seconds / 9.0 * TAU) + 0.1 * sin(seconds / 3.1 * TAU)
	WorldWind.set_wind(strength, Vector2.from_angle(0.5 + seconds * 0.03))

## The map before the walk: 24 headings, a ray of ground and water heights out to 240 m for each; the one with the
## longest run of dry land (above the water by 1.5 m, no step over 6 m between samples) wins. Returns the turn
## in radians from where the person faces (positive = the way `_apply_yaw` turns).
static func _survey(planet: PlanetWorld, player: Player) -> float:
	var heading := -player.global_basis.z
	heading.y = 0.0
	heading = heading.normalized()
	var best_turn := 0.0
	_best_run = -1.0
	for index in 24:
		var turn := TAU * float(index) / 24.0
		if turn > PI:
			turn -= TAU
		var way := heading.rotated(Vector3.UP, turn)
		var run := 0.0
		var last_y := player.global_position.y
		for step in range(1, 25):
			var at := player.global_position + way * (10.0 * step)
			var ground_y: float = planet.ground_at(at.x, at.z, last_y)["y"]
			var water := planet.water_at_world(Vector3(at.x, ground_y, at.z))
			if (water > -INF and water > ground_y - 1.5) or absf(ground_y - last_y) > 6.0:
				break
			last_y = ground_y
			run = 10.0 * step
		if run > _best_run + 0.5 or (is_equal_approx(run, _best_run) and absf(turn) < absf(best_turn)):
			_best_run = run
			best_turn = turn
	return best_turn


static func _height_over_ground(planet: PlanetWorld, player: Player) -> float:
	var p := player.global_position
	return p.y - float(planet.ground_at(p.x, p.z, p.y)["y"])


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
	if count >= 300: # (task 101) first third against last third of the walk: what is only there while the world is still settling (the colour map bake...)
		var third := count / 3
		var first := 0.0
		var last := 0.0
		for index in third:
			first += _frame_ms[index]
			last += _frame_ms[count - 1 - index]
		print("FOREST_WALK thirds: first %.1f fps | last %.1f fps" % [1000.0 * third / maxf(first, 0.001), 1000.0 * third / maxf(last, 0.001)])
	var travelled := _path
	# the walk must be a walk on land: over 10 % of the samples in water means the start was in or by the sea (use --earth --seed=8, the forest the pictures use)
	var wet_share := float(_wet_samples) / maxf(float(_samples), 1.0)
	var verdict := "PASS" if travelled > 40.0 and count > 100 and wet_share <= 0.1 else "FAIL"
	print("FOREST_WALK %s frames=%d travelled=%.0f m steers=%d stuck=%d in water=%.0f %% height over ground avg=%.1f max=%.1f m" % [verdict, count,
			travelled, _steers, _stuck, wet_share * 100.0, _above_sum / maxf(float(_samples), 1.0), _above_max])
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
	print("FOREST_WALK video memory peak %.0f MB (textures %.0f MB, buffers %.0f MB) | system memory peak %.0f MB" % [_video_peak / 1048576.0, _texture_peak / 1048576.0,
			_buffer_peak / 1048576.0, _static_peak / 1048576.0])
	_memory_census(player.get_tree().root)
	_census(player.get_tree().root)
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


## What the draw calls are: every visible mesh node in the tree, grouped by its kind (the node's name without its numbers,
## its class, the mesh's name, the surfaces it has) with the count of nodes, of draw calls (one per surface; a multimesh
## is one per surface) and of triangles. Printed as FOREST_CENSUS lines, the biggest first (`--census` only).
## (task 101, --census) where the buffer memory is: every multimesh's instance buffer (64 bytes an instance), and the distinct meshes (about 36 bytes a vertex, 4 an index).
static func _memory_census(root: Node) -> void:
	if not "--census" in OS.get_cmdline_user_args():
		return
	var instance_bytes := {}
	var mesh_bytes := {}
	var seen := {}
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		for child in node.get_children():
			stack.append(child)
		var mesh: Mesh = null
		var kind := String(node.get_class())
		if node is MultiMeshInstance3D and (node as MultiMeshInstance3D).multimesh != null:
			var multi := (node as MultiMeshInstance3D).multimesh
			mesh = multi.mesh
			var far := (node as GeometryInstance3D).visibility_range_begin
			var group := "multimesh instances, range begin %s" % ("0" if far <= 0.0 else ("<250 m" if far < 250.0 else ("<1500 m" if far < 1500.0 else ">=1500 m")))
			instance_bytes[group] = int(instance_bytes.get(group, 0)) + multi.instance_count * 64
		elif node is MeshInstance3D:
			mesh = (node as MeshInstance3D).mesh
			kind = "MeshInstance3D (%s)" % node.get_parent().name.rstrip("0123456789")
		if mesh == null or seen.has(mesh.get_instance_id()):
			continue
		seen[mesh.get_instance_id()] = true
		var bytes := 0
		for surface in mesh.get_surface_count():
			if mesh is ArrayMesh:
				var array_mesh := mesh as ArrayMesh
				bytes += array_mesh.surface_get_array_len(surface) * 36 + maxi(array_mesh.surface_get_array_index_len(surface), 0) * 4
		mesh_bytes[kind] = int(mesh_bytes.get(kind, 0)) + bytes
	for key in instance_bytes:
		print("FOREST_MEMORY %7.1f MB  %s" % [instance_bytes[key] / 1048576.0, key])
	var keys := mesh_bytes.keys()
	keys.sort_custom(func(a: Variant, b: Variant) -> bool: return mesh_bytes[a] > mesh_bytes[b])
	for key in keys.slice(0, 8):
		print("FOREST_MEMORY %7.1f MB  distinct meshes: %s" % [mesh_bytes[key] / 1048576.0, key])
	print("FOREST_MEMORY distinct meshes %d" % seen.size())


static func _census(root: Node) -> void:
	if not "--census" in OS.get_cmdline_user_args():
		return
	var groups := {}
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		for child in node.get_children():
			stack.append(child)
		if not (node is GeometryInstance3D) or not (node as Node3D).is_visible_in_tree():
			continue
		var mesh: Mesh = null
		var instances := 1
		if node is MeshInstance3D:
			mesh = (node as MeshInstance3D).mesh
		elif node is MultiMeshInstance3D and (node as MultiMeshInstance3D).multimesh != null:
			mesh = (node as MultiMeshInstance3D).multimesh.mesh
			instances = (node as MultiMeshInstance3D).multimesh.visible_instance_count
			if instances < 0:
				instances = (node as MultiMeshInstance3D).multimesh.instance_count
		if mesh == null:
			continue
		# (task 101) only what a frame draws: inside its visibility range and (its middle, 5 m up) in the view
		var eye := root.get_viewport().get_camera_3d()
		if eye != null:
			var seen_node := node as GeometryInstance3D
			var away := eye.global_position.distance_to((node as Node3D).global_position)
			if (seen_node.visibility_range_end > 0.0 and away >= seen_node.visibility_range_end) or away < seen_node.visibility_range_begin:
				continue
			if not eye.is_position_in_frustum((node as Node3D).global_position + Vector3.UP * 5.0):
				continue
		var base := String(node.name)
		var trimmed := ""
		for index in base.length():
			if not base[index].is_valid_int():
				trimmed += base[index]
		var key := ""
		var geometry := node as GeometryInstance3D
		var size_class := "tiny"
		var aabb_height := mesh.get_aabb().size.y
		if aabb_height > 12.0:
			size_class = "tree"
		elif aabb_height > 2.5:
			size_class = "shrub/small tree"
		elif aabb_height > 0.6:
			size_class = "plant"
		if OS.has_environment("LAB_CENSUS_NAMES"): # (task 101) which species: the node's name without its numbers
			size_class += " | " + trimmed
		key = "%s | seen %.0f-%.0f m | shadows %s | %s" % [node.get_class().trim_suffix("Instance3D"), geometry.visibility_range_begin, geometry.visibility_range_end,
				"on" if geometry.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF else "off", size_class]
		var calls := mesh.get_surface_count()
		var triangles := 0
		for surface in mesh.get_surface_count():
			var arrays := mesh.surface_get_arrays(surface)
			var indices: Variant = arrays[Mesh.ARRAY_INDEX]
			var vertices: Variant = arrays[Mesh.ARRAY_VERTEX]
			triangles += (indices.size() if indices != null and indices.size() > 0 else (vertices.size() if vertices != null else 0)) / 3
		var entry: Array = groups.get(key, [0, 0, 0, 0])
		entry[0] += 1
		entry[1] += calls
		entry[2] += triangles * instances
		entry[3] += instances
		groups[key] = entry
	var keys := groups.keys()
	keys.sort_custom(func(a: Variant, b: Variant) -> bool: return groups[a][2] > groups[b][2])
	var total_calls := 0
	for key in keys:
		total_calls += groups[key][1]
	print("FOREST_CENSUS drawn mesh nodes (in range and view), by triangles: %d kinds, %d surfaces in all" % [keys.size(), total_calls])
	for index in mini(keys.size(), 24):
		var entry: Array = groups[keys[index]]
		print("FOREST_CENSUS %5d surfaces %6d nodes %11d tris %8d instances | %s" % [entry[1], entry[0], entry[2], entry[3], keys[index]])
