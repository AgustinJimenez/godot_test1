class_name WorldScatter
extends RefCounted
## Puts the plants and rocks on one terrain tile. Each kind is laid out on a jittered grid (so it
## looks random but never clumps into a pile), kept or dropped by what the ground is (biome,
## slope, height), then drawn with one MultiMesh per kind and variant. Trunks and rocks also get a
## simple collider. The dice are seeded by the tile, so the same tile always grows the same things.

const GRASS_VISIBLE := 110.0 ## m the small plants stay drawn
const TREE_SPACING := 6.5
const ROCK_SPACING := 10.0
const BUSH_SPACING := 5.0
const GRASS_SPACING := 1.7
const FLOWER_SPACING := 3.2

var _noise: TerrainNoise
var _settings: WorldSettings
var _chunk: Node3D
var _rng := RandomNumberGenerator.new()
var _batches: Dictionary = {} # key (kind * 100 + variant) -> Array[Transform3D]
var _colors: Dictionary = {} # same key -> Array[Color]
var _body: StaticBody3D
var _heights := PackedFloat32Array() # the tile's height grid, so no point needs its own noise
var _grid_step := 2.0
var _grid_cells := 0
var _clearing: Dictionary = {} # the structure of this tile (trees and rocks keep off it)


## A far (horizon) tile: only sparse, very cheap trees, no colliders.
func populate_far(chunk: Node3D, noise: TerrainNoise, heights: PackedFloat32Array,
		step: float) -> void:
	_set_grid(heights, step)
	_chunk = chunk
	_noise = noise
	_settings = noise.settings
	var coord: Vector2i = chunk.get("coord")
	_rng.seed = hash(Vector3i(_settings.world_seed, coord.x, coord.y))
	_body = null
	_grid(13.0, func(x: float, z: float, ground: float, biome: int, steep: float) -> void:
		var chance := 0.0
		var kind := FloraMeshes.Kind.FAR_PINE
		match biome:
			TerrainNoise.Biome.FOREST:
				chance = 0.8
				kind = FloraMeshes.Kind.FAR_PINE if _rng.randf() < 0.55 else FloraMeshes.Kind.FAR_OAK
			TerrainNoise.Biome.MEADOW:
				chance = 0.1
				kind = FloraMeshes.Kind.FAR_OAK
			TerrainNoise.Biome.ROCKY:
				chance = 0.12
			TerrainNoise.Biome.SNOW:
				chance = 0.05
		if steep > 0.5 or _rng.randf() > chance * _settings.tree_density:
			return
		_add(kind, x, z, ground - 0.2, _rng.randf_range(0.8, 1.3), _rng.randf_range(0.0, TAU),
				Color.WHITE))
	_flush(false)



func populate(chunk: Node3D, noise: TerrainNoise, near: bool, heights: PackedFloat32Array,
		step: float) -> void:
	_set_grid(heights, step)
	_chunk = chunk
	_noise = noise
	_settings = noise.settings
	var coord: Vector2i = chunk.get("coord")
	_rng.seed = hash(Vector3i(_settings.world_seed, coord.x, coord.y))
	_clearing = WorldStructures.plan(coord, noise)
	_body = StaticBody3D.new()
	_body.collision_layer = 1
	chunk.add_child(_body)
	_trees()
	_rocks()
	_bushes()
	if near:
		_grass()
		_flowers()
		_cover()
	_features()
	_flush(near)


## Calls `place.call(world_x, world_z, ground, biome, steep)` for each jittered grid point.
func _grid(spacing: float, place: Callable) -> void:
	var size := _settings.chunk_size
	var count := int(size / spacing)
	var origin := _chunk.position
	for row in count:
		for column in count:
			var x := origin.x + (float(column) + _rng.randf()) * spacing
			var z := origin.z + (float(row) + _rng.randf()) * spacing
			var ground := _grid_height(x, z)
			if ground < _noise.water_level(x, z) + 0.9:
				continue
			if not _clearing.is_empty() and Vector2(x, z).distance_to(Vector2(
					(_clearing["position"] as Vector3).x, (_clearing["position"] as Vector3).z)) \
					< float(_clearing["radius"]):
				continue
			var steep := _grid_slope(x, z)
			place.call(x, z, ground, _noise.biome(x, z, ground, steep), steep)


func _trees() -> void:
	var forest_scale := _settings.tree_density
	_grid(TREE_SPACING, func(x: float, z: float, ground: float, biome: int, steep: float) -> void:
		if steep > 0.5 or Vector2(x, z).length() < 14.0:
			return
		var grove := _noise.moisture(x * 1.7, z * 1.7) # trees gather in groves
		var chance := 0.0
		var pick := _rng.randf()
		var kind := FloraMeshes.Kind.OAK
		var snowy := false
		match biome:
			TerrainNoise.Biome.FOREST:
				chance = 0.85
				kind = (FloraMeshes.Kind.PINE if pick < 0.55
						else FloraMeshes.Kind.OAK if pick < 0.9 else FloraMeshes.Kind.BIRCH)
			TerrainNoise.Biome.MEADOW:
				chance = 0.1 + grove * 0.12
				kind = FloraMeshes.Kind.OAK if pick < 0.6 else FloraMeshes.Kind.BIRCH
			TerrainNoise.Biome.ROCKY:
				chance = 0.2
				kind = FloraMeshes.Kind.PINE if pick < 0.7 else FloraMeshes.Kind.DEAD_TREE
				snowy = _noise.heat(x, z, ground) < 0.35 and kind == FloraMeshes.Kind.PINE
			TerrainNoise.Biome.SNOW:
				chance = 0.1
				kind = FloraMeshes.Kind.PINE if pick < 0.7 else FloraMeshes.Kind.DEAD_TREE
				snowy = kind == FloraMeshes.Kind.PINE
			TerrainNoise.Biome.DESERT:
				chance = 0.1
				kind = FloraMeshes.Kind.CACTUS if pick < 0.8 else FloraMeshes.Kind.DEAD_TREE
			TerrainNoise.Biome.MARSH:
				chance = 0.12
				kind = FloraMeshes.Kind.DEAD_TREE if pick < 0.5 else FloraMeshes.Kind.STUMP
			TerrainNoise.Biome.BEACH:
				chance = 0.1 if _noise.heat(x, z, ground) > 0.45 else 0.0
				kind = FloraMeshes.Kind.PALM
		if _rng.randf() > chance * forest_scale:
			return
		var scale := _rng.randf_range(0.8, 1.35)
		_add(kind, x, z, ground - 0.15, scale, _rng.randf_range(0.0, TAU), Color.WHITE,
				4 + _rng.randi() % 2 if snowy else -1)
		var footprint := FloraMeshes.footprint(kind)
		_add_shape(CylinderShape3D.new(), Vector3(x, ground + footprint.y * scale * 0.5, z),
				Vector3(footprint.x * scale, footprint.y * scale, footprint.x * scale)))


func _rocks() -> void:
	_grid(ROCK_SPACING, func(x: float, z: float, ground: float, biome: int, steep: float) -> void:
		if Vector2(x, z).length() < 10.0:
			return
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
		if _rng.randf() > chance * _settings.rock_density:
			return
		var scale := _rng.randf_range(0.5, 1.5) * big
		var kind := FloraMeshes.Kind.ROCK
		var variant := _rng.randi() % FloraMeshes.variant_count(kind)
		var yaw := _rng.randf_range(0.0, TAU)
		_add(kind, x, z, ground - scale * 0.15, scale, yaw, Color.WHITE, variant)
		var box := BoxShape3D.new()
		box.size = Vector3(1.7, 1.0, 1.5) * scale
		_add_shape(box, Vector3(x, ground + scale * 0.2, z), Vector3.ONE, yaw))


func _bushes() -> void:
	_grid(BUSH_SPACING, func(x: float, z: float, ground: float, biome: int, steep: float) -> void:
		var chance := 0.0
		match biome:
			TerrainNoise.Biome.FOREST:
				chance = 0.35
			TerrainNoise.Biome.MEADOW:
				chance = 0.12
			TerrainNoise.Biome.MARSH:
				chance = 0.2
		if steep > 0.5 or _rng.randf() > chance * _settings.tree_density:
			return
		_add(FloraMeshes.Kind.BUSH, x, z, ground - 0.05, _rng.randf_range(0.8, 1.6),
				_rng.randf_range(0.0, TAU), Color.WHITE))


func _grass() -> void:
	_grid(GRASS_SPACING, func(x: float, z: float, ground: float, biome: int, steep: float) -> void:
		var kind := FloraMeshes.Kind.GRASS
		var chance := 0.0
		match biome:
			TerrainNoise.Biome.MEADOW:
				chance = 0.95
			TerrainNoise.Biome.FOREST:
				chance = 0.5
			TerrainNoise.Biome.MARSH:
				chance = 0.6
				kind = FloraMeshes.Kind.REED if _rng.randf() < 0.45 else kind
			TerrainNoise.Biome.ROCKY:
				chance = 0.12
			TerrainNoise.Biome.DESERT:
				chance = 0.05
		if steep > 0.55 or _rng.randf() > chance * _settings.grass_density:
			return
		var dry := 1.0 - _noise.moisture(x, z)
		var tint := Color(1.0, 1.0, 1.0).lerp(Color(1.25, 1.05, 0.7), dry * 0.7)
		tint = tint.darkened(_rng.randf_range(0.0, 0.2))
		_add(kind, x, z, ground - 0.02, _rng.randf_range(0.7, 1.4), _rng.randf_range(0.0, TAU), tint))


func _flowers() -> void:
	_grid(FLOWER_SPACING, func(x: float, z: float, ground: float, biome: int, steep: float) -> void:
		if biome != TerrainNoise.Biome.MEADOW or steep > 0.4:
			return
		var patch := _noise.detail(x * 2.3, z * 2.3) # flowers come in patches
		if patch < 0.55 or _rng.randf() > 0.7:
			return
		_add(FloraMeshes.Kind.FLOWER, x, z, ground - 0.02, _rng.randf_range(0.8, 1.3),
				_rng.randf_range(0.0, TAU), Color.WHITE))


func _add(kind: FloraMeshes.Kind, x: float, z: float, ground: float, scale: float, yaw: float,
		tint: Color, variant := -1) -> void:
	if variant < 0:
		variant = _rng.randi() % FloraMeshes.variant_count(kind)
	var key := kind * 100 + variant
	if not _batches.has(key):
		_batches[key] = []
		_colors[key] = []
	var local := Vector3(x, ground, z) - _chunk.position
	(_batches[key] as Array).append(Transform3D(
			Basis(Vector3.UP, yaw).scaled(Vector3.ONE * scale), local))
	(_colors[key] as Array).append(tint)


func _add_shape(shape: Shape3D, at: Vector3, size := Vector3.ONE, yaw := 0.0) -> void:
	if shape is CylinderShape3D:
		(shape as CylinderShape3D).radius = size.x
		(shape as CylinderShape3D).height = size.y
	var collision := CollisionShape3D.new()
	collision.shape = shape
	collision.transform = Transform3D(Basis(Vector3.UP, yaw), at - _chunk.position)
	_body.add_child(collision)


func _flush(near: bool) -> void:
	for key: int in _batches.keys():
		var transforms: Array = _batches[key]
		var kind := key / 100 as FloraMeshes.Kind
		var variant := key % 100
		var multi := MultiMesh.new()
		multi.transform_format = MultiMesh.TRANSFORM_3D
		multi.use_colors = true
		multi.mesh = FloraMeshes.mesh(kind, variant, FloraMeshes.detailed)
		multi.instance_count = transforms.size()
		for index in transforms.size():
			multi.set_instance_transform(index, transforms[index])
			multi.set_instance_color(index, (_colors[key] as Array)[index])
		var instance := MultiMeshInstance3D.new()
		instance.multimesh = multi
		instance.set_meta(&"kind", kind)
		instance.set_meta(&"variant", variant)
		instance.add_to_group(&"world_flora")
		instance.material_override = FloraMeshes.material()
		if kind in [FloraMeshes.Kind.GRASS, FloraMeshes.Kind.FLOWER, FloraMeshes.Kind.REED]:
			instance.visibility_range_end = GRASS_VISIBLE
			instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		elif not near:
			instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_chunk.add_child(instance)


## Small ground cover close to the player: ferns and mushrooms in the forest, tall grass patches in
## the meadow, driftwood on the beach.
func _cover() -> void:
	_grid(2.6, func(x: float, z: float, ground: float, biome: int, steep: float) -> void:
		if steep > 0.5:
			return
		var kind := FloraMeshes.Kind.FERN
		var chance := 0.0
		match biome:
			TerrainNoise.Biome.FOREST:
				chance = 0.35
				kind = FloraMeshes.Kind.FERN if _rng.randf() < 0.8 else FloraMeshes.Kind.MUSHROOM
			TerrainNoise.Biome.MEADOW:
				chance = 0.5 if _noise.detail(x * 1.9, z * 1.9) > 0.62 else 0.0
				kind = FloraMeshes.Kind.TALL_GRASS
			TerrainNoise.Biome.MARSH:
				chance = 0.2
				kind = FloraMeshes.Kind.MUSHROOM
		if _rng.randf() > chance * _settings.grass_density:
			return
		_add(kind, x, z, ground - 0.03, _rng.randf_range(0.8, 1.4), _rng.randf_range(0.0, TAU),
				Color.WHITE))


## Bigger things that stand out from afar: fallen logs, rock spires, driftwood.
func _features() -> void:
	_grid(ROCK_SPACING * 1.4, func(x: float, z: float, ground: float, biome: int,
			steep: float) -> void:
		var kind := FloraMeshes.Kind.LOG
		var chance := 0.0
		match biome:
			TerrainNoise.Biome.FOREST:
				chance = 0.12
			TerrainNoise.Biome.BEACH:
				chance = 0.06
			TerrainNoise.Biome.ROCKY:
				chance = 0.16
				kind = FloraMeshes.Kind.SPIRE
			TerrainNoise.Biome.SNOW:
				chance = 0.16
				kind = FloraMeshes.Kind.SPIRE
			TerrainNoise.Biome.DESERT:
				chance = 0.1
				kind = FloraMeshes.Kind.SPIRE
		if Vector2(x, z).length() < 16.0 or _rng.randf() > chance * _settings.rock_density:
			return
		var scale := _rng.randf_range(0.8, 1.4)
		var yaw := _rng.randf_range(0.0, TAU)
		_add(kind, x, z, ground - 0.08, scale, yaw, Color.WHITE)
		var box := BoxShape3D.new()
		if kind == FloraMeshes.Kind.LOG:
			box.size = Vector3(3.6, 0.6, 0.6) * scale
		else:
			box.size = Vector3(1.6, 5.0, 1.6) * scale
		_add_shape(box, Vector3(x, ground + box.size.y * 0.4, z), Vector3.ONE, yaw))


func _set_grid(heights: PackedFloat32Array, step: float) -> void:
	_heights = heights
	_grid_step = step
	_grid_cells = int(round(sqrt(float(heights.size())))) - 1


## Ground height at a world point inside the tile, from the tile's own height grid.
func _grid_height(x: float, z: float) -> float:
	var fx := clampf((x - _chunk.position.x) / _grid_step, 0.0, float(_grid_cells) - 0.001)
	var fz := clampf((z - _chunk.position.z) / _grid_step, 0.0, float(_grid_cells) - 0.001)
	var column := int(fx)
	var row := int(fz)
	var stride := _grid_cells + 1
	var tx := fx - float(column)
	var tz := fz - float(row)
	var top := lerpf(_heights[row * stride + column], _heights[row * stride + column + 1], tx)
	var bottom := lerpf(_heights[(row + 1) * stride + column],
			_heights[(row + 1) * stride + column + 1], tx)
	return lerpf(top, bottom, tz)


## How steep the ground is there (0 flat .. 1 and more), from the grid cell it is in.
func _grid_slope(x: float, z: float) -> float:
	var column := clampi(int((x - _chunk.position.x) / _grid_step), 0, _grid_cells - 1)
	var row := clampi(int((z - _chunk.position.z) / _grid_step), 0, _grid_cells - 1)
	var stride := _grid_cells + 1
	var h00 := _heights[row * stride + column]
	var h10 := _heights[row * stride + column + 1]
	var h01 := _heights[(row + 1) * stride + column]
	var h11 := _heights[(row + 1) * stride + column + 1]
	var dx := (h10 - h00 + h11 - h01) / (2.0 * _grid_step)
	var dz := (h01 - h00 + h11 - h10) / (2.0 * _grid_step)
	return clampf(Vector2(dx, dz).length(), 0.0, 1.0)
