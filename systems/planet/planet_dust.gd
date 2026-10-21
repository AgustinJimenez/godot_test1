class_name PlanetDust
extends Node3D
## Puffs of dust where something lands or steps on dry ground (task 081, 2): a few soft round
## flakes that rise a little, grow and fade in a second or so, in the colour of the ground. Each
## burst is made on the spot and frees itself. Only on sand and dry ground; the caller decides.

const LIFE := 1.4 ## s

var _mesh: QuadMesh
var _fade: GradientTexture1D
var _growth: CurveTexture


func _ready() -> void:
	var round_flake := GradientTexture2D.new()
	round_flake.fill = GradientTexture2D.FILL_RADIAL
	round_flake.fill_from = Vector2(0.5, 0.5)
	round_flake.fill_to = Vector2(0.5, 0.0)
	round_flake.width = 64
	round_flake.height = 64
	var edge := Gradient.new()
	edge.set_color(0, Color(1, 1, 1, 1))
	edge.set_color(1, Color(1, 1, 1, 0))
	round_flake.gradient = edge
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_PER_VERTEX
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	material.vertex_color_use_as_albedo = true
	material.albedo_texture = round_flake
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_mesh = QuadMesh.new()
	_mesh.size = Vector2(0.5, 0.5)
	_mesh.material = material
	var ramp := Gradient.new()
	ramp.set_color(0, Color(1, 1, 1, 0.0))
	ramp.add_point(0.12, Color(1, 1, 1, 0.7))
	ramp.set_color(ramp.get_point_count() - 1, Color(1, 1, 1, 0.0))
	_fade = GradientTexture1D.new()
	_fade.gradient = ramp
	var curve := Curve.new()
	curve.add_point(Vector2(0.0, 0.35))
	curve.add_point(Vector2(1.0, 1.0))
	_growth = CurveTexture.new()
	_growth.curve = curve


## A puff at world position `at` (on the ground, `up` the way up), `colour` the ground's, `strength`
## 0.3 .. 1.5 (a step is 0.5, a hard landing 1.5).
func puff(at: Vector3, up: Vector3, colour: Color, strength: float) -> void:
	var flakes := GPUParticles3D.new()
	flakes.amount = int(5.0 * strength) + 3
	flakes.lifetime = LIFE
	flakes.one_shot = true
	flakes.explosiveness = 0.9
	flakes.visibility_aabb = AABB(Vector3(-3, -1, -3), Vector3(6, 4, 6))
	flakes.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var process := ParticleProcessMaterial.new()
	process.direction = up
	process.spread = 55.0
	process.initial_velocity_min = 0.25 * strength
	process.initial_velocity_max = 0.7 * strength
	process.gravity = Vector3.ZERO
	process.damping_min = 0.6
	process.damping_max = 1.2
	process.scale_min = 0.5
	process.scale_max = 1.1
	process.scale_curve = _growth
	process.color = colour.lightened(0.4)
	process.color_ramp = _fade
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	process.emission_sphere_radius = 0.12
	flakes.process_material = process
	flakes.draw_pass_1 = _mesh
	flakes.position = at + up * 0.04
	add_child(flakes)
	flakes.emitting = true
	get_tree().create_timer(LIFE + 0.8).timeout.connect(flakes.queue_free)
