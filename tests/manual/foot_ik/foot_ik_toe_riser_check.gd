extends Node3D
## Live lower-tread latch: supported ankles must not leave toes inside the next riser.

var _player: Player
var _ik: PlayerFootIKModifier
var _frame := 0
var _clipped := 0
var _max_step := 0.0
var _max_contact_error := 0.0
var _previous := Vector3.ZERO


func _ready() -> void:
	_player = $FootIkPreview/Player
	_player.global_position = Vector3(13.92332, 1.040266, 1.042998)
	_player.rotation.y = deg_to_rad(-151.260740981699)
	_player.movement_input_override = Vector2.ZERO
	for child: Node in _player.body.skeleton.get_children():
		if child is PlayerFootIKModifier:
			_ik = child
	_ik.reset_runtime_state()


func _physics_process(_delta: float) -> void:
	_frame += 1
	if _frame == 180:
		var target := Vector3(14.22776, 0.7, 1.146203)
		_ik._ground_sampler.smoothed_target[&"left"] = target
		_ik._ground_sampler.idle_lower_latched_target[&"left"] = target
		_ik._ground_sampler.lower_riser_cleared_target.erase(&"left")
	if _frame <= 180:
		return
	for joint: StringName in [&"toe", &"leaf"]:
		var bone: int = _ik._bone_indices[&"left"][joint]
		var point := _player.body.skeleton.global_transform \
				* _ik.get_final_bone_global_pose(bone).origin
		# Authored 0.35m staircase: third solid tread starts at z=1.2, top=1.05.
		if (_frame > 240 and point.x > 13.5 and point.x < 16.5
				and point.z > 1.195 and point.y < 1.05):
			_clipped += 1
	var foot := _player.body.skeleton.global_transform * _ik.get_final_bone_global_pose(
			_ik._bone_indices[&"left"][&"foot"]).origin
	if _frame > 181:
		_max_step = maxf(_max_step, foot.distance_to(_previous))
	_previous = foot
	if _frame > 240:
		var surface: Vector3 = _ik._smoothed_target[&"left"]
		var offset: float = _ik._ground_sampler.debug_effective_offset.get(&"left", 0.0)
		_max_contact_error = maxf(_max_contact_error, absf(foot.y - surface.y - offset))
	if _frame >= 540:
		var passed := _clipped == 0 and _max_step <= 0.035 and _max_contact_error <= 0.02
		print("FOOT_IK_TOE_RISER_CHECK %s clipped=%d step=%.6f contact_error=%.6f" % [
				"PASS" if passed else "FAIL", _clipped, _max_step, _max_contact_error])
		get_tree().quit(0 if passed else 1)
