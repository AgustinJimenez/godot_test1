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
		var radius := lerpf(s.crown, s.crown * 0.4, along) * rng.randf_range(0.9, 1.1)
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
			var shift := tilt * (at / trunk) * (at / trunk)
			builder.add_frustum(Vector3(shift.x, at, shift.z), 0.12, s.girth * 1.02, s.girth * 1.01,
					6, _still(Color(0.12, 0.12, 0.1)), _still(Color(0.12, 0.12, 0.1)))
	var top := tilt + Vector3(0.0, trunk, 0.0)
	var crown_height := (height - trunk) * 0.5
	var centre := top + Vector3(0.0, crown_height * 0.7, 0.0)
	var reach := s.crown * 0.7
	for branch in s.extra: # forks reaching toward the crown
		var yaw := rng.randf() * TAU
		var out := Vector3(cos(yaw), 0.0, sin(yaw)) * reach * rng.randf_range(0.5, 0.9)
		builder.xf = Transform3D(Basis.looking_at(out + Vector3(0.0, crown_height, 0.0), Vector3.UP)
				* Basis(Vector3.RIGHT, -PI * 0.5), top - Vector3(0.0, 0.2, 0.0))
		builder.add_frustum(Vector3.ZERO, (out + Vector3(0.0, crown_height, 0.0)).length(),
				s.girth * 0.45, s.girth * 0.18, 5, _still(s.bark.darkened(0.2)), _still(s.bark))
		builder.xf = Transform3D.IDENTITY
	for lump in s.count:
		var spot := centre + Vector3(rng.randf_range(-1.0, 1.0) * reach,
				rng.randf_range(-1.0, 1.0) * crown_height * 0.55, rng.randf_range(-1.0, 1.0) * reach)
		var size := s.crown * rng.randf_range(0.62, 0.95)
		# weeping crowns hang lower toward the rim
		spot.y -= s.droop * Vector2(spot.x - top.x, spot.z - top.z).length() * 0.5
		spot.y = maxf(spot.y, top.y + size * 0.4) # never hangs below the trunk's top
		var radius := Vector3(size, size * s.aspect * rng.randf_range(0.75, 1.0), size)
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
	var segments := 5
	var top := Vector3.ZERO
	for index in segments:
		var along := float(index) / float(segments)
		var shift := lean * along * along
		builder.xf = Transform3D(Basis.IDENTITY, Vector3(shift.x, height * along, shift.z))
		builder.add_frustum(Vector3.ZERO, height / float(segments) * 1.05,
				s.girth - along * s.girth * 0.3, s.girth * 0.9 - (along + 0.2) * s.girth * 0.3, 6,
				_still(s.bark.darkened(0.15 * (1.0 - along))), _still(s.bark), rng, 0.04)
		top = Vector3(shift.x, height * along, shift.z)
	builder.xf = Transform3D(Basis.IDENTITY, top + Vector3(lean.x * 0.2, height / float(segments),
			lean.z * 0.2))
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
	var pieces := 3
	for index in pieces: # a leaning trunk is a few short stacked pieces
		var from := float(index) / float(pieces)
		var to := float(index + 1) / float(pieces)
		var shift := tilt * from * from
		builder.xf = Transform3D(Basis.IDENTITY, Vector3(shift.x, trunk * from, shift.z))
		builder.add_frustum(Vector3.ZERO, trunk / float(pieces) * 1.02,
				lerpf(s.girth, s.girth * s.taper, from), lerpf(s.girth, s.girth * s.taper, to), 7,
				_still(s.bark.darkened(0.25 * (1.0 - from))), _still(s.bark), rng, 0.08)
	builder.xf = Transform3D.IDENTITY
