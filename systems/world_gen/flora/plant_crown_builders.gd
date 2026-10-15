class_name PlantCrownBuilders
extends RefCounted
## The crown of a broadleaf tree as it really grows: limbs leave the top of the trunk, each limb
## carries branches, each branch carries twigs, and every twig carries single leaves with the
## species' own outline (PlantLeafShapes). It replaces the old crown of lumpy balls, one leaf shape
## at a time: `supports()` says which species already get it.
##
## Wind: the vertex colour alpha is how much a vertex sways. It grows smoothly from 0 at the top of
## the trunk out to the leaf tips, and a child starts with the value its parent has at that spot, so
## a branch and what it carries always move together and a joint never pulls apart.

const GOLDEN_ANGLE := 2.39996323
## The leaf kinds that have been built (and looked at) so far; their trees get this crown.
const IMPLEMENTED := [PlantSpecies.LeafShape.OVAL, PlantSpecies.LeafShape.LOBED,
		PlantSpecies.LeafShape.PALMATE, PlantSpecies.LeafShape.HEART,
		PlantSpecies.LeafShape.DIAMOND, PlantSpecies.LeafShape.LANCEOLATE]
const RINGS := [6, 5, 3] ## rings of a limb, a branch, a twig (more rings = a rounder curve)
const SIDES := [11, 8, 5] ## sides of a limb, a branch, a twig (low-poly)
const SIDES_REAL := [12, 10, 6] ## and in the realistic look
const WANDER := [0.06, 0.08, 0.1] ## a little irregularity on top of the curve
const CURVE := [0.5, 0.8, 1.2] ## the most a limb, a branch, a twig bends over its length (radians)
const LIFT := [0.08, 0.05, 0.0] ## how much each ring reaches for the sky
const SAG := [0.0, 0.04, 0.1] ## and how much it sags (thin twigs bend under their leaves)
const DROOP_SAG := [0.0, 0.14, 0.3] ## more sag per unit of the species' droop (a weeping willow)
const SWAY_GAIN := [0.16, 0.2, 0.22] ## sway added from the start to the end of a limb, branch, twig
const LEAF_SWAY_GAIN := 0.45 ## and from the stalk to the tip of a leaf
const CHILD_RADIUS := 0.6 ## a child's radius, as a share of its parent's radius where it leaves
const TIP_RADIUS := [0.4, 0.25, 0.05] ## the radius at the end of a limb, a branch, a twig (a point)
const BURY := 0.4 ## how deep a child starts inside its parent, as a share of the parent's radius

var _builder: MeshBuilder
var _s: PlantSpecies
var _rng: RandomNumberGenerator
var _outline: PackedVector2Array
var _centre := Vector3.ZERO
var _radius_h := 1.0
var _radius_v := 1.0
var _leaf_length := 0.3
var _leaves := 0


## Which species get the branch-and-leaf crown (the others still have the old one).
static func supports(s: PlantSpecies) -> bool:
	return s.leaf_shape in IMPLEMENTED


func _init(builder: MeshBuilder, s: PlantSpecies, rng: RandomNumberGenerator) -> void:
	_builder = builder
	_s = s
	_rng = rng
	_outline = PlantLeafShapes.outline(s, builder.detailed)


## Grows the crown on a trunk that ends at `top`; `crown_height` is the height of the crown.
func grow(top: Vector3, crown_height: float) -> void:
	_centre = top + Vector3(0.0, crown_height * 0.7, 0.0)
	_radius_h = _s.crown * 1.8
	_radius_v = maxf(crown_height * 0.85, _s.crown * _s.aspect)
	# the low-poly look has fewer, bigger leaves
	_leaf_length = _s.crown * _s.leaf_size * (1.7 if _builder.detailed else 2.5)
	var limb_radius := _s.girth * _s.taper * 0.7
	var phase := _rng.randf() * TAU
	for index in _s.limb_count:
		var yaw := phase + float(index) * GOLDEN_ANGLE
		var pitch := deg_to_rad(_s.limb_angle * _rng.randf_range(0.85, 1.15))
		var dir := Vector3(sin(pitch) * cos(yaw), cos(pitch), sin(pitch) * sin(yaw))
		# the limbs start well down in the trunk's rounded top, so it narrows into them
		var start := top + Vector3(0.0, -limb_radius * 2.0 + float(index) * limb_radius * 0.6, 0.0)
		start -= dir * limb_radius * 0.5 # inside the trunk top, not out of its far side
		var length := clampf(_radius_h * 0.85 / maxf(sin(pitch), 0.35), _radius_h * 0.6,
				_radius_h * 1.3)
		length = minf(length, (_centre.y + _radius_v - start.y) / maxf(cos(pitch), 0.2))
		_branch(start, dir, length, limb_radius, 0, 0.0)


## One limb (depth 0), branch (1) or twig (2): a tube that bends a little as it goes, then whatever
## it carries. `sway` is the wind weight at its start (see the top of the file).
func _branch(start: Vector3, dir: Vector3, length: float, radius: float, depth: int,
		sway: float, continues := false) -> void:
	var rings: int = RINGS[depth]
	var points: Array[Vector3] = [start]
	var tangents: Array[Vector3] = [dir]
	var heading := dir
	# one smooth bend over the whole length (an arc in a plane through the branch), to either side,
	# more for the smaller branches; the rings then follow the arc
	var bend_axis := _outward(dir, _rng.randf() * TAU)
	var bend: float = CURVE[depth] * _rng.randf_range(0.35, 1.0)
	if _rng.randf() < 0.5:
		bend = -bend
	for ring in rings - 1:
		heading = heading.rotated(bend_axis, bend / float(rings - 1))
		var wander := Vector3(_rng.randf_range(-1.0, 1.0), _rng.randf_range(-0.4, 0.6),
				_rng.randf_range(-1.0, 1.0))
		heading = (heading + wander * WANDER[depth] + Vector3.UP * LIFT[depth]
				+ Vector3.DOWN * (SAG[depth] + _s.droop * DROOP_SAG[depth])).normalized()
		points.append(points[ring] + heading * length / float(rings - 1))
		tangents.append(heading)
	var radii: Array[float] = []
	var colors: Array[Color] = []
	for ring in rings:
		var along := float(ring) / float(rings - 1)
		radii.append(lerpf(radius, radius * TIP_RADIUS[depth], along))
		var bark := _s.bark.lightened(0.04 * float(depth)).darkened(0.12 * (1.0 - along))
		colors.append(Color(bark.r, bark.g, bark.b, sway + SWAY_GAIN[depth] * along))
	# a branch that continues its parent keeps the parent's number of sides, so the two meet
	# edge to edge; a parent that is continued is not closed at its end
	var sides_depth := depth - 1 if continues else depth
	var sides: int = SIDES_REAL[sides_depth] if _builder.detailed else SIDES[sides_depth]
	var closed_end := MeshBuilder.CAP_TOP if depth == 2 else 0
	PlantTreeBuilders.tube(_builder, points, radii, colors, sides, _rng, 0.0, closed_end, false)
	if depth == 2:
		_leaves_along(points, tangents, sway)
		return
	var children := 4
	for index in children:
		# the last child grows straight on from the tip: a branch never ends bare, it ends in twigs
		var leader := index == children - 1
		var along := 1.0 if leader else 0.3 + 0.55 * float(index) / float(children - 2)
		var at := _point_along(points, along)
		var tangent := _tangent_along(tangents, along)
		var out := _outward(tangent, float(index) * GOLDEN_ANGLE + float(depth) * 1.3)
		# the others leave at a wide angle, so the pieces do not run on in a row
		var child_dir := (tangent * 0.4 + out * 0.9 + Vector3.UP * 0.25).normalized()
		var child_length := length * (0.55 if depth == 0 else 0.5) * (1.25 - 0.5 * along)
		if leader:
			child_dir = (tangent * 0.95 + out * 0.25 + Vector3.UP * 0.05).normalized()
			child_length = length * 0.5
		var local_radius := lerpf(radius, radius * TIP_RADIUS[depth], along)
		# the child starts inside its parent, not as deep as its far side, so the joint is closed and
		# nothing sticks out at the back
		var buried := local_radius * BURY
		if leader:
			# the leader IS the parent going on: same point, same thickness, no step
			_branch(at, child_dir, child_length, local_radius, depth + 1,
					sway + SWAY_GAIN[depth] * along, true)
			continue
		_branch(at - child_dir * buried, child_dir, child_length + buried,
				local_radius * CHILD_RADIUS, depth + 1, sway + SWAY_GAIN[depth] * along)


## The single leaves of a twig: on alternate sides, in opposite pairs or in a spiral, and one at the
## tip.
func _leaves_along(points: Array[Vector3], tangents: Array[Vector3], sway: float) -> void:
	var nodes := 4 if not _builder.detailed else 5
	for node in nodes:
		var along := 0.3 + 0.65 * float(node) / float(nodes - 1)
		var at := _point_along(points, along)
		var tangent := _tangent_along(tangents, along)
		var here := sway + SWAY_GAIN[2] * along # what the twig itself sways at this spot
		match _s.leaf_pattern:
			PlantSpecies.LeafPattern.OPPOSITE:
				_leaf(at, tangent, 0.0, here)
				_leaf(at, tangent, PI, here)
			PlantSpecies.LeafPattern.SPIRAL:
				_leaf(at, tangent, float(node) * GOLDEN_ANGLE, here)
			_:
				_leaf(at, tangent, PI * float(node % 2), here)
	_leaf(points[points.size() - 1], tangents[tangents.size() - 1], 0.0, sway + SWAY_GAIN[2], 0.0)


## One leaf at `at` on a twig running along `tangent`, turned `azimuth` around the twig. A leaf at
## the very tip (`spread` 0) points straight on. `sway` is the twig's own wind weight at `at`.
func _leaf(at: Vector3, tangent: Vector3, azimuth: float, sway: float, spread := 0.7) -> void:
	if _builder.leafless:
		return
	var out := _outward(tangent, azimuth)
	var axis := (tangent * 0.6 + out * spread + Vector3.UP * 0.15).normalized()
	var normal := Vector3.UP - axis * axis.dot(Vector3.UP)
	normal = out if normal.length_squared() < 0.01 else normal.normalized()
	normal = (normal * 0.8 + out * 0.2)
	normal = (normal - axis * axis.dot(normal)).normalized()
	var tone := _s.leaf.lerp(_s.leaf.lightened(0.1), _rng.randf())
	var base_color := tone.darkened(0.3)
	base_color.a = sway # the stalk moves with the twig it grows on
	var tip_color := _s.leaf_tip.lerp(tone, 0.4)
	tip_color.a = minf(sway + LEAF_SWAY_GAIN, 1.0)
	var curl := -0.12 if _builder.detailed else 0.0
	PlantLeafShapes.add_leaf(_builder, _outline, at, axis, normal,
			_leaf_length * _rng.randf_range(0.8, 1.2), 0.1, curl, base_color, tip_color,
			_rng.randf_range(-0.18, 0.18), _rng.randf_range(-0.12, 0.12) * _leaf_aspect_share())
	_leaves += 1


## How much a leaf's tip may bend sideways: more for a long narrow leaf, less for a broad one.
func _leaf_aspect_share() -> float:
	return clampf(_s.leaf_aspect * 0.5, 0.5, 2.0)


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
