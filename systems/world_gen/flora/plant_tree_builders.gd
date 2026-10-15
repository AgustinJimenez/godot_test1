class_name PlantTreeBuilders
extends RefCounted
## The tree growth forms: each draws one mesh of a PlantSpecies from its numbers (see the field
## notes in plant_species.gd). Vertex colour alpha = how much a vertex sways in the wind, like every
## plant.


static func _still(color: Color) -> Color:
	return Color(color.r, color.g, color.b, 0.0)


static func _sway(color: Color, amount: float) -> Color:
	return Color(color.r, color.g, color.b, amount)


## Spruce, fir, pine: a trunk under stacked cones.
static func conifer(builder: MeshBuilder, s: PlantSpecies, rng: RandomNumberGenerator) -> void:
	var height := s.height * rng.randf_range(0.9, 1.1)
	var trunk := height * s.bare
	builder.add_frustum(Vector3.ZERO, trunk * 1.5, s.girth, s.girth * 0.55, 6,
			_still(s.bark.darkened(0.3)), _still(s.bark), rng, s.wobble * 0.7)
	var tiers := s.count + rng.randi_range(-1, 1)
	var green := s.leaf.lerp(s.leaf.lightened(0.1), rng.randf())
	var top_color := Color(0.93, 0.95, 0.98) if s.frosted else s.leaf_tip
	for tier in tiers:
		var along := float(tier) / float(tiers)
		var base_y := trunk * 0.8 + along * (height - trunk) * 0.78
		# tiers shrink evenly up the tree; only a hair of jitter so they do not look machined
		var radius := lerpf(s.crown, s.crown * 0.4, along) * rng.randf_range(0.97, 1.03)
		var tier_height := (height - base_y) * lerpf(0.3, 0.5, s.droop)
		builder.add_frustum(Vector3(0.0, base_y, 0.0), tier_height, radius, 0.0, 7,
				_sway(green.darkened(0.12), 0.35),
				_sway(top_color.lerp(green.lightened(0.12 * along + 0.05), 0.0 if s.frosted else 1.0), 1.0),
				rng, s.wobble, MeshBuilder.CAP_BOTTOM)


## Oak, maple, birch, willow: a trunk that forks under a crown of lumpy balls.
static func broadleaf(builder: MeshBuilder, s: PlantSpecies, rng: RandomNumberGenerator) -> void:
	var height := s.height * rng.randf_range(0.9, 1.1)
	var trunk := height * s.bare
	var tilt := Vector3(rng.randf_range(-1.0, 1.0), 0.0, rng.randf_range(-1.0, 1.0)).normalized() \
			* s.lean * height
	_trunk(builder, s, rng, trunk, tilt)
	if s.marked_bark: # the dark patches on pale bark
		for mark in int(trunk / 0.8):
			var at := float(mark) * 0.8 + 0.4
			var radius := lerpf(s.girth, s.girth * s.taper, at / trunk) * 1.04
			builder.add_frustum(_trunk_centre(tilt, trunk, at / trunk), 0.12, radius, radius * 0.99,
					6, _still(Color(0.12, 0.12, 0.1)), _still(Color(0.12, 0.12, 0.1)))
	var top := tilt + Vector3(0.0, trunk, 0.0)
	var crown_height := (height - trunk) * 0.5
	var centre := top + Vector3(0.0, crown_height * 0.7, 0.0)
	var reach := s.crown * 0.7
	# The crown is built evenly: the forks leave the trunk at equal angles with equal reach, each
	# one ends in a lump of leaves, and the remaining lumps sit on the axis and on a ring between
	# the forks, so the divisions look the same all round and the canopy has no gaps. (One fork
	# would only look like a crooked branch.)
	var forks := 0 if s.extra == 1 else s.extra
	var phase := rng.randf() * TAU
	var rise := crown_height * 0.9
	var spots: Array[Vector3] = []
	for branch in forks:
		var yaw := phase + TAU * float(branch) / float(forks) + rng.randf_range(-0.1, 0.1)
		var out := Vector3(cos(yaw), 0.0, sin(yaw)) * reach * rng.randf_range(0.9, 1.0)
		builder.xf = Transform3D(Basis.looking_at(out + Vector3(0.0, rise, 0.0), Vector3.UP)
				* Basis(Vector3.RIGHT, -PI * 0.5), top - Vector3(0.0, 0.2, 0.0))
		builder.add_frustum(Vector3.ZERO, (out + Vector3(0.0, rise, 0.0)).length(),
				s.girth * 0.45, s.girth * 0.18, 5, _still(s.bark.darkened(0.2)), _still(s.bark))
		builder.xf = Transform3D.IDENTITY
		spots.append(top + out + Vector3(0.0, rise, 0.0))
	if spots.size() < s.count:
		spots.append(centre)
	var ring := s.count - spots.size()
	for index in ring:
		var yaw := phase + PI / float(maxi(forks, 1)) + TAU * float(index) / float(ring)
		spots.append(centre + Vector3(cos(yaw), 0.0, sin(yaw)) * reach * 0.6)
	for spot_at in spots:
		var spot := spot_at + Vector3(rng.randf_range(-0.08, 0.08) * reach,
				rng.randf_range(-0.08, 0.08) * crown_height, rng.randf_range(-0.08, 0.08) * reach)
		var size := s.crown * rng.randf_range(0.7, 0.9)
		# weeping crowns hang lower toward the rim
		spot.y -= s.droop * Vector2(spot.x - top.x, spot.z - top.z).length() * 0.5
		spot.y = maxf(spot.y, top.y + size * 0.4) # never hangs below the trunk's top
		var radius := Vector3(size, size * s.aspect * rng.randf_range(0.8, 1.0), size)
		var tone := s.leaf.lerp(s.leaf.lightened(0.08), rng.randf())
		builder.add_blob(spot, radius, _sway(tone.darkened(0.25), 0.4), _sway(s.leaf_tip, 1.0), rng,
				s.wobble + 0.06)
		if builder.detailed:
			builder.add_leaf_cards(spot, radius, int(30.0 * size), 0.5, _sway(tone.darkened(0.15), 0.8),
					_sway(s.leaf_tip.lightened(0.1), 1.0), rng)


## A palm: a bent trunk of stacked pieces with a ring of arching fronds.
static func palm(builder: MeshBuilder, s: PlantSpecies, rng: RandomNumberGenerator) -> void:
	var height := s.height * rng.randf_range(0.9, 1.1)
	var lean := Vector3(rng.randf_range(-1.0, 1.0), 0.0, rng.randf_range(-1.0, 1.0)).normalized() \
			* height * s.lean * rng.randf_range(0.6, 1.4)
	# one continuous bent trunk; the slight bulge on every other ring gives the palm's ringed look
	var rings := 9
	var centres: Array[Vector3] = []
	var radii: Array[float] = []
	var colors: Array[Color] = []
	for index in rings:
		var along := float(index) / float(rings - 1)
		centres.append(Vector3(lean.x * along * along, height * along, lean.z * along * along))
		radii.append((s.girth - along * s.girth * 0.3) * (1.0 + 0.07 * float(index % 2)))
		colors.append(_still(s.bark.darkened(0.15 * (1.0 - along))))
	_tube(builder, centres, radii, colors, 6, rng, 0.03)
	builder.xf = Transform3D(Basis.IDENTITY, centres[rings - 1])
	for frond in s.count:
		var yaw := TAU * float(frond) / float(s.count) + rng.randf_range(-0.2, 0.2)
		var out := Vector3(cos(yaw), 0.0, sin(yaw))
		var side := Vector3(-out.z, 0.0, out.x) * s.crown * 0.11
		var tip := out * s.crown * rng.randf_range(0.8, 1.05) \
				+ Vector3(0.0, -rng.randf_range(0.5, 1.2), 0.0)
		var mid := out * s.crown * 0.45 + Vector3(0.0, 0.55, 0.0)
		builder.add_tri(-side * 0.3, side * 0.3, mid + side, _sway(s.leaf.darkened(0.2), 0.3),
				_sway(s.leaf.darkened(0.2), 0.3), _sway(s.leaf, 0.8))
		builder.add_tri(mid + side, mid - side, tip, _sway(s.leaf, 0.8), _sway(s.leaf, 0.8),
				_sway(s.leaf_tip, 1.0))
		builder.add_tri(-side * 0.3, mid + side, mid - side, _sway(s.leaf.darkened(0.2), 0.3),
				_sway(s.leaf, 0.8), _sway(s.leaf, 0.8))
	builder.xf = Transform3D.IDENTITY


## A dead tree: a tapering trunk with bare branches.
static func bare_tree(builder: MeshBuilder, s: PlantSpecies, rng: RandomNumberGenerator) -> void:
	var height := s.height * rng.randf_range(0.85, 1.15)
	builder.add_frustum(Vector3.ZERO, height, s.girth, s.girth * 0.27, 6, _still(s.bark.darkened(0.2)),
			_still(s.bark), rng, 0.12)
	for branch in s.count + rng.randi_range(-1, 1):
		builder.xf = Transform3D(Basis(Vector3.UP, rng.randf() * TAU)
				* Basis(Vector3.RIGHT, rng.randf_range(0.7, 1.2)),
				Vector3(0.0, height * rng.randf_range(0.45, 0.85), 0.0))
		builder.add_frustum(Vector3.ZERO, rng.randf_range(1.0, 1.9) * height * 0.25, s.girth * 0.3,
				s.girth * 0.07, 4, _still(s.bark.darkened(0.1)), _still(s.bark.lightened(0.1)))
	builder.xf = Transform3D.IDENTITY


## A far (horizon) tree: one cone or one trunk and ball, so a distant forest costs next to nothing.
static func far(builder: MeshBuilder, s: PlantSpecies, rng: RandomNumberGenerator) -> void:
	if s.form == PlantSpecies.Form.CONIFER:
		var green := s.leaf.lerp(s.leaf_tip, 0.3)
		builder.add_frustum(Vector3(0.0, 0.8, 0.0), s.height * rng.randf_range(0.9, 1.1), s.crown * 0.95,
				0.0, 5, _still(green.darkened(0.1)), _still(green.lightened(0.1)), rng, 0.1,
				MeshBuilder.CAP_BOTTOM)
		return
	var trunk := s.height * s.bare
	builder.add_frustum(Vector3.ZERO, trunk, s.girth, s.girth * 0.6, 4, _still(s.bark.darkened(0.3)),
			_still(s.bark))
	var size := s.crown * 1.3
	builder.add_blob(Vector3(0.0, trunk + (s.height - trunk) * 0.55, 0.0),
			Vector3(size, size * s.aspect * 0.8, size), _still(s.leaf.darkened(0.25)),
			_still(s.leaf_tip), rng, 0.2)


static func _trunk(builder: MeshBuilder, s: PlantSpecies, rng: RandomNumberGenerator, trunk: float,
		tilt: Vector3) -> void:
	var rings := 5
	var centres: Array[Vector3] = []
	var radii: Array[float] = []
	var colors: Array[Color] = []
	for index in rings:
		var along := float(index) / float(rings - 1)
		centres.append(_trunk_centre(tilt, trunk, along))
		radii.append(lerpf(s.girth, s.girth * s.taper, along))
		colors.append(_still(s.bark.darkened(0.25 * (1.0 - along))))
	_tube(builder, centres, radii, colors, 7, rng, 0.06)


## Where the axis of a leaning trunk is at `along` (0 foot, 1 top): it leans more toward the top.
static func _trunk_centre(tilt: Vector3, trunk: float, along: float) -> Vector3:
	return Vector3(tilt.x * along * along, trunk * along, tilt.z * along * along)


## One continuous tube through ring centres. Neighbouring pieces share their ring, so a leaning or
## bending trunk has no steps, gaps or colour bands (stacked separate cones had all three).
static func _tube(builder: MeshBuilder, centres: Array[Vector3], radii: Array[float],
		colors: Array[Color], sides: int, rng: RandomNumberGenerator, wobble: float) -> void:
	if builder.detailed and sides >= 5:
		sides *= 2
	var rings: Array[PackedVector3Array] = []
	for ring in centres.size():
		var points := PackedVector3Array()
		for index in sides:
			var angle := TAU * float(index) / float(sides)
			var jitter := 1.0 + rng.randf_range(-wobble, wobble)
			points.append(centres[ring] + Vector3(cos(angle), 0.0, sin(angle)) * radii[ring] * jitter)
		rings.append(points)
	for ring in centres.size() - 1:
		for index in sides:
			var next := (index + 1) % sides
			var low: Color = colors[ring]
			var high: Color = colors[ring + 1]
			builder.add_tri(rings[ring][index], rings[ring + 1][index], rings[ring][next], low, high, low)
			builder.add_tri(rings[ring][next], rings[ring + 1][index], rings[ring + 1][next], low, high,
					high)
