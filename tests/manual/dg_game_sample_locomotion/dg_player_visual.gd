class_name DGPlayerVisual
extends Node3D
## Animation layer for the DG_GAME_SAMPLE locomotion lab, driven by the game's own rig.
##
## Unlike `dg_game_sample_locomotion_visual.gd` (Y Bot + retargeted ALS clips), this loads the
## character baked straight out of DG_GAME_SAMPLE: `player_locomotion.glb` carries the player's four
## body parts, his hands, the 547-bone PSA skeleton and 37 clips decoded from the game
## (see the RE workspace's notes\animations.md). Clip names are the bake names:
## idle, walk_F/B/L/R/FL/FR/BL, run_F/B, sprint_F, crouch_walk_F/B/L/R,
## turn_L_90/R_90, turn_L_180/R_180, jump_start(_sprint), fall_loop, land_soft, land_hard,
## walk_uphill(_fast), walk_downhill(_fast), run_uphill, run_downhill,
## step_down, step_down_land, edge_drop, slide_45, slide_65.
##
## The GLB ships inside the project (assets/models/dg_game_sample/) and is imported by
## Godot like any other scene, so nothing here depends on an external path.
##
## State mapping mirrors the recovered UE4 machine:
##   Idle / Move -> "Locomotion" 2D blend space over local velocity (walk ring, run, sprint)
##   Crouch      -> "Crouch" 2D blend space over the local velocity direction (F/B/L/R)
##   Turn        -> 90 or 180 degree clip by turn magnitude, time-scaled to the procedural turn
##   Uphill/Downhill -> 1D blend space over speed, for grounds steeper than SLOPE_MIN_DEG
##   Air         -> jump_start / fall_loop, then land_soft or land_hard on touchdown
##
## The air sub-states are ours, not the game's: the body only reports "Air", so the visual
## infers jump / fall / land from the sign of vertical velocity and the recorded fall speed.
## Short drops (a stair, a kerb) use the game's step_down / step_down_land pair instead.
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
const STATE_JUMP := &"Jump"
const STATE_JUMP_SPRINT := &"JumpSprint"
const STATE_FALL := &"Fall"
const STATE_LAND_SOFT := &"LandSoft"
const STATE_LAND_HARD := &"LandHard"
const STATE_STEP_DOWN := &"StepDown"
const STATE_STEP_DOWN_LAND := &"StepDownLand"
const STATE_EDGE_DROP := &"EdgeDrop"
const STATE_SLOPE_UP := &"SlopeUp"
const STATE_SLOPE_DOWN := &"SlopeDown"

## A turn at or above this magnitude uses the 180 degree clip.
const TURN_180_THRESHOLD_DEG := 135.0

## Slope magnitude (degrees) past which the uphill/downhill clips replace the flat ring.
## The release threshold is lower so a body walking exactly on the enter angle cannot flicker.
## 10 deg is into the range where a flat walk visibly skates; the game's own clip is authored
## for 45 deg, so the mismatch is largest at the low end and the threshold trades that off.
const SLOPE_ENTER_DEG := 10.0
const SLOPE_EXIT_DEG := 7.0
## Largest drop (metres) still treated as a step down rather than a fall, and the larger limit
## below which the game's `edge_drop` clip is used instead of the free-fall loop.
const STEP_DOWN_MAX := 0.60
const EDGE_DROP_MAX := 1.20
## Airborne stretches shorter than this keep the current clip. A rounded capsule rolling over a
## stair nose loses floor contact for a frame or two (measured: 2 frames on a 0.35 m step), and
## that must not start a fall/land cycle.
const AIR_GRACE := 0.10
## Landing clips from a step down are held briefly; the long hold is for real falls.
const STEP_LAND_HOLD := 0.22

## Vertical speed above which leaving the ground counts as a jump rather than a drop.
const AIR_RISE_THRESHOLD := 0.5
## Touchdown speed (m/s, negative) that selects the hard landing clip.
const HARD_LANDING_SPEED := -6.0
## Longest time a landing clip is allowed to hold the visual before locomotion resumes.
const LAND_HOLD_MAX := 0.55

## The fall loop's name, in the order it is looked for. `fall_loop` is the bake name; Godot's
## glTF importer publishes it as `fall` (see `_fall_clip_name`).
const FALL_CLIP_NAMES := [&"fall_loop", &"fall"]

const SLOPE_UP_PARAM := &"parameters/SlopeUp/blend_position"
const SLOPE_DOWN_PARAM := &"parameters/SlopeDown/blend_position"

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
		&"crouch_walk_B", &"crouch_walk_L", &"crouch_walk_R", &"fall_loop", &"fall",
		&"walk_uphill", &"walk_uphill_fast", &"walk_downhill", &"walk_downhill_fast",
		&"run_uphill", &"run_downhill"]

## Slope clips as (animation, speed it was authored for in m/s). The game's uphill clips are
## authored at 45 deg (`dcn_walk_uphill_45degrees`); the speeds are INFERRED from how the pose
## reads, not recovered - the PSAs carry no speed metadata. Only the ordering matters to a 1D
## blend, and playback speed is scaled to the measured speed on top of it.
const SLOPE_UP_POINTS := [
	[&"walk_uphill", 3.0],
	[&"walk_uphill_fast", 4.2],
	[&"run_uphill", 5.6],
]

const SLOPE_DOWN_POINTS := [
	[&"walk_downhill", 3.0],
	[&"walk_downhill_fast", 4.2],
	[&"run_downhill", 5.6],
]

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
## Air sub-state: one of &"jump", &"fall", &"land", or &"" when grounded.
var _air_phase := &""
var _land_time_left := 0.0
## Most negative vertical speed seen during the current airborne stretch (m/s).
var _fall_speed := 0.0
## False until the body has stood on the floor once, so the spawn settle is not a landing.
var _grounded_once := false
## Which slope clip set currently owns the frame: &"", &"up" or &"down" (with hysteresis).
var _slope_side := &""
## Seconds spent off the floor in the current stretch, for the `AIR_GRACE` window.
var _air_time := 0.0


func _ready() -> void:
	_build_character()
	_build_animation_tree()


## Called by the lab once per physics frame.
func sync(delta: float) -> void:
	if body == null or _playback == null:
		return
	if _sync_air(delta):
		return
	_sync_grounded()


## Airborne handling. Returns true when the air phase owns the frame (airborne, landing, or the
## spawn settle). Airborne is a physics question, not a state-machine one: the machine can still
## report Idle/Move mid-jump, which is why `is_on_floor()` is the gate and not the state name.
func _sync_air(delta: float) -> bool:
	if _air_phase == &"land":
		_land_time_left -= delta
		if _land_time_left > 0.0 and body.is_grounded():
			return true
		_air_phase = &""
		_fall_speed = 0.0
		player.speed_scale = 1.0
	if not body.is_grounded():
		_air_time += delta
		# Ignore the spawn settle (a few centimetres before the first grounding) and floor
		# contacts lost for less than the grace window.
		if not _grounded_once or _air_time < AIR_GRACE:
			return true
		_sync_airborne()
		return true
	_grounded_once = true
	_air_time = 0.0
	if _air_phase != &"":
		_start_land()
		return true
	return false


## Pick the jump clip while rising, the fall loop once vertical speed turns over. A short drop
## that starts with no upward speed is a stair, not a jump, so it gets the step_down clip; the
## drop height is measured with a downward ray, since the fall itself has not happened yet.
func _sync_airborne() -> void:
	if _air_phase == &"":
		_fall_speed = body.velocity.y
		if body.velocity.y > AIR_RISE_THRESHOLD:
			_air_phase = &"jump"
			var sprinting := absf(body.velocity.length()) >= (SPEED_RUN + SPEED_SPRINT) * 0.5
			if sprinting and machine_has(STATE_JUMP_SPRINT):
				_travel(STATE_JUMP_SPRINT)
			else:
				_travel(STATE_JUMP)
		elif machine_has(STATE_STEP_DOWN) or machine_has(STATE_EDGE_DROP):
			# A short drop that starts with no upward speed is a stair or a kerb, not a jump.
			# Measure it now: the fall has not happened yet.
			var drop := _drop_distance(EDGE_DROP_MAX)
			if drop < STEP_DOWN_MAX and machine_has(STATE_STEP_DOWN):
				_air_phase = &"step"
				_travel(STATE_STEP_DOWN)
			elif drop < EDGE_DROP_MAX and machine_has(STATE_EDGE_DROP):
				_air_phase = &"edge"
				_travel(STATE_EDGE_DROP)
			else:
				_air_phase = &"fall"
				_travel(STATE_FALL)
		else:
			_air_phase = &"fall"
			_travel(STATE_FALL)
		player.speed_scale = 1.0
		return
	_fall_speed = minf(_fall_speed, body.velocity.y)
	if _air_phase == &"jump" and body.velocity.y <= 0.0:
		_air_phase = &"fall"
		_travel(STATE_FALL)
	player.speed_scale = 1.0


## Distance (metres) from the capsule's base to the first floor below it, capped at `limit`.
## The cap means a long fall only has to fail the tests, not measure the whole drop.
func _drop_distance(limit: float) -> float:
	var space := body.get_world_3d().direct_space_state
	if space == null:
		return limit
	var from := body.global_position + Vector3.UP * 0.05
	var query := PhysicsRayQueryParameters3D.create(
		from, from + Vector3.DOWN * limit, 1, [body.get_rid()]
	)
	var hit := space.intersect_ray(query)
	if hit.is_empty():
		return limit
	return from.y - (hit["position"] as Vector3).y


func _start_land() -> void:
	var stepping := _air_phase == &"step"
	var hard := _fall_speed <= HARD_LANDING_SPEED
	var state := STATE_LAND_HARD if hard else STATE_LAND_SOFT
	if stepping and machine_has(STATE_STEP_DOWN_LAND):
		state = STATE_STEP_DOWN_LAND
	if not machine_has(state):
		state = STATE_LAND_SOFT
	if not machine_has(state):
		_air_phase = &""
		_fall_speed = 0.0
		return
	var clip := _clip_for_state(state)
	_air_phase = &"land"
	_playback.travel(state)
	var hold := STEP_LAND_HOLD if state == STATE_STEP_DOWN_LAND else LAND_HOLD_MAX
	_land_time_left = minf(player.get_animation(clip).length, hold) \
			if player.has_animation(clip) else 0.0
	player.speed_scale = 1.0


## Animation name behind a one-shot state; empty when the clip is missing.
func _clip_for_state(state: StringName) -> StringName:
	match state:
		STATE_LAND_HARD:
			return &"land_hard"
		STATE_STEP_DOWN_LAND:
			return &"step_down_land"
		_:
			return &"land_soft"


func _sync_grounded() -> void:
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
	if _sync_slope():
		return
	_slope_side = &""
	_travel(STATE_LOCOMOTION)
	tree.set(&"parameters/Locomotion/blend_position", _local_velocity())
	player.speed_scale = _speed_scale(absf(body.velocity.length()), _ring_speed())


## Ground steeper than SLOPE_ENTER_DEG switches to the game's uphill/downhill cycles.
## Returns true when a slope state owns the frame.
##
## These clips are authored forwards and the game has one angle (45 deg), so they are only used
## heading forward: a sideways walk on a slope is better served by the flat ring's strafe.
func _sync_slope() -> bool:
	var planar := absf(body.velocity.length())
	var local := _local_velocity()
	if planar < 0.20 or local.y < local.length() * 0.5:
		_slope_side = &""
		return false
	var slope := body.get_slope_deg()
	var limit := SLOPE_EXIT_DEG if _slope_side != &"" else SLOPE_ENTER_DEG
	var side := &""
	if slope >= limit:
		side = &"up"
	elif slope <= -limit:
		side = &"down"
	var state := STATE_SLOPE_UP if side == &"up" else STATE_SLOPE_DOWN
	if side == &"" or not machine_has(state):
		_slope_side = &""
		return false
	_slope_side = side
	_travel(state)
	tree.set(SLOPE_UP_PARAM if side == &"up" else SLOPE_DOWN_PARAM, clampf(planar, 3.0, 5.6))
	player.speed_scale = 1.0
	return true


## The fall loop is baked as `fall_loop`, but Godot's glTF importer publishes it as `fall`
## (observed in the imported AnimationPlayer), so both names are accepted.
func _fall_clip_name() -> StringName:
	for candidate in FALL_CLIP_NAMES:
		if player.has_animation(candidate):
			return candidate
	return &""


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
			[STATE_TURN_L180, &"turn_L_180"], [STATE_TURN_R180, &"turn_R_180"],
			[STATE_JUMP, &"jump_start"], [STATE_JUMP_SPRINT, &"jump_start_sprint"],
			[STATE_LAND_SOFT, &"land_soft"], [STATE_LAND_HARD, &"land_hard"],
			[STATE_STEP_DOWN, &"step_down"], [STATE_STEP_DOWN_LAND, &"step_down_land"],
			[STATE_EDGE_DROP, &"edge_drop"]]:
		if player.has_animation(entry[1]):
			machine.add_node(entry[0], _clip_node(entry[1]))
	var fall_clip := _fall_clip_name()
	if fall_clip != &"":
		machine.add_node(STATE_FALL, _clip_node(fall_clip))
	for entry in [[STATE_SLOPE_UP, SLOPE_UP_POINTS], [STATE_SLOPE_DOWN, SLOPE_DOWN_POINTS]]:
		var space := _slope_space(entry[1])
		if space != null:
			machine.add_node(entry[0], space)
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


## 1D blend space over ground speed for one slope direction. Returns null when none of the
## clips are present, so the state is simply not added and the flat ring keeps the frame.
func _slope_space(points: Array) -> AnimationNodeBlendSpace1D:
	var space := AnimationNodeBlendSpace1D.new()
	var added := 0
	for entry in points:
		if not player.has_animation(entry[0]):
			continue
		var node := AnimationNodeAnimation.new()
		node.animation = entry[0]
		space.add_blend_point(node, entry[1], -1, String(entry[0]))
		added += 1
	if added == 0:
		return null
	space.min_space = points[0][1]
	space.max_space = points[points.size() - 1][1]
	return space


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
