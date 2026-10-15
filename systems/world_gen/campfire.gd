class_name Campfire
extends Node3D
## A small fire: flames (particles), a warm light that flickers, and a stone ring. The light fades
## out in daylight (nobody needs it) and in heavy rain.

var _light := OmniLight3D.new()
var _flames := GPUParticles3D.new()
var _time := randf() * 10.0
var daylight := 1.0 # set by the world
var rain := 0.0


func _ready() -> void:
	_light.light_color = Color(1.0, 0.6, 0.25)
	_light.omni_range = 16.0
	_light.shadow_enabled = false
	_light.position = Vector3(0.0, 0.9, 0.0)
	add_child(_light)
	_flames.amount = 28
	_flames.lifetime = 0.9
	_flames.visibility_aabb = AABB(Vector3(-2, -1, -2), Vector3(4, 5, 4))
	var process := ParticleProcessMaterial.new()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	process.emission_sphere_radius = 0.22
	process.gravity = Vector3(0.0, 2.6, 0.0)
	process.initial_velocity_min = 0.2
	process.initial_velocity_max = 0.6
	process.scale_min = 0.6
	process.scale_max = 1.3
	var ramp := Gradient.new()
	ramp.colors = PackedColorArray([Color(1.0, 0.85, 0.3, 1.0), Color(1.0, 0.35, 0.05, 0.8),
			Color(0.3, 0.05, 0.0, 0.0)])
	ramp.offsets = PackedFloat32Array([0.0, 0.5, 1.0])
	var ramp_texture := GradientTexture1D.new()
	ramp_texture.gradient = ramp
	process.color_ramp = ramp_texture
	_flames.process_material = process
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.16, 0.2, 0.16)
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.vertex_color_use_as_albedo = true
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mesh.material = material
	_flames.draw_pass_1 = mesh
	_flames.position = Vector3(0.0, 0.35, 0.0)
	add_child(_flames)


func _process(delta: float) -> void:
	_time += delta
	var strength := (1.0 - daylight * 0.9) * (1.0 - rain * 0.5)
	_light.light_energy = (1.6 + sin(_time * 13.0) * 0.25 + sin(_time * 5.3) * 0.2) * (0.25 + strength)
	_flames.emitting = true
