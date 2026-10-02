extends RefCounted
## Joint angular speed limit, v1's `_limit_correction` idea: the IK's correction of a joint (its
## rotation away from the animated pose) may change by at most `max_deg` per physics frame, so a
## joint never snaps however the target jumps. A bone not corrected last frame (a swing foot that
## was released, a teleport) restarts from the new value with no limit: there is nothing to follow.
## Per bone: the correction at the end of the previous frame, and the latest one this frame (a
## pass can repeat within a tick, and each repeat must start from the same previous frame).

var _previous: Dictionary = {} # bone -> Quaternion at the end of the last completed frame
var _latest: Dictionary = {} # bone -> Quaternion from the latest pass
var _frame: Dictionary = {} # bone -> physics frame of `_latest`


func limit(bone: int, frame: int, correction: Quaternion, max_deg: float) -> Quaternion:
	var seen := int(_frame.get(bone, -100))
	if seen != frame:
		if seen == frame - 1:
			_previous[bone] = _latest[bone]
		else:
			_previous.erase(bone)
		_frame[bone] = frame
	var result := correction
	if max_deg > 0.0 and _previous.has(bone):
		var before: Quaternion = _previous[bone]
		var angle := rad_to_deg(before.angle_to(correction))
		if angle > max_deg:
			result = before.slerp(correction, max_deg / angle)
	_latest[bone] = result
	return result
