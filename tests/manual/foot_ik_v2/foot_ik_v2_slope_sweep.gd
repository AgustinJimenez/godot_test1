extends Node3D
## Slope sweep for Foot IK v2: the player stands on a ramp of every angle from 5 to 70 degrees, facing
## several ways, with no input. On ground it can stand on (up to the player's floor_max_angle) it must STAY
## STILL; on a steeper slope it must SLIDE, only downhill and without walking. Never both: no creeping up
## the slope, no feet that keep re-stepping, no safe-zone nudge walking the body (a live log of the lab's
## 45 degree ramp had the body crept 1 m uphill by the ledge nudge, which read the slope as a void).
##   godot --headless --path . --fixed-fps 60 res://tests/manual/foot_ik_v2/foot_ik_v2_slope_sweep.tscn
## Prints one line per case and FOOT_IK_V2_SLOPE_SWEEP PASS / FAIL (exit code 0 / 1). `--angles=a,b,c`
## and `--yaws=a,b,c` narrow the sweep.

const PLAYER_SCENE := preload("res://actors/player/player.tscn")
const ANGLES := [5.0, 10.0, 15.0, 20.0, 25.0, 30.0, 35.0, 40.0, 44.0, 46.0, 50.0, 55.0, 60.0, 70.0]
const YAWS := [0.0, 45.0, 90.0, 135.0, 180.0, -90.0] ## 0 = facing uphill (the ramp climbs toward -Z)
const RAMP_SIZE := Vector3(24.0, 0.4, 80.0)
const SETTLE_FRAMES := 90 ## the body lands and the IK settles
const WATCH_FRAMES := 240
const STILL_DRIFT := 0.03 ## m the body may move over the watch while standing
const FOOT_MOVE := 0.012 ## m a planted foot may move against the body in one frame
const MAX_FOOT_MOVES := 6 ## frames with such a move (a settle can shuffle a foot once or twice)
const UPHILL_TOLERANCE := 0.03 ## m the body may go UP the slope while sliding

var _angles: Array = ANGLES
var _yaws: Array = YAWS
var _case := 0
var _frame := 0
var _ramp: StaticBody3D
var _player: Player
var _start := Vector3.ZERO
var _uphill := Vector3.ZERO
var _prev_feet := {}
var _foot_moves := 0
var _push_frames := 0
var _walk_frames := 0
var _floor_frames := 0
var _max_uphill := 0.0
var _failures: PackedStringArray = []


func _ready() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--angles="):
			_angles = Array(arg.trim_prefix("--angles=").split(",")).map(func(a: String) -> float: return a.to_float())
		if arg.begins_with("--yaws="):
			_yaws = Array(arg.trim_prefix("--yaws=").split(",")).map(func(a: String) -> float: return a.to_float())
	var floor_body := StaticBody3D.new() # far below, so a body sliding off the end of a ramp is caught
	floor_body.collision_layer = 1
	var floor_shape := CollisionShape3D.new()
	var floor_box := BoxShape3D.new()
	floor_box.size = Vector3(400.0, 1.0, 400.0)
	floor_shape.shape = floor_box
	floor_body.add_child(floor_shape)
	add_child(floor_body)
	floor_body.position = Vector3(0.0, -60.0, 0.0)
	_ramp = StaticBody3D.new()
	_ramp.collision_layer = 1
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = RAMP_SIZE
	shape.shape = box
	_ramp.add_child(shape)
	add_child(_ramp)
	_player = PLAYER_SCENE.instantiate() as Player
	add_child(_player)
	_player.movement_input_override = Vector2.ZERO
	_begin_case()


func _cases() -> int:
	return _angles.size() * _yaws.size()


func _angle() -> float:
	return float(_angles[_case / _yaws.size()])


func _yaw() -> float:
	return float(_yaws[_case % _yaws.size()])


func _begin_case() -> void:
	var angle := deg_to_rad(_angle())
	_ramp.rotation = Vector3(angle, 0.0, 0.0)
	_ramp.position = Vector3.ZERO
	# the top face's centre is at (0, 0.2 / cos, 0) tilted: put the player on it a little above, mid-ramp
	var surface := Vector3(0.0, RAMP_SIZE.y * 0.5, 0.0)
	var on_top := _ramp.global_transform * surface
	_player.global_position = on_top + Vector3.UP * 0.4
	_player.rotation = Vector3(0.0, deg_to_rad(_yaw()), 0.0)
	_player.velocity = Vector3.ZERO
	_uphill = (_ramp.global_transform.basis * Vector3(0.0, 0.0, -1.0))
	_uphill.y = 0.0
	_uphill = _uphill.normalized()
	_frame = 0
	_prev_feet = {}
	_foot_moves = 0
	_push_frames = 0
	_walk_frames = 0
	_floor_frames = 0
	_max_uphill = 0.0


func _physics_process(_delta: float) -> void:
	if _case >= _cases():
		return
	_frame += 1
	if _frame == SETTLE_FRAMES:
		_start = _player.global_position
	if _frame > SETTLE_FRAMES:
		_watch()
	if _frame >= SETTLE_FRAMES + WATCH_FRAMES:
		_judge()
		_case += 1
		if _case >= _cases():
			_finish()
		else:
			_begin_case()


func _watch() -> void:
	var v2 := _player.body.skeleton.get_node_or_null("FootIKV2") as FootIKV2Modifier
	if v2 != null and not v2.ledge_push().is_zero_approx():
		_push_frames += 1
	var clip := String(_player.body.anim_player.current_animation)
	if clip.contains("walk") or clip.contains("run") or clip.contains("sprint"):
		_walk_frames += 1
	if _player.is_on_floor():
		_floor_frames += 1
	var moved := _player.global_position - _start
	_max_uphill = maxf(_max_uphill, moved.dot(_uphill))
	var to_local := _player.global_transform.affine_inverse()
	var skeleton := _player.body.skeleton
	var moves := false
	for bone: String in ["foot_l", "foot_r"]:
		var index := skeleton.find_bone(bone)
		if index < 0:
			continue
		var here: Vector3 = to_local * (_player.body.global_transform * skeleton.get_bone_global_pose(index)).origin
		if _prev_feet.has(bone) and (here - (_prev_feet[bone] as Vector3)).length() > FOOT_MOVE:
			moves = true
		_prev_feet[bone] = here
	if moves:
		_foot_moves += 1


func _judge() -> void:
	var moved := _player.global_position - _start
	var drift := moved.length()
	var downhill := -moved.dot(_uphill)
	var standable := _angle() <= rad_to_deg(_player.floor_max_angle) - 0.5
	var sliding_expected := _angle() >= rad_to_deg(_player.floor_max_angle) + 0.5
	var verdict := ""
	var problems: PackedStringArray = []
	if standable:
		verdict = "STILL"
		if drift > STILL_DRIFT:
			problems.append("moved %.3f m" % drift)
		if _push_frames > 0:
			problems.append("ledge push %d frames" % _push_frames)
		if _walk_frames > 0:
			problems.append("walk clip %d frames" % _walk_frames)
		if _foot_moves > MAX_FOOT_MOVES:
			problems.append("feet moved on %d frames" % _foot_moves)
	elif sliding_expected:
		verdict = "SLIDE"
		if _max_uphill > UPHILL_TOLERANCE:
			problems.append("went UP the slope %.3f m" % _max_uphill)
		if _push_frames > 0:
			problems.append("ledge push %d frames" % _push_frames)
		if _walk_frames > 0:
			problems.append("walk clip %d frames" % _walk_frames)
		var across := Vector2(moved.x, moved.z).distance_to(Vector2(_uphill.x, _uphill.z) * -downhill)
		if across > 0.3 * maxf(downhill, 1.0):
			problems.append("slid %.2f m sideways of the fall line (downhill %.2f)" % [across, downhill])
	else:
		verdict = "LIMIT" # at the limit either is fine, but never uphill / pushed / walking
		if _max_uphill > UPHILL_TOLERANCE:
			problems.append("went UP the slope %.3f m" % _max_uphill)
		if _push_frames > 0:
			problems.append("ledge push %d frames" % _push_frames)
		if _walk_frames > 0:
			problems.append("walk clip %d frames" % _walk_frames)
	var line := "%-5s angle=%4.0f yaw=%5.0f drift=%.3f downhill=%.3f uphill_max=%.3f feet_moves=%d push=%d walk=%d floor=%d/%d %s" % [
			verdict, _angle(), _yaw(), drift, downhill, _max_uphill, _foot_moves, _push_frames, _walk_frames,
			_floor_frames, WATCH_FRAMES, "OK" if problems.is_empty() else "BAD: " + ", ".join(problems)]
	print(line)
	if not problems.is_empty():
		_failures.append(line)


func _finish() -> void:
	print("FOOT_IK_V2_SLOPE_SWEEP %s cases=%d bad=%d floor_max_angle=%.0f" % [
			"PASS" if _failures.is_empty() else "FAIL", _cases(), _failures.size(), rad_to_deg(_player.floor_max_angle)])
	get_tree().quit(0 if _failures.is_empty() else 1)
