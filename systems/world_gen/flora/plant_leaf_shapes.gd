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
	var simple := shape in [PlantSpecies.LeafShape.OVAL, PlantSpecies.LeafShape.DIAMOND]
	var per_side := 2 if simple else 3
	if detailed:
		per_side += 1
	if shape == PlantSpecies.LeafShape.LOBED:
		per_side = 2 * maxi(lobes, 1) + 1 # a notch, a lobe, a notch, a lobe...
	# a serrated or wavy edge (realistic look): more points, every other one pulled in
	var edge := 1.0
	var toothed := edge_kind != PlantSpecies.LeafEdge.SMOOTH
	if detailed and toothed and shape != PlantSpecies.LeafShape.LOBED:
		per_side += 2 # the teeth replace the extra roundness of the realistic look
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


## One leaf as a fan of triangles around a centre point that sits a little above the leaf (the
## leaf is folded along its midrib, so its two halves catch the light differently), with the tip
## bent down by `curl`. `axis` runs from the stalk to the tip, `normal` is the side facing the sky.
## Colours run from `base_color` at the stalk to `tip_color` at the tip; alpha is the wind sway.
static func add_leaf(builder: MeshBuilder, outline: PackedVector2Array, base: Vector3,
		axis: Vector3, normal: Vector3, length: float, fold: float, curl: float,
		base_color: Color, tip_color: Color, asym := 0.0, skew := 0.0) -> void:
	var right := axis.cross(normal).normalized()
	var corners: Array[Vector3] = []
	var colors: Array[Color] = []
	for point in outline:
		# this leaf's own look: one side a little wider than the other (`asym`) and the tip bent
		# to a side (`skew`, a share of the length)
		var across := point.x * (1.0 + asym * signf(point.x)) + skew * point.y * point.y
		corners.append(base + axis * (point.y * length) + right * (across * length)
				+ normal * (curl * point.y * point.y * length))
		colors.append(base_color.lerp(tip_color, point.y))
	var centre := base + axis * (0.45 * length) + normal * (fold * length)
	var centre_color := base_color.lerp(tip_color, 0.35).darkened(0.12)
	for index in corners.size():
		var next := (index + 1) % corners.size()
		builder.add_tri(centre, corners[index], corners[next], centre_color, colors[index],
				colors[next])
