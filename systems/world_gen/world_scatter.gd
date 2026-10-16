class_name WorldScatter
extends RefCounted
## Puts the plants and rocks on one terrain tile. Plants are the world's species (SpeciesRegistry):
## each layer (trees, shrubs, grass, flowers, ground cover) is laid out on a jittered grid so it
## looks random but never clumps into a pile. At every point the species that fits the spot best
## (its moisture, warmth, height above the water and slope against the species' niche) is the
## likeliest to grow there. Everything is drawn with one MultiMesh per species and variant.
## Trunks and rocks also get a simple collider. The dice are seeded by the tile, so the same tile
## always grows the same things.

const GRASS_VISIBLE := 110.0 ## m the small plants stay drawn
const ROCK_SPACING := 10.0
const SPACING := {
	PlantSpecies.Layer.CANOPY: 6.5, PlantSpecies.Layer.UNDERSTORY: 5.0,
	PlantSpecies.Layer.GRASS: 1.7, PlantSpecies.Layer.MEADOW: 3.2, PlantSpecies.Layer.COVER: 2.6,
}
## The most crowded a layer gets (the old per-biome maximums): species that fit add up to this.
const MAX_CHANCE := {
	PlantSpecies.Layer.CANOPY: 0.85, PlantSpecies.Layer.UNDERSTORY: 0.4,
	PlantSpecies.Layer.GRASS: 0.95, PlantSpecies.Layer.MEADOW: 0.7, PlantSpecies.Layer.COVER: 0.5,
}
## Batch keys: a rock or log is kind * 100 + variant; a species' mesh is PLANT_KEY + id * 100 +
## variant; its horizon version FAR_KEY + id * 100 + variant.
const PLANT_KEY := 100000
const FAR_KEY := 200000

## Where the player is (x, z), kept up to date by the world: a tile builds its trees in the version
## that suits its distance from here (WorldSettings.tree_lod_distance). Read from the tile workers.
static var focus := Vector2.ZERO

var _noise: TerrainNoise
var _settings: WorldSettings
var _species: SpeciesRegistry
var _chunk: Node3D
var _rng := RandomNumberGenerator.new()
var _batches: Dictionary = {} # key -> Array[Transform3D]
var _colors: Dictionary = {} # same key -> Array[Color]
var _body: StaticBody3D
var _heights := PackedFloat32Array() # the tile's height grid, so no point needs its own noise
var _grid_step := 2.0
var _grid_cells := 0
var _clearing: Dictionary = {} # the structure of this tile (trees and rocks keep off it)
var _water_here := 0.0 # water level at the grid point being visited
var _weights: Array[float] = []
var _pick_chance := 0.0 # how well the species picked last fits its spot (0..1)
var _wet_here := 0.0 # moisture at that spot


## A far (horizon) tile: only sparse, very cheap trees, no colliders.
func populate_far(chunk: Node3D, noise: TerrainNoise, heights: PackedFloat32Array,
		step: float) -> void:
	_set_grid(heights, step)
	_chunk = chunk
	_noise = noise
	_settings = noise.settings
	_species = SpeciesRegistry.for_settings(_settings)
	var coord: Vector2i = chunk.get("coord")
	_rng.seed = hash(Vector3i(_settings.world_seed, coord.x, coord.y))
	_body = null
	_grid(13.0, func(x: float, z: float, ground: float, _biome: int, steep: float) -> void:
		var tree := _pick(PlantSpecies.Layer.CANOPY, x, z, ground, steep)
		if tree == null or not PlantMeshes.has_far(tree) \
				or _rng.randf() > _pick_chance * _settings.tree_density:
			return
		_add_plant(tree, _rng.randi() % 2, x, z, ground - 0.2, _rng.randf_range(0.8, 1.3),
				_rng.randf_range(0.0, TAU), Color.WHITE, true), false)
	_flush(false)


func populate(chunk: Node3D, noise: TerrainNoise, near: bool, heights: PackedFloat32Array,
		step: float) -> void:
	_set_grid(heights, step)
	_chunk = chunk
	_noise = noise
	_settings = noise.settings
	_species = SpeciesRegistry.for_settings(_settings)
	var coord: Vector2i = chunk.get("coord")
	_rng.seed = hash(Vector3i(_settings.world_seed, coord.x, coord.y))
	_clearing = WorldStructures.plan(coord, noise)
	_body = StaticBody3D.new()
	_body.collision_layer = 1
	chunk.add_child(_body)
	_scatter(PlantSpecies.Layer.CANOPY)
	_rocks()
	_scatter(PlantSpecies.Layer.UNDERSTORY)
	if near:
		_scatter(PlantSpecies.Layer.GRASS)
		_scatter(PlantSpecies.Layer.MEADOW)
		_scatter(PlantSpecies.Layer.COVER)
	_features()
	_flush(near)


## Calls `place.call(world_x, world_z, ground, biome, steep)` for each jittered grid point. The
## biome is only worked out when `with_biome` is set (rocks and features use it; plants do not).
func _grid(spacing: float, place: Callable, with_biome := true) -> void:
	var size := _settings.chunk_size
	var count := int(size / spacing)
	var origin := _chunk.position
	for row in count:
		for column in count:
			var x := origin.x + (float(column) + _rng.randf()) * spacing
			var z := origin.z + (float(row) + _rng.randf()) * spacing
			var ground := _grid_height(x, z)
			_water_here = _noise.water_level(x, z)
			if ground < _water_here + 0.9:
				continue
			if not _clearing.is_empty() and Vector2(x, z).distance_to(Vector2(
					(_clearing["position"] as Vector3).x, (_clearing["position"] as Vector3).z)) \
					< float(_clearing["radius"]):
				continue
			var steep := _grid_slope(x, z)
			place.call(x, z, ground, _noise.biome(x, z, ground, steep) if with_biome else -1, steep)


## One layer of plants over the tile.
func _scatter(layer: PlantSpecies.Layer) -> void:
	var density := _settings.tree_density if layer <= PlantSpecies.Layer.UNDERSTORY \
			else _settings.grass_density
	_grid(SPACING[layer], func(x: float, z: float, ground: float, _biome: int, steep: float) -> void:
		if layer == PlantSpecies.Layer.CANOPY and Vector2(x, z).length() < 14.0:
			return # the spawn clearing
		var plant := _pick(layer, x, z, ground, steep)
		if plant != null and _rng.randf() <= _pick_chance * density:
			_place(plant, x, z, ground), false)


## The species of `layer` that grows at this spot, chosen at random in proportion to how well each
## fits (and how many of it its niche allows), or null for bare ground. Sets `_pick_chance`: the
## chance that anything is planted here at all (the species that fit add up, up to the layer's cap).
func _pick(layer: PlantSpecies.Layer, x: float, z: float, ground: float,
		steep: float) -> PlantSpecies:
	_wet_here = _noise.moisture(x, z)
	var warm := _noise.heat(x, z, ground)
	var above := ground - _water_here
	var candidates := _species.in_layer(layer)
	_weights.resize(candidates.size())
	var total := 0.0
	for index in candidates.size():
		var one := candidates[index]
		var weight := one.fitness(_wet_here, warm, above, steep) * one.density
		if weight > 0.003 and one.patch_strength > 0.0: # some plants only grow in clumps
			var patch := _noise.detail(x * one.patch_freq + one.patch_offset.x,
					z * one.patch_freq + one.patch_offset.y)
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


## Plants one plant of `plant`: size, turn, mesh variant and colour all differ from its neighbours.
func _place(plant: PlantSpecies, x: float, z: float, ground: float) -> void:
	var scale := 1.0 + _rng.randf_range(-plant.size_spread, plant.size_spread)
	var yaw := _rng.randf_range(0.0, TAU)
	var variant := _rng.randi() % plant.variants
	var tint := Color.WHITE
	if plant.layer() == PlantSpecies.Layer.GRASS: # dry ground browns the grass
		tint = Color(1.0, 1.0, 1.0).lerp(Color(1.25, 1.05, 0.7), (1.0 - _wet_here) * 0.7)
		tint = tint.darkened(_rng.randf_range(0.0, 0.2))
	else:
		var shade := _rng.randf_range(0.9, 1.1)
		tint = Color(shade, shade * _rng.randf_range(0.97, 1.03), shade)
	_add_plant(plant, variant, x, z, ground - (0.15 if plant.is_tree() else 0.03), scale, yaw, tint)
	var foot := plant.footprint() # trunks stop the player; the rest can be walked through
	if foot != Vector2.ZERO:
		_add_shape(CylinderShape3D.new(), Vector3(x, ground + foot.y * scale * 0.5, z),
				Vector3(foot.x * scale, foot.y * scale, foot.x * scale))


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


## Bigger things that stand out from afar: fallen logs, stumps, rock spires, driftwood.
func _features() -> void:
	_grid(ROCK_SPACING * 1.4, func(x: float, z: float, ground: float, biome: int,
			steep: float) -> void:
		var kind := FloraMeshes.Kind.LOG
		var chance := 0.0
		match biome:
			TerrainNoise.Biome.FOREST:
				chance = 0.16
				kind = FloraMeshes.Kind.LOG if _rng.randf() < 0.6 else FloraMeshes.Kind.STUMP
			TerrainNoise.Biome.MARSH:
				chance = 0.1
				kind = FloraMeshes.Kind.STUMP
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
		elif kind == FloraMeshes.Kind.STUMP:
			box.size = Vector3(0.8, 0.8, 0.8) * scale
		else:
			box.size = Vector3(1.6, 5.0, 1.6) * scale
		_add_shape(box, Vector3(x, ground + box.size.y * 0.4, z), Vector3.ONE, yaw))


func _add(kind: FloraMeshes.Kind, x: float, z: float, ground: float, scale: float, yaw: float,
		tint: Color, variant := -1) -> void:
	if variant < 0:
		variant = _rng.randi() % FloraMeshes.variant_count(kind)
	_queue(kind * 100 + variant, x, z, ground, scale, yaw, tint)


func _add_plant(plant: PlantSpecies, variant: int, x: float, z: float, ground: float, scale: float,
		yaw: float, tint: Color, far := false) -> void:
	_queue((FAR_KEY if far else PLANT_KEY) + plant.id * 100 + variant, x, z, ground, scale, yaw, tint)


func _queue(key: int, x: float, z: float, ground: float, scale: float, yaw: float,
		tint: Color) -> void:
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

## 1 (the lighter tree) when this tile is further from the player than tree_lod_distance, else 0.
func _tree_lod() -> int:
	var size := _settings.chunk_size
	var coord: Vector2i = _chunk.get("coord")
	var middle := Vector2((float(coord.x) + 0.5) * size, (float(coord.y) + 0.5) * size)
	return 1 if middle.distance_to(focus) > _settings.tree_lod_distance else 0


func _flush(near: bool) -> void:
	for key: int in _batches.keys():
		var transforms: Array = _batches[key]
		var multi := MultiMesh.new()
		multi.transform_format = MultiMesh.TRANSFORM_3D
		multi.use_colors = true
		var instance := MultiMeshInstance3D.new()
		var short_range := false # small plants are only drawn near the player
		if key >= FAR_KEY:
			var id := (key - FAR_KEY) / 100
			multi.mesh = _species.far_mesh(id, key % 100)
		elif key >= PLANT_KEY:
			var id := (key - PLANT_KEY) / 100
			var variant := key % 100
			var layer := _species.by_id(id).layer()
			var lod := _tree_lod() if layer == PlantSpecies.Layer.CANOPY else 0
			multi.mesh = _species.mesh(id, variant, FloraMeshes.detailed, lod)
			instance.set_meta(&"species", id)
			instance.set_meta(&"variant", variant)
			instance.set_meta(&"lod", lod)
			instance.set_meta(&"tree", layer == PlantSpecies.Layer.CANOPY)
			instance.add_to_group(&"world_flora")
			short_range = layer == PlantSpecies.Layer.GRASS or layer == PlantSpecies.Layer.MEADOW
		else:
			var kind := key / 100 as FloraMeshes.Kind
			multi.mesh = FloraMeshes.mesh(kind, key % 100, FloraMeshes.detailed)
			instance.set_meta(&"kind", kind)
			instance.set_meta(&"variant", key % 100)
			instance.add_to_group(&"world_flora")
		multi.instance_count = transforms.size()
		for index in transforms.size():
			multi.set_instance_transform(index, transforms[index])
			multi.set_instance_color(index, (_colors[key] as Array)[index])
		instance.multimesh = multi
		instance.material_override = FloraMeshes.material()
		if short_range:
			instance.visibility_range_end = GRASS_VISIBLE
			instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		elif not near:
			instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_chunk.add_child(instance)


func _set_grid(heights: PackedFloat32Array, step: float) -> void:
	_heights = heights
	_grid_step = step
	_grid_cells = int(round(sqrt(float(heights.size())))) - 1


## Ground height at a world point inside the tile, from the tile's own height grid, on the same
## triangles the terrain mesh and the physics heightmap use (each cell split along p10-p01), so a
## plant stands on the visible ground and not a few centimetres off it.
func _grid_height(x: float, z: float) -> float:
	var fx := clampf((x - _chunk.position.x) / _grid_step, 0.0, float(_grid_cells) - 0.001)
	var fz := clampf((z - _chunk.position.z) / _grid_step, 0.0, float(_grid_cells) - 0.001)
	var column := int(fx)
	var row := int(fz)
	var stride := _grid_cells + 1
	var tx := fx - float(column)
	var tz := fz - float(row)
	var h00 := _heights[row * stride + column]
	var h10 := _heights[row * stride + column + 1]
	var h01 := _heights[(row + 1) * stride + column]
	var h11 := _heights[(row + 1) * stride + column + 1]
	if tx + tz <= 1.0:
		return h00 + (h10 - h00) * tx + (h01 - h00) * tz
	return h11 + (h01 - h11) * (1.0 - tx) + (h10 - h11) * (1.0 - tz)


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
