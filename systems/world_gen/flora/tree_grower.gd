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
var _budget := BUDGET ## small plants get a smaller budget
var _lod := 0 ## 0 full tree, 1 the lighter one for trees at a distance
var _fine := false ## the realistic geometry (never in the lighter version)
var _depth := 3 ## levels of branching in this version
var _height := 8.0
var _trunk_length := 2.0 ## metres of trunk: to the limbs, or all the way for a leader
var _tilt := Vector3.ZERO
var _solid_points := PackedVector3Array() ## where limbs and branches already are (for `avoid`)
var _solid_radii := PackedFloat32Array()
var _solid_ids := PackedInt32Array()
var _next_id := 0
var _parent_id := -1
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
	for thrift: float in [1.0, 0.94, 0.88, 0.82, 0.76, 0.7, 0.6, 0.5, 0.4, 0.3, 0.2, 0.12]:
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
		grower._budget = clampi(int(1500.0 + 2000.0 * genome.height), 1500, BUDGET)
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
	if _b.triangle_count() < _budget - MARGIN:
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
	if _g.foliage == TreeGenome.Foliage.FROND and _trunk_length < 0.5:
		return # a fern, grass or flower grows straight from the ground: no trunk
	var rings := (7 if _g.leader else 5) - _lod
	var ringed := _g.bark_rings > 0.0 and _lod == 0
	if ringed: # a bulge and a darker band every bark_rings metres
		rings = clampi(int(_trunk_length / (_g.bark_rings * 0.5)), rings, 40)
	var centres: Array[Vector3] = []
	var radii: Array[float] = []
	var colors: Array[Color] = []
	if _g.trunk_bend > 0.0 or _g.trunk_lumps > 0.0 or _g.flutes > 0:
		rings = maxi(rings, 12 - 3 * _lod)
	var bend_phase := _rng.randf() * TAU
	var lump_phase := _rng.randf() * TAU
	var flute_depths := PackedFloat32Array()
	for index in rings:
		var along := float(index) / float(rings - 1)
		var centre := _axis(_trunk_length * along)
		if _g.trunk_bend > 0.0: # the trunk wanders from side to side
			var sway_by := _g.girth * 2.0 * _g.trunk_bend * sin(along * PI * 1.6 + bend_phase) * along
			centre += Vector3(sway_by, 0.0, sway_by * 0.6 * cos(along * 5.0 + bend_phase))
		centres.append(centre)
		var lumps := 1.0
		if _g.trunk_lumps > 0.0:
			lumps += _g.trunk_lumps * (0.14 * sin(along * TAU * 2.1 + lump_phase)
					+ 0.1 * sin(along * TAU * 4.3 + bend_phase))
		flute_depths.append(_g.flute_depth * (1.0 - 0.6 * along))
		radii.append(_trunk_radius(along) * lumps
				* (1.0 + 0.08 * float(index % 2) if ringed else 1.0))
		colors.append(_still(_g.bark.darkened(_g.trunk_dark * (1.0 - along)
				+ (0.12 if ringed and index % 2 == 1 else 0.0))))
	if not _g.leader:
		# the top of the trunk is a rounded dome the limbs grow out of (a flat cut shows as a disc)
		var top_radius := _g.girth * _g.taper
		var top := centres[centres.size() - 1]
		for dome: Array in [[0.5, 0.8], [0.95, 0.3]]:
			centres.append(top + Vector3(0.0, top_radius * float(dome[0]), 0.0))
			radii.append(top_radius * float(dome[1]))
			colors.append(colors[colors.size() - 1])
	var trunk_sides := _g.trunk_sides - 5 * _lod
	var flutes := _g.flutes if _lod == 0 else 0
	if flutes > 0:
		trunk_sides = maxi(trunk_sides, flutes * 4)
	PlantTreeBuilders.tube(_b, centres, radii, colors, trunk_sides, _rng,
			_g.trunk_wobble * _g.bark_rough, MeshBuilder.CAP_TOP, false, flutes, flute_depths)
	_roots()
	if _g.marked_bark and not _g.leader and _lod == 0: # the dark patches on pale bark
		for mark in int(_trunk_length / 0.8):
			var at := float(mark) * 0.8 + 0.4
			var radius := _trunk_radius(at / _trunk_length) * 1.04
			var patch := _still(Color(0.12, 0.12, 0.1))
			_b.add_frustum(_axis(at), 0.12, radius, radius * 0.99, _g.trunk_sides, patch, patch)


## Roots running out over the ground from the foot of the trunk, thick where they leave it, then
## thinner, sinking into the soil. Not drawn for the lighter distant version.
func _roots() -> void:
	if _g.roots <= 0 or _lod > 0:
		return
	var phase := _rng.randf() * TAU
	for index in _g.roots:
		var yaw := phase + TAU * float(index) / float(_g.roots) + _rng.randf_range(-0.3, 0.3)
		var out := Vector3(cos(yaw), 0.0, sin(yaw))
		var side := Vector3(-out.z, 0.0, out.x)
		var reach := _g.girth * (1.6 + 2.2 * _g.root_reach * _rng.randf_range(0.6, 1.2))
		var thick := _g.girth * _rng.randf_range(0.3, 0.55)
		var rise := _g.girth * _rng.randf_range(0.5, 1.2) # how high up the trunk it starts
		var wander := _rng.randf_range(-0.5, 0.5)
		var centres: Array[Vector3] = []
		var radii: Array[float] = []
		var colors: Array[Color] = []
		var parts := 6
		for step in parts:
			var t := float(step) / float(parts - 1)
			var distance := _g.girth * (0.5 + 1.0 * _g.root_flare) + reach * t
			var height := rise * pow(1.0 - t, 2.2) - 0.12 * t # arches down into the ground
			centres.append(_origin + out * distance + side * wander * reach * t * t
					+ Vector3(0.0, height, 0.0))
			radii.append(thick * lerpf(1.0, 0.18, pow(t, 0.8)) * (1.0 + 0.5 * (1.0 - t) * (1.0 - t)))
			colors.append(_still(_g.bark.darkened(0.12 + 0.1 * t)))
		PlantTreeBuilders.tube(_b, centres, radii, colors, 6, _rng, 0.08, MeshBuilder.CAP_TOP, false)


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
		if _g.flower.a > 0.0:
			steep = lerpf(0.55, 0.95, _rng.randf()) # flower stems stand up
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
	var rib := length * _g.rib_width
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
		# the midrib narrows to the tip: a strip of two triangles per part
		var narrow := 0.4 if _g.flower.a > 0.0 else 0.9 # a flower's stem stays thick up to the bloom
		var wide_a := side * rib * (1.0 - narrow * t)
		var wide_b := side * rib * (1.0 - narrow * (t + 1.0 / float(points.size() - 1)))
		_b.add_tri(a - wide_a, a + wide_a, b + wide_b, base, base, tip)
		_b.add_tri(a - wide_a, b + wide_b, b - wide_b, base, tip, tip)
		# leaflets: one tri per side, hanging from the midrib, longest in the middle of the frond
		var leaflets := (5 if _fine else 3) - _lod if _g.leaflet >= 0.02 else 0
		for leaf_index in leaflets:
			var u := (float(leaf_index) + 0.5) / float(leaflets)
			var at := a.lerp(b, u)
			var shape := pow(sin(PI * clampf(t + u / float(points.size() - 1), 0.05, 0.98)), 0.7)
			var size := length * _g.leaflet * shape * _rng.randf_range(0.85, 1.1)
			var step_len := (b - a).length() / float(leaflets)
			for sign_side: float in [-1.0, 1.0]:
				var dir := (side * sign_side * 0.9 + tangent * 0.5 + Vector3.DOWN * 0.45).normalized()
				var from_colour := tone.darkened(0.2)
				from_colour.a = sway
				var tip_colour := _g.leaf_tip.lerp(tone, 0.3)
				tip_colour.a = minf(sway + LEAF_SWAY, 1.0)
				_b.add_tri(at, at + tangent * step_len, at + dir * size + tangent * step_len * 0.5,
						from_colour, from_colour, tip_colour)
	if _g.flower.a > 0.0:
		_flower(points[points.size() - 1])


## A flower of the genome's ground-plant kind, facing the sky.
func _flower(at: Vector3) -> void:
	_bloom(at, Vector3.UP, _g.flower_size, _g.flower, _g.flower_centre, _g.petals, _g.flower_cup, 0.9)


## One flower at `at` facing `normal`: `petals` petals round a centre, standing up more as `cup`
## grows (0 flat daisy, 1 a closed tulip). `sway` is the wind weight of what it grows on.
func _bloom(at: Vector3, normal: Vector3, size: float, colour: Color, centre: Color, petals: int,
		cup: float, sway: float) -> void:
	if _full():
		return
	var u := normal.cross(Vector3.UP)
	if u.length_squared() < 0.01:
		u = normal.cross(Vector3.RIGHT)
	u = u.normalized()
	var v := normal.cross(u)
	var inner := colour.darkened(0.12)
	inner.a = sway
	var outer := colour.lightened(0.12)
	outer.a = minf(sway + 0.2, 1.0)
	var middle := centre
	middle.a = sway
	var heart := at + normal * size * 0.1
	for index in petals:
		var angle := TAU * float(index) / float(petals)
		var next := TAU * float(index + 1) / float(petals)
		var dir := u * cos(angle) + v * sin(angle)
		var side := v * cos(angle) - u * sin(angle)
		var base := at + dir * size * lerpf(0.2, 0.1, cup)
		var tip := at + dir * size * lerpf(1.0, 0.7, cup) + normal * size * lerpf(0.35, 1.0, cup)
		_b.add_tri(base + side * size * 0.24, base - side * size * 0.24, tip, inner, inner, outer)
		if _fine:
			_b.add_tri(heart, at + dir * size * 0.2,
					at + (u * cos(next) + v * sin(next)) * size * 0.2, middle, middle, middle)


## A soft clump of foliage at a twig's end: a small jittered eight-sided shape in the leaf colours,
## darker underneath. Many of them make a crown look like a mass instead of scattered leaves.
func _mass(at: Vector3, sway: float) -> void:
	if _g.foliage_mass <= 0.0 or _lod > 0 or _full() or _rng.randf() > _g.foliage_mass:
		return
	var size := _leaf_length * _g.mass_size * _rng.randf_range(1.4, 2.2)
	var tone := _g.leaf.lerp(_g.leaf_tip, _rng.randf() * 0.5).darkened(_rng.randf_range(0.0, 0.2))
	var low := tone.darkened(0.3)
	low.a = sway
	var high := tone
	high.a = minf(sway + LEAF_SWAY, 1.0)
	var middle := tone.darkened(0.12)
	middle.a = minf(sway + 0.2, 1.0)
	var centre := at + Vector3(0.0, size * 0.25, 0.0)
	var axes: Array[Vector3] = [Vector3.RIGHT, Vector3.UP * 0.35, Vector3.BACK]
	var ends: Array[Array] = [[], [], []]
	for axis in 3:
		for sign_side: float in [1.0, -1.0]:
			var jitter := Vector3(_rng.randf_range(-0.35, 0.35), _rng.randf_range(-0.2, 0.2),
					_rng.randf_range(-0.35, 0.35))
			ends[axis].append(centre + (axes[axis] * sign_side + jitter) * size)
	for sx in 2:
		for sy in 2:
			for sz in 2:
				var corner_x: Vector3 = ends[0][sx]
				var corner_y: Vector3 = ends[1][sy]
				var corner_z: Vector3 = ends[2][sz]
				var flip := (sx + sy + sz) % 2 == 1
				var a_color := high if sy == 0 else low
				var side_color := middle
				if flip:
					_b.add_tri(corner_y, corner_x, corner_z, a_color, side_color, side_color)
				else:
					_b.add_tri(corner_y, corner_z, corner_x, a_color, side_color, side_color)


## Blossom on a twig: a single flower or two (`SINGLE`), a hanging stem of flowers like a bird
## cherry's (`RACEME`), or a round cluster (`UMBEL`).
func _blossoms(points: Array[Vector3], tangents: Array[Vector3], sway: float) -> void:
	if _g.blossom.a <= 0.0 or _rng.randf() > _g.blossom_density:
		return
	var size := _g.blossom_size * _rng.randf_range(0.8, 1.2)
	var tip := points[points.size() - 1]
	var tangent := tangents[tangents.size() - 1]
	var colour := _g.blossom.lerp(_g.blossom.lightened(0.15), _rng.randf())
	match _g.blossom_kind:
		TreeGenome.Bloom.RACEME:
			var hang := (tangent * 0.35 + Vector3.DOWN * 0.65).normalized()
			var length := size * 8.0
			var count := 6 if _fine else 4
			var green := _g.leaf.darkened(0.2)
			green.a = sway
			var green_tip := green
			green_tip.a = minf(sway + 0.3, 1.0)
			var side := _outward(hang, _rng.randf() * TAU) * size * 0.07
			_b.add_tri(tip - side, tip + side, tip + hang * length, green, green, green_tip)
			for index in count:
				var t := (float(index) + 0.5) / float(count)
				var out := _outward(hang, float(index) * GOLDEN_ANGLE)
				_bloom(tip + hang * length * t + out * size * 0.5,
						(out * 0.9 + Vector3.UP * 0.2).normalized(), size * (1.0 - 0.4 * t), colour,
						_g.flower_centre, _g.petals, _g.flower_cup, minf(sway + 0.3, 1.0))
		TreeGenome.Bloom.UMBEL:
			var middle := tip + (tangent * 0.3 + Vector3.UP * 0.5).normalized() * size * 1.4
			for index in 5:
				var out := _outward(Vector3.UP, float(index) * GOLDEN_ANGLE * 2.0)
				_bloom(middle + out * size * 1.1, (out * 0.6 + Vector3.UP).normalized(), size * 0.9,
						colour, _g.flower_centre, _g.petals, _g.flower_cup, minf(sway + 0.3, 1.0))
		_:
			for index in 3:
				var at := _point_along(points, 0.4 + 0.3 * float(index))
				var out := _outward(tangent, _rng.randf() * TAU)
				_bloom(at + out * size * 0.4, (out * 0.6 + Vector3.UP * 0.6).normalized(), size,
						colour, _g.flower_centre, _g.petals, _g.flower_cup, minf(sway + 0.3, 1.0))


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
	var my_id := _next_id
	_next_id += 1
	var parent_id := _parent_id
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
	var wave_phase := _rng.randf() * TAU
	var wave_count := _rng.randf_range(1.0, 2.2)
	var ground := radius * 0.7 # a branch that sags to the ground lies on it
	for ring in rings - 1:
		if arc > 0.0:
			var turn := bend / float(rings - 1)
			if _g.twist > 0.0: # S-curves: the bend changes side along the branch
				var wave := sin(wave_phase + wave_count * TAU * float(ring) / float(rings - 1))
				turn *= (1.0 - _g.twist) + _g.twist * 2.0 * wave
			heading = heading.rotated(bend_axis, turn)
			if _g.twist > 0.0: # and the plane of the bend turns, so the branch winds in 3D
				bend_axis = bend_axis.rotated(heading, _g.twist * 0.3)
		var wander := Vector3(_rng.randf_range(-1.0, 1.0), _rng.randf_range(-0.4, 0.6),
				_rng.randf_range(-1.0, 1.0))
		var sagging: float = _g.sag[level] + _g.droop * _g.droop_sag[level]
		heading = (heading + wander * _g.wander[level] + Vector3.UP * _g.lift[level]
				+ Vector3.DOWN * sagging).normalized()
		var next := points[ring] + heading * length / float(rings - 1)
		if _g.avoid and level < 2:
			var here := lerpf(radius, radius * _g.tip_radius[level], float(ring + 1) / float(rings - 1))
			if ring >= 1:
				heading = _steer_clear(next, heading, here, my_id, parent_id)
				next = points[ring] + heading * length / float(rings - 1)
			_solid_points.append(next)
			_solid_radii.append(here)
			_solid_ids.append(my_id)
		if next.y < ground and level < 2:
			next.y = ground
			heading = Vector3(heading.x, maxf(heading.y, 0.0), heading.z).normalized()
		points.append(next)
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
	_parent_id = my_id
	_children(points, tangents, length, radius, level, sway, continues)
	_parent_id = parent_id


## `heading` turned away from any other limb or branch that `spot` (a point of the one being grown,
## `radius` thick) would run into. Its own branch and its parent are not counted.
func _steer_clear(spot: Vector3, heading: Vector3, radius: float, my_id: int,
		parent_id: int) -> Vector3:
	var push := Vector3.ZERO
	for index in _solid_points.size():
		var id := _solid_ids[index]
		if id == my_id or id == parent_id:
			continue
		var away := spot - _solid_points[index]
		var wanted := radius + _solid_radii[index] + 0.1
		var distance := away.length()
		if distance < wanted and distance > 0.001:
			push += away / distance * (wanted - distance) / wanted
	if push == Vector3.ZERO:
		return heading
	return (heading + push * 1.5).normalized()


func _children(points: Array[Vector3], tangents: Array[Vector3], length: float, radius: float,
		level: int, sway: float, _continues: bool) -> void:
	var total: int = maxi(_g.children[level] - _lod, mini(_g.children[level], 2))
	# on a wide crown a long branch carries more branches and twigs (a full canopy, not bare limbs)
	if _g.crown > 3.5 and not (_g.avoid and level == 1):
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
				local_radius * _g.child_radius * (_g.twig_radius if level == 1 else 1.0), level + 1,
				child_sway)


## The single leaves of a twig: on alternate sides, in opposite pairs or in a spiral, and one at the
## tip.
func _leaves_along(points: Array[Vector3], tangents: Array[Vector3], sway: float,
		level: int) -> void:
	_blossoms(points, tangents, sway)
	_mass(points[points.size() - 1], sway)
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
	if _g.compound:
		_feather(at, axis, normal, size * 1.6, base_color, tip_color)
		return
	PlantLeafShapes.add_leaf(_b, _outline, at, axis, normal, size, 0.1, curl, base_color, tip_color,
			_rng.randf_range(-0.2, 0.2), _rng.randf_range(-0.14, 0.14) * share,
			_rng.randf_range(0.8, 1.2), Vector2(_rng.randf(), _rng.randf()))


## A compound leaf: a stalk with pairs of small leaflets along it, one at the tip.
func _feather(at: Vector3, axis: Vector3, normal: Vector3, length: float, base_color: Color,
		tip_color: Color) -> void:
	var across := axis.cross(normal).normalized()
	var pairs := 4 if _fine else 3
	var stalk_end := at + axis * length
	var stalk := across * length * 0.02
	_b.add_tri(at - stalk, at + stalk, stalk_end, base_color, base_color, tip_color)
	for index in pairs:
		var t := (float(index) + 0.6) / float(pairs)
		var on := at + axis * length * t
		var leaflet := length * 0.3 * (1.0 - 0.45 * t)
		var color := base_color.lerp(tip_color, t)
		for sign_side: float in [-1.0, 1.0]:
			var reach := on + (across * sign_side * 0.9 + axis * 0.45 + normal * 0.15) * leaflet
			_b.add_tri(on, on + axis * leaflet * 0.5, reach, color, color, tip_color)
	_b.add_tri(stalk_end - across * leaflet_width(length), stalk_end + across * leaflet_width(length),
			stalk_end + axis * length * 0.22, tip_color, tip_color, tip_color)


func leaflet_width(length: float) -> float:
	return length * 0.07


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
