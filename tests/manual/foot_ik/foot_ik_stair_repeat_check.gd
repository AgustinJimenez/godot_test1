extends RefCounted

## Drives one real Player over the same staircase repeatedly without resetting
## PlayerStairController. This catches stale tread/contact state that a fresh
## one-way ascent cannot expose.

const INPUT_FORWARD := Vector2(0.0, -1.0)
const RAMP_START_POSITION := Vector3(7.7, 0.95, 0.9)
const RAMP_EXIT_Z := -0.75
const IDLE_STAIR_TOP_POSITION := Vector3(11.27848, 1.200398, 3.474523)
const START_POSITION := Vector3(15.0, 0.05, -0.8)
const TOP_Z := 3.35
const BOTTOM_Z := -0.8
const HOLD_FRAMES := 12
const RAMP_SETTLE_FRAMES := 30
const IDLE_FREEZE_HOLD_FRAMES := 75
const IDLE_FINAL_YAW := 76.0
const REQUIRED_ASCENTS := 2
const STALL_TRAVEL := 0.002
const MAX_STALL_FRAMES := 8
const MAX_VERTICAL_FRAME_TRAVEL := 0.05
const MAX_SURFACE_TRANSITION_TURN_DEG := 12.0
const MAX_SURFACE_VERTICAL_FRAME_TRAVEL := 0.06

var _player: Player
var _phase := &"hold_ramp_start"
var _hold_frames := RAMP_SETTLE_FRAMES
var _ascents := 0
var _stall_frames := 0
var _max_stall_frames := 0
var _previous_xz := Vector2.ZERO
var _previous_root_y := 0.0
var _previous_head := Vector3.ZERO
var _previous_head_delta := Vector3.ZERO
var _head_turns: Array[float] = []
var _previous_root := Vector3.ZERO
var _previous_root_delta := Vector3.ZERO
var _root_turns: Array[float] = []
var _max_surface_transition_turn := 0.0
var _max_surface_transition_frame := 0
var _previous_head_relative_y := 0.0
var _max_head_relative_frame_m := 0.0
var _max_head_relative_frame := 0
var _trajectory_frame := 0
var _trajectory_initialized := false
var _max_vertical_frame_travel := 0.0
var _max_surface_vertical_frame_travel := 0.0
var _max_balance_offset := 0.0
var _done := false
var _last_player_position := Vector3.ZERO
var _idle_freeze_check := FootIkIdleFreezeClearanceCheck.new()


func setup(player: Player) -> void:
	_player = player
	_player.global_position = RAMP_START_POSITION
	_player.rotation = Vector3.ZERO
	_player.velocity = Vector3.ZERO
	_player.movement_input_override = Vector2.ZERO
	_player.gameplay_action_input_enabled = false
	_previous_xz = _xz()
	_previous_root_y = _player.global_position.y
	_previous_head = _head_position()
	_previous_root = _player.global_position
	_previous_head_relative_y = _previous_head.y - _previous_root.y
	_last_player_position = _player.global_position
	_idle_freeze_check.setup(player)


func drive() -> void:
	if _done:
		return
	_last_player_position = _player.global_position
	var travel := _xz().distance_to(_previous_xz)
	_previous_xz = _xz()
	if _phase == &"ramp_down" or _phase == &"up" or _phase == &"down":
		_sample_stall(travel)
		_sample_trajectory()
	match _phase:
		&"hold_ramp_start":
			_hold_frames -= 1
			if _hold_frames <= 0:
				_phase = &"ramp_down"
				_player.movement_input_override = INPUT_FORWARD
				_previous_xz = _xz()
				_trajectory_initialized = false
		&"ramp_down":
			_player.movement_input_override = INPUT_FORWARD
			if _player.global_position.z <= RAMP_EXIT_Z:
				_begin_hold(&"hold_ramp_exit")
		&"hold_ramp_exit":
			_hold_frames -= 1
			if _hold_frames <= 0:
				_start_idle_freeze_sequence()
		&"hold_idle_top":
			_hold_frames -= 1
			if _hold_frames <= 0:
				_start_stair_sequence()
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
				_idle_freeze_check.run_shared_pelvis_invariant()
				_done = true
				_player.movement_input_override = Vector2.ZERO
			else:
				_tick_hold(&"up", PI)


func is_done() -> bool:
	return _done


func sample_post_solve() -> void:
	if _phase == &"hold_idle_top":
		_idle_freeze_check.sample()


func format_result() -> String:
	var passed := _done and _ascents >= REQUIRED_ASCENTS \
			and _max_stall_frames <= MAX_STALL_FRAMES \
			and _max_vertical_frame_travel <= MAX_VERTICAL_FRAME_TRAVEL \
			and _max_surface_transition_turn <= MAX_SURFACE_TRANSITION_TURN_DEG \
			and (_max_surface_vertical_frame_travel
					<= MAX_SURFACE_VERTICAL_FRAME_TRAVEL)
	var head_p95 := _percentile(_head_turns, 0.95)
	var root_p95 := _percentile(_root_turns, 0.95)
	return ("FOOT_IK_STAIR_REPEAT_CHECK %s ascents=%d max_stall_frames=%d "
			+ "limit=%d max_vertical_frame_m=%.4f vertical_limit_m=%.4f "
			+ "root_turn_p95_deg=%.2f head_turn_p95_deg=%.2f "
			+ "surface_turn_max_deg=%.2f surface_turn_limit_deg=%.2f surface_frame=%d "
			+ "surface_vertical_m=%.4f surface_vertical_limit_m=%.4f "
			+ "floor_max_deg=%.2f "
			+ "head_relative_frame_m=%.4f relative_frame=%d balance_max_m=%.4f "
			+ "head_turn_samples=%d phase=%s position=%s") % [
			"PASS" if passed else "FAIL", _ascents, _max_stall_frames,
			MAX_STALL_FRAMES, _max_vertical_frame_travel, MAX_VERTICAL_FRAME_TRAVEL,
			root_p95, head_p95, _max_surface_transition_turn,
			MAX_SURFACE_TRANSITION_TURN_DEG, _max_surface_transition_frame,
			_max_surface_vertical_frame_travel, MAX_SURFACE_VERTICAL_FRAME_TRAVEL,
			rad_to_deg(_player.floor_max_angle),
			_max_head_relative_frame_m,
			_max_head_relative_frame, _max_balance_offset,
			_head_turns.size(), _phase, _last_player_position]


func format_idle_freeze_result() -> String:
	return _idle_freeze_check.format_result()


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
	_trajectory_initialized = false


func _start_stair_sequence() -> void:
	_phase = &"up"
	_player.global_position = START_POSITION
	_player.rotation = Vector3(0.0, PI, 0.0)
	_player.velocity = Vector3.ZERO
	_player.movement_input_override = INPUT_FORWARD
	_previous_xz = _xz()
	_trajectory_initialized = false


func _start_idle_freeze_sequence() -> void:
	_phase = &"hold_idle_top"
	_hold_frames = IDLE_FREEZE_HOLD_FRAMES
	_player.global_position = IDLE_STAIR_TOP_POSITION
	_player.rotation = Vector3(0.0, deg_to_rad(IDLE_FINAL_YAW), 0.0)
	_player.velocity = Vector3.ZERO
	_player._reset_stair_hover()
	_player.movement_input_override = Vector2.ZERO
	_previous_xz = _xz()
	_trajectory_initialized = false


func _sample_stall(travel: float) -> void:
	if travel < STALL_TRAVEL:
		_stall_frames += 1
		_max_stall_frames = maxi(_max_stall_frames, _stall_frames)
	else:
		_stall_frames = 0


func _sample_trajectory() -> void:
	_trajectory_frame += 1
	var stair_state := _player.get_stair_debug_state()
	_max_balance_offset = maxf(
			_max_balance_offset, absf(float(stair_state["balance_offset_y"])))
	var head := _head_position()
	var root := _player.global_position
	# The player scene needs two modifier evaluations before cached visual
	# bone poses represent the running skeleton; setup-time poses are stale.
	if _trajectory_frame <= 3 or not _trajectory_initialized:
		_previous_root_y = root.y
		_previous_head = head
		_previous_root = root
		_previous_head_relative_y = head.y - root.y
		_trajectory_initialized = true
		return
	var vertical_travel := absf(root.y - _previous_root_y)
	if _phase == &"ramp_down":
		_max_surface_vertical_frame_travel = maxf(
				_max_surface_vertical_frame_travel, vertical_travel)
	else:
		_max_vertical_frame_travel = maxf(_max_vertical_frame_travel, vertical_travel)
	_previous_root_y = root.y
	var delta := head - _previous_head
	_previous_head = head
	var root_delta := root - _previous_root
	_previous_root = root
	if root_delta.length() > 0.0005 and _previous_root_delta.length() > 0.0005:
		var root_turn := rad_to_deg(_previous_root_delta.angle_to(root_delta))
		_root_turns.append(root_turn)
		if _phase == &"ramp_down" and root_turn > _max_surface_transition_turn:
			_max_surface_transition_turn = root_turn
			_max_surface_transition_frame = _trajectory_frame
	if root_delta.length() > 0.0005:
		_previous_root_delta = root_delta
	var head_relative_y := head.y - root.y
	var relative_change := absf(head_relative_y - _previous_head_relative_y)
	if relative_change > _max_head_relative_frame_m:
		_max_head_relative_frame_m = relative_change
		_max_head_relative_frame = _trajectory_frame
	_previous_head_relative_y = head_relative_y
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
