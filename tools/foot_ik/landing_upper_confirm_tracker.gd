class_name LandingUpperConfirmTracker
extends RefCounted
## Tracks consecutive-frame confirmation that a foot's raw contact has moved onto a genuinely
## higher surface, requiring the SAME candidate across the whole streak - not just any higher
## point each frame. A rotating body can otherwise sweep the raw raycast smoothly from one
## tread onto a neighboring one, satisfying a naive frame-to-frame check without the foot ever
## really settling on one real surface (AGENT_TASKS/019's "clipped out of nowhere").

const CANDIDATE_TOLERANCE := 0.01

var _frames: Dictionary = {} # side -> int
var _candidate: Dictionary = {} # side -> Vector3


func reset() -> void:
	_frames.clear()
	_candidate.clear()


func reset_side(side: StringName) -> void:
	_frames.erase(side)
	_candidate.erase(side)


## Advances the streak for `side` toward `raw_surface`; true once `hold_frames` consecutive,
## mutually-consistent confirmations have accumulated (and clears the streak in that case).
func confirm(side: StringName, raw_surface: Vector3, hold_frames: int) -> bool:
	var frames: int = int(_frames.get(side, 0))
	var candidate: Vector3 = raw_surface if frames == 0 else _candidate.get(side, raw_surface)
	if raw_surface.distance_to(candidate) > CANDIDATE_TOLERANCE:
		frames = 0
		candidate = raw_surface
	_candidate[side] = candidate
	frames += 1
	_frames[side] = frames
	if frames >= hold_frames:
		reset_side(side)
		return true
	return false
