class_name WaterSplash
extends Node3D
## Splashes and ripples where the player meets the water: a burst of droplets and a ring that
## spreads and fades when you step or jump in, rings while you wade, and a wake while you swim.
## Each effect is made on the spot and frees itself.

const RING_LIFE := 1.3

var _ring_material: StandardMaterial3D
var _drop_mesh := SphereMesh.new()
var _drop_material := StandardMaterial3D.new()
var _ring_mesh := TorusMesh.new()


func _ready() -> void:
	_ring_material = StandardMaterial3D.new()
	_ring_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_ring_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_ring_material.albedo_color = Color(1, 1, 1, 0.55)
	_ring_mesh.inner_radius = 0.46
	_ring_mesh.outer_radius = 0.5
	_ring_mesh.rings = 20
	_ring_mesh.ring_segments = 4
	_ring_mesh.material = _ring_material
	_drop_mesh.radius = 0.04
	_drop_mesh.height = 0.08
	_drop_mesh.radial_segments = 5
	_drop_mesh.rings = 3
	_drop_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_drop_material.albedo_color = Color(0.9, 0.96, 1.0, 0.8)
	_drop_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_drop_mesh.material = _drop_material


## A burst of droplets and a ring at `at` (a point on the water surface); `strength` 0.3 .. 1.5.
func splash(at: Vector3, strength: float) -> void:
	var drops := GPUParticles3D.new()
	drops.amount = int(18.0 * strength) + 6
	drops.lifetime = 0.9
	drops.one_shot = true
	drops.explosiveness = 1.0
	drops.visibility_aabb = AABB(Vector3(-4, -1, -4), Vector3(8, 6, 8))
	var process := ParticleProcessMaterial.new()
	process.direction = Vector3.UP
	process.spread = 38.0
	process.initial_velocity_min = 1.6 * strength
	process.initial_velocity_max = 3.4 * strength
	process.gravity = Vector3(0.0, -9.0, 0.0)
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	process.emission_sphere_radius = 0.2
	drops.process_material = process
	drops.draw_pass_1 = _drop_mesh
	drops.position = at
	add_child(drops)
	drops.emitting = true
	get_tree().create_timer(2.0).timeout.connect(drops.queue_free)
	ripple(at, 1.0 + strength)


## One ring that spreads from `at` and fades out.
func ripple(at: Vector3, reach: float) -> void:
	var ring := MeshInstance3D.new()
	ring.mesh = _ring_mesh
	ring.position = at + Vector3(0.0, 0.03, 0.0)
	ring.scale = Vector3(0.3, 0.3, 0.3)
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var material := _ring_material.duplicate() as StandardMaterial3D
	ring.material_override = material
	add_child(ring)
	var tween := create_tween().set_parallel(true)
	tween.tween_property(ring, "scale", Vector3(reach, reach, reach) * 1.6, RING_LIFE)
	tween.tween_property(material, "albedo_color:a", 0.0, RING_LIFE)
	tween.chain().tween_callback(ring.queue_free)
