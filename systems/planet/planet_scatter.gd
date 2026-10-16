class_name PlanetScatter
extends RefCounted
## The plants of one planet tile: the same species and the same rules as the flat world's
## WorldScatter (each layer on a jittered grid, the species whose niche fits the spot best the
## likeliest), but the niche is read from the planet's climate: moisture from the rain, warmth from
## the temperature at the spot's height (so trees thin out and stop up a mountain), and the slope.
## Plants stand upright in the tile's own frame (a tile is small, so its "up" is the plant's up).
## Everything is drawn with one MultiMesh per species and variant, in the tile's local space.

const GRASS_VISIBLE := 110.0
const SPACING := {
	PlantSpecies.Layer.CANOPY: 6.5, PlantSpecies.Layer.UNDERSTORY: 5.0,
	PlantSpecies.Layer.GRASS: 1.7, PlantSpecies.Layer.MEADOW: 3.2, PlantSpecies.Layer.COVER: 2.6,
}
const MAX_CHANCE := {
	PlantSpecies.Layer.CANOPY: 0.85, PlantSpecies.Layer.UNDERSTORY: 0.4,
	PlantSpecies.Layer.GRASS: 0.95, PlantSpecies.Layer.MEADOW: 0.7, PlantSpecies.Layer.COVER: 0.5,
}
const PLANT_KEY := 100000

enum Detail { NONE, TREES, ALL }

var _tile: Node3D
var _noise: PlanetNoise
var _species: SpeciesRegistry
var _rng := RandomNumberGenerator.new()
var _batches: Dictionary = {} # key -> Array[Transform3D]
var _colors: Dictionary = {} # key -> Array[Color]
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


## Plants the tile. `grid` is the tile's padded grid (see PlanetTile.build): local positions,
## directions from the planet's centre and heights, `cells` quads along an edge.
func populate(tile: Node3D, noise: PlanetNoise, positions: Array[Vector3], dirs: Array[Vector3],
		heights: PackedFloat32Array, cells: int, size: float, detail: Detail,
		collide: bool) -> void:
	_tile = tile
	_noise = noise
	_species = noise.species
	_positions = positions
	_dirs = dirs
	_heights = heights
	_cells = cells
	_side = cells + 3
	_size = size
	var key: int = tile.get("tile_key")
	_rng.seed = hash(Vector2i(noise.settings.world_seed, key))
	if collide:
		_body = StaticBody3D.new()
		_body.collision_layer = 1
		_body.name = "Plants"
		tile.add_child(_body)
	_scatter(PlantSpecies.Layer.CANOPY, 1.0 if detail == Detail.ALL else 2.0)
	_scatter(PlantSpecies.Layer.UNDERSTORY, 1.0 if detail == Detail.ALL else 2.0)
	if detail == Detail.ALL:
		_scatter(PlantSpecies.Layer.GRASS, 1.0)
		_scatter(PlantSpecies.Layer.MEADOW, 1.0)
		_scatter(PlantSpecies.Layer.COVER, 1.0)
	_flush(detail == Detail.ALL)


## One layer of plants over the tile (`stretch` widens the grid: a far tile has fewer, bigger gaps).
func _scatter(layer: PlantSpecies.Layer, stretch: float) -> void:
	var spacing: float = SPACING[layer] * stretch
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
			if _noise.hydrology != null and _noise.hydrology.water_at(dir, ground) > ground - 0.3:
				continue # a river or a lake
			var plant := _pick(layer, dir, ground, steep, x, z)
			if plant != null and _rng.randf() <= _pick_chance * density:
				_place(plant, at)


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


func _place(plant: PlantSpecies, at: Vector3) -> void:
	var scale := 1.0 + _rng.randf_range(-plant.size_spread, plant.size_spread)
	var yaw := _rng.randf_range(0.0, TAU)
	var variant := _rng.randi() % plant.variants
	var tint := Color.WHITE
	if plant.layer() == PlantSpecies.Layer.GRASS:
		tint = Color(1.0, 1.0, 1.0).lerp(Color(1.25, 1.05, 0.7), (1.0 - _wet) * 0.7)
		tint = tint.darkened(_rng.randf_range(0.0, 0.2))
	else:
		var shade := _rng.randf_range(0.9, 1.1)
		tint = Color(shade, shade * _rng.randf_range(0.97, 1.03), shade)
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
	for key: int in _batches.keys():
		var transforms: Array = _batches[key]
		var id := (key - PLANT_KEY) / 100
		var variant := key % 100
		var layer := _species.by_id(id).layer()
		var multi := MultiMesh.new()
		multi.transform_format = MultiMesh.TRANSFORM_3D
		multi.use_colors = true
		multi.mesh = _species.mesh(id, variant, FloraMeshes.detailed, 0)
		multi.instance_count = transforms.size()
		for index in transforms.size():
			multi.set_instance_transform(index, transforms[index])
			multi.set_instance_color(index, (_colors[key] as Array)[index])
		var instance := MultiMeshInstance3D.new()
		instance.multimesh = multi
		instance.material_override = FloraMeshes.material()
		if layer == PlantSpecies.Layer.GRASS or layer == PlantSpecies.Layer.MEADOW:
			instance.visibility_range_end = GRASS_VISIBLE
			instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		elif not near:
			instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_tile.add_child(instance)


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
