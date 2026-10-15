class_name WorldWater
extends MeshInstance3D
## The sea and the lakes: a faceted plane at sea level that slides along with the player (in whole
## facets, so the waves do not swim), plus a huge coarse plane just under it out to the horizon.
## Everything below the surface is under water.

const SHADER := preload("res://shaders/world/water_lowpoly.gdshader")
const SIZE := 900.0 ## m across, fine facets
const FACET := 5.0 ## m, one fine water triangle pair
const FAR_SIZE := 6000.0 ## m across, coarse facets to the horizon
const FAR_FACET := 40.0
const FAR_SINK := 0.4 ## m the far plane lies under the near one

var level := 0.0

var _far: MeshInstance3D


func _init() -> void:
	var material := ShaderMaterial.new()
	material.shader = SHADER
	mesh = _plane(SIZE, FACET)
	material_override = material
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	extra_cull_margin = 4.0
	_far = MeshInstance3D.new()
	_far.mesh = _plane(FAR_SIZE, FAR_FACET)
	_far.material_override = material
	_far.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_far.extra_cull_margin = 4.0
	_far.top_level = true
	add_child(_far)


func follow(target: Vector3) -> void:
	position = Vector3(snappedf(target.x, FACET), level, snappedf(target.z, FACET))
	_far.global_position = Vector3(snappedf(target.x, FAR_FACET), level - FAR_SINK,
			snappedf(target.z, FAR_FACET))


func _plane(size: float, facet: float) -> PlaneMesh:
	var plane := PlaneMesh.new()
	plane.size = Vector2(size, size)
	plane.subdivide_width = int(size / facet)
	plane.subdivide_depth = int(size / facet)
	return plane


static var _lake_material: ShaderMaterial


## A flat round lake surface of `radius` metres at the node's own height (rings of facets, so the
## water shader can roll waves across it).
static func lake_surface(radius: float) -> MeshInstance3D:
	if _lake_material == null:
		_lake_material = ShaderMaterial.new()
		_lake_material.shader = SHADER
	var builder := MeshBuilder.new()
	var rings := 7
	var segments := 28
	var white := Color.WHITE
	for ring in rings:
		var inner := radius * float(ring) / float(rings)
		var outer := radius * float(ring + 1) / float(rings)
		for index in segments:
			var a0 := TAU * float(index) / float(segments)
			var a1 := TAU * float(index + 1) / float(segments)
			var p00 := Vector3(cos(a0) * inner, 0.0, sin(a0) * inner)
			var p01 := Vector3(cos(a1) * inner, 0.0, sin(a1) * inner)
			var p10 := Vector3(cos(a0) * outer, 0.0, sin(a0) * outer)
			var p11 := Vector3(cos(a1) * outer, 0.0, sin(a1) * outer)
			builder.add_tri(p00, p01, p10, white)
			builder.add_tri(p10, p01, p11, white)
	var instance := MeshInstance3D.new()
	instance.mesh = builder.commit()
	instance.material_override = _lake_material
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return instance


static var _river_material: ShaderMaterial


## The water of every river segment in a tile: flat strips following the current, at each
## segment's own surface height. `origin` is the tile's world corner; the mesh is in tile space.
static func river_surface(segments: Array, origin: Vector2) -> MeshInstance3D:
	if segments.is_empty():
		return null
	if _river_material == null:
		_river_material = ShaderMaterial.new()
		_river_material.shader = preload("res://shaders/world/river_lowpoly.gdshader")
	var builder := MeshBuilder.new()
	for segment: Array in segments:
		var a: Vector2 = segment[0]
		var b: Vector2 = segment[1]
		var along := (b - a).normalized()
		var side := Vector2(-along.y, along.x)
		# the third channel is how steeply the water falls here (rapids, cascades)
		var fall := clampf((float(segment[2]) - float(segment[3])) / maxf(a.distance_to(b), 1.0) * 3.0,
				0.0, 1.0)
		var tint := Color(along.x * 0.5 + 0.5, along.y * 0.5 + 0.5, fall, 1.0)
		var wa := float(segment[4]) * 1.05
		var wb := float(segment[5]) * 1.05
		var a0 := a - along * 2.0 # a little overlap hides the cracks at the bends
		var b0 := b + along * 2.0
		var la := Vector3(a0.x - origin.x - side.x * wa, float(segment[2]), a0.y - origin.y - side.y * wa)
		var ra := Vector3(a0.x - origin.x + side.x * wa, float(segment[2]), a0.y - origin.y + side.y * wa)
		var lb := Vector3(b0.x - origin.x - side.x * wb, float(segment[3]), b0.y - origin.y - side.y * wb)
		var rb := Vector3(b0.x - origin.x + side.x * wb, float(segment[3]), b0.y - origin.y + side.y * wb)
		builder.add_tri(la, ra, lb, tint)
		builder.add_tri(lb, ra, rb, tint)
	var instance := MeshInstance3D.new()
	instance.mesh = builder.commit()
	instance.material_override = _river_material
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return instance
