## Voxel terrain of the REAL planet (task 096). Needs the engine with the voxel module
## (E:\Godot\double\src\bin\godot.windows.editor.double.x86_64.exe) and the double
## planet_crust library. Run (windowed), with the console exe of that folder:
##   --path . res://tests/manual/voxel/real_planet.tscn -- --lods=12 --view=4096 --secs=15
##   --ball=1 --shot=PATH --seed=1337 --scale=1.0
## The planet size is PlanetSettings.earth(scale): 1.0 is Earth.
extends Node3D

const Generator := preload("res://tests/manual/voxel/real_planet_generator.gd")

var _terrain: Node
var _cam: Camera3D
var _ball: RigidBody3D
var _gen: VoxelGeneratorScript
var _radius := 6371000.0
var _up := Vector3.UP
var _lods := 12
var _view := 4096
var _secs := 20.0
var _speed := 60.0
var _altitude := 700.0
var _shot := ""
var _seed := 1337
var _scale := 1.0
var _ball_on := true
var _t := 0.0
var _loaded_at := -1.0
var _stable := 0.0
var _samples: Array[float] = []
var _ground := 0.0
var _forward := Vector3.FORWARD


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--lods="):
			_lods = int(a.substr(7))
		elif a.begins_with("--view="):
			_view = int(a.substr(7))
		elif a.begins_with("--secs="):
			_secs = float(a.substr(7))
		elif a.begins_with("--speed="):
			_speed = float(a.substr(8))
		elif a.begins_with("--shot="):
			_shot = a.substr(7)
		elif a.begins_with("--seed="):
			_seed = int(a.substr(7))
		elif a.begins_with("--scale="):
			_scale = float(a.substr(8))
		elif a.begins_with("--ball="):
			_ball_on = a.substr(7) == "1"
	var settings: Object = ClassDB.class_call_static("PlanetSettings", "earth", _scale)
	settings.set("world_seed", _seed)
	_radius = settings.get("radius")
	var noise: Object = ClassDB.class_call_static("PlanetNoise", "create", settings)
	_pick_land(noise)
	_gen = Generator.new()
	_gen.set("radius", _radius)
	_gen.set("noise", noise)
	_terrain = ClassDB.instantiate("VoxelLodTerrain")
	_terrain.set("lod_count", _lods)
	_terrain.set("generator", _gen)
	_terrain.set("mesher", ClassDB.instantiate("VoxelMesherTransvoxel"))
	_terrain.set("view_distance", _view)
	_terrain.set("bounds", AABB(Vector3.ONE * -_radius * 1.6, Vector3.ONE * _radius * 3.2))
	add_child(_terrain)
	_cam = Camera3D.new()
	_cam.far = 60000.0
	add_child(_cam)
	_place_camera()
	var viewer: Node = ClassDB.instantiate("VoxelViewer")
	viewer.set("view_distance", _view)
	viewer.set("requires_collisions", true)
	_cam.add_child(viewer)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, 30, 0)
	add_child(sun)
	print("REAL start radius=", _radius, " lods=", _lods, " view=", _view, " up=", _up,
			" ground=", snappedf(_ground, 1.0))


## Finds a direction on land that is not too high (the camera and the ball start there).
func _pick_land(noise: Object) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = _seed
	var best_height := -1.0e9
	for i in 400:
		var dir := Vector3(rng.randfn(), rng.randfn(), rng.randfn()).normalized()
		var h: float = noise.call("height", dir.x, dir.y, dir.z)
		if h > 80.0 and h < 400.0:
			_up = dir
			_ground = h
			return
		if h > best_height:
			best_height = h
			_up = dir
			_ground = h


func _place_camera() -> void:
	var side := _up.cross(Vector3.UP)
	if side.length() < 0.01:
		side = _up.cross(Vector3.RIGHT)
	_forward = side.normalized().cross(_up).normalized()
	_cam.position = _up * (_radius + _ground + _altitude)
	_cam.look_at_from_position(_cam.position, _cam.position + _forward * 100.0 - _up * 60.0, _up)


func _stats() -> Dictionary:
	var engine: Object = Engine.get_singleton("VoxelEngine")
	return engine.call("get_stats") if engine != null else {}


func _tasks() -> int:
	var tasks := 0
	var stats := _stats()
	if stats.has("tasks"):
		for k in (stats["tasks"] as Dictionary):
			tasks += int((stats["tasks"] as Dictionary)[k])
	return tasks


func _physics_process(_dt: float) -> void:
	if _ball != null:
		_ball.apply_central_force(-_ball.position.normalized() * 9.8 * _ball.mass)


func _process(dt: float) -> void:
	_t += dt
	if _loaded_at < 0.0:
		_stable = _stable + dt if (_tasks() == 0 and _t > 2.0) else 0.0
		if _stable > 2.0:
			_loaded_at = _t
			print("REAL loaded after ", snappedf(_t, 0.1), " s  blocks=", _gen.get("blocks_asked"),
					" ms_in_heights=", _gen.get("msec_asking"))
			if _ball_on:
				_drop_ball()
	else:
		var moved := _cam.position + _forward * _speed * dt
		var up := moved.normalized()
		_cam.position = up * (_radius + _ground + _altitude)
		_forward = (_forward - up * _forward.dot(up)).normalized()
		_samples.append(dt * 1000.0)
		if _ball != null and fmod(_t, 2.0) < dt:
			print("REAL ball height above radius=", snappedf(_ball.position.length() - _radius, 0.1),
					" vel=", snappedf(_ball.linear_velocity.length(), 0.1))
	if (_loaded_at > 0.0 and _t > _loaded_at + _secs) or _t > 900.0:
		_report()
		get_tree().quit()


func _drop_ball() -> void:
	_ball = RigidBody3D.new()
	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 1.0
	shape.shape = sphere
	_ball.add_child(shape)
	var tool: Object = _terrain.call("get_voxel_tool")
	var from := _up * (_radius + _ground + 1500.0)
	var hit: Object = tool.call("raycast", from, -_up, 3000.0)
	var height := _radius + _ground
	if hit != null:
		var at: Vector3 = Vector3(hit.get("position"))
		height = at.length()
		print("REAL raycast hit ", snappedf(height - _radius, 0.1), " m above the radius (noise says ",
				snappedf(_ground, 0.1), ")")
	else:
		print("REAL raycast: no hit")
	_ball.position = _up * (height + 30.0)
	add_child(_ball)


func _report() -> void:
	var n := _samples.size()
	var sum := 0.0
	var worst := 0.0
	for v in _samples:
		sum += v
		worst = maxf(worst, v)
	var sorted := _samples.duplicate()
	sorted.sort()
	var p99: float = sorted[int(n * 0.99)] if n > 10 else 0.0
	print("REAL flight frames=", n, " avg_ms=", snappedf(sum / maxf(n, 1.0), 0.01),
			" p99_ms=", snappedf(p99, 0.01), " worst_ms=", snappedf(worst, 0.1))
	var mem := Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0
	var video := Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0
	print("REAL mem static_MB=", snappedf(mem, 0.1), " video_MB=", snappedf(video, 0.1), " tris=",
			int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)))
	print("REAL generator: blocks=", _gen.get("blocks_asked"), " ms_in_heights_of=",
			_gen.get("msec_asking"))
	if _ball != null:
		print("REAL ball final height above radius=",
				snappedf(_ball.position.length() - _radius, 0.1))
	if _shot != "":
		get_viewport().get_texture().get_image().save_png(_shot)
