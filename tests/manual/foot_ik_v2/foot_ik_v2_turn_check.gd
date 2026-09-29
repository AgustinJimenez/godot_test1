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
const START_YAW_DEG := 87.4
const SNAP_DEG := 40.0 # the fast turns after the fine sweep
const SNAP_HOLD_FRAMES := 14
# m in one frame after the settle (a step is 2.5 cm/frame plus its lift arc; was 0.28 m unstepped).
const STEPPING_SHARE_LIMIT := 0.15 # of graded foot-frames a foot may spend walking a step
const FOOT_STEP_LIMIT := 0.07


static func replay() -> Array:
	var steps: Array = [{"name": "idle_start", "input": Vector2.ZERO, "frames": 60, "grade": false}]
	for index in int(360.0 / STEP_DEG):
		steps.append({"name": "idle_turn_%03d" % index, "input": Vector2.ZERO,
				"frames": HOLD_FRAMES, "grade": true, "settle": SETTLE_FRAMES,
				"yaw": START_YAW_DEG + float(index) * STEP_DEG})
	# then big fast snaps (a quick turn on the spot): the body carries the feet with it - that is
	# NOT a step, and a stepper that treats it as one drags the foot behind the turn (the loop)
	for index in int(360.0 / SNAP_DEG):
		steps.append({"name": "idle_snap_%03d" % index, "input": Vector2.ZERO,
				"frames": SNAP_HOLD_FRAMES, "grade": true, "settle": SETTLE_FRAMES,
				"yaw": START_YAW_DEG + float(index) * SNAP_DEG})
	return steps


## Largest one-frame move of `pos` for `side` since the last call (0 when not graded). Two guards
## fold into it as a failing 9.9: (1) a foot walking a step is skipped by the tip / heel grading,
## so it must not step for most of the sweep (the limiter once never finished and vibrated the
## foot): past STEPPING_SHARE_LIMIT of the graded frames; (2) the knee bending BACKWARD
## (`pose_fault`: knee behind the leg line, past the flexion cap or the swing cone).
static func step(previous: Dictionary, side: StringName, pos: Vector3, graded: bool,
		stepping: bool, pose_fault: float) -> float:
	var moved := 0.0
	if graded:
		previous["frames"] = int(previous.get("frames", 0)) + 1
		previous["stepping"] = int(previous.get("stepping", 0)) + (1 if stepping else 0)
		if previous.has(side):
			moved = pos.distance_to(previous[side] as Vector3)
		if int(previous["frames"]) > 200 and float(previous["stepping"]) > (
				STEPPING_SHARE_LIMIT * float(previous["frames"])) or pose_fault > 0.0:
			moved = 9.9
	previous[side] = pos
	return moved
