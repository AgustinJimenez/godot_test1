extends Node3D
## 024: replay the exact no-input stance; measure rendered motion over several idle loops.
const POSITION := Vector3(15.52282, 1.422718, 1.734463)
const YAW_DEGREES := 100.977250312091
const SETTLE_FRAMES := 120
const END_FRAME := 600

var _player: Player
var _ik: PlayerFootIKModifier
var _frame := 0
var _anchors: Dictionary = {}
var _previous: Dictionary = {}
var _root_anchor := Vector3.ZERO
var _max_drift := 0.0
var _max_step := 0.0
var _max_clearance := 0.0
var _max_root_drift := 0.0
var _invalid_frames := 0
var _samples := 0


func _ready() -> void:
	_player = $FootIkPreview/Player
	_player.global_position = POSITION
	_player.rotation.y = deg_to_rad(YAW_DEGREES)
	_player.velocity = Vector3.ZERO
	_player.movement_input_override = Vector2.ZERO
	_ik = _player.body._foot_ik_modifier
	_ik.reset_runtime_state()


func _physics_process(_delta: float) -> void:
	_frame += 1
	if _frame <= SETTLE_FRAMES:
		return
	if _samples == 0:
		_root_anchor = _player.global_position
	_samples += 1
	_max_root_drift = maxf(_max_root_drift, _root_anchor.distance_to(_player.global_position))
	var sampler: FootIKGroundSampler = _ik._ground_sampler
	for side: StringName in [&"left", &"right"]:
		var bone: int = _ik._bone_indices[side]["foot"]
		var foot := _player.body.skeleton.global_transform * _ik.get_final_bone_global_pose(bone).origin
		if not _anchors.has(side):
			_anchors[side] = foot
			_previous[side] = foot
		_max_drift = maxf(_max_drift, foot.distance_to(_anchors[side]))
		_max_step = maxf(_max_step, foot.distance_to(_previous[side]))
		_previous[side] = foot
		var surface: Vector3 = sampler.smoothed_target.get(side, Vector3.INF)
		var offset: float = sampler.debug_effective_offset.get(side, 0.0)
		_max_clearance = maxf(_max_clearance, absf(foot.y - surface.y - offset))
		if (not sampler.is_target_inside_stance_zone(side, foot, 0.002)
				or not _ik.debug_contact_hit.get(side, false)
				or float(_ik._smoothed_ground_weight.get(side, 0.0)) < 0.95):
			_invalid_frames += 1
	if not sampler.idle_lower_latched_target.has(&"right"):
		_invalid_frames += 1
	if _frame < END_FRAME:
		return
	var rejection_isolated := _check_rejection_scope(sampler)
	var passed := (_samples == END_FRAME - SETTLE_FRAMES and _max_drift <= 0.01
			and _max_step <= 0.02 and _max_clearance <= 0.02 and _max_root_drift <= 0.01
			and _invalid_frames == 0 and rejection_isolated)
	print("FOOT_IK_SPLIT_IDLE_FEEDBACK_CHECK %s samples=%d drift=%.6f step=%.6f "
			% ["PASS" if passed else "FAIL", _samples, _max_drift, _max_step]
			+ "clearance=%.6f root_drift=%.6f invalid=%d rejection_isolated=%s"
			% [_max_clearance, _max_root_drift, _invalid_frames, rejection_isolated])
	get_tree().quit(0 if passed else 1)


func _check_rejection_scope(sampler: FootIKGroundSampler) -> bool:
	# Declining optional upper-foot body motion must not cancel a different owner's plant.
	if (sampler.split_safe_root_target.is_finite()
			or not sampler.split_safe_held_upper_target.is_empty()):
		return false
	var targets := sampler.smoothed_target.duplicate()
	var latches := sampler.idle_lower_latched_target.duplicate()
	sampler.preferred_root_nudge = Vector3.LEFT
	sampler.reject_split_safe_root()
	var isolated := (sampler.smoothed_target == targets
			and sampler.idle_lower_latched_target == latches
			and sampler.preferred_root_nudge.is_zero_approx())
	# A real split-recovery rejection must still perform its existing release transaction.
	sampler.split_safe_root_target = _player.global_position
	sampler.split_safe_surface_y = _player.global_position.y
	sampler.reject_split_safe_root()
	return (isolated and sampler.idle_lower_latched_target.is_empty()
			and sampler.idle_lower_acquiring.is_empty()
			and not sampler.split_safe_root_target.is_finite())
