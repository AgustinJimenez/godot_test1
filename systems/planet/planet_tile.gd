class_name PlanetTile
extends Node3D
## One square patch of a planet's ground: a cell of one of the six cube faces, bent onto the sphere.
## The mesh is built around the patch's own centre (so its numbers stay small, however big the
## planet), and the node's transform places it in the world (see PlanetFrame). The finest tiles also
## get a collider. Every tile has the same number of quads, so a tile twice as big has quads twice
## as wide: the same code makes the near ground and the horizon.

const FACES: Array[Array] = [ # [normal, u, v] of the six cube faces (u x v = normal)
	[Vector3(1, 0, 0), Vector3(0, 0, -1), Vector3(0, 1, 0)],
	[Vector3(-1, 0, 0), Vector3(0, 0, 1), Vector3(0, 1, 0)],
	[Vector3(0, 1, 0), Vector3(1, 0, 0), Vector3(0, 0, -1)],
	[Vector3(0, -1, 0), Vector3(1, 0, 0), Vector3(0, 0, 1)],
	[Vector3(0, 0, 1), Vector3(1, 0, 0), Vector3(0, 1, 0)],
	[Vector3(0, 0, -1), Vector3(-1, 0, 0), Vector3(0, 1, 0)],
]

var face := 0
var level := 0
var tile_x := 0
var tile_y := 0
var centre := Vector3.ZERO ## unit direction of the tile's middle (planet space)
var origin := PackedFloat64Array([0.0, 0.0, 0.0]) ## planet space position of the tile's middle (m)
var local_basis := Basis.IDENTITY ## the tile's axes in planet space: y is up
var size := 0.0 ## m, along one edge
var has_collider := false
var min_height := 0.0

var _noise: PlanetNoise
var _settings: PlanetSettings
var _e1 := Vector3.ZERO # the tile's axes as unit vectors, for the maths below
var _e3 := Vector3.ZERO


## The tile key: (face, level, x, y) packed in one int.
static func key_of(f: int, lvl: int, x: int, y: int) -> int:
	return (((f * 16 + lvl) << 20) | (x << 10)) | y


## Direction on the planet of the cube face point (s, t), both -1..1.
static func direction(f: int, s: float, t: float) -> Vector3:
	var axes: Array = FACES[f]
	var a := tan(s * PI * 0.25)
	var b := tan(t * PI * 0.25)
	var v: Vector3 = (axes[0] as Vector3) + (axes[1] as Vector3) * a + (axes[2] as Vector3) * b
	return v.normalized()


## Builds the tile (on any thread). `collide`: also build the collider (the player walks here).
func build(f: int, lvl: int, x: int, y: int, noise: PlanetNoise, collide: bool) -> PlanetTile:
	face = f
	level = lvl
	tile_x = x
	tile_y = y
	_noise = noise
	_settings = noise.settings
	var radius := _settings.radius
	var count := 1 << level
	var s0 := -1.0 + 2.0 * float(x) / float(count)
	var s1 := -1.0 + 2.0 * float(x + 1) / float(count)
	var t0 := -1.0 + 2.0 * float(y) / float(count)
	var t1 := -1.0 + 2.0 * float(y + 1) / float(count)
	centre = direction(f, (s0 + s1) * 0.5, (t0 + t1) * 0.5)
	origin = PackedFloat64Array([centre.x * radius, centre.y * radius, centre.z * radius])
	var axes: Array = FACES[f]
	var u: Vector3 = axes[1]
	_e1 = (u - centre * u.dot(centre)).normalized()
	_e3 = _e1.cross(centre)
	local_basis = Basis(_e1, centre, _e3)
	size = (direction(f, s0, (t0 + t1) * 0.5) - direction(f, s1, (t0 + t1) * 0.5)).length() * radius
	name = "Tile_%d_%d_%d_%d" % [f, lvl, x, y]
	var cells := _settings.tile_cells
	var side := cells + 3
	# padded grid of local positions (one extra ring round the tile, for the edge normals)
	var positions: Array[Vector3] = []
	var heights := PackedFloat32Array()
	var dirs: Array[Vector3] = []
	positions.resize(side * side)
	heights.resize(side * side)
	dirs.resize(side * side)
	min_height = INF
	for row in side:
		var t := lerpf(t0, t1, float(row - 1) / float(cells))
		for column in side:
			var s := lerpf(s0, s1, float(column - 1) / float(cells))
			var dir := direction(f, s, t)
			var h := noise.height(dir.x, dir.y, dir.z)
			dirs[row * side + column] = dir
			heights[row * side + column] = h
			positions[row * side + column] = _to_local(dir, radius + h)
			if row > 0 and column > 0 and row <= cells + 1 and column <= cells + 1:
				min_height = minf(min_height, h)
	var normals: Array[Vector3] = []
	normals.resize(side * side)
	for row in range(1, cells + 2):
		for column in range(1, cells + 2):
			var along := positions[row * side + column + 1] - positions[row * side + column - 1]
			var down := positions[(row + 1) * side + column] - positions[(row - 1) * side + column]
			var normal := along.cross(down).normalized()
			normals[row * side + column] = normal if normal.y >= 0.0 else -normal
	var colors: Array[Color] = []
	colors.resize(side * side)
	for row in range(1, cells + 2):
		for column in range(1, cells + 2):
			var index := row * side + column
			var dir := dirs[index]
			colors[index] = _noise.facet_color(dir.x, dir.y, dir.z, heights[index],
					1.0 - normals[index].y)
	var builder := MeshBuilder.new()
	var faces := PackedVector3Array()
	for row in range(1, cells + 1):
		for column in range(1, cells + 1):
			var i00 := row * side + column
			var i10 := i00 + 1
			var i01 := i00 + side
			var i11 := i01 + 1
			_triangle(builder, faces, [i00, i01, i10], positions, normals, colors, dirs, heights)
			_triangle(builder, faces, [i10, i01, i11], positions, normals, colors, dirs, heights)
	if not collide:
		_skirt(builder, positions, colors, cells)
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.mesh = builder.commit()
	mesh_instance.material_override = TerrainChunk.ground_material()
	if not collide and level < _settings.max_level() - 1:
		mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mesh_instance)
	if min_height < _settings.sea_level + 0.5:
		_add_sea(dirs, side, cells)
	if collide:
		has_collider = true
		var body := StaticBody3D.new()
		body.collision_layer = 1
		var collision := CollisionShape3D.new()
		var shape := ConcavePolygonShape3D.new()
		shape.set_faces(faces)
		collision.shape = shape
		body.add_child(collision)
		add_child(body)
	return self


## The planet space direction `dir` at distance `reach` from the centre, as a position in this
## tile's own axes, measured from the tile's middle (in doubles, so exact on a huge planet).
func _to_local(dir: Vector3, reach: float) -> Vector3:
	var dx := float(dir.x) * reach - origin[0]
	var dy := float(dir.y) * reach - origin[1]
	var dz := float(dir.z) * reach - origin[2]
	return Vector3(dx * _e1.x + dy * _e1.y + dz * _e1.z,
			dx * centre.x + dy * centre.y + dz * centre.z,
			dx * _e3.x + dy * _e3.y + dz * _e3.z)


func _triangle(builder: MeshBuilder, faces: PackedVector3Array, ids: Array,
		positions: Array[Vector3], normals: Array[Vector3], colors: Array[Color],
		dirs: Array[Vector3], heights: PackedFloat32Array) -> void:
	var a := positions[ids[0]]
	var b := positions[ids[1]]
	var c := positions[ids[2]]
	var first := 1
	var second := 2
	# the builder wants the corners counter clockwise seen from above; swap if this one is not
	if (b - a).cross(c - a).y < 0.0:
		b = positions[ids[2]]
		c = positions[ids[1]]
		first = 2
		second = 1
	faces.append_array([a, c, b]) # clockwise from above is the front face: solid from above
	var middle := (dirs[ids[0]] + dirs[ids[1]] + dirs[ids[2]]).normalized()
	var normal := (b - a).cross(c - a).normalized()
	var height := (heights[ids[0]] + heights[ids[1]] + heights[ids[2]]) / 3.0
	var flat := _noise.facet_color(middle.x, middle.y, middle.z, height, 1.0 - absf(normal.y))
	var corner_normals: Array[Vector3] = [normals[ids[0]], normals[ids[first]], normals[ids[second]]]
	var corner_colors: Array[Color] = [colors[ids[0]], colors[ids[first]], colors[ids[second]]]
	builder.add_tri_smooth(a, b, c, flat, corner_normals, corner_colors)


## Walls hanging under the four edges, hiding the cracks to a neighbour of another size.
func _skirt(builder: MeshBuilder, positions: Array[Vector3], colors: Array[Color],
		cells: int) -> void:
	var side := cells + 3
	var drop := Vector3(0.0, -maxf(size * 0.04, 2.0), 0.0)
	var edges: Array[Vector2i] = []
	for index in cells:
		edges.append(Vector2i(side + 1 + index, side + 2 + index)) # first row
		edges.append(Vector2i((cells + 1) * side + 1 + index, (cells + 1) * side + 2 + index))
		edges.append(Vector2i((1 + index) * side + 1, (2 + index) * side + 1)) # first column
		edges.append(Vector2i((1 + index) * side + cells + 1, (2 + index) * side + cells + 1))
	for edge in edges:
		var a := positions[edge.x]
		var b := positions[edge.y]
		var colour := colors[edge.x]
		var wall_normal := (b - a).cross(drop).normalized()
		var wall_normals: Array[Vector3] = [wall_normal, wall_normal, wall_normal]
		var back_normals: Array[Vector3] = [-wall_normal, -wall_normal, -wall_normal]
		var wall_colors: Array[Color] = [colour, colour, colour]
		# both faces of the wall, so it hides the crack whichever side the neighbour is on
		builder.add_tri_smooth(a, b, b + drop, colour, wall_normals, wall_colors)
		builder.add_tri_smooth(a, b + drop, a + drop, colour, wall_normals, wall_colors)
		builder.add_tri_smooth(a, b + drop, b, colour, back_normals, wall_colors)
		builder.add_tri_smooth(a, a + drop, b + drop, colour, back_normals, wall_colors)


## The sea over this tile: a coarse patch at sea level, bent like the ground.
func _add_sea(dirs: Array[Vector3], side: int, cells: int) -> void:
	var steps := 12
	var builder := MeshBuilder.new()
	var grid: Array[Vector3] = []
	for row in steps + 1:
		for column in steps + 1:
			var index := (1 + row * cells / steps) * side + 1 + column * cells / steps
			grid.append(_to_local(dirs[index], _settings.radius + _settings.sea_level))
	var up: Array[Vector3] = [Vector3.UP, Vector3.UP, Vector3.UP]
	var white: Array[Color] = [Color.WHITE, Color.WHITE, Color.WHITE]
	for row in steps:
		for column in steps:
			var i00 := row * (steps + 1) + column
			var i01 := i00 + steps + 1
			builder.add_tri_smooth(grid[i00], grid[i01], grid[i00 + 1], Color.WHITE, up, white)
			builder.add_tri_smooth(grid[i00 + 1], grid[i01], grid[i01 + 1], Color.WHITE, up, white)
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.mesh = builder.commit()
	var material := ShaderMaterial.new()
	material.shader = preload("res://shaders/world/water_lowpoly.gdshader")
	mesh_instance.material_override = material
	mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mesh_instance)
