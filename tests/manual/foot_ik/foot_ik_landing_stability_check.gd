class_name FootIkLandingStabilityCheck
extends Node3D
const JOINT_LIMIT_CHECK := preload("res://tests/manual/foot_ik/foot_ik_joint_limit_check.gd")
## Reproduces a live jump onto the top-landing corner where a two-frame lower
## floor sample survived behind a later proven upper-foot plant. The stale
## support used to pull the right leg down after landing, then back up in idle.

const STAIR_SURFACES := preload("res://tests/manual/foot_ik/foot_ik_stair_surfaces.gd")
const STAIR_ORIGIN := Vector3(8.0, 0.0, 0.0)
const STAIR_WIDTH := 3.0
const STAIR_TREAD_DEPTH := 0.6
const STAIR_COUNT := 6
const STAIR_HEIGHT := 0.1
const START := Vector3(8.371093, 0.495433, 4.28113)
const YAW := 82.8251073474332
const JUMP_FRAME := 37
const UPPER_SURFACE_Y := 0.6
const UPPER_CONFIRM_FRAMES := 4
const TARGET_HEIGHT_TOLERANCE := 0.05
const FOOT_STEP_LIMIT := 0.15
const RUN_FRAMES := 180

var _player: Player
var _ik: PlayerFootIKModifier
var _frame := 0
var _airborne_seen := false
var _upper_streak := 0
var _upper_confirm_frame := -1
var _lowest_target_after_upper := INF
var _lowest_foot_after_upper := INF
var _max_foot_step := 0.0
var _max_foot_step_frame := -1
var _previous_foot := Vector3.ZERO
var _has_previous_foot := false


func _ready() -> void:
	_build_lower_floor()
	_build_stair_landing()
	var player_scene: PackedScene = load("res://actors/player/player.tscn")
	_player = player_scene.instantiate() as Player
	add_child(_player)
	STAIR_SURFACES.configure_player(_player)
	for child in _player.skeleton.get_children():
		if child is PlayerFootIKModifier:
			_ik = child
			break
	_player.global_position = START
	_player.rotation.y = deg_to_rad(YAW)
	_player._look_yaw = 0.0
	_player.head.rotation.y = 0.0
	_player.third_person_arm.rotation.y = 0.0
	_player.velocity = Vector3.ZERO
	_player.movement_input_override = Vector2.ZERO
	_player.ledge_safety_enabled = true
	_ik.reset_runtime_state()


func _physics_process(_delta: float) -> void:
	_frame += 1
	if _frame == JUMP_FRAME:
		Input.action_press(&"jump")
	elif _frame == JUMP_FRAME + 1:
		Input.action_release(&"jump")
	if _frame >= JUMP_FRAME and not _player.is_on_floor():
		_airborne_seen = true
	var target: Vector3 = _ik._smoothed_target.get(&"right", Vector3.ZERO)
	var foot := _final_foot_world()
	var upper_now := (_airborne_seen and _player.is_on_floor()
			and absf(target.y - UPPER_SURFACE_Y) <= TARGET_HEIGHT_TOLERANCE)
	_upper_streak = _upper_streak + 1 if upper_now else 0
	if _upper_confirm_frame < 0 and _upper_streak >= UPPER_CONFIRM_FRAMES:
		_upper_confirm_frame = _frame
		_previous_foot = foot
		_has_previous_foot = true
	if _upper_confirm_frame >= 0:
		_lowest_target_after_upper = minf(_lowest_target_after_upper, target.y)
		_lowest_foot_after_upper = minf(_lowest_foot_after_upper, foot.y)
		if _has_previous_foot:
			var step := foot.distance_to(_previous_foot)
			if step > _max_foot_step:
				_max_foot_step = step
				_max_foot_step_frame = _frame
		_previous_foot = foot
		_has_previous_foot = true
	if _frame >= RUN_FRAMES:
		_finish_check()


func _final_foot_world() -> Vector3:
	var foot_idx: int = _ik._bone_indices[&"right"][&"foot"]
	var pose: Transform3D = _ik._final_bone_poses.get(
			foot_idx, _player.skeleton.get_bone_global_pose(foot_idx))
	return _player.skeleton.global_transform * pose.origin


func _finish_check() -> void:
	Input.action_release(&"jump")
	var failures: Array[String] = []
	failures.append_array(JOINT_LIMIT_CHECK.failures(_ik, _player.skeleton, "landing_stability"))
	if _upper_confirm_frame < 0:
		failures.append("right foot never confirmed upper landing support")
	var left_target: Vector3 = _ik._smoothed_target.get(&"left", Vector3.ZERO)
	var right_target: Vector3 = _ik._smoothed_target.get(&"right", Vector3.ZERO)
	if absf(left_target.y - right_target.y) > TARGET_HEIGHT_TOLERANCE:
		failures.append("landing retained split targets %.3f/%.3f" % [
				left_target.y, right_target.y])
	if _max_foot_step > FOOT_STEP_LIMIT:
		failures.append("right foot moved %.3fm at frame %d (limit %.3fm)" % [
				_max_foot_step, _max_foot_step_frame, FOOT_STEP_LIMIT])
	var details := ("root=%s upper_frame=%d lowest_target=%.3f lowest_foot=%.3f "
			+ "max_foot_step=%.3f step_frame=%d") % [str(_player.global_position),
			_upper_confirm_frame, _lowest_target_after_upper, _lowest_foot_after_upper,
			_max_foot_step, _max_foot_step_frame]
	if not failures.is_empty():
		print("FOOT_IK_LANDING_STABILITY_CHECK FAIL %s details=%s" % [
				"; ".join(failures), details])
		get_tree().quit(1)
		return
	print("FOOT_IK_LANDING_STABILITY_CHECK PASS %s" % details)
	get_tree().quit(0)


func _build_stair_landing() -> void:
	for step in STAIR_COUNT:
		var rise := STAIR_HEIGHT * (step + 1)
		var box := CSGBox3D.new()
		box.size = Vector3(STAIR_WIDTH, rise, STAIR_TREAD_DEPTH)
		box.use_collision = true
		STAIR_SURFACES.configure_authored_stair(box)
		box.position = STAIR_ORIGIN + Vector3(
				0.0, rise * 0.5, (step + 0.5) * STAIR_TREAD_DEPTH)
		add_child(box)
	STAIR_SURFACES.build_traversal_ramp(self, STAIR_ORIGIN, STAIR_WIDTH, 0.3,
			STAIR_TREAD_DEPTH, STAIR_COUNT, STAIR_HEIGHT)
	STAIR_SURFACES.build_top_landing(self, STAIR_ORIGIN, STAIR_WIDTH,
			STAIR_TREAD_DEPTH, STAIR_COUNT, STAIR_HEIGHT)


func _build_lower_floor() -> void:
	var body := StaticBody3D.new()
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(12.0, 1.0, 12.0)
	collision.shape = shape
	body.position = Vector3(8.0, -0.5, 3.0)
	body.add_child(collision)
	add_child(body)
