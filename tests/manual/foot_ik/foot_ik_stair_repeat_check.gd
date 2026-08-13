extends RefCounted

## Drives one real Player over the same staircase repeatedly without resetting
## PlayerStairController. This catches stale tread/contact state that a fresh
## one-way ascent cannot expose.

const INPUT_FORWARD := Vector2(0.0, -1.0)
const START_POSITION := Vector3(15.0, 0.05, -0.8)
const TOP_Z := 3.35
const BOTTOM_Z := -0.8
const HOLD_FRAMES := 12
const REQUIRED_ASCENTS := 2
const STALL_TRAVEL := 0.002
const MAX_STALL_FRAMES := 8
const MAX_VERTICAL_FRAME_TRAVEL := 0.05

var _player: Player
var _phase := &"up"
var _hold_frames := 0
var _ascents := 0
var _stall_frames := 0
var _max_stall_frames := 0
var _previous_xz := Vector2.ZERO
var _previous_root_y := 0.0
var _previous_head := Vector3.ZERO
var _previous_head_delta := Vector3.ZERO
var _head_turns: Array[float] = []
var _max_vertical_frame_travel := 0.0
var _max_balance_offset := 0.0
var _done := false


func setup(player: Player) -> void:
	_player = player
	_player.global_position = START_POSITION
	_player.rotation = Vector3(0.0, PI, 0.0)
	_player.velocity = Vector3.ZERO
	_player.movement_input_override = INPUT_FORWARD
	_player.gameplay_action_input_enabled = false
	_previous_xz = _xz()
	_previous_root_y = _player.global_position.y
	_previous_head = _head_position()


func drive() -> void:
	if _done:
		return
	var travel := _xz().distance_to(_previous_xz)
	_previous_xz = _xz()
	if _phase == &"up" or _phase == &"down":
		_sample_stall(travel)
		_sample_trajectory()
	match _phase:
		&"up":
			_player.movement_input_override = INPUT_FORWARD
			if _player.global_position.z >= TOP_Z:
				_ascents += 1
				_begin_hold(&"hold_top")
		&"hold_top":
			_tick_hold(&"down", 0.0)
		&"down":
			_player.movement_input_override = INPUT_FORWARD
			if _player.global_position.z <= BOTTOM_Z:
				_begin_hold(&"hold_bottom")
		&"hold_bottom":
			if _ascents >= REQUIRED_ASCENTS:
				_done = true
				_player.movement_input_override = Vector2.ZERO
			else:
				_tick_hold(&"up", PI)


func is_done() -> bool:
	return _done


func format_result() -> String:
	var passed := _done and _ascents >= REQUIRED_ASCENTS \
			and _max_stall_frames <= MAX_STALL_FRAMES \
			and _max_vertical_frame_travel <= MAX_VERTICAL_FRAME_TRAVEL
	var head_p95 := _percentile(_head_turns, 0.95)
	return ("FOOT_IK_STAIR_REPEAT_CHECK %s ascents=%d max_stall_frames=%d "
			+ "limit=%d max_vertical_frame_m=%.4f vertical_limit_m=%.4f "
			+ "head_turn_p95_deg=%.2f balance_max_m=%.4f "
			+ "head_turn_samples=%d phase=%s") % [
			"PASS" if passed else "FAIL", _ascents, _max_stall_frames,
			MAX_STALL_FRAMES, _max_vertical_frame_travel, MAX_VERTICAL_FRAME_TRAVEL,
			head_p95, _max_balance_offset,
			_head_turns.size(), _phase]


func _begin_hold(phase: StringName) -> void:
	_phase = phase
	_hold_frames = HOLD_FRAMES
	_player.movement_input_override = Vector2.ZERO
	_player.velocity.x = 0.0
	_player.velocity.z = 0.0
	_stall_frames = 0


func _tick_hold(next_phase: StringName, yaw: float) -> void:
	_hold_frames -= 1
	if _hold_frames > 0:
		return
	_phase = next_phase
	_player.rotation = Vector3(0.0, yaw, 0.0)
	_player.movement_input_override = INPUT_FORWARD
	_previous_xz = _xz()


func _sample_stall(travel: float) -> void:
	if travel < STALL_TRAVEL:
		_stall_frames += 1
		_max_stall_frames = maxi(_max_stall_frames, _stall_frames)
	else:
		_stall_frames = 0


func _sample_trajectory() -> void:
	var stair_state := _player.get_stair_debug_state()
	_max_balance_offset = maxf(
			_max_balance_offset, absf(float(stair_state["balance_offset_y"])))
	_max_vertical_frame_travel = maxf(
			_max_vertical_frame_travel,
			absf(_player.global_position.y - _previous_root_y))
	_previous_root_y = _player.global_position.y
	var head := _head_position()
	var delta := head - _previous_head
	_previous_head = head
	if delta.length() > 0.0005 and _previous_head_delta.length() > 0.0005:
		_head_turns.append(rad_to_deg(_previous_head_delta.angle_to(delta)))
	if delta.length() > 0.0005:
		_previous_head_delta = delta


func _head_position() -> Vector3:
	var index := _player.skeleton.find_bone(_player.body.resolve_bone_name(&"Head"))
	return (_player.body.global_transform
			* _player.body.get_visual_bone_global_pose(index).origin)


func _percentile(values: Array[float], ratio: float) -> float:
	if values.is_empty():
		return 0.0
	var sorted := values.duplicate()
	sorted.sort()
	return sorted[roundi((sorted.size() - 1) * ratio)]


func _xz() -> Vector2:
	return Vector2(_player.global_position.x, _player.global_position.z)
