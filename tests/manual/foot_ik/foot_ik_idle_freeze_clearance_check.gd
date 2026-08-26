class_name FootIkIdleFreezeClearanceCheck
extends RefCounted
## Guards the split-tread idle transition where one leg requests a shared
## pelvis sink exactly as idle freeze engages. Both rendered soles must stay
## on their retained surfaces after the common ancestor moves.

const MAX_PENETRATION := 0.025
const REQUIRED_FROZEN_SAMPLES := 10
const SHARED_DROP := 0.3
const MAX_PRESERVED_FOOT_DISPLACEMENT := 0.01

var _player: Player
var _ik: PlayerFootIKModifier
var _samples := 0
var _failures := 0
var _max_penetration := 0.0
var _side_failures := {&"left": 0, &"right": 0}
var _max_freeze_streak := {&"left": 0, &"right": 0}
var _max_weight := {&"left": 0.0, &"right": 0.0}
var _max_target_height_difference := 0.0
var _invariant_ran := false
var _max_preserved_foot_displacement := 0.0


func setup(player: Player) -> void:
	_player = player
	_ik = _find_foot_ik(player)
	if _ik != null:
		# The static preview normally force-plants purely for presentation.
		# Exercise the real idle classification/freeze path in this fixture.
		_ik.force_plant_mode = false


func sample() -> void:
	if _player == null or _ik == null:
		return
	for side: StringName in [&"left", &"right"]:
		_max_freeze_streak[side] = maxi(int(_max_freeze_streak[side]),
				int(_ik._idle_freeze_streak.get(side, 0)))
		_max_weight[side] = maxf(float(_max_weight[side]),
				float(_ik._smoothed_ground_weight.get(side, 0.0)))
	var left_target: Vector3 = _ik._smoothed_target.get(&"left", Vector3.ZERO)
	var right_target: Vector3 = _ik._smoothed_target.get(&"right", Vector3.ZERO)
	_max_target_height_difference = maxf(
			_max_target_height_difference, absf(left_target.y - right_target.y))
	for side: StringName in [&"left", &"right"]:
		if int(_ik._idle_freeze_streak.get(side, 0)) < 15:
			continue
		_samples += 1
		var clearance := _sole_clearance(side)
		var penetration := maxf(-clearance, 0.0)
		_max_penetration = maxf(_max_penetration, penetration)
		if penetration > MAX_PENETRATION:
			_failures += 1
			_side_failures[side] = int(_side_failures[side]) + 1


func run_shared_pelvis_invariant() -> void:
	if _player == null or _ik == null or _invariant_ran:
		return
	_invariant_ran = true
	var skeleton := _player.skeleton
	var to_world := skeleton.global_transform
	var per_leg := {}
	var expected_foot_positions := {}
	for side: StringName in [&"left", &"right"]:
		var indices: Dictionary = _ik._bone_indices[side]
		var hip_pose := skeleton.get_bone_global_pose(int(indices["hip"]))
		var foot_pose := skeleton.get_bone_global_pose(int(indices["foot"]))
		var target: Vector3 = to_world * foot_pose.origin
		expected_foot_positions[side] = target
		per_leg[side] = {
			"hit": true, "preserve_idle_pose": true,
			"hip_pos": to_world * hip_pose.origin, "target": target,
			"upper": float(_ik._leg_lengths[side]["upper"]),
			"lower": float(_ik._leg_lengths[side]["lower"]),
			"ground_weight": 1.0, "chain_weight": 1.0,
		}
	var prediction_enabled := _ik.step_prediction_enabled
	_ik.step_prediction_enabled = false
	_ik._leg_solver.reset_runtime_state()
	_ik._apply_support_pelvis_and_legs(skeleton, to_world, per_leg, SHARED_DROP, 1.0)
	_ik.step_prediction_enabled = prediction_enabled
	for side: StringName in [&"left", &"right"]:
		var foot_index: int = _ik._bone_indices[side]["foot"]
		var actual: Vector3 = to_world * skeleton.get_bone_global_pose(foot_index).origin
		_max_preserved_foot_displacement = maxf(_max_preserved_foot_displacement,
				actual.distance_to(expected_foot_positions[side] as Vector3))


func format_result() -> String:
	var passed := (_samples >= REQUIRED_FROZEN_SAMPLES and _failures == 0
			and _invariant_ran
			and _max_preserved_foot_displacement <= MAX_PRESERVED_FOOT_DISPLACEMENT)
	var template := ("FOOT_IK_IDLE_FREEZE_CLEARANCE_CHECK %s samples=%d failures=%d "
			+ "left_failures=%d right_failures=%d max_penetration_m=%.6f limit_m=%.6f "
			+ "max_streak=%d/%d max_weight=%.3f/%.3f target_height_diff_m=%.3f "
			+ "preserved_foot_displacement_m=%.6f displacement_limit_m=%.6f")
	return template % ["PASS" if passed else "FAIL", _samples, _failures,
			_side_failures[&"left"], _side_failures[&"right"],
			_max_penetration, MAX_PENETRATION,
			_max_freeze_streak[&"left"], _max_freeze_streak[&"right"],
			_max_weight[&"left"], _max_weight[&"right"], _max_target_height_difference,
			_max_preserved_foot_displacement, MAX_PRESERVED_FOOT_DISPLACEMENT]


func _sole_clearance(side: StringName) -> float:
	var foot_index: int = _ik._bone_indices[side]["foot"]
	var foot_pose: Transform3D = _ik._final_bone_poses.get(
			foot_index, _player.skeleton.get_bone_global_pose(foot_index))
	var foot_world := _player.skeleton.global_transform * foot_pose
	var normal: Vector3 = _ik._smoothed_normal.get(side, Vector3.UP)
	var sole_down: Vector3 = foot_world.basis * (_ik._sole_down_local[side] as Vector3)
	var sole_depth: float = _ik._sole_depth_below_foot.get(side, _ik.ankle_offset)
	var sole := foot_world.origin + sole_down * sole_depth
	var surface: Vector3 = _ik._smoothed_target.get(side, sole)
	return (sole - surface).dot(normal)


func _find_foot_ik(player: Player) -> PlayerFootIKModifier:
	for child: Node in player.skeleton.get_children():
		if child is PlayerFootIKModifier:
			return child
	return null
