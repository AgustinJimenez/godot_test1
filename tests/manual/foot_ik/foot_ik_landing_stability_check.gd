class_name FootIkLandingStabilityCheck
extends Node3D
const JOINT_LIMIT_CHECK := preload("res://tests/manual/foot_ik/foot_ik_joint_limit_check.gd")
## Reproduces a live jump onto the top-landing corner. Landing planning must
## choose one safe level before contact; neither leg may hand off afterward.

const STAIR_SURFACES := preload("res://tests/manual/foot_ik/foot_ik_stair_surfaces.gd")
const STAIR_ORIGIN := Vector3(8.0, 0.0, 0.0)
const STAIR_WIDTH := 3.0
const STAIR_TREAD_DEPTH := 0.6
const STAIR_COUNT := 6
const STAIR_HEIGHT := 0.1
const START := Vector3(8.371093, 0.495433, 4.28113)
const YAW := 82.8251073474332
const JUMP_FRAME := 37
const TARGET_HEIGHT_TOLERANCE := 0.05
const FOOT_STEP_LIMIT := 0.15
const RUN_FRAMES := 180

var _player: Player
var _ik: PlayerFootIKModifier
var _frame := 0
var _airborne_seen := false
var _commit_seen := false
var _landing_frame := -1
var _landing_count := 0
var _post_landing_airborne := false
var _landing_root_y := INF
var _max_root_height_change := 0.0
var _max_foot_step := 0.0
var _max_foot_step_frame := -1
var _previous_feet: Dictionary = {}
var _previous_on_floor := true


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
	if (_airborne_seen and _ik._ground_sampler.airborne_safe_root_target.is_finite()
			and _ik._ground_sampler.airborne_landing_decision != "already_safe"):
		_commit_seen = true
	var on_floor := _player.is_on_floor()
	if _airborne_seen and on_floor and not _previous_on_floor:
		_landing_count += 1
		if _landing_frame < 0:
			_landing_frame = _frame
			_landing_root_y = _player.global_position.y
	if _landing_frame >= 0:
		if not on_floor:
			_post_landing_airborne = true
		_max_root_height_change = maxf(_max_root_height_change,
				absf(_player.global_position.y - _landing_root_y))
		var feet := {&"left": _final_foot_world(&"left"),
				&"right": _final_foot_world(&"right")}
		if not _previous_feet.is_empty():
			for side: StringName in [&"left", &"right"]:
				var step: float = (feet[side] as Vector3).distance_to(_previous_feet[side])
				if step > _max_foot_step:
					_max_foot_step = step
					_max_foot_step_frame = _frame
		_previous_feet = feet
	_previous_on_floor = on_floor
	if _frame >= RUN_FRAMES:
		_finish_check()


func _final_foot_world(side: StringName) -> Vector3:
	var foot_idx: int = _ik._bone_indices[side][&"foot"]
	var pose: Transform3D = _ik._final_bone_poses.get(
			foot_idx, _player.skeleton.get_bone_global_pose(foot_idx))
	return _player.skeleton.global_transform * pose.origin


func _finish_check() -> void:
	Input.action_release(&"jump")
	var failures: Array[String] = []
	failures.append_array(JOINT_LIMIT_CHECK.failures(_ik, _player.skeleton, "landing_stability"))
	if not _airborne_seen:
		failures.append("jump never became airborne")
	if not _commit_seen:
		failures.append("no single-surface landing commitment before contact")
	if _landing_count != 1:
		failures.append("expected one landing, observed %d" % _landing_count)
	if _post_landing_airborne:
		failures.append("character became airborne again after landing")
	if _max_root_height_change > 0.08:
		failures.append("root changed height %.3fm after landing" % _max_root_height_change)
	var left_target: Vector3 = _ik._smoothed_target.get(&"left", Vector3.ZERO)
	var right_target: Vector3 = _ik._smoothed_target.get(&"right", Vector3.ZERO)
	if absf(left_target.y - right_target.y) > TARGET_HEIGHT_TOLERANCE:
		failures.append("landing retained split targets %.3f/%.3f" % [
				left_target.y, right_target.y])
	if _max_foot_step > FOOT_STEP_LIMIT:
		failures.append("foot moved %.3fm at frame %d (limit %.3fm)" % [
				_max_foot_step, _max_foot_step_frame, FOOT_STEP_LIMIT])
	var details := ("root=%s commit=%s landing_frame=%d landings=%d relanded=%s "
			+ "root_dy=%.3f targets=%.3f/%.3f max_foot_step=%.3f step_frame=%d") % [
			str(_player.global_position), _commit_seen, _landing_frame, _landing_count,
			_post_landing_airborne, _max_root_height_change, left_target.y, right_target.y,
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
