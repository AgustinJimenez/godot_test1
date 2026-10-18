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
var tile_key := 0 ## see key_of
var plant_grid: Dictionary = {} ## the grid the plants are placed on (empty: this tile has none)
var plant_detail := PlanetScatter.Detail.NONE ## what grows on it now
var plant_holder: Node3D

var _noise: PlanetNoise
var _settings: PlanetSettings
var _e1 := Vector3.ZERO # the tile's axes as unit vectors, for the maths below
var _e3 := Vector3.ZERO


static var _ground_material: ShaderMaterial
static var _water_material: ShaderMaterial
static var _river_material: ShaderMaterial


## The ground shader material (made once, shared by every tile).
static func ground_material() -> ShaderMaterial:
	if _ground_material == null:
		_ground_material = ShaderMaterial.new()
		_ground_material.shader = preload("res://shaders/world/planet_ground.gdshader")
	return _ground_material


## The water shader material (made once, shared by every tile).
static func water_material() -> ShaderMaterial:
	if _water_material == null:
		_water_material = ShaderMaterial.new()
		_water_material.shader = preload("res://shaders/world/planet_water.gdshader")
		_water_material.set_shader_parameter(&"depth_fade", 24.0) # the shelf shows as it deepens
	return _water_material


## The river shader material (made once, shared by every tile).
static func river_material() -> ShaderMaterial:
	if _river_material == null:
		_river_material = ShaderMaterial.new()
		_river_material.shader = preload("res://shaders/world/river.gdshader")
		_river_material.render_priority = 1 # where water meets water, the river is drawn last
	return _river_material


## The tile key: (face, level, x, y) packed in one int.
static func key_of(f: int, lvl: int, x: int, y: int) -> int:
	return (((f * 32 + lvl) << 40) | (x << 20)) | y


## Direction on the planet of the cube face point (s, t), both -1..1.
static func direction(f: int, s: float, t: float) -> Vector3:
	var axes: Array = FACES[f]
	var a := tan(s * PI * 0.25)
	var b := tan(t * PI * 0.25)
	var v: Vector3 = (axes[0] as Vector3) + (axes[1] as Vector3) * a + (axes[2] as Vector3) * b
	return v.normalized()


## Builds the tile (on any thread). `collide`: also build the collider (the player walks here).
func build(f: int, lvl: int, x: int, y: int, noise: PlanetNoise, collide: bool) -> PlanetTile:
	tile_key = key_of(f, lvl, x, y)
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
	var fast := noise.native != null and noise.hydrology == null # the crust in native code
	var positions: Array[Vector3] = []
	var heights := PackedFloat32Array()
	var dirs: Array[Vector3] = []
	var packed_dirs := PackedVector3Array()
	if fast:
		packed_dirs = noise.native.call(&"tile_dirs", f, s0, s1, t0, t1, cells)
	else:
		packed_dirs.resize(side * side)
		for row in side:
			var t := lerpf(t0, t1, float(row - 1) / float(cells))
			for column in side:
				var s := lerpf(s0, s1, float(column - 1) / float(cells))
				packed_dirs[row * side + column] = direction(f, s, t)
	dirs.assign(packed_dirs)
	heights = noise.heights_of(packed_dirs) # (the crust is asked for the whole grid at once)
	var packed_positions := PackedVector3Array()
	if fast:
		packed_positions = noise.native.call(&"local_positions", packed_dirs, heights, origin, _e1,
				centre, _e3)
	else:
		packed_positions.resize(side * side)
		for index in side * side:
			packed_positions[index] = _to_local(dirs[index], radius + heights[index])
	positions.assign(packed_positions)
	min_height = INF
	for row in range(1, cells + 2):
		for column in range(1, cells + 2):
			min_height = minf(min_height, heights[row * side + column])
	var packed_normals := PackedVector3Array()
	if fast:
		packed_normals = noise.native.call(&"grid_normals", packed_positions, cells)
	else:
		packed_normals.resize(side * side)
		for row in range(1, cells + 2):
			for column in range(1, cells + 2):
				var along := positions[row * side + column + 1] - positions[row * side + column - 1]
				var down := positions[(row + 1) * side + column] - positions[(row - 1) * side + column]
				var normal := along.cross(down).normalized()
				packed_normals[row * side + column] = normal if normal.y >= 0.0 else -normal
	var packed_colours := PackedColorArray()
	if fast:
		packed_colours = noise.native.call(&"ground_colours", packed_dirs, heights, packed_normals,
				cells)
	else:
		packed_colours.resize(side * side)
		var inner_dirs := PackedVector3Array()
		var inner_heights := PackedFloat32Array()
		var inner_steeps := PackedFloat32Array()
		for row in range(1, cells + 2):
			for column in range(1, cells + 2):
				var index := row * side + column
				inner_dirs.append(dirs[index])
				inner_heights.append(heights[index])
				inner_steeps.append(1.0 - packed_normals[index].y)
		var inner_colours := noise.colours_of(inner_dirs, inner_heights, inner_steeps)
		var at := 0
		for row in range(1, cells + 2):
			for column in range(1, cells + 2):
				packed_colours[row * side + column] = inner_colours[at]
				at += 1
	var normals: Array[Vector3] = []
	normals.assign(packed_normals)
	var colors: Array[Color] = []
	colors.assign(packed_colours)
	var builder := MeshBuilder.new()
	var faces := PackedVector3Array()
	if fast:
		var made: Dictionary = noise.native.call(&"triangles", packed_positions, packed_normals,
				packed_colours, cells)
		builder.append_smooth(made["vertices"], made["normals"], made["colours"], made["custom"])
		faces = made["faces"]
	else:
		for row in range(1, cells + 1):
			for column in range(1, cells + 1):
				var i00 := row * side + column
				var i10 := i00 + 1
				var i01 := i00 + side
				var i11 := i01 + 1
				_triangle(builder, faces, [i00, i01, i10], positions, normals, colors)
				_triangle(builder, faces, [i10, i01, i11], positions, normals, colors)
	if not collide:
		_skirt(builder, positions, colors, cells)
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.mesh = builder.commit()
	mesh_instance.material_override = ground_material()
	if not collide and level < _settings.max_level() - 1:
		mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mesh_instance)
	if _settings.sea_on and min_height < _settings.sea_level + 0.5:
		_add_sea(dirs, side, cells)
	_add_running_water(s0, s1, t0, t1, dirs, heights)
	if level >= _settings.max_level() - 4: # plants can grow here later (PlanetSurface asks for them)
		plant_grid = {"positions": positions, "dirs": dirs, "heights": heights}
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


## Plants this tile (on any thread): a node full of plants for `detail`, not yet in the tree.
func grow_plants(detail: PlanetScatter.Detail) -> Node3D:
	var holder := Node3D.new()
	holder.name = "PlantsOf%d" % tile_key
	PlanetScatter.new().populate(holder, tile_key, _noise, plant_grid["positions"],
			plant_grid["dirs"], plant_grid["heights"], _settings.tile_cells, size, detail,
			has_collider)
	return holder


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
		positions: Array[Vector3], normals: Array[Vector3], colors: Array[Color]) -> void:
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
	# the facet's own colour: the mean of its corners' (they were made from the crust, with the
	# smooth steepness); asking the crust again for each of the ~4,600 triangles cost a quarter of
	# a tile
	var flat := (colors[ids[0]] + colors[ids[1]] + colors[ids[2]]) / 3.0
	var corner_normals: Array[Vector3] = [normals[ids[0]], normals[ids[first]], normals[ids[second]]]
	var corner_colors: Array[Color] = [colors[ids[0]], colors[ids[first]], colors[ids[second]]]
	builder.add_tri_smooth(a, b, c, flat, corner_normals, corner_colors)


## Walls hanging under the four edges, hiding the cracks to a neighbour of another size.
func _skirt(builder: MeshBuilder, positions: Array[Vector3], colors: Array[Color],
		cells: int) -> void:
	var side := cells + 3
	# deep enough to hide the crack between this tile and a finer neighbour (the ground between this
	# tile's samples can be lower than its edge by about the hills), no deeper: a skirt that
	# stands taller than that shows as a wall
	var drop := Vector3(0.0, -clampf(size * 0.03, 2.0, _noise.relief * 0.15 + 4.0), 0.0)
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
	# near the player the facets are about 5 m (the waves roll them); further out they are bigger,
	# and a facet bigger than the waves would catch the sun as one square, so the sea goes flat
	var steps := clampi(int(size / 5.0), 12, 32)
	var facet := size / float(steps)
	var roll := Color(1.0 - smoothstep(6.0, 14.0, facet), 1.0, 1.0)
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
			builder.add_tri_smooth(grid[i00], grid[i01], grid[i00 + 1], roll, up, white)
			builder.add_tri_smooth(grid[i00 + 1], grid[i01], grid[i01 + 1], roll, up, white)
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.mesh = builder.commit()
	mesh_instance.material_override = water_material()
	mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mesh_instance)


## The rivers and lakes that run over this tile: ribbons and cell squares of water at the water's
## own level, cut to the tile's edges so neighbouring tiles never draw the same water twice.
func _add_running_water(s0: float, s1: float, t0: float, t1: float, dirs: Array[Vector3],
		heights: PackedFloat32Array) -> void:
	var water := _noise.hydrology
	if water == null:
		_add_crust_rivers(dirs, heights)
		return
	if level < _settings.max_level() - 1:
		return
	var rings := mini(ceili(size / water.cell_metres) + 2, 6)
	var ids := water.cells_around(water.cell_of(centre), rings)
	var rivers := water.river_segments(ids)
	var lakes := water.has_lake(ids)
	if rivers.is_empty() and not lakes:
		return
	var radius := _settings.radius
	var edge: Array[Vector3] = []
	for corner: Vector2 in [Vector2(s0, t0), Vector2(s1, t0), Vector2(s1, t1), Vector2(s0, t1)]:
		edge.append(_to_local(direction(face, corner.x, corner.y), radius))
	if not rivers.is_empty():
		_add_rivers(dirs, heights)
	if lakes:
		_add_lakes(dirs, heights)


func _add_water_mesh(builder: MeshBuilder, material: ShaderMaterial) -> void:
	if builder.triangle_count() == 0:
		return
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.mesh = builder.commit()
	mesh_instance.material_override = material
	mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mesh_instance)


## The rivers on this tile: water laid over the ground the valleys were already cut into. Every
## corner of the tile's grid asks the river for its water level; where the (carved) ground is under
## it the corner is wet. A square with a wet corner gets a quad, its dry corners sunk into the
## ground so the terrain hides them: the bank is where the water meets the ground, the shape the
## valley has, not the straight edge of a ribbon. The sea owns everything below the sea level.
func _add_rivers(dirs: Array[Vector3], heights: PackedFloat32Array) -> void:
	var water := _noise.hydrology
	var cells := _settings.tile_cells
	var side := cells + 3
	var wet := PackedByteArray()
	wet.resize(side * side)
	var samples: Array[Vector3] = []
	var any := false
	for index in side * side:
		var sample := water.river_sample(dirs[index])
		samples.append(sample)
		if sample.x > -INF and heights[index] > 0.0 and heights[index] < sample.x - 0.02:
			wet[index] = 1
			any = true
	if not any:
		return
	var builder := MeshBuilder.new()
	var radius := _settings.radius
	var roll := Color(0.25, 1.0, 1.0)
	for row in range(1, cells + 1):
		for column in range(1, cells + 1):
			var i00 := row * side + column
			var corners := [i00, i00 + 1, i00 + side, i00 + side + 1]
			var level := -INF
			var wet_corner := false
			for corner: int in corners:
				if wet[corner] == 1:
					wet_corner = true
					level = maxf(level, samples[corner].x)
			if not wet_corner:
				continue
			var points: Array[Vector3] = []
			var coords: Array[Vector2] = []
			for corner: int in corners:
				var sample := samples[corner]
				var height := level if wet[corner] == 1 else minf(heights[corner] - 0.15, level)
				points.append(_to_local(dirs[corner], radius + height))
				coords.append(Vector2(sample.z if sample.x > -INF else 0.5, maxf(sample.y, 0.0)))
			_river_triangle(builder, points, coords, 0, 2, 1, roll)
			_river_triangle(builder, points, coords, 1, 2, 3, roll)
	_add_water_mesh(builder, river_material())


func _river_triangle(builder: MeshBuilder, points: Array[Vector3], coords: Array[Vector2],
		i: int, j: int, k: int, roll: Color) -> void:
	var a := points[i]
	var b := points[j]
	var c := points[k]
	var uv_a := coords[i]
	var uv_b := coords[j]
	var uv_c := coords[k]
	if (b - a).cross(c - a).y < 0.0:
		b = points[k]
		c = points[j]
		uv_b = coords[k]
		uv_c = coords[j]
	builder.add_tri_uv(a, b, c, roll, roll, roll, uv_a, uv_b, uv_c)


## The lakes on this tile: a quad of water for every square of the tile's own grid whose four
## corners are under a lake's level, so the shore follows the ground (down to the grid's size).
func _add_lakes(dirs: Array[Vector3], heights: PackedFloat32Array) -> void:
	var water := _noise.hydrology
	var cells := _settings.tile_cells
	var side := cells + 3
	var levels := PackedFloat32Array()
	levels.resize(side * side)
	var any := false
	for index in side * side:
		var level := water.lake_level_at(dirs[index], heights[index])
		levels[index] = level if level > -INF else -1000.0
		any = any or level > -INF
	if not any:
		return
	var builder := MeshBuilder.new()
	var radius := _settings.radius
	var up: Array[Vector3] = [Vector3.UP, Vector3.UP, Vector3.UP]
	var roll := Color(0.4, 1.0, 1.0)
	var white: Array[Color] = [roll, roll, roll]
	for row in range(1, cells + 1):
		for column in range(1, cells + 1):
			var i00 := row * side + column
			var corners := [i00, i00 + 1, i00 + side, i00 + side + 1]
			var level := -1000.0
			var all_wet := true
			for corner: int in corners:
				level = maxf(level, levels[corner])
				all_wet = all_wet and levels[corner] > -999.0
			if not all_wet:
				continue
			var p00 := _to_local(dirs[i00], radius + level)
			var p10 := _to_local(dirs[i00 + 1], radius + level)
			var p01 := _to_local(dirs[i00 + side], radius + level)
			var p11 := _to_local(dirs[i00 + side + 1], radius + level)
			builder.add_tri_smooth(p00, p01, p10, roll, up, white)
			builder.add_tri_smooth(p10, p01, p11, roll, up, white)
	_add_water_mesh(builder, water_material())


## Cuts `polygon` (convex, seen from above, with a texture coordinate per corner) to the tile's quad
## `edge` and adds it as a fan.
func _water_polygon(builder: MeshBuilder, polygon: Array[Vector3], uvs: Array[Vector2],
		edge: Array[Vector3], roll: Color) -> void:
	var clipped := polygon
	var coords := uvs
	var turn := signf((edge[1].x - edge[0].x) * (edge[2].z - edge[0].z)
			- (edge[1].z - edge[0].z) * (edge[2].x - edge[0].x))
	for index in 4:
		var p := edge[index]
		var q := edge[(index + 1) % 4]
		var kept: Array[Vector3] = []
		var kept_uv: Array[Vector2] = []
		for k in clipped.size():
			var before_index := (k + clipped.size() - 1) % clipped.size()
			var current := clipped[k]
			var previous := clipped[before_index]
			var now := _side(p, q, current) * turn
			var before := _side(p, q, previous) * turn
			if now >= 0.0:
				if before < 0.0:
					var t := before / (before - now)
					kept.append(previous.lerp(current, t))
					kept_uv.append(coords[before_index].lerp(coords[k], t))
				kept.append(current)
				kept_uv.append(coords[k])
			elif before >= 0.0:
				var t := before / (before - now)
				kept.append(previous.lerp(current, t))
				kept_uv.append(coords[before_index].lerp(coords[k], t))
		clipped = kept
		coords = kept_uv
		if clipped.size() < 3:
			return
	for index in range(1, clipped.size() - 1):
		var a := clipped[0]
		var b := clipped[index]
		var c := clipped[index + 1]
		var uv_a := coords[0]
		var uv_b := coords[index]
		var uv_c := coords[index + 1]
		if (b - a).cross(c - a).y < 0.0:
			b = clipped[index + 1]
			c = clipped[index]
			uv_b = coords[index + 1]
			uv_c = coords[index]
		builder.add_tri_uv(a, b, c, roll, roll, roll, uv_a, uv_b, uv_c)


## Which side of the line p -> q (in the ground plane) the point is on.
func _side(p: Vector3, q: Vector3, point: Vector3) -> float:
	return (q.x - p.x) * (point.z - p.z) - (q.z - p.z) * (point.x - p.x)


## The rivers of the crust's own valleys (the drainage): the native crust says, for every corner of
## the tile's grid, the water level of the river whose valley is there; where the ground is under
## it (and above the sea) the corner is wet, and a square with a wet corner gets water, its dry
## corners sunk into the ground, so the bank is where the valley's ground meets the water.
func _add_crust_rivers(dirs: Array[Vector3], heights: PackedFloat32Array) -> void:
	if not _settings.hydrology_on or _noise.drainage == null or _noise.native == null \
			or level < _settings.max_level() - 3:
		return
	var samples: PackedVector3Array = _noise.native.call(&"river_waters", PackedVector3Array(dirs))
	var cells := _settings.tile_cells
	var side := cells + 3
	var wet := PackedByteArray()
	wet.resize(side * side)
	var any := false
	for index in side * side:
		var water_level := samples[index].x
		if water_level > _settings.sea_level and heights[index] < water_level - 0.02 \
				and heights[index] > _settings.sea_level:
			wet[index] = 1
			any = true
	if not any:
		return
	var builder := MeshBuilder.new()
	var radius := _settings.radius
	var roll := Color(0.25, 1.0, 1.0)
	for row in range(1, cells + 1):
		for column in range(1, cells + 1):
			var i00 := row * side + column
			var corners := [i00, i00 + 1, i00 + side, i00 + side + 1]
			var surface := -INF
			for corner: int in corners:
				if wet[corner] == 1:
					surface = maxf(surface, samples[corner].x)
			if surface == -INF:
				continue
			var points: Array[Vector3] = []
			var coords: Array[Vector2] = []
			for corner: int in corners:
				var height := surface if wet[corner] == 1 else minf(heights[corner] - 0.15, surface)
				points.append(_to_local(dirs[corner], radius + height))
				coords.append(Vector2(samples[corner].z, maxf(samples[corner].y, 0.0)))
			_river_triangle(builder, points, coords, 0, 2, 1, roll)
			_river_triangle(builder, points, coords, 1, 2, 3, roll)
	_add_water_mesh(builder, river_material())
