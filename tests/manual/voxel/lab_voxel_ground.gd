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
	print("VOXEL ground on: radius ", radius, " lods ", _terrain.get("lod_count"))


func _physics_process(_delta: float) -> void:
	_frame += 1
	_follow_frame()
	if _frame % 20 == 0:
		_switch_tiles_off()
	if not ground_ready:
		_wait_for_ground(_delta)
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
	_player.global_position = (hit["position"] as Vector3) + Vector3(0, 0.05, 0)
	_player.process_mode = Node.PROCESS_MODE_INHERIT
	print("VOXEL ground ready: the player stands at ",
			_player.global_position.snapped(Vector3.ONE * 0.1))
