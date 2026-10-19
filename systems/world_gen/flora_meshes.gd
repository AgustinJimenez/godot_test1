class_name FloraMeshes
extends RefCounted
## The scenery that is not a plant: rocks, stumps, fallen logs and rock spires, drawn in code as
## low-poly meshes. Plants are species made per world (see flora/species_generator.gd). Each kind
## comes in a few variants (a different random seed, so no two neighbours match) and is built once
## and shared. Vertex colour alpha = how much a vertex sways in the wind.

## The numbers stay what they were when plants shared this enum, so the rocks keep their shapes.
enum Kind { ROCK = 5, STUMP = 10, LOG = 14, SPIRE = 15, PEBBLES = 16, LITTER = 17, TWIGS = 18 }

const VARIANTS := {Kind.ROCK: 6, Kind.STUMP: 2, Kind.LOG: 3, Kind.SPIRE: 3, Kind.PEBBLES: 4, Kind.LITTER: 5, Kind.TWIGS: 4}
const BARK := Color(0.33, 0.23, 0.15)
const BARK_DARK := Color(0.22, 0.15, 0.1)

static var _cache: Dictionary = {}
static var _cache_lock := Mutex.new()
static var fine_trees := false # trees and shrubs in the finer meshes even where `detailed` is off (the middle ground detail)
static var detailed := false # the realistic look wants the finer meshes (set by the world)
static var _material: ShaderMaterial
static var _structure_material: ShaderMaterial


static func material() -> ShaderMaterial:
	if _material == null:
		_material = ShaderMaterial.new()
		_material.shader = preload("res://shaders/world/flora_wind.gdshader")
	return _material


## The same plant shader with board-wood on the browns, for the buildings.
static func structure_material() -> ShaderMaterial:
	if _structure_material == null:
		_structure_material = material().duplicate() as ShaderMaterial
		_structure_material.set_shader_parameter(&"planks", true)
	return _structure_material


static func mesh(kind: Kind, variant: int, detailed := false) -> ArrayMesh:
	var key := kind * 100 + variant + (10000 if detailed else 0)
	_cache_lock.lock()
	if not _cache.has(key):
		_cache[key] = _build(kind, variant, detailed)
	var result: ArrayMesh = _cache[key]
	_cache_lock.unlock()
	return result


static func variant_count(kind: Kind) -> int:
	return VARIANTS[kind]


static func _build(kind: Kind, variant: int, detailed: bool) -> ArrayMesh:
	if ClassDB.class_exists(&"PlantMeshNative"):
		var maker: Object = ClassDB.instantiate(&"PlantMeshNative")
		return PlantMeshes.mesh_from(maker.call(&"scenery", int(kind), variant, detailed))
	var rng := RandomNumberGenerator.new()
	rng.seed = kind * 7919 + variant * 104729 + 17
	var builder := MeshBuilder.new()
	builder.detailed = detailed
	match kind:
		Kind.ROCK:
			_rock(builder, rng, variant)
		Kind.STUMP:
			_stump(builder, rng)
		Kind.LOG:
			_log(builder, rng)
		Kind.SPIRE:
			_spire(builder, rng, variant)
		Kind.PEBBLES:
			_pebbles(builder, rng, variant)
		Kind.LITTER:
			_litter(builder, rng, variant)
		Kind.TWIGS:
			_twigs(builder, rng, variant)
	return builder.commit()


static func _still(color: Color) -> Color:
	return Color(color.r, color.g, color.b, 0.0)


static func _sway(color: Color, amount: float) -> Color:
	return Color(color.r, color.g, color.b, amount)


static func _rock(builder: MeshBuilder, rng: RandomNumberGenerator, variant: int) -> void:
	var tone := rng.randf_range(0.0, 1.0)
	var stone := Color(0.33, 0.32, 0.31).lerp(Color(0.47, 0.44, 0.4), tone)
	if variant == 5: # a reddish one
		stone = Color(0.52, 0.38, 0.3)
	var low := _still(stone.darkened(0.25))
	var high := _still(stone.lightened(0.1))
	builder.add_rock(Vector3(0.0, 0.25, 0.0), Vector3(1.0, 0.85, 0.85) * rng.randf_range(0.9, 1.15),
			low, high, rng, 6 + variant % 3)
	if variant % 2 == 1: # a second, smaller stone leaning on it
		builder.add_rock(Vector3(0.7, 0.1, 0.4), Vector3(0.5, 0.4, 0.45), low, high, rng, 5)


## A few small stones lying together (a hand's width each), pale or dark by variant.
static func _pebbles(builder: MeshBuilder, rng: RandomNumberGenerator, variant: int) -> void:
	var tones := [Color(0.5, 0.48, 0.45), Color(0.38, 0.36, 0.35), Color(0.6, 0.55, 0.47),
			Color(0.45, 0.37, 0.3)]
	var stone: Color = tones[variant % tones.size()]
	for index in 3 + variant % 3:
		var size := rng.randf_range(0.07, 0.17)
		var at := Vector3(rng.randf_range(-0.4, 0.4), size * 0.3, rng.randf_range(-0.4, 0.4))
		var shade := rng.randf_range(0.85, 1.1)
		builder.add_blob(at, Vector3(size, size * 0.6, size * 0.85), _still(stone.darkened(0.2) * shade),
				_still(stone.lightened(0.08) * shade), rng, 0.25)


## Fallen leaves lying flat on the ground, in the colours of a forest floor (greens, ochres, rusts,
## browns by variant), each its own size, turn and tilt, a few overlapping.
static func _litter(builder: MeshBuilder, rng: RandomNumberGenerator, variant: int) -> void:
	var tones := [Color(0.55, 0.36, 0.14), Color(0.42, 0.3, 0.14), Color(0.62, 0.45, 0.16),
			Color(0.34, 0.4, 0.14), Color(0.5, 0.22, 0.1)]
	var tone: Color = tones[variant % tones.size()]
	var shapes := [PlantSpecies.LeafShape.OVAL, PlantSpecies.LeafShape.LOBED, PlantSpecies.LeafShape.HEART,
			PlantSpecies.LeafShape.LANCEOLATE]
	var outline := PlantLeafShapes.outline_for(shapes[variant % shapes.size()], rng.randf_range(1.5, 2.2),
			2, PlantSpecies.LeafEdge.SMOOTH, true)
	for index in 12 + variant * 2:
		var spot := Vector2.from_angle(rng.randf() * TAU) * 0.55 * sqrt(rng.randf())
		var yaw := rng.randf() * TAU
		var axis := Vector3(cos(yaw), rng.randf_range(0.0, 0.18), sin(yaw)).normalized()
		var normal := (Vector3.UP - axis * axis.dot(Vector3.UP)).normalized()
		var shade := rng.randf_range(0.7, 1.15)
		var colour := tone.lerp(Color(0.3, 0.2, 0.1), rng.randf() * 0.5) * shade
		colour.a = 0.0
		PlantLeafShapes.add_leaf(builder, outline, Vector3(spot.x, 0.012 + 0.006 * index, spot.y), axis,
				normal, rng.randf_range(0.11, 0.24), 0.04, 0.05, colour.darkened(0.2), colour, 0.0, 0.0,
				rng.randf_range(0.9, 1.2), Vector2(rng.randf(), rng.randf()))


## Fallen sticks: a few thin branches lying across each other (one forked), dry grey-brown wood.
static func _twigs(builder: MeshBuilder, rng: RandomNumberGenerator, variant: int) -> void:
	var wood := Color(0.36, 0.28, 0.2).lerp(Color(0.5, 0.44, 0.38), float(variant) / 4.0)
	for index in 3 + variant % 3:
		var length := rng.randf_range(0.35, 1.1)
		var radius := rng.randf_range(0.012, 0.03)
		var yaw := rng.randf() * TAU
		var tilt := rng.randf_range(0.0, 0.2)
		var at := Vector3(rng.randf_range(-0.35, 0.35), radius * 0.8 + 0.02 * index, rng.randf_range(-0.35, 0.35))
		# the stick lies along the ground: a frustum turned from standing up to lying down
		var lie := Basis(Vector3.UP, yaw) * Basis(Vector3.BACK, -PI * 0.5 + tilt)
		builder.xf = Transform3D(lie, at)
		var shade := rng.randf_range(0.85, 1.1)
		builder.add_frustum(Vector3.ZERO, length, radius, radius * 0.45, 5, _still(wood.darkened(0.15) * shade),
				_still(wood * shade), rng, 0.08, MeshBuilder.CAP_BOTTOM)
		if index == 0:
			builder.xf = Transform3D(lie * Basis(Vector3.FORWARD, 0.6), at + lie * Vector3(0.0, length * 0.5, 0.0))
			builder.add_frustum(Vector3.ZERO, length * 0.5, radius * 0.6, radius * 0.25, 4,
					_still(wood.darkened(0.1)), _still(wood), rng, 0.08)
	builder.xf = Transform3D.IDENTITY


static func _stump(builder: MeshBuilder, rng: RandomNumberGenerator) -> void:
	var height := rng.randf_range(0.5, 0.9)
	builder.add_frustum(Vector3.ZERO, height, 0.42, 0.34, 7, _still(BARK_DARK), _still(BARK), rng, 0.1,
			MeshBuilder.CAP_TOP)


static func _log(builder: MeshBuilder, rng: RandomNumberGenerator) -> void:
	var length := rng.randf_range(2.5, 4.5)
	var wood := Color(0.4, 0.3, 0.22)
	builder.xf = Transform3D(Basis(Vector3.BACK, PI * 0.5), Vector3(-length * 0.5, 0.3, 0.0))
	builder.add_frustum(Vector3.ZERO, length, 0.3, 0.26, 7, _still(wood), _still(wood.lightened(0.08)),
			rng, 0.06, MeshBuilder.CAP_TOP | MeshBuilder.CAP_BOTTOM)
	builder.xf = Transform3D.IDENTITY


static func _spire(builder: MeshBuilder, rng: RandomNumberGenerator, variant: int) -> void:
	var stone := Color(0.42, 0.4, 0.4).lerp(Color(0.6, 0.55, 0.5), float(variant) / 3.0)
	var height := rng.randf_range(4.0, 8.0)
	builder.add_frustum(Vector3.ZERO, height, rng.randf_range(1.0, 1.6), rng.randf_range(0.1, 0.35), 5,
			_still(stone.darkened(0.25)), _still(stone.lightened(0.1)), rng, 0.22)
	if variant != 1:
		builder.add_frustum(Vector3(1.1, 0.0, 0.5), height * 0.5, 0.8, 0.12, 5,
				_still(stone.darkened(0.2)), _still(stone), rng, 0.2)


## The tufts of short grass for the turf of the ground (PlanetTurf): TURF_VARIANTS arrangements of a dozen separate blades, each a
## narrow card (UV2.y of 8 marks it: the plant shader cuts the blade out of it) at its own place, turn and lean, so no plane or
## line shows. A blade is its own bending link (CUSTOM0.x is its row in the mesh "branches" meta, as for a grown plant) so that the
## walker can push the tufts nearby (PlanetSway). Built once.
const TURF_VARIANTS := 3
const TURF_BLADES := 12
static var _turf: Array[ArrayMesh] = []


static func turf_tuft(variant: int) -> ArrayMesh:
	if _turf.is_empty():
		for index in TURF_VARIANTS:
			_turf.append(_make_tuft(index))
	return _turf[variant % TURF_VARIANTS]


static func _make_tuft(variant: int) -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7919 * (variant + 1)
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var uvs := PackedVector2Array()
	var uv2s := PackedVector2Array()
	var links := PackedFloat32Array()
	var table := PackedFloat32Array([0, 0, 0, 0, 0, 0, 0, 0, 0, 0]) # the root (the ground): never moves
	for blade in TURF_BLADES:
		# at its own place (within a hand breadth, more of them near the middle), turned any way, leaning out a little
		var around := rng.randf() * TAU
		var reach := 0.14 * sqrt(rng.randf())
		var root := Vector3(cos(around) * reach, 0.0, sin(around) * reach)
		var yaw := rng.randf() * TAU
		var lean_way := around + rng.randf_range(-0.8, 0.8)
		var lean := rng.randf_range(0.0, 0.42)
		var tall := rng.randf_range(0.14, 0.34)
		var wide := rng.randf_range(0.03, 0.055)
		var up := (Vector3.UP * cos(lean) + Vector3(cos(lean_way), 0.0, sin(lean_way)) * sin(lean)).normalized()
		var across := Vector3(cos(yaw), 0.0, sin(yaw))
		across = (across - up * across.dot(up)).normalized()
		var tip := root + up * tall
		table.append_array(PackedFloat32Array([0, 9, root.x, root.y, root.z, tip.x, tip.y, tip.z, 0.01, tall]))
		var id := float(blade + 1)
		var dice := rng.randf()
		var corners := [root - across * wide * 0.5, root + across * wide * 0.5, tip + across * wide * 0.5, tip - across * wide * 0.5]
		var corner_uv := [Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)]
		for index in [0, 1, 2, 0, 2, 3]:
			vertices.append(corners[index])
			normals.append(Vector3.UP)
			colors.append(Color(0.22, 0.34, 0.12, 0.0 if index < 2 else 0.8)) # (alpha: how much the wind moves it)
			uvs.append(corner_uv[index])
			uv2s.append(Vector2(dice, 8.0))
			links.append(id)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_TEX_UV2] = uv2s
	arrays[Mesh.ARRAY_CUSTOM0] = links
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {}, Mesh.ARRAY_CUSTOM_R_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT)
	mesh.set_meta(&"branches", table)
	return mesh
