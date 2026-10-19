class_name MeshBuilder
extends RefCounted
## Builds low-poly meshes out of flat-shaded triangles with a colour per vertex. Every triangle has
## its own three vertices, so it keeps its own normal and the model shows its facets.
## `xf` is applied to everything added after it is set (place a part, then add its triangles).

const CAP_TOP := 1
const CAP_BOTTOM := 2

var xf := Transform3D.IDENTITY
var leaf_cards := true ## broadleaf crowns as cards of many small leaves in the realistic look
var detailed := false # finer geometry for the realistic look: rounder rings, 4x the blob facets
var leafless := false # a debug look: tree builders leave their leaves out (bare branches and trunk)
var _vertices := PackedVector3Array()
var _normals := PackedVector3Array()
var _colors := PackedColorArray()
var _custom := PackedByteArray() # smooth per-vertex colour (CUSTOM0) for the smooth terrain
var _uvs := PackedVector2Array() # only leaves have them (see add_tri_uv); everything else is (0, 0)
var _uv2s := PackedVector2Array() # a leaf's own random numbers (its veins), same corners as _uvs


func triangle_count() -> int:
	return _vertices.size() / 3


## Throws away everything added so far (to build the same thing again with less).
func reset() -> void:
	_vertices.clear()
	_normals.clear()
	_colors.clear()
	_custom.clear()
	_uvs.clear()
	_uv2s.clear()
	xf = Transform3D.IDENTITY


func add_tri(a: Vector3, b: Vector3, c: Vector3, color_a: Color, color_b := color_a,
		color_c := color_a) -> void:
	var pa := xf * a
	var pb := xf * b
	var pc := xf * c
	# the corners come counter clockwise seen from outside; Godot wants clockwise, so b and c swap
	var normal := (pb - pa).cross(pc - pa).normalized()
	_vertices.append_array([pa, pc, pb])
	_normals.append_array([normal, normal, normal])
	_colors.append_array([color_a, color_c, color_b])


## A triangle with a UV on each corner (a leaf: x 0..1 across with 0.5 on the midrib, y 0..1 from
## the stalk to the tip, so the plant shader can draw its veins). Others have no UV (0, 0).
func add_tri_uv(a: Vector3, b: Vector3, c: Vector3, color_a: Color, color_b: Color,
		color_c: Color, uv_a: Vector2, uv_b: Vector2, uv_c: Vector2,
		leaf_dice := Vector2.ZERO) -> void:
	add_tri(a, b, c, color_a, color_b, color_c)
	var before := _vertices.size() - 3
	while _uvs.size() < before:
		_uvs.append(Vector2.ZERO)
		_uv2s.append(Vector2.ZERO)
	_uvs.append_array([uv_a, uv_c, uv_b]) # the same order as the vertices
	_uv2s.append_array([leaf_dice, leaf_dice, leaf_dice])


## A quad a-b-c-d (counter clockwise seen from the front).
func add_quad(a: Vector3, b: Vector3, c: Vector3, d: Vector3, color: Color) -> void:
	add_tri(a, b, c, color)
	add_tri(a, c, d, color)


## A tapered ring from `bottom` (radius r0) to `top` (radius r1), straight up the local Y axis.
## `jitter` moves each ring point a little (0 = a clean cone / cylinder).
func add_frustum(base: Vector3, height: float, r0: float, r1: float, sides: int,
		color_bottom: Color, color_top: Color, rng: RandomNumberGenerator = null,
		jitter := 0.0, caps := 0) -> void:
	if detailed and sides >= 5 and sides < 12: # already round at 12 sides: no more
		sides *= 2
	var bottom_ring: Array[Vector3] = []
	var top_ring: Array[Vector3] = []
	for index in sides:
		var angle := TAU * float(index) / float(sides)
		var wobble0 := 1.0 + (rng.randf_range(-jitter, jitter) if rng != null else 0.0)
		var wobble1 := 1.0 + (rng.randf_range(-jitter, jitter) if rng != null else 0.0)
		var lift := rng.randf_range(-jitter, jitter) * height * 0.15 if rng != null else 0.0
		bottom_ring.append(base + Vector3(cos(angle) * r0 * wobble0, 0.0, sin(angle) * r0 * wobble0))
		top_ring.append(base + Vector3(cos(angle) * r1 * wobble1, height + lift,
				sin(angle) * r1 * wobble1))
	var apex := base + Vector3(0.0, height, 0.0)
	for index in sides:
		var next := (index + 1) % sides
		if r1 <= 0.0001:
			add_tri(bottom_ring[index], apex, bottom_ring[next], color_bottom,
					color_top, color_bottom)
		else:
			add_tri(bottom_ring[index], top_ring[index], bottom_ring[next], color_bottom, color_top,
					color_bottom)
			add_tri(bottom_ring[next], top_ring[index], top_ring[next], color_bottom, color_top,
					color_top)
		if caps & CAP_TOP and r1 > 0.0001:
			add_tri(apex, top_ring[next], top_ring[index], color_top)
		if caps & CAP_BOTTOM:
			add_tri(base, bottom_ring[next], bottom_ring[index], color_bottom)


## A lumpy ball: an icosahedron split once (80 facets), each point pushed in or out.
func add_blob(center: Vector3, radius: Vector3, color_low: Color, color_high: Color,
		rng: RandomNumberGenerator, lumpiness := 0.18) -> void:
	var level := 2 if detailed else 1
	var points := _icosphere_points(level)
	var moved: Array[Vector3] = []
	var waves: Array = [] # detailed: a few smooth bulges instead of per-point noise
	if detailed:
		for wave in 5:
			waves.append([Vector3(rng.randf_range(-1.0, 1.0), rng.randf_range(-1.0, 1.0),
					rng.randf_range(-1.0, 1.0)).normalized(), rng.randf_range(1.5, 4.5),
					rng.randf() * TAU, rng.randf_range(0.4, 1.0) * lumpiness])
	for unit: Vector3 in points:
		var bulge := 0.0
		for wave: Array in waves:
			bulge += float(wave[3]) * sin(unit.dot(wave[0] as Vector3) * float(wave[1]) + float(wave[2]))
		moved.append(unit * (1.0 + (bulge + rng.randf_range(-lumpiness, lumpiness) * 0.12 if detailed
				else rng.randf_range(-lumpiness, lumpiness))))
	var faces := _icosphere_faces(level)
	for face in faces:
		var corners: Array[Vector3] = []
		var colors: Array[Color] = []
		for index in 3:
			var local: Vector3 = moved[face[index]]
			corners.append(center + local * radius)
			colors.append(color_low.lerp(color_high, clampf(local.y * 0.5 + 0.5, 0.0, 1.0)))
		add_tri(corners[0], corners[1], corners[2], colors[0], colors[1], colors[2])


## A terrain triangle: flat colour for the low-poly look, smooth normals and colours for the
## realistic one (the ground shader picks). Corners counter clockwise seen from outside.
func add_tri_smooth(a: Vector3, b: Vector3, c: Vector3, flat: Color, normals: Array[Vector3],
		smooth: Array[Color]) -> void:
	_vertices.append_array([xf * a, xf * c, xf * b])
	_normals.append_array([normals[0], normals[2], normals[1]])
	_colors.append_array([flat, flat, flat])
	for index in [0, 2, 1]:
		var color: Color = smooth[index]
		_custom.append_array([int(color.r * 255.0), int(color.g * 255.0), int(color.b * 255.0), 255])


## Adds smooth terrain triangles that were made elsewhere (native code), the arrays being what
## `add_tri_smooth` would have appended: three vertices a triangle, the flat colour and the smooth
## colour bytes.
func append_smooth(vertices: PackedVector3Array, normals: PackedVector3Array,
		flat: PackedColorArray, smooth_bytes: PackedByteArray) -> void:
	_vertices.append_array(vertices)
	_normals.append_array(normals)
	_colors.append_array(flat)
	_custom.append_array(smooth_bytes)


func commit() -> ArrayMesh:
	var mesh := ArrayMesh.new()
	if _vertices.is_empty():
		return mesh
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = _vertices
	arrays[Mesh.ARRAY_NORMAL] = _normals if not _custom.is_empty() else _smoothed_normals()
	arrays[Mesh.ARRAY_COLOR] = _colors
	if not _uvs.is_empty():
		while _uvs.size() < _vertices.size():
			_uvs.append(Vector2.ZERO)
			_uv2s.append(Vector2.ZERO)
		arrays[Mesh.ARRAY_TEX_UV] = _uvs
		arrays[Mesh.ARRAY_TEX_UV2] = _uv2s
	var flags := 0
	if not _custom.is_empty():
		arrays[Mesh.ARRAY_CUSTOM0] = _custom
		flags = Mesh.ARRAY_CUSTOM_RGBA8_UNORM << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {}, flags)
	return mesh


static var _icospheres: Dictionary = {} # level -> [points, faces]
static var _ico_lock := Mutex.new()


static func _icosphere_points(level: int) -> Array[Vector3]:
	return _icosphere(level)[0]


static func _icosphere_faces(level: int) -> Array:
	return _icosphere(level)[1]


static func _icosphere(level: int) -> Array:
	_ico_lock.lock()
	if not _icospheres.has(level):
		_icospheres[level] = _build_icosphere(level)
	var result: Array = _icospheres[level]
	_ico_lock.unlock()
	return result


## An icosahedron split `level` times (level 1 = 80 facets, 2 = 320): [points, faces].
static func _build_icosphere(level: int) -> Array:
	var points: Array[Vector3] = []
	var t := (1.0 + sqrt(5.0)) * 0.5
	var base: Array[Vector3] = [
		Vector3(-1, t, 0), Vector3(1, t, 0), Vector3(-1, -t, 0), Vector3(1, -t, 0),
		Vector3(0, -1, t), Vector3(0, 1, t), Vector3(0, -1, -t), Vector3(0, 1, -t),
		Vector3(t, 0, -1), Vector3(t, 0, 1), Vector3(-t, 0, -1), Vector3(-t, 0, 1)]
	for point in base:
		points.append(point.normalized())
	var faces: Array = [[0, 11, 5], [0, 5, 1], [0, 1, 7], [0, 7, 10], [0, 10, 11], [1, 5, 9],
			[5, 11, 4], [11, 10, 2], [10, 7, 6], [7, 1, 8], [3, 9, 4], [3, 4, 2], [3, 2, 6],
			[3, 6, 8], [3, 8, 9], [4, 9, 5], [2, 4, 11], [6, 2, 10], [8, 6, 7], [9, 8, 1]]
	for split in level:
		var midpoints := {}
		var next_faces: Array = []
		for face in faces:
			var mids: Array[int] = []
			for edge in 3:
				var a: int = face[edge]
				var b: int = face[(edge + 1) % 3]
				var key := Vector2i(mini(a, b), maxi(a, b))
				if not midpoints.has(key):
					midpoints[key] = points.size()
					points.append(((points[a] + points[b]) * 0.5).normalized())
				mids.append(midpoints[key])
			next_faces.append([face[0], mids[0], mids[2]])
			next_faces.append([face[1], mids[1], mids[0]])
			next_faces.append([face[2], mids[2], mids[1]])
			next_faces.append([mids[0], mids[1], mids[2]])
		faces = next_faces
	return [points, faces]


const SMOOTH_ANGLE := 0.5 ## cos of the widest angle between faces that still share a smooth normal

## The vertex normals for the smooth (realistic) look: at every point, the average of the faces
## that meet there and lean within about 60 degrees of this face, so round things (canopies, rocks,
## trunks) shade round while sharp edges (a box, a roof ridge) stay sharp. The flat look recomputes
## its own flat normal in the shader, so the mesh can carry these.
func _smoothed_normals() -> PackedVector3Array:
	var sums := {}
	for index in _vertices.size():
		var key := Vector3i((_vertices[index] * 100.0).round())
		if not sums.has(key):
			sums[key] = []
		(sums[key] as Array).append(_normals[index])
	var smooth := PackedVector3Array()
	smooth.resize(_vertices.size())
	for index in _vertices.size():
		var key := Vector3i((_vertices[index] * 100.0).round())
		var total := Vector3.ZERO
		for other: Vector3 in sums[key]:
			if other.dot(_normals[index]) > SMOOTH_ANGLE:
				total += other
		smooth[index] = total.normalized() if total.length_squared() > 0.0001 else _normals[index]
	return smooth


## Leaf cards over a canopy: `count` small diamonds standing on the surface of an ellipsoid, each
## tilted a little off the surface and turned at random, so the silhouette breaks into leaves.
func add_leaf_cards(center: Vector3, radius: Vector3, count: int, size: float, color_low: Color,
		color_high: Color, rng: RandomNumberGenerator) -> void:
	for card in count:
		var normal := Vector3(rng.randf_range(-1.0, 1.0), rng.randf_range(-0.6, 1.0),
				rng.randf_range(-1.0, 1.0)).normalized()
		var at := center + normal * radius * 1.02
		var side := normal.cross(Vector3.UP if absf(normal.y) < 0.95 else Vector3.RIGHT).normalized()
		var up := side.cross(normal)
		var roll := rng.randf() * TAU
		var along := (side * cos(roll) + up * sin(roll)) * size
		var across := normal.cross(along).normalized() * size * 0.55
		var tilt := normal * size * rng.randf_range(0.0, 0.5)
		var base := at - along * 0.5
		var tip := at + along * 0.5 + tilt
		var mid := at + tilt * 0.4
		var blend := clampf(normal.y * 0.5 + 0.5, 0.0, 1.0)
		var color := color_low.lerp(color_high, blend)
		add_tri(base, mid - across, mid + across, color.darkened(0.1), color, color)
		add_tri(mid - across, tip, mid + across, color, color.lightened(0.08), color)
