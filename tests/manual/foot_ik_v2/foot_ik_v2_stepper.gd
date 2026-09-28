class_name FootIKV2Stepper
extends RefCounted
## A resting foot is never re-seated further than SPEED per physics frame. When a turn crosses a
## riser the flat-fit jumps to the other tread (0.28 m in ONE frame); the foot now walks there as a
## small step - a straight glide with a lift arc so it clears the tread edge.
## Per side it keeps where the foot was at the START of this frame, so a modifier pass repeated
## within a tick gives the same answer.

const SPEED := 0.025 # m/frame (1.5 m/s)
const LIFT := 0.05 # m the foot rises at mid-step

var stepping: Dictionary = {} # side -> walking a step this frame (a graded float is expected)
var _frame: Dictionary = {}
var _was_planted: Dictionary = {}
var _start: Dictionary = {} # side -> foot position at the start of this frame
var _last: Dictionary = {} # side -> where the last pass left the foot
var _length: Dictionary = {} # side -> length of the step in progress


## The position to put the foot at: `here` (where the fit wants it) or a step toward it. `planted`
## false (moving, airborne, swinging) resets everything: a landing is not a step.
func limit(side: StringName, frame: int, here: Vector3, planted: bool) -> Vector3:
	if int(_frame.get(side, -1)) != frame:
		_frame[side] = frame
		var continuing: bool = planted and _was_planted.get(side, false)
		_start[side] = _last.get(side, here) if continuing else here
		_was_planted[side] = planted
		var jump := (_start[side] as Vector3).distance_to(here)
		if not _length.has(side) and jump > SPEED:
			_length[side] = jump
	var start: Vector3 = _start[side]
	var left := start.distance_to(here)
	if not planted or left <= SPEED:
		_length.erase(side)
		_last[side] = here
		stepping[side] = false
		return here
	var moved := start.move_toward(here, SPEED)
	var progress := 1.0 - (left - SPEED) / maxf(float(_length.get(side, left)), 0.001)
	moved.y += LIFT * sin(PI * clampf(progress, 0.0, 1.0))
	_last[side] = moved
	stepping[side] = true
	return moved
