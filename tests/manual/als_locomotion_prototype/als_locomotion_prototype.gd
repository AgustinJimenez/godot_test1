extends "res://tests/manual/als_locomotion_prototype/als_locomotion_prototype_build.gd"
## Split out of a single monolithic file purely to stay under the project's
## max-file-lines lint cap - see als_locomotion_prototype_state.gd's header
## for the full explanation of the split. This is the file the scene actually
## attaches (als_locomotion_prototype.tscn references this exact filename),
## so it keeps the per-frame update loop and terrain construction.

func _physics_process(delta: float) -> void:
	if _body == null:
		return
	if _is_mantling:
		# Fully procedural, like turn-in-place: no gravity/collision movement
		# while mantling, just an interpolated position toward the ledge-top
		# point over the clip's duration.
		_update_mantle(delta)
		return

	var input_dir := Vector2(
			Input.get_action_strength(&"move_right") - Input.get_action_strength(&"move_left"),
			Input.get_action_strength(&"move_back") - Input.get_action_strength(&"move_forward"))
	input_dir = input_dir.limit_length(1.0)

	if not _body.is_on_floor():
		_body.velocity.y -= GRAVITY * delta
		# Captured here (not read at the landing edge itself) because
		# move_and_slide() zeroes velocity.y back toward 0 the instant it
		# resolves floor contact - by the time on_floor flips true this frame,
		# the real "how fast was I actually falling" value is already gone.
		_last_fall_velocity_y = _body.velocity.y
		# Running/jumping mantle: pressing jump again mid-air (e.g. right after
		# leaving the ground toward a ledge) can also trigger a mantle, not
		# just a standing jump-press - real ALS lets a running jump catch a
		# ledge the same way.
		if Input.is_action_just_pressed(&"jump"):
			_try_start_mantle(false)
	elif Input.is_action_just_pressed(CROUCH_ACTION):
		# Crouch is grounded-only in ALS, and toggled rather than held.
		_set_crouching(not _is_crouching)
	elif Input.is_action_just_pressed(&"jump"):
		# Jumping from a crouch stands up first, and is refused outright if
		# there's no headroom to stand into - matching crouch's own gate.
		if _is_crouching:
			_set_crouching(false)
		if not _is_crouching and not _try_start_mantle(true):
			_body.velocity.y = JUMP_VELOCITY
			_apply_jump_play_rate()

	# ALS's three real gaits (EALSGait Walking/Running/Sprinting). Running is
	# the baseline; walk and sprint are both held modifiers off it.
	var target_speed := CROUCH_RUN_SPEED if _is_crouching else RUN_SPEED
	if Input.is_action_pressed(&"sprint"):
		target_speed = CROUCH_SPRINT_SPEED if _is_crouching else SPRINT_SPEED
	elif Input.is_action_pressed(WALK_ACTION):
		target_speed = CROUCH_WALK_SPEED if _is_crouching else WALK_SPEED
	# Camera-relative movement (ALS standard third-person control): input is
	# always relative to where the camera is looking, in both rotation modes -
	# only the BODY's facing differs between the two modes, not which way
	# input actually moves it.
	var camera_yaw := _camera_pivot.rotation.y
	# ALSBaseCharacter.cpp caches AimYawRate once per tick, before anything
	# reads it - same here, since both the turn-in-place gate and the grounded
	# rotation rate consume it.
	_aim_yaw_rate_deg = (
			absf(rad_to_deg(wrapf(camera_yaw - _prev_camera_yaw, -PI, PI))) / delta
			if _has_prev_camera_yaw else 0.0)
	_prev_camera_yaw = camera_yaw
	_has_prev_camera_yaw = true
	var move_dir := Basis(Vector3.UP, camera_yaw) * Vector3(input_dir.x, 0.0, input_dir.y)
	var target_velocity := move_dir * target_speed
	var horizontal := Vector3(_body.velocity.x, 0.0, _body.velocity.z)
	var accel := ACCELERATION if move_dir.length() > 0.01 else DECELERATION
	horizontal = horizontal.move_toward(target_velocity, accel * delta)
	_body.velocity.x = horizontal.x
	_body.velocity.z = horizontal.z

	_update_air_lean_and_land_prediction(delta)

	var playback: AnimationNodeStateMachinePlayback = _anim_tree.get(&"parameters/playback")

	if _is_turning and move_dir.length() > 0.01:
		# Player started moving mid-turn - cancel back to normal Grounded
		# blending immediately rather than finishing the canned animation.
		_is_turning = false
		playback.travel(&"Grounded")

	if _is_landing and move_dir.length() > 0.01:
		# Same cancel-early idea as turn-in-place: don't force the player to
		# sit through the landing pose if they're already moving away.
		_is_landing = false
		playback.travel(&"Grounded")

	# ALSBaseCharacter.cpp's real bCanUpdateMovingRot gate: (bIsMoving &&
	# bHasMovementInput) || Speed > 150 cm/s (1.5 m/s) - shared by both
	# rotation modes for whether the body continuously chases a target yaw
	# at all this frame. While NOT moving, real ALS never continuously
	# rotates the body either way; Looking Direction instead runs the
	# delay-gated discrete TurnInPlaceCheck (see _update_turn_in_place_check)
	# so idle facing changes happen as a canned 90/180 clip, not a live spin.
	var moving_rot_gate := (
			move_dir.length() > 0.01 or horizontal.length() > ALS_MOVING_ROT_SPEED_THRESHOLD)
	if _is_turning:
		_update_turn_in_place(delta)
	elif _rotation_mode == RotationMode.LOOKING_DIRECTION:
		if moving_rot_gate:
			# Real ALS (ALSBaseCharacter.cpp::UpdateGroundedRotation, Looking
			# Direction branch - confirmed by reading the actual source, not
			# assumed): while sprinting the body SNAPS TO FACE VELOCITY, same
			# as Velocity Direction mode, not the camera. Non-sprint target is
			# AimingRotation.Yaw + a per-clip YawOffsetCurve (hip/lean offset
			# baked into the animation itself) - we have no such curve, so the
			# non-sprint target here is plain camera yaw.
			_turn_check_elapsed = 0.0
			if Input.is_action_pressed(&"sprint") and horizontal.length() > 0.1:
				var vel_yaw := atan2(-horizontal.x, -horizontal.z)
				_smooth_character_rotation(vel_yaw, ALS_TARGET_INTERP_VELOCITY_DEG, delta)
			else:
				_smooth_character_rotation(camera_yaw, ALS_TARGET_INTERP_LOOKING_DEG, delta)
		elif _body.is_on_floor():
			_update_turn_in_place_check(delta, camera_yaw, playback)
	elif moving_rot_gate:
		# Godot actor forward is local -Z: atan2(-x, -z) is the correct yaw
		# for a direction vector (see AGENTS.md). Confirmed backward before an
		# earlier fix via a headless test comparing actual velocity direction
		# against the character's resulting forward vector (dot product -1.0
		# i.e. facing exactly opposite its own travel direction).
		var target_yaw := atan2(-horizontal.x, -horizontal.z)
		_smooth_character_rotation(target_yaw, ALS_TARGET_INTERP_VELOCITY_DEG, delta)
	elif _body.is_on_floor():
		# Idle in Velocity Direction mode: real ALS leaves the body facing
		# wherever it last stopped (no idle facing-catch-up in this mode at
		# all) - this prototype still runs the same delay-gated turn-in-place
		# trigger here anyway, as a pragmatic UX addition so the camera can't
		# leave the body stuck facing away indefinitely. Not itself ported
		# behavior, just reuses the real trigger machinery.
		_update_turn_in_place_check(delta, camera_yaw, playback)

	_apply_stair_step_up(delta)
	_body.move_and_slide()

	var on_floor := _body.is_on_floor()
	if _foot_ik_modifier != null:
		_foot_ik_modifier.set_character_grounded(on_floor)
		# The solver is turned OFF entirely while crouched, not merely
		# pose-suppressed. Measured, not assumed: running it on ALS's crouch
		# pose drags the hips from the clip's authored 0.437m up to 0.966m -
		# almost fully standing - because it plants the bent crouch legs and
		# pushes the pelvis up to compensate" was a misdiagnosis - the crouch
		# clips' arms were broken by a wrong retarget argument (see the status
		# log), and that made the pose look wrong for an unrelated reason.
		# Confirmed by testing directly: with the retarget fixed, leaving the
		# modifier fully active still measures the crouch pose correctly
		# (head 1.446 -> 0.951m above the feet). Foot IK stays on throughout
		# crouch; only strafing suppresses the foot pose, matching PlayerBody's
		# own condition exactly.
		_foot_ik_modifier.set_pose_suppressed(
				_is_crouching and on_floor and absf(input_dir.x) > 0.5)
	if _spine_twist_modifier != null:
		# DISABLED, and that is the faithful behaviour - see below.
		#
		# The C++ (`UpdateAimingValues`) only gates SpineRotation on
		# `!RotationMode.VelocityDirection()`, which is what an earlier version
		# of this drove it from - and it looked wrong live: the torso swung
		# with the camera while the legs stayed planted, unbounded, at any
		# angle. Reading the AnimGraph rather than just the C++ shows why. The
		# node applying SpineRotation is alpha-gated by an ANIMATION CURVE,
		# `Enable_SpineRotation` (its AlphaCurveName), sitting under a comment
		# reading "Apply Aim Offsets or manual spine rotation" - it is the
		# either/or FALLBACK for when aim offsets are masked, not the mechanism
		# ordinary third-person uses. Third-person upper-body-follows-camera in
		# real ALS comes from the additive AIM OFFSET, which is bounded and
		# smooth; the manual twist is raw and unbounded.
		#
		# Our retargeted clips carry no curves at all (same reason
		# `Layering_*`/`Mask_*`/`BasePose_*` are unavailable), so
		# `Enable_SpineRotation` would evaluate to 0 here and real ALS would
		# apply no twist either. Driving it unconditionally was porting a real
		# mechanism onto the wrong condition.
		#
		# The modifier itself is kept, correct and verified (25/50/75 across
		# spine_01/02/03) - it becomes usable if an Aiming mode and a real aim
		# offset ever exist here.
		_spine_twist_modifier.twist_yaw = 0.0
	if not _anim_started:
		# The "parameters/playback" resource isn't live until the tree has
		# processed at least one frame - calling start() from _build_player
		# (before any frame ran) silently had no effect, confirmed via a
		# headless smoke test. Whatever the state machine's real default
		# initial state is otherwise (observed as Airborne, not the first- or
		# last-added node), this forces it explicitly on the first real frame.
		playback.start(&"Grounded" if on_floor else &"Airborne")
		_anim_started = true
		_visually_airborne = not on_floor
	else:
		_airborne_frames = 0 if on_floor else _airborne_frames + 1
		if _visually_airborne and on_floor:
			# Real landing - the animation had actually committed to Airborne.
			_is_turning = false
			_is_landing = true
			_land_elapsed = 0.0
			var use_heavy := absf(_last_fall_velocity_y) >= LAND_HEAVY_SPEED_THRESHOLD
			var land_clip_name := &"land_heavy" if use_heavy else &"land_light"
			_land_node.animation = StringName("clips/" + String(land_clip_name))
			var land_anim: Animation = _anim_player.get_animation_library(
					&"clips").get_animation(land_clip_name)
			_land_duration = land_anim.length
			playback.travel(&"Landing")
			_visually_airborne = false
		elif not _visually_airborne and not on_floor and _airborne_frames >= AIRBORNE_DEBOUNCE_FRAMES:
			# Off the floor long enough to treat as a real fall, not a
			# momentary stair-step snap gap.
			_is_turning = false
			playback.travel(&"Airborne")
			_visually_airborne = true
	if _is_landing:
		_update_landing(delta)
	# Character-LOCAL (right, forward) velocity - matches the blend space's
	# own points, which are placed by direction relative to the BODY's own
	# facing, not world space (this is what makes strafing in Looking
	# Direction mode play a strafe/backpedal clip instead of forward-walk).
	var local_velocity: Vector3 = _character.transform.basis.inverse() * horizontal
	var blend_position := Vector2(local_velocity.x, -local_velocity.z)
	# Each blendspace's OUTERMOST ring is its run ring, and sprint speed sits
	# well beyond it - a sprinting blend position would land outside the
	# triangulated hull entirely and stop resolving to the run clips (this is
	# exactly what broke sprint when the invented 3.0/6.0 speeds were replaced
	# by ALS's real 1.75/3.75/6.5, since sprint used to land ON the ring by
	# coincidence). ALS has no sprint clips: it clamps to the run cycle and
	# raises the play rate instead, which is what the TimeScale below does.
	_anim_tree.set(&"parameters/Grounded/StandBlend/blend_position",
			blend_position.limit_length(RUN_SPEED))
	_anim_tree.set(&"parameters/Grounded/CrouchBlend/blend_position",
			blend_position.limit_length(CROUCH_RUN_SPEED))

	# CalculateStandingPlayRate, simplified: real speed divided by the speed
	# the current gait's clips were AUTHORED at. ALS's full version lerps
	# between all three via the `W_Gait` animation curve, which our retargeted
	# clips don't carry, so the gait is selected discretely instead.
	var animated_speed := ALS_ANIMATED_RUN_SPEED
	if _is_crouching:
		animated_speed = ALS_ANIMATED_CROUCH_SPEED
	elif Input.is_action_pressed(&"sprint"):
		animated_speed = ALS_ANIMATED_SPRINT_SPEED
	elif Input.is_action_pressed(WALK_ACTION):
		animated_speed = ALS_ANIMATED_WALK_SPEED
	# Held at 1.0 when essentially stationary: ALS can clamp to 0 because its
	# idle is a separate state, but here idle shares the blendspace and a zero
	# rate would freeze it.
	var ground_speed := horizontal.length()
	_anim_tree.set(&"parameters/Grounded/GroundTimeScale/scale",
			1.0 if ground_speed < 0.1
			else clampf(ground_speed / animated_speed, 0.0, ALS_PLAY_RATE_MAX))

	# Sprint layer: only once actually moving at pace, so a stationary sprint
	# key-hold doesn't pop the character into a sprint pose on the spot.
	var sprinting := (
			SPRINT_CLIP_ENABLED
			and Input.is_action_pressed(&"sprint") and not _is_crouching
			and ground_speed > RUN_SPEED * 0.5)
	_sprint_blend = move_toward(
			_sprint_blend, 1.0 if sprinting else 0.0, SPRINT_BLEND_SPEED * delta)
	_anim_tree.set(&"parameters/Grounded/SprintBlend/blend_amount", _sprint_blend)
	# Eased rather than snapped so standing up / crouching down is a blend, not
	# a pop. ALS gets the same smoothing from its BasePose_N/BasePose_CLF
	# curves, which we have no equivalent of.
	_stance_blend = move_toward(_stance_blend, 1.0 if _is_crouching else 0.0,
			STANCE_BLEND_SPEED * delta)
	_anim_tree.set(&"parameters/Grounded/StanceBlend/blend_amount", _stance_blend)
	_anim_tree.set(&"parameters/Airborne/AirBlend/blend_position",
			clampf(_body.velocity.y, -AIR_BLEND_VELOCITY_RANGE, AIR_BLEND_VELOCITY_RANGE))

	# Last: the camera reads the character's final settled position and the
	# skeleton's current head location, so it has to run after move_and_slide
	# and after the animation tree has been driven for this frame.
	_update_camera(delta)


## Reuses foot_ik_ramp_matrix_check.gd's ramp shape/rotation math and
## foot_ik_stair_surfaces.gd's step-height parameterization, but built
## standalone here (no PlayerStairController/foot-IK layer coupling) so this
## prototype stays independent of actors/player/*.
func _build_terrain() -> void:
	var floor_mesh := CSGBox3D.new()
	floor_mesh.name = &"Floor"
	floor_mesh.size = Vector3(40.0, 0.2, 40.0)
	floor_mesh.position = Vector3(0.0, -0.1, 0.0)
	floor_mesh.use_collision = true
	add_child(floor_mesh)

	var ramp_angles := [15.0, 30.0, 45.0]
	for i in ramp_angles.size():
		_build_ramp(Vector3(-12.0 + i * 6.0, 0.0, -6.0), ramp_angles[i])

	_build_stairs(Vector3(6.0, 0.0, -6.0), 8, 0.15)
	_build_stairs(Vector3(12.0, 0.0, -6.0), 8, 0.3)

	_build_mantle_ledge(Vector3(0.0, 0.0, 4.0), 1.0)
	_build_mantle_ledge(Vector3(4.0, 0.0, 4.0), 1.8)


func _build_mantle_ledge(origin: Vector3, height: float) -> void:
	const LEDGE_WIDTH := 3.0
	const LEDGE_DEPTH := 2.0
	var ledge := CSGBox3D.new()
	ledge.name = &"MantleLedge"
	ledge.size = Vector3(LEDGE_WIDTH, height, LEDGE_DEPTH)
	ledge.use_collision = true
	ledge.position = origin + Vector3(0.0, height * 0.5, 0.0)
	add_child(ledge)


func _build_ramp(origin: Vector3, angle_degrees: float) -> void:
	const RAMP_WIDTH := 3.0
	const RAMP_LENGTH := 4.0
	const RAMP_THICKNESS := 0.3
	var ramp := CSGBox3D.new()
	ramp.name = StringName("Ramp%d" % roundi(angle_degrees))
	ramp.size = Vector3(RAMP_WIDTH, RAMP_THICKNESS, RAMP_LENGTH)
	ramp.use_collision = true
	ramp.rotation = Vector3(-deg_to_rad(angle_degrees), 0.0, 0.0)
	var half_length := ramp.basis * Vector3(0.0, 0.0, RAMP_LENGTH * 0.5)
	var half_thickness := ramp.basis * Vector3(0.0, -RAMP_THICKNESS * 0.5, 0.0)
	ramp.position = origin + half_length + half_thickness
	add_child(ramp)


func _build_stairs(origin: Vector3, step_count: int, step_height: float) -> void:
	# 0.9, not the original 0.3: the capsule collider is 0.7m in diameter
	# (radius 0.35), wider than a 0.3-deep tread - the character's own body
	# was permanently touching the NEXT riser even standing still on any
	# step, so _apply_stair_step_up()'s post-lift test_move() always still
	# read "blocked" and correctly (per its own logic) refused to climb.
	# Confirmed via a per-frame position/velocity trace showing the
	# character fully stuck (zero velocity) at the base of the stairs,
	# never even starting to climb - not a step-up logic bug, a tread-vs-
	# capsule geometry mismatch.
	const STEP_DEPTH := 0.9
	const STEP_WIDTH := 2.0
	var stairs := Node3D.new()
	stairs.name = StringName("Stairs_h%d" % roundi(step_height * 100.0))
	add_child(stairs)
	for i in step_count:
		var step := CSGBox3D.new()
		step.name = StringName("Step%d" % i)
		var rise := step_height * (i + 1)
		step.size = Vector3(STEP_WIDTH, rise, STEP_DEPTH)
		step.use_collision = true
		step.position = origin + Vector3(0.0, rise * 0.5, -STEP_DEPTH * i)
		stairs.add_child(step)
