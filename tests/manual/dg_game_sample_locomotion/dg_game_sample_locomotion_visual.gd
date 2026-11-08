class_name DGGameSampleLocomotionVisual
extends Node3D
## Animation layer for the DG_GAME_SAMPLE locomotion lab.
##
## Uses the project's already-retargeted clips (assets/models/als_retarget_test/
## *_on_ybot.res, built by tools/retarget_cli.gd) on the Y Bot rig. Nothing is
## imported from Blender: the FBX are already imported in this project.
##
## State mapping (the visual side of the recovered UE4 machine):
##   Idle / Move  -> "Locomotion" 2D blend space keyed by local velocity
##                    (idle at the origin, walk ring, run ring)
##   Crouch       -> "Crouch" 2D blend space (4-direction ALS crouch set)
##   Air          -> "Jump" while rising, "Fall" while dropping
##   Turn         -> TurnIP_L/R90 or L/R180, time-scaled to the procedural turn
##
## The turn clips are verified in-place (hips quaternion is identity at both
## ends), so they layer on top of the capsule yaw the state machine applies.

const MODEL_PATH := "res://assets/models/mixamo_characters/Y Bot.fbx"
const CLIP_DIR := "res://assets/models/als_retarget_test/"

const BLEND_WALK_SPEED := 3.0
const BLEND_RUN_SPEED := 3.75
const BLEND_CROUCH_SPEED := 1.35

## clip name -> file stem in CLIP_DIR
const CLIPS := {
	&"idle": "ALS_N_Pose_on_ybot",
	&"walk_f": "ALS_N_Walk_F_on_ybot",
	&"walk_b": "ALS_N_Walk_B_on_ybot",
	&"walk_lf": "ALS_N_Walk_LF_on_ybot",
	&"walk_rf": "ALS_N_Walk_RF_on_ybot",
	&"walk_lb": "ALS_N_Walk_LB_on_ybot",
	&"walk_rb": "ALS_N_Walk_RB_on_ybot",
	&"run_f": "ALS_N_Run_F_on_ybot",
	&"run_b": "ALS_N_Run_B_on_ybot",
	&"run_lf": "ALS_N_Run_LF_on_ybot",
	&"run_rf": "ALS_N_Run_RF_on_ybot",
	&"run_lb": "ALS_N_Run_LB_on_ybot",
	&"run_rb": "ALS_N_Run_RB_on_ybot",
	&"crouch_idle": "ALS_CLF_Pose_on_ybot",
	&"crouch_f": "ALS_CLF_Walk_F_on_ybot",
	&"crouch_b": "ALS_CLF_Walk_B_on_ybot",
	&"crouch_l": "ALS_CLF_Walk_L_on_ybot",
	&"crouch_r": "ALS_CLF_Walk_R_on_ybot",
	&"jump": "ALS_N_JumpLoop_on_ybot",
	&"fall": "ALS_N_FallLoop_on_ybot",
	&"turn_l90": "ALS_N_TurnIP_L90_on_ybot",
	&"turn_r90": "ALS_N_TurnIP_R90_on_ybot",
	&"turn_l180": "ALS_N_TurnIP_L180_on_ybot",
	&"turn_r180": "ALS_N_TurnIP_R180_on_ybot",
}

const LOOPING := [&"idle", &"walk_f", &"walk_b", &"walk_lf", &"walk_rf", &"walk_lb",
		&"walk_rb", &"run_f", &"run_b", &"run_lf", &"run_rf", &"run_lb", &"run_rb",
		&"crouch_idle", &"crouch_f", &"crouch_b", &"crouch_l", &"crouch_r", &"jump", &"fall"]

const STATE_LOCOMOTION := &"Locomotion"
const STATE_CROUCH := &"Crouch"
const STATE_JUMP := &"Jump"
const STATE_FALL := &"Fall"
const STATE_TURN_L90 := &"TurnL90"
const STATE_TURN_R90 := &"TurnR90"
const STATE_TURN_L180 := &"TurnL180"
const STATE_TURN_R180 := &"TurnR180"

## Body whose state drives the animation. Set by the lab before _ready runs.
var body: DGGameSampleLocomotionBody

var player: AnimationPlayer
var tree: AnimationTree
var skeleton: Skeleton3D

var _playback: AnimationNodeStateMachinePlayback
var _turn_state := &""
var _turn_speed_scale := 1.0


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
	if state == &"Air":
		_travel(STATE_JUMP if body.velocity.y > 0.5 else STATE_FALL)
		return
	if body.wants_crouch:
		_travel(STATE_CROUCH)
		tree.set(&"parameters/Crouch/blend_position", _local_velocity())
		return
	_travel(STATE_LOCOMOTION)
	tree.set(&"parameters/Locomotion/blend_position", _local_velocity())


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


# ------------------------------------------------------------------ build --

func _build_character() -> void:
	var packed := load(MODEL_PATH) as PackedScene
	if packed == null:
		push_error("locomotion lab: missing character scene %s" % MODEL_PATH)
		return
	var model := packed.instantiate()
	model.name = &"Character"
	# The Mixamo rig faces +Z; the body treats -Z as forward.
	model.rotation.y = PI
	add_child(model)

	skeleton = model.find_child("Skeleton3D", true, false) as Skeleton3D
	player = model.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if skeleton == null or player == null:
		push_error("locomotion lab: character has no Skeleton3D/AnimationPlayer")
		return
	player.root_node = player.get_path_to(model)
	_add_clip_library()


func _add_clip_library() -> void:
	var library := AnimationLibrary.new()
	for clip_name: StringName in CLIPS:
		var path := CLIP_DIR + String(CLIPS[clip_name]) + ".res"
		var animation := load(path) as Animation
		if animation == null:
			push_warning("locomotion lab: missing clip %s" % path)
			continue
		var copy := animation.duplicate() as Animation
		copy.loop_mode = Animation.LOOP_LINEAR if clip_name in LOOPING else Animation.LOOP_NONE
		library.add_animation(clip_name, copy)
	player.add_animation_library(&"clips", library)


func _build_animation_tree() -> void:
	if player == null:
		return
	var machine := AnimationNodeStateMachine.new()

	var locomotion := _blend_space(
		[
			[&"clips/idle", Vector2.ZERO],
			[&"clips/walk_f", Vector2(0.0, BLEND_WALK_SPEED)],
			[&"clips/walk_b", Vector2(0.0, -BLEND_WALK_SPEED)],
			[&"clips/walk_lf", Vector2(-0.707, 0.707) * BLEND_WALK_SPEED],
			[&"clips/walk_rf", Vector2(0.707, 0.707) * BLEND_WALK_SPEED],
			[&"clips/walk_lb", Vector2(-0.707, -0.707) * BLEND_WALK_SPEED],
			[&"clips/walk_rb", Vector2(0.707, -0.707) * BLEND_WALK_SPEED],
			[&"clips/run_f", Vector2(0.0, BLEND_RUN_SPEED)],
			[&"clips/run_b", Vector2(0.0, -BLEND_RUN_SPEED)],
			[&"clips/run_lf", Vector2(-0.707, 0.707) * BLEND_RUN_SPEED],
			[&"clips/run_rf", Vector2(0.707, 0.707) * BLEND_RUN_SPEED],
			[&"clips/run_lb", Vector2(-0.707, -0.707) * BLEND_RUN_SPEED],
			[&"clips/run_rb", Vector2(0.707, -0.707) * BLEND_RUN_SPEED],
		],
		8.0
	)
	var crouch := _blend_space(
		[
			[&"clips/crouch_idle", Vector2.ZERO],
			[&"clips/crouch_f", Vector2(0.0, BLEND_CROUCH_SPEED)],
			[&"clips/crouch_b", Vector2(0.0, -BLEND_CROUCH_SPEED)],
			[&"clips/crouch_l", Vector2(-BLEND_CROUCH_SPEED, 0.0)],
			[&"clips/crouch_r", Vector2(BLEND_CROUCH_SPEED, 0.0)],
		],
		2.2
	)

	machine.add_node(STATE_LOCOMOTION, locomotion)
	machine.add_node(STATE_CROUCH, crouch)
	machine.add_node(STATE_JUMP, _clip_node(&"clips/jump"))
	machine.add_node(STATE_FALL, _clip_node(&"clips/fall"))
	machine.add_node(STATE_TURN_L90, _clip_node(&"clips/turn_l90"))
	machine.add_node(STATE_TURN_R90, _clip_node(&"clips/turn_r90"))
	machine.add_node(STATE_TURN_L180, _clip_node(&"clips/turn_l180"))
	machine.add_node(STATE_TURN_R180, _clip_node(&"clips/turn_r180"))
	_connect_all(machine)

	tree = AnimationTree.new()
	tree.name = &"AnimationTree"
	add_child(tree)
	tree.anim_player = tree.get_path_to(player)
	tree.tree_root = machine
	tree.active = true
	_playback = tree.get(&"parameters/playback")


func _blend_space(points: Array, radius: float) -> AnimationNodeBlendSpace2D:
	var space := AnimationNodeBlendSpace2D.new()
	space.min_space = Vector2(-radius, -radius)
	space.max_space = Vector2(radius, radius)
	for entry in points:
		var node := AnimationNodeAnimation.new()
		node.animation = entry[0]
		space.add_blend_point(node, entry[1], -1, String(entry[0]).get_slice("/", 1))
	return space


func _clip_node(animation: StringName) -> AnimationNodeAnimation:
	var node := AnimationNodeAnimation.new()
	node.animation = animation
	return node


## Every state can reach every other state, so the driver can travel freely.
## Skips the state machine's reserved Start/End nodes.
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
	if _turn_state != &"":
		_turn_state = &""
		player.speed_scale = 1.0
	if _playback.get_current_node() == state:
		return
	_playback.travel(state)


func _sync_turn() -> void:
	var machine := body.state_machine
	var angle := machine.turn_angle_deg
	var magnitude := absf(angle)
	var state := STATE_TURN_R90
	if magnitude >= 130.0:
		state = STATE_TURN_L180 if angle > 0.0 else STATE_TURN_R180
	else:
		state = STATE_TURN_L90 if angle > 0.0 else STATE_TURN_R90
	var clip_length := _clip_length(state)
	var duration := maxf(0.05, machine.turn_duration)
	player.speed_scale = clip_length / duration
	if state != _turn_state:
		_turn_state = state
		_playback.travel(state)


func _clip_length(state: StringName) -> float:
	var name: StringName = {
		STATE_TURN_L90: &"turn_l90",
		STATE_TURN_R90: &"turn_r90",
		STATE_TURN_L180: &"turn_l180",
		STATE_TURN_R180: &"turn_r180",
	}.get(state, &"turn_l90")
	return player.get_animation(&"clips/" + String(name)).length


func _local_velocity() -> Vector2:
	if body == null:
		return Vector2.ZERO
	var local := body.global_transform.basis.inverse() * body.velocity
	return Vector2(local.x, -local.z)
