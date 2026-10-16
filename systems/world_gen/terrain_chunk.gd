class_name TerrainChunk
extends Node3D
## One square tile of ground. The mesh carries both looks: a flat colour per facet (low-poly) and
## smooth normals and per-vertex colours (realistic); the ground shader picks with `realism`.
## Near tiles are fine (the player walks on them): a height-field collider, plants and rocks from
## WorldScatter, rivers, structures. Far tiles are coarse scenery for the horizon: bigger facets, a
## skirt hiding the cracks to their finer neighbours, no collider, only cheap far trees.

const GROUND_SHADER := preload("res://shaders/world/ground_lowpoly.gdshader")
const FAR_FACTOR := 4 ## a far facet is this many near facets wide
const SKIRT := 4.0 ## m a far tile's edge hangs down

static var _ground_material: ShaderMaterial

var coord := Vector2i.ZERO
var far := false

var _noise: TerrainNoise
var _settings: WorldSettings
var _step := 2.0
var _padded := PackedFloat32Array() # heights with one extra sample around, for edge normals
var _cells := 0


## The ground shader material (made once, shared by every tile).
static func ground_material() -> ShaderMaterial:
	if _ground_material == null:
		_ground_material = ShaderMaterial.new()
		_ground_material.shader = GROUND_SHADER
	return _ground_material


## `near` false builds the coarse far version.
func build(chunk_coord: Vector2i, noise: TerrainNoise, near := true) -> TerrainChunk:
	coord = chunk_coord
	far = not near
	_noise = noise
	_settings = noise.settings
	_step = _settings.cell_size * (1.0 if near else float(FAR_FACTOR))
	name = "%s_%d_%d" % ["Chunk" if near else "Far", coord.x, coord.y]
	position = Vector3(float(coord.x), 0.0, float(coord.y)) * _settings.chunk_size
	_cells = int(round(_settings.chunk_size / _step))
	var heights := _sample_heights(_cells)
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.mesh = _build_mesh(heights, _cells)
	mesh_instance.material_override = ground_material()
	if far:
		mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mesh_instance)
	_add_lakes()
	if near:
		_add_rivers() # far tiles are too coarse for a channel a few metres wide
		add_child(_build_collider(heights, _cells))
		WorldScatter.new().populate(self, noise, true, heights, _step)
		var plan := WorldStructures.plan(coord, noise)
		if not plan.is_empty():
			WorldStructures.new().build(self, plan, _settings.world_seed)
	else:
		WorldScatter.new().populate_far(self, noise, heights, _step)
	return self


## (cells + 1)^2 heights, row by row along z (and the padded copy kept for the normals).
func _sample_heights(cells: int) -> PackedFloat32Array:
	var side := cells + 3
	_padded.resize(side * side)
	for row in side:
		for column in side:
			_padded[row * side + column] = _noise.height(
					position.x + float(column - 1) * _step, position.z + float(row - 1) * _step)
	var heights := PackedFloat32Array()
	heights.resize((cells + 1) * (cells + 1))
	for row in cells + 1:
		for column in cells + 1:
			heights[row * (cells + 1) + column] = _padded[(row + 1) * side + column + 1]
	return heights


## The smooth normal of the grid point (column, row), from the padded heights around it.
func _vertex_normal(column: int, row: int) -> Vector3:
	var side := _cells + 3
	var left := _padded[(row + 1) * side + column]
	var right := _padded[(row + 1) * side + column + 2]
	var up := _padded[row * side + column + 1]
	var down := _padded[(row + 2) * side + column + 1]
	return Vector3(left - right, 2.0 * _step, up - down).normalized()


func _build_mesh(heights: PackedFloat32Array, cells: int) -> ArrayMesh:
	var builder := MeshBuilder.new()
	var stride := cells + 1
	# per grid point: the smooth normal and the palette colour there (once, not per triangle)
	var normals: Array[Vector3] = []
	var smooth: Array[Color] = []
	for row in stride:
		for column in stride:
			var normal := _vertex_normal(column, row)
			normals.append(normal)
			smooth.append(TerrainColors.facet(_noise, position.x + float(column) * _step,
					position.z + float(row) * _step, heights[row * stride + column],
					1.0 - normal.y))
	for row in cells:
		for column in cells:
			var i00 := row * stride + column
			var i10 := i00 + 1
			var i01 := i00 + stride
			var i11 := i01 + 1
			var x0 := float(column) * _step
			var z0 := float(row) * _step
			var p00 := Vector3(x0, heights[i00], z0)
			var p10 := Vector3(x0 + _step, heights[i10], z0)
			var p01 := Vector3(x0, heights[i01], z0 + _step)
			var p11 := Vector3(x0 + _step, heights[i11], z0 + _step)
			# Every cell is split along p10-p01, because that is how the physics heightmap
			# (HeightMapShape3D) splits it. A mesh that picked its own diagonal per cell showed
			# the ground 10-40 cm away from the ground the feet and the capsule stand on.
			_triangle(builder, [p00, p01, p10], [i00, i01, i10], normals, smooth)
			_triangle(builder, [p10, p01, p11], [i10, i01, i11], normals, smooth)
	if far:
		_skirt(builder, heights, cells)
	return builder.commit()


func _triangle(builder: MeshBuilder, points: Array, indices: Array, normals: Array[Vector3],
		smooth: Array[Color]) -> void:
	var a: Vector3 = points[0]
	var b: Vector3 = points[1]
	var c: Vector3 = points[2]
	var corner_normals: Array[Vector3] = [normals[indices[0]], normals[indices[1]],
			normals[indices[2]]]
	var corner_colors: Array[Color] = [smooth[indices[0]], smooth[indices[1]],
			smooth[indices[2]]]
	builder.add_tri_smooth(a, b, c, _facet_color(a, b, c), corner_normals, corner_colors)


## Walls hanging under the four edges of a far tile.
func _skirt(builder: MeshBuilder, heights: PackedFloat32Array, cells: int) -> void:
	var stride := cells + 1
	var drop := Vector3(0.0, -SKIRT, 0.0)
	var length := _step * float(cells)
	for index in cells:
		var along := float(index) * _step
		var next := along + _step
		var color := TerrainColors.facet(_noise, position.x + along, position.z, heights[index], 0.3)
		# north (z = 0), then south, west and east; every wall faces away from the tile
		var a := Vector3(along, heights[index], 0.0)
		var b := Vector3(next, heights[index + 1], 0.0)
		_wall(builder, b, a, drop, color)
		a = Vector3(along, heights[cells * stride + index], length)
		b = Vector3(next, heights[cells * stride + index + 1], length)
		_wall(builder, a, b, drop, color)
		a = Vector3(0.0, heights[index * stride], along)
		b = Vector3(0.0, heights[(index + 1) * stride], next)
		_wall(builder, a, b, drop, color)
		a = Vector3(length, heights[index * stride + cells], along)
		b = Vector3(length, heights[(index + 1) * stride + cells], next)
		_wall(builder, b, a, drop, color)


func _wall(builder: MeshBuilder, a: Vector3, b: Vector3, drop: Vector3, color: Color) -> void:
	var normal := (b - a).cross(drop).normalized()
	var normals: Array[Vector3] = [normal, normal, normal]
	var colors: Array[Color] = [color, color, color]
	builder.add_tri_smooth(a, b, b + drop, color, normals, colors)
	builder.add_tri_smooth(a, b + drop, a + drop, color, normals, colors)


func _facet_color(a: Vector3, b: Vector3, c: Vector3) -> Color:
	var middle := (a + b + c) / 3.0
	var normal := (b - a).cross(c - a).normalized()
	return TerrainColors.facet(_noise, position.x + middle.x, position.z + middle.z, middle.y,
			1.0 - absf(normal.y))


func _build_collider(heights: PackedFloat32Array, cells: int) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	var shape := HeightMapShape3D.new()
	shape.map_width = cells + 1
	shape.map_depth = cells + 1
	shape.set(&"map_data", heights) # float32 or float64 array, whichever build (double precision)
	var collision := CollisionShape3D.new()
	collision.shape = shape
	body.add_child(collision)
	# the shape is centred on its node and spaced one unit per sample
	body.scale = Vector3(_step, 1.0, _step)
	body.position = Vector3(_settings.chunk_size * 0.5, 0.0, _settings.chunk_size * 0.5)
	return body


## The water of every lake whose middle lies in this tile (a lake may reach over the tile border).
func _add_lakes() -> void:
	var cell := Vector2i(floori(position.x / TerrainNoise.LAKE_CELL),
			floori(position.z / TerrainNoise.LAKE_CELL))
	var size := _settings.chunk_size
	for dz in range(-1, 2):
		for dx in range(-1, 2):
			var lake := _noise.lake_in(cell + Vector2i(dx, dz))
			if lake.is_empty():
				continue
			var center: Vector2 = lake["center"]
			if center.x < position.x or center.x >= position.x + size \
					or center.y < position.z or center.y >= position.z + size:
				continue
			var surface := WorldWater.lake_surface(float(lake["radius"]) * 1.02)
			surface.position = Vector3(center.x - position.x, float(lake["level"]),
					center.y - position.z)
			add_child(surface)


## The river water running through this tile (flat strips under the carved channels).
func _add_rivers() -> void:
	var origin := Vector2(position.x, position.z)
	var surface := WorldWater.river_surface(_noise.rivers.segments_in(origin, _settings.chunk_size),
			origin)
	if surface != null:
		add_child(surface)
		for segment: Array in _noise.rivers.segments_in(origin, _settings.chunk_size):
			var drop := float(segment[2]) - float(segment[3])
			var middle := (segment[0] as Vector2).lerp(segment[1] as Vector2, 0.5)
			if drop > 2.2 and middle.x >= origin.x and middle.x < origin.x + _settings.chunk_size \
					and middle.y >= origin.y and middle.y < origin.y + _settings.chunk_size:
				var mist := WaterfallMist.new()
				mist.position = Vector3(middle.x - origin.x, float(segment[3]) + 0.8, middle.y - origin.y)
				add_child(mist)
