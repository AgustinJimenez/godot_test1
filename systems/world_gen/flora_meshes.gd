class_name FloraMeshes
extends RefCounted
## Every plant and rock the world scatters, drawn in code as low-poly meshes. Each kind comes in a
## few variants (a different random seed, so no two neighbours match) and is built once and shared.
## Vertex colour alpha = how much a vertex sways in the wind.

enum Kind {
	PINE, OAK, BIRCH, DEAD_TREE, BUSH, ROCK, GRASS, FLOWER, CACTUS, REED, STUMP, PALM, FERN,
	MUSHROOM, LOG, SPIRE, TALL_GRASS, FAR_PINE, FAR_OAK,
}

const VARIANTS := {
	Kind.PINE: 6, Kind.OAK: 4, Kind.BIRCH: 3, Kind.DEAD_TREE: 3, Kind.BUSH: 3, Kind.ROCK: 6,
	Kind.GRASS: 3, Kind.FLOWER: 5, Kind.CACTUS: 2, Kind.REED: 2, Kind.STUMP: 2, Kind.PALM: 3,
	Kind.FERN: 3, Kind.MUSHROOM: 3, Kind.LOG: 3, Kind.SPIRE: 3, Kind.TALL_GRASS: 3,
	Kind.FAR_PINE: 2, Kind.FAR_OAK: 2,
}
const BARK := Color(0.33, 0.23, 0.15)
const BARK_DARK := Color(0.22, 0.15, 0.1)
const BIRCH_BARK := Color(0.86, 0.85, 0.8)

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


## Rough size of a kind (for colliders): radius and height in metres at scale 1.
static func footprint(kind: Kind) -> Vector2:
	match kind:
		Kind.PINE, Kind.OAK, Kind.BIRCH, Kind.DEAD_TREE, Kind.STUMP, Kind.PALM:
			return Vector2(0.32, 3.0)
		Kind.CACTUS:
			return Vector2(0.4, 2.5)
		_:
			return Vector2(0.5, 1.0)


static func _build(kind: Kind, variant: int, detailed: bool) -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = kind * 7919 + variant * 104729 + 17
	var builder := MeshBuilder.new()
	builder.detailed = detailed
	match kind:
		Kind.PINE:
			_pine(builder, rng, variant)
		Kind.OAK:
			_oak(builder, rng, variant)
		Kind.BIRCH:
			_birch(builder, rng, variant)
		Kind.DEAD_TREE:
			_dead_tree(builder, rng)
		Kind.BUSH:
			_bush(builder, rng, variant)
		Kind.ROCK:
			_rock(builder, rng, variant)
		Kind.GRASS:
			_grass(builder, rng, variant)
		Kind.FLOWER:
			_flower(builder, rng, variant)
		Kind.CACTUS:
			_cactus(builder, rng)
		Kind.REED:
			_reed(builder, rng)
		Kind.STUMP:
			_stump(builder, rng)
		Kind.PALM:
			_palm(builder, rng)
		Kind.FERN:
			_fern(builder, rng)
		Kind.MUSHROOM:
			_mushroom(builder, rng, variant)
		Kind.LOG:
			_log(builder, rng)
		Kind.SPIRE:
			_spire(builder, rng, variant)
		Kind.TALL_GRASS:
			_tall_grass(builder, rng, variant)
		Kind.FAR_PINE:
			_far_pine(builder, rng, variant)
		Kind.FAR_OAK:
			_far_oak(builder, rng, variant)
	return builder.commit()


static func _still(color: Color) -> Color:
	return Color(color.r, color.g, color.b, 0.0)


static func _sway(color: Color, amount: float) -> Color:
	return Color(color.r, color.g, color.b, amount)


static func _pine(builder: MeshBuilder, rng: RandomNumberGenerator, variant: int) -> void:
	var height := rng.randf_range(7.0, 11.0)
	var trunk := height * 0.22
	builder.add_frustum(Vector3.ZERO, trunk * 1.5, 0.3, 0.16, 6, _still(BARK_DARK), _still(BARK),
			rng, 0.08)
	var tiers := 4 + variant % 2
	var green := Color(0.13, 0.33, 0.2).lerp(Color(0.2, 0.4, 0.2), rng.randf())
	var snowy := variant >= 4 # the cold biome's pines wear snow
	for tier in tiers:
		var along := float(tier) / float(tiers)
		var base_y := trunk * 0.8 + along * (height - trunk) * 0.78
		var radius := lerpf(2.3, 0.9, along) * rng.randf_range(0.9, 1.1)
		var tier_height := (height - base_y) * 0.42
		builder.add_frustum(Vector3(0.0, base_y, 0.0), tier_height, radius, 0.0, 7,
				_sway(green.darkened(0.12 + along * 0.0), 0.35),
				_sway(Color(0.93, 0.95, 0.98) if snowy else green.lightened(0.12 * along + 0.05), 1.0),
				rng, 0.16, MeshBuilder.CAP_BOTTOM)


static func _oak(builder: MeshBuilder, rng: RandomNumberGenerator, variant: int) -> void:
	var trunk := rng.randf_range(2.2, 3.2)
	builder.add_frustum(Vector3.ZERO, trunk, 0.38, 0.24, 7, _still(BARK_DARK), _still(BARK), rng, 0.1)
	var leaf := Color(0.26, 0.5, 0.18)
	if variant == 3: # one autumn variant
		leaf = Color(0.8, 0.4, 0.12)
	elif variant == 2:
		leaf = Color(0.38, 0.55, 0.15)
	var crown := rng.randf_range(1.9, 2.5)
	for index in rng.randi_range(3, 5):
		var spot := Vector3(rng.randf_range(-1.3, 1.3), trunk + rng.randf_range(0.2, 1.8),
				rng.randf_range(-1.3, 1.3))
		var size := crown * rng.randf_range(0.7, 1.05)
		builder.add_blob(spot, Vector3(size, size * 0.85, size), _sway(leaf.darkened(0.25), 0.4),
				_sway(leaf.lightened(0.12), 1.0), rng, 0.22)
		if builder.detailed:
			builder.add_leaf_cards(spot, Vector3(size, size * 0.85, size), 55, 0.5,
					_sway(leaf.darkened(0.15), 0.8), _sway(leaf.lightened(0.25), 1.0), rng)


static func _birch(builder: MeshBuilder, rng: RandomNumberGenerator, variant: int) -> void:
	var trunk := rng.randf_range(3.4, 4.8)
	builder.add_frustum(Vector3.ZERO, trunk, 0.2, 0.1, 6, _still(BIRCH_BARK), _still(BIRCH_BARK),
			rng, 0.05)
	for mark in 4: # the dark patches on the bark
		builder.add_frustum(Vector3(0.0, 0.5 + float(mark) * 0.8, 0.0), 0.12, 0.205 - float(mark) * 0.018,
				0.2 - float(mark) * 0.018, 6, _still(Color(0.12, 0.12, 0.1)), _still(Color(0.12, 0.12, 0.1)))
	var leaf := Color(0.55, 0.66, 0.2) if variant != 2 else Color(0.85, 0.7, 0.2)
	for index in 3:
		var spot := Vector3(rng.randf_range(-0.7, 0.7), trunk + rng.randf_range(-0.4, 1.0),
				rng.randf_range(-0.7, 0.7))
		builder.add_blob(spot, Vector3(1.3, 1.1, 1.3), _sway(leaf.darkened(0.2), 0.4),
				_sway(leaf.lightened(0.1), 1.0), rng, 0.2)
		if builder.detailed:
			builder.add_leaf_cards(spot, Vector3(1.3, 1.1, 1.3), 36, 0.4,
					_sway(leaf.darkened(0.1), 0.8), _sway(leaf.lightened(0.2), 1.0), rng)


static func _dead_tree(builder: MeshBuilder, rng: RandomNumberGenerator) -> void:
	var height := rng.randf_range(3.5, 5.5)
	var wood := Color(0.36, 0.31, 0.27)
	builder.add_frustum(Vector3.ZERO, height, 0.3, 0.08, 6, _still(wood.darkened(0.2)), _still(wood),
			rng, 0.12)
	for branch in rng.randi_range(3, 5):
		builder.xf = Transform3D(Basis(Vector3.UP, rng.randf() * TAU)
				* Basis(Vector3.RIGHT, rng.randf_range(0.7, 1.2)),
				Vector3(0.0, height * rng.randf_range(0.45, 0.85), 0.0))
		builder.add_frustum(Vector3.ZERO, rng.randf_range(1.0, 1.9), 0.09, 0.02, 4,
				_still(wood.darkened(0.1)), _still(wood.lightened(0.1)))
	builder.xf = Transform3D.IDENTITY


static func _bush(builder: MeshBuilder, rng: RandomNumberGenerator, variant: int) -> void:
	var leaf := Color(0.28, 0.5, 0.2).lerp(Color(0.4, 0.55, 0.15), float(variant) / 3.0)
	for index in rng.randi_range(2, 3):
		var size := rng.randf_range(0.5, 0.8)
		builder.add_blob(Vector3(rng.randf_range(-0.4, 0.4), size * 0.55, rng.randf_range(-0.4, 0.4)),
				Vector3(size, size * 0.8, size), _sway(leaf.darkened(0.3), 0.3),
				_sway(leaf.lightened(0.1), 1.0), rng, 0.25)


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


static func _grass(builder: MeshBuilder, rng: RandomNumberGenerator, variant: int) -> void:
	var base := Color(0.26, 0.46, 0.16)
	var tip := Color(0.5, 0.68, 0.22).lerp(Color(0.7, 0.72, 0.3), float(variant) / 3.0)
	if builder.detailed:
		_grass_detailed(builder, rng, base, tip)
		return
	for blade in 6:
		var angle := rng.randf() * TAU
		var lean := rng.randf_range(0.1, 0.5)
		var height := rng.randf_range(0.35, 0.75)
		var root := Vector3(rng.randf_range(-0.12, 0.12), 0.0, rng.randf_range(-0.12, 0.12))
		var across := Vector3(cos(angle), 0.0, sin(angle)) * 0.045
		var top := root + Vector3(sin(angle) * lean * height, height, -cos(angle) * lean * height)
		builder.add_tri(root - across, root + across, top, _sway(base, 0.0), _sway(base, 0.0),
				_sway(tip, 1.0))


static func _flower(builder: MeshBuilder, rng: RandomNumberGenerator, variant: int) -> void:
	var petals := [Color(0.97, 0.97, 0.9), Color(0.98, 0.84, 0.2), Color(0.7, 0.45, 0.85),
			Color(0.9, 0.25, 0.3), Color(0.35, 0.55, 0.95)]
	var color: Color = petals[variant % petals.size()]
	var height := rng.randf_range(0.35, 0.6)
	var stem := Color(0.25, 0.5, 0.18)
	builder.add_frustum(Vector3.ZERO, height, 0.018, 0.012, 3, _sway(stem, 0.0), _sway(stem, 0.7))
	for petal in 5:
		var angle := TAU * float(petal) / 5.0
		var out := Vector3(cos(angle), 0.0, sin(angle))
		var side := Vector3(-out.z, 0.0, out.x) * 0.045
		var middle := Vector3(0.0, height, 0.0)
		builder.add_tri(middle - side, middle + side, middle + out * 0.12 + Vector3(0.0, 0.03, 0.0),
				_sway(color.lightened(0.15), 0.8), _sway(color.lightened(0.15), 0.8), _sway(color, 1.0))
	builder.add_frustum(Vector3(0.0, height, 0.0), 0.03, 0.035, 0.0, 5,
			_sway(Color(0.9, 0.7, 0.1), 0.8), _sway(Color(0.9, 0.7, 0.1), 0.8))


static func _cactus(builder: MeshBuilder, rng: RandomNumberGenerator) -> void:
	var green := Color(0.28, 0.5, 0.3)
	var height := rng.randf_range(1.8, 2.8)
	builder.add_frustum(Vector3.ZERO, height, 0.28, 0.22, 7, _still(green.darkened(0.2)),
			_still(green), rng, 0.04, MeshBuilder.CAP_TOP)
	for arm in rng.randi_range(1, 2):
		var side := -1.0 if arm == 0 else 1.0
		var at := height * rng.randf_range(0.35, 0.6)
		builder.xf = Transform3D(Basis(Vector3.BACK, side * PI * 0.5), Vector3(side * 0.2, at, 0.0))
		builder.add_frustum(Vector3.ZERO, 0.45, 0.14, 0.14, 6, _still(green.darkened(0.1)), _still(green))
		builder.xf = Transform3D(Basis.IDENTITY, Vector3(side * 0.65, at, 0.0))
		builder.add_frustum(Vector3.ZERO, rng.randf_range(0.6, 1.0), 0.14, 0.1, 6, _still(green),
				_still(green.lightened(0.05)), null, 0.0, MeshBuilder.CAP_TOP)
		builder.xf = Transform3D.IDENTITY


static func _reed(builder: MeshBuilder, rng: RandomNumberGenerator) -> void:
	var base := Color(0.3, 0.42, 0.18)
	var tip := Color(0.62, 0.6, 0.3)
	for blade in 7:
		var angle := rng.randf() * TAU
		var height := rng.randf_range(1.0, 1.8)
		var root := Vector3(rng.randf_range(-0.2, 0.2), 0.0, rng.randf_range(-0.2, 0.2))
		var across := Vector3(cos(angle), 0.0, sin(angle)) * 0.035
		var top := root + Vector3(rng.randf_range(-0.15, 0.15), height, rng.randf_range(-0.15, 0.15))
		builder.add_tri(root - across, root + across, top, _sway(base, 0.0), _sway(base, 0.0),
				_sway(tip, 1.0))


static func _stump(builder: MeshBuilder, rng: RandomNumberGenerator) -> void:
	var height := rng.randf_range(0.5, 0.9)
	builder.add_frustum(Vector3.ZERO, height, 0.42, 0.34, 7, _still(BARK_DARK), _still(BARK), rng, 0.1,
			MeshBuilder.CAP_TOP)


static func _palm(builder: MeshBuilder, rng: RandomNumberGenerator) -> void:
	var height := rng.randf_range(5.0, 7.5)
	var lean := Vector3(rng.randf_range(-0.9, 0.9), 0.0, rng.randf_range(-0.9, 0.9))
	var wood := Color(0.5, 0.38, 0.24)
	var segments := 5
	var top := Vector3.ZERO
	for index in segments: # a bent trunk made of short stacked pieces
		var along := float(index) / float(segments)
		var shift := lean * along * along
		builder.xf = Transform3D(Basis.IDENTITY, Vector3(shift.x, height * along, shift.z))
		builder.add_frustum(Vector3.ZERO, height / float(segments) * 1.05, 0.22 - along * 0.07,
				0.2 - (along + 0.2) * 0.07, 6, _still(wood.darkened(0.15 * (1.0 - along))),
				_still(wood), rng, 0.04)
		top = Vector3(shift.x, height * along, shift.z)
	builder.xf = Transform3D(Basis.IDENTITY, top + Vector3(lean.x * 0.2, height / float(segments),
			lean.z * 0.2))
	var leaf := Color(0.25, 0.55, 0.22)
	for frond in 8:
		var yaw := TAU * float(frond) / 8.0 + rng.randf_range(-0.2, 0.2)
		var out := Vector3(cos(yaw), 0.0, sin(yaw))
		var side := Vector3(-out.z, 0.0, out.x) * 0.32
		var tip := out * rng.randf_range(2.2, 3.0) + Vector3(0.0, -rng.randf_range(0.5, 1.2), 0.0)
		var mid := out * 1.3 + Vector3(0.0, 0.55, 0.0)
		builder.add_tri(Vector3.ZERO - side * 0.3, Vector3.ZERO + side * 0.3, mid + side,
				_sway(leaf.darkened(0.2), 0.3), _sway(leaf.darkened(0.2), 0.3), _sway(leaf, 0.8))
		builder.add_tri(mid + side, mid - side, tip, _sway(leaf, 0.8), _sway(leaf, 0.8),
				_sway(leaf.lightened(0.15), 1.0))
		builder.add_tri(Vector3.ZERO - side * 0.3, mid + side, mid - side,
				_sway(leaf.darkened(0.2), 0.3), _sway(leaf, 0.8), _sway(leaf, 0.8))
	builder.xf = Transform3D.IDENTITY


static func _fern(builder: MeshBuilder, rng: RandomNumberGenerator) -> void:
	var leaf := Color(0.22, 0.46, 0.2)
	for frond in 7:
		var yaw := TAU * float(frond) / 7.0 + rng.randf_range(-0.25, 0.25)
		var out := Vector3(cos(yaw), 0.0, sin(yaw))
		var side := Vector3(-out.z, 0.0, out.x) * 0.11
		var length := rng.randf_range(0.7, 1.1)
		var mid := out * length * 0.5 + Vector3(0.0, 0.42, 0.0)
		var tip := out * length + Vector3(0.0, 0.18, 0.0)
		builder.add_tri(Vector3.ZERO, mid + side, mid - side, _sway(leaf.darkened(0.3), 0.2),
				_sway(leaf, 0.7), _sway(leaf, 0.7))
		builder.add_tri(mid + side, tip, mid - side, _sway(leaf, 0.7), _sway(leaf.lightened(0.15), 1.0),
				_sway(leaf, 0.7))


static func _mushroom(builder: MeshBuilder, rng: RandomNumberGenerator, variant: int) -> void:
	var caps := [Color(0.82, 0.18, 0.15), Color(0.62, 0.42, 0.25), Color(0.9, 0.78, 0.55)]
	var cap: Color = caps[variant % caps.size()]
	for index in rng.randi_range(1, 3):
		var at := Vector3(rng.randf_range(-0.2, 0.2), 0.0, rng.randf_range(-0.2, 0.2))
		var height := rng.randf_range(0.14, 0.3)
		builder.add_frustum(at, height, 0.035, 0.03, 5, _still(Color(0.9, 0.88, 0.8)),
				_still(Color(0.92, 0.9, 0.84)))
		builder.add_frustum(at + Vector3(0.0, height, 0.0), height * 0.7, height * 0.9, 0.02, 7,
				_still(cap.darkened(0.15)), _still(cap), rng, 0.05)


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


static func _tall_grass(builder: MeshBuilder, rng: RandomNumberGenerator, variant: int) -> void:
	var base := Color(0.3, 0.45, 0.14)
	var tip := Color(0.78, 0.74, 0.34).lerp(Color(0.6, 0.7, 0.26), float(variant) / 3.0)
	for blade in 9:
		var angle := rng.randf() * TAU
		var height := rng.randf_range(0.9, 1.5)
		var root := Vector3(rng.randf_range(-0.2, 0.2), 0.0, rng.randf_range(-0.2, 0.2))
		var across := Vector3(cos(angle), 0.0, sin(angle)) * 0.04
		var top := root + Vector3(sin(angle) * 0.3, height, -cos(angle) * 0.3)
		builder.add_tri(root - across, root + across, top, _sway(base, 0.0), _sway(base, 0.0),
				_sway(tip, 1.0))


## Horizon trees: one cone (a few triangles) so a far forest costs next to nothing.
static func _far_pine(builder: MeshBuilder, rng: RandomNumberGenerator, variant: int) -> void:
	var green := Color(0.15, 0.34, 0.2) if variant == 0 else Color(0.2, 0.38, 0.2)
	var height := rng.randf_range(8.0, 11.0)
	builder.add_frustum(Vector3(0.0, 0.8, 0.0), height, 2.2, 0.0, 5, _still(green.darkened(0.1)),
			_still(green.lightened(0.1)), rng, 0.1, MeshBuilder.CAP_BOTTOM)


static func _far_oak(builder: MeshBuilder, rng: RandomNumberGenerator, variant: int) -> void:
	var leaf := Color(0.3, 0.5, 0.18) if variant == 0 else Color(0.78, 0.4, 0.15)
	builder.add_frustum(Vector3.ZERO, 3.0, 0.4, 0.25, 4, _still(BARK_DARK), _still(BARK))
	builder.add_blob(Vector3(0.0, 5.0, 0.0), Vector3(3.2, 2.6, 3.2), _still(leaf.darkened(0.25)),
			_still(leaf.lightened(0.1)), rng, 0.2)


## A finer tuft: 9 curved blades, each in two tapering segments that bend over toward the tip.
static func _grass_detailed(builder: MeshBuilder, rng: RandomNumberGenerator, base: Color,
		tip: Color) -> void:
	for blade in 9:
		var angle := rng.randf() * TAU
		var height := rng.randf_range(0.4, 0.85)
		var bend := rng.randf_range(0.15, 0.55) * height
		var root := Vector3(rng.randf_range(-0.14, 0.14), 0.0, rng.randf_range(-0.14, 0.14))
		var out := Vector3(sin(angle), 0.0, -cos(angle))
		var across := Vector3(cos(angle), 0.0, sin(angle))
		var mid := root + out * bend * 0.3 + Vector3(0.0, height * 0.55, 0.0)
		var top := root + out * bend + Vector3(0.0, height * 0.95, 0.0)
		var shade := rng.randf_range(0.85, 1.15)
		var low := base * shade
		var high := tip.lerp(base, 0.4) * shade
		var upper := tip * shade
		builder.add_tri(root - across * 0.05, root + across * 0.05, mid - across * 0.032,
				_sway(low, 0.0), _sway(low, 0.0), _sway(high, 0.5))
		builder.add_tri(root + across * 0.05, mid + across * 0.032, mid - across * 0.032,
				_sway(low, 0.0), _sway(high, 0.5), _sway(high, 0.5))
		builder.add_tri(mid - across * 0.032, mid + across * 0.032, top, _sway(high, 0.5),
				_sway(high, 0.5), _sway(upper, 1.0))
