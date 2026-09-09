extends "res://tests/manual/als_locomotion_prototype/als_locomotion_prototype_state.gd"
## Split out of als_locomotion_prototype.gd purely to stay under the
## project's max-file-lines lint cap - see als_locomotion_prototype_state.gd's
## header for the full explanation of the split. Holds player/scene
## construction and the mid-level per-system update helpers (turn-in-place,
## stair-step, landing, mantle) that _physics_process (in the final file of
## the chain) calls into every frame.

func _build_player() -> void:
	_body = CharacterBody3D.new()
	_body.name = &"PrototypeBody"
	_body.position = Vector3(0.0, 1.0, 8.0)
	# Wider than STAIR_STEP_HEIGHT so move_and_slide() reliably re-acquires
	# the floor the same frame after _apply_stair_step_up() lifts the body -
	# the default (0.1) left a 1-frame is_on_floor()=false gap on every
	# single stair step, which the Grounded/Airborne/Landing state machine
	# read as a real fall, flickering the fall/landing animation up an
	# entire flight instead of a smooth walk (confirmed by live user report).
	_body.floor_snap_length = STAIR_STEP_HEIGHT + 0.1

	var shape := CollisionShape3D.new()
	_collision_shape = shape
	var capsule := CapsuleShape3D.new()
	_capsule = capsule
	capsule.radius = 0.35
	capsule.height = 1.8
	shape.shape = capsule
	shape.position = Vector3(0.0, 0.9, 0.0)
	_body.add_child(shape)

	# _character is the LOGICAL facing node every rotation-mode/turn-in-place
	# calculation manipulates - kept as a bare wrapper, separate from the
	# instantiated mesh, because the mesh's own visual front turned out not to
	# match what a bone-position-based facing probe reported (confirmed wrong
	# by direct user observation after the probe said otherwise - see
	# AGENT_TASKS/016's status notes). Correcting the offset here, on the
	# purely-visual child, means every rotation formula above stays the
	# textbook-correct Godot -Z convention with no compensating fudge baked
	# into the movement/camera/turn math itself.
	_character = PrototypeBodyFacade.new()
	_character.name = &"CharacterFacing"
	_body.add_child(_character)
	var visual := (load(CHARACTER_MODEL) as PackedScene).instantiate()
	visual.rotation.y = PI
	_character.add_child(visual)
	_character.character = visual
	var skeleton: Skeleton3D = visual.find_child("Skeleton3D", true, false)
	_skeleton = skeleton
	_anim_player = _character.find_child("AnimationPlayer", true, false)
	if _anim_player == null:
		_anim_player = AnimationPlayer.new()
		_anim_player.name = &"AnimationPlayer"
		_character.add_child(_anim_player)
	_character.anim_player = _anim_player
	# Track paths resolve relative to root_node (the character's own parent
	# here), not to the AnimationPlayer itself - see 015/016 retarget notes.
	_anim_player.root_node = _anim_player.get_path_to(skeleton.get_parent())
	var anim_root: Node = _anim_player.get_node(_anim_player.root_node)
	var skeleton_path := anim_root.get_path_to(skeleton)

	# Same auto-detect PlayerBody._detect_target_humanoid_map() falls back to
	# for a character with no characters/*.json catalog entry - needed here so
	# PlayerFootIKModifier.resolve_bone_name() (via the facade) can map its
	# canonical leg-bone roles (LeftUpLeg/LeftLeg/LeftFoot/...) onto Y Bot's
	# real mixamorig_-prefixed bone names.
	var prefix = HumanoidRetargeter.detect_bone_prefix(skeleton)
	_character._target_humanoid_map = (
			CharacterEditorRigHandler.auto_map(skeleton) if prefix == null or prefix == "B-"
			else CharacterEditorRigHandler.full_map_from_prefix(skeleton, prefix))

	var lib := AnimationLibrary.new()
	for entry in [[&"idle", IDLE_ANIMATION], [&"jump", JUMP_ANIMATION], [&"fall", FALL_ANIMATION]]:
		var anim: Animation = (load(entry[1]) as Animation).duplicate()
		anim.loop_mode = Animation.LOOP_LINEAR
		_retarget_track_paths(anim, skeleton_path)
		lib.add_animation(entry[0], anim)
	for clip_name: StringName in DIRECTIONAL_ANIMATIONS:
		var dir_info: Array = DIRECTIONAL_ANIMATIONS[clip_name]
		var anim: Animation = (load(String(dir_info[0])) as Animation).duplicate()
		anim.loop_mode = Animation.LOOP_LINEAR
		_retarget_track_paths(anim, skeleton_path)
		lib.add_animation(clip_name, anim)
	for clip_name: StringName in CROUCH_ANIMATIONS:
		var crouch_info: Array = CROUCH_ANIMATIONS[clip_name]
		var anim: Animation = (load(String(crouch_info[0])) as Animation).duplicate()
		anim.loop_mode = Animation.LOOP_LINEAR
		_retarget_track_paths(anim, skeleton_path)
		lib.add_animation(clip_name, anim)
	var crouch_idle: Animation = (load(CROUCH_IDLE_ANIMATION) as Animation).duplicate()
	crouch_idle.loop_mode = Animation.LOOP_LINEAR
	_retarget_track_paths(crouch_idle, skeleton_path)
	lib.add_animation(&"crouch_idle", crouch_idle)
	var sprint_anim: Animation = (load(SPRINT_ANIMATION) as Animation).duplicate()
	sprint_anim.loop_mode = Animation.LOOP_LINEAR
	_retarget_track_paths(sprint_anim, skeleton_path)
	lib.add_animation(&"sprint", sprint_anim)
	for entry in [[&"mantle_low", MANTLE_LOW_ANIMATION], [&"mantle_high", MANTLE_HIGH_ANIMATION]]:
		var mantle_anim: Animation = (load(entry[1]) as Animation).duplicate()
		mantle_anim.loop_mode = Animation.LOOP_NONE
		_retarget_track_paths(mantle_anim, skeleton_path)
		lib.add_animation(entry[0], mantle_anim)
	for entry in [[&"land_light", LAND_LIGHT_ANIMATION], [&"land_heavy", LAND_HEAVY_ANIMATION]]:
		var land_anim: Animation = (load(entry[1]) as Animation).duplicate()
		land_anim.loop_mode = Animation.LOOP_NONE
		_retarget_track_paths(land_anim, skeleton_path)
		lib.add_animation(entry[0], land_anim)
	for clip_name: StringName in TURN_ANIMATIONS:
		var turn_info: Array = TURN_ANIMATIONS[clip_name]
		var anim: Animation = (load(String(turn_info[0])) as Animation).duplicate()
		anim.loop_mode = Animation.LOOP_NONE
		_retarget_track_paths(anim, skeleton_path)
		lib.add_animation(clip_name, anim)
	_anim_player.add_animation_library(&"clips", lib)

	# Grounded: 2D directional blendspace (real ALS technique) - idle at the
	# origin, a walk-speed ring of 6 directional clips, and a run-speed ring
	# of the same 6 directions at a larger radius. Godot 4.6's
	# AnimationNodeBlendSpace2D only has Interpolated/Discrete/Carry modes -
	# no separate "Directional" mode like some other engines (confirmed via
	# property-list introspection, not assumed) - but the default
	# Interpolated mode already does a Delaunay-triangulation blend between
	# the nearest enclosing points, which is exactly the technique needed here.
	var ground_blend := AnimationNodeBlendSpace2D.new()
	ground_blend.min_space = Vector2(-SPRINT_SPEED, -SPRINT_SPEED)
	ground_blend.max_space = Vector2(SPRINT_SPEED, SPRINT_SPEED)
	var idle_node := AnimationNodeAnimation.new()
	idle_node.animation = &"clips/idle"
	ground_blend.add_blend_point(idle_node, Vector2.ZERO)
	for clip_name: StringName in DIRECTIONAL_ANIMATIONS:
		var dir_info: Array = DIRECTIONAL_ANIMATIONS[clip_name]
		var dir_node := AnimationNodeAnimation.new()
		dir_node.animation = StringName("clips/" + String(clip_name))
		var direction: Vector2 = dir_info[1]
		var speed: float = dir_info[2]
		ground_blend.add_blend_point(dir_node, direction * speed)

	# Crouch: its own 4-point blendspace (ALS's crouch set has no diagonals),
	# rings at the crouch gait speeds rather than the standing ones.
	var crouch_blend := AnimationNodeBlendSpace2D.new()
	crouch_blend.min_space = Vector2(-CROUCH_SPRINT_SPEED, -CROUCH_SPRINT_SPEED)
	crouch_blend.max_space = Vector2(CROUCH_SPRINT_SPEED, CROUCH_SPRINT_SPEED)
	var crouch_idle_node := AnimationNodeAnimation.new()
	crouch_idle_node.animation = &"clips/crouch_idle"
	crouch_blend.add_blend_point(crouch_idle_node, Vector2.ZERO)
	for clip_name: StringName in CROUCH_ANIMATIONS:
		var crouch_info: Array = CROUCH_ANIMATIONS[clip_name]
		var crouch_node := AnimationNodeAnimation.new()
		crouch_node.animation = StringName("clips/" + String(clip_name))
		crouch_blend.add_blend_point(crouch_node, (crouch_info[1] as Vector2) * CROUCH_RUN_SPEED)

	# Stance is a Blend2 INSIDE the Grounded state rather than a sibling state.
	# Real ALS does use separate (N) Standing / (CLF) Crouching states, but it
	# also curve-blends between the two base poses; a Blend2 gets the same
	# visual result here while leaving every existing playback.travel(
	# &"Grounded") call - turn-in-place, landing, mantle exits - working
	# untouched, which a new sibling state would have silently broken.
	var ground_tree := AnimationNodeBlendTree.new()
	ground_tree.add_node(&"StandBlend", ground_blend)
	ground_tree.add_node(&"CrouchBlend", crouch_blend)
	var stance_blend := AnimationNodeBlend2.new()
	stance_blend.sync = true
	ground_tree.add_node(&"StanceBlend", stance_blend)
	# Sprint layers over the standing blendspace before stance is applied, so
	# crouching still wins over it (ALS has no crouched sprint clip either).
	var sprint_node := AnimationNodeAnimation.new()
	sprint_node.animation = &"clips/sprint"
	ground_tree.add_node(&"SprintClip", sprint_node)
	var sprint_blend := AnimationNodeBlend2.new()
	# Synchronised: run is a 0.8s cycle and sprint a 0.6s one, so without this
	# Godot advances them independently and they drift out of phase - blending
	# two locomotion cycles at opposite phases puts one arm forward and the
	# other back at the same time, which reads exactly as "the arms cross".
	sprint_blend.sync = true
	ground_tree.add_node(&"SprintBlend", sprint_blend)
	ground_tree.connect_node(&"SprintBlend", 0, &"StandBlend")
	ground_tree.connect_node(&"SprintBlend", 1, &"SprintClip")
	ground_tree.connect_node(&"StanceBlend", 0, &"SprintBlend")
	ground_tree.connect_node(&"StanceBlend", 1, &"CrouchBlend")
	# Same trick as the Airborne branch: Godot has no per-state play rate, and
	# ALS's whole sprint presentation is the run cycle played faster
	# (CalculateStandingPlayRate) rather than a separate clip set.
	var ground_time_scale := AnimationNodeTimeScale.new()
	ground_tree.add_node(&"GroundTimeScale", ground_time_scale)
	ground_tree.connect_node(&"GroundTimeScale", 0, &"StanceBlend")
	ground_tree.connect_node(&"output", 0, &"GroundTimeScale")

	# Airborne: 1D blendspace keyed by vertical velocity - fall loop while
	# descending, jump loop while still rising. min/max are a real velocity
	# RANGE (m/s), not a normalized -1..1 pair: the blend position fed in
	# is clamped raw velocity.y (see _physics_process), so this genuinely
	# eases through zero at the arc's apex instead of the two clips ever
	# being weighted 50/50 by construction.
	var air_blend := AnimationNodeBlendSpace1D.new()
	air_blend.min_space = -AIR_BLEND_VELOCITY_RANGE
	air_blend.max_space = AIR_BLEND_VELOCITY_RANGE
	var fall_node := AnimationNodeAnimation.new()
	fall_node.animation = &"clips/fall"
	var jump_node := AnimationNodeAnimation.new()
	jump_node.animation = &"clips/jump"
	air_blend.add_blend_point(fall_node, -AIR_BLEND_VELOCITY_RANGE)
	air_blend.add_blend_point(jump_node, AIR_BLEND_VELOCITY_RANGE)

	# The Airborne state is a blend tree rather than the bare blendspace, only
	# so an AnimationNodeTimeScale can sit between it and the output: Godot has
	# no per-state play rate, and real ALS scales the jump animation by
	# OnJumped's JumpPlayRate. Driven via
	# "parameters/Airborne/JumpTimeScale/scale" (see _apply_jump_play_rate).
	var air_tree := AnimationNodeBlendTree.new()
	air_tree.add_node(&"AirBlend", air_blend)
	var air_time_scale := AnimationNodeTimeScale.new()
	air_tree.add_node(&"JumpTimeScale", air_time_scale)
	air_tree.connect_node(&"JumpTimeScale", 0, &"AirBlend")
	air_tree.connect_node(&"output", 0, &"JumpTimeScale")

	# Grounded <-> Airborne, switched explicitly via playback.travel() on
	# is_on_floor() transitions (see _physics_process) rather than an
	# advance_condition, since the trigger is a one-frame edge, not a
	# continuously-true condition.
	var state_machine := AnimationNodeStateMachine.new()
	state_machine.add_node(&"Grounded", ground_tree)
	state_machine.add_node(&"Airborne", air_tree)
	var to_air := AnimationNodeStateMachineTransition.new()
	to_air.xfade_time = 0.15
	to_air.advance_mode = AnimationNodeStateMachineTransition.ADVANCE_MODE_DISABLED
	state_machine.add_transition(&"Grounded", &"Airborne", to_air)
	var to_ground := AnimationNodeStateMachineTransition.new()
	to_ground.xfade_time = 0.2
	to_ground.advance_mode = AnimationNodeStateMachineTransition.ADVANCE_MODE_DISABLED
	state_machine.add_transition(&"Airborne", &"Grounded", to_ground)

	# Landing: one-shot ALS_N_Land_Light played on a genuine Airborne->Grounded
	# landing edge (see _physics_process), instead of the plain Airborne->
	# Grounded crossfade above (kept as a fallback for other paths, e.g. the
	# very first frame's forced start()). Which clip plays (light vs heavy) is
	# picked by fall speed at trigger time - _land_node.animation is swapped
	# right before travel(&"Landing"), see LAND_HEAVY_SPEED_THRESHOLD.
	_land_node = AnimationNodeAnimation.new()
	_land_node.animation = &"clips/land_light"
	state_machine.add_node(&"Landing", _land_node)
	var to_landing := AnimationNodeStateMachineTransition.new()
	to_landing.xfade_time = 0.1
	to_landing.advance_mode = AnimationNodeStateMachineTransition.ADVANCE_MODE_DISABLED
	state_machine.add_transition(&"Airborne", &"Landing", to_landing)
	var from_landing := AnimationNodeStateMachineTransition.new()
	from_landing.xfade_time = 0.2
	from_landing.advance_mode = AnimationNodeStateMachineTransition.ADVANCE_MODE_DISABLED
	state_machine.add_transition(&"Landing", &"Grounded", from_landing)

	# Mantle: one-shot, can start from either Grounded or Airborne (a running
	# jump toward a ledge is airborne at the moment mantle triggers) and
	# always returns to Grounded (mantling always ends standing on solid
	# ground). Two states (Low/High), matching real ALS's Low/High mantle
	# TYPE split (see MANTLE_LOW_ANIMATION/MANTLE_HIGH_ANIMATION doc comment).
	for mantle_state in [&"MantleLow", &"MantleHigh"]:
		var mantle_node := AnimationNodeAnimation.new()
		mantle_node.animation = StringName(
				"clips/mantle_low" if mantle_state == &"MantleLow" else "clips/mantle_high")
		# Wrapped in a blend tree, same reason as Airborne/Grounded: Godot has
		# no per-state play rate, and real ALS's PlayRate is a genuine
		# per-asset constant (1.0 for the 1m asset, 1.2 for the 2m one) it
		# applies to both the montage AND the position-correction timeline.
		var mantle_tree := AnimationNodeBlendTree.new()
		mantle_tree.add_node(&"Clip", mantle_node)
		var mantle_time_scale := AnimationNodeTimeScale.new()
		mantle_tree.add_node(&"PlayRate", mantle_time_scale)
		mantle_tree.connect_node(&"PlayRate", 0, &"Clip")
		mantle_tree.connect_node(&"output", 0, &"PlayRate")
		state_machine.add_node(mantle_state, mantle_tree)
		for from_state in [&"Grounded", &"Airborne"]:
			var to_mantle := AnimationNodeStateMachineTransition.new()
			to_mantle.xfade_time = 0.1
			to_mantle.advance_mode = AnimationNodeStateMachineTransition.ADVANCE_MODE_DISABLED
			state_machine.add_transition(from_state, mantle_state, to_mantle)
		var from_mantle := AnimationNodeStateMachineTransition.new()
		from_mantle.xfade_time = 0.15
		from_mantle.advance_mode = AnimationNodeStateMachineTransition.ADVANCE_MODE_DISABLED
		state_machine.add_transition(mantle_state, &"Grounded", from_mantle)

	# Turn-in-place states: one per clip, each just Grounded<->TurnXxx (never
	# Airborne<->TurnXxx - turning only triggers while standing on the floor).
	for clip_name: StringName in TURN_ANIMATIONS:
		var turn_node := AnimationNodeAnimation.new()
		turn_node.animation = StringName("clips/" + String(clip_name))
		var state_name: StringName = TURN_ANIMATIONS[clip_name][1]
		state_machine.add_node(state_name, turn_node)
		var to_turn := AnimationNodeStateMachineTransition.new()
		to_turn.xfade_time = 0.15
		to_turn.advance_mode = AnimationNodeStateMachineTransition.ADVANCE_MODE_DISABLED
		state_machine.add_transition(&"Grounded", state_name, to_turn)
		var from_turn := AnimationNodeStateMachineTransition.new()
		from_turn.xfade_time = 0.15
		from_turn.advance_mode = AnimationNodeStateMachineTransition.ADVANCE_MODE_DISABLED
		state_machine.add_transition(state_name, &"Grounded", from_turn)

	var anim_tree_root := AnimationTree.new()
	anim_tree_root.name = &"AnimationTree"
	anim_tree_root.tree_root = state_machine
	_character.add_child(anim_tree_root)
	anim_tree_root.anim_player = anim_tree_root.get_path_to(_anim_player)
	anim_tree_root.active = true
	_anim_tree = anim_tree_root

	_camera_pivot = Node3D.new()
	_camera_pivot.name = &"CameraPivot"
	_body.add_child(_camera_pivot)
	_camera_pivot.position = Vector3(0.0, 1.6, 0.0)
	_camera_pivot_stand_height = _camera_pivot.position.y
	var camera := Camera3D.new()
	camera.name = &"Camera3D"
	# ALS_CharacterBP's real ThirdPersonFOV (its FirstPersonFOV is also 90).
	camera.fov = ALS_THIRD_PERSON_FOV
	camera.current = true
	# Added to the SCENE, not to the pivot: _update_camera() writes its world
	# transform every frame, ALS-style. Parenting it would re-apply the body's
	# motion on top of the lag and defeat the whole point.
	add_child(camera)
	_camera = camera

	# _body must already be inside the live scene tree before attaching
	# anything that itself calls add_child() during _ready() (like
	# PlayerFootIKModifier's native-backend setup below) - otherwise Godot
	# refuses with "Parent node is busy setting up children" (confirmed via a
	# headless run, not assumed): the real Player scene never hits this
	# because its whole hierarchy already exists via its own .tscn before
	# _ready() runs anywhere in it, but this prototype builds everything
	# procedurally in one _ready() call, so ordering here actually matters.
	add_child(_body)

	# Stretch goal (AGENT_TASKS/016 Phase 6): reuse the existing Foot IK
	# system rather than fork a second implementation, per the task doc's own
	# instruction. PlayerFootIKModifier only needs 6 members off its
	# player_body (see prototype_body_facade.gd's own header comment for how
	# that was confirmed) - the facade above already satisfies all of them.
	# This runs on top of whatever pose the AnimationTree above produced, as
	# a SkeletonModifier3D (the engine calls it automatically after
	# animation, same as real gameplay).
	_foot_ik_modifier = FOOT_IK_MODIFIER.new() as PlayerFootIKModifier
	_foot_ik_modifier.player_body = _character
	skeleton.add_child(_foot_ik_modifier)

	# Added AFTER the foot IK modifier deliberately: SkeletonModifier3D runs in
	# sibling order, and the spine twist writes absolute global poses. Running
	# it second means it snapshots a pose foot IK has already adjusted, rather
	# than writing a pose foot IK then moves out from under it.
	_spine_twist_modifier = SPINE_TWIST_MODIFIER.new() as PrototypeSpineTwistModifier
	_spine_twist_modifier.player_body = _character
	skeleton.add_child(_spine_twist_modifier)

	_mantle_hand_ik_modifier = MANTLE_HAND_IK_MODIFIER.new() as PrototypeMantleHandIKModifier
	_mantle_hand_ik_modifier.player_body = _character
	skeleton.add_child(_mantle_hand_ik_modifier)


func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	_mode_label = Label.new()
	_mode_label.offset_left = 16.0
	_mode_label.offset_top = 16.0
	layer.add_child(_mode_label)
	_update_mode_label()


func _update_mode_label() -> void:
	var mode_name := (
			"Velocity Direction" if _rotation_mode == RotationMode.VELOCITY_DIRECTION
			else "Looking Direction")
	_mode_label.text = (
			"Rotation mode: %s  |  %s  (G toggles mode, Ctrl crouch, Alt walk, Shift sprint)"
			% [mode_name, "Crouching" if _is_crouching else "Standing"])


## Ports ALSBaseCharacter.cpp::SmoothCharacterRotation exactly: NOT a single
## lerp straight to the desired yaw (what this prototype did before reading
## the real source). Two stages - (1) an internal "TargetRotation" chases the
## desired yaw at a CONSTANT angular speed (RInterpConstantTo, i.e. a hard
## cap on how fast the target itself can move, independent of how far away it
## is), then (2) the actual character rotation exponentially chases that
## TargetRotation (RInterpTo). The result is snappier at first (constant-rate
## catch-up) and eases in at the end (exponential), rather than a single lerp
## which is fastest at the start and slowest at the end regardless of gap size.
func _smooth_character_rotation(
		target_yaw: float, target_interp_speed_deg: float, delta: float) -> void:
	_rotation_target_yaw = rotate_toward(
			_rotation_target_yaw, target_yaw, deg_to_rad(target_interp_speed_deg) * delta)
	# Stage 2's rate is CalculateGroundedRotationRate: the (unportable) speed
	# curve, stood in for by ROTATION_SPEED, times the real aim-yaw-rate
	# multiplier - see ALS_AIM_YAW_RATE_RANGE_DEG.
	var rate_multiplier := remap(
			clampf(_aim_yaw_rate_deg, 0.0, ALS_AIM_YAW_RATE_RANGE_DEG),
			0.0, ALS_AIM_YAW_RATE_RANGE_DEG,
			ALS_AIM_YAW_RATE_MULT_MIN, ALS_AIM_YAW_RATE_MULT_MAX)
	_character.rotation.y = lerp_angle(
			_character.rotation.y, _rotation_target_yaw,
			1.0 - exp(-ROTATION_SPEED * rate_multiplier * delta))


## Ported from UALSCharacterAnimInstance::TurnInPlaceCheck: counts up only
## while the camera has drifted past the threshold AND isn't currently being
## spun fast (a quick camera flick shouldn't commit to a turn), then fires
## once the elapsed time exceeds a delay mapped from the angle. Note the
## mapping direction: GetMappedRangeValueClamped maps the MIN angle (45) to
## MinAngleDelay and 180 to MaxAngleDelay, so a barely-over-threshold angle
## turns almost instantly while a fully-behind one waits up to 0.75s.
## diff_deg is real ALS's AimingValues.AimingAngle.X - the RAW (unsmoothed)
## aim-vs-actor yaw delta, confirmed against UpdateAimingValues; the separate
## SmoothedAimingAngle exists only for aim-offset blending, which this
## prototype has no equivalent of.
func _update_turn_in_place_check(
		delta: float, camera_yaw: float, playback: AnimationNodeStateMachinePlayback) -> void:
	var diff_deg := rad_to_deg(wrapf(camera_yaw - _character.rotation.y, -PI, PI))
	if (absf(diff_deg) <= ALS_TURN_CHECK_MIN_ANGLE_DEG
			or _aim_yaw_rate_deg >= ALS_AIM_YAW_RATE_LIMIT_DEG):
		_turn_check_elapsed = 0.0
		return
	_turn_check_elapsed += delta
	var delay := remap(
			clampf(absf(diff_deg), ALS_TURN_CHECK_MIN_ANGLE_DEG, 180.0),
			ALS_TURN_CHECK_MIN_ANGLE_DEG, 180.0,
			ALS_TURN_MIN_ANGLE_DELAY, ALS_TURN_MAX_ANGLE_DELAY)
	if _turn_check_elapsed > delay:
		_turn_check_elapsed = 0.0
		_maybe_start_turn_in_place(camera_yaw, playback)


## Picks the smallest clip whose magnitude comfortably covers the actual
## angle to turn (a 130 threshold before reaching for one of the four fixed
## clip magnitudes gives the 90 clip room for real angles up to ~130,
## rather than needing exact 90/180 matches).
func _maybe_start_turn_in_place(
		camera_yaw: float, playback: AnimationNodeStateMachinePlayback) -> void:
	var diff := wrapf(camera_yaw - _character.rotation.y, -PI, PI)
	var diff_deg := rad_to_deg(diff)
	if absf(diff_deg) < ALS_TURN_CHECK_MIN_ANGLE_DEG:
		return
	var use_180 := absf(diff_deg) >= TURN_180_THRESHOLD_DEG
	var clip_name := (
			(&"turn_r180" if diff_deg > 0.0 else &"turn_l180") if use_180
			else (&"turn_r90" if diff_deg > 0.0 else &"turn_l90"))
	var turn_info: Array = TURN_ANIMATIONS[clip_name]
	_is_turning = true
	_turn_start_yaw = _character.rotation.y
	_turn_delta_yaw = deg_to_rad(float(turn_info[2]))
	_turn_elapsed = 0.0
	var anim: Animation = _anim_player.get_animation_library(&"clips").get_animation(clip_name)
	_turn_duration = anim.length
	playback.travel(turn_info[1] as StringName)


## Drives _character.rotation.y procedurally over the clip's duration rather
## than reading the retargeted clip's own hip rotation back out - see the
## TURN_ANIMATIONS doc comment for why.
func _update_turn_in_place(delta: float) -> void:
	_turn_elapsed += delta
	var t := clampf(_turn_elapsed / _turn_duration, 0.0, 1.0)
	_character.rotation.y = _turn_start_yaw + _turn_delta_yaw * t
	if t >= 1.0:
		_is_turning = false
		var playback: AnimationNodeStateMachinePlayback = _anim_tree.get(&"parameters/playback")
		playback.travel(&"Grounded")


## Standard CharacterBody3D auto-step recipe: test_move() with the intended
## horizontal motion at the current height; if blocked, retest the same
## motion after lifting the body by STAIR_STEP_HEIGHT. If THAT'S clear, the
## obstruction was a short step (not a real wall) - lift the body and let
## move_and_slide()'s own floor snap settle it back onto the step surface
## right after this call. If still blocked even after lifting, leave it
## alone - too tall to step, correctly still reads as a wall.
## Second attempt's downward-raycast placement was itself broken: the probe
## point was lifted_transform.origin + motion, but `motion` is only THIS
## FRAME'S tiny velocity*delta displacement (millimeters), not remotely far
## enough to have actually reached the step ahead - so the raycast kept
## hitting the flat floor short of the step, snapping the body back down to
## y=0 every frame and leaving move_and_slide() to re-detect the same wall
## on the very next frame. Net effect: completely stuck, confirmed via a
## per-frame trace showing zero net progress in Z OR Y (caught by live user
## report after the "zero flicker" headless check missed it - that check
## only verified on_floor never flickered, not that the character actually
## climbed, and a permanently-stuck-at-the-bottom character trivially also
## never flickers). Back to a plain lift; the animation flicker this was
## trying to avoid is now handled separately, by debouncing the Airborne
## transition instead of trying to make on_floor never blip - see
## _AIRBORNE_DEBOUNCE_FRAMES in _physics_process.
func _apply_stair_step_up(delta: float) -> void:
	if not _body.is_on_floor():
		return
	var horizontal_vel := Vector3(_body.velocity.x, 0.0, _body.velocity.z)
	if horizontal_vel.length() < 0.1:
		return
	var motion := horizontal_vel * delta
	var base_transform := _body.global_transform
	if not _body.test_move(base_transform, motion):
		return
	var lifted_transform := base_transform
	lifted_transform.origin += Vector3.UP * STAIR_STEP_HEIGHT
	if _body.test_move(lifted_transform, motion):
		return
	_body.global_position.y += STAIR_STEP_HEIGHT


func _update_landing(delta: float) -> void:
	_land_elapsed += delta
	if _land_elapsed >= _land_duration:
		_is_landing = false
		var playback: AnimationNodeStateMachinePlayback = _anim_tree.get(&"parameters/playback")
		playback.travel(&"Grounded")


## Detects a mantleable ledge directly ahead: a wall within
## MANTLE_WALL_CHECK_DISTANCE, and a walkable surface on top of it within
## [MANTLE_MIN_HEIGHT, MANTLE_MAX_HEIGHT] above the body. Starts the mantle
## and returns true if found, otherwise returns false (leaving the caller to
## fall back to a normal jump).
## Ported from UALSMathLibrary::GetCapsuleLocationFromBase - converts a
## base/feet location into the capsule CENTRE that _capsule_has_room() expects.
## Its inverse (GetCapsuleBaseLocation) isn't ported because it has no work to
## do here: this prototype's _body origin already sits at the capsule base (the
## CollisionShape3D carries the +half-height offset), which is exactly what
## real ALS calls the capsule base location.
func _capsule_location_from_base(base_location: Vector3, z_offset: float) -> Vector3:
	var result := base_location
	result.y += CAPSULE_HEIGHT * 0.5 + z_offset
	return result


## Ported from UALSMathLibrary::CapsuleHasRoomCheck - real ALS's actual "can
## the character stand here" test. Sweeps a sphere of the capsule's own radius
## along the capsule's cylindrical segment (half_height - radius, above and
## below the centre), which traces out exactly the capsule's own volume. This
## replaces an invented zero-width downward raycast, which could thread
## straight through a gap the 0.7m-wide body could never actually fit through.
## target_location is the capsule CENTRE, not the feet.
func _capsule_has_room(
		target_location: Vector3, height_offset := 0.0, radius_offset := 0.0) -> bool:
	var half_height_without_hemisphere := CAPSULE_HEIGHT * 0.5 - CAPSULE_RADIUS
	var z_target := half_height_without_hemisphere - radius_offset + height_offset
	var sphere := SphereShape3D.new()
	sphere.radius = CAPSULE_RADIUS + radius_offset
	var params := PhysicsShapeQueryParameters3D.new()
	params.shape = sphere
	params.transform = Transform3D(Basis(), target_location + Vector3(0.0, z_target, 0.0))
	params.exclude = [_body.get_rid()]
	var space_state := _body.get_world_3d().direct_space_state

	# Godot's cast_motion is NOT equivalent to Unreal's SweepSingleByChannel:
	# it reports only collisions newly ENTERED during the motion and silently
	# returns [1.0, 1.0] for a shape that already overlaps something at its
	# start position - verified directly, a start position with 4 confirmed
	# intersect_shape overlaps still reported a completely clear sweep. Unreal
	# reports that case as bStartPenetrating, which ALS explicitly checks, so
	# the two halves of ALS's own `!(bBlockingHit || bStartPenetrating)` need
	# two separate Godot queries.
	if not space_state.intersect_shape(params, 1).is_empty():
		return false
	params.motion = Vector3(0.0, -2.0 * z_target, 0.0)
	# [safe_fraction, unsafe_fraction]; safe below 1.0 means the sweep was
	# blocked partway. An empty return is a malformed query - treated
	# conservatively as "no room".
	var result := space_state.cast_motion(params)
	return result.size() >= 1 and result[0] >= 1.0


## Sweeps a sphere from `from` to `to`. ALS's mantle probes are RADIUS traces
## (`ForwardTraceRadius`/`DownwardTraceRadius`, both 30cm on the real
## MantleComponent) rather than the zero-width rays this used before - a thin
## ray slips past a ledge edge that a fat probe catches. Returns {} on no hit,
## else "position"/"normal" keyed the same way intersect_ray's result is, so
## callers read it identically.
func _shape_probe(shape: Shape3D, from: Vector3, to: Vector3) -> Dictionary:
	var params := PhysicsShapeQueryParameters3D.new()
	params.shape = shape
	params.transform = Transform3D(Basis(), from)
	params.motion = to - from
	params.exclude = [_body.get_rid()]
	var space_state := _body.get_world_3d().direct_space_state
	var fractions := space_state.cast_motion(params)
	if fractions.size() < 2 or fractions[0] >= 1.0:
		return {}
	# Rest info is taken at the UNSAFE fraction - the safe one is by definition
	# the last position that is NOT yet touching, so asking there returns
	# nothing. This also reports the real contact point rather than the sphere
	# centre, which would otherwise overstate a ledge's height by the radius.
	params.transform = Transform3D(Basis(), from + (to - from) * fractions[1])
	params.motion = Vector3.ZERO
	var rest := space_state.get_rest_info(params)
	if rest.is_empty():
		return {}
	return {"position": rest["point"], "normal": rest["normal"]}


## `grounded` picks which of ALS's real trace profiles applies - a standing
## jump-press reaches further and higher than a mantle caught mid-jump.
func _try_start_mantle(grounded: bool) -> bool:
	var min_height := MANTLE_GROUNDED_MIN_HEIGHT if grounded else MANTLE_FALLING_MIN_HEIGHT
	var max_height := MANTLE_GROUNDED_MAX_HEIGHT if grounded else MANTLE_FALLING_MAX_HEIGHT
	var reach := MANTLE_GROUNDED_REACH if grounded else MANTLE_FALLING_REACH
	var facing_dir: Vector3 = -_character.transform.basis.z
	var base := _body.global_position + Vector3(0.0, ALS_MANTLE_CAPSULE_Z_OFFSET, 0.0)

	# Step 1 (ALSMantleComponent.cpp): sweep a tall CAPSULE forward, spanning
	# the entire mantleable height band in one trace, rather than the single
	# low probe this used before - which is why real ALS needs no
	# "probe below the lowest ledge" trick to catch ledges of any height.
	# The start is offset BACKWARD by exactly the trace radius, so the probe's
	# leading surface begins at the body and ReachDistance means real reach
	# rather than reach-plus-a-radius.
	var forward_shape := CapsuleShape3D.new()
	forward_shape.radius = MANTLE_TRACE_RADIUS
	forward_shape.height = 2.0 * (MANTLE_TRACE_HALF_HEIGHT_PAD + (max_height - min_height) * 0.5)
	var trace_start := base - facing_dir * MANTLE_TRACE_RADIUS
	trace_start.y += (max_height + min_height) * 0.5
	var wall_hit := _shape_probe(forward_shape, trace_start, trace_start + facing_dir * reach)
	if wall_hit.is_empty():
		return false
	# ALS rejects a hit it could simply walk up (its IsWalkable check) - a
	# mantle needs a wall, not a ramp.
	if (wall_hit["normal"] as Vector3).y > cos(_body.floor_max_angle):
		return false

	# Step 2: sweep a sphere straight down from above the ledge to foot level,
	# starting from the wall impact point pushed 15cm INTO the surface along
	# its own normal so the probe lands on the ledge top rather than skimming
	# its outer edge.
	var down_shape := SphereShape3D.new()
	down_shape.radius = MANTLE_TRACE_RADIUS
	var down_end: Vector3 = wall_hit["position"]
	down_end.y = base.y
	down_end += (wall_hit["normal"] as Vector3) * -MANTLE_DOWN_TRACE_NORMAL_OFFSET
	var down_start := down_end
	down_start.y += max_height + MANTLE_TRACE_RADIUS + MANTLE_TRACE_HALF_HEIGHT_PAD
	var down_hit := _shape_probe(down_shape, down_start, down_end)
	if down_hit.is_empty():
		return false

	var ledge_top: Vector3 = down_hit["position"]
	var ledge_height := ledge_top.y - _body.global_position.y
	if ledge_height < min_height or ledge_height > max_height:
		return false

	# Real ALS's landing target IS the downward-trace hit point directly
	# (lifted to capsule-centre height) - `TargetTransform`'s position is
	# `CapsuleLocationFBase`, with NO further forward travel added past the
	# trace's own 15cm push-in. This prototype previously added a SECOND,
	# invented 0.5m forward offset on top of that real one - found by
	# actually reading ALSMantleComponent.cpp's Start() function past step 2,
	# prompted by a live user report that the whole body was still visibly
	# clipping through the ledge even after the curve-driven motion was
	# ported. That redundant 0.5m dragged the character nearly 4x deeper
	# across the ledge surface (through more of its volume) than real ALS
	# ever does, which is very plausibly what was actually causing the
	# clipping - not the motion curve, which was already faithfully ported.
	var landing_spot := ledge_top

	# Room check: does the character's whole body actually fit at the landing
	# spot, so a mantle can't pull it up into a low ceiling (ALSMantleComponent.cpp
	# step 3: convert the downward-trace hit into a capsule location with a
	# 2cm lift, then CapsuleHasRoomCheck it).
	if not _capsule_has_room(
			_capsule_location_from_base(landing_spot, ALS_MANTLE_CAPSULE_Z_OFFSET)):
		return false

	_is_mantling = true
	if _mantle_hand_ik_modifier != null:
		_mantle_hand_ik_modifier.weight = 0.0
	_mantle_start_pos = _body.global_position
	_mantle_target_pos = landing_spot
	_mantle_target_pos.y = ledge_top.y
	_body.velocity = Vector3.ZERO
	_mantle_elapsed = 0.0
	# Real ALS's Low/High mantle TYPE split, at the real 125cm threshold
	# (ALSMantleComponent.cpp) - a High ledge plays a visibly different climb.
	var is_high := ledge_height > ALS_MANTLE_HIGH_THRESHOLD
	var clip_name := &"mantle_high" if is_high else &"mantle_low"
	var anim: Animation = _anim_player.get_animation_library(&"clips").get_animation(clip_name)
	var start_offset := ALS_MANTLE_HIGH_START_OFFSET if is_high else ALS_MANTLE_LOW_START_OFFSET
	# Real MantleAnimatedStartOffset: a point behind (start_offset.x) and
	# below (start_offset.y) the ledge, matching where the clip's own root
	# motion actually begins - the early part of the climb tracks toward
	# THIS, not straight from wherever the player happened to approach from.
	_mantle_animated_start_pos = (
			ledge_top - facing_dir * start_offset.x - Vector3.UP * start_offset.y)
	_mantle_active_curves = _mantle_high_curves if is_high else _mantle_low_curves
	var height_range := ALS_MANTLE_HIGH_HEIGHT_RANGE if is_high else ALS_MANTLE_LOW_HEIGHT_RANGE
	var start_pos_range := (
			ALS_MANTLE_HIGH_START_POSITION_RANGE if is_high else ALS_MANTLE_LOW_START_POSITION_RANGE)
	_mantle_starting_position = remap(
			clampf(ledge_height, height_range.x, height_range.y),
			height_range.x, height_range.y, start_pos_range.x, start_pos_range.y)
	_mantle_play_rate = ALS_MANTLE_HIGH_PLAY_RATE if is_high else ALS_MANTLE_LOW_PLAY_RATE
	_anim_tree.set(
			&"parameters/%s/PlayRate/scale" % ("MantleHigh" if is_high else "MantleLow"),
			_mantle_play_rate)
	# Real ALS: MantleTimeline->SetTimelineLength(MaxTime - StartingPosition),
	# then plays it at PlayRate - so the real (unscaled) wall-clock duration
	# is that timeline length divided by PlayRate.
	var max_time: float = _mantle_active_curves["max_time"]
	_mantle_duration = minf(
			anim.length / _mantle_play_rate, (max_time - _mantle_starting_position) / _mantle_play_rate)
	# Face the wall for the duration of the mantle (facing_dir is already the
	# direction cast toward it) rather than leaving whatever yaw the
	# character had on approach, which could be visibly off during a
	# diagonal/running mantle.
	_mantle_start_yaw = _character.rotation.y
	_mantle_target_yaw = atan2(-facing_dir.x, -facing_dir.z)
	var playback: AnimationNodeStateMachinePlayback = _anim_tree.get(&"parameters/playback")
	playback.travel(&"MantleHigh" if is_high else &"MantleLow")
	# KNOWN GAP, not silently fixed: real ALS explicitly starts the MONTAGE
	# itself at StartingPosition too (`Montage_Play(..., StartingPosition,
	# ...)`), not just the position-correction curve - a short ledge skips
	# ahead in BOTH together, since they were authored as a matched pair.
	# Tried `_anim_tree.advance(_mantle_starting_position)` right after
	# travel() to fast-forward the freshly-entered state by that offset in
	# one shot - measured directly against sampling the raw Animation
	# resource at the same time, and it does NOT work: the skeleton's pose
	# right after still matches t=0, not the sought time (most likely
	# because travel()'s own crossfade consumes that first advance() call
	# rather than the new state's own internal clock). Left un-seeked rather
	# than ship something that LOOKS like a fix but measurably isn't - only
	# affects the High mantle type (StartingPosition ~0.16s of a 2.2s clip
	# at the test ledge's height; the Low type's own real StartingPosition
	# is 0 at this test ledge's exact height, so this isn't what's causing
	# hand-tracking to look wrong on that one).
	return true


## Ports UALSMantleComponent::MantleUpdate's actual position-correction math
## (steps 2-4 of the real function), not an invented arc. Real ALS blends via
## FTransform algebra in the ledge's own local frame (TransformAdd/Sub); here
## it's done directly in world Cartesian space, which is equivalent for a
## target whose only real rotation component is yaw (matches how this
## prototype already handles mantle facing separately from position).
func _update_mantle(delta: float) -> void:
	_mantle_elapsed += delta
	# Real ALS samples the curve at StartingPosition + GetPlaybackPosition(),
	# where the timeline's own playback position advances at PlayRate x real
	# time - StartingPosition lets a short ledge skip ahead into the curve
	# instead of always playing it from the start, and PlayRate speeds the
	# whole thing up for the 2m asset. Not a normalized 0-1 fraction, which is
	# why Mantle_2m's curve has a real domain out to 2.1, not [0,1].
	var max_time: float = _mantle_active_curves["max_time"]
	var ct := minf(
			_mantle_starting_position + _mantle_elapsed * _mantle_play_rate, max_time)
	var pos_alpha: float = (_mantle_active_curves["pos_alpha"] as Curve).sample(ct)
	var xy_alpha: float = (_mantle_active_curves["xy_alpha"] as Curve).sample(ct)
	var z_alpha: float = (_mantle_active_curves["z_alpha"] as Curve).sample(ct)

	# Step 2: independently blend horizontal (XZ ground-plane) position from
	# the real approach point toward the animation-matched reference using
	# XYCorrectionAlpha, and vertical (Y) using ZCorrectionAlpha - these run
	# on their own real timing (XY arrives faster than Z for Mantle_1m),
	# which is the actual mechanism giving the climb its shape instead of a
	# single uniform lerp.
	var hz := Vector2(_mantle_start_pos.x, _mantle_start_pos.z).lerp(
			Vector2(_mantle_animated_start_pos.x, _mantle_animated_start_pos.z), xy_alpha)
	var vt := lerpf(_mantle_start_pos.y, _mantle_animated_start_pos.y, z_alpha)
	var offset_pos := Vector3(hz.x, vt, hz.y)

	# Step 3: blend the whole offset-based position toward the true final
	# landing spot as PositionAlpha rises - at pos_alpha=1 you're exactly on
	# the ledge, no offset remaining.
	var result := offset_pos.lerp(_mantle_target_pos, pos_alpha)

	# Real MantleTimelineCurve's BlendIn: eases from the player's exact
	# approach pose into the curve-corrected path over the first 0.2s, so a
	# mantle triggered from an off-axis approach doesn't pop.
	var blend_in := clampf(_mantle_elapsed / ALS_MANTLE_BLEND_IN_TIME, 0.0, 1.0)
	_body.global_position = _mantle_start_pos.lerp(result, blend_in)

	_character.rotation.y = lerp_angle(_mantle_start_yaw, _mantle_target_yaw,
			smoothstep(0.0, 1.0, minf(_mantle_elapsed / _mantle_duration * 3.0, 1.0)))

	# Prototype-only hand IK (not a real ALS mechanism - see the modifier's
	# own doc comment for why one is needed here at all): pins both hands to
	# the real ledge grip point while the body is still being corrected
	# toward it (xy/z alpha rising), fading out as pos_alpha commits the body
	# fully onto the ledge - by then the animation should be pushing up to
	# stand, and real climbing hands release the edge at that point too.
	if _mantle_hand_ik_modifier != null:
		_mantle_hand_ik_modifier.target_position = _mantle_target_pos
		_mantle_hand_ik_modifier.weight = maxf(xy_alpha, z_alpha) * (1.0 - pos_alpha) * blend_in

	if _mantle_elapsed >= _mantle_duration:
		_is_mantling = false
		_body.velocity = Vector3.ZERO
		if _mantle_hand_ik_modifier != null:
			_mantle_hand_ik_modifier.weight = 0.0
		# is_on_floor() only reflects the last move_and_slide() call - without
		# this, the frame right after a teleport-style position set would
		# read on_floor()=false (stale) and briefly re-trigger gravity/falling.
		_body.move_and_slide()
		var playback: AnimationNodeStateMachinePlayback = _anim_tree.get(&"parameters/playback")
		playback.travel(&"Grounded")


## Rewrites every track's NodePath to point at new_skeleton_path, keeping each
## track's own bone-name subname intact - same fix als_retarget_preview.gd uses.
func _retarget_track_paths(anim: Animation, new_skeleton_path: NodePath) -> void:
	for t in anim.get_track_count():
		var old_path := anim.track_get_path(t)
		if old_path.get_subname_count() == 0:
			continue
		var bone_name := old_path.get_subname(0)
		anim.track_set_path(t, NodePath(String(new_skeleton_path) + ":" + String(bone_name)))
