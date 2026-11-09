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
var _gen: VoxelGeneratorScript
var _anchor := Node3D.new() # the voxel viewer follows this (the player once there)
var _player: Player
var _lods := 12
var _view := 2048
var _secs := 60.0
var _lattice := 2
var _seed := 1337
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


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--secs="):
			_secs = float(a.substr(7))
		elif a.begins_with("--shot="):
			_shot = a.substr(7)
		elif a.begins_with("--lattice="):
			_lattice = int(a.substr(10))
		elif a.begins_with("--view="):
			_view = int(a.substr(7))
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
	_gen = Generator.new()
	_gen.set("radius", _radius)
	_gen.set("noise", _noise)
	_gen.set("lattice", _lattice)
	_gen.set("frame", _frame)
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
	_anchor.position = Vector3(0, _radius + _ground, 0)
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
	if _walk_t0 < 0.0 and _t > _loaded_at + 3.0:
		_walk_t0 = _t
		_start = _player.global_position
		Input.action_press(&"move_forward")
		Input.action_press(&"sprint")
	if _walk_t0 > 0.0:
		if _player.is_on_floor():
			_on_floor += 1
		_worst_above = maxf(_worst_above, absf(_ground_above(_player.global_position)))
		if _t > _walk_t0 + _secs:
			_report()
			get_tree().quit()


func _spawn_player() -> void:
	var tool: Object = _terrain.call("get_voxel_tool")
	var from := Vector3(0, _radius + _ground + 1500.0, 0)
	var hit: Object = tool.call("raycast", from, Vector3.DOWN, 3000.0)
	var y := _radius + _ground
	if hit != null:
		y = float((hit.get("position") as Vector3i).y)
	print("WALK loaded after ", snappedf(_t, 0.1), " s; ground hit ", snappedf(y - _radius, 0.1),
			" m (noise ", snappedf(_ground, 0.1), ")")
	_player = PLAYER_SCENE.instantiate() as Player
	add_child(_player)
	_player.global_position = Vector3(0, y + 3.0, 0)


func _report() -> void:
	var travelled := _player.global_position.distance_to(_start)
	var share := 100.0 * float(_on_floor) / maxf(float(_frames), 1.0)
	var verdict := "PASS" if travelled > 100.0 and share > 80.0 and _worst_above < 4.0 else "FAIL"
	print("WALK %s travelled=%.0f m on_floor=%.0f%% worst_above_ground=%.2f m" % [verdict,
			travelled, share, _worst_above])
	print("WALK frames=%d worst_frame=%.1f ms over33ms=%d" % [_frames, _worst_frame * 1000.0, _slow])
	if _shot != "":
		get_viewport().get_texture().get_image().save_png(_shot)

