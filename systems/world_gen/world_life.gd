class_name WorldLife
extends Node3D
## Things that move on their own: flocks of birds wheeling high up by day, butterflies over the
## meadows by day, fireflies drifting by night. Everything stays around the target, so it costs the
## same wherever you are.

const BIRD_COUNT := 28
const BUTTERFLY_COUNT := 36
const SHADER := preload("res://shaders/world/flutter.gdshader")

var noise: TerrainNoise
var daylight := 1.0 # 0 night .. 1 day, set by the world
var wetness := 0.0 # rain keeps the animals in

var _birds := MultiMesh.new()
var _butterflies := MultiMesh.new()
var _fireflies := GPUParticles3D.new()
var _bird_seed: Array[Vector4] = [] # flock x, flock z, radius, phase
var _butterfly_state: Array[Vector3] = [] # offset from the target
var _butterfly_heading: Array[float] = []
var _time := 0.0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.seed = 99
	_make_birds()
	_make_butterflies()
	_make_fireflies()


func update(target: Vector3, day: float, rain: float, delta: float) -> void:
	_time += delta
	daylight = day
	wetness = rain
	var show := day > 0.25 and rain < 0.5
	_birds.visible_instance_count = BIRD_COUNT if show else 0
	_butterflies.visible_instance_count = BUTTERFLY_COUNT if show and rain < 0.1 else 0
	_fireflies.emitting = day < 0.2 and rain < 0.3
	_fireflies.global_position = target + Vector3(0.0, 2.0, 0.0)
	if show:
		_move_birds(target)
		_move_butterflies(target, delta)


func _make_birds() -> void:
	var builder := MeshBuilder.new()
	var dark := Color(0.12, 0.12, 0.14)
	# a body and two wings, as a few flat triangles
	builder.add_tri(Vector3(0.0, 0.0, 0.5), Vector3(-0.12, 0.0, -0.3), Vector3(0.12, 0.0, -0.3), dark)
	builder.add_tri(Vector3(-0.1, 0.0, 0.1), Vector3(-1.1, 0.0, -0.25), Vector3(-0.1, 0.0, -0.3), dark)
	builder.add_tri(Vector3(0.1, 0.0, 0.1), Vector3(0.1, 0.0, -0.3), Vector3(1.1, 0.0, -0.25), dark)
	_birds.transform_format = MultiMesh.TRANSFORM_3D
	_birds.mesh = builder.commit()
	_birds.instance_count = BIRD_COUNT
	for index in BIRD_COUNT:
		_bird_seed.append(Vector4(_rng.randf_range(-250.0, 250.0), _rng.randf_range(-250.0, 250.0),
				_rng.randf_range(30.0, 90.0), _rng.randf() * TAU))
	add_child(_instance(_birds, 6.0, 0.6))


func _make_butterflies() -> void:
	var builder := MeshBuilder.new()
	var hues := [Color(0.98, 0.8, 0.2), Color(0.95, 0.5, 0.15), Color(0.9, 0.95, 1.0),
			Color(0.55, 0.65, 1.0)]
	var color: Color = hues[_rng.randi() % hues.size()]
	builder.add_tri(Vector3.ZERO, Vector3(-0.1, 0.0, 0.06), Vector3(-0.02, 0.0, -0.08), color)
	builder.add_tri(Vector3.ZERO, Vector3(0.02, 0.0, -0.08), Vector3(0.1, 0.0, 0.06), color)
	_butterflies.transform_format = MultiMesh.TRANSFORM_3D
	_butterflies.use_colors = true
	_butterflies.mesh = builder.commit()
	_butterflies.instance_count = BUTTERFLY_COUNT
	for index in BUTTERFLY_COUNT:
		_butterfly_state.append(Vector3(_rng.randf_range(-22.0, 22.0), _rng.randf_range(0.6, 2.2),
				_rng.randf_range(-22.0, 22.0)))
		_butterfly_heading.append(_rng.randf() * TAU)
		_butterflies.set_instance_color(index, hues[index % hues.size()])
	add_child(_instance(_butterflies, 16.0, 0.9))


func _instance(multi: MultiMesh, speed: float, size: float) -> MultiMeshInstance3D:
	var material := ShaderMaterial.new()
	material.shader = SHADER
	material.set_shader_parameter(&"flap_speed", speed)
	material.set_shader_parameter(&"flap_size", size)
	var instance := MultiMeshInstance3D.new()
	instance.multimesh = multi
	instance.material_override = material
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	instance.extra_cull_margin = 400.0
	return instance


func _make_fireflies() -> void:
	_fireflies.amount = 90
	_fireflies.lifetime = 7.0
	_fireflies.visibility_aabb = AABB(Vector3(-30, -10, -30), Vector3(60, 20, 60))
	_fireflies.local_coords = false
	var process := ParticleProcessMaterial.new()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	process.emission_box_extents = Vector3(26.0, 3.0, 26.0)
	process.gravity = Vector3.ZERO
	process.initial_velocity_min = 0.1
	process.initial_velocity_max = 0.5
	process.direction = Vector3.UP
	process.spread = 180.0
	process.turbulence_enabled = true
	process.turbulence_noise_strength = 0.6
	process.turbulence_noise_scale = 2.0
	process.scale_min = 0.6
	process.scale_max = 1.2
	_fireflies.process_material = process
	var mesh := SphereMesh.new()
	mesh.radius = 0.05
	mesh.height = 0.1
	mesh.radial_segments = 6
	mesh.rings = 3
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color(0.85, 1.0, 0.4)
	material.emission_enabled = true
	material.emission = Color(0.8, 1.0, 0.3)
	material.emission_energy_multiplier = 3.0
	mesh.material = material
	_fireflies.draw_pass_1 = mesh
	_fireflies.emitting = false
	add_child(_fireflies)


func _move_birds(target: Vector3) -> void:
	for index in BIRD_COUNT:
		var seed := _bird_seed[index]
		var flock := Vector3(seed.x, 0.0, seed.y)
		var angle := _time * (0.12 + 0.04 * float(index % 3)) + seed.w
		var at := target + flock * 0.4 + Vector3(cos(angle), 0.0, sin(angle)) * seed.z
		at.y = target.y + 40.0 + float(index % 5) * 9.0 + sin(angle * 2.0) * 4.0
		var heading := Vector3(-sin(angle), 0.0, cos(angle))
		var basis := Basis.looking_at(heading, Vector3.UP).rotated(heading, sin(angle * 3.0) * 0.25)
		_birds.set_instance_transform(index, Transform3D(basis, at))


func _move_butterflies(target: Vector3, delta: float) -> void:
	for index in BUTTERFLY_COUNT:
		var heading := _butterfly_heading[index] + sin(_time * 1.3 + float(index)) * 2.0 * delta
		_butterfly_heading[index] = heading
		var offset := _butterfly_state[index]
		offset += Vector3(cos(heading), sin(_time * 2.0 + float(index)) * 0.3, sin(heading)) * 1.1 * delta
		offset.x = clampf(offset.x, -24.0, 24.0)
		offset.z = clampf(offset.z, -24.0, 24.0)
		_butterfly_state[index] = offset
		var at := target + Vector3(offset.x, 0.0, offset.z)
		var ground := noise.height(at.x, at.z) if noise != null else target.y
		at.y = maxf(ground, 0.0) + clampf(offset.y, 0.5, 2.5)
		_butterflies.set_instance_transform(index, Transform3D(
				Basis(Vector3.UP, -heading), at))
