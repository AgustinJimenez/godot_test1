class_name FootIkWalkIdleStanceCheck
extends Node3D
## Replays walk-to-idle transitions at deterministic positions, body yaws,
## and travel angles. It measures the modifier's final rendered foot poses,
## not the animation pose Skeleton3D restores after modifiers finish.

const PLATFORM_HEIGHT := 3.0
const FLOOR_SIZE := Vector3(4.0, PLATFORM_HEIGHT, 4.0)
const TOTAL_CASES := 24
const WALK_FRAMES := 90
const IDLE_GRACE_FRAMES := 40
const IDLE_SAMPLE_FRAMES := 90
const MIN_SIDE_CLEARANCE := 0.04
const MAX_FROZEN_TARGET_DRIFT := 0.08

var _player: Player
var _skeleton: Skeleton3D
var _ik: PlayerFootIKModifier
var _cases: Array[Dictionary] = []
var _case_index := 0
var _frame_in_case := 0
var _sample_count := 0
var _failures: Array[String] = []
var _failed_cases: Dictionary = {}
var _worst_left_clearance := INF
var _worst_right_clearance := INF


func _ready() -> void:
	_build_floor()
	_build_cases()
	_setup_player()


func _build_floor() -> void:
	var floor_body := StaticBody3D.new()
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = FLOOR_SIZE
	collision.shape = shape
	floor_body.add_child(collision)
	floor_body.position.y = PLATFORM_HEIGHT * 0.5
	add_child(floor_body)


func _build_cases() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 24680
	for case_number in TOTAL_CASES:
		var movement := Vector2(rng.randf_range(-1.0, 1.0), rng.randf_range(-1.0, 1.0))
		if movement.length_squared() < 0.25:
			movement = Vector2(0.7, -1.0)
		_cases.append({
			"name": "case_%02d" % case_number,
			"position": Vector3.ZERO + Vector3.UP * PLATFORM_HEIGHT,
			"yaw": rng.randf_range(-PI, PI),
			"movement": movement.normalized(),
		})


func _setup_player() -> void:
	var player_scene: PackedScene = load("res://actors/player/player.tscn")
	_player = player_scene.instantiate() as Player
	_player.ledge_safety_enabled = true
	add_child(_player)
	_skeleton = _player.body.skeleton
	for child in _skeleton.get_children():
		if child is PlayerFootIKModifier:
			_ik = child
			break
	_apply_case()


func _apply_case() -> void:
	var current: Dictionary = _cases[_case_index]
	_player.global_position = current["position"]
	_player.rotation = Vector3(0.0, current["yaw"], 0.0)
	_player.velocity = Vector3.ZERO
	_player._look_yaw = 0.0
	_player.head.rotation.y = 0.0
	_player.third_person_arm.rotation.y = 0.0
	_player.movement_input_override = current["movement"]
	_ik.reset_runtime_state()
	_frame_in_case = 0


func _physics_process(_delta: float) -> void:
	_frame_in_case += 1
	if _frame_in_case == WALK_FRAMES:
		_player.movement_input_override = Vector2.ZERO
	var idle_frame := _frame_in_case - WALK_FRAMES
	if idle_frame >= IDLE_GRACE_FRAMES:
		_sample_stance(idle_frame)
	if idle_frame < IDLE_GRACE_FRAMES + IDLE_SAMPLE_FRAMES:
		return
	_case_index += 1
	if _case_index >= _cases.size():
		_finish_check()
	else:
		_apply_case()


func _sample_stance(idle_frame: int) -> void:
	_check_released_target_latches(idle_frame)
	_check_frozen_target_drift(idle_frame)
	var left_hip_idx: int = _ik._bone_indices[&"left"]["hip"]
	var right_hip_idx: int = _ik._bone_indices[&"right"]["hip"]
	var left_foot_idx: int = _ik._bone_indices[&"left"]["foot"]
	var right_foot_idx: int = _ik._bone_indices[&"right"]["foot"]
	var hip_l_w := _skeleton.global_transform * _final_pose(left_hip_idx).origin
	var hip_r_w := _skeleton.global_transform * _final_pose(right_hip_idx).origin
	var foot_l_w := _skeleton.global_transform * _final_pose(left_foot_idx).origin
	var foot_r_w := _skeleton.global_transform * _final_pose(right_foot_idx).origin
	var hip_axis := hip_l_w - hip_r_w
	hip_axis.y = 0.0
	if hip_axis.length_squared() <= 0.0001:
		return
	var left_dir := hip_axis.normalized()
	var root_pos := _player.global_position
	var left_clearance := (foot_l_w - root_pos).dot(left_dir)
	var right_clearance := -(foot_r_w - root_pos).dot(left_dir)
	_worst_left_clearance = minf(_worst_left_clearance, left_clearance)
	_worst_right_clearance = minf(_worst_right_clearance, right_clearance)
	_sample_count += 1
	if left_clearance >= MIN_SIDE_CLEARANCE and right_clearance >= MIN_SIDE_CLEARANCE:
		return
	var current: Dictionary = _cases[_case_index]
	if _failed_cases.has(current["name"]):
		return
	_failed_cases[current["name"]] = true
	var left_target: Vector3 = _ik._solved_target_smoothed.get(&"left", foot_l_w)
	var right_target: Vector3 = _ik._solved_target_smoothed.get(&"right", foot_r_w)
	var detail := "%s idle_frame=%d animation=%s left=%.3f left_target=%.3f right=%.3f " + \
			"right_target=%.3f weights=(%.2f,%.2f)"
	_failures.append(detail % [
				current["name"], idle_frame, _player.body.anim_player.current_animation,
				left_clearance, (left_target - root_pos).dot(left_dir), right_clearance,
				-(right_target - root_pos).dot(left_dir),
				float(_ik._smoothed_ground_weight.get(&"left", 0.0)),
				float(_ik._smoothed_ground_weight.get(&"right", 0.0)),
			])


func _check_released_target_latches(idle_frame: int) -> void:
	for side: StringName in [&"left", &"right"]:
		if bool(_ik._idle_frozen.get(side, false)) or not _ik._idle_freeze_yaw.has(side):
			continue
		var key := "%s:stale_latch" % side
		var current: Dictionary = _cases[_case_index]
		if _failed_cases.has(key):
			continue
		_failed_cases[key] = true
		_failures.append(
				"%s idle_frame=%d %s foot released with stale target latch" % [
					current["name"], idle_frame, side])


func _check_frozen_target_drift(idle_frame: int) -> void:
	for side: StringName in [&"left", &"right"]:
		if not bool(_ik._idle_frozen.get(side, false)):
			continue
		var held: Vector3 = _ik._smoothed_target.get(side, Vector3.ZERO)
		var sampled: Vector3 = _ik._ground_sampler.debug_raw_target.get(side, held)
		if held.distance_to(sampled) <= MAX_FROZEN_TARGET_DRIFT + 0.001:
			continue
		var key := "%s:frozen_drift" % side
		if _failed_cases.has(key):
			continue
		_failed_cases[key] = true
		_failures.append("%s idle_frame=%d %s frozen target drift=%.3f" % [
				_cases[_case_index]["name"], idle_frame, side, held.distance_to(sampled)])


func _final_pose(bone_idx: int) -> Transform3D:
	return _ik._final_bone_poses.get(bone_idx, _skeleton.get_bone_global_pose(bone_idx))


func _finish_check() -> void:
	if not _failures.is_empty():
		print("FOOT_IK_WALK_IDLE_STANCE_CHECK FAIL samples=%d details=%s" % [
				_sample_count, "; ".join(_failures)])
		get_tree().quit(1)
		return
	var summary := "FOOT_IK_WALK_IDLE_STANCE_CHECK PASS cases=%d samples=%d " + \
			"worst_left_clearance=%.3f worst_right_clearance=%.3f"
	print(summary % [
				TOTAL_CASES, _sample_count, _worst_left_clearance, _worst_right_clearance])
	get_tree().quit(0)
