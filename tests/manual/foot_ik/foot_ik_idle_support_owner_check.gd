extends Node3D
## Captured stationary stair stance: animation probes must not reopen landing ownership.

var _player: Player
var _ik: PlayerFootIKModifier
var _frame := 0
var _switches := 0
var _previous_surface := INF
var _max_clearance := 0.0
var _max_step := 0.0
var _previous_foot := Vector3.ZERO


func _ready() -> void:
	_player = $FootIkPreview/Player
	_player.global_position = Vector3(14.04099, 1.4, 1.753284)
	_player.rotation.y = deg_to_rad(-10.2225323948938)
	_player.movement_input_override = Vector2.ZERO
	for child: Node in _player.body.skeleton.get_children():
		if child is PlayerFootIKModifier:
			_ik = child
	_ik.reset_runtime_state()


func _physics_process(_delta: float) -> void:
	_frame += 1
	if _frame <= 180:
		return
	var side := &"left"
	var surface: Vector3 = _ik._smoothed_target.get(side, Vector3.ZERO)
	var bone: int = _ik._bone_indices[side][&"foot"]
	var pose: Transform3D = _ik.get_final_bone_global_pose(bone)
	var foot := _player.body.skeleton.global_transform * pose.origin
	var offset: float = _ik._ground_sampler.debug_effective_offset.get(side, 0.0)
	_max_clearance = maxf(_max_clearance, absf(foot.y - surface.y - offset))
	if is_finite(_previous_surface):
		if absf(surface.y - _previous_surface) > 0.1:
			_switches += 1
		_max_step = maxf(_max_step, foot.distance_to(_previous_foot))
	_previous_surface = surface.y
	_previous_foot = foot
	if _frame >= 480:
		var passed := _switches == 0 and _max_clearance <= 0.05 and _max_step <= 0.035
		var settings: FootIKRuntimeSettings = _ik._ground_sampler._settings
		passed = passed and settings.allows_support_height_difference(0.350001)
		passed = passed and not settings.allows_support_height_difference(0.36)
		print("FOOT_IK_IDLE_SUPPORT_OWNER_CHECK %s switches=%d clearance=%.6f step=%.6f" % [
				"PASS" if passed else "FAIL", _switches, _max_clearance, _max_step])
		get_tree().quit(0 if passed else 1)
