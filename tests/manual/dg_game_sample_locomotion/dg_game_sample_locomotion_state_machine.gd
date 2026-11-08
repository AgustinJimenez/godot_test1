class_name DGGameSampleLocomotionStateMachine
extends Node
## Ground locomotion state machine modelled on UBendCharacterMovementComponent.
##
## The method names below are deliberate: they are the names of the native
## UFunctions recovered from DGGameSample.exe (`WantsToTransitionIdleToMove`,
## `CanEarlyOutAnyTurnInProgress`, ...). Keeping them makes the port auditable
## against `symbols/ubendcharactermovementcomponent-ufunctions.txt`.
##
## States: Idle, Move, Turn (turn in place), Air.
## The body writes the input snapshot each tick, then calls `tick()`, then
## applies `yaw_delta()` while the machine reports Turn.

signal state_changed(previous: int, current: int)

enum State { IDLE, MOVE, TURN, AIR }

const STATE_NAMES := {
	State.IDLE: &"Idle",
	State.MOVE: &"Move",
	State.TURN: &"Turn",
	State.AIR: &"Air",
}

var tuning: DGGameSampleLocomotionTuning

# --- Input snapshot, rewritten by the body every physics tick ---------------
## 0..1 magnitude of the movement request.
var input_magnitude := 0.0
## Signed yaw error between capsule facing and requested heading, in degrees.
var angle_to_input_deg := 0.0
## Current planar speed in m/s.
var planar_speed := 0.0
var on_floor := true

# --- Turn-in-place bookkeeping ---------------------------------------------
var state: State = State.IDLE
## Absolute yaw the current turn is rotating toward (radians).
var turn_target_yaw := 0.0
var turn_elapsed := 0.0
var turn_duration := 0.0
## Signed heading error the current turn is correcting, in degrees.
## Positive = left (counter-clockwise), matching Godot's +Y rotation.
var turn_angle_deg := 0.0

var _turn_windup := 0.0
var _turn_settle := 0.0
var _turn_delta_yaw := 0.0
var _turn_applied_yaw := 0.0
var _tap_timer := 0.0
var _tap_queued := false
var _state_before_air := State.IDLE


func _ready() -> void:
	if tuning == null:
		tuning = DGGameSampleLocomotionTuning.new()


## Advance the state machine by one physics step.
func tick(delta: float) -> void:
	_tap_timer = maxf(0.0, _tap_timer - delta)

	if not on_floor:
		if state != State.AIR:
			_state_before_air = state
			_set_state(State.AIR)
		return

	if state == State.TURN:
		turn_elapsed += delta
		if _can_finish_turn_in_progress():
			_finish_turn()
		return

	if state == State.AIR:
		# Landed this frame: pick the state the input asks for right now.
		if _wants_to_transition_idle_to_turn():
			_begin_turn()
		elif _wants_to_transition_idle_to_move():
			_set_state(State.MOVE)
		else:
			_set_state(State.IDLE)
		return

	if state == State.MOVE:
		if _wants_to_transition_move_to_turn():
			_begin_turn()
		elif _wants_to_transition_move_to_idle():
			_set_state(State.IDLE)
		return

	# Idle
	if _wants_to_transition_idle_to_turn():
		_begin_turn()
	elif _wants_to_transition_idle_to_move():
		_set_state(State.MOVE)


## Yaw change (radians) to apply this frame. Non-zero only in Turn.
func yaw_delta(_delta: float) -> float:
	if state != State.TURN:
		return 0.0
	var rotation_time := maxf(0.001, turn_duration - _turn_windup - _turn_settle)
	var progress := clampf((turn_elapsed - _turn_windup) / rotation_time, 0.0, 1.0)
	var eased := smoothstep(0.0, 1.0, progress)
	var target := _turn_delta_yaw * eased
	var step := target - _turn_applied_yaw
	_turn_applied_yaw = target
	return step


## Body-facing name of the current state, used by the HUD and the tests.
func state_name() -> StringName:
	return STATE_NAMES[state]


func reset() -> void:
	turn_elapsed = 0.0
	turn_duration = 0.0
	_tap_timer = 0.0
	_tap_queued = false
	_set_state(State.IDLE)


## Feed a fresh press of the movement input (used for turn-tap chaining).
func notify_move_input_started() -> void:
	if _tap_timer > 0.0:
		_tap_queued = true


## Feed a release of the movement input (starts the tap window).
func notify_move_input_ended() -> void:
	if state == State.TURN and turn_elapsed < turn_duration * 0.6:
		_tap_timer = tuning.turn_in_place_tap_window_s


## True while a queued turn tap is waiting to be consumed.
func has_turn_in_place_tap_request() -> bool:
	return _tap_queued


func _wants_to_transition_idle_to_move() -> bool:
	return (
		input_magnitude > tuning.input_deadzone
		and absf(angle_to_input_deg) < tuning.turn_in_place_enter_deg
	)


func _wants_to_transition_idle_to_turn() -> bool:
	return (
		input_magnitude > tuning.input_deadzone * 1.5
		and absf(angle_to_input_deg) >= tuning.turn_in_place_enter_deg
	)


func _wants_to_transition_move_to_idle() -> bool:
	return (
		input_magnitude < tuning.input_deadzone
		and planar_speed < tuning.idle_speed_threshold
	)


func _wants_to_transition_move_to_turn() -> bool:
	return (
		input_magnitude > tuning.input_deadzone * 1.5
		and planar_speed < tuning.move_to_turn_max_speed
		and absf(angle_to_input_deg) >= tuning.move_to_turn_min_angle_deg
	)


## Mirrors CanEarlyOutAnyTurnInProgress: input release may cancel a turn, but
## only after the shortest legible hold so taps do not flicker the state.
func _can_early_out_any_turn_in_progress() -> bool:
	if turn_elapsed < tuning.turn_in_place_min_hold_s:
		return false
	if input_magnitude < tuning.input_deadzone:
		return true
	var remaining := _turn_delta_yaw - _turn_applied_yaw
	return absf(remaining) < deg_to_rad(tuning.turn_in_place_early_out_deg)


func _can_finish_turn_in_progress() -> bool:
	return turn_elapsed >= turn_duration or _can_early_out_any_turn_in_progress()


func _begin_turn() -> void:
	var tuning_rate := maxf(1.0, tuning.turn_in_place_rate_deg_per_s)
	_turn_delta_yaw = deg_to_rad(angle_to_input_deg)
	turn_angle_deg = angle_to_input_deg
	_turn_applied_yaw = 0.0
	_turn_windup = tuning.turn_in_place_windup_s
	_turn_settle = tuning.turn_in_place_settle_s
	var rotation_time := absf(angle_to_input_deg) / tuning_rate
	turn_elapsed = 0.0
	turn_duration = _turn_windup + rotation_time + _turn_settle
	_turn_applied_yaw = 0.0
	_set_state(State.TURN)


func _finish_turn() -> void:
	turn_target_yaw = 0.0
	if _tap_queued and _wants_to_transition_idle_to_turn():
		_tap_queued = false
		_begin_turn()
		return
	_tap_queued = false
	if input_magnitude > tuning.input_deadzone:
		_set_state(State.MOVE)
	else:
		_set_state(State.IDLE)


func _set_state(next: State) -> void:
	if next == state:
		return
	var previous := state
	state = next
	state_changed.emit(previous, next)
