class_name FootIKV2KneeHint
extends RefCounted
## The direction a RESTING knee bends towards: the animated knee's own direction from the hip, low-
## passed. The animation's bend is kept (the old rest-pole hint put the idle knee 9 cm off the
## animation), but its hip sway is averaged out, so a planted foot keeps a steady knee.

const RATE := 0.4 # per second: ~2.5 s to settle (0.8 swayed the knee 5 cm, limit 4)
const WALK_RATE := 12.0 # walking: tracks the animated knee, so start/stop does not snap

var _direction: Dictionary = {}


## A point on the hint direction (hip + unit direction), like the solver expects.
func steady(side: StringName, hip: Vector3, knee: Vector3, delta: float, walk: float) -> Vector3:
	var now := (knee - hip).normalized()
	var current: Vector3 = _direction.get(side, now)
	var rate := lerpf(RATE, WALK_RATE, walk)
	current = current.slerp(now, 1.0 - exp(-rate * delta)) if current != now else now
	_direction[side] = current
	return hip + current
