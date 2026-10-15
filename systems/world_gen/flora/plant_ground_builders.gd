class_name PlantGroundBuilders
extends RefCounted
## The small growth forms: shrubs, cacti, grasses, reeds, flowers, ferns, mushrooms. Each draws one
## mesh of a PlantSpecies from its numbers (see the field notes in plant_species.gd).


static func _still(color: Color) -> Color:
	return Color(color.r, color.g, color.b, 0.0)


static func _sway(color: Color, amount: float) -> Color:
	return Color(color.r, color.g, color.b, amount)


## Lumpy balls of leaf, with berries or blossom dotted over them when the species has them.
static func shrub(builder: MeshBuilder, s: PlantSpecies, rng: RandomNumberGenerator) -> void:
	var lumps: Array[Vector4] = [] # centre and radius, for the berries
	for index in s.count + rng.randi_range(0, 1):
		var size := s.crown * rng.randf_range(0.65, 1.0)
		var centre := Vector3(rng.randf_range(-0.4, 0.4) * s.crown * 1.5, size * 0.55 * s.height,
				rng.randf_range(-0.4, 0.4) * s.crown * 1.5)
		var tone := s.leaf.lerp(s.leaf.lightened(0.1), rng.randf())
		builder.add_blob(centre, Vector3(size, size * 0.8 * s.height, size),
				_sway(tone.darkened(0.3), 0.3), _sway(s.leaf_tip, 1.0), rng, s.wobble)
		lumps.append(Vector4(centre.x, centre.y, centre.z, size))
	for berry in s.extra:
		var lump: Vector4 = lumps[rng.randi() % lumps.size()]
		var dir := Vector3(rng.randf_range(-1.0, 1.0), rng.randf_range(0.0, 1.0),
				rng.randf_range(-1.0, 1.0)).normalized()
		var at := Vector3(lump.x, lump.y, lump.z) + dir * lump.w * Vector3(1.0, 0.8 * s.height, 1.0) * 1.0
		builder.add_blob(at, Vector3.ONE * 0.05, _sway(s.accent.darkened(0.2), 0.6),
				_sway(s.accent, 0.8), rng, 0.1)


## Columnar cactus with arms, or a squat ribbed barrel.
static func cactus(builder: MeshBuilder, s: PlantSpecies, rng: RandomNumberGenerator) -> void:
	var height := s.height * rng.randf_range(0.9, 1.1)
	if s.count == 1: # barrel: wide and low
		builder.add_frustum(Vector3.ZERO, height * 0.7, s.girth * 0.85, s.girth, 8,
				_still(s.leaf.darkened(0.2)), _still(s.leaf), rng, 0.03)
		builder.add_frustum(Vector3(0.0, height * 0.7, 0.0), height * 0.3, s.girth, s.girth * 0.25, 8,
				_still(s.leaf), _still(s.leaf_tip), rng, 0.03, MeshBuilder.CAP_TOP)
		builder.add_frustum(Vector3(0.0, height, 0.0), 0.06, 0.1, 0.0, 5, _still(s.accent),
				_still(s.accent))
		return
	builder.add_frustum(Vector3.ZERO, height, s.girth, s.girth * 0.8, 7, _still(s.leaf.darkened(0.2)),
			_still(s.leaf), rng, 0.04, MeshBuilder.CAP_TOP)
	for arm in s.extra:
		var side := -1.0 if arm % 2 == 0 else 1.0
		var at := height * rng.randf_range(0.3, 0.62)
		var reach := s.girth * rng.randf_range(2.0, 3.0)
		builder.xf = Transform3D(Basis(Vector3.BACK, side * PI * 0.5),
				Vector3(side * s.girth * 0.7, at, 0.0))
		builder.add_frustum(Vector3.ZERO, reach, s.girth * 0.6, s.girth * 0.6, 6,
				_still(s.leaf.darkened(0.1)), _still(s.leaf))
		builder.xf = Transform3D(Basis.IDENTITY, Vector3(side * (s.girth * 0.7 + reach), at, 0.0))
		builder.add_frustum(Vector3.ZERO, height * rng.randf_range(0.25, 0.4), s.girth * 0.6,
				s.girth * 0.45, 6, _still(s.leaf), _still(s.leaf_tip), null, 0.0,
				MeshBuilder.CAP_TOP)
		builder.xf = Transform3D.IDENTITY
	if rng.randf() < 0.5:
		builder.add_frustum(Vector3(0.0, height, 0.0), 0.08, 0.09, 0.0, 5, _still(s.accent),
				_still(s.accent))


## A tuft of blades, bending over toward the tip; finer, curved blades for the realistic look.
static func grass(builder: MeshBuilder, s: PlantSpecies, rng: RandomNumberGenerator) -> void:
	var blades := int(float(s.count) * (1.5 if builder.detailed else 1.0))
	var tall := s.height > 0.85
	for blade in blades:
		var angle := rng.randf() * TAU
		var height := s.height * rng.randf_range(0.65, 1.15)
		var bend := s.droop * height * rng.randf_range(0.5, 1.2)
		var spread := 0.12 if not tall else 0.2
		var root := Vector3(rng.randf_range(-spread, spread), 0.0, rng.randf_range(-spread, spread))
		var out := Vector3(sin(angle), 0.0, -cos(angle))
		var across := Vector3(cos(angle), 0.0, sin(angle))
		var shade := rng.randf_range(0.88, 1.12)
		var low := s.leaf * shade
		var high := s.leaf.lerp(s.leaf_tip, 0.4) * shade
		var upper := s.leaf_tip * shade
		if builder.detailed:
			var mid := root + out * bend * 0.3 + Vector3(0.0, height * 0.55, 0.0)
			var top := root + out * bend + Vector3(0.0, height * 0.95, 0.0)
			var w := s.girth * 1.1
			builder.add_tri(root - across * w, root + across * w, mid - across * w * 0.64, _sway(low, 0.0),
					_sway(low, 0.0), _sway(high, 0.5))
			builder.add_tri(root + across * w, mid + across * w * 0.64, mid - across * w * 0.64,
					_sway(low, 0.0), _sway(high, 0.5), _sway(high, 0.5))
			builder.add_tri(mid - across * w * 0.64, mid + across * w * 0.64, top, _sway(high, 0.5),
					_sway(high, 0.5), _sway(upper, 1.0))
		else:
			var top := root + out * bend + Vector3(0.0, height, 0.0)
			builder.add_tri(root - across * s.girth, root + across * s.girth, top, _sway(low, 0.0),
					_sway(low, 0.0), _sway(upper, 1.0))
		if tall and s.extra > 0 and rng.randf() < 0.45: # seed head
			var head := root + out * bend + Vector3(0.0, height, 0.0)
			builder.add_frustum(head - Vector3(0.0, 0.1, 0.0), 0.16, 0.02, 0.0, 3,
					_sway(s.accent, 0.9), _sway(s.accent.lightened(0.1), 1.0))


## Tall straight blades, with cattail heads on some species.
static func reed(builder: MeshBuilder, s: PlantSpecies, rng: RandomNumberGenerator) -> void:
	for blade in s.count:
		var angle := rng.randf() * TAU
		var height := s.height * rng.randf_range(0.7, 1.15)
		var root := Vector3(rng.randf_range(-0.2, 0.2), 0.0, rng.randf_range(-0.2, 0.2))
		var across := Vector3(cos(angle), 0.0, sin(angle)) * s.girth
		var top := root + Vector3(rng.randf_range(-1.0, 1.0), 0.0, rng.randf_range(-1.0, 1.0)) \
				* s.droop * height + Vector3(0.0, height, 0.0)
		builder.add_tri(root - across, root + across, top, _sway(s.leaf, 0.0), _sway(s.leaf, 0.0),
				_sway(s.leaf_tip, 1.0))
		if s.extra > 0 and blade % 3 == 0: # a cattail
			builder.add_frustum(top - Vector3(0.0, 0.42, 0.0), 0.3, 0.045, 0.04, 5, _sway(s.accent, 0.7),
					_sway(s.accent.darkened(0.2), 0.9), null, 0.0, MeshBuilder.CAP_TOP)


## A clump of stems, each with a ring of petals round a yellow heart.
static func flower(builder: MeshBuilder, s: PlantSpecies, rng: RandomNumberGenerator) -> void:
	for stem in s.extra:
		var root := Vector3.ZERO if s.extra == 1 else Vector3(rng.randf_range(-0.14, 0.14), 0.0,
				rng.randf_range(-0.14, 0.14))
		var height := s.height * rng.randf_range(0.75, 1.15)
		builder.add_frustum(root, height, 0.018, 0.012, 3, _sway(s.leaf, 0.0), _sway(s.leaf_tip, 0.7))
		# two small leaves at the foot
		for leaf in 2:
			var yaw := rng.randf() * TAU
			var out := Vector3(cos(yaw), 0.0, sin(yaw))
			var side := Vector3(-out.z, 0.0, out.x) * 0.03
			builder.add_tri(root + side, root - side, root + out * 0.16 + Vector3(0.0, 0.1, 0.0),
					_sway(s.leaf, 0.0), _sway(s.leaf, 0.0), _sway(s.leaf_tip, 0.8))
		var head := root + Vector3(0.0, height, 0.0)
		for petal in s.count:
			var angle := TAU * float(petal) / float(s.count)
			var out := Vector3(cos(angle), 0.0, sin(angle))
			var side := Vector3(-out.z, 0.0, out.x) * s.crown * 0.38
			builder.add_tri(head - side, head + side, head + out * s.crown + Vector3(0.0, 0.03, 0.0),
					_sway(s.accent.lightened(0.15), 0.8), _sway(s.accent.lightened(0.15), 0.8),
					_sway(s.accent, 1.0))
		builder.add_frustum(head, 0.03, 0.035, 0.0, 5, _sway(Color(0.9, 0.7, 0.1), 0.8),
				_sway(Color(0.9, 0.7, 0.1), 0.8))


## A rosette of arching fronds; the realistic look adds leaflets along each one.
static func fern(builder: MeshBuilder, s: PlantSpecies, rng: RandomNumberGenerator) -> void:
	for frond in s.count:
		var yaw := TAU * float(frond) / float(s.count) + rng.randf_range(-0.25, 0.25)
		var out := Vector3(cos(yaw), 0.0, sin(yaw))
		var along := Vector3(-out.z, 0.0, out.x)
		var length := s.crown * rng.randf_range(0.7, 1.1)
		var side := along * length * 0.15
		var mid := out * length * 0.5 + Vector3(0.0, s.height * 0.95, 0.0)
		var tip := out * length + Vector3(0.0, s.height * (0.5 - s.droop * 0.5), 0.0)
		builder.add_tri(Vector3.ZERO, mid + side, mid - side, _sway(s.leaf.darkened(0.3), 0.2),
				_sway(s.leaf, 0.7), _sway(s.leaf, 0.7))
		builder.add_tri(mid + side, tip, mid - side, _sway(s.leaf, 0.7), _sway(s.leaf_tip, 1.0),
				_sway(s.leaf, 0.7))
		if builder.detailed: # leaflets
			for leaflet in 3:
				var f := 0.3 + float(leaflet) * 0.22
				var at := Vector3.ZERO.lerp(mid, f * 2.0) if f < 0.5 else mid.lerp(tip, (f - 0.5) * 2.0)
				var wing := along * length * 0.2 * (1.0 - f * 0.6)
				builder.add_tri(at, at + wing + out * 0.05, at + wing * 0.4 + Vector3(0.0, -0.04, 0.0),
						_sway(s.leaf, 0.6), _sway(s.leaf_tip, 1.0), _sway(s.leaf, 0.7))
				builder.add_tri(at, at - wing * 0.4 + Vector3(0.0, -0.04, 0.0), at - wing + out * 0.05,
						_sway(s.leaf, 0.6), _sway(s.leaf, 0.7), _sway(s.leaf_tip, 1.0))


## A cluster of stalks under domed or flat caps.
static func mushroom(builder: MeshBuilder, s: PlantSpecies, rng: RandomNumberGenerator) -> void:
	for index in s.count:
		var at := Vector3(rng.randf_range(-0.2, 0.2), 0.0, rng.randf_range(-0.2, 0.2)) \
				if s.count > 1 else Vector3.ZERO
		var height := s.height * rng.randf_range(0.7, 1.2)
		builder.add_frustum(at, height, 0.035, 0.03, 5, _still(Color(0.9, 0.88, 0.8)),
				_still(Color(0.92, 0.9, 0.84)))
		builder.add_frustum(at + Vector3(0.0, height, 0.0), height * lerpf(0.3, 0.9, s.droop),
				height * s.crown, 0.02, 7, _still(s.accent.darkened(0.15)), _still(s.accent), rng, 0.05)
