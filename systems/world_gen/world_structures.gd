class_name WorldStructures
extends RefCounted
## The things people left in the world: cabins, ruined towers (with climbing holds on one face),
## stone circles and camp fires. `plan()` decides, from the tile alone, whether the tile has one and
## where, so WorldScatter can keep trees and rocks out of its way; `build()` makes it. Everything
## sits at least 16 m inside its tile, so it never reaches over a tile border.

enum Kind { CABIN, TOWER, CIRCLE, CAMP }

const CHANCE := 0.1 ## of a tile with a structure
const MARGIN := 16.0
const WOOD := Color(0.45, 0.31, 0.19)
const WOOD_DARK := Color(0.3, 0.2, 0.13)
const ROOF := Color(0.55, 0.22, 0.16)
const STONE := Color(0.52, 0.5, 0.47)
const STONE_DARK := Color(0.38, 0.37, 0.36)

var _builder := MeshBuilder.new()
var _boxes: Array = [] # [Transform3D (chunk local), Vector3 size] for colliders


## {} or {kind, position (world), radius, yaw}.
static func plan(coord: Vector2i, noise: TerrainNoise) -> Dictionary:
	var settings := noise.settings
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(Vector3i(settings.world_seed + 77, coord.x, coord.y))
	if rng.randf() > CHANCE:
		return {}
	var origin := Vector2(coord) * settings.chunk_size
	for attempt in 8:
		var x := origin.x + rng.randf_range(MARGIN, settings.chunk_size - MARGIN)
		var z := origin.y + rng.randf_range(MARGIN, settings.chunk_size - MARGIN)
		var ground := noise.height(x, z)
		if ground < noise.water_level(x, z) + 1.5 or Vector2(x, z).length() < 20.0:
			continue
		var flat := true # the whole footprint is level (no cabin hanging off a slope)
		for offset: Vector2 in [Vector2(7, 0), Vector2(-7, 0), Vector2(0, 7), Vector2(0, -7)]:
			if absf(noise.height(x + offset.x, z + offset.y) - ground) > 1.2:
				flat = false
		if not flat:
			continue
		var biome := noise.biome(x, z, ground, noise.slope(x, z))
		var kind := Kind.CIRCLE
		var pick := rng.randf()
		match biome:
			TerrainNoise.Biome.FOREST:
				kind = Kind.CABIN if pick < 0.45 else Kind.CAMP if pick < 0.8 else Kind.TOWER
			TerrainNoise.Biome.MEADOW:
				kind = Kind.CABIN if pick < 0.35 else Kind.TOWER if pick < 0.6 else Kind.CIRCLE
			TerrainNoise.Biome.ROCKY:
				kind = Kind.CIRCLE if pick < 0.5 else Kind.TOWER
			TerrainNoise.Biome.BEACH:
				kind = Kind.CAMP
			TerrainNoise.Biome.DESERT:
				kind = Kind.CIRCLE if pick < 0.6 else Kind.TOWER
			_:
				continue
		return {"kind": kind, "position": Vector3(x, ground, z), "radius": 9.0,
				"yaw": snappedf(rng.randf() * TAU, PI * 0.5)}
	return {}


## Adds the structure of `plan` under `chunk` (which sits at its own world position).
func build(chunk: Node3D, plan_data: Dictionary, world_seed: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(Vector3i(world_seed + 5, int((plan_data["position"] as Vector3).x),
			int((plan_data["position"] as Vector3).z)))
	var local: Vector3 = (plan_data["position"] as Vector3) - chunk.position
	var base := Transform3D(Basis(Vector3.UP, plan_data["yaw"] as float), local)
	var node := Node3D.new()
	node.transform = base
	chunk.add_child(node)
	match plan_data["kind"]:
		Kind.CABIN:
			_cabin(rng, node)
		Kind.TOWER:
			_tower(rng, node)
		Kind.CIRCLE:
			_circle(rng)
		Kind.CAMP:
			_camp(rng, node)
	var instance := MeshInstance3D.new()
	instance.mesh = _builder.commit()
	instance.material_override = FloraMeshes.structure_material()
	node.add_child(instance)
	var body := StaticBody3D.new()
	body.collision_layer = 1
	node.add_child(body)
	for entry: Array in _boxes:
		var shape := BoxShape3D.new()
		shape.size = entry[1]
		var collision := CollisionShape3D.new()
		collision.shape = shape
		collision.transform = entry[0]
		body.add_child(collision)


## A solid box: mesh and collider (centre, size, yaw about the structure's up axis, tilt about X).
func _box(center: Vector3, size: Vector3, color: Color, yaw := 0.0, tilt := 0.0,
		collide := true) -> void:
	var transform := Transform3D(Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, tilt), center)
	_builder.xf = transform
	var h := size * 0.5
	var c := Color(color.r, color.g, color.b, 0.0)
	var dark := c.darkened(0.2)
	var corners := [Vector3(-h.x, -h.y, -h.z), Vector3(h.x, -h.y, -h.z), Vector3(h.x, h.y, -h.z),
			Vector3(-h.x, h.y, -h.z), Vector3(-h.x, -h.y, h.z), Vector3(h.x, -h.y, h.z),
			Vector3(h.x, h.y, h.z), Vector3(-h.x, h.y, h.z)]
	# counter clockwise seen from outside: front (+z), back, left, right, top, bottom
	_builder.add_quad(corners[4], corners[5], corners[6], corners[7], c)
	_builder.add_quad(corners[1], corners[0], corners[3], corners[2], c.darkened(0.1))
	_builder.add_quad(corners[0], corners[4], corners[7], corners[3], dark)
	_builder.add_quad(corners[5], corners[1], corners[2], corners[6], dark)
	_builder.add_quad(corners[7], corners[6], corners[2], corners[3], c.lightened(0.08))
	_builder.add_quad(corners[0], corners[1], corners[5], corners[4], dark)
	_builder.xf = Transform3D.IDENTITY
	if collide:
		_boxes.append([transform, size])


func _cabin(rng: RandomNumberGenerator, node: Node3D) -> void:
	var width := rng.randf_range(5.5, 7.0)
	var depth := rng.randf_range(4.0, 5.0)
	var wall := 2.7
	var thick := 0.28
	var door := 1.2
	_box(Vector3(0.0, 0.05, 0.0), Vector3(width, 0.3, depth), WOOD_DARK)
	_box(Vector3(0.0, wall * 0.5 + 0.2, -depth * 0.5), Vector3(width, wall, thick), WOOD)
	_box(Vector3(-width * 0.5, wall * 0.5 + 0.2, 0.0), Vector3(thick, wall, depth), WOOD)
	_box(Vector3(width * 0.5, wall * 0.5 + 0.2, 0.0), Vector3(thick, wall, depth), WOOD)
	var side := (width - door) * 0.5
	var post := (door + side) * 0.5
	_box(Vector3(-post, wall * 0.5 + 0.2, depth * 0.5), Vector3(side, wall, thick), WOOD)
	_box(Vector3(post, wall * 0.5 + 0.2, depth * 0.5), Vector3(side, wall, thick), WOOD)
	_box(Vector3(0.0, wall - 0.35 + 0.2, depth * 0.5), Vector3(door, 0.7, thick), WOOD)
	# the roof: two slabs leaning on a ridge, and the triangle gables under them
	var pitch := 0.62
	var slab := (width * 0.5 + 0.5) / cos(pitch)
	var ridge := wall + 0.2 + (width * 0.5) * tan(pitch)
	for sign in [-1.0, 1.0]:
		_roof_slab(Vector3(sign * (width * 0.25 + 0.1), wall + 0.2 + width * 0.25 * tan(pitch), 0.0),
				Vector3(slab, 0.2, depth + 0.8), -sign * pitch)
	for end in [-1.0, 1.0]:
		var z: float = end * (depth * 0.5)
		_builder.add_tri(Vector3(-width * 0.5, wall + 0.2, z), Vector3(width * 0.5, wall + 0.2, z),
				Vector3(0.0, ridge, z), Color(WOOD.r, WOOD.g, WOOD.b, 0.0) if end > 0.0
				else Color(WOOD.r, WOOD.g, WOOD.b, 0.0).darkened(0.1))
		_builder.add_tri(Vector3(-width * 0.5, wall + 0.2, z), Vector3(0.0, ridge, z),
				Vector3(width * 0.5, wall + 0.2, z), Color(WOOD_DARK.r, WOOD_DARK.g, WOOD_DARK.b, 0.0))
	_box(Vector3(width * 0.3, ridge + 0.4, -depth * 0.25), Vector3(0.7, 1.6, 0.7), STONE_DARK)
	# inside: a bed, a table with a stool, and a hearth under the chimney that lights the room
	var cloth := Color(0.55, 0.62, 0.7)
	_box(Vector3(-width * 0.5 + 1.0, 0.55, -depth * 0.5 + 1.1), Vector3(1.0, 0.4, 2.0), WOOD_DARK)
	var bedding := Vector3(-width * 0.5 + 1.0, 0.8, -depth * 0.5 + 1.1)
	_box(bedding, Vector3(0.95, 0.15, 1.9), cloth, 0.0, 0.0, false)
	_box(Vector3(-0.4, 0.75, 0.1), Vector3(1.3, 0.1, 0.8), WOOD)
	_box(Vector3(-0.4, 0.4, 0.1), Vector3(0.2, 0.7, 0.6), WOOD_DARK)
	_box(Vector3(0.7, 0.45, 0.5), Vector3(0.45, 0.35, 0.45), WOOD_DARK)
	var hearth := Campfire.new()
	hearth.position = Vector3(width * 0.3, 0.35, -depth * 0.25 + 0.7)
	hearth.scale = Vector3.ONE * 0.6
	hearth.add_to_group(&"campfire")
	node.add_child(hearth)


func _roof_slab(center: Vector3, size: Vector3, roll: float) -> void:
	# a slab tilted about the Z axis (ridge direction): built from a box rotated by hand
	var basis := Basis(Vector3.BACK, roll)
	var transform := Transform3D(basis, center)
	_builder.xf = transform
	var h := size * 0.5
	var c := Color(ROOF.r, ROOF.g, ROOF.b, 0.0)
	var v := [Vector3(-h.x, -h.y, -h.z), Vector3(h.x, -h.y, -h.z), Vector3(h.x, h.y, -h.z),
			Vector3(-h.x, h.y, -h.z), Vector3(-h.x, -h.y, h.z), Vector3(h.x, -h.y, h.z),
			Vector3(h.x, h.y, h.z), Vector3(-h.x, h.y, h.z)]
	_builder.add_quad(v[4], v[5], v[6], v[7], c.darkened(0.1))
	_builder.add_quad(v[1], v[0], v[3], v[2], c.darkened(0.1))
	_builder.add_quad(v[0], v[4], v[7], v[3], c.darkened(0.2))
	_builder.add_quad(v[5], v[1], v[2], v[6], c.darkened(0.2))
	_builder.add_quad(v[7], v[6], v[2], v[3], c.lightened(0.06))
	_builder.add_quad(v[0], v[1], v[5], v[4], c.darkened(0.3))
	_builder.xf = Transform3D.IDENTITY
	_boxes.append([transform, size])


func _tower(rng: RandomNumberGenerator, node: Node3D) -> void:
	var radius := rng.randf_range(2.8, 3.4)
	var sides := 8
	var chord := 2.0 * radius * sin(PI / float(sides))
	var climb_side := rng.randi() % sides
	for side in sides:
		var angle := TAU * float(side) / float(sides)
		var height := rng.randf_range(9.0, 13.0) - float(rng.randi() % 3) * 1.7 # jagged top
		if side == climb_side:
			height = 12.0 # the climbable wall is tall and whole
		var out := Vector3(sin(angle), 0.0, cos(angle))
		var center := out * radius + Vector3(0.0, height * 0.5 - 0.3, 0.0)
		if side == (climb_side + 4) % sides: # a doorway on the far side: wall only above it
			_box(Vector3(out.x * radius, (height + 2.2) * 0.5 - 0.3, out.z * radius),
					Vector3(chord, height - 2.2, 0.7), STONE, angle)
			continue
		_box(center, Vector3(chord + 0.05, height, 0.7), STONE if side % 2 == 0 else STONE_DARK, angle)
	_box(Vector3(0.0, -0.1, 0.0), Vector3(radius * 2.0, 0.4, radius * 2.0), STONE_DARK, 0.0, 0.0,
			false)
	var holds := ClimbHoldWall.new()
	holds.columns = 5
	holds.rows = 30
	holds.spacing = Vector2(0.45, 0.4)
	var angle := TAU * float(climb_side) / float(sides)
	holds.position = Vector3(sin(angle), 0.0, cos(angle)) * (radius + 0.35) + Vector3(0.0, 0.6, 0.0)
	holds.rotation.y = angle
	node.add_child(holds)


func _circle(rng: RandomNumberGenerator) -> void:
	var count := rng.randi_range(7, 10)
	for index in count:
		var angle := TAU * float(index) / float(count)
		var height := rng.randf_range(2.4, 4.0)
		var width := rng.randf_range(0.9, 1.4)
		_box(Vector3(sin(angle) * 5.0, height * 0.5 - 0.3, cos(angle) * 5.0),
				Vector3(width, height, rng.randf_range(0.5, 0.8)),
				STONE if index % 2 == 0 else STONE_DARK, angle + rng.randf_range(-0.12, 0.12))
	_box(Vector3(0.0, 0.2, 0.0), Vector3(1.8, 0.9, 1.1), STONE_DARK, rng.randf() * TAU)


func _camp(rng: RandomNumberGenerator, node: Node3D) -> void:
	for index in 8:
		var angle := TAU * float(index) / 8.0
		_builder.xf = Transform3D(Basis.IDENTITY, Vector3(sin(angle) * 0.85, 0.12, cos(angle) * 0.85))
		_builder.add_blob(Vector3.ZERO, Vector3(0.3, 0.22, 0.28), Color(0.3, 0.3, 0.3, 0.0),
				Color(0.5, 0.5, 0.48, 0.0), rng, 0.3)
	_builder.xf = Transform3D.IDENTITY
	for index in 3:
		var angle := float(index) * TAU / 3.0 + 0.4
		_builder.xf = Transform3D(Basis(Vector3.UP, angle) * Basis(Vector3.BACK, PI * 0.5),
				Vector3(0.0, 0.18, 0.0))
		_builder.add_frustum(Vector3.ZERO, 1.3, 0.1, 0.09, 5, Color(0.25, 0.17, 0.1, 0.0),
				Color(0.3, 0.2, 0.12, 0.0))
	_builder.xf = Transform3D.IDENTITY
	# a log to sit on, and a tent
	_box(Vector3(2.2, 0.25, 0.4), Vector3(2.2, 0.45, 0.5), WOOD_DARK, 0.4, 0.0, true)
	_builder.xf = Transform3D(Basis(Vector3.UP, 0.3), Vector3(-3.4, 0.0, -1.6))
	var cloth := Color(0.72, 0.62, 0.4, 0.0)
	_builder.add_tri(Vector3(-1.2, 0.0, 1.4), Vector3(1.2, 0.0, 1.4), Vector3(0.0, 1.5, 1.4), cloth)
	_builder.add_tri(Vector3(-1.2, 0.0, -1.4), Vector3(0.0, 1.5, -1.4), Vector3(1.2, 0.0, -1.4),
			cloth.darkened(0.1))
	_builder.add_quad(Vector3(-1.2, 0.0, 1.4), Vector3(0.0, 1.5, 1.4), Vector3(0.0, 1.5, -1.4),
			Vector3(-1.2, 0.0, -1.4), cloth.darkened(0.15))
	_builder.add_quad(Vector3(1.2, 0.0, 1.4), Vector3(1.2, 0.0, -1.4), Vector3(0.0, 1.5, -1.4),
			Vector3(0.0, 1.5, 1.4), cloth.darkened(0.05))
	_builder.xf = Transform3D.IDENTITY
	var fire := Campfire.new()
	fire.position = Vector3(0.0, 0.0, 0.0)
	fire.add_to_group(&"campfire")
	node.add_child(fire)
