## The real player walks on the voxel planet (task 096). The terrain is not turned: the planet's
## noise is asked through a rotation (`frame`) that puts a chosen land spot at +Y, so the player's
## up and gravity are the world's own. Needs the voxel-module engine, like real_planet.gd:
##   --path . res://tests/manual/voxel/voxel_walk.tscn -- --secs=60 --shot=PATH --lattice=2
## Prints WALK lines: on-floor share, how far above the noise's ground the player stood, frames.
extends Node3D

const Generator := preload("res://tests/manual/voxel/real_planet_generator.gd")
const PLAYER_SCENE := preload("res://actors/player/player.tscn")

var _radius := 6371000.0
var _noise: Object
var _frame := Basis.IDENTITY
var _ground := 0.0
var _terrain: Node
var _gen: Object
var _native := false
var _anchor := Node3D.new() # the voxel viewer follows this (the player once there)
var _player: Player
var _lods := 12
var _view := 2048
var _secs := 60.0
var _lattice := 2
var _seed := 1337
var _exact_lods := 1
var _mid_lods := 3
var _lattice_far := 4
var _shot := ""
var _t := 0.0
var _stable := 0.0
var _loaded_at := -1.0
var _walk_t0 := -1.0
var _start := Vector3.ZERO
var _on_floor := 0
var _frames := 0
var _worst_above := 0.0
var _worst_frame := 0.0
var _slow := 0
var _caves := false
var _dig := false # dig a hole under the player and see them fall in
var _dig_y := 0.0
var _dig_at := -1.0
var _fly := 0.0 # --fly=SPEED: free mode at this speed (m/s) instead of walking
var _seams := false # --seam-check: physics rays over a grid against the planet's height
var _dig_many := false # --dig-many: 200 holes round the player
var _jump := false # --jump: jump every 2 s
var _mem0 := 0.0
var _next_report := 60.0
var _min_above := 0.0
var _hitches: PackedStringArray = []
var _did_special := false
var _visit := false # start the player inside a tunnel
var _cave_at := Vector3.ZERO


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--secs="):
			_secs = float(a.substr(7))
		elif a.begins_with("--shot="):
			_shot = a.substr(7)
		elif a.begins_with("--lattice="):
			_lattice = int(a.substr(10))
		elif a.begins_with("--mid-lods="):
			_mid_lods = int(a.substr(11))
		elif a.begins_with("--lattice-far="):
			_lattice_far = int(a.substr(14))
		elif a.begins_with("--exact-lods="):
			_exact_lods = int(a.substr(13))
		elif a.begins_with("--view="):
			_view = int(a.substr(7))
		elif a == "--caves":
			_caves = true
		elif a.begins_with("--fly="):
			_fly = float(a.substr(6))
		elif a == "--seam-check":
			_seams = true
		elif a == "--dig-many":
			_dig_many = true
		elif a == "--jump":
			_jump = true
		elif a == "--dig":
			_dig = true
		elif a == "--cave-visit":
			_caves = true
			_visit = true
		elif a.begins_with("--seed="):
			_seed = int(a.substr(7))
	var settings: Object = ClassDB.class_call_static("PlanetSettings", "earth", 1.0)
	settings.set("world_seed", _seed)
	_radius = settings.get("radius")
	_noise = ClassDB.class_call_static("PlanetNoise", "create", settings)
	var up := _pick_land()
	var side := up.cross(Vector3.RIGHT)
	if side.length() < 0.01:
		side = up.cross(Vector3.FORWARD)
	side = side.normalized()
	_frame = Basis(side, up, side.cross(up)) # turns +Y into the chosen direction
	var forced := "--gdscript-gen" in OS.get_cmdline_user_args()
	_native = ClassDB.class_exists("VoxelGeneratorPlanet") and not forced
	if _native:
		_gen = ClassDB.instantiate("VoxelGeneratorPlanet")
		_gen.call("set_radius", _radius)
		_gen.call("set_noise", _noise)
		_gen.call("set_frame", _frame)
		_gen.call("set_caves", _caves)
		_gen.call("set_cave_seed", _seed)
		_gen.call("set_exact_lods", _exact_lods)
		_gen.call("set_mid_lods", _mid_lods)
		_gen.call("set_lattice_mid", _lattice)
		_gen.call("set_lattice_far", _lattice_far)
	else:
		_gen = Generator.new()
		_gen.set("radius", _radius)
		_gen.set("noise", _noise)
		_gen.set("lattice", _lattice)
		_gen.set("exact_lods", _exact_lods)
		_gen.set("frame", _frame)
		if _caves:
			_gen.call("setup_caves", _seed)
	if _visit:
		_find_cave()
	print("WALK generator: ", "C++ module" if _native else "GDScript")
	_terrain = ClassDB.instantiate("VoxelLodTerrain")
	_terrain.set("lod_count", _lods)
	_terrain.set("generator", _gen)
	_terrain.set("mesher", ClassDB.instantiate("VoxelMesherTransvoxel"))
	_terrain.set("view_distance", _view)
	var material := ShaderMaterial.new()
	material.shader = load("res://shaders/voxel/voxel_ground.gdshader")
	material.set_shader_parameter("radius", _radius)
	_terrain.set("material", material)
	_terrain.set("bounds", AABB(Vector3.ONE * -_radius * 1.6, Vector3.ONE * _radius * 3.2))
	add_child(_terrain)
	add_child(_anchor)
	_anchor.position = _cave_at if _visit else Vector3(0, _radius + _ground, 0)
	var viewer: Node = ClassDB.instantiate("VoxelViewer")
	viewer.set("view_distance", _view)
	viewer.set("requires_collisions", true)
	_anchor.add_child(viewer)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, 30, 0)
	sun.shadow_enabled = true
	add_child(sun)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_SKY
	env.environment.sky = Sky.new()
	env.environment.sky.sky_material = ProceduralSkyMaterial.new()
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	add_child(env)
	print("WALK start radius=", _radius, " ground=", snappedf(_ground, 0.1), " lattice=", _lattice)


func _pick_land() -> Vector3:
	var rng := RandomNumberGenerator.new()
	rng.seed = _seed
	var best := Vector3.UP
	var best_height := -1.0e9
	for i in 400:
		var dir := Vector3(rng.randfn(), rng.randfn(), rng.randfn()).normalized()
		var h: float = _noise.call("height", dir.x, dir.y, dir.z)
		if h > 80.0 and h < 400.0:
			_ground = h
			return dir
		if h > best_height:
			best_height = h
			best = dir
	_ground = best_height
	return best


func _tasks() -> int:
	var engine: Object = Engine.get_singleton("VoxelEngine")
	var stats: Dictionary = engine.call("get_stats") if engine != null else {}
	var tasks := 0
	if stats.has("tasks"):
		for k in (stats["tasks"] as Dictionary):
			tasks += int((stats["tasks"] as Dictionary)[k])
	return tasks


func _ground_above(world: Vector3) -> float:
	var dir := _frame * world.normalized()
	var h: float = _noise.call("height", dir.x, dir.y, dir.z)
	return world.length() - _radius - h


func _process(dt: float) -> void:
	_t += dt
	if _loaded_at < 0.0:
		_stable = _stable + dt if (_tasks() == 0 and _t > 2.0) else 0.0
		if _stable > 2.0:
			_loaded_at = _t
			_spawn_player()
		elif _t > 600.0:
			print("WALK FAIL: the terrain did not finish loading")
			get_tree().quit()
		return
	_anchor.global_position = _player.global_position
	_frames += 1
	_worst_frame = maxf(_worst_frame, dt)
	if dt > 0.033:
		_slow += 1
		if dt > 0.05 and _hitches.size() < 12:
			_hitches.append("%.0fs:%.0fms" % [_t - _loaded_at, dt * 1000.0])
	if _seams and not _did_special and _t > _loaded_at + 4.0:
		_did_special = true
		_seam_check()
		return
	if _dig_many and not _did_special and _t > _loaded_at + 3.0:
		_did_special = true
		_dig_many_holes()
	if _jump and _walk_t0 > 0.0 and int((_t - _walk_t0) * 10.0) % 20 == 0 and _player.is_on_floor():
		Input.action_press(&"jump")
	elif _jump:
		Input.action_release(&"jump")
	if _walk_t0 < 0.0 and _t > _loaded_at + 3.0:
		_walk_t0 = _t
		_start = _player.global_position
		_mem0 = Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0
		if _fly > 0.0:
			_player.set_free_mode(true)
			_player.free_mode_speed = _fly
		Input.action_press(&"move_forward")
		Input.action_press(&"sprint")
	if _dig and _dig_at < 0.0 and _t > _loaded_at + 2.0:
		_dig_at = _t
		_dig_y = _player.global_position.y
		var tool: Object = _terrain.call("get_voxel_tool")
		tool.set("mode", 1) # VoxelTool.MODE_REMOVE
		var centre := _player.global_position + Vector3(0, -1.0, 0)
		var before: float = tool.call("get_voxel_f", Vector3i(centre.round()))
		tool.call("do_sphere", centre, 3.0)
		var after: float = tool.call("get_voxel_f", Vector3i(centre.round()))
		print("WALK dig: voxel under the player ", snappedf(before, 0.01), " -> ", snappedf(after, 0.01))
	if _dig and _dig_at > 0.0 and _t > _dig_at + 3.0 and _dig_y > 0.0:
		print("WALK dig: the player's height ", snappedf(_dig_y, 0.01), " -> ",
				snappedf(_player.global_position.y, 0.01), " m (on floor: ", _player.is_on_floor(), ")")
		_dig_y = -1.0
	if _walk_t0 > 0.0:
		if _player.is_on_floor():
			_on_floor += 1
		var above := _ground_above(_player.global_position)
		_worst_above = maxf(_worst_above, absf(above))
		_min_above = minf(_min_above, above)
		if _t > _walk_t0 + _next_report - 0.0 and _next_report < _secs:
			_next_report += 60.0
			print("WALK at ", snappedf(_t - _walk_t0, 1.0), " s: travelled ",
					snappedf(_player.global_position.distance_to(_start), 1.0), " m, memory ",
					snappedf(Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0, 0.1),
					" MB, voxel tasks ", _tasks())
		if _t > _walk_t0 + _secs:
			_report()
			get_tree().quit()


func _spawn_player() -> void:
	var tool: Object = _terrain.call("get_voxel_tool")
	var from := Vector3(0, _radius + _ground + 1500.0, 0)
	var reach := 3000.0
	if _visit:
		from = _cave_at
		reach = 60.0
		print("WALK cave voxel value at the target: ", snappedf(
				tool.call("get_voxel_f", Vector3i(_cave_at.round())), 0.01), " (positive: air)")
	var hit: Object = tool.call("raycast", from, Vector3.DOWN, reach)
	var y := from.y if _visit else _radius + _ground
	if hit != null:
		y = float((hit.get("position") as Vector3i).y)
	elif _visit:
		print("WALK no floor found under the cave target")
	print("WALK loaded after ", snappedf(_t, 0.1), " s; ground hit ", snappedf(y - _radius, 0.1),
			" m (noise ", snappedf(_ground, 0.1), ")")
	_player = PLAYER_SCENE.instantiate() as Player
	add_child(_player)
	_player.global_position = Vector3(_cave_at.x if _visit else 0.0, y + (2.0 if _visit else 3.0),
			_cave_at.z if _visit else 0.0)


func _report() -> void:
	var travelled := _player.global_position.distance_to(_start)
	var share := 100.0 * float(_on_floor) / maxf(float(_frames), 1.0)
	var verdict := "PASS" if travelled > 100.0 and share > 80.0 and _worst_above < 4.0 else "FAIL"
	print("WALK %s travelled=%.0f m on_floor=%.0f%% worst_above_ground=%.2f m" % [verdict,
			travelled, share, _worst_above])
	print("WALK frames=%d worst_frame=%.1f ms over33ms=%d" % [_frames, _worst_frame * 1000.0, _slow])
	print("WALK lowest below the noise's ground: ", snappedf(_min_above, 0.01), " m; memory ",
			snappedf(_mem0, 0.1), " -> ", snappedf(
			Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0, 0.1), " MB; hitches ",
			", ".join(_hitches))
	if _shot != "":
		get_viewport().get_texture().get_image().save_png(_shot)



## The most tunnel-like point 20-100 m under the ground near the spawn (the middle of a tunnel).
func _find_cave() -> void:
	var best := 1.0e9
	for x in range(-300, 301, 10):
		for z in range(-300, 301, 10):
			var ground_y := _radius + _ground
			for depth in range(20, 101, 5):
				var p := Vector3(x, ground_y - depth, z)
				p.y = sqrt(maxf(_radius * _radius - x * x - z * z, 0.0)) + (_ground - depth)
				var above := _ground_above(p)
				if above > -15.0:
					continue
				var c: float = _gen.call("get_cave_field" if _native else "cave_field", p)
				if c < best:
					best = c
					_cave_at = p
	print("WALK cave target ", _cave_at.snapped(Vector3.ONE * 0.1), " field ", snappedf(best, 0.001),
			" ground above it ", snappedf(-_ground_above(_cave_at), 0.1), " m")


## Physics rays from above over a grid round the player: where is there no ground, or ground that
## is not where the planet's noise says (a crack between patches shows up as a miss or a step).
func _seam_check() -> void:
	var space := get_world_3d().direct_space_state
	var rays := 0
	var misses := 0
	var off := 0
	var worst := 0.0
	var worst_at := Vector2.ZERO
	var centre := _player.global_position
	for gx in range(-300, 301, 3):
		for gz in range(-300, 301, 3):
			var top := Vector3(centre.x + gx, centre.y + 200.0, centre.z + gz)
			var query := PhysicsRayQueryParameters3D.create(top, top + Vector3(0, -400, 0))
			query.exclude = [_player.get_rid()]
			var hit := space.intersect_ray(query)
			rays += 1
			if hit.is_empty():
				misses += 1
				print("SEAMS no ground at ", gx, ", ", gz)
				_probe_gap(space, centre + Vector3(gx, 0, gz))
				continue
			var pos: Vector3 = hit["position"]
			var err := absf(_ground_above(pos))
			if err > 0.5:
				off += 1
			if err > worst:
				worst = err
				worst_at = Vector2(gx, gz)
	print("SEAMS rays=", rays, " no ground=", misses, " off by >0.5 m=", off, " worst error ",
			snappedf(worst, 0.01), " m at ", worst_at)
	get_tree().quit()


## 200 holes of 3 m round the player: the cost of the edits and of the colliders updating.
func _dig_many_holes() -> void:
	var tool: Object = _terrain.call("get_voxel_tool")
	tool.set("mode", 1)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var centre := _player.global_position
	var started := Time.get_ticks_usec()
	var worst_call := 0
	for i in 200:
		var at := centre + Vector3(rng.randf_range(-60, 60), -1.0, rng.randf_range(-60, 60))
		at.y = _radius + _ground_height_at(at)
		var t := Time.get_ticks_usec()
		tool.call("do_sphere", at, 3.0)
		worst_call = maxi(worst_call, Time.get_ticks_usec() - t)
	print("WALK dig-many: 200 holes in ", (Time.get_ticks_usec() - started) / 1000, " ms (worst call ",
			worst_call / 1000.0, " ms)")


func _ground_height_at(world: Vector3) -> float:
	var dir := _frame * world.normalized()
	return _noise.call("height", dir.x, dir.y, dir.z)


## Rays 0.1 m apart over 3 m x 3 m round a point that had no ground: how big is the gap?
func _probe_gap(space: PhysicsDirectSpaceState3D, at: Vector3) -> void:
	var misses := 0
	var total := 0
	var min_x := 99.0
	var max_x := -99.0
	var min_z := 99.0
	var max_z := -99.0
	for ix in range(-15, 16):
		for iz in range(-15, 16):
			var top := Vector3(at.x + ix * 0.1, at.y + 200.0, at.z + iz * 0.1)
			var query := PhysicsRayQueryParameters3D.create(top, top + Vector3(0, -400, 0))
			query.exclude = [_player.get_rid()]
			total += 1
			if space.intersect_ray(query).is_empty():
				misses += 1
				min_x = minf(min_x, ix * 0.1)
				max_x = maxf(max_x, ix * 0.1)
				min_z = minf(min_z, iz * 0.1)
				max_z = maxf(max_z, iz * 0.1)
	print("SEAMS gap probe: ", misses, " of ", total, " rays miss, x ", min_x, "..", max_x, " z ",
			min_z, "..", max_z)
