class_name FootIKV2GroundFilter
extends RefCounted
## Floor height under a foot, filtered per side: a tread edge flips the raw sample every frame, so a
## HIGHER floor is believed at once (a late rise clips the toe), a lower one only after it was the
## answer several frames in a row, and then at a limited rate.

## The floor height a foot chases changes at most this fast (m/s): a 0.35 m riser takes ~7 frames.
const RATE := 3.0
## A different floor level must be the answer this many frames in a row before the foot follows.
const HOLD_FRAMES := 3
const SAME_LEVEL := 0.04
## Changes up to this per frame (a slope) are followed exactly; bigger steps rate-limited.
const FOLLOW := 0.06
const SNAP := 0.45

var state: Dictionary = {} # side -> filtered height
var _pending: Dictionary = {}
var _raw: Dictionary = {}
var _frame: Dictionary = {}


func height(side: StringName, raw: float) -> float:
	var frame_now := Engine.get_physics_frames()
	if int(_frame.get(side, -1)) == frame_now:
		return float(state.get(side, raw))
	_frame[side] = frame_now
	_raw[side] = raw
	if not state.has(side):
		state[side] = raw
		return raw
	var current: float = state[side]
	var gap := absf(raw - current)
	if gap <= FOLLOW or gap > SNAP or raw > current:
		# a slope, a landing/teleport, or a HIGHER tread (late clips the toe); a flicker DOWN waits.
		state[side] = raw
		_pending.erase(side)
		return raw
	# A different tread level must be the answer HOLD_FRAMES in a row before it is believed.
	var pending: Dictionary = _pending.get(side, {})
	if not pending.is_empty() and absf(raw - float(pending["level"])) <= SAME_LEVEL:
		pending["count"] = int(pending["count"]) + 1
	else:
		pending = {"level": raw, "count": 1}
	_pending[side] = pending
	if int(pending["count"]) >= HOLD_FRAMES:
		state[side] = move_toward(current, raw, RATE / 60.0)
	return float(state[side])


## The re-sample under the LANDED foot: filtered first sample plus the slope-sized rise or fall.
func resample(side: StringName, again_y: float) -> float:
	if not state.has(side):
		return again_y
	var difference := again_y - float(_raw.get(side, again_y))
	if absf(difference) > FOLLOW:
		difference = 0.0
	return float(state[side]) + difference
