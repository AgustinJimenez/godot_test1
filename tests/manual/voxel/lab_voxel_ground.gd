## `planet_lab --voxel` (task 096): the ground of the planet is a VoxelLodTerrain instead of the
## heightmap tiles. Needs the voxel-module engine (E:\Godot\double\src\bin\...). The terrain lives
## in the PLANET's space (its generator asks the lab's own PlanetNoise) and is moved with the
## lab's PlanetFrame, so the flat-world game around the player (up is +Y) keeps working:
##   world = rot * (q - anchor) + origin_w   ->   terrain transform (rot, origin_w - rot * anchor)
## The heightmap tiles keep being built (that is wasted work for now) but their ground and
## colliders are switched off; their plants stay. The player is held until the voxel ground under
## them has a collider.
extends Node3D

var ground_ready := false

var _planet: PlanetWorld
var _player: Node3D
var _terrain: Node
var _material: ShaderMaterial
var _key := ""
var _frame := 0
var _stable := 0.0
var _announced := false
var _peak_tasks := 0
var _generator: Object
var _tiles_off := {} # instance id -> true: the tiles whose ground is already switched off
var _water: Array[Node] = [] # the sea and the rivers: thin volumes over the ground (no collision)
var _rivers_wanted := false
var _dig_test := false
var _surface_test := false
var _find := false
var _surface_frame := 0
var _dig_frame := 0
var _dig_y := 0.0
var _dig_radius := 2.5
var _cover: CanvasLayer
var _cover_label: Label
var _map_task := -1
var _map_image: Image
var _map_rows := 0
var _map_started := 0
var _map_steep := 0.0 # the steepness the map's colours are for (snow and scree depend on it)
var _map_widths: Array[int] = []


## The lab's one call: the voxel ground, or none (and a message) on an engine without the module.
static func attach(lab: Node, planet: PlanetWorld, player: Node3D) -> Node3D:
	if not available():
		print("VOXEL this engine has no voxel module (E:/Godot/double/src/bin has one): ignored")
		return null
	var node: Node3D = (load("res://tests/manual/voxel/lab_voxel_ground.gd") as GDScript).new()
	lab.add_child(node)
	node.call("setup", planet, player)
	return node


static func available() -> bool:
	return ClassDB.class_exists("VoxelLodTerrain") and ClassDB.class_exists("VoxelViewer")


func setup(planet: PlanetWorld, player: Node3D, view := 2048) -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--voxel-view="):
			view = int(arg.trim_prefix("--voxel-view="))
	_planet = planet
	_player = player
	# the tiles build no ground mesh nor collider, and the plants stand on the exact height (native planet_crust; an older library lacks it)
	planet.settings.set("voxel_ground", true)
	var radius := planet.settings.radius
	# (loaded here, not preloaded: that script extends a voxel class the stock engine lacks, and
	# the lab must still compile there)
	var args := OS.get_cmdline_user_args()
	_dig_test = "--voxel-dig-test" in args
	_surface_test = "--voxel-surface-check" in args
	_find = "--voxel-find" in args
	for arg in args:
		if arg.begins_with("--voxel-steep="):
			_map_steep = float(arg.trim_prefix("--voxel-steep="))
	var gen: Object
	if ClassDB.class_exists("VoxelGeneratorPlanet") and not "--voxel-gdscript" in args:
		# (C++, built into the engine: scripts/install_voxel_planet_module.sh)
		gen = ClassDB.instantiate("VoxelGeneratorPlanet")
		gen.call("set_radius", radius)
		gen.call("set_noise", planet.noise)
		gen.call("set_caves", "--voxel-caves" in args)
		gen.call("set_cave_seed", planet.settings.world_seed)
	else:
		# (loaded here, not preloaded: that script extends a voxel class the stock engine lacks, and
		# the lab must still compile there)
		gen = (load("res://tests/manual/voxel/real_planet_generator.gd") as GDScript).new()
		gen.set("radius", radius)
		gen.set("noise", planet.noise)
		gen.set("lattice", 2)
		gen.set("exact_lods", 1)
		if "--voxel-caves" in args:
			gen.call("setup_caves", planet.settings.world_seed)
	_generator = gen
	print("VOXEL generator: ", gen.get_class() if gen.get_class() != "Resource" else "GDScript")
	_terrain = ClassDB.instantiate("VoxelLodTerrain")
	_terrain.set("lod_count", 12 if radius > 1.0e6 else 9)
	_terrain.set("generator", gen)
	_terrain.set("mesher", ClassDB.instantiate("VoxelMesherTransvoxel"))
	_terrain.set("view_distance", view)
	_terrain.set("bounds", AABB(Vector3.ONE * -radius * 1.6, Vector3.ONE * radius * 3.2))
	_material = ShaderMaterial.new()
	_material.shader = load("res://shaders/voxel/voxel_ground.gdshader")
	_material.set_shader_parameter("radius", radius)
	_give_scans()
	_terrain.set("material", _material)
	add_child(_terrain)
	var viewer: Node = ClassDB.instantiate("VoxelViewer")
	viewer.set("view_distance", view)
	viewer.set("requires_collisions", true)
	player.add_child(viewer)
	if planet.settings.sea_on and not "--voxel-no-sea" in args:
		_make_water(1, 4096, PlanetTile.water_material())
	_rivers_wanted = planet.settings.hydrology_on and not "--voxel-no-rivers" in args
	_follow_frame()
	_player.process_mode = Node.PROCESS_MODE_DISABLED
	_make_cover()
	_start_colour_map()
	print("VOXEL ground on: radius ", radius, " lods ", _terrain.get("lod_count"))


func _physics_process(_delta: float) -> void:
	_frame += 1
	_follow_frame()
	if _rivers_wanted and _planet.noise.drainage != null: # (the valleys are solved on a worker thread: the water asks them)
		_rivers_wanted = false
		var river := ShaderMaterial.new()
		river.shader = load("res://shaders/voxel/voxel_river.gdshader")
		river.render_priority = 1
		river.set_shader_parameter("sea_radius", _planet.settings.radius + _planet.settings.sea_level)
		_make_water(2, 1024, river)
	if _frame % 20 == 0:
		_switch_tiles_off()
	_poll_colour_map()
	if _map_task < 0 and ground_ready and not _map_widths.is_empty():
		_begin_map_stage()
	if _dig_test and ground_ready:
		_dig_test_step()
	if _find and ground_ready:
		_surface_frame += 1
		if _surface_frame == 60:
			_find_places()
	if _surface_test and ground_ready:
		_surface_frame += 1
		if _surface_frame == 240:
			_surface_check()
	if not ground_ready:
		_wait_for_ground(_delta)
		_update_cover()
		if not ground_ready and not _planet.loading:
			_player.process_mode = Node.PROCESS_MODE_DISABLED # (the planet let them in: not yet)


func _follow_frame() -> void:
	var frame := _planet.frame
	var key := "%s|%s|%s" % [frame.rot, frame.anchor, frame.origin_w]
	if key == _key:
		return
	_key = key
	var anchor := Vector3(frame.anchor[0], frame.anchor[1], frame.anchor[2])
	var placed := Transform3D(frame.rot, frame.origin_w - frame.rot * anchor)
	_terrain.global_transform = placed
	for water in _water:
		(water as Node3D).global_transform = placed
	_material.set_shader_parameter("world_to_planet", placed.affine_inverse())


## The sea (mode 1) or the rivers (mode 2) as a terrain of their own: a thin volume of water over the ground.
func _make_water(mode: int, view: int, material: Material) -> void:
	var radius := _planet.settings.radius
	var gen: Object = ClassDB.instantiate("VoxelGeneratorPlanet")
	gen.call("set_radius", radius)
	gen.call("set_noise", _planet.noise)
	gen.call("set_water", mode)
	gen.call("set_sea_level", _planet.settings.sea_level)
	var water: Node3D = ClassDB.instantiate("VoxelLodTerrain")
	water.set("lod_count", _terrain.get("lod_count"))
	water.set("generator", gen)
	water.set("mesher", ClassDB.instantiate("VoxelMesherTransvoxel"))
	water.set("view_distance", view)
	water.set("bounds", AABB(Vector3.ONE * -radius * 1.6, Vector3.ONE * radius * 3.2))
	water.set("generate_collisions", false)
	water.set("material", material)
	add_child(water)
	water.global_transform = _terrain.global_transform
	_water.append(water)
	print("VOXEL water ", ["", "sea", "rivers"][mode], " on, view ", view)


func _switch_tiles_off() -> void:
	# (only the tiles not seen before: a search of ~700 tiles cost a 29 ms frame every 20)
	for tile: PlanetTile in _planet.surface.tiles.values():
		var id := tile.get_instance_id()
		if _tiles_off.has(id):
			continue
		_tiles_off[id] = true
		if tile.ground_instance != null:
			tile.ground_instance.visible = false
		for body in tile.find_children("*", "CollisionObject3D", true, false):
			(body as CollisionObject3D).collision_layer = 0
	if _tiles_off.size() > 4000: # (tiles come and go: forget the old ones)
		_tiles_off.clear()


func _tasks() -> int:
	var engine: Object = Engine.get_singleton("VoxelEngine")
	var stats: Dictionary = engine.call("get_stats") if engine != null else {}
	var tasks := 0
	if stats.has("tasks"):
		for k in (stats["tasks"] as Dictionary):
			tasks += int((stats["tasks"] as Dictionary)[k])
	return tasks


func _wait_for_ground(delta: float) -> void:
	_stable = _stable + delta if _tasks() == 0 else 0.0
	if _stable < 2.0:
		return
	var space := get_world_3d().direct_space_state
	var from := _player.global_position + Vector3(0, 60, 0)
	var query := PhysicsRayQueryParameters3D.create(from, from + Vector3(0, -200, 0), 1)
	var hit := space.intersect_ray(query)
	if hit.is_empty():
		return
	ground_ready = true
	_lift_cover()
	if _planet.spawn_on_solid_ground: # (a swim check starts the player in the sea on purpose)
		_player.global_position = (hit["position"] as Vector3) + Vector3(0, 0.05, 0)
	_player.process_mode = Node.PROCESS_MODE_INHERIT
	print("VOXEL ground ready after %d ms (the process started): the player stands at %s" % [
			Time.get_ticks_msec(), _player.global_position.snapped(Vector3.ONE * 0.1)])


## The loading screen: black and a percentage, over the lab's own, until the ground is there.
func _make_cover() -> void:
	_cover = CanvasLayer.new()
	_cover.layer = 100
	var rect := ColorRect.new()
	rect.color = Color.BLACK
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_cover.add_child(rect)
	_cover_label = Label.new()
	_cover_label.set_anchors_preset(Control.PRESET_CENTER)
	_cover_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_cover_label.text = "Generating the planet's ground..."
	_cover.add_child(_cover_label)
	add_child(_cover)


func _update_cover() -> void:
	var tasks := _tasks()
	_peak_tasks = maxi(_peak_tasks, tasks)
	var done := 0.0 if _peak_tasks == 0 else 1.0 - float(tasks) / float(_peak_tasks)
	var map_done := 1.0 if _map_image == null or _map_task < 0 else 0.0
	_cover_label.text = "Generating the planet's ground...  %d %%" % int(
			100.0 * minf(done, 0.99) * (0.9 + 0.1 * map_done))


func _lift_cover() -> void:
	var fade := create_tween()
	for child in _cover.get_children():
		if child is CanvasItem:
			fade.parallel().tween_property(child, "modulate:a", 0.0, 0.8)
	fade.tween_callback(_cover.queue_free)


## The planet's own ground colours as one picture (longitude x latitude), baked on a worker thread:
## the voxel mesh has no per-vertex colours, so the shader reads this by direction. Coarse on a
## big planet (about 20 km a pixel on Earth): the near detail is the shader's own.
func _start_colour_map() -> void:
	# a quick coarse map first, the finer one (Earth) only once the ground is there: the bake and the
	# terrain share the cores
	_map_widths.assign([1024, 2048] if _planet.settings.radius > 1.0e6 else [1024])
	_begin_map_stage()


func _begin_map_stage() -> void:
	var width: int = _map_widths.pop_front()
	_map_image = Image.create(width, width / 2, false, Image.FORMAT_RGB8)
	_map_rows = width / 2
	_map_started = Time.get_ticks_msec()
	_map_task = WorkerThreadPool.add_task(_bake_colour_map.bind(width))


func _bake_colour_map(width: int) -> void:
	var noise := _planet.noise
	var height := width / 2
	for y in height:
		var lat := (0.5 - (y + 0.5) / height) * PI
		var dirs := PackedVector3Array()
		dirs.resize(width)
		for x in width:
			var lon := ((x + 0.5) / width - 0.5) * TAU
			dirs[x] = Vector3(cos(lat) * cos(lon), sin(lat), cos(lat) * sin(lon))
		var heights := noise.heights_of(dirs)
		var steeps := PackedFloat32Array()
		steeps.resize(width)
		steeps.fill(_map_steep)
		var colours := noise.colours_of(dirs, heights, steeps)
		for x in width:
			_map_image.set_pixel(x, y, colours[x])


func _poll_colour_map() -> void:
	if _map_task < 0 or not WorkerThreadPool.is_task_completed(_map_task):
		return
	WorkerThreadPool.wait_for_task_completion(_map_task)
	_map_task = -1
	_material.set_shader_parameter("colour_map", ImageTexture.create_from_image(_map_image))
	_material.set_shader_parameter("use_map", not "--voxel-nomap" in OS.get_cmdline_user_args())
	print("VOXEL colour map ready (", _map_image.get_width(), " x ", _map_image.get_height(),
			") after ", Time.get_ticks_msec() - _map_started, " ms of baking")


## The near ground's scans (the tiles' own textures) and the switch for the lab's anchor globals.
func _give_scans() -> void:
	for scan in ["gravel", "red", "leaf"]:
		for kind in ["c", "n"]:
			var path := "res://assets/textures/ground/scans/%s_%s.png" % [scan, kind]
			_material.set_shader_parameter("scan_%s_%s" % [scan, kind], load(path))
	for kind in ["c", "n"]: # (the steep faces' slabs)
		_material.set_shader_parameter("cliff_%s" % kind,
				load("res://assets/textures/ground/scans/cliff_%s.png" % kind))
	_material.set_shader_parameter("detail_on", true)
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--voxel-debug="):
			_material.set_shader_parameter("debug_mode", int(arg.trim_prefix("--voxel-debug=")))


## G digs a hole where the camera looks, H fills one (a sphere of `_dig_radius` m, up to 14 m away).
func _unhandled_input(event: InputEvent) -> void:
	if not ground_ready or not event is InputEventKey or not event.pressed or event.echo:
		return
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return
	var from := camera.global_position
	var ahead := -camera.global_basis.z
	if event.keycode == KEY_G:
		edit(from, ahead, false)
	elif event.keycode == KEY_H:
		edit(from, ahead, true)


## Digs (or, with `add`, fills) a sphere where a ray from `from` along `ahead` (world space) meets
## the ground. Returns the world position it worked at, or INF when nothing was hit.
func edit(from: Vector3, ahead: Vector3, add: bool) -> Vector3:
	var tool: Object = _terrain.call("get_voxel_tool")
	var local_from: Vector3 = _terrain.to_local(from)
	var local_ahead: Vector3 = (_terrain.global_transform.basis.inverse() * ahead).normalized()
	var at := _march(tool, local_from, local_ahead, 14.0)
	if at == Vector3.INF:
		return Vector3.INF
	tool.set("mode", 0 if add else 1) # VoxelTool.MODE_ADD / MODE_REMOVE
	tool.call("do_sphere", at, _dig_radius)
	return _terrain.to_global(at)


## The first point along a ray (terrain space) where the voxel value turns negative (solid), found
## by stepping and then halving: VoxelTool.raycast returned nothing in the lab (not looked into).
func _march(tool: Object, origin: Vector3, direction: Vector3, reach: float) -> Vector3:
	var previous := 0.0
	var step := 0.4
	var travelled := step
	while travelled <= reach:
		var value: float = tool.call("get_voxel_f_interpolated", origin + direction * travelled)
		if value < 0.0:
			var low := previous
			var high := travelled
			for i in 10:
				var middle := (low + high) * 0.5
				if float(tool.call("get_voxel_f_interpolated", origin + direction * middle)) < 0.0:
					high = middle
				else:
					low = middle
			return origin + direction * high
		previous = travelled
		travelled += step
	return Vector3.INF


## A dig under the player's feet, then a look at whether they fell in (the lab's --voxel-dig-test).
func _dig_test_step() -> void:
	_dig_frame += 1
	if _dig_frame == 120:
		_dig_y = _player.global_position.y
		var worked := edit(_player.global_position + Vector3(0, 6.0, 0), Vector3.DOWN, false)
		var where := "nothing"
		if worked != Vector3.INF:
			where = str(worked.snapped(Vector3.ONE * 0.1))
		print("VOXEL dig test: dug at ", where)
	elif _dig_frame == 420:
		print("VOXEL dig test: the player's height ", snappedf(_dig_y, 0.01), " -> ",
				snappedf(_player.global_position.y, 0.01), " m, on floor ",
				(_player as CharacterBody3D).is_on_floor() if _player is CharacterBody3D else "?")
		get_tree().quit()


## --voxel-surface-check: how far the voxel collision is from the planet's exact height (what the plants stand on), over
## random spots round the player: SURFACE_CHECK mean / max of the difference in metres.
func _surface_check() -> void:
	var frame := _planet.frame
	var anchor := Vector3(frame.anchor[0], frame.anchor[1], frame.anchor[2])
	var inverse: Basis = (frame.rot as Basis).inverse()
	var space := get_world_3d().direct_space_state
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var radius := _planet.settings.radius
	var sum := 0.0
	var worst := 0.0
	var count := 0
	var skipped := 0
	for i in 400:
		var spot := _player.global_position + Vector3(rng.randf_range(-40, 40), 0, rng.randf_range(-40, 40))
		var query := PhysicsRayQueryParameters3D.create(spot + Vector3(0, 80, 0), spot + Vector3(0, -80, 0), 1)
		var hit := space.intersect_ray(query)
		if hit.is_empty() or hit.get("collider") != _terrain: # (a plant or a rock: not the ground)
			skipped += 1
			continue
		var planet_point: Vector3 = inverse * ((hit["position"] as Vector3) - frame.origin_w) + anchor
		var dir := planet_point.normalized()
		var exact: float = radius + _planet.noise.height(dir.x, dir.y, dir.z)
		var gap := absf(planet_point.length() - exact)
		sum += gap
		worst = maxf(worst, gap)
		count += 1
	print("SURFACE_CHECK spots ", count, " (not the terrain: ", skipped, ") mean ", snappedf(sum / maxf(count, 1), 0.001), " max ", snappedf(worst, 0.001))
	get_tree().quit()


## --voxel-find: places worth a picture (a river on land, a steep slope above the sea), as directions for --dir=
func _find_places() -> void:
	var noise: PlanetNoise = _planet.noise
	var settings: PlanetSettings = _planet.settings
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var n := 80000
	var step := 3.0 / settings.radius
	var dirs := PackedVector3Array()
	for i in n:
		var d := Vector3(rng.randfn(), rng.randfn(), rng.randfn()).normalized()
		var t1 := d.cross(Vector3.UP if absf(d.y) < 0.9 else Vector3.RIGHT).normalized()
		dirs.append(d)
		dirs.append((d + t1 * step).normalized())
		dirs.append((d + d.cross(t1) * step).normalized())
	var h := noise.heights_of(dirs)
	var waters := noise.get_native().river_waters(dirs) as PackedVector3Array
	var rivers := []
	var slopes := []
	var coasts := []
	for i in n:
		var h0 := h[i * 3]
		if h0 < settings.sea_level + 3.0:
			if h0 < settings.sea_level - 3.0 and h0 > settings.sea_level - 12.0 and coasts.size() < 3:
				coasts.append(dirs[i * 3])
			continue
		var slope := rad_to_deg(atan(sqrt(pow(h[i * 3 + 1] - h0, 2) + pow(h[i * 3 + 2] - h0, 2)) / 3.0))
		slopes.append([slope, dirs[i * 3], h0])
		var surface := waters[i * 3].x
		if surface > settings.sea_level and h0 < surface - 0.02 and surface - h0 < 4.0: # (a river that sits on its valley, not a sheet hanging over a gorge)
			rivers.append([surface - h0, dirs[i * 3], h0])
	slopes.sort_custom(func(a, b): return a[0] > b[0])
	rivers.sort_custom(func(a, b): return a[0] > b[0])
	print("FIND land points ", slopes.size(), " wet river points ", rivers.size())
	for coast in coasts:
		print("FIND shallow sea --dir=", (coast as Vector3).snapped(Vector3.ONE * 1.0e-7))
	for k in mini(4, slopes.size()):
		print("FIND slope ", snappedf(slopes[k][0], 0.1), " deg  --dir=", (slopes[k][1] as Vector3).snapped(Vector3.ONE * 1.0e-7), " ground ", snappedf(slopes[k][2], 0.1))
	for k in mini(4, rivers.size()):
		print("FIND river water ", snappedf(rivers[k][0], 0.01), " m over the bed  --dir=", (rivers[k][1] as Vector3).snapped(Vector3.ONE * 1.0e-7), " ground ", snappedf(rivers[k][2], 0.1))
	if not rivers.is_empty(): # the wet ground round the best one: a grid of 6 m over 600 m, the middle of what is wet
		var at: Vector3 = rivers[0][1]
		var east := at.cross(Vector3.UP if absf(at.y) < 0.9 else Vector3.RIGHT).normalized()
		var north := at.cross(east)
		var grid := PackedVector3Array()
		for gz in range(-50, 51):
			for gx in range(-50, 51):
				grid.append((at + (east * gx + north * gz) * (6.0 / settings.radius)).normalized())
		var grid_heights := noise.heights_of(grid)
		var grid_waters := noise.get_native().river_waters(grid) as PackedVector3Array
		var wet := 0
		var sum := Vector3.ZERO
		for k in grid.size():
			if grid_waters[k].x > settings.sea_level and grid_heights[k] < grid_waters[k].x - 0.3:
				wet += 1
				sum += grid[k]
		print("FIND river patch: ", wet, " wet spots of ", grid.size(), " (6 m apart); middle --dir=", (sum / maxf(wet, 1)).normalized().snapped(Vector3.ONE * 1.0e-7))
	get_tree().quit()
