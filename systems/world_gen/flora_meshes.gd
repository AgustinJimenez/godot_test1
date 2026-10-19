class_name FloraMeshes
extends RefCounted
## The scenery that is not a plant: rocks, stumps, fallen logs and rock spires, drawn in code as
## low-poly meshes. Plants are species made per world (see flora/species_generator.gd). Each kind
## comes in a few variants (a different random seed, so no two neighbours match) and is built once
## and shared. Vertex colour alpha = how much a vertex sways in the wind.

## The numbers stay what they were when plants shared this enum, so the rocks keep their shapes.
enum Kind { ROCK = 5, STUMP = 10, LOG = 14, SPIRE = 15, PEBBLES = 16 }

const VARIANTS := {Kind.ROCK: 6, Kind.STUMP: 2, Kind.LOG: 3, Kind.SPIRE: 3, Kind.PEBBLES: 4}
const BARK := Color(0.33, 0.23, 0.15)
const BARK_DARK := Color(0.22, 0.15, 0.1)

static var _cache: Dictionary = {}
static var _cache_lock := Mutex.new()
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
	return builder.commit()


static func _still(color: Color) -> Color:
	return Color(color.r, color.g, color.b, 0.0)


static func _sway(color: Color, amount: float) -> Color:
	return Color(color.r, color.g, color.b, amount)


static func _rock(builder: MeshBuilder, rng: RandomNumberGenerator, variant: int) -> void:
	var tone := rng.randf_range(0.0, 1.0)
	var stone := Color(0.4, 0.39, 0.38).lerp(Color(0.56, 0.52, 0.47), tone)
	if variant == 5: # a reddish one
		stone = Color(0.52, 0.38, 0.3)
	var low := _still(stone.darkened(0.25))
	var high := _still(stone.lightened(0.1))
	builder.add_blob(Vector3(0.0, 0.25, 0.0), Vector3(1.0, 0.7, 0.85) * rng.randf_range(0.9, 1.15),
			low, high, rng, 0.3)
	if variant % 2 == 1: # a second, smaller stone leaning on it
		builder.add_blob(Vector3(0.7, 0.1, 0.4), Vector3(0.5, 0.4, 0.45), low, high, rng, 0.3)


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
