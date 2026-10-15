extends Node3D
## Procedural world lab. `-- --world-check` (headless): builds the world around the origin,
## prints one WORLD_CHECK line (chunk count, build time, the player standing on the ground).
## `-- --world-shots` (with a window): saves /tmp/world_*.png from a few viewpoints.
## Plain run: the player walks the generated world.

const PLAYER_SCENE := preload("res://actors/player/player.tscn")
const VIEWS := [
	[Vector3(0.0, 14.0, 40.0), Vector3(0.0, 4.0, -40.0)],
	[Vector3(60.0, 40.0, 60.0), Vector3(-40.0, 0.0, -40.0)],
	[Vector3(-80.0, 70.0, 80.0), Vector3(40.0, 10.0, -60.0)],
	[Vector3(10.0, 5.2, 12.0), Vector3(40.0, 4.0, -30.0)],
	[Vector3(-30.0, 9.0, 20.0), Vector3(-10.0, 4.0, -40.0)],
]

var world: ProceduralWorld
var player: Player
var _checking := false
var _shots := false
var _frame := 0
var _camera: Camera3D
var _shot_index := 0
var _seed := 1337
var _autumn := 0.0
var _realism := 0.0
var _fauna_view := false
var _splash_view := false # camera beside the player, shots of the water splash (with --swim)
var _prints_view := false # walk through snow, then look back at the prints
var _ground_views := false
var _perf := false
var _perf_times: Array[float] = []
var _walk := 0.0
var _swim_test := false
var _tower_test := false
var _tower_hold: Node3D
var _tower_spot := Vector2.ZERO
var _tower_state := "run"
var _tower_frame := 0
var _tower_start_y := 0.0
var _last_usec := 0
var _at := Vector2.ZERO


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	_checking = "--world-check" in args
	_shots = "--world-shots" in args
	_ground_views = "--ground" in args
	_fauna_view = "--fauna" in args
	_splash_view = "--splash-view" in args
	_prints_view = "--prints-view" in args
	_perf = "--perf" in args
	_tower_test = "--tower-check" in args # run at a tower wall, jump, climb its holds
	_swim_test = "--swim" in args # drop the player into deep water and see it float
	var weather_name := ""
	var hour := 10.0
	for arg in args:
		if arg.begins_with("--weather="):
			weather_name = arg.trim_prefix("--weather=")
		if arg == "--autumn":
			_autumn = 1.0
		if arg == "--realistic":
			_realism = 1.0
		if arg.begins_with("--hour="):
			hour = arg.trim_prefix("--hour=").to_float()
		if arg.begins_with("--seed="):
			_seed = arg.trim_prefix("--seed=").to_int()
		if arg.begins_with("--at="):
			var parts := arg.trim_prefix("--at=").split(",")
			_at = Vector2(parts[0].to_float(), parts[1].to_float())
	world = ProceduralWorld.new()
	world.settings = WorldSettings.new()
	world.settings.world_seed = _seed
	world.time_of_day = hour
	world.autumn = _autumn
	world.realism = _realism
	add_child(world)
	if weather_name != "":
		world.weather.snap(WorldWeather.State[weather_name.to_upper()])
	player = PLAYER_SCENE.instantiate() as Player
	add_child(player)
	world.set_target(player)
	world.generator.chunks_per_frame = 4
	var started := Time.get_ticks_msec()
	if _tower_test:
		_tower_spot = _find_structure(WorldStructures.Kind.TOWER)
		_at = _tower_spot + Vector2(0.0, 28.0)
	if _swim_test:
		_at = _find_deep_water()
	var spot := Vector3(_at.x, world.ground_height(_at.x, _at.y) + 0.5, _at.y)
	if _swim_test:
		spot.y = 1.5
	player.global_position = spot
	world.build_around(spot)
	if _tower_test:
		_start_tower_test()
	print("WORLD built %d chunks in %d ms" % [world.generator.chunks.size(),
			Time.get_ticks_msec() - started])
	if _checking or "--flora" in args:
		_print_flora()
	if _checking or "--calm" in args:
		_print_calm()
	if "--biomes" in args:
		_print_biomes()
	if "--structures" in args:
		_print_structures()
	if "--lakes" in args:
		_print_lakes()
	if "--rivers" in args:
		_print_rivers()
	if _shots:
		_camera = Camera3D.new()
		_camera.far = 900.0
		add_child(_camera)
		_camera.make_current()


func _physics_process(_delta: float) -> void:
	_frame += 1
	if _tower_test:
		_run_tower_test()
	if _swim_test and _frame == 300:
		var float_y := world.settings.sea_level - WorldSwim.FLOAT_DEPTH
		var swims := world.swim.swimming and absf(player.global_position.y - float_y) < 0.6
		print("SWIM_CHECK %s swimming=%s y=%.2f (floats at %.2f) ground=%.1f" % [
				"PASS" if swims else "FAIL", world.swim.swimming, player.global_position.y, float_y,
				world.ground_height(player.global_position.x, player.global_position.z)])
		get_tree().quit()
	if _checking and _frame == 90:
		var ground := world.ground_height(player.global_position.x, player.global_position.z)
		var standing := absf(player.global_position.y - ground) < 0.3 and player.is_on_floor()
		print("WORLD_CHECK %s chunks=%d player_y=%.2f ground=%.2f" % [
				"PASS" if standing else "FAIL", world.generator.chunks.size(),
				player.global_position.y, ground])
		get_tree().quit()


func _process(delta: float) -> void:
	if _perf:
		_run_perf(delta)
	if not _shots or _frame < 20:
		return
	if _splash_view or _prints_view:
		_special_view()
		return
	if _fauna_view:
		var animal: WorldFauna.Animal = world.fauna._animals[_shot_index % 2 * 9]
		var at := animal.global_position
		_camera.look_at_from_position(at + Vector3(5.0, 2.2, 5.0), at + Vector3(0.0, 1.0, 0.0))
	elif _ground_views:
		# eye height on the spot, looking along a compass direction
		var yaw := float(_shot_index) * PI * 0.5
		var eye := Vector3(_at.x, world.ground_height(_at.x, _at.y) + 2.2, _at.y)
		_camera.look_at_from_position(eye, eye + Vector3(sin(yaw), -0.05, -cos(yaw)) * 30.0)
	else:
		var view: Array = VIEWS[_shot_index]
		var from: Vector3 = view[0] + Vector3(_at.x, 0.0, _at.y)
		var to: Vector3 = view[1] + Vector3(_at.x, 0.0, _at.y)
		from.y = world.ground_height(from.x, from.z) + float((view[0] as Vector3).y) - 3.0
		to.y = world.ground_height(to.x, to.z) + float((view[1] as Vector3).y) - 3.0
		_camera.look_at_from_position(from, to)
	if _frame % 30 == 0:
		get_viewport().get_texture().get_image().save_png("/tmp/world_%d.png" % _shot_index)
		_shot_index += 1
		if _shot_index >= (4 if _ground_views or _fauna_view else VIEWS.size()):
			get_tree().quit()


## How much of the map each biome takes (a 70 x 70 sample over +-1400 m), and the height range.
## `--flora` (also part of `--world-check`): how many different species the built tiles grow, and in
## how many layers. A world that plants one or two species everywhere is a regression.
func _print_flora() -> void:
	var seen := {} # species id -> instances
	var registry := SpeciesRegistry.for_settings(world.settings)
	for node in get_tree().get_nodes_in_group(&"world_flora"):
		var id: int = node.get_meta(&"species", 0)
		if id > 0:
			seen[id] = int(seen.get(id, 0)) + (node as MultiMeshInstance3D).multimesh.instance_count
	var layers := {}
	for id: int in seen.keys():
		layers[registry.by_id(id).layer()] = true
	var rows: Array[String] = []
	for id: int in seen.keys():
		rows.append("%s x%d" % [registry.by_id(id).common_name, seen[id]])
	rows.sort()
	var enough := seen.size() >= 14 and layers.size() == PlantSpecies.Layer.size()
	print("FLORA_CHECK %s species=%d of %d layers=%d/%d" % ["PASS" if enough else "FAIL", seen.size(),
			registry.species.size(), layers.size(), PlantSpecies.Layer.size()])
	if "--flora" in OS.get_cmdline_user_args():
		print("  ", ", ".join(rows))


## The water calm map (how much of the sea's waves a spot gets): over maps scattered around the
## origin, open sea must come out lively and enclosed or shallow water calm. A map that is all one
## or the other is a regression. Only water texels (at least 1 m under the sea) are counted.
func _print_calm() -> void:
	var terrain := world.generator.noise
	var calm := WaterCalmMap.new(ShaderMaterial.new())
	calm.terrain = terrain
	calm.sea_level = world.settings.sea_level
	var lively := 0
	var quiet := 0
	var in_between := 0
	for dz in range(-3, 4):
		for dx in range(-3, 4):
			var middle := Vector2(dx, dz) * 900.0
			var cells := calm._cells(middle, terrain)
			var corner := middle - Vector2.ONE * WaterCalmMap.CELLS * WaterCalmMap.CELL * 0.5
			for index in cells.size():
				var x := corner.x + (float(index % WaterCalmMap.CELLS) + 0.5) * WaterCalmMap.CELL
				var z := corner.y + (float(index / WaterCalmMap.CELLS) + 0.5) * WaterCalmMap.CELL
				if terrain.base_height(x, z) > calm.sea_level - 1.0:
					continue
				if cells[index] >= 230:
					lively += 1
				elif cells[index] <= 90:
					quiet += 1
				else:
					in_between += 1
	print("CALM_CHECK %s water texels: lively=%d calm=%d between=%d" % [
			"PASS" if lively > 3000 and quiet > 3000 else "FAIL", lively, quiet, in_between])


func _print_biomes() -> void:
	var counts := {}
	var examples := {}
	var lowest := INF
	var highest := -INF
	var samples := 0
	for row in 70:
		for column in 70:
			var x := (float(column) / 69.0 - 0.5) * 2800.0
			var z := (float(row) / 69.0 - 0.5) * 2800.0
			var ground := world.ground_height(x, z)
			lowest = minf(lowest, ground)
			highest = maxf(highest, ground)
			var name: String = TerrainNoise.Biome.keys()[world.generator.noise.biome(
					x, z, ground, world.generator.noise.slope(x, z))]
			counts[name] = int(counts.get(name, 0)) + 1
			if world.generator.noise.slope(x, z) < 0.25 and ground > world.settings.sea_level + 2.0:
				examples[name] = Vector2(snappedf(x, 1.0), snappedf(z, 1.0))
			samples += 1
	var parts: Array[String] = []
	for name: String in counts:
		parts.append("%s %d%%" % [name, int(round(100.0 * float(counts[name]) / float(samples)))])
	for name: String in examples:
		print("  AT %s --at=%d,%d" % [name, (examples[name] as Vector2).x, (examples[name] as Vector2).y])
	var under := 0
	for row in 70:
		for column in 70:
			if world.ground_height((float(column) / 69.0 - 0.5) * 2800.0,
					(float(row) / 69.0 - 0.5) * 2800.0) < world.settings.sea_level:
				under += 1
	print("BIOMES seed %d: %s  water %d%%  height %.1f..%.1f" % [_seed, ", ".join(parts),
			int(round(100.0 * float(under) / float(samples))), lowest, highest])


## `-- --perf`: walks the player across the world (8 m/s, tiles stream in as it goes) and prints the
## frame times: PERF avg / worst 1% / worst frame in ms, tiles alive, ground height still found.
func _run_perf(delta: float) -> void:
	var now := Time.get_ticks_usec()
	var real := float(now - _last_usec) / 1000.0
	_last_usec = now
	_walk += delta
	var x := _walk * 8.0
	player.global_position = Vector3(x, world.ground_height(x, 0.0) + 0.3, 0.0)
	player.velocity = Vector3.ZERO
	if _walk > 1.0: # the first second is the start-up
		_perf_times.append(real)
	if _perf_times.size() >= 900:
		_perf_times.sort()
		var total := 0.0
		for time in _perf_times:
			total += time
		print("PERF avg %.1f ms  p99 %.1f ms  worst %.1f ms  tiles %d" % [
				total / float(_perf_times.size()), _perf_times[int(_perf_times.size() * 0.99)],
				_perf_times[_perf_times.size() - 1], world.generator.chunks.size()])
		get_tree().quit()


## The nearest spot to the origin where the sea is more than 6 m deep (rings out from the origin).
func _find_deep_water() -> Vector2:
	for radius in range(20, 1500, 20):
		for degrees in range(0, 360, 20):
			var point := Vector2(radius, 0.0).rotated(deg_to_rad(float(degrees)))
			if world.ground_height(point.x, point.y) < world.settings.sea_level - 6.0:
				return point
	return Vector2.ZERO


## The nearest structure of each kind to the origin: `--at=x,z` shows where to look.
func _print_structures() -> void:
	var found := {}
	for ring in range(0, 25):
		for dz in range(-ring, ring + 1):
			for dx in range(-ring, ring + 1):
				if maxi(absi(dx), absi(dz)) != ring:
					continue
				var plan := WorldStructures.plan(Vector2i(dx, dz), world.generator.noise)
				if plan.is_empty():
					continue
				var name: String = WorldStructures.Kind.keys()[plan["kind"]]
				if not found.has(name):
					var at: Vector3 = plan["position"]
					found[name] = at
					print("STRUCTURE %s --at=%d,%d" % [name, at.x, at.z])


## `-- --tower-check`: climbing the holds on the ruined tower (the first structure of that kind).
func _start_tower_test() -> void:
	PlayerClimbInstall.install(player)
	var tower_at := Vector3(_tower_spot.x, 0.0, _tower_spot.y)
	var best := INF
	for node: Node in get_tree().get_nodes_in_group(&"climb_hold"):
		var hold := node as Node3D
		if hold != null and hold.global_position.distance_to(tower_at) < best:
			best = hold.global_position.distance_to(tower_at)
			_tower_hold = hold
	if _tower_hold == null:
		print("TOWER_CHECK FAIL no climbing holds found on the tower")
		get_tree().quit()
		return
	var out := _tower_hold.global_basis.z.slide(Vector3.UP).normalized()
	var start := _tower_hold.global_position + out * 2.2
	start.y = world.ground_height(start.x, start.z) + 0.1
	player.global_position = start
	player.velocity = Vector3.ZERO
	player.rotation.y = atan2(out.x, out.z) # face the wall, view and body together
	player._look_yaw = 0.0
	player.head.rotation.y = 0.0
	player.third_person_arm.rotation.y = 0.0
	_tower_start_y = start.y


func _run_tower_test() -> void:
	_tower_frame += 1
	if _tower_frame < 90: # settle on the ground first
		return
	match _tower_state:
		"run": # hop onto the wall: put the player in the air right at the holds, as a jump would
			var out := _tower_hold.global_basis.z.slide(Vector3.UP).normalized()
			var at := _tower_hold.global_position + out * 0.55
			at.y = world.ground_height(at.x, at.z) + 1.0
			player.global_position = at
			player.velocity = Vector3.ZERO
			_tower_state = "jump"
			_tower_frame = 90
		"jump":
			player.movement_input_override = Vector2.ZERO
			if player.climb.state == PlayerClimb.State.WALL:
				_tower_state = "climb"
				_tower_frame = 90
			elif _tower_frame > 90 + 150:
				_finish_tower_test("never caught a hold")
		"climb":
			player.movement_input_override = Vector2(0.0, -1.0)
			if _tower_frame > 90 + 420:
				_finish_tower_test("")


func _finish_tower_test(failure: String) -> void:
	var gained := player.global_position.y - _tower_start_y
	if failure == "" and gained < 3.0:
		failure = "climbed only %.1f m" % gained
	print("TOWER_CHECK %s gained=%.1f m state=%d %s" % ["PASS" if failure == "" else "FAIL",
			gained, player.climb.state, failure])
	get_tree().quit()


## The lakes in the 7 x 7 cells around the origin: `--at=x,z` puts the camera there.
func _print_lakes() -> void:
	for cz in range(-3, 4):
		for cx in range(-3, 4):
			var lake := world.generator.noise.lake_in(Vector2i(cx, cz))
			if not lake.is_empty():
				var center: Vector2 = lake["center"]
				print("LAKE --at=%d,%d radius %.0f level %.1f" % [center.x, center.y,
						lake["radius"], lake["level"]])


## Where rivers run: a point on the water in each 256 m square within 1.5 km (`--at=x,z`).
func _print_rivers() -> void:
	var rivers := world.generator.noise.rivers
	var shown := 0
	for gz in range(-6, 6):
		for gx in range(-6, 6):
			var segments := rivers.segments_in(Vector2(gx, gz) * 256.0, 256.0)
			for segment: Array in segments:
				var a: Vector2 = segment[0]
				if a.x >= gx * 256.0 and a.x < (gx + 1) * 256.0 and a.y >= gz * 256.0 \
						and a.y < (gz + 1) * 256.0 and shown < 12 and float(segment[4]) > 4.0:
					print("RIVER --at=%d,%d width %.1f surface %.1f" % [a.x, a.y, segment[4],
							segment[2]])
					shown += 1
					break
	var falls := 0
	for gz in range(-6, 6):
		for gx in range(-6, 6):
			for segment: Array in rivers.segments_in(Vector2(gx, gz) * 256.0, 256.0):
				var drop := float(segment[2]) - float(segment[3])
				var a: Vector2 = segment[0]
				if drop > 2.2 and a.x >= gx * 256.0 and a.x < (gx + 1) * 256.0 and a.y >= gz * 256.0 \
						and a.y < (gz + 1) * 256.0 and falls < 4:
					print("WATERFALL --at=%d,%d drop %.1f m" % [a.x, a.y, drop])
					falls += 1
	print("RIVER_CHECK %s rivers=%d" % ["PASS" if shown > 0 else "FAIL", shown])


## The nearest structure of a kind to the origin (x, z), searching the tiles ring by ring.
func _find_structure(kind: WorldStructures.Kind) -> Vector2:
	for ring in range(0, 25):
		for dz in range(-ring, ring + 1):
			for dx in range(-ring, ring + 1):
				if maxi(absi(dx), absi(dz)) != ring:
					continue
				var plan := WorldStructures.plan(Vector2i(dx, dz), world.generator.noise)
				if not plan.is_empty() and plan["kind"] == kind:
					var at: Vector3 = plan["position"]
					return Vector2(at.x, at.z)
	return Vector2.ZERO


## `--splash-view` (with `--swim`): shots beside the player as it hits the water.
## `--prints-view`: the player walks forward through fresh snow, then the camera looks back.
func _special_view() -> void:
	if _prints_view:
		if _frame == 21:
			world.weather.snap(WorldWeather.State.SNOW)
		player.movement_input_override = Vector2(0.0, -1.0) if _frame < 380 else Vector2.ZERO
		# from above the tree tops, looking down at the trail just walked
		var last: Decal = world.footprints._decals[(world.footprints._next + 59) % 60]
		var trail := last.global_position - Vector3(0.0, 0.5, 0.0) + player.global_basis.z * 1.6
		_camera.look_at_from_position(trail + Vector3(0.0, 3.2, 1.2), trail, Vector3.UP)
		if _frame == 395:
			get_tree().call_group(&"world_flora", "hide") # plants out of the way, only prints and snow
		if _frame in [400, 420]:
			_capture_special(_frame)
		if _frame == 430:
			var shown := 0
			for decal: Decal in world.footprints._decals:
				shown += 1 if decal.visible else 0
			print("PRINTS visible=%d" % shown)
	else:
		_camera.look_at_from_position(player.global_position + Vector3(3.0, 1.6, 3.0),
				player.global_position + Vector3(0.0, 0.2, 0.0))
		if _frame in [64, 72, 84, 100, 140, 200]:
			_capture_special(_frame)
	if _frame > 430:
		get_tree().quit()


func _capture_special(frame: int) -> void:
	get_viewport().get_texture().get_image().save_png("/tmp/special_%d.png" % frame)
