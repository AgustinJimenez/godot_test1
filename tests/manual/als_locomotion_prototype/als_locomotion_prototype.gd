extends Node3D
## Phase 1 scaffold for AGENT_TASKS/016 - an ALS-style locomotion prototype
## built from scratch, independent of actors/player/*. Character: Y Bot
## (assets/models/mixamo_characters/Y Bot.fbx), chosen after comparing X Bot
## and Y Bot in tests/manual/animation/als_retarget_preview.tscn - X Bot
## looks visibly feminine/androgynous, a poor match for the muscular ALS
## reference mesh. Previously used the default player rig
## (W1_Stand_Aim_Idle_IPC.fbx, what's really on screen in
## foot_ik_preview.tscn) - see git history for that variant.
## Animations are retargeted onto this rig via tools/retarget_cli.gd's
## target_model= mode (no catalog manifest needed). Every clip here must come
## from the same ALSHost export pipeline - never this project's own
## pistol_starter/Mixamo animations.
## AnimationTree root is a 2-state AnimationNodeStateMachine (Grounded/
## Airborne), each holding its own 1D blendspace - not a single flat
## blendspace - since travel() needs a named state to switch to on the
## is_on_floor() edge, and the two blendspaces are keyed by unrelated axes
## (horizontal speed vs. vertical velocity sign).

const CHARACTER_MODEL := "res://assets/models/mixamo_characters/Y Bot.fbx"
## ALS has no baked idle cycle - the pose export is a near-single-frame hold
## (ALS_N_Pose), not a looping clip. Real ALS idles by holding this pose plus
## an additive sway (ALS_N_SecondaryMotion), not modeled here yet.
const IDLE_ANIMATION := "res://assets/models/als_retarget_test/ALS_N_Pose_on_ybot.res"
const WALK_ANIMATION := "res://assets/models/als_retarget_test/ALS_N_Walk_F_on_ybot.res"
const RUN_ANIMATION := "res://assets/models/als_retarget_test/ALS_N_Run_F_on_ybot.res"
const JUMP_ANIMATION := "res://assets/models/als_retarget_test/ALS_N_JumpLoop_on_ybot.res"
const FALL_ANIMATION := "res://assets/models/als_retarget_test/ALS_N_FallLoop_on_ybot.res"

const WALK_SPEED := 3.0
const SPRINT_SPEED := 6.0
const ACCELERATION := 12.0
const DECELERATION := 16.0
const ROTATION_SPEED := 10.0
const JUMP_VELOCITY := 4.5
const GRAVITY := 18.0

var _body: CharacterBody3D
var _character: Node3D
var _anim_player: AnimationPlayer
var _anim_tree: AnimationTree
var _camera_pivot: Node3D
var _was_on_floor := true
var _anim_started := false


func _ready() -> void:
	_build_terrain()
	_build_player()


func _build_player() -> void:
	_body = CharacterBody3D.new()
	_body.name = &"PrototypeBody"
	_body.position = Vector3(0.0, 1.0, 8.0)

	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.35
	capsule.height = 1.8
	shape.shape = capsule
	shape.position = Vector3(0.0, 0.9, 0.0)
	_body.add_child(shape)

	_character = (load(CHARACTER_MODEL) as PackedScene).instantiate()
	_body.add_child(_character)
	var skeleton: Skeleton3D = _character.find_child("Skeleton3D", true, false)
	_anim_player = _character.find_child("AnimationPlayer", true, false)
	if _anim_player == null:
		_anim_player = AnimationPlayer.new()
		_anim_player.name = &"AnimationPlayer"
		_character.add_child(_anim_player)
	# Track paths resolve relative to root_node (the character's own parent
	# here), not to the AnimationPlayer itself - see 015/016 retarget notes.
	_anim_player.root_node = _anim_player.get_path_to(skeleton.get_parent())
	var anim_root: Node = _anim_player.get_node(_anim_player.root_node)
	var skeleton_path := anim_root.get_path_to(skeleton)

	var lib := AnimationLibrary.new()
	for entry in [
			[&"idle", IDLE_ANIMATION], [&"walk", WALK_ANIMATION], [&"run", RUN_ANIMATION],
			[&"jump", JUMP_ANIMATION], [&"fall", FALL_ANIMATION]]:
		var anim: Animation = (load(entry[1]) as Animation).duplicate()
		anim.loop_mode = Animation.LOOP_LINEAR
		_retarget_track_paths(anim, skeleton_path)
		lib.add_animation(entry[0], anim)
	_anim_player.add_animation_library(&"clips", lib)

	# Grounded: 1D speed blendspace (ALS baseline idea) - idle at 0, walk at
	# WALK_SPEED, run at SPRINT_SPEED, blended by current horizontal speed.
	var ground_blend := AnimationNodeBlendSpace1D.new()
	ground_blend.min_space = 0.0
	ground_blend.max_space = SPRINT_SPEED
	var idle_node := AnimationNodeAnimation.new()
	idle_node.animation = &"clips/idle"
	var walk_node := AnimationNodeAnimation.new()
	walk_node.animation = &"clips/walk"
	var run_node := AnimationNodeAnimation.new()
	run_node.animation = &"clips/run"
	ground_blend.add_blend_point(idle_node, 0.0)
	ground_blend.add_blend_point(walk_node, WALK_SPEED)
	ground_blend.add_blend_point(run_node, SPRINT_SPEED)

	# Airborne: 1D blendspace keyed by vertical velocity - fall loop while
	# descending, jump loop while still rising.
	var air_blend := AnimationNodeBlendSpace1D.new()
	air_blend.min_space = -1.0
	air_blend.max_space = 1.0
	var fall_node := AnimationNodeAnimation.new()
	fall_node.animation = &"clips/fall"
	var jump_node := AnimationNodeAnimation.new()
	jump_node.animation = &"clips/jump"
	air_blend.add_blend_point(fall_node, -1.0)
	air_blend.add_blend_point(jump_node, 1.0)

	# Grounded <-> Airborne, switched explicitly via playback.travel() on
	# is_on_floor() transitions (see _physics_process) rather than an
	# advance_condition, since the trigger is a one-frame edge, not a
	# continuously-true condition.
	var state_machine := AnimationNodeStateMachine.new()
	state_machine.add_node(&"Grounded", ground_blend)
	state_machine.add_node(&"Airborne", air_blend)
	var to_air := AnimationNodeStateMachineTransition.new()
	to_air.xfade_time = 0.15
	to_air.advance_mode = AnimationNodeStateMachineTransition.ADVANCE_MODE_DISABLED
	state_machine.add_transition(&"Grounded", &"Airborne", to_air)
	var to_ground := AnimationNodeStateMachineTransition.new()
	to_ground.xfade_time = 0.2
	to_ground.advance_mode = AnimationNodeStateMachineTransition.ADVANCE_MODE_DISABLED
	state_machine.add_transition(&"Airborne", &"Grounded", to_ground)

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
	var camera := Camera3D.new()
	camera.name = &"Camera3D"
	camera.position = Vector3(0.0, 0.8, 4.0)
	camera.look_at_from_position(camera.position, Vector3(0.0, 0.9, 0.0), Vector3.UP)
	camera.current = true
	_camera_pivot.add_child(camera)

	add_child(_body)


## Rewrites every track's NodePath to point at new_skeleton_path, keeping each
## track's own bone-name subname intact - same fix als_retarget_preview.gd uses.
func _retarget_track_paths(anim: Animation, new_skeleton_path: NodePath) -> void:
	for t in anim.get_track_count():
		var old_path := anim.track_get_path(t)
		if old_path.get_subname_count() == 0:
			continue
		var bone_name := old_path.get_subname(0)
		anim.track_set_path(t, NodePath(String(new_skeleton_path) + ":" + String(bone_name)))


func _physics_process(delta: float) -> void:
	if _body == null:
		return
	var input_dir := Vector2(
			Input.get_action_strength(&"move_right") - Input.get_action_strength(&"move_left"),
			Input.get_action_strength(&"move_back") - Input.get_action_strength(&"move_forward"))
	input_dir = input_dir.limit_length(1.0)

	if not _body.is_on_floor():
		_body.velocity.y -= GRAVITY * delta
	elif Input.is_action_just_pressed(&"jump"):
		_body.velocity.y = JUMP_VELOCITY

	var target_speed := SPRINT_SPEED if Input.is_action_pressed(&"sprint") else WALK_SPEED
	var move_dir := Vector3(input_dir.x, 0.0, input_dir.y)
	var target_velocity := move_dir * target_speed
	var horizontal := Vector3(_body.velocity.x, 0.0, _body.velocity.z)
	var accel := ACCELERATION if move_dir.length() > 0.01 else DECELERATION
	horizontal = horizontal.move_toward(target_velocity, accel * delta)
	_body.velocity.x = horizontal.x
	_body.velocity.z = horizontal.z

	# Velocity Direction rotation mode (ALS baseline): body faces move direction.
	if horizontal.length() > 0.1:
		var target_yaw := atan2(horizontal.x, horizontal.z)
		_character.rotation.y = lerp_angle(_character.rotation.y, target_yaw, ROTATION_SPEED * delta)

	_body.move_and_slide()

	var on_floor := _body.is_on_floor()
	var playback: AnimationNodeStateMachinePlayback = _anim_tree.get(&"parameters/playback")
	if not _anim_started:
		# The "parameters/playback" resource isn't live until the tree has
		# processed at least one frame - calling start() from _build_player
		# (before any frame ran) silently had no effect, confirmed via a
		# headless smoke test. Whatever the state machine's real default
		# initial state is otherwise (observed as Airborne, not the first- or
		# last-added node), this forces it explicitly on the first real frame.
		playback.start(&"Grounded" if on_floor else &"Airborne")
		_anim_started = true
	elif on_floor != _was_on_floor:
		playback.travel(&"Grounded" if on_floor else &"Airborne")
	_was_on_floor = on_floor
	_anim_tree.set(&"parameters/Grounded/blend_position", horizontal.length())
	_anim_tree.set(&"parameters/Airborne/blend_position", signf(_body.velocity.y))


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
	const STEP_DEPTH := 0.3
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
