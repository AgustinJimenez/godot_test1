extends RefCounted
## Turn-in-place regression (v1's "rotation snap" idea): stand still on the stairs and step the
## body's yaw 2 degrees at a time through a full circle. Every step swings the animated feet to new
## spots against the treads and risers, which exposed a foot lifted 10 cm onto the next riser (heel
## 8 cm under the tread). Graded like the other idle replays (tip / heel clip and float against the
## real surface) plus a limit on how far a foot may move in ONE frame once a turn has settled.
## Offsets: `--stairs-turn=dz:x:yaw[:quick]` puts the riser under the foot anywhere.

const STEP_DEG := 2.0
const HOLD_FRAMES := 10
const SETTLE_FRAMES := 2 # the snap frame(s) themselves are not graded
const START_YAW_DEG := 87.4
const SNAP_DEG := 40.0 # the fast turns after the fine sweep
const SNAP_HOLD_FRAMES := 14
# m in one frame after the settle (a step is 2.5 cm/frame plus its lift arc; was 0.28 m unstepped).
const STEPPING_RUN_LIMIT := 120 # frames a foot may keep stepping in a row (a smooth turn is 120)
const FOOT_STEP_LIMIT := 0.07

const SMOOTH_FRAMES := 45 # frames per smooth turn (3, 8 and 20 deg/frame, both ways)


## Phases: fine steps around the circle, big 40 degree snaps, then SMOOTH turns (a constant yaw rate
## every frame, like the mouse) in both directions at three speeds.
static func replay(start_yaw := START_YAW_DEG, quick := false) -> Array:
	var steps: Array = [{"name": "idle_start", "input": Vector2.ZERO, "frames": 60, "grade": false}]
	var fine := 6.0 if quick else STEP_DEG
	var hold := 6 if quick else HOLD_FRAMES
	for index in int(360.0 / fine):
		steps.append({"name": "idle_turn_%03d" % index, "input": Vector2.ZERO,
				"frames": hold, "grade": true, "settle": SETTLE_FRAMES,
				"yaw": start_yaw + float(index) * fine})
	# big fast snaps (a quick turn on the spot): the body carries the feet with it - that is NOT a
	# step, and a stepper that treats it as one drags the foot behind the turn (the loop)
	for index in int(360.0 / SNAP_DEG):
		steps.append({"name": "idle_snap_%03d" % index, "input": Vector2.ZERO,
				"frames": SNAP_HOLD_FRAMES, "grade": true, "settle": SETTLE_FRAMES,
				"yaw": start_yaw + float(index) * SNAP_DEG})
	# smooth turns are KNOWN OPEN (item 15): only the fuzz (`quick`) runs them, the suite does not
	for rate: float in ([3.0, -3.0, 8.0, -8.0, 20.0, -20.0] if quick else [] as Array[float]):
		steps.append({"name": "idle_smooth_%+d" % int(rate), "input": Vector2.ZERO,
				"frames": SMOOTH_FRAMES, "grade": true, "settle": SETTLE_FRAMES,
				"yaw_rate": rate})
	return steps


## Largest one-frame move of `pos` for `side` since the last call (0 when not graded). Two guards
## fold into it as a failing 9.9: (1) a foot walking a step is skipped by the tip / heel grading, so
## it must not stay in one for more than STEPPING_RUN_LIMIT frames in a row (the limiter once never
## finished and vibrated the foot); (2) `pose_fault`: the knee behind the leg line, past the flexion
## cap or the swing cone.
static func step(previous: Dictionary, side: StringName, pos: Vector3, graded: bool,
		stepping: bool, pose_fault: float) -> float:
	var moved := 0.0
	if graded:
		var key := "run_%s" % side
		previous[key] = int(previous.get(key, 0)) + 1 if stepping else 0
		if previous.has(side):
			moved = pos.distance_to(previous[side] as Vector3)
		var why := ""
		if int(previous[key]) > STEPPING_RUN_LIMIT:
			why = "stepping %d frames in a row" % int(previous[key])
		elif pose_fault > 0.0:
			why = "impossible leg pose (knee wrong way / past a cap)"
		elif moved > FOOT_STEP_LIMIT:
			why = "foot moved %.3f m against the body in one frame" % moved
		# the first of each kind, once per run: what to look at when the fuzz reports a fail
		if why != "" and not previous.has("why_" + why.split(" ")[0]):
			previous["why_" + why.split(" ")[0]] = true
			print("TURN_FAULT frame=%d side=%s %s" % [Engine.get_physics_frames(), side, why])
		if int(previous[key]) > STEPPING_RUN_LIMIT or pose_fault > 0.0:
			moved = 9.9
	previous[side] = pos
	return moved
