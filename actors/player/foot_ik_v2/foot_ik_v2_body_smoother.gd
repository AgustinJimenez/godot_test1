class_name FootIKV2BodySmoother
extends RefCounted
## The visible body height follows the capsule in two stages, like the GALS game's root smoother
## (RootBaseSmoother, found in the reference pack): the capsule's climb SPEED is smoothed first
## (rate 20/s), the height integrates that, then it is pulled to the capsule (rate 7/s). A stair
## step that lifts the capsule in a few frames no longer lifts the hips in as few frames.

const VELOCITY_RATE := 20.0

var _y := 0.0
var _velocity := 0.0
var _last_target := 0.0


func reset(target: float) -> float:
	_y = target
	_velocity = 0.0
	_last_target = target
	return _y


func follow(target: float, delta: float, position_rate: float, max_lag: float) -> float:
	var speed := (target - _last_target) / maxf(delta, 0.0001)
	_last_target = target
	_velocity += (speed - _velocity) * (1.0 - exp(-VELOCITY_RATE * delta))
	_y += _velocity * delta
	_y += (target - _y) * (1.0 - exp(-position_rate * delta))
	_y = clampf(_y, target - max_lag, target) # never above the capsule, never far below it
	return _y
