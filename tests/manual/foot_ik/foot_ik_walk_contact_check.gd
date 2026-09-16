extends Node3D
## Walking toe/riser clearance regression for 025's live "11.3cm toe during moves/unarmed_walk"
## report: walk the real Player up and back down the 0.35m stairs and assert neither foot's ankle
## nor toe tip ever enters the authored tread boxes. The authored treads run through
## finalize_authored_box, so each is a real StaticBody3D + BoxShape3D and the box math is exact.
## Do NOT reuse the live overlay's [FOOT_IK_CLIP] log here: it only prints the FIRST frame of each
## penetration episode, so a deepening episode's worst frames are invisible to it - this samples
## every frame.

const MONITOR := preload("res://tools/foot_ik/foot_ik_live_penetration_monitor.gd")
const MAX_DEPTH_M := 0.005
const TOE_TIP_EXTRA_LENGTH := 0.035
const FORWARD := Vector2(0.0, -1.0)
const START := Vector3(15.0, 0.05, -0.8)
const STAIR_APPROACH_Z := -0.25
const TOP_Z := 3.35
const BOTTOM_Z := -0.50
## Turn in place at the top instead of teleporting or resetting IK. The live bug depends on the
## uninterrupted ascent -> turn -> descent history and disappears in a cold descent spawn.
const TURN_FRAMES := 60
const TURN_SETTLE_FRAMES := 20
const MAX_FRAMES := 2000
const GROUNDED_SETTLE_FRAMES := 10

enum Phase { SETTLE, ASCEND, TURN, DESCEND }

var _player: Player
var _ik: PlayerFootIKModifier
var _frame := 0
var _samples := 0
var _ascents := 0
var _descents := 0
var _max_depth := 0.0
var _max_depth_frame := 0
var _max_depth_side := ""
var _max_depth_point := Vector3.ZERO
var _max_depth_root := Vector3.ZERO
var _max_depth_joint := ""
var _max_root_z := -INF
var _done := false
var _grounded_streak := 0
var _phase := Phase.SETTLE
var _turn_frame := 0
var _last_sampled_physics_frame := -1


func _ready() -> void:
	_player = $FootIkPreview/Player
	_player.global_position = START
	_player.rotation = Vector3(0.0, PI, 0.0)
	_player.velocity = Vector3.ZERO
	_player.movement_input_override = Vector2.ZERO
	_ik = _player.body._foot_ik_modifier
	_ik.reset_runtime_state()


func _physics_process(_delta: float) -> void:
	if _done:
		return
	_frame += 1
	if _phase == Phase.SETTLE:
		_player.movement_input_override = Vector2.ZERO
		_grounded_streak = _grounded_streak + 1 if _player.is_on_floor() and _ik.active else 0
		if _grounded_streak < GROUNDED_SETTLE_FRAMES:
			return
		_phase = Phase.ASCEND
	if _phase == Phase.TURN:
		_process_top_turn()
		return
	_player.movement_input_override = FORWARD
	if _phase == Phase.ASCEND and _player.global_position.z >= TOP_Z:
		_ascents = 1
		_phase = Phase.TURN
		_player.movement_input_override = Vector2.ZERO
		return
	if _phase == Phase.DESCEND and _player.global_position.z <= BOTTOM_Z:
		_descents = 1
		_finish()
		return
	if _player.global_position.z < STAIR_APPROACH_Z and _phase == Phase.ASCEND:
		return
	if _frame >= MAX_FRAMES:
		_finish()


func _process(_delta: float) -> void:
	if (_done or not (_phase in [Phase.ASCEND, Phase.DESCEND])
			or (_phase == Phase.ASCEND and _player.global_position.z < STAIR_APPROACH_Z)
			or not _ik.has_fresh_final_bone_poses()):
		return
	var physics_frame := Engine.get_physics_frames()
	if physics_frame == _last_sampled_physics_frame:
		return
	_last_sampled_physics_frame = physics_frame
	_samples += 1
	_max_root_z = maxf(_max_root_z, _player.global_position.z)
	for side: StringName in [&"left", &"right"]:
		var indices: Dictionary = _ik._bone_indices[side]
		var ankle := _world_position(indices["foot"])
		var toe := _world_position(indices["toe"])
		var tip := toe + (toe - ankle).normalized() * TOE_TIP_EXTRA_LENGTH
		var result := MONITOR.check(get_world_3d().direct_space_state,
				PackedVector3Array([ankle, tip]), FootIKGroundSampler.GROUND_COLLISION_MASK)
		if float(result["depth_m"]) > _max_depth:
			_max_depth = float(result["depth_m"])
			_max_depth_frame = physics_frame
			_max_depth_side = str(side)
			_max_depth_point = result["point"]
			_max_depth_root = _player.global_position
			_max_depth_joint = "ankle" if result["point"].distance_to(ankle) < 0.001 else "toe_tip"
func _process_top_turn() -> void:
	_player.movement_input_override = Vector2.ZERO
	_turn_frame += 1
	if _turn_frame <= TURN_FRAMES:
		_player.rotation.y = rotate_toward(_player.rotation.y, 0.0, PI / TURN_FRAMES)
		return
	if _turn_frame < TURN_FRAMES + TURN_SETTLE_FRAMES:
		return
	_player.rotation.y = 0.0
	_phase = Phase.DESCEND


func _finish() -> void:
	_done = true
	var ascended := _max_root_z >= TOP_Z - 0.05 and _ascents == 1
	var traversed := ascended and _descents == 1
	var passed := _samples > 0 and traversed and _max_depth <= MAX_DEPTH_M
	print("FOOT_IK_WALK_CONTACT_CHECK %s samples=%d ascents=%d descents=%d depth_m=%.6f "
			% ["PASS" if passed else "FAIL", _samples, _ascents, _descents, _max_depth]
			+ "frame=%d side=%s joint=%s point=%s root=%s ascended_z=%.3f"
			% [_max_depth_frame, _max_depth_side, _max_depth_joint,
			_max_depth_point, _max_depth_root, _max_root_z])
	get_tree().quit(0 if passed else 1)


func _world_position(index: int) -> Vector3:
	return _player.skeleton.global_transform * _ik.get_final_bone_global_pose(index).origin
