class_name FootIkIdleSeamCheck
extends RefCounted
## Regression for a live idle-loop seam where a supported left foot moved
## despite unchanged root, target, ownership, and IK weight.

const SETTLE_FRAMES := 120
const SAMPLE_FRAMES := 330
const FOOT_STEP_LIMIT := 0.025

var enabled := "--idle-ik-seam-check" in OS.get_cmdline_user_args()
var _frame := 0
var _previous_left_foot := Vector3(INF, INF, INF)
var _max_left_step := 0.0
var _max_left_step_frame := -1


func advance(player: Player) -> void:
	if not enabled:
		return
	_frame += 1
	call_deferred(&"_sample", player)


func _sample(player: Player) -> void:
	var ik := _find_foot_ik(player)
	if ik == null or ik._bone_indices.is_empty():
		return
	var foot_index: int = ik._bone_indices[&"left"][&"foot"]
	var foot: Vector3 = player.skeleton.global_transform \
			* ik.get_final_bone_global_pose(foot_index).origin
	if _frame > SETTLE_FRAMES and _previous_left_foot.is_finite():
		var movement := foot.distance_to(_previous_left_foot)
		if movement > _max_left_step:
			_max_left_step = movement
			_max_left_step_frame = _frame
	_previous_left_foot = foot
	if _frame >= SAMPLE_FRAMES:
		var result := "PASS" if _max_left_step <= FOOT_STEP_LIMIT else "FAIL"
		print("FOOT_IK_IDLE_SEAM_CHECK %s max_left_step_m=%.4f frame=%d limit_m=%.4f" % [
				result, _max_left_step, _max_left_step_frame, FOOT_STEP_LIMIT])
		player.get_tree().quit(0 if result == "PASS" else 1)


func _find_foot_ik(player: Player) -> PlayerFootIKModifier:
	for child in player.skeleton.get_children():
		if child is PlayerFootIKModifier:
			return child
	return null
