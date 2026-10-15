class_name WaterfallMist
extends GPUParticles3D
## The cloud of spray at the foot of a waterfall: soft pale particles rising from where the water
## falls. One per steep drop in a river.

func _init() -> void:
	amount = 36
	lifetime = 2.4
	visibility_aabb = AABB(Vector3(-8, -3, -8), Vector3(16, 12, 16))
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var process := ParticleProcessMaterial.new()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	process.emission_sphere_radius = 1.8
	process.gravity = Vector3(0.0, 0.5, 0.0)
	process.initial_velocity_min = 0.3
	process.initial_velocity_max = 1.0
	process.scale_min = 1.2
	process.scale_max = 2.6
	var ramp := Gradient.new()
	ramp.colors = PackedColorArray([Color(1, 1, 1, 0.0), Color(1, 1, 1, 0.28), Color(1, 1, 1, 0.0)])
	ramp.offsets = PackedFloat32Array([0.0, 0.3, 1.0])
	var ramp_texture := GradientTexture1D.new()
	ramp_texture.gradient = ramp
	process.color_ramp = ramp_texture
	process_material = process
	var mesh := SphereMesh.new()
	mesh.radius = 0.5
	mesh.height = 1.0
	mesh.radial_segments = 6
	mesh.rings = 3
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.vertex_color_use_as_albedo = true
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mesh.material = material
	draw_pass_1 = mesh
