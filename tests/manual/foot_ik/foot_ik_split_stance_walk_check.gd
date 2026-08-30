class_name FootIkSplitStanceWalkCheck
extends Node3D
const JOINT_LIMIT_CHECK := preload("res://tests/manual/foot_ik/foot_ik_joint_limit_check.gd")
## Starts from the former 0.60m split stance and waits for the over-height
## policy to choose one safe level before walking parallel to the edge.

const START := Vector3(9.258939, 0.585117, 4.203303)
const YAW_DEGREES := -88.3
const UPPER_Y := 0.6
const LOWER_Y := 0.0
const SPLIT_TOLERANCE := 0.05
const SETTLE_STREAK_REQUIRED := 8
const SETTLE_FRAME_LIMIT := 240
const MOVE_FRAMES := 12
const SUPPORTED_WEIGHT_MIN := 0.5
const TARGET_SUPPORT_GAP_LIMIT := 0.12
const SOLE_SUPPORT_GAP_LIMIT := 0.15

var _player: Player
var _ik: PlayerFootIKModifier
var _frame := 0
var _split_streak := 0
var _movement_start_frame := -1
var _max_weighted_target_gap := 0.0
var _max_gap_frame := -1
var _max_gap_weight := 0.0
var _max_weighted_sole_gap := 0.0
var _max_sole_gap_frame := -1
var _max_sole_gap_weight := 0.0


func _ready() -> void:
	_build_surfaces()
	var player_scene: PackedScene = load("res://actors/player/player.tscn")
	_player = player_scene.instantiate() as Player
	add_child(_player)
	for child in _player.skeleton.get_children():
		if child is PlayerFootIKModifier:
			_ik = child
			break
	_player.global_position = START
	_player.rotation.y = deg_to_rad(YAW_DEGREES)
	_player._look_yaw = 0.0
	_player.head.rotation.y = 0.0
	_player.third_person_arm.rotation.y = 0.0
	_player.velocity = Vector3.ZERO
	_player.movement_input_override = Vector2.ZERO
	_player.ledge_safety_enabled = true
	_ik.reset_runtime_state()


func _physics_process(_delta: float) -> void:
	_frame += 1
	var left_target: Vector3 = _ik._smoothed_target.get(&"left", Vector3.ZERO)
	var right_target: Vector3 = _ik._smoothed_target.get(&"right", Vector3.ZERO)
	var split_now := (_player.is_on_floor()
			and absf(left_target.y - right_target.y) <= SPLIT_TOLERANCE
			and (absf(left_target.y - UPPER_Y) <= SPLIT_TOLERANCE
					or absf(left_target.y - LOWER_Y) <= SPLIT_TOLERANCE)
			and float(_ik._smoothed_ground_weight.get(&"left", 0.0)) >= 0.99
			and float(_ik._smoothed_ground_weight.get(&"right", 0.0)) >= 0.99)
	_split_streak = _split_streak + 1 if split_now else 0
	if _movement_start_frame < 0 and _split_streak >= SETTLE_STREAK_REQUIRED:
		_movement_start_frame = _frame + 1
	if _movement_start_frame >= 0 and _frame >= _movement_start_frame:
		var movement_frame := _frame - _movement_start_frame + 1
		_player.movement_input_override = Vector2(0.0, minf(float(movement_frame) / 8.0, 1.0))
		_sample_weighted_support(movement_frame)
		if movement_frame >= MOVE_FRAMES:
			_finish_check()
	elif _frame >= SETTLE_FRAME_LIMIT:
		_finish_check()


func _sample_weighted_support(movement_frame: int) -> void:
	var side := &"right"
	var weight := float(_ik._smoothed_ground_weight.get(side, 0.0))
	if weight < SUPPORTED_WEIGHT_MIN:
		return
	var target: Vector3 = _ik._smoothed_target.get(side, Vector3.ZERO)
	var probe := Vector3(target.x, _player.global_position.y + 0.2, target.z)
	var support: Dictionary = _ik._ground_sampler.raycast_ground(
			get_world_3d().direct_space_state, probe, 1.5)
	if not support["hit"]:
		return
	var real_surface: Vector3 = support["position"]
	var gap := target.y - real_surface.y
	if gap > _max_weighted_target_gap:
		_max_weighted_target_gap = gap
		_max_gap_frame = movement_frame
		_max_gap_weight = weight
	var sole_gap := _final_sole_y(side) - real_surface.y
	if sole_gap > _max_weighted_sole_gap:
		_max_weighted_sole_gap = sole_gap
		_max_sole_gap_frame = movement_frame
		_max_sole_gap_weight = weight


func _final_sole_y(side: StringName) -> float:
	var foot_idx: int = _ik._bone_indices[side][&"foot"]
	var pose: Transform3D = _ik._final_bone_poses.get(
			foot_idx, _player.skeleton.get_bone_global_pose(foot_idx))
	var to_world := _player.skeleton.global_transform
	var foot_world := to_world * pose.origin
	var sole_down: Vector3 = (to_world.basis * pose.basis
			* (_ik._sole_down_local[side] as Vector3)).normalized()
	var sole_depth: float = _ik._sole_depth_below_foot.get(side, _ik.ankle_offset)
	return foot_world.y + sole_down.y * sole_depth


func _finish_check() -> void:
	_player.movement_input_override = Vector2.ZERO
	var failures: Array[String] = []
	failures.append_array(JOINT_LIMIT_CHECK.failures(_ik, _player.skeleton, "split_stance_walk"))
	if _movement_start_frame < 0:
		failures.append("never resolved the over-height split onto one safe level")
	if _max_weighted_target_gap > TARGET_SUPPORT_GAP_LIMIT:
		failures.append("weighted lower target floated %.3fm at move frame %d (weight %.2f)" % [
				_max_weighted_target_gap, _max_gap_frame, _max_gap_weight])
	if _max_weighted_sole_gap > SOLE_SUPPORT_GAP_LIMIT:
		failures.append("weighted lower sole floated %.3fm at move frame %d (weight %.2f)" % [
				_max_weighted_sole_gap, _max_sole_gap_frame, _max_sole_gap_weight])
	var details := ("start_frame=%d max_gap=%.3f gap_frame=%d weight=%.2f "
			+ "max_sole_gap=%.3f sole_frame=%d root=%s") % [
			_movement_start_frame, _max_weighted_target_gap, _max_gap_frame,
			_max_gap_weight, _max_weighted_sole_gap, _max_sole_gap_frame,
			str(_player.global_position)]
	if not failures.is_empty():
		print("FOOT_IK_SPLIT_STANCE_WALK_CHECK FAIL %s details=%s" % [
				"; ".join(failures), details])
		get_tree().quit(1)
		return
	print("FOOT_IK_SPLIT_STANCE_WALK_CHECK PASS %s" % details)
	get_tree().quit(0)


func _build_surfaces() -> void:
	_add_box(Vector3(10.0, 0.3, 3.85), Vector3(3.0, 0.6, 0.5))
	_add_box(Vector3(10.0, -0.5, 3.85), Vector3(7.0, 1.0, 5.0))


func _add_box(position: Vector3, size: Vector3) -> void:
	var body := StaticBody3D.new()
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collision.shape = shape
	body.add_child(collision)
	body.position = position
	add_child(body)
