class_name PlantLeafShapes
extends RefCounted
## The outline of one leaf and how it becomes triangles. A leaf lives in "leaf space": x across (the
## leaf is 1 / aspect wide), y along from the stalk (0) to the tip (1). Each broadleaf species has
## its own shape (PlantSpecies.leaf_shape), proportions and size, so no two species share a leaf.


## The corner points of a leaf of species `s`, going up the right side and back down the left:
## [stalk end, right side..., tip, left side...]. More points = rounder (the realistic look); a
## lobed or palmate leaf has a point for every lobe tip and every notch between lobes.
static func outline(s: PlantSpecies, detailed: bool) -> PackedVector2Array:
	return outline_for(s.leaf_shape, s.leaf_aspect, s.leaf_lobes, s.leaf_edge, detailed)


## The same from the loose numbers (a species or a tree genome).
static func outline_for(shape: PlantSpecies.LeafShape, aspect: float, lobes: int,
		edge_kind: PlantSpecies.LeafEdge, detailed: bool) -> PackedVector2Array:
	if shape == PlantSpecies.LeafShape.PALMATE:
		return _palmate(aspect)
	if shape == PlantSpecies.LeafShape.LOBED and detailed:
		return _lobed_dense(aspect, maxi(lobes, 1))
	var simple := shape in [PlantSpecies.LeafShape.OVAL, PlantSpecies.LeafShape.DIAMOND]
	var per_side := 2 if simple else 3
	if detailed:
		per_side += 1
		if shape != PlantSpecies.LeafShape.LOBED:
			per_side = 11 # sampled finely: the width curve itself is the leaf's shape (the spline smooths the rest)
	if shape == PlantSpecies.LeafShape.LOBED:
		per_side = 2 * maxi(lobes, 1) + 1 # a notch, a lobe, a notch, a lobe...
	# a serrated or wavy edge (realistic look): more points, every other one pulled in
	var edge := 1.0
	var toothed := edge_kind != PlantSpecies.LeafEdge.SMOOTH
	if detailed and toothed and shape != PlantSpecies.LeafShape.LOBED:
		per_side += 6 if per_side > 8 else 2 # the teeth replace the extra roundness of the realistic look
		edge = 0.8 if edge_kind == PlantSpecies.LeafEdge.SERRATED else 0.92
	var half := 0.5 / aspect
	var points := PackedVector2Array()
	points.append(Vector2.ZERO)
	for index in per_side:
		var along := float(index + 1) / float(per_side + 1)
		points.append(Vector2(half * _width(shape, along, per_side) * _tooth(index, edge), along))
	points.append(Vector2(0.0, 1.0))
	for index in per_side:
		var along := float(per_side - index) / float(per_side + 1)
		var tooth := _tooth(per_side - 1 - index, edge)
		points.append(Vector2(-half * _width(shape, along, per_side) * tooth, along))
	return points


## The width factor of point `index` on a toothed edge: full on the points, `edge` in the notches.
static func _tooth(index: int, edge: float) -> float:
	return 1.0 if edge >= 1.0 or index % 2 == 1 else edge


## How wide the leaf is at `along` (0 stalk .. 1 tip), as a share of its widest point.
static func _width(shape: PlantSpecies.LeafShape, along: float, per_side: int) -> float:
	match shape:
		PlantSpecies.LeafShape.LOBED:
			# an oval envelope; the points alternate between a notch (deep) and a lobe (full)
			var lobe := 0.5 + 0.5 * cos(PI * float(per_side + 1) * along)
			return sin(PI * pow(along, 0.85)) * lerpf(0.5, 1.0, lobe)
		PlantSpecies.LeafShape.HEART:
			# widest low down, a notch where the stalk is, a drawn-out point
			return sin(PI * pow(along, 0.55)) * (1.0 + 0.2 * (1.0 - along))
		PlantSpecies.LeafShape.DIAMOND:
			# straight sides to a wide point low on the leaf, then to the tip
			return along / 0.42 if along < 0.42 else (1.0 - along) / 0.58
		PlantSpecies.LeafShape.LANCEOLATE:
			# long and narrow, widest below the middle, tapering to a long point
			return pow(sin(PI * pow(along, 0.85)), 0.8)
		_:
			# an oval: a rounded base, widest a little below the middle, a pointed tip
			return sin(PI * pow(along, 0.78))


## A maple-like leaf: five lobes fanning out from one point, the middle one the longest, with a
## notch between each pair. The points go from the stalk up the right side, over the middle lobe,
## and down the left side.
static func _palmate(aspect: float) -> PackedVector2Array:
	var centre := Vector2(0.0, 0.5)
	var squeeze := 1.0 / aspect # the leaf is 1 / aspect wide
	# [angle from straight up in degrees, distance from the centre]: notch, lobe, notch, lobe...
	var right := [Vector2(112.0, 0.26), Vector2(74.0, 0.4), Vector2(55.0, 0.3),
			Vector2(36.0, 0.47), Vector2(18.0, 0.3)]
	var points := PackedVector2Array()
	points.append(Vector2.ZERO)
	for spot: Vector2 in right:
		points.append(_polar(centre, spot, squeeze))
	points.append(Vector2(0.0, 1.0))
	for index in range(right.size() - 1, -1, -1):
		var spot: Vector2 = right[index]
		points.append(_polar(centre, Vector2(-spot.x, spot.y), squeeze))
	return points


static func _polar(centre: Vector2, spot: Vector2, squeeze: float) -> Vector2:
	var angle := deg_to_rad(spot.x)
	return Vector2(centre.x + sin(angle) * spot.y * squeeze, centre.y + cos(angle) * spot.y)


## A cluster of leaves as one card (two triangles): a quad from the stalk `base` along `axis`,
## `length` long
## and about as wide, facing `normal`. The shader (flora_wind.gdshader) draws a dozen small veined
## leaves
## on it and cuts the rest away, so a crown reads as foliage (many small leaves), not as a few huge
## flat ones, for a fraction of the triangles. UV2.y above 1.5 marks a card; UV2.x is its own dice.
static func add_leaf_card(builder: MeshBuilder, base: Vector3, axis: Vector3, normal: Vector3,
		length: float, base_color: Color, tip_color: Color, dice: float) -> void:
	var right := axis.cross(normal).normalized()
	var half := length * 0.5
	var a := base - right * half * 0.8
	var b := base + right * half * 0.8
	var c := base + axis * length + right * half
	var d := base + axis * length - right * half
	var mark := Vector2(dice, 2.0 + dice)
	builder.add_tri_uv(a, b, c, base_color, base_color, tip_color, Vector2(0.1, 0.0),
			Vector2(0.9, 0.0), Vector2(1.0, 1.0), mark)
	builder.add_tri_uv(a, c, d, base_color, tip_color, tip_color, Vector2(0.1, 0.0),
			Vector2(1.0, 1.0), Vector2(0.0, 1.0), mark)


## One leaf as a fan of triangles around a centre point that sits a little above the leaf (the
## leaf is folded along its midrib, so its two halves catch the light differently), with the tip
## bent down by `curl`. `axis` runs from the stalk to the tip, `normal` is the side facing the sky.
## Colours run from `base_color` at the stalk to `tip_color` at the tip; alpha is the wind sway.
static func add_leaf(builder: MeshBuilder, outline: PackedVector2Array, base: Vector3,
		axis: Vector3, normal: Vector3, length: float, fold: float, curl: float,
		base_color: Color, tip_color: Color, asym := 0.0, skew := 0.0, width := 1.0,
		leaf_dice := Vector2.ZERO) -> void:
	if builder.detailed:
		_add_leaf_smooth(builder, outline, base, axis, normal, length, fold, curl, base_color, tip_color,
				asym, skew, width, leaf_dice)
		return
	var right := axis.cross(normal).normalized()
	var corners: Array[Vector3] = []
	var colors: Array[Color] = []
	for point in outline:
		# this leaf's own look: one side a little wider than the other (`asym`) and the tip bent
		# to a side (`skew`, a share of the length)
		var across := point.x * width * (1.0 + asym * signf(point.x)) + skew * point.y * point.y
		corners.append(base + axis * (point.y * length) + right * (across * length)
				+ normal * (curl * point.y * point.y * length))
		colors.append(base_color.lerp(tip_color, point.y))
	# Veins, drawn with the vertex colours (no extra triangles): the midrib and the point where the
	# veins meet are light, and the points along the edge alternate light and dark, so bands fan
	# out from the middle to the rim the way the veins of a leaf do.
	for index in colors.size():
		var on_midrib := outline[index].x == 0.0
		if on_midrib:
			colors[index] = colors[index].lightened(0.22)
		elif index % 2 == 1:
			colors[index] = colors[index].lightened(0.14)
		else:
			colors[index] = colors[index].darkened(0.16)
	var centre := base + axis * (0.45 * length) + normal * (fold * length)
	var centre_color := base_color.lerp(tip_color, 0.35).lightened(0.2)
	# where each corner is on the leaf, for the shader's veins: across 0..1 (0.5 on the midrib) and
	# along 0..1
	var widest := 0.001
	for point in outline:
		widest = maxf(widest, absf(point.x))
	var uvs: Array[Vector2] = []
	for point in outline:
		uvs.append(Vector2(0.5 + 0.5 * point.x / widest, point.y))
	var centre_uv := Vector2(0.5, 0.45)
	for index in corners.size():
		var next := (index + 1) % corners.size()
		builder.add_tri_uv(centre, corners[index], corners[next], centre_color, colors[index],
				colors[next], centre_uv, uvs[index], uvs[next], leaf_dice)


const SMOOTH_STEPS := 3 ## points added between two outline corners (the realistic look)
const SMOOTH_RINGS := 3 ## rings from the midrib to the rim: the blade bends between them
const VEIN_SLOPE := 0.45 ## how far up the leaf a rim point is from where its vein leaves the midrib, per unit across

## The outline as a smooth curve: each side (stalk up to the tip) is run through a Catmull-Rom spline, `sharp` 0
## fully round .. 1 the straight corners (a toothed or lobed edge keeps its points, a plain leaf is round). The
## stalk and the tip stay corners. Returns the closed outline, same order as `outline`.
static func smooth_outline(outline: PackedVector2Array, sharp: float) -> PackedVector2Array:
	var tip := 0
	for index in outline.size():
		if outline[index].x == 0.0 and outline[index].y >= 0.999:
			tip = index
	if tip < 2:
		return outline
	var right := PackedVector2Array()
	for index in range(0, tip + 1):
		right.append(outline[index])
	var left := PackedVector2Array()
	left.append(outline[tip])
	for index in range(tip + 1, outline.size()):
		left.append(outline[index])
	left.append(outline[0])
	var result := _spline(right, sharp)
	var back := _spline(left, sharp)
	for index in range(1, back.size() - 1):
		result.append(back[index])
	return result


static func _spline(points: PackedVector2Array, sharp: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	for index in points.size() - 1:
		var p0 := points[maxi(index - 1, 0)]
		var p1 := points[index]
		var p2 := points[index + 1]
		var p3 := points[mini(index + 2, points.size() - 1)]
		for step in SMOOTH_STEPS:
			var t := float(step) / float(SMOOTH_STEPS)
			var round_point := 0.5 * ((2.0 * p1) + (-p0 + p2) * t + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t * t
					+ (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * t * t * t)
			out.append(round_point.lerp(p1.lerp(p2, t), sharp))
	out.append(points[points.size() - 1])
	return out


## A leaf as a grid: rings from the midrib out to the rim, so the blade can cup across and ripple between the
## veins instead of being one flat fan. The grid lines follow the veins (a rim point is joined to the midrib
## a little lower down, as the side veins of a leaf run up and out).
static func _add_leaf_smooth(builder: MeshBuilder, outline: PackedVector2Array, base: Vector3,
		axis: Vector3, normal: Vector3, length: float, fold: float, curl: float,
		base_color: Color, tip_color: Color, asym: float, skew: float, width: float,
		leaf_dice: Vector2) -> void:
	var turns := 0 # how often the width stops growing and starts shrinking along the right side: a smooth leaf once, lobes and teeth many times
	var rising := true
	for index in range(2, outline.size()):
		if outline[index].x <= 0.0 and outline[index].y >= 0.999:
			break
		var step := outline[index].x - outline[index - 1].x
		if absf(step) > 0.0005 and (step > 0.0) != rising:
			rising = step > 0.0
			turns += 1
	var toothed := turns > 2
	var rim := smooth_outline(outline, 0.55 if toothed else 0.15)
	var right := axis.cross(normal).normalized()
	var widest := 0.001
	for point in rim:
		widest = maxf(widest, absf(point.x))
	var count := rim.size()
	var grid: Array = [] # ring -> Array of [position, colour, uv]
	for ring in SMOOTH_RINGS + 1:
		var share := float(ring) / float(SMOOTH_RINGS)
		var row: Array = []
		for point in rim:
			var spine_y := clampf(point.y - VEIN_SLOPE * absf(point.x) / widest * 0.5, 0.0, 1.0)
			if point.x == 0.0:
				spine_y = point.y
			var here := Vector2(point.x * share, lerpf(spine_y, point.y, share))
			var across := here.x * width * (1.0 + asym * signf(here.x)) + skew * here.y * here.y
			# cupped: the midrib rides high, the blade falls away to the rim, rippled between the veins
			var ripple := sin(here.y * 17.0 + signf(here.x) * 1.7) * 0.012 * share
			var lift := fold * (1.0 - share) * 0.4 + ripple - 0.015 * share * share
			var spot := base + axis * (here.y * length) + right * (across * length) 					+ normal * ((lift + curl * here.y * here.y) * length)
			var color := base_color.lerp(tip_color, here.y)
			if ring == 0:
				color = color.lightened(0.18)
			elif share < 1.0:
				color = color.lightened(0.05 * (1.0 - share))
			row.append([spot, color, Vector2(0.5 + 0.5 * here.x / widest, here.y)])
		grid.append(row)
	for ring in SMOOTH_RINGS:
		for index in count:
			var next := (index + 1) % count
			var a: Array = grid[ring][index]
			var b: Array = grid[ring + 1][index]
			var c: Array = grid[ring + 1][next]
			var d: Array = grid[ring][next]
			builder.add_tri_uv(a[0], b[0], c[0], a[1], b[1], c[1], a[2], b[2], c[2], leaf_dice)
			if ring > 0 or (a[0] as Vector3).distance_squared_to(d[0] as Vector3) > 0.0000001:
				builder.add_tri_uv(a[0], c[0], d[0], a[1], c[1], d[1], a[2], c[2], d[2], leaf_dice)


## An oak / maple style leaf for the realistic look: an oval envelope with `lobes` rounded lobes a side, each swept
## forward toward the tip and separated by a notch cut deeper toward the stalk, and a lobe at the tip. Sampled
## finely (the smoothing keeps the lobe tips round); [stalk, right side up, tip, left side down] like `outline_for`.
static func _lobed_dense(aspect: float, lobes: int) -> PackedVector2Array:
	var half := 0.5 / aspect
	var samples := 7 * lobes + 6
	var right := PackedVector2Array()
	var cycles := float(lobes) + 0.5
	for index in range(1, samples):
		var along := float(index) / float(samples)
		var envelope := sin(PI * pow(along, 0.8)) * (1.0 + 0.15 * (1.0 - along))
		# a lobe is a hump, a notch the dip between humps; the notches get shallower toward the tip
		var phase := 0.5 + 0.5 * cos(TAU * cycles * (along - 0.12) / 0.88)
		var depth := lerpf(0.42, 0.25, along)
		var hump := 1.0 - depth * (1.0 - smoothstep(0.0, 1.0, phase))
		hump = lerpf(1.0, hump, smoothstep(0.08, 0.3, along) * (1.0 - smoothstep(0.88, 1.0, along)))
		# lobes sweep forward: a point on the rim sits further up where it is wide
		var forward := 0.06 * smoothstep(0.0, 1.0, phase) * (1.0 - along)
		right.append(Vector2(half * envelope * hump, minf(along + forward, 0.995)))
	var points := PackedVector2Array()
	points.append(Vector2.ZERO)
	points.append_array(right)
	points.append(Vector2(0.0, 1.0))
	for index in range(right.size() - 1, -1, -1):
		points.append(Vector2(-right[index].x, right[index].y))
	return points
