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

## How long after losing floor contact the downward sweep may still glue the body back down.
## Refreshed on every grounded frame. Without the window the sweep would also cut a real fall
## short by up to `floor_snap_length` - the capsule would pop down the last 0.4 m of every drop.
const STICK_GRACE := 0.15

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
## True on the frame a downward sweep glued the capsule back to the floor, which Godot's own
## single-frame snap misses (see `_stick_to_floor`).
var _stuck_to_floor := false
## Seconds left in the window where the floor sweep may still glue the body down (see
## `STICK_GRACE`).
var _stick_time_left := 0.0


func _ready() -> void:
	if tuning == null:
		tuning = DGGameSampleLocomotionTuning.new()
	_current_height = tuning.stand_height
	_build_collision()
	_apply_floor_settings()
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


## True when the body stands on something. Differs from `is_on_floor()` on the frame the floor
## sweep glues the capsule back down, which Godot reports as airborne.
func is_grounded() -> bool:
	return is_on_floor() or _stuck_to_floor


## Hide the capsule stand-in once a real character mesh is attached.
func set_placeholder_visible(visible_now: bool) -> void:
	for mesh in _placeholder_meshes:
		mesh.visible = visible_now


func get_capsule_height() -> float:
	return _capsule.height


## Slope of the ground along the current movement direction, in degrees: positive uphill,
## negative downhill, 0 when standing still or airborne. This is the value the animation layer
## uses to pick the game's uphill/downhill clips; it is derived from the floor normal, so a
## ramp banked sideways has no slope until the character actually heads up it.
func get_slope_deg() -> float:
	if not is_grounded():
		return 0.0
	var flat := Vector3(velocity.x, 0.0, velocity.z)
	if flat.length() < 0.05:
		return 0.0
	# Uphill means the floor normal leans against the movement direction.
	return -rad_to_deg(asin(clampf(get_floor_normal().dot(flat.normalized()), -1.0, 1.0)))


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


## The floor/step block recovered from UCharacterMovementComponent's defaults
## (RE workspace reports/floor-params.txt). Godot's own defaults are close but not identical,
## and it has no step-up at all, which `_try_step_up` covers.
func _apply_floor_settings() -> void:
	floor_max_angle = deg_to_rad(tuning.floor_max_angle_deg)
	floor_snap_length = tuning.floor_snap_length
	floor_stop_on_slope = true
	# UE4 does not slow the character down on slopes, so keep the requested speed constant.
	floor_constant_speed = true


# ------------------------------------------------------------------- frame --

func _physics_process(delta: float) -> void:
	_tick_posture(delta)
	_tick_state(delta)
	_tick_facing(delta)
	_tick_velocity(delta)
	_tick_air(delta)

	_try_step_up()
	move_and_slide()
	_stick_to_floor(delta)
	_update_speed_ratio(delta)
	_was_on_floor = is_grounded()


## Godot snaps to the floor only on the first frame a floor is lost, and this capsule's rounded
## base can roll off a stair nose without a floor contact on that frame (measured on a 0.35 m
## platform: is_on_floor() false at 0.28 m up, then a free fall, so the step was crossed as a
## fall). UE4 instead keeps the character on the ground with a downward sweep and perches on
## ledges up to PerchAdditionalHeight (40 cm in reports/floor-params.txt), so sweep here too -
## but only within `STICK_GRACE` of standing on something, or every real fall would be cut
## short by the sweep distance.
func _stick_to_floor(delta: float) -> void:
	_stuck_to_floor = false
	if is_on_floor():
		_stick_time_left = STICK_GRACE
		return
	_stick_time_left = maxf(0.0, _stick_time_left - delta)
	if _stick_time_left <= 0.0 or velocity.y > 0.01 or tuning.floor_snap_length <= 0.0:
		return
	var probe := KinematicCollision3D.new()
	if not test_move(global_transform, Vector3.DOWN * tuning.floor_snap_length, probe):
		return
	# Only a walkable surface counts: a stair nose or a steep face is not a floor.
	if probe.get_normal().dot(up_direction) < cos(floor_max_angle) - 0.01:
		return
	# A contact with no distance left still counts as grounded: after a stick the capsule sits
	# flush with the floor, and move_and_slide needs a frame to report a floor again.
	var drop := global_position.y - probe.get_position().y
	if drop > 0.0:
		global_position.y -= minf(drop, tuning.floor_snap_length)
	velocity.y = 0.0
	_stuck_to_floor = true


## UE4's step-up pass, which CharacterBody3D does not have: without it a 20 cm stair is a wall.
##
## The move is only redirected when the blocking surface is steeper than the walkable limit
## (a riser, not a ramp - `move_and_slide` already climbs ramps), the same move succeeds from
## `max_step_height` above the current position, and there is headroom to rise. The lift is
## then the height of the surface found by a downward probe, so the capsule rises by exactly
## the step height and `move_and_slide` carries it forward onto the step.
func _try_step_up() -> void:
	var motion := Vector3(velocity.x, 0.0, velocity.z) * get_physics_process_delta_time()
	if not is_grounded() or tuning.max_step_height <= 0.0 or motion.length_squared() < 1.0e-8:
		return
	var wall := KinematicCollision3D.new()
	if not test_move(global_transform, motion, wall):
		return										# nothing in the way
	if wall.get_normal().dot(up_direction) > cos(floor_max_angle) - 0.01:
		return										# walkable surface: slide up it instead
	var lift := up_direction * tuning.max_step_height
	var raised := global_transform.translated(lift)
	if test_move(raised, motion) or test_move(global_transform, lift):
		return										# a wall, or no room to rise
	var probe := KinematicCollision3D.new()
	if not test_move(raised.translated(motion), -lift, probe):
		return										# nothing to stand on
	# The capsule's shape origin is its base, so the contact point is the step surface.
	var rise := probe.get_position().dot(up_direction) - global_position.dot(up_direction)
	if rise <= 0.001 or rise > tuning.max_step_height + 0.001:
		return
	global_position += up_direction * (rise + 0.001)
	if velocity.y < 0.0:
		velocity.y = 0.0


func _tick_state(delta: float) -> void:
	state_machine.on_floor = is_grounded()
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
	var in_air := not is_grounded()
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
	if is_grounded():
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
