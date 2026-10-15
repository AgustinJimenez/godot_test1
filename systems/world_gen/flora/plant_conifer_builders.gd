class_name PlantConiferBuilders
extends RefCounted
## A spruce, fir or pine as it really grows: a straight trunk that narrows to a leader, whorls of
## branches around it (drooping, their tips lifting), each branch carrying branchlets, and on every
## branch and branchlet sprays of single needles. The whorls shrink toward the top, so the
## silhouette is the usual cone. Same rules as the leafy trees (PlantCrownBuilders): every tube
## starts inside its parent, ends in a point or under a spray, and the wind weight (vertex colour
## alpha) grows smoothly from the trunk out to the needle tips so nothing pulls apart in a gust.

const RINGS := [3, 2] ## rings of a branch, a branchlet
const SIDES := [5, 3] ## and their sides (low-poly)
const SIDES_REAL := [7, 4] ## in the realistic look
const BURY := 0.4 ## how deep a tube starts inside its parent, as a share of the parent's radius
const SWAY_GAIN := [0.2, 0.25] ## wind weight added along a branch, a branchlet
const NEEDLE_SWAY := 0.35 ## and from the base of a needle spray to its tips

var _builder: MeshBuilder
var _s: PlantSpecies
var _rng: RandomNumberGenerator
var _height := 8.0
var _trunk_base_radius := 0.3
var _needle_length := 0.4


static func build(builder: MeshBuilder, s: PlantSpecies, rng: RandomNumberGenerator) -> void:
	var crown := PlantConiferBuilders.new()
	crown._builder = builder
	crown._s = s
	crown._rng = rng
	crown._grow()


func _still(color: Color) -> Color:
	return Color(color.r, color.g, color.b, 0.0)


func _grow() -> void:
	_height = _s.height * _rng.randf_range(0.9, 1.1)
	_trunk_base_radius = _s.girth
	_needle_length = clampf(_s.crown * 0.45, 0.6, 1.1) * (1.0 if _builder.detailed else 1.2)
	var trunk_part := _height * _s.bare
	_trunk(trunk_part)
	# a whorl every 0.5 - 0.9 m, close together, so the sprays overlap into the dense tiers of a spruce
	var spacing := clampf(_s.crown * 0.35, 0.5, 0.9)
	var tiers := maxi(int((_height * 0.94 - trunk_part * 0.75) / spacing), 5)
	var phase := _rng.randf() * TAU
	for tier in tiers:
		var along := float(tier) / float(tiers - 1)
		var y := lerpf(trunk_part * 0.75, _height * 0.94, pow(along, 0.92))
		var reach := lerpf(_s.crown, _s.crown * 0.1, pow(along, 0.9)) * _rng.randf_range(0.94, 1.06)
		var count := 6 if along < 0.6 else 5
		if _builder.detailed:
			count += 1
		phase += 1.9 # each whorl is turned against the one below
		for index in count:
			var yaw := phase + TAU * float(index) / float(count) + _rng.randf_range(-0.2, 0.2)
			_branch_off_trunk(y, yaw, reach, along)
	# the top: a few needle sprays at the point of the leader
	var top := _trunk_point(_height)
	for index in 4:
		var yaw := TAU * float(index) / 4.0 + _rng.randf() * 0.5
		var out := Vector3(cos(yaw), 0.0, sin(yaw))
		_spray(top - Vector3(0.0, 0.1, 0.0), (out * 0.5 + Vector3.UP * 0.8).normalized(),
				_needle_length * 0.9, 0.55)


## The straight trunk from the ground up, narrowing to a point at the very top (the leader).
func _trunk(_bare_part: float) -> void:
	var rings := 7
	var centres: Array[Vector3] = []
	var radii: Array[float] = []
	var colors: Array[Color] = []
	for index in rings:
		var along := float(index) / float(rings - 1)
		centres.append(_trunk_point(_height * along))
		radii.append(_trunk_base_radius * pow(1.0 - along, 0.85) + 0.02)
		colors.append(_still(_s.bark.darkened(0.3 * (1.0 - along))))
	PlantTreeBuilders.tube(_builder, centres, radii, colors, 12, _rng, 0.03,
			MeshBuilder.CAP_TOP, false)


func _trunk_radius_at(y: float) -> float:
	return _trunk_base_radius * pow(1.0 - clampf(y / _height, 0.0, 1.0), 0.85) + 0.02


func _trunk_point(y: float) -> Vector3:
	return Vector3(0.0, y, 0.0)


## One branch of a whorl: leaves the trunk sideways, droops, its tip lifting, with branchlets and
## needle sprays along it.
func _branch_off_trunk(y: float, yaw: float, reach: float, along: float) -> void:
	var out := Vector3(cos(yaw), 0.0, sin(yaw))
	# below the horizontal for a drooping species, above it high in the tree
	var droop := lerpf(-0.1, 0.55, _s.droop) * (1.0 - 0.7 * along)
	var dir := (out * cos(droop) + Vector3.DOWN * sin(droop)).normalized()
	var radius := _trunk_radius_at(y) * 0.45
	var start := _trunk_point(y) - dir * radius * 0.5 # inside the trunk, not out of its far side
	_branch(start, dir, reach, radius, 0, 0.0, out)


func _branch(start: Vector3, dir: Vector3, length: float, radius: float, depth: int, sway: float,
		out: Vector3) -> void:
	var rings: int = RINGS[depth]
	var points: Array[Vector3] = [start]
	var tangents: Array[Vector3] = [dir]
	var heading := dir
	var lift := 0.55 if depth == 0 else 0.3 # the tip of a branch turns up
	for ring in rings - 1:
		heading = (heading + Vector3.UP * lift / float(rings - 1)
				+ _jitter() * 0.08).normalized()
		points.append(points[ring] + heading * length / float(rings - 1))
		tangents.append(heading)
	var radii: Array[float] = []
	var colors: Array[Color] = []
	for ring in rings:
		var f := float(ring) / float(rings - 1)
		radii.append(lerpf(radius, radius * 0.18, f))
		var bark := _s.bark.lightened(0.05 * float(depth)).darkened(0.1 * (1.0 - f))
		colors.append(Color(bark.r, bark.g, bark.b, sway + SWAY_GAIN[depth] * f))
	var sides: int = SIDES_REAL[depth] if _builder.detailed else SIDES[depth]
	PlantTreeBuilders.tube(_builder, points, radii, colors, sides, _rng, 0.0, MeshBuilder.CAP_TOP,
			false)
	var tip := points[points.size() - 1]
	var tip_tangent := tangents[tangents.size() - 1]
	var tip_sway: float = sway + SWAY_GAIN[depth]
	_spray(tip, tip_tangent, _needle_length * (1.0 if depth == 0 else 0.8), tip_sway)
	if depth == 0: # and one half way along, so the branch is not bare between its ends
		_spray(_point_along(points, 0.55), _tangent_along(tangents, 0.55), _needle_length * 0.8,
				sway + SWAY_GAIN[0] * 0.55)
	if depth == 1:
		return
	var branchlets := 2
	for index in branchlets:
		var f := 0.3 + 0.6 * float(index) / float(branchlets)
		var at := _point_along(points, f)
		var tangent := _tangent_along(tangents, f)
		var side := 1.0 if index % 2 == 0 else -1.0
		var across := tangent.cross(Vector3.UP).normalized() * side
		var child_dir := (tangent * 0.75 + across * 0.7 + Vector3.DOWN * 0.1).normalized()
		var child_length := length * 0.42 * (1.15 - 0.6 * f)
		var local_radius := lerpf(radius, radius * 0.18, f)
		var buried := local_radius * BURY
		_branch(at - child_dir * buried, child_dir, child_length + buried, local_radius * 0.55,
				1, sway + SWAY_GAIN[0] * f, out)


## A fan of single needles in the plane of a branch: `axis` is where the branch points.
func _spray(base: Vector3, axis: Vector3, length: float, sway: float) -> void:
	if _builder.leafless:
		return
	var count := 11 if _builder.detailed else 9
	var side := axis.cross(Vector3.UP)
	if side.length_squared() < 0.0001:
		side = axis.cross(Vector3.RIGHT)
	side = side.normalized()
	var up := side.cross(axis).normalized()
	var tone := _s.leaf.lerp(_s.leaf.lightened(0.1), _rng.randf())
	var tip_color := Color(0.93, 0.95, 0.98) if _s.frosted else _s.leaf_tip.lerp(tone, 0.3)
	var base_color := tone.darkened(0.25)
	base_color.a = sway
	tip_color.a = minf(sway + NEEDLE_SWAY, 1.0)
	var width := length * 0.1
	for index in count:
		var fan := (float(index) / float(count - 1) - 0.5) * 2.0 # -1 .. 1 across the spray
		var angle := fan * 0.95 # radians away from the branch direction, in the spray's plane
		var lift := _rng.randf_range(-0.12, 0.28) # needles are not quite flat
		var dir := (axis * cos(angle) + side * sin(angle) + up * lift).normalized()
		var needle := length * _rng.randf_range(0.75, 1.15) * (1.0 - 0.25 * absf(fan))
		var near := base + dir * needle * 0.12
		var sideways := dir.cross(up).normalized() * width
		_builder.add_tri(near - sideways, near + sideways, base + dir * needle, base_color,
				base_color, tip_color)


func _jitter() -> Vector3:
	return Vector3(_rng.randf_range(-1.0, 1.0), _rng.randf_range(-0.5, 0.5),
			_rng.randf_range(-1.0, 1.0))


func _point_along(points: Array[Vector3], along: float) -> Vector3:
	var scaled := along * float(points.size() - 1)
	var index := mini(int(scaled), points.size() - 2)
	return points[index].lerp(points[index + 1], scaled - float(index))


func _tangent_along(tangents: Array[Vector3], along: float) -> Vector3:
	var scaled := along * float(tangents.size() - 1)
	var index := mini(int(scaled), tangents.size() - 2)
	return tangents[index].lerp(tangents[index + 1], scaled - float(index)).normalized()
