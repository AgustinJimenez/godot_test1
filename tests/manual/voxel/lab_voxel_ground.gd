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
var _cover: CanvasLayer
var _cover_label: Label
var _map_task := -1
var _map_image: Image
var _map_rows := 0


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
	_planet = planet
	_player = player
	var radius := planet.settings.radius
	# (loaded here, not preloaded: that script extends a voxel class the stock engine lacks, and
	# the lab must still compile there)
	var gen: Object = (load("res://tests/manual/voxel/real_planet_generator.gd") as GDScript).new()
	gen.set("radius", radius)
	gen.set("noise", planet.noise)
	gen.set("lattice", 2)
	gen.set("exact_lods", 1)
	_terrain = ClassDB.instantiate("VoxelLodTerrain")
	_terrain.set("lod_count", 12 if radius > 1.0e6 else 9)
	_terrain.set("generator", gen)
	_terrain.set("mesher", ClassDB.instantiate("VoxelMesherTransvoxel"))
	_terrain.set("view_distance", view)
	_terrain.set("bounds", AABB(Vector3.ONE * -radius * 1.6, Vector3.ONE * radius * 3.2))
	_material = ShaderMaterial.new()
	_material.shader = load("res://shaders/voxel/voxel_ground.gdshader")
	_material.set_shader_parameter("radius", radius)
	_terrain.set("material", _material)
	add_child(_terrain)
	var viewer: Node = ClassDB.instantiate("VoxelViewer")
	viewer.set("view_distance", view)
	viewer.set("requires_collisions", true)
	player.add_child(viewer)
	_follow_frame()
	_player.process_mode = Node.PROCESS_MODE_DISABLED
	_make_cover()
	_start_colour_map()
	print("VOXEL ground on: radius ", radius, " lods ", _terrain.get("lod_count"))


func _physics_process(_delta: float) -> void:
	_frame += 1
	_follow_frame()
	if _frame % 20 == 0:
		_switch_tiles_off()
	_poll_colour_map()
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
	_material.set_shader_parameter("world_to_planet", placed.affine_inverse())


func _switch_tiles_off() -> void:
	for tile: PlanetTile in _planet.surface.tiles.values():
		if tile.ground_instance != null:
			tile.ground_instance.visible = false
		for body in tile.find_children("*", "CollisionObject3D", true, false):
			(body as CollisionObject3D).collision_layer = 0


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
	var width := 2048 if _planet.settings.radius > 1.0e6 else 1024
	_map_image = Image.create(width, width / 2, false, Image.FORMAT_RGB8)
	_map_rows = width / 2
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
		var colours := noise.colours_of(dirs, heights, steeps)
		for x in width:
			_map_image.set_pixel(x, y, colours[x])


func _poll_colour_map() -> void:
	if _map_task < 0 or not WorkerThreadPool.is_task_completed(_map_task):
		return
	WorkerThreadPool.wait_for_task_completion(_map_task)
	_map_task = -1
	_material.set_shader_parameter("colour_map", ImageTexture.create_from_image(_map_image))
	_material.set_shader_parameter("use_map", true)
	print("VOXEL colour map ready (", _map_image.get_width(), " x ", _map_image.get_height(), ")")
