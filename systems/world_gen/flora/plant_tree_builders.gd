class_name PlantTreeBuilders
extends RefCounted
## Shared tree mesh helpers: the tube TreeGrower grows its trunks and branches from, and the
## far (horizon) tree. Vertex colour alpha = how much a vertex sways in the wind, like every plant.


static func _still(color: Color) -> Color:
	return Color(color.r, color.g, color.b, 0.0)


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
	# the crown: a few lumps of leaves of their own tone, so the outline is a cloud, not one ball
	var size := s.crown * 1.3
	var middle := Vector3(0.0, trunk + (s.height - trunk) * 0.55, 0.0)
	for lump in 4:
		var offset := Vector3(rng.randf_range(-1.0, 1.0), rng.randf_range(-0.55, 0.65),
				rng.randf_range(-1.0, 1.0))
		var radius := size * rng.randf_range(0.5, 0.72)
		var tone := rng.randf_range(0.0, 0.18)
		builder.add_blob(middle + offset * size * Vector3(0.55, 0.45 * s.aspect, 0.55),
				Vector3(radius, radius * s.aspect * 0.8, radius),
				_still(s.leaf.darkened(0.3 - tone)), _still(s.leaf_tip.darkened(tone * 0.5)), rng, 0.3)


## One continuous tube through ring centres. Neighbouring pieces share their ring, so a leaning or
## bending trunk has no steps, gaps or colour bands (stacked separate cones had all three). The
## rings stand at right angles to the path (carried along it without twisting), so a branch that
## runs sideways is as round as an upright trunk. `caps` closes the tube at its end(s)
## (MeshBuilder.CAP_*).
static func tube(builder: MeshBuilder, centres: Array[Vector3], radii: Array[float],
		colors: Array[Color], sides: int, rng: RandomNumberGenerator, wobble: float,
		caps := 0, refine := true, flutes := 0, flute_depths := PackedFloat32Array()) -> void:
	# the realistic look doubles the sides, unless the caller chose them (`refine` false) or the tube
	# is already round at 12
	if refine and builder.detailed and sides >= 5 and sides < 12:
		sides *= 2
	var count := centres.size()
	var rings: Array[PackedVector3Array] = []
	var side := Vector3.ZERO
	var last_tangent := Vector3.ZERO
	for ring in count:
		var tangent := (centres[mini(ring + 1, count - 1)] - centres[maxi(ring - 1, 0)]).normalized()
		if ring == 0:
			# any direction at right angles to the path will do to start with
			var reference := Vector3.RIGHT if absf(tangent.x) < 0.8 else Vector3.FORWARD
			side = (reference - tangent * tangent.dot(reference)).normalized()
		else:
			# turn the frame by the same turn the path made, so it does not twist
			var turn := last_tangent.cross(tangent)
			if turn.length_squared() > 0.000001:
				side = side.rotated(turn.normalized(), last_tangent.angle_to(tangent))
			side = (side - tangent * tangent.dot(side)).normalized()
		last_tangent = tangent
		var across := side.cross(tangent) # side x across = -tangent: the winding of a cone
		var points := PackedVector3Array()
		for index in sides:
			var angle := TAU * float(index) / float(sides)
			var jitter := 1.0 + rng.randf_range(-wobble, wobble)
			if flutes > 0: # ridges and grooves running up the trunk, turning slowly
				var depth := flute_depths[mini(ring, flute_depths.size() - 1)]
				jitter *= 1.0 + depth * cos(float(flutes) * angle + float(ring) * 0.12)
			points.append(centres[ring] + (side * cos(angle) + across * sin(angle)) * radii[ring]
					* jitter)
		rings.append(points)
	for ring in count - 1:
		for index in sides:
			var next := (index + 1) % sides
			var low: Color = colors[ring]
			var high: Color = colors[ring + 1]
			builder.add_tri(rings[ring][index], rings[ring + 1][index], rings[ring][next], low, high, low)
			builder.add_tri(rings[ring][next], rings[ring + 1][index], rings[ring + 1][next], low, high,
					high)
	for index in sides:
		var next := (index + 1) % sides
		if caps & MeshBuilder.CAP_TOP:
			builder.add_tri(centres[count - 1], rings[count - 1][next], rings[count - 1][index],
					colors[count - 1])
		if caps & MeshBuilder.CAP_BOTTOM:
			builder.add_tri(centres[0], rings[0][index], rings[0][next], colors[0])
