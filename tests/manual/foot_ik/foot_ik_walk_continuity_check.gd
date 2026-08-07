class_name FootIkWalkContinuityCheck
extends RefCounted
## Companion to FootIkPoseContinuityCheck: that one only samples once the
## character is fully idle-settled, explicitly excluding the transition
## right after a rotation change - if the reported shake happens *while*
## actively walking/turning rather than after settling, that check
## structurally can't see it. This one drives the controlled player to walk
## in a slow circle on the ramp and watches for outlier per-frame pops
## during real (not teleported) motion instead.
##
## No fixed distance threshold: normal walk-cycle motion is legitimately
## much larger per frame than idle sway, and varies with the animation's own
## stride rhythm, so an absolute cm limit would either miss slow ramp-up
## pops or false-positive on ordinary stride peaks. Instead this flags a
## frame whose jump is a clear outlier against a short rolling average of
## its own recent frames - a genuine one-frame snap stands out from the
## walk cycle's own smooth rhythm regardless of that rhythm's amplitude.
const ROLLING_WINDOW := 10
const OUTLIER_MULTIPLIER := 4.0
const SETTLE_FRAMES := 20 # let the walk cycle actually start before sampling

var samples := 0
var outliers := 0
var max_ratio := 0.0
var _prev_bone_pos: Dictionary = {} # "side_kind" -> Vector3 (skeleton space)
var _recent_jumps: Dictionary = {} # "side_kind" -> Array[float], most recent last
var _walk_streak := 0
var _turn_direction := 1.0
var _turn_rate := deg_to_rad(18.0) # full circle every 20s


var _spawn_xz := Vector2.ZERO
var _spawn_y := 0.0
var _recentered_this_frame := false


## Continuous forward walk + slow turn would eventually walk the character
## off this ramp's small platform - re-center back over spawn (keeping
## rotation and animation state) whenever it strays too far, so the walk
## cycle and turning keep exercising the same ramp spot indefinitely.
func drive(player: Player, delta: float) -> void:
	if _spawn_xz == Vector2.ZERO and _spawn_y == 0.0:
		_spawn_xz = Vector2(player.global_position.x, player.global_position.z)
		_spawn_y = player.global_position.y
	player.movement_input_override = Vector2(0.0, -1.0)
	player.rotation.y += _turn_direction * _turn_rate * delta
	if absf(player.rotation.y) > PI:
		_turn_direction = -_turn_direction # keep it from winding up unbounded
	var here := Vector2(player.global_position.x, player.global_position.z)
	if here.distance_to(_spawn_xz) > 1.0:
		player.global_position = Vector3(_spawn_xz.x, player.global_position.y, _spawn_xz.y)
		_recentered_this_frame = true


func sample(player: Player, ik: PlayerFootIKModifier) -> void:
	var walking: bool = (player.is_on_floor()
			and player.body.anim_player.current_animation == "moves/unarmed_walk")
	_walk_streak = _walk_streak + 1 if walking else 0
	if _walk_streak <= SETTLE_FRAMES or _recentered_this_frame:
		_prev_bone_pos.clear()
		_recentered_this_frame = false
		return
	for side: StringName in [&"left", &"right"]:
		var key_prefix := str(side) + "_"
		# Swing phase legitimately drops ground_weight/loses contact every
		# stride - that transition is a real, fast, expected gait-cycle event,
		# not the bug this check is after.
		if float(ik._smoothed_ground_weight.get(side, 0.0)) <= 0.0 \
				or ik.debug_step_down.get(side, false) \
				or ik.debug_contact_lost.get(side, false):
			_prev_bone_pos.erase(key_prefix + "hip")
			_prev_bone_pos.erase(key_prefix + "foot")
			continue
		for kind: String in ["hip", "foot"]:
			var bone_idx: int = ik._bone_indices[side][kind]
			var pose: Transform3D = ik._final_bone_poses.get(
					bone_idx, player.skeleton.get_bone_global_pose(bone_idx))
			var key := key_prefix + kind
			if _prev_bone_pos.has(key):
				_check_jump(key, pose.origin.distance_to(_prev_bone_pos[key]))
			_prev_bone_pos[key] = pose.origin


func _check_jump(key: String, jump: float) -> void:
	var recent: Array = _recent_jumps.get(key, [])
	samples += 1
	if recent.size() >= ROLLING_WINDOW:
		var average: float = 0.0
		for value: float in recent:
			average += value
		average /= recent.size()
		if average > 0.0001:
			var ratio := jump / average
			max_ratio = maxf(max_ratio, ratio)
			if ratio > OUTLIER_MULTIPLIER:
				outliers += 1
	recent.append(jump)
	if recent.size() > ROLLING_WINDOW:
		recent.pop_front()
	_recent_jumps[key] = recent


func format_result() -> String:
	return "FOOT_IK_WALK_CONTINUITY_CHECK %s samples=%d outliers=%d max_ratio=%s" % [
		"FAIL" if outliers > 0 else "PASS", samples, outliers, snappedf(max_ratio, 0.01)]
