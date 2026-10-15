class_name PlayerLedgeCommit
extends RefCounted
## The ledge safety refuses to walk off a big drop, which made a high platform impossible to leave
## on purpose. Holding the stick into the drop for HOLD_SECONDS commits to the fall: the safety
## lets go until the body has left the floor (or SPAN_SECONDS passed without it leaving).

const HOLD_SECONDS := 0.5 # s of pushing into a blocked drop
const SPAN_SECONDS := 1.5 # s the commitment lasts if the body does not leave the floor

var walking_off := false
var _held := 0.0
var _span := 0.0
var _left_floor := false


## Call once a physics frame before the safety runs; true while the fall is committed.
func update(player: Player, delta: float) -> bool:
	if walking_off:
		_span += delta
		_left_floor = _left_floor or not player.is_on_floor()
		if (_left_floor and player.is_on_floor()) or _span > SPAN_SECONDS:
			walking_off = false
			_held = 0.0
		return walking_off
	var pushing: bool = player._ledge_direction_blocked and player._smoothed_input_dir.length() > 0.5
	_held = _held + delta if pushing else 0.0
	if _held >= HOLD_SECONDS:
		walking_off = true
		_span = 0.0
		_left_floor = false
	return walking_off
