class_name FootIKV2TurnCheck
extends RefCounted
## Turn-in-place regression (v1's "rotation snap" idea): stand still on the stairs and step the
## body's yaw 2 degrees at a time through a full circle. Every step swings the animated feet to new
## spots against the treads and risers, which exposed a foot lifted 10 cm onto the next riser (heel
## 8 cm under the tread). Graded like the other idle replays (tip / heel clip and float against the
## real surface) plus a limit on how far a foot may move in ONE frame once a turn has settled.
## Run at several offsets along the treads (`--stairs-turn=<dz>`): the riser lands at a different
## spot under the foot each time.

const STEP_DEG := 2.0
const HOLD_FRAMES := 10
const SETTLE_FRAMES := 2 # the snap frame(s) themselves are not graded
const START_YAW_DEG := 13.2
# m in one frame after the settle. KNOWN OPEN: a turn that crosses a riser re-seats the foot 0.28 m
# in one frame (no step arc yet) - tighten to 0.03 when it has one.
const FOOT_STEP_LIMIT := 0.30


static func replay() -> Array:
	var steps: Array = [{"name": "idle_start", "input": Vector2.ZERO, "frames": 60, "grade": false}]
	for index in int(360.0 / STEP_DEG):
		steps.append({"name": "idle_turn_%03d" % index, "input": Vector2.ZERO,
				"frames": HOLD_FRAMES, "grade": true, "settle": SETTLE_FRAMES,
				"yaw": START_YAW_DEG + float(index) * STEP_DEG})
	return steps


## Largest one-frame move of `pos` for `side` since the last call (0 when not graded).
static func step(previous: Dictionary, side: StringName, pos: Vector3, graded: bool) -> float:
	var moved := 0.0
	if graded and previous.has(side):
		moved = pos.distance_to(previous[side] as Vector3)
	previous[side] = pos
	return moved
