class_name DGPlayerVisual
extends Node3D
## Animation layer for the DG_GAME_SAMPLE locomotion lab, driven by the game's own rig.
##
## Unlike `dg_game_sample_locomotion_visual.gd` (Y Bot + retargeted ALS clips), this loads the
## character baked straight out of DG_GAME_SAMPLE: `player_locomotion.glb` carries the player's four
## body parts, his hands, the 547-bone PSA skeleton and 19 clips decoded from the game
## (see the RE workspace's notes\animations.md). Clip names are the bake names:
## idle, walk_F/B/L/R/FL/FR/BL, run_F/B, sprint_F, crouch_walk_F/B/L/R,
## turn_L_90/R_90, turn_L_180/R_180.
##
## The GLB ships inside the project (assets/models/dg_game_sample/) and is imported by
## Godot like any other scene, so nothing here depends on an external path.
##
## State mapping mirrors the recovered UE4 machine:
##   Idle / Move -> "Locomotion" 2D blend space over local velocity (walk ring, run, sprint)
##   Crouch      -> "Crouch" 2D blend space over the local velocity direction (F/B/L/R)
##   Turn        -> 90 or 180 degree clip by turn magnitude, time-scaled to the procedural turn
##
## The turn clips carry the whole turn as skeleton yaw (measured: the pelvis ends at
## +-90 / +-180 degrees, RE workspace reports/turn-yaw.txt). The body rotates the capsule by
## the same angle, so the model is counter-rotated while a turn plays; otherwise the character
## would visually spin twice.

const MODEL_PATH := "res://assets/models/dg_game_sample/player_locomotion.glb"

## Nominal ground speed each clip was authored for, from the recovered tuning.
const SPEED_WALK := 3.0
const SPEED_RUN := 3.75
const SPEED_SPRINT := 7.5

const STATE_LOCOMOTION := &"Locomotion"
const STATE_CROUCH := &"Crouch"
const STATE_TURN_L90 := &"TurnL90"
const STATE_TURN_R90 := &"TurnR90"
const STATE_TURN_L180 := &"TurnL180"
const STATE_TURN_R180 := &"TurnR180"

## A turn at or above this magnitude uses the 180 degree clip.
const TURN_180_THRESHOLD_DEG := 135.0

## Blend-space point -> GLB animation name. Points whose clip is missing are skipped.
const LOCOMOTION_POINTS := [
	[&"idle", Vector2(0.0, 0.0)],
	[&"walk_F", Vector2(0.0, SPEED_WALK)],
	[&"walk_B", Vector2(0.0, -SPEED_WALK)],
	[&"walk_L", Vector2(-SPEED_WALK, 0.0)],
	[&"walk_R", Vector2(SPEED_WALK, 0.0)],
	[&"walk_FL", Vector2(-0.707, 0.707) * SPEED_WALK],
	[&"walk_FR", Vector2(0.707, 0.707) * SPEED_WALK],
	[&"walk_BL", Vector2(-0.707, -0.707) * SPEED_WALK],
	[&"run_F", Vector2(0.0, SPEED_RUN)],
	[&"run_B", Vector2(0.0, -SPEED_RUN)],
	[&"sprint_F", Vector2(0.0, SPEED_SPRINT)],
]

## Crouch strafes, placed on the unit circle: the blend position is the normalised local
## velocity direction, so a diagonal press blends two of them.
const CROUCH_POINTS := [
	[&"crouch_walk_F", Vector2(0.0, 1.0)],
	[&"crouch_walk_B", Vector2(0.0, -1.0)],
	[&"crouch_walk_L", Vector2(-1.0, 0.0)],
	[&"crouch_walk_R", Vector2(1.0, 0.0)],
]

const LOOPING := [&"idle", &"walk_F", &"walk_B", &"walk_L", &"walk_R", &"walk_FL",
		&"walk_FR", &"walk_BL", &"run_F", &"run_B", &"sprint_F", &"crouch_walk_F",
		&"crouch_walk_B", &"crouch_walk_L", &"crouch_walk_R"]

var body: DGGameSampleLocomotionBody

var model: Node3D
var skeleton: Skeleton3D
var player: AnimationPlayer
var tree: AnimationTree

var _playback: AnimationNodeStateMachinePlayback
var _turn_state := &""
var _available: Array[StringName] = []
## True while a turn clip is playing; the model is counter-rotated meanwhile.
var _turning := false
var _turn_base_yaw := 0.0


func _ready() -> void:
	_build_character()
	_build_animation_tree()


## Called by the lab once per physics frame.
func sync(_delta: float) -> void:
	if body == null or _playback == null:
		return
	var state := body.get_state_name()
	if state == &"Turn":
		_sync_turn()
		return
	if _turning:
		_turning = false
		model.rotation.y = PI
	if body.wants_crouch:
		_travel(STATE_CROUCH)
		tree.set(&"parameters/Crouch/blend_position", _crouch_direction())
		player.speed_scale = _speed_scale(absf(body.velocity.length()), SPEED_WALK)
		return
	_travel(STATE_LOCOMOTION)
	tree.set(&"parameters/Locomotion/blend_position", _local_velocity())
	player.speed_scale = _speed_scale(absf(body.velocity.length()), _ring_speed())


## Name of the state the animation state machine is currently playing.
func playback_name() -> StringName:
	if _playback == null:
		return &""
	return _playback.get_current_node()


## Current Locomotion blend-space position (right, forward) in m/s.
func blend_position() -> Vector2:
	if tree == null:
		return Vector2.ZERO
	return tree.get(&"parameters/Locomotion/blend_position")


## Names of the GLB clips that were actually found.
func available_clips() -> Array[StringName]:
	return _available


# ------------------------------------------------------------------ build --

func _build_character() -> void:
	var packed := load(MODEL_PATH) as PackedScene
	if packed == null:
		push_error("player view: could not load %s" % MODEL_PATH)
		return
	model = packed.instantiate()
	model.name = &"Character"
	# The exported mesh faces +Z, while the body (like everything in Godot) treats -Z as
	# forward. Measured, not assumed: the lab camera sits behind the body at dot(to_camera,
	# forward) = -0.88 and the character still faced it. Without this yaw the model turns the
	# opposite way to the movement direction (move right -> mesh looks left).
	model.rotation.y = PI
	add_child(model)

	skeleton = model.find_child("Skeleton3D", true, false) as Skeleton3D
	player = model.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if skeleton == null or player == null:
		push_error("player view: model has no Skeleton3D/AnimationPlayer")
		return
	player.root_node = player.get_path_to(model)
	for anim_name in player.get_animation_list():
		_available.append(anim_name)
		var anim := player.get_animation(anim_name)
		anim.loop_mode = Animation.LOOP_LINEAR if anim_name in LOOPING else Animation.LOOP_NONE


func _build_animation_tree() -> void:
	if player == null:
		return
	var machine := AnimationNodeStateMachine.new()

	var points: Array = []
	for entry in LOCOMOTION_POINTS:
		if player.has_animation(entry[0]):
			points.append([entry[0], entry[1]])
	var locomotion := AnimationNodeBlendSpace2D.new()
	locomotion.min_space = Vector2(-SPEED_SPRINT, -SPEED_SPRINT)
	locomotion.max_space = Vector2(SPEED_SPRINT, SPEED_SPRINT)
	for entry in points:
		var node := AnimationNodeAnimation.new()
		node.animation = entry[0]
		locomotion.add_blend_point(node, entry[1], -1, String(entry[0]))

	var crouch := AnimationNodeBlendSpace2D.new()
	for entry in CROUCH_POINTS:
		if player.has_animation(entry[0]):
			var crouch_node := AnimationNodeAnimation.new()
			crouch_node.animation = entry[0]
			crouch.add_blend_point(crouch_node, entry[1], -1, String(entry[0]))
	crouch.min_space = Vector2(-1.0, -1.0)
	crouch.max_space = Vector2(1.0, 1.0)

	machine.add_node(STATE_LOCOMOTION, locomotion)
	machine.add_node(STATE_CROUCH, crouch)
	for entry in [[STATE_TURN_L90, &"turn_L_90"], [STATE_TURN_R90, &"turn_R_90"],
			[STATE_TURN_L180, &"turn_L_180"], [STATE_TURN_R180, &"turn_R_180"]]:
		if player.has_animation(entry[1]):
			machine.add_node(entry[0], _clip_node(entry[1]))
	_connect_all(machine)

	tree = AnimationTree.new()
	tree.name = &"AnimationTree"
	add_child(tree)
	tree.anim_player = tree.get_path_to(player)
	tree.tree_root = machine
	tree.active = true
	_playback = tree.get(&"parameters/playback")


func _clip_node(animation: StringName) -> AnimationNodeAnimation:
	var node := AnimationNodeAnimation.new()
	node.animation = animation
	return node


func _connect_all(machine: AnimationNodeStateMachine) -> void:
	var names: Array[StringName] = []
	for entry in machine.get_node_list():
		if entry == &"Start" or entry == &"End":
			continue
		names.append(entry)
	for from_name in names:
		for to_name in names:
			if from_name == to_name:
				continue
			var transition := AnimationNodeStateMachineTransition.new()
			transition.xfade_time = 0.15
			machine.add_transition(from_name, to_name, transition)


# ------------------------------------------------------------------ frame --

func _travel(state: StringName) -> void:
	if _playback == null or not machine_has(state):
		return
	if _turn_state != &"":
		_turn_state = &""
		player.speed_scale = 1.0
	if _playback.get_current_node() == state:
		return
	_playback.travel(state)


func machine_has(state: StringName) -> bool:
	var machine := tree.tree_root as AnimationNodeStateMachine
	return machine != null and machine.has_node(state)


func _sync_turn() -> void:
	var sm := body.state_machine
	var angle := sm.turn_angle_deg
	var clip_90 := &"turn_R_90" if angle <= 0.0 else &"turn_L_90"
	var clip_180 := &"turn_R_180" if angle <= 0.0 else &"turn_L_180"
	var wide := absf(angle) >= TURN_180_THRESHOLD_DEG
	var state := (STATE_TURN_R180 if angle <= 0.0 else STATE_TURN_L180) if wide \
			else (STATE_TURN_R90 if angle <= 0.0 else STATE_TURN_L90)
	if not machine_has(state):
		# The 180 clip is optional; fall back to the 90 clip rather than not turning at all.
		wide = false
		state = STATE_TURN_R90 if angle <= 0.0 else STATE_TURN_L90
		clip_180 = clip_90
	if not machine_has(state):
		return
	var clip_name: StringName = clip_180 if wide else clip_90
	var duration := maxf(0.05, sm.turn_duration)
	player.speed_scale = player.get_animation(clip_name).length / duration

	# The clip yaws the skeleton by the turn; the body yaws the capsule by the same angle.
	# Counter-rotating the model by the body's applied turn leaves exactly the clip's yaw.
	if not _turning:
		_turning = true
		_turn_base_yaw = body.facing_yaw
	model.rotation.y = PI - wrapf(body.facing_yaw - _turn_base_yaw, -PI, PI)

	if state != _turn_state:
		_turn_state = state
		_playback.travel(state)


func _ring_speed() -> float:
	var planar := absf(body.velocity.length())
	if planar >= (SPEED_RUN + SPEED_SPRINT) * 0.5:
		return SPEED_SPRINT
	if planar >= SPEED_WALK * 1.15:
		return SPEED_RUN
	return SPEED_WALK


## Keep the feet planted by scaling playback to actual speed, gently clamped so a blend
## between two clips never looks like it is skating or running in place.
func _speed_scale(planar: float, nominal: float) -> float:
	if nominal <= 0.0:
		return 1.0
	return clampf(planar / nominal, 0.6, 1.6)


func _local_velocity() -> Vector2:
	if body == null:
		return Vector2.ZERO
	var local := body.global_transform.basis.inverse() * body.velocity
	return Vector2(local.x, -local.z)


## Crouch blend position: the movement direction on the unit circle. Standing still has no
## direction, so it leans forward rather than averaging all four clips into a squat shuffle.
func _crouch_direction() -> Vector2:
	var local := _local_velocity()
	if local.length() < 0.15:
		return Vector2(0.0, 1.0)
	return local.normalized()
