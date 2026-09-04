class_name FootIkIdleSeamCheck
extends RefCounted
## Regression for a live idle-loop seam where a supported left foot moved
## despite unchanged root, target, ownership, and IK weight.

const SETTLE_FRAMES := 120
const SAMPLE_FRAMES := 330
const FOOT_STEP_LIMIT := 0.025
const KNEE_STEP_LIMIT := 0.012
const KNEE_FLEX_STEP_LIMIT_DEG := 3.0

var enabled := "--idle-ik-seam-check" in OS.get_cmdline_user_args()
var _frame := 0
var _previous_left_foot := Vector3(INF, INF, INF)
var _previous_left_knee := Vector3(INF, INF, INF)
var _previous_animation_position := -1.0
var _seam_window_frames := 0
var _max_left_step := 0.0
var _max_left_step_frame := -1
var _max_left_knee_step := 0.0
var _max_left_knee_step_frame := -1
var _previous_left_knee_flexion := INF
var _max_left_knee_flexion_step := 0.0
var _max_left_knee_flexion_step_frame := -1


func advance(player: Player) -> void:
	if not enabled:
		return
	_frame += 1
	call_deferred(&"_sample", player)


func _sample(player: Player) -> void:
	var ik := _find_foot_ik(player)
	if ik == null or ik._bone_indices.is_empty():
		return
	var hip_index: int = ik._bone_indices[&"left"][&"hip"]
	var knee_index: int = ik._bone_indices[&"left"][&"knee"]
	var foot_index: int = ik._bone_indices[&"left"][&"foot"]
	var hip_skeleton := ik.get_final_bone_global_pose(hip_index).origin
	var knee_skeleton := ik.get_final_bone_global_pose(knee_index).origin
	var foot_skeleton := ik.get_final_bone_global_pose(foot_index).origin
	var foot: Vector3 = player.skeleton.global_transform * foot_skeleton
	var knee: Vector3 = player.skeleton.global_transform * knee_skeleton
	var knee_flexion := rad_to_deg(
			(knee_skeleton - hip_skeleton).angle_to(foot_skeleton - knee_skeleton))
	var animation_position: float = player.body.anim_player.current_animation_position
	if (_previous_animation_position >= 0.0
			and animation_position < _previous_animation_position - 0.05):
		_seam_window_frames = 12
	if _frame > SETTLE_FRAMES and _previous_left_foot.is_finite():
		var movement := foot.distance_to(_previous_left_foot)
		if movement > _max_left_step:
			_max_left_step = movement
			_max_left_step_frame = _frame
		if _seam_window_frames > 0 and _previous_left_knee.is_finite():
			var knee_movement := knee.distance_to(_previous_left_knee)
			if knee_movement > _max_left_knee_step:
				_max_left_knee_step = knee_movement
				_max_left_knee_step_frame = _frame
		if _seam_window_frames > 0 and is_finite(_previous_left_knee_flexion):
			var flexion_step := absf(knee_flexion - _previous_left_knee_flexion)
			if flexion_step > _max_left_knee_flexion_step:
				_max_left_knee_flexion_step = flexion_step
				_max_left_knee_flexion_step_frame = _frame
	_previous_left_foot = foot
	_previous_left_knee = knee
	_previous_left_knee_flexion = knee_flexion
	_previous_animation_position = animation_position
	_seam_window_frames = maxi(0, _seam_window_frames - 1)
	if _frame >= SAMPLE_FRAMES:
		var passed := (_max_left_step <= FOOT_STEP_LIMIT
				and _max_left_knee_step <= KNEE_STEP_LIMIT
				and _max_left_knee_flexion_step <= KNEE_FLEX_STEP_LIMIT_DEG)
		var result := "PASS" if passed else "FAIL"
		print(("FOOT_IK_IDLE_SEAM_CHECK %s max_left_step_m=%.4f frame=%d limit_m=%.4f "
				+ "max_knee_step_m=%.4f knee_step_frame=%d knee_step_limit_m=%.4f "
				+ "max_knee_flex_step_deg=%.2f knee_flex_frame=%d knee_flex_limit_deg=%.2f") % [
				result, _max_left_step, _max_left_step_frame, FOOT_STEP_LIMIT,
				_max_left_knee_step, _max_left_knee_step_frame, KNEE_STEP_LIMIT,
				_max_left_knee_flexion_step, _max_left_knee_flexion_step_frame,
				KNEE_FLEX_STEP_LIMIT_DEG])
		player.get_tree().quit(0 if result == "PASS" else 1)


func _find_foot_ik(player: Player) -> PlayerFootIKModifier:
	for child in player.skeleton.get_children():
		if child is PlayerFootIKModifier:
			return child
	return null
