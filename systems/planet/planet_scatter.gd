class_name PlanetScatter
extends RefCounted
## The plants of one planet tile: the same species and the same rules as the flat world's
## WorldScatter (each layer on a jittered grid, the species whose niche fits the spot best the
## likeliest), but the niche is read from the planet's climate: moisture from the rain, warmth from
## the temperature at the spot's height (so trees thin out and stop up a mountain), and the slope.
## Plants stand upright in the tile's own frame (a tile is small, so its "up" is the plant's up).
## Everything is drawn with one MultiMesh per species and variant, in the tile's local space.

const BANK := 4.0 ## m from a river edge inside which nothing grows (the bank can be higher)
const GRASS_VISIBLE := 110.0
const PEBBLE_VISIBLE := 45.0 ## m: small stones are gone beyond this
const TREE_FULL := 80.0 ## m: beyond this a tree is drawn as its lighter version
const SMALL_VISIBLE := 220.0 ## m: shrubs and ground cover are gone beyond this
const TREE_LIGHT := 220.0 ## m: beyond this, as the cheap far tree (a cone or a ball on a trunk)
const SPACING := {
	PlantSpecies.Layer.CANOPY: 6.5, PlantSpecies.Layer.UNDERSTORY: 5.0,
	PlantSpecies.Layer.GRASS: 1.7, PlantSpecies.Layer.MEADOW: 3.2, PlantSpecies.Layer.COVER: 2.6,
}
const MAX_CHANCE := {
	PlantSpecies.Layer.CANOPY: 0.85, PlantSpecies.Layer.UNDERSTORY: 0.4,
	PlantSpecies.Layer.GRASS: 0.95, PlantSpecies.Layer.MEADOW: 0.7, PlantSpecies.Layer.COVER: 0.5,
}
const GRASS_FINE := 0.6 ## the grass grid's spacing in the realistic look, as a share of the usual
const PLANT_KEY := 100000
const FAR_KEY := 200000

enum Detail { NONE, FAR, TREES, ALL } ## FAR: only the cheap horizon trees, sparse

var _tile: Node3D
var _noise: PlanetNoise
var _species: SpeciesRegistry
var _rng := RandomNumberGenerator.new()
var _batches: Dictionary = {} # key -> Array[Transform3D]
var _colors: Dictionary = {} # key -> Array[Color]
var _far_meshes: Array = [] # [mesh, transform, tint] of the far trees of the near ground
var _horizon_meshes: Array = [] # the same for the horizon: no range, they are all there is
var _body: StaticBody3D
var _positions: Array[Vector3] = []
var _dirs: Array[Vector3] = []
var _heights := PackedFloat32Array()
var _cells := 0
var _side := 0
var _size := 0.0
var _weights: Array[float] = []
var _pick_chance := 0.0
var _wet := 0.0
var _packed_positions := PackedVector3Array() ## the grid as packed arrays, for the native placement
var _packed_dirs := PackedVector3Array()


## Plants a tile into `holder` (a node of its own that the tile adopts when this is done, so it can
## be built on a worker thread while the tile is already in the world). `key` is the tile's key (it
## seeds the dice); the grid is the tile's padded grid (see PlanetTile.build): local positions,
## directions from the planet's centre and heights, `cells` quads along an edge.
func populate(holder: Node3D, key: int, noise: PlanetNoise, positions: Array[Vector3],
		dirs: Array[Vector3], heights: PackedFloat32Array, cells: int, size: float, detail: Detail,
		collide: bool, packed_positions := PackedVector3Array(),
		packed_dirs := PackedVector3Array()) -> void:
	_packed_positions = packed_positions
	_packed_dirs = packed_dirs
	_tile = holder
	_noise = noise
	_species = noise.species
	_positions = positions
	_dirs = dirs
	_heights = heights
	_cells = cells
	_side = cells + 3
	_size = size
	_rng.seed = hash(Vector2i(noise.settings.world_seed, key))
	if collide:
		_body = StaticBody3D.new()
		_body.collision_layer = 1
		_body.name = "Plants"
		holder.add_child(_body)
	if noise.scatter_native != null and noise.hydrology == null and not _packed_positions.is_empty():
		_populate_native(key, detail, collide)
		return
	if detail == Detail.FAR:
		_scatter_far()
		_flush(false)
		return
	_scatter(PlantSpecies.Layer.CANOPY, 1.0 if detail == Detail.ALL else 2.0)
	_scatter(PlantSpecies.Layer.UNDERSTORY, 1.0 if detail == Detail.ALL else 2.0)
	if detail != Detail.NONE:
		_rocks(detail == Detail.ALL)
	if detail == Detail.ALL and int(GraphicsSettings.get_graphics_value(&"ground_detail")) >= 2:
		_pebbles()
		_debris()
	if detail == Detail.ALL:
		_scatter(PlantSpecies.Layer.GRASS, 1.0)
		_scatter(PlantSpecies.Layer.MEADOW, 1.0)
		_scatter(PlantSpecies.Layer.COVER, 1.0)
	_flush(detail == Detail.ALL)


## The species as plain numbers, for the native placement (PlanetScatterNative.setup).
static func species_table(registry: SpeciesRegistry) -> Array:
	var table: Array = []
	for one in registry.species:
		table.append({"id": one.id, "layer": one.layer(), "variants": one.variants, "tree": one.is_tree(),
				"has_far": PlantMeshes.has_far(one), "moisture": one.moisture,
				"moisture_tol": one.moisture_tol, "heat": one.heat, "heat_tol": one.heat_tol,
				"above_min": one.above_min, "above_max": one.above_max, "slope_max": one.slope_max,
				"density": one.density, "patch_freq": one.patch_freq,
				"patch_strength": one.patch_strength, "size_spread": one.size_spread,
				"patch_offset": one.patch_offset, "footprint": one.footprint()})
	return table


## The same placement as the loops below, run natively (the plants' buffers come back ready to hang).
func _populate_native(key: int, detail: Detail, collide: bool) -> void:
	var placed: Dictionary = _noise.scatter_native.call(&"scatter", {
		"key": key, "positions": _packed_positions, "dirs": _packed_dirs, "heights": _heights,
		"cells": _cells, "size": _size, "detail": int(detail), "collide": collide,
		"clearing": _noise.clearing,
		"fine": int(GraphicsSettings.get_graphics_value(&"ground_detail")) >= 2,
		"grass_fine": FloraMeshes.detailed})
	if placed.is_empty():
		return
	if _body != null:
		var cylinders: PackedFloat32Array = placed["cylinders"]
		for index in cylinders.size() / 5:
			var shape := CylinderShape3D.new()
			shape.radius = cylinders[index * 5 + 3]
			shape.height = cylinders[index * 5 + 4]
			var collision := CollisionShape3D.new()
			collision.shape = shape
			collision.position = Vector3(cylinders[index * 5], cylinders[index * 5 + 1],
					cylinders[index * 5 + 2])
			_body.add_child(collision)
		var boxes: PackedFloat32Array = placed["boxes"]
		for index in boxes.size() / 7:
			var box := BoxShape3D.new()
			box.size = Vector3(boxes[index * 7 + 4], boxes[index * 7 + 5], boxes[index * 7 + 6])
			_add_box(box, Vector3(boxes[index * 7], boxes[index * 7 + 1], boxes[index * 7 + 2]),
					boxes[index * 7 + 3])
	_hang(placed["keys"], placed["buffers"], detail == Detail.ALL)


## One layer of plants over the tile (`stretch` widens the grid: a far tile has fewer, bigger gaps).
func _scatter(layer: PlantSpecies.Layer, stretch: float) -> void:
	var spacing: float = SPACING[layer] * stretch
	if layer == PlantSpecies.Layer.GRASS and FloraMeshes.detailed:
		spacing *= GRASS_FINE # the realistic look: a meadow of tufts, not a few of them
	var count := int(_size / spacing)
	var density := _noise.settings.plant_density
	for row in count:
		for column in count:
			var x := (float(column) + _rng.randf()) * spacing
			var z := (float(row) + _rng.randf()) * spacing
			var fx := clampf(x / _size * float(_cells), 0.0, float(_cells) - 0.001)
			var fz := clampf(z / _size * float(_cells), 0.0, float(_cells) - 0.001)
			var at := _ground(fx, fz)
			var ground := _height_at(fx, fz)
			if ground < 0.9:
				continue # the sea
			var steep := _slope(fx, fz)
			var dir := _direction(fx, fz)
			if _noise.near_water(dir, ground, BANK):
				continue # a river or a lake
			if layer <= PlantSpecies.Layer.UNDERSTORY and _in_clearing(dir):
				continue
			var plant := _pick(layer, dir, ground, steep, x, z)
			if plant != null and _rng.randf() <= _pick_chance * density:
				_place(plant, at)


## The horizon: a sparse grid of the cheap far trees (one cone or one trunk and ball each), so a
## forest does not stop where the real trees do. Same species rules as near trees.
func _scatter_far() -> void:
	var spacing := clampf(_size / 26.0, 14.0, 90.0)
	var count := int(_size / spacing)
	for row in count:
		for column in count:
			var x := (float(column) + _rng.randf()) * spacing
			var z := (float(row) + _rng.randf()) * spacing
			var fx := clampf(x / _size * float(_cells), 0.0, float(_cells) - 0.001)
			var fz := clampf(z / _size * float(_cells), 0.0, float(_cells) - 0.001)
			var ground := _height_at(fx, fz)
			if ground < 0.9:
				continue
			var dir := _direction(fx, fz)
			if _noise.near_water(dir, ground, BANK):
				continue
			var tree := _pick(PlantSpecies.Layer.CANOPY, dir, ground, _slope(fx, fz), x, z)
			if tree == null or not PlantMeshes.has_far(tree):
				continue
			if _rng.randf() > _pick_chance * _noise.settings.plant_density:
				continue
			var key := FAR_KEY + tree.id * 100 + _rng.randi() % 2
			if not _batches.has(key):
				_batches[key] = []
				_colors[key] = []
			# a far tree stands for the trees around it: a little bigger than one
			var scale := _rng.randf_range(1.0, 1.8)
			(_batches[key] as Array).append(Transform3D(
					Basis(Vector3.UP, _rng.randf_range(0.0, TAU)).scaled(Vector3.ONE * scale),
					_ground(fx, fz) - Vector3(0.0, 0.2, 0.0)))
			(_colors[key] as Array).append(Color.WHITE)


## Rocks (more and bigger on rocky, snowy and dry ground and steep slopes) and, further apart,
## the things that stand out: fallen logs and stumps in forests, rock spires in the hills and
## deserts, driftwood on beaches. The same kinds and chances as the flat world's WorldScatter.
func _rocks(near: bool) -> void:
	var spacing := 10.0 if near else 20.0
	var count := int(_size / spacing)
	for row in count:
		for column in count:
			var x := (float(column) + _rng.randf()) * spacing
			var z := (float(row) + _rng.randf()) * spacing
			var fx := clampf(x / _size * float(_cells), 0.0, float(_cells) - 0.001)
			var fz := clampf(z / _size * float(_cells), 0.0, float(_cells) - 0.001)
			var ground := _height_at(fx, fz)
			if ground < 0.9:
				continue
			var dir := _direction(fx, fz)
			if _noise.near_water(dir, ground, BANK):
				continue
			if _in_clearing(dir):
				continue
			var steep := _slope(fx, fz)
			var biome := _noise.biome(dir.x, dir.y, dir.z, ground, steep)
			_rock_at(biome, steep, _ground(fx, fz), near)


## Small stones lying about near the player (the Fine ground detail and up): thick on bare, rocky,
## snowy and desert ground, a few on the rest, none in the sea or by the water.
func _pebbles() -> void:
	var spacing := 2.4
	var count := int(_size / spacing)
	for row in count:
		for column in count:
			var x := (float(column) + _rng.randf()) * spacing
			var z := (float(row) + _rng.randf()) * spacing
			var fx := clampf(x / _size * float(_cells), 0.0, float(_cells) - 0.001)
			var fz := clampf(z / _size * float(_cells), 0.0, float(_cells) - 0.001)
			var ground := _height_at(fx, fz)
			if ground < 0.9:
				continue
			var dir := _direction(fx, fz)
			if _noise.near_water(dir, ground, BANK * 0.5):
				continue
			var steep := _slope(fx, fz)
			var chance := 0.08 + steep * 0.5
			match _noise.biome(dir.x, dir.y, dir.z, ground, steep):
				TerrainNoise.Biome.ROCKY, TerrainNoise.Biome.SNOW:
					chance += 0.35
				TerrainNoise.Biome.DESERT, TerrainNoise.Biome.BEACH:
					chance += 0.2
			if _rng.randf() < chance * _noise.settings.rock_density:
				var kind := FloraMeshes.Kind.PEBBLES
				_queue_kind(kind, _rng.randi() % FloraMeshes.variant_count(kind), _ground(fx, fz),
						_rng.randf_range(0.7, 1.5), _rng.randf_range(0.0, TAU))


## Dead leaves and fallen sticks on the ground (the Fine ground detail and up): thick under a forest, some in a
## meadow, none on bare rock, sand, snow or by the water.
func _debris() -> void:
	var spacing := 1.5
	var count := int(_size / spacing)
	for row in count:
		for column in count:
			var x := (float(column) + _rng.randf()) * spacing
			var z := (float(row) + _rng.randf()) * spacing
			var fx := clampf(x / _size * float(_cells), 0.0, float(_cells) - 0.001)
			var fz := clampf(z / _size * float(_cells), 0.0, float(_cells) - 0.001)
			var ground := _height_at(fx, fz)
			if ground < 0.9:
				continue
			var dir := _direction(fx, fz)
			if _noise.near_water(dir, ground, BANK * 0.5):
				continue
			var chance := 0.0
			match _noise.biome(dir.x, dir.y, dir.z, ground, _slope(fx, fz)):
				TerrainNoise.Biome.FOREST:
					chance = 0.5
				TerrainNoise.Biome.MEADOW:
					chance = 0.12
				TerrainNoise.Biome.MARSH:
					chance = 0.1
			if _rng.randf() >= chance:
				continue
			var kind := FloraMeshes.Kind.LITTER if _rng.randf() < 0.7 else FloraMeshes.Kind.TWIGS
			_queue_kind(kind, _rng.randi() % FloraMeshes.variant_count(kind), _ground(fx, fz),
					_rng.randf_range(0.8, 1.6), _rng.randf_range(0.0, TAU))


func _rock_at(biome: int, steep: float, at: Vector3, near: bool) -> void:
	var chance := 0.1
	var big := 1.0
	match biome:
		TerrainNoise.Biome.ROCKY:
			chance = 0.55
			big = 2.2
		TerrainNoise.Biome.SNOW:
			chance = 0.3
			big = 1.8
		TerrainNoise.Biome.BEACH:
			chance = 0.1
			big = 0.7
		TerrainNoise.Biome.DESERT:
			chance = 0.2
			big = 1.4
	chance += steep * 0.3
	var density := _noise.settings.rock_density
	if _rng.randf() < chance * density:
		var scale := _rng.randf_range(0.5, 1.5) * big
		var yaw := _rng.randf_range(0.0, TAU)
		var kind := FloraMeshes.Kind.ROCK
		_queue_kind(kind, _rng.randi() % FloraMeshes.variant_count(kind), at, scale, yaw)
		if _body != null:
			var box := BoxShape3D.new()
			box.size = Vector3(1.7, 1.0, 1.5) * scale
			_add_box(box, at + Vector3(0.0, scale * 0.2, 0.0), yaw)
	if not near:
		return
	var feature := FloraMeshes.Kind.LOG
	var odds := 0.0
	match biome:
		TerrainNoise.Biome.FOREST:
			odds = 0.16
			feature = FloraMeshes.Kind.LOG if _rng.randf() < 0.6 else FloraMeshes.Kind.STUMP
		TerrainNoise.Biome.MARSH:
			odds = 0.1
			feature = FloraMeshes.Kind.STUMP
		TerrainNoise.Biome.BEACH:
			odds = 0.06
		TerrainNoise.Biome.ROCKY, TerrainNoise.Biome.SNOW:
			odds = 0.16
			feature = FloraMeshes.Kind.SPIRE
		TerrainNoise.Biome.DESERT:
			odds = 0.1
			feature = FloraMeshes.Kind.SPIRE
	if _rng.randf() < odds * density:
		var scale := _rng.randf_range(0.8, 1.4)
		var yaw := _rng.randf_range(0.0, TAU)
		_queue_kind(feature, _rng.randi() % FloraMeshes.variant_count(feature), at, scale, yaw)
		if _body != null:
			var box := BoxShape3D.new()
			if feature == FloraMeshes.Kind.LOG:
				box.size = Vector3(3.6, 0.6, 0.6) * scale
			elif feature == FloraMeshes.Kind.STUMP:
				box.size = Vector3(0.8, 0.8, 0.8) * scale
			else:
				box.size = Vector3(1.6, 5.0, 1.6) * scale
			_add_box(box, at + Vector3(0.0, box.size.y * 0.4, 0.0), yaw)


func _queue_kind(kind: int, variant: int, at: Vector3, scale: float, yaw: float) -> void:
	var key := kind * 100 + variant
	if not _batches.has(key):
		_batches[key] = []
		_colors[key] = []
	var flat := kind == FloraMeshes.Kind.LITTER or kind == FloraMeshes.Kind.TWIGS # lie on the ground
	(_batches[key] as Array).append(Transform3D(
			Basis(Vector3.UP, yaw).scaled(Vector3.ONE * scale),
			at - Vector3(0.0, 0.0 if flat else scale * 0.12, 0.0)))
	(_colors[key] as Array).append(Color.WHITE)


func _add_box(box: BoxShape3D, at: Vector3, yaw: float) -> void:
	var collision := CollisionShape3D.new()
	collision.shape = box
	collision.transform = Transform3D(Basis(Vector3.UP, yaw), at)
	_body.add_child(collision)


## The species of `layer` that grows at this spot, in proportion to how well each fits, or null.
func _pick(layer: PlantSpecies.Layer, dir: Vector3, ground: float, steep: float, x: float,
		z: float) -> PlantSpecies:
	_wet = _noise.moisture(dir.x, dir.y, dir.z)
	var warm := _noise.heat(dir.x, dir.y, dir.z, ground)
	var above := minf(ground, 30.0) # the height niche is a coastal plain one; cold is `warm`'s job
	var candidates := _species.in_layer(layer)
	_weights.resize(candidates.size())
	var total := 0.0
	for index in candidates.size():
		var one := candidates[index]
		var weight := one.fitness(_wet, warm, above, steep) * one.density
		if weight > 0.003 and one.patch_strength > 0.0:
			var patch := _noise.detail_at(Vector3(x * one.patch_freq + one.patch_offset.x,
					z * one.patch_freq + one.patch_offset.y, float(layer)))
			weight *= lerpf(1.0, smoothstep(0.5, 0.66, patch), one.patch_strength)
		_weights[index] = weight
		total += weight
	_pick_chance = minf(total, MAX_CHANCE[layer])
	if total <= 0.0:
		return null
	var roll := _rng.randf() * total
	for index in candidates.size():
		roll -= _weights[index]
		if roll <= 0.0:
			return candidates[index]
	return candidates[candidates.size() - 1]


## Where the player starts nothing tall grows (the flat world keeps its spawn clear too).
func _in_clearing(dir: Vector3) -> bool:
	if _noise.clearing == Vector3.ZERO:
		return false
	return dir.distance_to(_noise.clearing) * _noise.settings.radius < 12.0


func _place(plant: PlantSpecies, at: Vector3) -> void:
	var scale := 1.0 + _rng.randf_range(-plant.size_spread, plant.size_spread)
	var yaw := _rng.randf_range(0.0, TAU)
	var variant := _rng.randi() % plant.variants
	var tint := Color.WHITE
	if plant.layer() == PlantSpecies.Layer.GRASS:
		tint = Color(1.0, 1.0, 1.0).lerp(Color(1.25, 1.05, 0.7), (1.0 - _wet) * 0.7)
		tint = tint.darkened(_rng.randf_range(0.0, 0.2))
	else:
		# every plant its own shade: lighter or darker, a little more of one colour (a tree of the
		# same species still differs from its neighbour)
		var shade := _rng.randf_range(0.82, 1.18)
		tint = Color(shade * _rng.randf_range(0.92, 1.08), shade * _rng.randf_range(0.95, 1.05),
				shade * _rng.randf_range(0.9, 1.1))
	var key := PLANT_KEY + plant.id * 100 + variant
	if not _batches.has(key):
		_batches[key] = []
		_colors[key] = []
	var lowered := at - Vector3(0.0, 0.15 if plant.is_tree() else 0.03, 0.0)
	(_batches[key] as Array).append(Transform3D(
			Basis(Vector3.UP, yaw).scaled(Vector3.ONE * scale), lowered))
	(_colors[key] as Array).append(tint)
	var foot := plant.footprint() # trunks stop the player; the rest can be walked through
	if _body != null and foot != Vector2.ZERO:
		var shape := CylinderShape3D.new()
		shape.radius = foot.x * scale
		shape.height = foot.y * scale
		var collision := CollisionShape3D.new()
		collision.shape = shape
		collision.position = at + Vector3(0.0, foot.y * scale * 0.5, 0.0)
		_body.add_child(collision)


func _flush(near: bool) -> void:
	var keys := PackedInt32Array()
	var buffers: Array = []
	for key: int in _batches.keys():
		keys.append(key)
		buffers.append(_buffer_of(key))
	_hang(keys, buffers, near)


## What a MultiMesh wants for the batch of `key`: 12 floats of transform (3 rows of basis x, y, z and the origin) and 4
## of colour for every instance (thousands of set_instance_* calls cost far more).
func _buffer_of(key: int) -> PackedFloat32Array:
	var transforms: Array = _batches[key]
	var colours: Array = _colors[key]
	var buffer := PackedFloat32Array()
	buffer.resize(transforms.size() * 16)
	for index in transforms.size():
		var t: Transform3D = transforms[index]
		var c: Color = colours[index]
		var at := index * 16
		buffer[at] = t.basis.x.x
		buffer[at + 1] = t.basis.y.x
		buffer[at + 2] = t.basis.z.x
		buffer[at + 3] = t.origin.x
		buffer[at + 4] = t.basis.x.y
		buffer[at + 5] = t.basis.y.y
		buffer[at + 6] = t.basis.z.y
		buffer[at + 7] = t.origin.y
		buffer[at + 8] = t.basis.x.z
		buffer[at + 9] = t.basis.y.z
		buffer[at + 10] = t.basis.z.z
		buffer[at + 11] = t.origin.z
		buffer[at + 12] = c.r
		buffer[at + 13] = c.g
		buffer[at + 14] = c.b
		buffer[at + 15] = c.a
	return buffer


## Hangs the batches (a key and its instances' buffer each) on the tile: a multimesh for each, and the far trees
## merged into one mesh.
func _hang(keys: PackedInt32Array, buffers: Array, near: bool) -> void:
	var far_parts: Array = [] # [mesh, buffer] of the far trees of the near ground
	var horizon_parts: Array = [] # the same for the horizon: no range, they are all there is
	for at in keys.size():
		var key := keys[at]
		var buffer: PackedFloat32Array = buffers[at]
		if key >= FAR_KEY:
			horizon_parts.append([_species.far_mesh((key - FAR_KEY) / 100, key % 100), buffer])
			continue
		var plant := key >= PLANT_KEY
		var id := (key - PLANT_KEY) / 100
		var variant := key % 100
		var layer := _species.by_id(id).layer() if plant else PlantSpecies.Layer.CANOPY
		var tree := plant and _species.by_id(id).is_tree()
		if tree and not near:
			# trees beyond the near ground are only ever seen from far: the lighter version
			var light := _add_trees(buffer, _species.mesh(id, variant % 2, FloraMeshes.detailed, 1), false)
			if PlantMeshes.has_far(_species.by_id(id)):
				light.visibility_range_end = TREE_LIGHT
				far_parts.append([_species.far_mesh(id, variant % 2), buffer])
			continue
		var mesh: ArrayMesh
		if plant:
			mesh = _species.mesh(id, variant, FloraMeshes.detailed, 0)
		else:
			mesh = FloraMeshes.mesh(key / 100 as FloraMeshes.Kind, variant, FloraMeshes.detailed)
		var instance := _add_trees(buffer, mesh, true)
		if not plant and key / 100 in [FloraMeshes.Kind.PEBBLES, FloraMeshes.Kind.LITTER,
				FloraMeshes.Kind.TWIGS]:
			instance.visibility_range_end = PEBBLE_VISIBLE
			instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		elif layer == PlantSpecies.Layer.GRASS or layer == PlantSpecies.Layer.MEADOW:
			instance.visibility_range_end = GRASS_VISIBLE
			instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		elif not near:
			instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			instance.visibility_range_end = SMALL_VISIBLE
		elif not tree:
			instance.visibility_range_end = SMALL_VISIBLE
		else:
			# near trees: the full tree close up, the lighter one (no shadow) further out
			instance.visibility_range_end = TREE_FULL
			var light := _add_trees(buffer, _species.mesh(id, variant % 2, FloraMeshes.detailed, 1),
					false)
			light.visibility_range_begin = TREE_FULL * 0.95
			if PlantMeshes.has_far(_species.by_id(id)):
				light.visibility_range_end = TREE_LIGHT
				far_parts.append([_species.far_mesh(id, variant % 2), buffer])
	_commit_far(far_parts, TREE_LIGHT * 0.95)
	_commit_far(horizon_parts, 0.0)


## One mesh with all the far trees of the tile (parts: [mesh, instances' buffer]), drawn from `begin` metres away (0:
## always): a draw call for the whole tile instead of one for each kind of tree.
func _commit_far(parts: Array, begin: float) -> void:
	if parts.is_empty():
		return
	var arrays_of := {}
	var sources: Array = []
	for part: Array in parts:
		var mesh: ArrayMesh = part[0]
		if not arrays_of.has(mesh):
			arrays_of[mesh] = mesh.surface_get_arrays(0) if mesh.get_surface_count() > 0 else []
		var arrays: Array = arrays_of[mesh]
		if arrays.is_empty():
			continue
		sources.append({"vertices": arrays[Mesh.ARRAY_VERTEX], "normals": arrays[Mesh.ARRAY_NORMAL],
				"colors": arrays[Mesh.ARRAY_COLOR], "buffer": part[1]})
	if sources.is_empty():
		return
	var merged: Dictionary
	if _noise.scatter_native != null:
		merged = _noise.scatter_native.call(&"merge_far", sources)
	else:
		merged = _merge_far_script(sources)
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = merged["vertices"]
	arrays[Mesh.ARRAY_NORMAL] = merged["normals"]
	arrays[Mesh.ARRAY_COLOR] = merged["colors"]
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = FloraMeshes.material()
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	instance.visibility_range_begin = begin
	_tile.add_child(instance)


## What `merge_far` does natively, for a planet without the library.
func _merge_far_script(sources: Array) -> Dictionary:
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	for source: Dictionary in sources:
		var buffer: PackedFloat32Array = source["buffer"]
		for index in buffer.size() / 16:
			var at := index * 16
			var placed := Transform3D(Basis(
					Vector3(buffer[at], buffer[at + 4], buffer[at + 8]),
					Vector3(buffer[at + 1], buffer[at + 5], buffer[at + 9]),
					Vector3(buffer[at + 2], buffer[at + 6], buffer[at + 10])),
					Vector3(buffer[at + 3], buffer[at + 7], buffer[at + 11]))
			var tint := Color(buffer[at + 12], buffer[at + 13], buffer[at + 14], buffer[at + 15])
			vertices.append_array(placed * (source["vertices"] as PackedVector3Array))
			var turn := Transform3D(placed.basis.orthonormalized(), Vector3.ZERO)
			normals.append_array(turn * (source["normals"] as PackedVector3Array))
			for colour: Color in source["colors"]:
				colors.append(Color(colour.r * tint.r, colour.g * tint.g, colour.b * tint.b, colour.a))
	return {"vertices": vertices, "normals": normals, "colors": colors}


## One multimesh of `mesh` at the instances in `buffer` (12 floats of transform and 4 of colour each), added to the tile.
func _add_trees(buffer: PackedFloat32Array, mesh: ArrayMesh, shadows: bool) -> MultiMeshInstance3D:
	var multi := MultiMesh.new()
	multi.transform_format = MultiMesh.TRANSFORM_3D
	multi.use_colors = true
	multi.mesh = mesh
	multi.instance_count = buffer.size() / 16
	multi.buffer = buffer
	var instance := MultiMeshInstance3D.new()
	instance.multimesh = multi
	instance.material_override = FloraMeshes.material()
	if not shadows:
		instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_tile.add_child(instance)
	return instance


## The tile's grid index (fractional) to the padded array index of its lower corner.
func _index(fx: float, fz: float) -> int:
	return (int(fz) + 1) * _side + int(fx) + 1


## A point on the ground (tile space) at the fractional grid position, on the same triangles the
## mesh and the collider use (each quad split along its p10-p01 diagonal).
func _ground(fx: float, fz: float) -> Vector3:
	var index := _index(fx, fz)
	var tx := fx - floorf(fx)
	var tz := fz - floorf(fz)
	var p00 := _positions[index]
	var p10 := _positions[index + 1]
	var p01 := _positions[index + _side]
	var p11 := _positions[index + _side + 1]
	if tx + tz <= 1.0:
		return p00 + (p10 - p00) * tx + (p01 - p00) * tz
	return p11 + (p01 - p11) * (1.0 - tx) + (p10 - p11) * (1.0 - tz)


func _height_at(fx: float, fz: float) -> float:
	var index := _index(fx, fz)
	var tx := fx - floorf(fx)
	var tz := fz - floorf(fz)
	var h00 := _heights[index]
	var h10 := _heights[index + 1]
	var h01 := _heights[index + _side]
	var h11 := _heights[index + _side + 1]
	if tx + tz <= 1.0:
		return h00 + (h10 - h00) * tx + (h01 - h00) * tz
	return h11 + (h01 - h11) * (1.0 - tx) + (h10 - h11) * (1.0 - tz)


func _direction(fx: float, fz: float) -> Vector3:
	var index := _index(fx, fz)
	return ((_dirs[index] + _dirs[index + 1] + _dirs[index + _side] + _dirs[index + _side + 1])
			* 0.25).normalized()


## Slope (0 flat .. 1 and more steep) of the quad at the fractional grid position.
func _slope(fx: float, fz: float) -> float:
	var index := _index(fx, fz)
	var step := _size / float(_cells)
	var dx := (_positions[index + 1].y - _positions[index].y
			+ _positions[index + _side + 1].y - _positions[index + _side].y) / (2.0 * step)
	var dz := (_positions[index + _side].y - _positions[index].y
			+ _positions[index + _side + 1].y - _positions[index + 1].y) / (2.0 * step)
	return clampf(Vector2(dx, dz).length(), 0.0, 1.0)
