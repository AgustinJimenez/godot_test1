class_name PlayerClimb
extends RefCounted
## Ledge climbing for the player (Uncharted-style, opt-in: PlayerClimbInstall puts it on a Player).
## FREE -> a jump toward a ledge in reach catches it -> HANG (hands IK'd to the edge, A / D
## shimmy along it, W pulls up, jump leaps, crouch drops) -> MANTLE (up and over onto the top) ->
## FREE. Crouch at a wall's edge, facing off it, lowers into a hang.
## `update()` returns true on the frames it owns the body; the player then skips its own movement.
## With the Mixamo hang clips (ClimbClips) the body plays them and the hand IK only fine-tunes the
## hands onto the ledge; without them the legs play the fall clip and the arms are IK alone.

enum State { FREE, HANG, MANTLE, WALL }

const GRAB_SPEED_Y := 3.5 # m/s: faster upward than this the jump is still launching
const GRAB_BLEND := 0.2 # s to settle into the hang
const SHIMMY_SPEED := 1.0 # m/s
const MANTLE_TIME := 1.0 # s
const MANTLE_RISE := 0.6 # fraction of the mantle spent going up before going over
const COOLDOWN := 0.5 # s after letting go / mantling before the next grab
const HAND_SPREAD := 0.22 # m each hand sits from the middle
const HAND_BACK := 0.07 # m behind the edge, on the top surface
const SHOULDER_BACK := 0.3 # m the body hangs from the wall face (capsule radius + a little)
const SHOULDER_BEHIND := 0.08 # m the shoulders sit behind the capsule centre (measured)
const REACH_FRACTION := 0.9 # of the full arm: the elbows stay a little bent
const TURN_SPEED := 8.0 # 1/s the body turns to face the wall
const LEAP_UP := 6.5 # m/s a leap off a hold goes up
const LEAP_OUT := 3.0 # m/s it goes toward / away from the wall or sideways
const WRIST_HANG := 1.78 # m the wrists are above the capsule in the hang clip (measured)
const WRIST_UP := 2.0 # the same at the start of the pull-up clip
const HANG_BACK := 0.0 # m out from the wall face the capsule hangs with the clips
const GRAB_CLIP_SPEED := 3.0 # the jump-to-hang clip plays this much faster than authored
const GRAB_CLIP_TIME := 0.5 # s before the hang idle takes over
const UP_SPEED := 2.0 # the pull-up clip plays this much faster than authored

var state := State.FREE
var enabled := true
var hands: PlayerHandHoldIKModifier

var _player: Player
var _ledge: Dictionary = {}
var _time := 0.0
var _from := Vector3.ZERO
var _cooldown := 0.0
var _hang_drop := 1.8 # m from the hands to the feet while hanging (from the arm length)
var _wall: ClimbWall
var balance: PlayerBalance
var shuffle := ClimbHandShuffle.new() # the hands along the ledge while hanging
var _down_time := 0.0 # s the stick has asked for DOWN with no hold below
var clips_ok := false # the hang clips are in the animation library
var _hang_back := SHOULDER_BACK
var _wrist_up := WRIST_UP
var _foot_ik_weight := -1.0 # the foot IK weight to give back after the climb (-1 = not held)
var _clip: StringName = &""
var _grab_pending := false
var _reverse := false # the pull-up clip plays backwards: lowering into a hang
var _origin := Vector3.ZERO # capsule position when the pull-up clip is at its start


func setup(player: Player, hand_modifier: PlayerHandHoldIKModifier) -> PlayerClimb:
	_player = player
	hands = hand_modifier
	_wall = ClimbWall.new().setup(self, player)
	balance = PlayerBalance.new().setup(player, hands)
	var reach := hands.arm_reach() * REACH_FRACTION
	var across := SHOULDER_BACK + HAND_BACK + SHOULDER_BEHIND # shoulder to hand, horizontally
	_hang_drop = hands.shoulder_height() + sqrt(maxf(reach * reach - across * across, 0.01))
	return self


## True while climbing owns the player this physics frame.
func update(delta: float) -> bool:
	if not enabled or _player == null:
		return false
	_cooldown = maxf(_cooldown - delta, 0.0)
	_foot_ik_hold(state != State.FREE)
	match state:
		State.FREE:
			balance.update(delta)
			return _try_drop_to_hang() or _try_grab()
		State.HANG:
			_hang(delta)
		State.MANTLE:
			_mantle(delta)
		State.WALL:
			_on_wall(delta)
	return true


## The foot IK plants feet on whatever is under them (the ledge top, the floor): off while the climb owns the legs.
func _foot_ik_hold(hold: bool) -> void:
	var v2 := _player.skeleton.get_node_or_null("FootIKV2")
	if v2 == null or hold == (_foot_ik_weight >= 0.0):
		return
	if hold:
		_foot_ik_weight = v2.weight
		v2.weight = 0.0
	else:
		v2.weight = _foot_ik_weight
		_foot_ik_weight = -1.0


func _try_grab() -> bool:
	if _cooldown > 0.0 or _player.is_on_floor() or _player.velocity.y > GRAB_SPEED_Y:
		return false
	var forward := -_player.global_basis.z
	var flat := Vector3(_player.velocity.x, 0.0, _player.velocity.z)
	if flat.length() > 0.5: # the way it is flying, not the way it looks
		forward = flat.normalized()
	var ledge := ClimbProbe.find(_player.get_world_3d(), _player.global_position, forward,
			_player.collision_mask, [_player.get_rid()])
	if ledge.is_empty():
		if _wall.begin():
			state = State.WALL
			_player.velocity = Vector3.ZERO
			_down_time = 0.0
			return true
		return false
	_ledge = ledge
	_from = _player.global_position
	_time = 0.0
	_grab_pending = true
	state = State.HANG
	_player.velocity = Vector3.ZERO
	return true


func _hang(delta: float) -> void:
	_time += delta
	var normal: Vector3 = _ledge["normal"]
	var right := (-normal).cross(Vector3.UP).normalized() # to the player's right, facing the wall
	var input := Input.get_vector(&"move_left", &"move_right", &"move_forward", &"move_back")
	if movement_override() is Vector2:
		input = movement_override()
	if _time <= delta * 1.5: # just grabbed: the hands start either side of the body
		shuffle.reset((_ledge["point"] as Vector3).dot(right))
	var moved := 0.0
	if input.x != 0.0 and _time >= GRAB_BLEND:
		var next := (_ledge["point"] as Vector3) + right * input.x * SHIMMY_SPEED * delta
		var found := ClimbProbe.follow(_player.get_world_3d(), _ledge, next,
				_player.collision_mask, [_player.get_rid()])
		if not found.is_empty():
			_ledge = found
			moved = input.x
	shuffle.update((_ledge["point"] as Vector3).dot(right), signf(moved), delta)
	if _time >= GRAB_BLEND and input.y < -0.5 and _start_mantle():
		return
	if _time >= GRAB_BLEND and Input.is_action_just_pressed(&"jump"):
		_leap(_ledge["normal"], input)
		return
	if _time >= GRAB_BLEND and Input.is_action_just_pressed(&"crouch"):
		_finish(Vector3.ZERO)
		return
	var held := _hang_position()
	_player.global_position = _from.lerp(held, smoothstep(0.0, GRAB_BLEND, _time))
	face(-normal, delta)
	_place_hands(1.0)
	_animate_hang(delta)


func _start_mantle() -> bool:
	var normal: Vector3 = _ledge["normal"]
	var top := _top_position()
	var space_ok := not _player.test_move(Transform3D(_player.global_basis, top + Vector3.UP * 0.05),
			Vector3.ZERO)
	if not space_ok:
		return false
	if clips_ok:
		_begin_clip(false)
		return true
	_from = _player.global_position
	_time = 0.0
	state = State.MANTLE
	return normal != Vector3.ZERO


func _mantle(delta: float) -> void:
	if clips_ok:
		_mantle_clip(delta)
		return
	_time += delta
	var progress := clampf(_time / MANTLE_TIME, 0.0, 1.0)
	var top := _top_position()
	var over := _from
	over.y = top.y + 0.02
	if progress < MANTLE_RISE:
		_player.global_position = _from.lerp(over, smoothstep(0.0, 1.0, progress / MANTLE_RISE))
	else:
		_player.global_position = over.lerp(top, smoothstep(0.0, 1.0,
				(progress - MANTLE_RISE) / (1.0 - MANTLE_RISE)))
	_place_hands(1.0 - smoothstep(MANTLE_RISE, 1.0, progress))
	animate(delta)
	if progress >= 1.0:
		_finish(Vector3.ZERO)


## Jump off a hold: up, toward the wall with W, away from it with S, sideways with A / D.
func _leap(normal: Vector3, input: Vector2) -> void:
	var right := (-normal).cross(Vector3.UP).normalized()
	_finish(Vector3.UP * LEAP_UP - normal * (LEAP_OUT * -input.y) + right * (LEAP_OUT * input.x))


## Lets go of everything (the climbing is switched off).
func release() -> void:
	if state != State.FREE:
		_finish(Vector3.ZERO)


## True when the crouch key means "drop" (hanging, or at an edge to hang from), not crouch.
func wants_crouch() -> bool:
	return state != State.FREE or not _drop_ledge().is_empty()


## Standing at the top of a wall: the ledge to lower down to. `anywhere` looks all around (the
## nearest edge to the way the body faces), else only straight ahead.
func _drop_ledge(anywhere := false) -> Dictionary:
	if not _player.is_on_floor() or _cooldown > 0.0:
		return {}
	var facing := -_player.global_basis.z
	facing.y = 0.0
	var ledge := {}
	for turn: int in ([0, 1, -1, 2, -2, 3, -3, 4, -4, 5, -5, 6, -6, 7, -7, 8] if anywhere else [0]):
		ledge = ClimbProbe.find_below(_player.get_world_3d(), _player.global_position,
				facing.normalized().rotated(Vector3.UP, turn * PI / 8.0), _player.collision_mask,
				[_player.get_rid()])
		if not ledge.is_empty():
			break
	if ledge.is_empty():
		return {}
	var feet := (ledge["point"] as Vector3) - Vector3.UP * (_hang_drop + 0.3)
	if ClimbProbe.ground_within(_player.get_world_3d(), feet + (ledge["normal"] as Vector3) * 0.3,
			0.3, _player.collision_mask, [_player.get_rid()]):
		return {} # too low to hang from: just step down
	return ledge


## Crouch at an edge you face, or E at any edge (the body turns round to the wall as it hangs).
func _try_drop_to_hang() -> bool:
	var by_key := Input.is_action_just_pressed(&"interact") and _player._current_interactable() == null
	if not by_key and not Input.is_action_just_pressed(&"crouch"):
		return false
	var ledge := _drop_ledge(by_key)
	if ledge.is_empty():
		return false
	_ledge = ledge
	_from = _player.global_position
	_time = 0.0
	_grab_pending = false
	if clips_ok:
		_begin_clip(true)
		return true
	state = State.HANG
	_player.velocity = Vector3.ZERO
	return true


func _finish(velocity: Vector3) -> void:
	state = State.FREE
	_cooldown = COOLDOWN
	_player.velocity = velocity
	if clips_ok:
		_clip = &""
		_player.body._airborne = false # the next update_motion starts the jump or the idle
	if hands != null:
		hands.weight = 0.0
		hands.targets.clear()
		hands.foot_weight = 0.0
		hands.foot_targets.clear()


## Where the body hangs: against the wall, the hands the arm's length under the edge.
func _hang_position() -> Vector3:
	var normal: Vector3 = _ledge["normal"]
	var point: Vector3 = _ledge["point"]
	return Vector3(point.x, point.y - _hang_drop, point.z) + normal * _hang_back


## Standing on the top, just inside the edge.
func _top_position() -> Vector3:
	var normal: Vector3 = _ledge["normal"]
	var point: Vector3 = _ledge["point"]
	return Vector3(point.x, point.y, point.z) - normal * 0.45


func _place_hands(weight: float) -> void:
	if hands == null:
		return
	var normal: Vector3 = _ledge["normal"]
	var right := (-normal).cross(Vector3.UP).normalized()
	var on_top := (_ledge["point"] as Vector3) - normal * HAND_BACK
	var base := on_top.dot(right)
	hands.targets = {}
	for side: StringName in [&"left", &"right"]:
		hands.targets[side] = on_top + right * (shuffle.along(side) - base) \
				+ Vector3.UP * shuffle.lift(side)
	hands.weight = weight
	hands.foot_weight = 0.0 # the legs hang from a ledge
	hands.foot_targets.clear()


func face(direction: Vector3, delta: float) -> void:
	var yaw := atan2(-direction.x, -direction.z)
	var step := angle_difference(_player.rotation.y, yaw) * minf(TURN_SPEED * delta, 1.0)
	# the view stays where the mouse put it while the body turns (as the player's own catch-up does)
	_player._look_yaw -= step
	_player.third_person_arm.rotation.y = _player._look_yaw
	_player.rotate_y(step)


func animate(delta: float) -> void:
	_player.body.update_motion(false, false, 0.0, false, false, -1.0, delta, false)


func movement_override() -> Variant:
	return _player.movement_input_override


## The distance from the hands to the feet while hanging (the arm's length under the hold).
func hang_drop() -> float:
	return _hang_drop


func _on_wall(delta: float) -> void:
	var input := Input.get_vector(&"move_left", &"move_right", &"move_forward", &"move_back")
	if movement_override() is Vector2:
		input = movement_override()
	if Input.is_action_just_pressed(&"jump"):
		_leap(_wall.normal, input)
		return
	if Input.is_action_just_pressed(&"crouch"):
		_finish(Vector3.ZERO)
		return
	if _wall.at_top(input):
		var ledge := ClimbProbe.find(_player.get_world_3d(), _player.global_position,
				-_wall.normal, _player.collision_mask, [_player.get_rid()])
		if not ledge.is_empty():
			_ledge = ledge
			_from = _player.global_position
			_time = 0.0
			state = State.HANG
			return
	_wall.update(delta, input)
	_down_time = _down_time + delta if input.y > 0.5 and _wall.pick_blocked(input) else 0.0
	if _down_time > 0.6: # nothing lower to hold: let go
		_finish(_wall.normal * 1.0)
		return
	animate(delta)


## Switches to the hang clips: the wrists sit WRIST_HANG above the capsule, the body HANG_BACK
## out from the wall face.
func use_clips(wrist_hang := WRIST_HANG, wrist_up := WRIST_UP, hang_back := HANG_BACK) -> void:
	clips_ok = true
	_hang_drop = wrist_hang
	_wrist_up = wrist_up
	_hang_back = hang_back


func _animate_hang(delta: float) -> void:
	if not clips_ok:
		animate(delta)
		return
	if _time > GRAB_CLIP_TIME:
		_grab_pending = false
	if _grab_pending:
		_play(ClimbClips.GRAB, 0.1, GRAB_CLIP_SPEED)
	else:
		_play(ClimbClips.IDLE, 0.2, 1.0)


func _play(clip: StringName, blend: float, speed: float, reverse := false) -> void:
	var body := _player.body
	var key := StringName("%s%s" % [clip, "<" if reverse else ">"])
	if _clip == key:
		return
	_clip = key
	body.anim_player.play("moves/" + clip, blend, -speed if reverse else speed, reverse)
	body.anim_player.speed_scale = 1.0


## Starts the pull-up clip (or, `reverse`, its lowering into a hang).
func _begin_clip(reverse: bool) -> void:
	_reverse = reverse
	_from = _player.global_position
	_time = 0.0
	_origin = _hang_position()
	_origin.y = (_ledge["point"] as Vector3).y - _wrist_up
	state = State.MANTLE
	_player.velocity = Vector3.ZERO
	_clip = &""


func _mantle_clip(delta: float) -> void:
	_time += delta
	var length := ClimbClips.length(ClimbClips.UP)
	var clip_time := _time * UP_SPEED
	var at := clampf(length - clip_time if _reverse else clip_time, 0.0, length)
	var normal: Vector3 = _ledge["normal"]
	var off := ClimbClips.path(ClimbClips.UP, at)
	var held := _origin + Basis(Vector3.UP, atan2(normal.x, normal.z)) * off
	var pos := _from.lerp(held, smoothstep(0.0, 0.25, _time))
	_player.global_position = pos.lerp(_top_position(), smoothstep(length - 0.35, length - 0.05, at))
	face(-normal, delta)
	_place_hands(1.0 - smoothstep(0.1, 0.4, at / length))
	_play(ClimbClips.UP, 0.1, UP_SPEED, _reverse)
	if clip_time >= length - 0.05:
		if _reverse:
			_from = _player.global_position
			_time = 0.0
			_grab_pending = false
			state = State.HANG
		else:
			_finish(Vector3.ZERO)
