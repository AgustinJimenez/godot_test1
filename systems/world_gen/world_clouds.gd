class_name WorldClouds
extends Node3D
## Low-poly clouds drifting over the world with the wind. They ride along with the player (wrapping
## around a big square), so there are always clouds overhead. `cover` (0..1) decides how many are
## shown, `darkness` (0..1) turns them from white to storm grey.

const COUNT := 70
const AREA := 1400.0 ## m across, centred on the follow target
const MIN_HEIGHT := 150.0
const MAX_HEIGHT := 230.0

var cover := 0.4:
	set(value):
		cover = clampf(value, 0.0, 1.0)
		_multi.visible_instance_count = int(round(float(COUNT) * cover))
var darkness := 0.0:
	set(value):
		darkness = clampf(value, 0.0, 1.0)
		_material.albedo_color = Color(1.0, 1.0, 1.0).lerp(Color(0.32, 0.34, 0.38), darkness)
var wind := Vector2(1.0, 0.3)
var speed := 4.0 ## m/s at full strength

var _multi := MultiMesh.new()
var _material := StandardMaterial3D.new()
var _offsets: Array[Vector3] = [] # x, z along the area and the height
var _scales: Array[float] = []
var _drift := Vector2.ZERO


func _init() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 424242
	var builder := MeshBuilder.new()
	for puff in 7:
		var at := Vector3(rng.randf_range(-22.0, 22.0), rng.randf_range(-2.0, 4.0),
				rng.randf_range(-12.0, 12.0))
		var size := rng.randf_range(11.0, 20.0)
		builder.add_blob(at, Vector3(size, size * 0.5, size * 0.8), Color(0.78, 0.8, 0.86),
				Color(1.0, 1.0, 1.0), rng, 0.18)
	_material.vertex_color_use_as_albedo = true
	_material.vertex_color_is_srgb = true
	_material.roughness = 1.0
	_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_multi.transform_format = MultiMesh.TRANSFORM_3D
	_multi.mesh = builder.commit()
	_multi.instance_count = COUNT
	for index in COUNT:
		_offsets.append(Vector3(rng.randf() * AREA, rng.randf_range(MIN_HEIGHT, MAX_HEIGHT),
				rng.randf() * AREA))
		_scales.append(rng.randf_range(0.8, 1.8))
	var instance := MultiMeshInstance3D.new()
	instance.multimesh = _multi
	instance.material_override = _material
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	instance.extra_cull_margin = 2000.0
	add_child(instance)
	cover = cover
	darkness = darkness


func follow(target: Vector3, strength: float, delta: float) -> void:
	_drift += wind.normalized() * (0.6 + strength) * speed * delta
	for index in COUNT:
		var at := _offsets[index]
		var x := fposmod(at.x + _drift.x - target.x + AREA * 0.5, AREA) - AREA * 0.5
		var z := fposmod(at.z + _drift.y - target.z + AREA * 0.5, AREA) - AREA * 0.5
		var basis := Basis(Vector3.UP, float(index) * 1.7).scaled(Vector3.ONE * _scales[index])
		_multi.set_instance_transform(index, Transform3D(basis, Vector3(x + target.x, at.y,
				z + target.z)))
