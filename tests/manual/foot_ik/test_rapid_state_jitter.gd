class_name TestRapidStateJitter
extends Node3D
## Stress test that rapidly switches player locomotion states (sprint fluttering,
## crouch fluttering, diagonal slalom, and start-stop stutter) to verify that
## animations, torso yaw, and foot IK do not snap or pop on split-second changes.

const PLAYER_SCENE := preload("res://actors/player/player.tscn")
const JOINTS: Array[StringName] = [
	&"Hips",
	&"Spine",
	&"Spine1",
	&"Spine2",
	&"Neck",
	&"Head",
	&"LeftUpLeg",
	&"LeftLeg",
	&"LeftFoot",
	&"LeftToeBase",
	&"RightUpLeg",
	&"RightLeg",
	&"RightFoot",
	&"RightToeBase",
]

## Single-frame maximum allowable rotation jump in degrees (16.6ms frame).
## Spine/torso/head bones must stay strictly smooth (<= 25.0 deg).
## Full-stride swing limbs during sprint/crouch transitions allow up to 65.0 deg.
const MAX_ALLOWED_BODY_JUMP_DEG := 25.0
const MAX_ALLOWED_LIMB_JUMP_DEG := 65.0

const BODY_JOINTS: Array[StringName] = [
	&"Hips",
	&"Spine",
	&"Spine1",
	&"Spine2",
	&"Neck",
	&"Head",
]

const PHASES: Array[Dictionary] = [
	{
		"name": &"sprint_flutter",
		"duration_frames": 150,
		"interval_frames": 8,
		"description": "Rapid Shift press/release while walking forward",
	},
	{
		"name": &"crouch_flutter",
		"duration_frames": 150,
		"interval_frames": 5,
		"description": "Rapid Crouch/Stand toggle while moving forward",
	},
	{
		"name": &"diagonal_slalom",
		"duration_frames": 150,
		"interval_frames": 4,
		"description": "Rapid W+A / W+D / W diagonal alternation",
	},
	{
		"name": &"start_stop_stutter",
		"duration_frames": 150,
		"interval_frames": 4,
		"description": "Rapid walk start / stop toggle",
	},
]

var _player: Player
var _joint_indices: Dictionary = {}
var _previous_rotations: Dictionary = {}
var _previous_positions: Dictionary = {}
var _phase_index := 0
var _frame_in_phase := 0
var _failed_any := false
var _phase_worst_jump := 0.0
var _phase_worst_joint := StringName()
var _phase_worst_frame := 0


var _rendered_poses: Dictionary = {}
var _sample_scheduled := false


func _ready() -> void:
	_build_floor()
	_spawn_player()
	_start_phase()


func _physics_process(_delta: float) -> void:
	if _player == null or _phase_index >= PHASES.size():
		return
	_drive_phase_input()
	if not _sample_scheduled:
		_sample_scheduled = true
		call_deferred(&"_sample_frame")


func _build_floor() -> void:
	var floor_body := StaticBody3D.new()
	var collision := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(20.0, 1.0, 40.0)
	collision.shape = box
	collision.position = Vector3(0.0, -0.5, 0.0)
	floor_body.add_child(collision)
	add_child(floor_body)


func _spawn_player() -> void:
	_player = PLAYER_SCENE.instantiate() as Player
	_player.position = Vector3(0.0, 0.05, 0.0)
	add_child(_player)
	for camera: Node in _player.find_children("*", "Camera3D", true, false):
		(camera as Camera3D).current = false
	for joint: StringName in JOINTS:
		var bone_name := _player.body.resolve_bone_name(joint)
		_joint_indices[joint] = _player.skeleton.find_bone(bone_name)
	_player.skeleton.skeleton_updated.connect(_capture_rendered_pose)


func _capture_rendered_pose() -> void:
	for bone_index in _player.skeleton.get_bone_count():
		_rendered_poses[bone_index] = _player.skeleton.get_bone_global_pose(bone_index)


func _sample_frame() -> void:
	_sample_scheduled = false
	if _player == null or _phase_index >= PHASES.size():
		return
	for joint: StringName in JOINTS:
		var bone_idx: int = _joint_indices.get(joint, -1)
		if bone_idx < 0:
			continue
		var pose: Transform3D = _rendered_poses.get(
			bone_idx, _player.skeleton.get_bone_global_pose(bone_idx)
		)
		var rotation := pose.basis.get_rotation_quaternion().normalized()
		if _previous_rotations.has(joint) and _frame_in_phase >= 3:
			var prev_rot := _previous_rotations[joint] as Quaternion
			var jump_deg := rad_to_deg(prev_rot.angle_to(rotation))
			if jump_deg > _phase_worst_jump:
				_phase_worst_jump = jump_deg
				_phase_worst_joint = joint
				_phase_worst_frame = _frame_in_phase
		_previous_rotations[joint] = rotation
	_frame_in_phase += 1
	var current_phase: Dictionary = PHASES[_phase_index]
	if _frame_in_phase >= int(current_phase["duration_frames"]):
		_finish_phase()
		_phase_index += 1
		if _phase_index < PHASES.size():
			_start_phase()
		else:
			_finish_all()


func _start_phase() -> void:
	_frame_in_phase = 0
	_phase_worst_jump = 0.0
	_phase_worst_joint = StringName()
	_phase_worst_frame = 0
	_previous_rotations.clear()
	_previous_positions.clear()
	_player.global_position = Vector3(0.0, 0.05, 0.0)
	_player.velocity = Vector3.ZERO
	_player.stamina = _player.sprint_duration
	_player._sprint_locked = false
	_player._crouched = false
	Input.action_release(&"sprint")


func _drive_phase_input() -> void:
	var current_phase: Dictionary = PHASES[_phase_index]
	var phase_name := current_phase["name"] as StringName
	var interval := int(current_phase["interval_frames"])
	var tick := (_frame_in_phase / interval) % 2
	match phase_name:
		&"sprint_flutter":
			_player._crouched = false
			_player.movement_input_override = Vector2(0.0, -1.0)
			if tick == 1:
				Input.action_press(&"sprint")
			else:
				Input.action_release(&"sprint")
		&"crouch_flutter":
			Input.action_release(&"sprint")
			_player.movement_input_override = Vector2(0.0, -1.0)
			_player._crouched = (tick == 1)
		&"diagonal_slalom":
			Input.action_release(&"sprint")
			_player._crouched = false
			var sub_tick := (_frame_in_phase / interval) % 3
			if sub_tick == 0:
				_player.movement_input_override = Vector2(-1.0, -1.0)
			elif sub_tick == 1:
				_player.movement_input_override = Vector2(1.0, -1.0)
			else:
				_player.movement_input_override = Vector2(0.0, -1.0)
		&"start_stop_stutter":
			Input.action_release(&"sprint")
			_player._crouched = false
			_player.movement_input_override = (
				Vector2(0.0, -1.0) if tick == 1 else Vector2.ZERO
			)



func _finish_phase() -> void:
	var current_phase: Dictionary = PHASES[_phase_index]
	var phase_name := current_phase["name"] as StringName
	var limit := (
		MAX_ALLOWED_BODY_JUMP_DEG
		if _phase_worst_joint in BODY_JOINTS
		else MAX_ALLOWED_LIMB_JUMP_DEG
	)
	var phase_failed := _phase_worst_jump > limit
	_failed_any = _failed_any or phase_failed
	print(
		"RAPID_JITTER_CHECK ",
		"FAIL" if phase_failed else "PASS",
		" phase=",
		phase_name,
		" worst_jump_deg=",
		snappedf(_phase_worst_jump, 0.001),
		" limit_deg=",
		limit,
		" worst_joint=",
		_phase_worst_joint,
		" at_frame=",
		_phase_worst_frame
	)


func _finish_all() -> void:
	print("RAPID_JITTER_SUITE ", "FAIL" if _failed_any else "PASS")
	get_tree().quit(1 if _failed_any else 0)
