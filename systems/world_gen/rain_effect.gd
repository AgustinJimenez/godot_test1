class_name RainEffect
extends GPUParticles3D
## Rain or snow falling around the camera: one box of particles that follows the follow target.
## `amount_ratio` is how hard it falls (0 stops it). Snow falls slow and drifts, rain falls fast
## and leans with the wind.

const BOX := Vector3(34.0, 14.0, 34.0)

var snowing := false:
	set(value):
		snowing = value
		_apply_kind()

var _process_material := ParticleProcessMaterial.new()
var _draw_material := StandardMaterial3D.new()
var _mesh := BoxMesh.new()


func _init() -> void:
	amount = 5200
	lifetime = 1.4
	visibility_aabb = AABB(-BOX, BOX * 2.0)
	local_coords = false
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_process_material.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	_process_material.emission_box_extents = Vector3(BOX.x, 1.0, BOX.z)
	process_material = _process_material
	_draw_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_draw_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mesh.material = _draw_material
	draw_pass_1 = _mesh
	emitting = true
	amount_ratio = 0.0
	_apply_kind()


func _apply_kind() -> void:
	if snowing:
		_mesh.size = Vector3(0.07, 0.07, 0.07)
		_draw_material.albedo_color = Color(1.0, 1.0, 1.0, 0.9)
		lifetime = 7.0
		_process_material.gravity = Vector3(0.0, -1.2, 0.0)
		_process_material.initial_velocity_min = 0.0
		_process_material.initial_velocity_max = 0.5
	else:
		_mesh.size = Vector3(0.012, 0.55, 0.012)
		_draw_material.albedo_color = Color(0.72, 0.8, 0.9, 0.55)
		lifetime = 1.0
		_process_material.gravity = Vector3(0.0, -34.0, 0.0)
		_process_material.initial_velocity_min = 0.0
		_process_material.initial_velocity_max = 0.0


## Follows the camera / player, a little above it, leaning into the wind.
func follow(target: Vector3, wind: Vector2, strength: float) -> void:
	global_position = target + Vector3(0.0, BOX.y * 0.5 + 4.0, 0.0)
	if not snowing:
		_process_material.gravity = Vector3(wind.x * strength * 9.0, -34.0, wind.y * strength * 9.0)
	else:
		_process_material.gravity = Vector3(wind.x * strength * 2.0, -1.2, wind.y * strength * 2.0)
