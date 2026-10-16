class_name TreeGrower
extends RefCounted
## Grows any tree from its TreeGenome: the trunk, the branches that leave it (in whorls up the trunk
## for a conifer, as limbs at the top of the trunk for a leafy tree), the levels of branching, and
## the foliage (single leaves along the twigs, or sprays of needles at the ends).
##
## Rules every tube follows (all learnt the hard way, see AGENT_TASKS/041 and 042):
## - a child starts inside its parent (a share of the parent's radius, never past its far side);
## - rings stand at right angles to the path, so a sideways branch is as round as an upright trunk;
## - a branch that carries on from its parent starts at the parent's tip with the parent's radius
##   and the same number of sides, and the parent is not capped there;
## - branches taper to points and nothing ends bare (a twig ends in a leaf, a branch under a spray);
## - the wind weight (vertex alpha) grows smoothly from the trunk out to the leaf tips, and a child
##   starts with the value its parent has at that spot, so a joint never pulls apart.

const GOLDEN_ANGLE := 2.39996323
const LEAF_SWAY := 0.45 ## wind weight added from the stalk to the tip of a leaf
const NEEDLE_SWAY := 0.35 ## and from the base of a needle spray to its tips
## No tree gets more triangles than this: once the mesh is full no more branches or leaves are
## added (a wild genome then has a bare top instead of a forest-sized mesh).
const BUDGET := 12000
const MARGIN := 150 ## the check runs between branches, so one more can still be added after it

var capped := false ## the budget ran out while growing
var _thrift := 1.0 ## 1 as drawn; less: fewer branches, whorls and leaves (see build)

var _g: TreeGenome
var _b: MeshBuilder
var _rng: RandomNumberGenerator
var _lod := 0 ## 0 full tree, 1 the lighter one for trees at a distance
var _fine := false ## the realistic geometry (never in the lighter version)
var _depth := 3 ## levels of branching in this version
var _height := 8.0
var _trunk_length := 2.0 ## metres of trunk: to the limbs, or all the way for a leader
var _tilt := Vector3.ZERO
var _origin := Vector3.ZERO ## where the stem being grown starts (a clump has several)
var _outline := PackedVector2Array()
var _leaf_length := 0.3
var _needle_length := 0.5


## `lod` 1 grows a lighter version of the same tree (one level of branching less, fewer limbs and
## whorls, leaves and needles, fewer sides) for trees seen from far away.
## A tree that does not fit the budget is grown again with less (fewer branches, whorls and leaves:
## `thrift` 1 down to 0.12) from the same dice, so it keeps its shape and its whole height.
## Returns true if even that was cut short.
static func build(builder: MeshBuilder, genome: TreeGenome, rng: RandomNumberGenerator,
		lod := 0) -> bool:
	var start := rng.state
	var grower: TreeGrower
	for thrift: float in [1.0, 0.7, 0.5, 0.35, 0.25, 0.18, 0.12]:
		builder.reset()
		rng.state = start
		grower = TreeGrower.new()
		grower._g = genome
		grower._b = builder
		grower._rng = rng
		grower._lod = lod
		grower._fine = builder.detailed and lod == 0
		grower._depth = genome.depth
		grower._thrift = thrift
		grower._grow()
		if not grower.capped:
			break
	return grower.capped


func _grow() -> void:
	if _g.stems <= 1 or _g.leader:
		_grow_stem()
		return
	# a clump: every stem is a smaller tree of its own, leaning out from a shared root
	var height := _g.height
	var girth := _g.girth
	var crown := _g.crown
	var phase := _rng.randf() * TAU
	for stem in _g.stems:
		var size := 1.0 - 0.3 * float(stem) / float(_g.stems) * _rng.randf_range(0.6, 1.2)
		_g.height = height * size
		_g.girth = girth * size * 0.8
		_g.crown = crown * (0.6 + 0.4 * size)
		var yaw := phase + TAU * float(stem) / float(_g.stems) + _rng.randf_range(-0.3, 0.3)
		var out := Vector3(cos(yaw), 0.0, sin(yaw))
		_origin = out * girth * 0.8
		_grow_stem(out * _g.stem_spread * _g.height)
	_g.height = height
	_g.girth = girth
	_g.crown = crown
	_origin = Vector3.ZERO


func _grow_stem(lean_to := Vector3.ZERO) -> void:
	_height = _g.height * _rng.randf_range(0.9, 1.1)
	_tilt = lean_to
	_trunk_length = _height if _g.leader else _height * _g.trunk_part
	if _g.lean > 0.0:
		_tilt += Vector3(_rng.randf_range(-1.0, 1.0), 0.0, _rng.randf_range(-1.0, 1.0)).normalized() \
				* _g.lean * _height
	_outline = PlantLeafShapes.outline_for(_g.leaf_shape, _g.leaf_aspect, _g.leaf_lobes,
			_g.leaf_edge, _fine)
	# the low-poly look has fewer, bigger leaves and sprays (the lighter version bigger still)
	var bigger := 1.0 + 0.8 * float(_lod)
	# leaves grow with the crown, but slowly: a giant tree has more leaves, not door-sized ones
	var leaf_basis := 2.0 * pow(maxf(_g.crown, 0.2) / 2.0, 0.55)
	leaf_basis *= pow(maxf(_g.crown / 3.5, 1.0), 0.6) # a wide crown has clumps of leaves
	_leaf_length = leaf_basis * _g.leaf_size * (1.7 if _fine else 2.5) * bigger
	# sprays grow with a thick trunk too (a giant's needles are not a normal tree's)
	var stout := pow(maxf(_g.girth / 0.4, 1.0), 0.75)
	var needle := clampf(leaf_basis * _g.needle_size, 0.6, 1.1) * stout
	_needle_length = needle * (1.0 if _fine else 1.2) * bigger
	_trunk()
	if _g.foliage == TreeGenome.Foliage.FROND:
		_fronds()
	elif _g.leader:
		_whorls()
	else:
		_limbs()


## True once the mesh has used its triangle budget.
func _full() -> bool:
	if _b.triangle_count() < BUDGET - MARGIN:
		return false
	capped = true
	return true


func _still(color: Color) -> Color:
	return Color(color.r, color.g, color.b, 0.0)


## The point of the trunk's axis at height `y` (a leaning trunk leans more toward its top).
func _axis(y: float) -> Vector3:
	var along := y / _trunk_length
	return _origin + Vector3(_tilt.x * along * along, y, _tilt.z * along * along)


func _trunk() -> void:
	var rings := (7 if _g.leader else 5) - _lod
	var centres: Array[Vector3] = []
	var radii: Array[float] = []
	var colors: Array[Color] = []
	for index in rings:
		var along := float(index) / float(rings - 1)
		centres.append(_axis(_trunk_length * along))
		radii.append(_trunk_radius(along))
		colors.append(_still(_g.bark.darkened(_g.trunk_dark * (1.0 - along))))
	if not _g.leader:
		# the top of the trunk is a rounded dome the limbs grow out of (a flat cut shows as a disc)
		var top_radius := _g.girth * _g.taper
		var top := centres[centres.size() - 1]
		for dome: Array in [[0.5, 0.8], [0.95, 0.3]]:
			centres.append(top + Vector3(0.0, top_radius * float(dome[0]), 0.0))
			radii.append(top_radius * float(dome[1]))
			colors.append(colors[colors.size() - 1])
	var trunk_sides := _g.trunk_sides - 5 * _lod
	PlantTreeBuilders.tube(_b, centres, radii, colors, trunk_sides, _rng, _g.trunk_wobble,
			MeshBuilder.CAP_TOP, false)
	if _g.marked_bark and not _g.leader and _lod == 0: # the dark patches on pale bark
		for mark in int(_trunk_length / 0.8):
			var at := float(mark) * 0.8 + 0.4
			var radius := _trunk_radius(at / _trunk_length) * 1.04
			var patch := _still(Color(0.12, 0.12, 0.1))
			_b.add_frustum(_axis(at), 0.12, radius, radius * 0.99, _g.trunk_sides, patch, patch)


## The trunk's radius at `along` (0 foot .. 1 top).
func _trunk_radius(along: float) -> float:
	var flare := 1.0 + 2.0 * _g.root_flare * pow(1.0 - along, 6.0) # widens at the foot
	if _g.leader and _g.column >= 0.0: # a column: stays thick far up
		return _g.girth * lerpf(1.0, _g.column, pow(along, 0.9)) * flare
	if _g.leader:
		return (_g.girth * pow(1.0 - along, 0.85) + 0.02) * flare # narrows to a point
	return lerpf(_g.girth, _g.girth * _g.taper, along) * flare


## Limbs at the top of the trunk (a leafy tree): they fan out at the species' angle, spiralling
## round by the golden angle, and are as long as the crown envelope allows.
func _limbs() -> void:
	var top := _axis(_trunk_length)
	var crown_height := (_height - _trunk_length) * 0.5
	var centre := top + Vector3(0.0, crown_height * 0.7, 0.0)
	var radius_h := _g.crown * 1.8
	var radius_v := maxf(crown_height * 0.85, _g.crown * _g.aspect)
	var limb_radius := _g.girth * _g.taper * _g.limb_thickness
	var phase := _rng.randf() * TAU
	for index in maxi(_g.limbs - _lod, 3):
		var yaw := phase + float(index) * GOLDEN_ANGLE
		var pitch := deg_to_rad(_g.limb_angle * _rng.randf_range(0.85, 1.15))
		var dir := Vector3(sin(pitch) * cos(yaw), cos(pitch), sin(pitch) * sin(yaw))
		# the limbs start well down in the trunk's rounded top, so it narrows into them
		var start := top + Vector3(0.0, -limb_radius * 2.0 + float(index) * limb_radius * 0.6, 0.0)
		start -= dir * limb_radius * 0.5
		var length := clampf(radius_h * 0.85 / maxf(sin(pitch), 0.35), radius_h * 0.6,
				radius_h * 1.3)
		length = minf(length, (centre.y + radius_v - start.y) / maxf(cos(pitch), 0.2))
		length *= _g.limb_length
		_branch(start, dir, length, limb_radius, 0, 0.0)


## A palm's crown: fronds out from the top of the trunk, the young ones in the middle pointing up,
## the old ones arching out and hanging. Each is a midrib with a row of leaflets down both sides.
func _fronds() -> void:
	var top := _axis(_trunk_length) + Vector3(0.0, 0.05, 0.0)
	var count := maxi(_g.fronds - 3 * _lod, 5)
	var phase := _rng.randf() * TAU
	for index in count:
		var yaw := phase + float(index) * GOLDEN_ANGLE
		var out := Vector3(cos(yaw), 0.0, sin(yaw))
		var side := Vector3(-out.z, 0.0, out.x)
		var length := _g.frond_length * _rng.randf_range(0.85, 1.1)
		var steep := pow(_rng.randf(), 1.5) # the young ones stand up
		var parts := 9 - 3 * _lod
		var points: Array[Vector3] = []
		for step in parts + 1:
			var t := float(step) / float(parts)
			var reach := length * t * (1.0 - 0.6 * steep)
			var rise := length * (0.9 * steep * t + 0.5 * _g.frond_arch * sin(PI * t)
					- _g.frond_droop * t * t)
			points.append(top + out * reach + Vector3(0.0, rise, 0.0))
		_frond(points, side)


func _frond(points: Array[Vector3], side: Vector3) -> void:
	if _b.leafless or _full():
		return
	var length := (points[points.size() - 1] - points[0]).length()
	var rib := length * 0.012
	var dark := _g.leaf.darkened(0.35)
	var tone := _g.leaf.lerp(_g.leaf.lightened(0.12), _rng.randf())
	for index in points.size() - 1:
		var t := float(index) / float(points.size() - 1)
		var sway := 0.35 + 0.5 * t
		var a := points[index]
		var b := points[index + 1]
		var tangent := (b - a).normalized()
		var base := dark
		base.a = sway
		var tip := dark
		tip.a = minf(sway + 0.1, 1.0)
		_b.add_tri(a - side * rib, a + side * rib, b, base, base, tip)
		# leaflets: one tri per side, hanging from the midrib, longest in the middle of the frond
		var leaflets := (5 if _fine else 3) - _lod
		for leaf_index in maxi(leaflets, 1):
			var u := (float(leaf_index) + 0.5) / float(maxi(leaflets, 1))
			var at := a.lerp(b, u)
			var shape := pow(sin(PI * clampf(t + u / float(points.size() - 1), 0.05, 0.98)), 0.7)
			var size := length * _g.leaflet * shape * _rng.randf_range(0.85, 1.1)
			var step_len := (b - a).length() / float(maxi(leaflets, 1))
			for sign_side: float in [-1.0, 1.0]:
				var dir := (side * sign_side * 0.9 + tangent * 0.5 + Vector3.DOWN * 0.45).normalized()
				var from_colour := tone.darkened(0.2)
				from_colour.a = sway
				var tip_colour := _g.leaf_tip.lerp(tone, 0.3)
				tip_colour.a = minf(sway + LEAF_SWAY, 1.0)
				_b.add_tri(at, at + tangent * step_len, at + dir * size + tangent * step_len * 0.5,
						from_colour, from_colour, tip_colour)


## Whorls of branches up the trunk (a conifer), close together, each turned against the one below;
## shorter toward the top, so the outline is a cone. Needle trees get a few sprays at the leader.
func _whorls() -> void:
	var first := _height * _g.nodes_from
	var last := _height * 0.94
	var spacing := maxf(_g.nodes_spacing, 0.1) * (1.0 + 0.8 * float(_lod)) / _thrift
	var tiers := maxi(int((last - first) / spacing), 5)
	var phase := _rng.randf() * TAU
	for tier in tiers:
		var along := float(tier) / float(tiers - 1)
		var y := lerpf(first, last, pow(along, 0.92))
		var reach := lerpf(_g.crown, _g.crown * 0.1, pow(along, 0.9)) * _rng.randf_range(0.94, 1.06)
		var count := _g.limbs + (1 if along < 0.6 else 0) + (1 if _fine else 0) - _lod
		count = maxi(roundi(float(count) * _thrift), 3)
		phase += 1.9
		for index in count:
			var yaw := phase + TAU * float(index) / float(count) + _rng.randf_range(-0.2, 0.2)
			var out := Vector3(cos(yaw), 0.0, sin(yaw))
			# below the horizontal for a drooping species, above it high in the tree
			var below := lerpf(-0.1, 0.55, _g.droop) * (1.0 - 0.7 * along)
			var dir := (out * cos(below) + Vector3.DOWN * sin(below)).normalized()
			var radius := _trunk_radius(y / _trunk_length) * 0.45
			var start := _axis(y) - dir * radius * 0.5 # inside the trunk, not out of its far side
			_branch(start, dir, reach, radius, 0, 0.0)
	if _g.foliage == TreeGenome.Foliage.NEEDLE:
		var top := _axis(_height)
		for index in 4:
			var yaw := TAU * float(index) / 4.0 + _rng.randf() * 0.5
			var out := Vector3(cos(yaw), 0.0, sin(yaw))
			_spray(top - Vector3(0.0, 0.1, 0.0), (out * 0.5 + Vector3.UP * 0.8).normalized(),
					_needle_length * 0.9, 0.55)


## One limb (level 0), branch (1) or twig (2): a tube that bends along its length, then whatever
## it carries. `sway` is the wind weight at its start; `continues` says it carries on from the tip
## of its parent.
func _branch(start: Vector3, dir: Vector3, length: float, radius: float, level: int, sway: float,
		continues := false) -> void:
	if _full():
		return
	var rings := maxi(_g.rings[level] - (1 if level < 2 else 0) * _lod, 2)
	var points: Array[Vector3] = [start]
	var tangents: Array[Vector3] = [dir]
	var heading := dir
	# one smooth bend over the whole length (an arc in a plane through the branch), to either side
	var arc := _g.curve[level]
	var bend_axis := _outward(dir, _rng.randf() * TAU)
	if level == 0 and _g.limb_angle > 65.0:
		# a spreading tree's limbs wander sideways (round the vertical), not up and down
		bend_axis = (bend_axis * 0.3 + Vector3.UP).normalized()
	var bend: float = arc * _rng.randf_range(0.35, 1.0)
	if _rng.randf() < 0.5:
		bend = -bend
	for ring in rings - 1:
		if arc > 0.0:
			heading = heading.rotated(bend_axis, bend / float(rings - 1))
		var wander := Vector3(_rng.randf_range(-1.0, 1.0), _rng.randf_range(-0.4, 0.6),
				_rng.randf_range(-1.0, 1.0))
		var sagging: float = _g.sag[level] + _g.droop * _g.droop_sag[level]
		heading = (heading + wander * _g.wander[level] + Vector3.UP * _g.lift[level]
				+ Vector3.DOWN * sagging).normalized()
		points.append(points[ring] + heading * length / float(rings - 1))
		tangents.append(heading)
	var radii: Array[float] = []
	var colors: Array[Color] = []
	for ring in rings:
		var along := float(ring) / float(rings - 1)
		radii.append(lerpf(radius, radius * _g.tip_radius[level], along))
		var bark := _g.bark.lightened(0.04 * float(level)).darkened(0.12 * (1.0 - along))
		colors.append(Color(bark.r, bark.g, bark.b, sway + _g.sway[level] * along))
	# a branch that continues its parent has the parent's number of sides, so they meet edge to edge
	var sides_level := level - 1 if continues else level
	var sides: int = _g.sides_real[sides_level] if _fine else _g.sides[sides_level]
	sides = maxi(sides - 3 * _lod, 3)
	var last_level := level == _depth - 1
	var closed := MeshBuilder.CAP_TOP if (last_level or not _g.carry_on) else 0
	PlantTreeBuilders.tube(_b, points, radii, colors, sides, _rng, 0.0, closed, false)
	var tip_sway: float = sway + _g.sway[level]
	if _g.foliage == TreeGenome.Foliage.NEEDLE and (last_level or not _g.tips_only):
		var tip_tangent := tangents[tangents.size() - 1]
		if _g.tips_only: # the tufts face up, so together they make a canopy
			tip_tangent = (tip_tangent * 0.35 + Vector3.UP * 0.9).normalized()
		_spray(points[points.size() - 1], tip_tangent,
				_needle_length * (1.0 if level == 0 else 0.8), tip_sway)
		if level == 0 and not _g.tips_only: # and one half way along, so it is not bare between
			_spray(_point_along(points, 0.55), _tangent_along(tangents, 0.55),
					_needle_length * 0.8, sway + _g.sway[0] * 0.55)
	if last_level:
		if _g.foliage == TreeGenome.Foliage.BLADE:
			_leaves_along(points, tangents, sway, level)
		return
	_children(points, tangents, length, radius, level, sway, continues)


func _children(points: Array[Vector3], tangents: Array[Vector3], length: float, radius: float,
		level: int, sway: float, _continues: bool) -> void:
	var total: int = maxi(_g.children[level] - _lod, mini(_g.children[level], 2))
	# on a wide crown a long branch carries more branches and twigs (a full canopy, not bare limbs)
	if _g.crown > 3.5:
		total += mini(int(length / 3.5), 4)
	total = maxi(roundi(float(total) * _thrift), mini(total, 2))
	var spread := total - (1 if _g.carry_on else 0)
	for index in total:
		# the last child grows straight on from the tip: a branch never ends bare
		var leader := _g.carry_on and index == total - 1
		var f := 1.0
		if not leader:
			f = _g.children_from + (_g.children_to - _g.children_from) * float(index) \
					/ float(maxi(spread - 1, 1))
		var at := _point_along(points, f)
		var tangent := _tangent_along(tangents, f)
		var out := _outward(tangent, float(index) * GOLDEN_ANGLE + float(level) * 1.3)
		if _g.children_planar:
			out = tangent.cross(Vector3.UP).normalized() * (1.0 if index % 2 == 0 else -1.0)
		var local_radius := lerpf(radius, radius * _g.tip_radius[level], f)
		var child_sway: float = sway + _g.sway[level] * f
		if leader:
			# the leader IS the parent going on: same point, same thickness, no step
			var on := (tangent * 0.95 + out * 0.25 + Vector3.UP * 0.05).normalized()
			_branch(at, on, length * 0.5, local_radius, level + 1, child_sway, true)
			continue
		var child_dir := (tangent * _g.child_forward + out * _g.child_side
				+ Vector3.UP * _g.child_up).normalized()
		var child_length: float = length * _g.child_length[level] \
				* (_g.child_length_a - _g.child_length_b * f)
		# the child starts inside its parent, not as deep as its far side, so the joint is closed
		# and nothing sticks out at the back
		var buried := local_radius * _g.bury
		_branch(at - child_dir * buried, child_dir, child_length + buried,
				local_radius * _g.child_radius, level + 1, child_sway)


## The single leaves of a twig: on alternate sides, in opposite pairs or in a spiral, and one at the
## tip.
func _leaves_along(points: Array[Vector3], tangents: Array[Vector3], sway: float,
		level: int) -> void:
	var nodes := maxi(roundi(float(5 if _fine else (4 - _lod)) * _thrift), 2)
	if _g.crown > 3.5:
		nodes += 1 # a wide crown: more leaves on each twig
	if _g.leaf_density < 1.0:
		if _rng.randf() > _g.leaf_density: # this twig has no leaves at all
			return
		nodes = maxi(roundi(float(nodes) * _g.leaf_density), 2)
	var gain: float = _g.sway[level]
	for node in nodes:
		var along := 0.3 + 0.65 * float(node) / float(nodes - 1)
		var at := _point_along(points, along)
		var tangent := _tangent_along(tangents, along)
		var here := sway + gain * along # what the twig itself sways at this spot
		match _g.leaf_pattern:
			PlantSpecies.LeafPattern.OPPOSITE:
				_leaf(at, tangent, 0.0, here)
				_leaf(at, tangent, PI, here)
			PlantSpecies.LeafPattern.SPIRAL:
				_leaf(at, tangent, float(node) * GOLDEN_ANGLE, here)
			_:
				_leaf(at, tangent, PI * float(node % 2), here)
	_leaf(points[points.size() - 1], tangents[tangents.size() - 1], 0.0, sway + gain, 0.0)


## One leaf at `at` on a twig running along `tangent`, turned `azimuth` around the twig. A leaf at
## the very tip (`spread` 0) points straight on. `sway` is the twig's own wind weight at `at`.
func _leaf(at: Vector3, tangent: Vector3, azimuth: float, sway: float, spread := 0.7) -> void:
	if _b.leafless or _full():
		return
	var out := _outward(tangent, azimuth)
	var axis := (tangent * 0.6 + out * spread + Vector3.UP * 0.15).normalized()
	var normal := Vector3.UP - axis * axis.dot(Vector3.UP)
	normal = out if normal.length_squared() < 0.01 else normal.normalized()
	normal = normal * 0.8 + out * 0.2
	normal = (normal - axis * axis.dot(normal)).normalized()
	var tone := _g.leaf.lerp(_g.leaf.lightened(0.14), _rng.randf())
	tone = tone.darkened(_rng.randf_range(0.0, 0.18)) # some leaves are darker (in the shade)
	var base_color := tone.darkened(0.3)
	base_color.a = sway # the stalk moves with the twig it grows on
	var tip_color := _g.leaf_tip.lerp(tone, 0.4)
	tip_color.a = minf(sway + LEAF_SWAY, 1.0)
	var curl := -0.12 if _fine else 0.0
	var share := clampf(_g.leaf_aspect * 0.5, 0.5, 2.0) # a long narrow leaf may bend its tip more
	# every leaf is its own: a wide range of sizes (small ones are common), a little wider or
	# narrower, and its own random numbers for the veins in the shader
	var size := _leaf_length * lerpf(0.6, 1.5, pow(_rng.randf(), 1.2))
	PlantLeafShapes.add_leaf(_b, _outline, at, axis, normal, size, 0.1, curl, base_color, tip_color,
			_rng.randf_range(-0.2, 0.2), _rng.randf_range(-0.14, 0.14) * share,
			_rng.randf_range(0.8, 1.2), Vector2(_rng.randf(), _rng.randf()))


## A fan of single needles in the plane of a branch: `axis` is where the branch points.
func _spray(base: Vector3, axis: Vector3, length: float, sway: float) -> void:
	if _b.leafless or _full():
		return
	var count := 11 if _fine else (9 - 3 * _lod)
	var side := axis.cross(Vector3.UP)
	if side.length_squared() < 0.0001:
		side = axis.cross(Vector3.RIGHT)
	side = side.normalized()
	var up := side.cross(axis).normalized()
	var tone := _g.leaf.lerp(_g.leaf.lightened(0.1), _rng.randf())
	var tip_color := Color(0.93, 0.95, 0.98) if _g.frosted else _g.leaf_tip.lerp(tone, 0.3)
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
		_b.add_tri(near - sideways, near + sideways, base + dir * needle, base_color, base_color,
				tip_color)


## A unit vector at right angles to `tangent`, turned `azimuth` around it.
func _outward(tangent: Vector3, azimuth: float) -> Vector3:
	var side := tangent.cross(Vector3.UP)
	if side.length_squared() < 0.0001:
		side = tangent.cross(Vector3.RIGHT)
	return side.normalized().rotated(tangent, azimuth)


func _point_along(points: Array[Vector3], along: float) -> Vector3:
	var scaled := along * float(points.size() - 1)
	var index := mini(int(scaled), points.size() - 2)
	return points[index].lerp(points[index + 1], scaled - float(index))


func _tangent_along(tangents: Array[Vector3], along: float) -> Vector3:
	var scaled := along * float(tangents.size() - 1)
	var index := mini(int(scaled), tangents.size() - 2)
	return tangents[index].lerp(tangents[index + 1], scaled - float(index)).normalized()
