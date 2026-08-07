class_name FootIkPoseContinuityCheck
extends RefCounted
## Catches the idle-on-a-ramp shake reported live: a rendered hip/foot bone
## popping between physics frames while the controlled player stands still,
## typically right on an animation loop-reset. Split out purely to keep
## foot_ik_preview.gd under the project's max-file-lines cap.
##
## Skeleton-local (not world) bone positions, so real root movement never
## counts - only pops in the leg pose itself, relative to the skeleton, are
## the signal this is after. Samples only while genuinely idle: the
## harness's own automated jump/land (for the airborne check) is fast,
## legitimate motion that would otherwise register as a false failure here.
## Also skips a leg with zero ground_weight (pure animated pose, same as IK
## off entirely - already confirmed not to shake; covers the separate,
## already-logged ramp-edge overreach leg in CURRENT_TASK_IK_FOOT.md) or
## mid step_down (settling toward a distant lower surface legitimately
## moves the foot a lot per frame - see step_down_pelvis_drop's own doc).
const POSE_JUMP_LIMIT := 0.02 # meters/frame - well above idle sway, below a step
const IDLE_SETTLE_FRAMES := 30 # let ground_weight fully ramp up before sampling
const INSPECTION_ANGLE_HOLD_TIME := 1.25 # matches the CASES row's own hold time

var samples := 0
var max_jump := 0.0
var failed := false
var _prev_bone_pos: Dictionary = {} # "side_kind" -> Vector3 (skeleton space)
var _idle_streak := 0
var _inspection_angle := 0
var _inspection_timer := INSPECTION_ANGLE_HOLD_TIME


## Reported shake was angle-dependent on a ramp, not reproduced at a single
## fixed rotation - cycle through the same yaws the CASES row inspects at.
## A rotation change legitimately moves every bone, so restart the settle
## window (see notify_rotation_changed) instead of comparing across it.
func maybe_rotate(player: Player, delta: float, yaws: Array[float]) -> void:
	_inspection_timer -= delta
	if _inspection_timer > 0.0:
		return
	_inspection_angle = (_inspection_angle + 1) % yaws.size()
	player.rotation = Vector3(0.0, yaws[_inspection_angle], 0.0)
	_inspection_timer = INSPECTION_ANGLE_HOLD_TIME
	_idle_streak = 0
	_prev_bone_pos.clear()


func sample(player: Player, ik: PlayerFootIKModifier) -> void:
	var idle: bool = (player.is_on_floor() and ik._landing_grace_time <= 0.0
			and player.body.anim_player.current_animation == "moves/unarmed_idle")
	_idle_streak = _idle_streak + 1 if idle else 0
	if _idle_streak <= IDLE_SETTLE_FRAMES:
		_prev_bone_pos.clear() # Don't compare across the excluded gap.
		return
	for side: StringName in [&"left", &"right"]:
		var key_prefix := str(side) + "_"
		if float(ik._smoothed_ground_weight.get(side, 0.0)) <= 0.0 \
				or ik.debug_step_down.get(side, false):
			_prev_bone_pos.erase(key_prefix + "hip")
			_prev_bone_pos.erase(key_prefix + "foot")
			continue
		for kind: String in ["hip", "foot"]:
			var bone_idx: int = ik._bone_indices[side][kind]
			var pose: Transform3D = ik._final_bone_poses.get(
					bone_idx, player.skeleton.get_bone_global_pose(bone_idx))
			var key := key_prefix + kind
			if _prev_bone_pos.has(key):
				var jump: float = pose.origin.distance_to(_prev_bone_pos[key])
				samples += 1
				max_jump = maxf(max_jump, jump)
				if jump > POSE_JUMP_LIMIT:
					failed = true
			_prev_bone_pos[key] = pose.origin


func format_result() -> String:
	return "FOOT_IK_POSE_CONTINUITY_CHECK %s samples=%d max_jump_m=%s limit_m=%s" % [
		"FAIL" if failed else "PASS", samples, snappedf(max_jump, 0.000001), POSE_JUMP_LIMIT]
