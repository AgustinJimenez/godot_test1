class_name DGGameSampleLocomotionBody
extends CharacterBody3D
## DG_GAME_SAMPLE-style third-person locomotion, rebuilt from the recovered
## UBendCharacterMovementComponent API (see the RE workspace's notes/
## locomotion-map.md). Self-contained: it builds its own capsule, mesh and
## state machine, and takes an already camera-relative world direction.
##
## The recovered pieces this mirrors:
##   - OnGroundIdle_* / OnGroundMove_* states, plus turn-in-place and air.
##   - GetMoveSpeedForAnimationSelectionAndScaling -> get_speed_ratio().
##   - BendCharacterMovementTurnRateScaleVsStrafeAngleCurve -> tuning curve.
##   - SetCollisionShape / RevertToDefaultCollisionShape -> crouch capsule swap.

const STATE_MACHINE_SCRIPT := preload(
	"res://tests/manual/dg_game_sample_locomotion/dg_game_sample_locomotion_state_machine.gd"
)

@export var tuning: DGGameSampleLocomotionTuning

var state_machine: DGGameSampleLocomotionStateMachine

# --- Input snapshot ---------------------------------------------------------
## Horizontal unit direction of the movement request, world space.
var move_direction := Vector3.ZERO
var move_magnitude := 0.0
var wants_sprint := false
var wants_crouch := false

# --- Observable state -------------------------------------------------------
## Capsule yaw in radians; forward is -Z as everywhere in Godot.
var facing_yaw := 0.0
## 0..1 speed ratio suitable for an animation blend parameter.
var speed_ratio := 0.0

var _capsule: CapsuleShape3D
var _collision: CollisionShape3D
var _visual: Node3D
var _current_height := 1.8
var _placeholder_meshes: Array[MeshInstance3D] = []
var _pending_jump := false
var _was_on_floor := true


func _ready() -> void:
	if tuning == null:
		tuning = DGGameSampleLocomotionTuning.new()
	_current_height = tuning.stand_height
	_build_collision()
	_build_visual()
	_build_state_machine()


# ------------------------------------------------------------------ public --

## Feed the movement request. `world_direction` must be horizontal (may be zero).
func set_move_input(world_direction: Vector3, magnitude: float) -> void:
	var flat := Vector3(world_direction.x, 0.0, world_direction.z)
	if flat.length() > 0.001:
		move_direction = flat.normalized()
	move_magnitude = clampf(magnitude, 0.0, 1.0)
	if move_magnitude <= tuning.input_deadzone:
		move_direction = Vector3.ZERO


func set_sprint(enabled: bool) -> void:
	wants_sprint = enabled


func set_crouch(enabled: bool) -> void:
	wants_crouch = enabled


func request_jump() -> void:
	_pending_jump = true


## Animation hook: 0 at rest, 1 at sprint speed (GetMoveSpeedForAnimation...).
func get_speed_ratio() -> float:
	return speed_ratio


func get_planar_speed() -> float:
	return Vector2(velocity.x, velocity.z).length()


func get_state_name() -> StringName:
	return state_machine.state_name()


## Hide the capsule stand-in once a real character mesh is attached.
func set_placeholder_visible(visible_now: bool) -> void:
	for mesh in _placeholder_meshes:
		mesh.visible = visible_now


func get_capsule_height() -> float:
	return _capsule.height


# ------------------------------------------------------------- build steps --

func _build_collision() -> void:
	_capsule = CapsuleShape3D.new()
	_capsule.radius = tuning.capsule_radius
	_capsule.height = tuning.stand_height
	_collision = CollisionShape3D.new()
	_collision.name = "Collision"
	_collision.shape = _capsule
	_collision.position = Vector3(0.0, tuning.stand_height * 0.5, 0.0)
	add_child(_collision)
	collision_layer = 2
	collision_mask = 1


func _build_visual() -> void:
	_visual = Node3D.new()
	_visual.name = "Visual"
	add_child(_visual)

	var body_mesh := CapsuleMesh.new()
	body_mesh.radius = tuning.capsule_radius
	body_mesh.height = tuning.stand_height
	var body_instance := MeshInstance3D.new()
	body_instance.name = "Body"
	body_instance.mesh = body_mesh
	body_instance.position = Vector3(0.0, tuning.stand_height * 0.5, 0.0)
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.36, 0.52, 0.78)
	body_instance.material_override = material
	_visual.add_child(body_instance)
	_placeholder_meshes.append(body_instance)

	# A wedge on -Z so turn-in-place and facing are readable without a model.
	var nose_mesh := BoxMesh.new()
	nose_mesh.size = Vector3(0.22, 0.16, 0.34)
	var nose := MeshInstance3D.new()
	nose.name = "Facing"
	nose.mesh = nose_mesh
	nose.position = Vector3(0.0, tuning.stand_height * 0.78, -tuning.capsule_radius - 0.12)
	var nose_material := StandardMaterial3D.new()
	nose_material.albedo_color = Color(0.95, 0.75, 0.25)
	nose.material_override = nose_material
	_visual.add_child(nose)
	_placeholder_meshes.append(nose)


func _build_state_machine() -> void:
	state_machine = STATE_MACHINE_SCRIPT.new()
	state_machine.name = "LocomotionStateMachine"
	state_machine.tuning = tuning
	add_child(state_machine)


# ------------------------------------------------------------------- frame --

func _physics_process(delta: float) -> void:
	_tick_posture(delta)
	_tick_state(delta)
	_tick_facing(delta)
	_tick_velocity(delta)
	_tick_air(delta)

	move_and_slide()
	_update_speed_ratio(delta)
	_was_on_floor = is_on_floor()


func _tick_state(delta: float) -> void:
	state_machine.on_floor = is_on_floor()
	state_machine.input_magnitude = move_magnitude
	state_machine.planar_speed = get_planar_speed()
	state_machine.angle_to_input_deg = rad_to_deg(_signed_angle_to_input())
	state_machine.tick(delta)


func _tick_facing(delta: float) -> void:
	match state_machine.state:
		DGGameSampleLocomotionStateMachine.State.TURN:
			facing_yaw = wrapf(facing_yaw + state_machine.yaw_delta(delta), -PI, PI)
		DGGameSampleLocomotionStateMachine.State.MOVE:
			_rotate_toward_input(delta)
		_:
			pass
	rotation.y = facing_yaw


func _tick_velocity(delta: float) -> void:
	var planar := Vector3(velocity.x, 0.0, velocity.z)
	var in_turn := state_machine.state == DGGameSampleLocomotionStateMachine.State.TURN
	var in_air := not is_on_floor()
	var target := Vector3.ZERO
	if not in_turn and move_magnitude > tuning.input_deadzone and not in_air:
		target = move_direction * (_target_speed() * move_magnitude)
	var braking := target == Vector3.ZERO
	var time := tuning.decelerate_time if braking else tuning.accelerate_time
	if in_air:
		time = tuning.accelerate_time * (1.0 / maxf(0.01, tuning.air_control_scale))
	var accel := 0.0
	if target.length() > 0.01:
		accel = target.length() / maxf(0.01, time)
	else:
		accel = maxf(0.01, planar.length() / maxf(0.01, time))
	planar = planar.move_toward(target, accel * delta)
	velocity.x = planar.x
	velocity.z = planar.z


func _tick_air(delta: float) -> void:
	var gravity := float(ProjectSettings.get_setting("physics/3d/default_gravity"))
	if is_on_floor():
		if _pending_jump:
			velocity.y = tuning.jump_velocity
			_pending_jump = false
		return
	_pending_jump = false
	velocity.y -= gravity * tuning.gravity_scale * delta


func _tick_posture(delta: float) -> void:
	var wanted := tuning.crouch_height if wants_crouch else tuning.stand_height
	var step := absf(tuning.stand_height - tuning.crouch_height)
	var rate := step / maxf(0.01, tuning.crouch_transition_time)
	_current_height = move_toward(_current_height, wanted, rate * delta)
	_capsule.height = _current_height
	_collision.position.y = _current_height * 0.5
	_visual.scale.y = _current_height / tuning.stand_height


func _update_speed_ratio(delta: float) -> void:
	var goal := clampf(get_planar_speed() / maxf(0.01, tuning.sprint_speed), 0.0, 1.0)
	speed_ratio = move_toward(speed_ratio, goal, delta * 6.0)


# ----------------------------------------------------------------- helpers --

func _target_speed() -> float:
	if wants_crouch:
		return tuning.crouch_speed
	var forward_dot := _forward().dot(move_direction)
	var speed := tuning.jog_speed
	if wants_sprint and forward_dot > 0.55:
		speed = tuning.sprint_speed
	elif move_magnitude < 0.55:
		speed = tuning.walk_speed
	if forward_dot < -0.35:
		return speed * tuning.backward_speed_scale
	if absf(forward_dot) < 0.55:
		return speed * tuning.strafe_speed_scale
	return speed


func _rotate_toward_input(delta: float) -> void:
	var error := _signed_angle_to_input()
	if absf(error) < 0.001:
		return
	# Do not spin the capsule around for near-180 reversals while moving.
	if _forward().dot(move_direction) < -0.2:
		return
	var scale := tuning.turn_rate_scale_for_angle(rad_to_deg(absf(error)))
	var max_step := deg_to_rad(tuning.turn_rate_deg_per_s) * scale * delta
	facing_yaw = wrapf(facing_yaw + clampf(error, -max_step, max_step), -PI, PI)


func _signed_angle_to_input() -> float:
	if move_direction.length() < 0.001:
		return 0.0
	var target_yaw := atan2(-move_direction.x, -move_direction.z)
	return wrapf(target_yaw - facing_yaw, -PI, PI)


func _forward() -> Vector3:
	return Vector3(-sin(facing_yaw), 0.0, -cos(facing_yaw))
