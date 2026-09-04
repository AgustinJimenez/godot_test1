class_name FootIkLedgeSafetyCheck
extends Node3D
## Verifies ledge rejection, safe parallel travel, and supported edge recovery.

const PLATFORM_HEIGHT := 3.0
const PLATFORM_SIZE := Vector3(4.0, PLATFORM_HEIGHT, 4.0)
const START_POSITION := Vector3(0.0, PLATFORM_HEIGHT, -1.80)
const SPLIT_PLATFORM_ORIGIN := Vector3(-8.0, 0.0, 0.0)
const LIVE_SPLIT_ORIGIN := Vector3(-14.0, 0.0, 0.0)
const SPLIT_PLATFORM_DROP := 0.60
const SHORT_FALL_UPPER_Y := 2.10
const SHORT_FALL_LOWER_Y := 1.20
const LANDING_HANDOFF_EDGE_X := 10.0
const UPPER_PENETRATION_EDGE_X := 9.27
const UPPER_PENETRATION_OFFSET := Vector3(12.0, 0.0, 0.0)
const LEG_EDGE_CLIP_OFFSET := Vector3(30.0, 0.0, 0.0)
const LEG_EDGE_X := 8.5 + LEG_EDGE_CLIP_OFFSET.x
const LEG_EDGE_TOP_Y := 0.6
const LEG_CORNER_OFFSET := Vector3(45.0, 0.0, 0.0)
const LEG_CORNER_EDGE_X := 8.5 + LEG_CORNER_OFFSET.x
const LEG_CORNER_EDGE_Z := 4.1
const STAIR_SURFACES := preload("res://tests/manual/foot_ik/foot_ik_stair_surfaces.gd")
const PENETRATION_CHECK := preload(
		"res://tests/manual/foot_ik/foot_ik_live_penetration_check.gd")
const JOINT_LIMIT_CHECK := preload("res://tests/manual/foot_ik/foot_ik_joint_limit_check.gd")
const SHORT_FALL_ANIMATION_CHECK := preload(
		"res://tests/manual/foot_ik/foot_ik_short_fall_animation_check.gd")
const STAIR_ORIGIN := Vector3(8.0, 0.0, 0.0)
const STAIR_WIDTH := 3.0
const STAIR_TREAD_DEPTH := 0.6
const STAIR_COUNT := 6
const STAIR_HEIGHT := 0.35
const SETTLE_FRAMES := 12
const MOVE_FRAMES := 20
const LONG_MOVE_FRAMES := 400
const RECOVERY_FRAMES := 180
const BLOCKED_DISTANCE_LIMIT := 0.02
const PARALLEL_DISTANCE_MIN := 0.30
const ZONE_MIN_LATERAL := 0.06
const ZONE_MAX_LATERAL := 0.56
const ZONE_MAX_LONGITUDINAL := 0.40
const SHORT_FALL_MIN_AIRBORNE_FRAMES := 6
const LANDING_LOWER_SETTLE_FRAME_LIMIT := 13
const LANDING_FOOT_STEP_LIMIT := 0.265
const LANDING_HIP_STEP_LIMIT := 0.15
const LANDING_UPPER_PENETRATION_SAMPLE_THRESHOLD := 0.025
const LANDING_UPPER_PENETRATION_DEPTH_LIMIT := 0.05
const LANDING_UPPER_PENETRATION_FRAME_LIMIT := 3
const SPLIT_TURN_FOOT_STEP_LIMIT := 0.15
const LEG_EDGE_CLEARANCE := 0.04
const LEG_EDGE_MESH_TOLERANCE := 0.003
const LEG_EDGE_MESH_SAMPLE_INTERVAL := 10
const LEG_EDGE_FOOT_STEP_LIMIT := 0.12
var _player: Player
var _ik: PlayerFootIKModifier
var _leg_edge_upper_box: CSGBox3D
var _leg_edge_penetration_check: FootIkLivePenetrationCheck
var _leg_edge_bones: Dictionary = {}
var _leg_corner_upper_box: CSGBox3D
var _leg_corner_bones: Dictionary = {}
var _cases: Array[Dictionary] = [
	{"name": "straight_into_void", "input": Vector2(0.0, -1.0), "blocked": true},
	{"name": "diagonal_left_into_void", "input": Vector2(-1.0, -1.0), "blocked": true},
	{"name": "diagonal_right_into_void", "input": Vector2(1.0, -1.0), "blocked": true},
	{"name": "parallel_to_edge", "input": Vector2(1.0, 0.0), "blocked": false},
	{
		"name": "held_diagonal_stair_landing_edge",
		"input": Vector2(0.707107, 0.707107),
		"blocked": true,
		"start": STAIR_ORIGIN + Vector3(-1.2914, 2.101, 3.840638),
		"yaw": deg_to_rad(-61.0552),
		"move_frames": LONG_MOVE_FRAMES,
		"recovery_frames": RECOVERY_FRAMES,
		"check_feet": true,
	},
	{
		"name": "held_lateral_stair_landing_turn",
		"input": Vector2(-1.0, 0.0),
		"blocked": true,
		"blocked_limit": 0.05,
		"start": STAIR_ORIGIN + Vector3(-1.21045, 2.101, 3.923219),
		"yaw": deg_to_rad(109.69),
		"turn_yaw": deg_to_rad(68.43),
		"turn_hold_frames": 60,
		"turn_steps": 12,
		"move_frames": 114,
		"recovery_frames": 30,
		"check_feet": true,
		"check_zones_during_turn": true,
	},
	{
		"name": "jump_land_middle_of_landing_edge",
		"input": Vector2.ZERO,
		"blocked": true,
		"skip_movement_check": true,
		"start": STAIR_ORIGIN + Vector3(-0.67397, 3.413661, 4.220969),
		"yaw": deg_to_rad(89.06),
		"initial_velocity": Vector3(0.0, -0.226668, 0.0),
		"move_frames": 180,
		"recovery_frames": 60,
		"check_feet": true,
	},
	{
		"name": "idle_split_height_foot_support",
		"input": Vector2.ZERO,
		"blocked": false,
		"skip_movement_check": true,
		"start": SPLIT_PLATFORM_ORIGIN + Vector3(0.0, PLATFORM_HEIGHT, -1.92),
		"yaw": deg_to_rad(90.0),
		"move_frames": 60,
		"recovery_frames": 120,
		"check_feet": true,
		"check_safe_level": true,
		"allow_recovery_motion": true,
	},
	{
		"name": "walk_to_idle_split_height_live_repro",
		"input": Vector2(-0.4, 0.0),
		"blocked": false,
		"skip_movement_check": true,
		"start": LIVE_SPLIT_ORIGIN + Vector3(0.216, PLATFORM_HEIGHT, 0.303),
		"yaw": deg_to_rad(-81.2233),
		"move_frames": 9,
		"recovery_frames": 240,
		"check_feet": true,
		"check_safe_level": true,
		"allow_recovery_motion": true,
	},
	{
		"name": "idle_split_height_target_stability_live_repro",
		"input": Vector2.ZERO,
		"blocked": false,
		"skip_movement_check": true,
		"start": LIVE_SPLIT_ORIGIN + Vector3(-0.04546, PLATFORM_HEIGHT, 0.204419),
		"yaw": deg_to_rad(92.72666),
		"move_frames": 1,
		"recovery_frames": 300,
		"check_feet": true,
		"allow_recovery_motion": true,
		"stability_side": &"left",
		"stability_warmup": 30,
	},
	{
		"name": "jump_land_split_height_commits_safe_support",
		"input": Vector2.ZERO,
		"blocked": false,
		"skip_movement_check": true,
		"start": Vector3(9.839911, 1.48293, 4.049873),
		"yaw": deg_to_rad(97.3103266523861),
		"initial_velocity": Vector3(0.0, -2.840002, 0.0),
		"move_frames": 70,
		"recovery_frames": 70,
		"check_feet": true,
		"check_safe_level": true,
		"allow_recovery_motion": true,
	},
	{
		"name": "jump_land_split_height_upper_foot_penetration_live_repro",
		"input": Vector2.ZERO,
		"blocked": false,
		"skip_movement_check": true,
		"start": Vector3(9.160601, 1.801206, 4.157832) + UPPER_PENETRATION_OFFSET,
		"yaw": deg_to_rad(78.9756742029166),
		"initial_velocity": Vector3(0.0, 0.1, 0.0),
		"move_frames": 70,
		"recovery_frames": 70,
		"check_feet": true,
		"allow_recovery_motion": true,
		"landing_upper_side": &"right",
	},
	{
		"name": "idle_split_height_turn_pause_no_leg_snap_live_repro",
		"input": Vector2.ZERO,
		"blocked": false,
		"skip_movement_check": true,
		"start": Vector3(9.948931, 0.600523, 4.080213),
		"yaw": deg_to_rad(127.517),
		"turn_yaw": deg_to_rad(76.959),
		"turn_hold_frames": 40,
		"turn_steps": 30,
		"move_frames": 120,
		"recovery_frames": 120,
		"check_feet": true,
		"allow_recovery_motion": true,
		"check_safe_level": true,
		"check_zones_during_turn": true,
		"check_split_turn_continuity": true,
		"split_turn_warmup": 30,
	},
	{
		"name": "idle_lower_leg_clears_platform_side_live_repro",
		"input": Vector2.ZERO,
		"blocked": false,
		"skip_movement_check": true,
		"start": Vector3(8.585059, 0.600102, 3.853755) + LEG_EDGE_CLIP_OFFSET,
		"yaw": deg_to_rad(41.8025643055135),
		"move_frames": 1,
		"recovery_frames": 180,
		"check_feet": true,
		"allow_recovery_motion": true,
		"check_safe_level": true,
	},
	{
		"name": "idle_both_lower_legs_clear_platform_corner_live_repro",
		"input": Vector2.ZERO,
		"blocked": false,
		"skip_movement_check": true,
		"start": Vector3(8.602919, 0.600554, 3.874536) + LEG_CORNER_OFFSET,
		"yaw": deg_to_rad(-23.2859675693858),
		"move_frames": 1,
		"recovery_frames": 180,
		"check_feet": true,
		"allow_recovery_motion": true,
		"check_leg_corner": true,
		"leg_corner_warmup": 60,
	},
	{
		"name": "walk_off_verified_short_fall_live_repro",
		"input": Vector2(0.0, -1.0),
		"blocked": false,
		"start": Vector3(13.91262, 2.100216, 3.627019),
		"yaw": deg_to_rad(90.4348191772304),
		"move_frames": 30,
		"recovery_frames": 120,
		"check_feet": true,
		"allow_recovery_motion": true,
		"check_short_fall": true,
	},
]
var _case_index := 0
var _frame_in_case := 0
var _start_position := Vector3.ZERO
var _blocked_end_position := Vector3.ZERO
var _failures: Array[String] = []
var _results: Array[String] = []
var _target_height_min := INF
var _target_height_max := -INF
var _landing_lower_contact_frame := -1
var _landing_lower_settle_frame := -1
var _landing_max_foot_step := 0.0
var _landing_max_hip_step := 0.0
var _landing_max_foot_step_frame := -1
var _landing_max_hip_step_frame := -1
var _landing_previous_points: Dictionary = {}
var _landing_upper_min_clearance := INF
var _landing_upper_penetration_frames := 0
var _split_turn_previous_feet: Dictionary = {}
var _split_turn_max_foot_step := 0.0
var _split_turn_max_foot_step_frame := -1
var _leg_edge_samples := 0
var _leg_edge_worst_clearance := INF
var _leg_edge_mesh_samples := 0
var _leg_edge_mesh_penetrating_samples := 0
var _leg_edge_mesh_vertices := 0
var _leg_edge_mesh_max_depth := 0.0
var _leg_edge_previous_foot := Vector3.ZERO
var _leg_edge_has_previous_foot := false
var _leg_edge_max_foot_step := 0.0
var _leg_edge_max_foot_step_frame := -1
var _leg_corner_samples := 0
var _leg_corner_worst_clearance := INF
var _leg_corner_mesh_samples := 0
var _leg_corner_mesh_penetrating_samples := 0
var _leg_corner_mesh_vertices := 0
var _leg_corner_mesh_max_depth := 0.0
var _leg_corner_mesh_bones: Dictionary = {}
var _short_fall_airborne_seen := false
var _short_fall_landed_lower_seen := false
var _short_fall_airborne_frames := 0
var _short_fall_animation_seen := false


func _ready() -> void:
	_build_platform()
	_build_split_height_platform()
	_build_live_split_height_platform()
	_build_latest_latch_repro_surface()
	_build_landing_handoff_split()
	_build_upper_penetration_split()
	_build_leg_edge_clip_split()
	_build_leg_corner_clip_split()
	_build_short_fall_platforms()
	_build_stair_landing()
	var player_scene: PackedScene = load("res://actors/player/player.tscn")
	_player = player_scene.instantiate() as Player
	add_child(_player)
	_leg_edge_penetration_check = PENETRATION_CHECK.new()
	STAIR_SURFACES.configure_player(_player)
	for child in _player.skeleton.get_children():
		if child is PlayerFootIKModifier:
			_ik = child
			break
	for role: StringName in [&"LeftUpLeg", &"LeftLeg", &"LeftFoot", &"LeftToeBase"]:
		_leg_edge_bones[_player.body.resolve_bone_name(role)] = true
	for role: StringName in [&"LeftUpLeg", &"LeftLeg", &"LeftFoot", &"LeftToeBase",
			&"RightUpLeg", &"RightLeg", &"RightFoot", &"RightToeBase"]:
		_leg_corner_bones[_player.body.resolve_bone_name(role)] = true
	var left_leaf: int = _ik._bone_indices[&"left"][&"leaf"]
	if left_leaf >= 0:
		_leg_edge_bones[_player.skeleton.get_bone_name(left_leaf)] = true
		_leg_corner_bones[_player.skeleton.get_bone_name(left_leaf)] = true
	var right_leaf: int = _ik._bone_indices[&"right"][&"leaf"]
	if right_leaf >= 0:
		_leg_corner_bones[_player.skeleton.get_bone_name(right_leaf)] = true
	_reset_case()

func _build_platform() -> void:
	var static_body := StaticBody3D.new()
	var collision := CollisionShape3D.new()
	var box_shape := BoxShape3D.new()
	box_shape.size = PLATFORM_SIZE
	collision.shape = box_shape
	static_body.add_child(collision)
	static_body.position = Vector3(0.0, PLATFORM_HEIGHT * 0.5, 0.0)
	add_child(static_body)

func _build_split_height_platform() -> void:
	var upper := StaticBody3D.new()
	var upper_collision := CollisionShape3D.new()
	var upper_shape := BoxShape3D.new()
	upper_shape.size = PLATFORM_SIZE
	upper_collision.shape = upper_shape
	upper.add_child(upper_collision)
	upper.position = SPLIT_PLATFORM_ORIGIN + Vector3(0.0, PLATFORM_HEIGHT * 0.5, 0.0)
	add_child(upper)
	var lower_height := PLATFORM_HEIGHT - SPLIT_PLATFORM_DROP
	var lower := StaticBody3D.new()
	var lower_collision := CollisionShape3D.new()
	var lower_shape := BoxShape3D.new()
	lower_shape.size = Vector3(4.0, lower_height, 2.0)
	lower_collision.shape = lower_shape
	lower.add_child(lower_collision)
	lower.position = SPLIT_PLATFORM_ORIGIN + Vector3(0.0, lower_height * 0.5, -3.0)
	add_child(lower)


func _build_live_split_height_platform() -> void:
	var upper := StaticBody3D.new()
	var upper_collision := CollisionShape3D.new()
	var upper_shape := BoxShape3D.new()
	upper_shape.size = Vector3(2.0, PLATFORM_HEIGHT, 4.0)
	upper_collision.shape = upper_shape
	upper.add_child(upper_collision)
	upper.position = LIVE_SPLIT_ORIGIN + Vector3(1.0, PLATFORM_HEIGHT * 0.5, 0.0)
	add_child(upper)
	var lower_height := PLATFORM_HEIGHT - SPLIT_PLATFORM_DROP
	var lower := StaticBody3D.new()
	var lower_collision := CollisionShape3D.new()
	var lower_shape := BoxShape3D.new()
	lower_shape.size = Vector3(2.0, lower_height, 4.0)
	lower_collision.shape = lower_shape
	lower.add_child(lower_collision)
	lower.position = LIVE_SPLIT_ORIGIN + Vector3(-1.0, lower_height * 0.5, 0.0)
	add_child(lower)


func _build_latest_latch_repro_surface() -> void:
	# Lower tread under the exact stale targets from the latest live trace.
	# It deliberately provides real collision so the regression proves that
	# collision support cannot make an out-of-zone cached target valid.
	var lower := StaticBody3D.new()
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(2.0, 1.75, 2.0)
	collision.shape = shape
	lower.add_child(collision)
	lower.position = Vector3(14.9, 0.875, 2.0)
	add_child(lower)


func _build_landing_handoff_split() -> void:
	var upper := StaticBody3D.new()
	var upper_collision := CollisionShape3D.new()
	var upper_shape := BoxShape3D.new()
	upper_shape.size = Vector3(2.0, 0.6, 4.0)
	upper_collision.shape = upper_shape
	upper.add_child(upper_collision)
	upper.position = Vector3(LANDING_HANDOFF_EDGE_X - 1.0, 0.3, 4.0)
	add_child(upper)
	var lower := StaticBody3D.new()
	var lower_collision := CollisionShape3D.new()
	var lower_shape := BoxShape3D.new()
	lower_shape.size = Vector3(2.0, 1.0, 4.0)
	lower_collision.shape = lower_shape
	lower.add_child(lower_collision)
	lower.position = Vector3(LANDING_HANDOFF_EDGE_X + 1.0, -0.5, 4.0)
	add_child(lower)


func _build_upper_penetration_split() -> void:
	var upper := StaticBody3D.new()
	var upper_collision := CollisionShape3D.new()
	var upper_shape := BoxShape3D.new()
	upper_shape.size = Vector3(2.0, 0.6, 4.0)
	upper_collision.shape = upper_shape
	upper.add_child(upper_collision)
	upper.position = Vector3(UPPER_PENETRATION_EDGE_X + 1.0, 0.3, 4.0) \
			+ UPPER_PENETRATION_OFFSET
	add_child(upper)
	var lower := StaticBody3D.new()
	var lower_collision := CollisionShape3D.new()
	var lower_shape := BoxShape3D.new()
	lower_shape.size = Vector3(2.0, 1.0, 4.0)
	lower_collision.shape = lower_shape
	lower.add_child(lower_collision)
	lower.position = Vector3(UPPER_PENETRATION_EDGE_X - 1.0, -0.5, 4.0) \
			+ UPPER_PENETRATION_OFFSET
	add_child(lower)


func _build_leg_edge_clip_split() -> void:
	# Exact side edge under the final pose from the live frame-1245 capture.
	# The upper slab occupies +X; the lower foot is allowed to plant on -X.
	_leg_edge_upper_box = CSGBox3D.new()
	_leg_edge_upper_box.size = Vector3(3.0, LEG_EDGE_TOP_Y, 4.0)
	_leg_edge_upper_box.position = Vector3(
			LEG_EDGE_X + 1.5, LEG_EDGE_TOP_Y * 0.5, 5.6)
	_leg_edge_upper_box.use_collision = true
	add_child(_leg_edge_upper_box)
	_add_short_fall_box(Vector3(LEG_EDGE_X - 1.5, -0.5, 5.6),
			Vector3(3.0, 1.0, 4.0))


func _build_leg_corner_clip_split() -> void:
	# Exact 0.10m-stair top landing bounds under the newest live corner stance.
	_leg_corner_upper_box = CSGBox3D.new()
	_leg_corner_upper_box.size = Vector3(3.0, LEG_EDGE_TOP_Y, 0.5)
	_leg_corner_upper_box.position = Vector3(
			LEG_CORNER_EDGE_X + 1.5, LEG_EDGE_TOP_Y * 0.5, 3.85)
	_leg_corner_upper_box.use_collision = true
	add_child(_leg_corner_upper_box)
	_add_short_fall_box(Vector3(LEG_CORNER_EDGE_X + 0.5, -0.5, 3.85),
			Vector3(7.0, 1.0, 5.0))


func _build_short_fall_platforms() -> void:
	# Exact neighboring top landings from the live 0.35m/0.20m stair cases:
	# crossing toward -X drops 0.90m onto a known, wide lower surface.
	_add_short_fall_box(Vector3(15.0, SHORT_FALL_UPPER_Y * 0.5, 3.65),
			Vector3(3.0, SHORT_FALL_UPPER_Y, 2.0))
	_add_short_fall_box(Vector3(12.5, SHORT_FALL_LOWER_Y * 0.5, 3.65),
			Vector3(3.0, SHORT_FALL_LOWER_Y, 2.0))


func _add_short_fall_box(position: Vector3, size: Vector3) -> void:
	var body := StaticBody3D.new()
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collision.shape = shape
	body.add_child(collision)
	body.position = position
	add_child(body)


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


func _physics_process(_delta: float) -> void:
	if _case_index >= _cases.size():
		return
	_frame_in_case += 1
	if _frame_in_case == SETTLE_FRAMES:
		_start_position = _player.global_position
		_player.velocity = Vector3.ZERO
		_player.ledge_safety_enabled = true
		_player.movement_input_override = _cases[_case_index]["input"]
	var data: Dictionary = _cases[_case_index]
	var move_frames: int = data.get("move_frames", MOVE_FRAMES)
	var recovery_frames: int = data.get("recovery_frames", 0)
	_update_turn_case(data)
	_sample_target_stability(data)
	_sample_landing_lower_handoff(data)
	_sample_landing_upper_penetration(data)
	_sample_split_turn_continuity(data)
	_sample_leg_edge_clearance(data)
	_sample_leg_corner_clearance(data)
	_sample_short_fall(data)
	if recovery_frames > 0 and _frame_in_case == SETTLE_FRAMES + move_frames:
		_blocked_end_position = _player.global_position
		_player.movement_input_override = Vector2.ZERO
	elif _frame_in_case >= SETTLE_FRAMES + move_frames + recovery_frames:
		if recovery_frames == 0:
			_blocked_end_position = _player.global_position
		_evaluate_case()
		_case_index += 1
		if _case_index < _cases.size():
			_reset_case()
		else:
			_finish_check()


func _update_turn_case(data: Dictionary) -> void:
	if not data.get("check_zones_during_turn", false):
		return
	var turn_tick := _frame_in_case - SETTLE_FRAMES - int(data["turn_hold_frames"])
	var turn_steps := int(data["turn_steps"])
	if turn_tick < 1 or turn_tick > turn_steps * 2:
		return
	if turn_tick % 2 == 1:
		var step := (turn_tick + 1) / 2
		_player.rotation.y = lerp_angle(float(data["yaw"]), float(data["turn_yaw"]),
				float(step) / float(turn_steps))
		_player._look_yaw = 0.0
		_player.head.rotation.y = 0.0
		_player.third_person_arm.rotation.y = 0.0
	else:
		_sample_safe_zones(String(data["name"]), turn_tick)


func _sample_safe_zones(case_name: String, turn_tick: int) -> void:
	var left_hip := _final_bone_world(&"left", &"hip")
	var right_hip := _final_bone_world(&"right", &"hip")
	var left_dir := left_hip - right_hip
	left_dir.y = 0.0
	if left_dir.length_squared() <= 0.0001:
		return
	left_dir = left_dir.normalized()
	var forward_dir := Vector3.UP.cross(left_dir).normalized()
	for side: StringName in [&"left", &"right"]:
		var foot := _final_bone_world(side, &"foot")
		var from_root := foot - _player.global_position
		var side_sign := 1.0 if side == &"left" else -1.0
		var lateral := from_root.dot(left_dir) * side_sign
		var longitudinal := from_root.dot(forward_dir)
		if (lateral < ZONE_MIN_LATERAL or lateral > ZONE_MAX_LATERAL
				or absf(longitudinal) > ZONE_MAX_LONGITUDINAL):
			_failures.append(("%s turn_tick=%d side=%s safe zone " + \
					"lateral=%.3f longitudinal=%.3f") % [
					case_name, turn_tick, side, lateral, longitudinal])


func _sample_target_stability(data: Dictionary) -> void:
	if not data.has("stability_side"):
		return
	var warmup_frame := SETTLE_FRAMES + int(data.get("stability_warmup", 0))
	if _frame_in_case < warmup_frame:
		return
	var side: StringName = data["stability_side"]
	var target: Vector3 = _ik._smoothed_target.get(side, Vector3.ZERO)
	_target_height_min = minf(_target_height_min, target.y)
	_target_height_max = maxf(_target_height_max, target.y)


func _sample_landing_lower_handoff(data: Dictionary) -> void:
	if not data.has("landing_lower_side"):
		return
	var side: StringName = data["landing_lower_side"]
	var surface: Vector3 = _ik._smoothed_target.get(side, Vector3.ZERO)
	var lower_contact: bool = (_ik.debug_contact_hit.get(side, false)
			and _player.global_position.y - surface.y >= 0.3)
	if lower_contact and _landing_lower_contact_frame < 0:
		_landing_lower_contact_frame = _frame_in_case
	var root := _player.global_position
	var points := {
		&"left_foot": _final_bone_world(&"left", &"foot") - root,
		&"right_foot": _final_bone_world(&"right", &"foot") - root,
		&"hips": ((_final_bone_world(&"left", &"hip")
				+ _final_bone_world(&"right", &"hip")) * 0.5) - root,
	}
	if not _landing_previous_points.is_empty() and _landing_lower_contact_frame >= 0:
		var foot_step := maxf(
				(points[&"left_foot"] as Vector3).distance_to(_landing_previous_points[&"left_foot"]),
				(points[&"right_foot"] as Vector3).distance_to(_landing_previous_points[&"right_foot"]))
		var hip_step: float = (points[&"hips"] as Vector3).distance_to(
				_landing_previous_points[&"hips"])
		if foot_step > _landing_max_foot_step:
			_landing_max_foot_step = foot_step
			_landing_max_foot_step_frame = _frame_in_case
		if hip_step > _landing_max_hip_step:
			_landing_max_hip_step = hip_step
			_landing_max_hip_step_frame = _frame_in_case
	_landing_previous_points = points
	if not lower_contact:
		return
	var foot: Vector3 = points[side + &"_foot"] + root
	var offset: float = _ik._ground_sampler.debug_effective_offset.get(side, 0.0)
	if foot.y - (surface.y + offset) <= 0.12 and _landing_lower_settle_frame < 0:
		_landing_lower_settle_frame = _frame_in_case


func _sample_landing_upper_penetration(data: Dictionary) -> void:
	if not data.has("landing_upper_side") or not _player.is_on_floor():
		return
	var side: StringName = data["landing_upper_side"]
	var surface: Vector3 = _ik._smoothed_target.get(side, Vector3.ZERO)
	if absf(surface.y - 0.6) > 0.05:
		return
	var clearance := _final_sole_clearance(side, surface.y)
	_landing_upper_min_clearance = minf(_landing_upper_min_clearance, clearance)
	if clearance < -LANDING_UPPER_PENETRATION_SAMPLE_THRESHOLD:
		_landing_upper_penetration_frames += 1
func _sample_split_turn_continuity(data: Dictionary) -> void:
	if not data.get("check_split_turn_continuity", false):
		return
	if _frame_in_case < SETTLE_FRAMES + int(data.get("split_turn_warmup", 0)):
		return
	if _frame_in_case > SETTLE_FRAMES + int(data.get("move_frames", MOVE_FRAMES)) + 30:
		return
	var root := _player.global_position
	var feet := {
		&"left": _final_bone_world(&"left", &"foot") - root,
		&"right": _final_bone_world(&"right", &"foot") - root,
	}
	if not _split_turn_previous_feet.is_empty():
		var left_step: float = (feet[&"left"] as Vector3).distance_to(
				_split_turn_previous_feet[&"left"])
		var right_step: float = (feet[&"right"] as Vector3).distance_to(
				_split_turn_previous_feet[&"right"])
		var step := maxf(left_step, right_step)
		if step > _split_turn_max_foot_step:
			_split_turn_max_foot_step = step
			_split_turn_max_foot_step_frame = _frame_in_case
	_split_turn_previous_feet = feet
func _sample_leg_edge_clearance(data: Dictionary) -> void:
	if not data.has("leg_edge_lower_side"):
		return
	var side: StringName = data["leg_edge_lower_side"]
	var foot := _final_bone_world(side, &"foot") - _player.global_position
	if _leg_edge_has_previous_foot:
		var foot_step := foot.distance_to(_leg_edge_previous_foot)
		if foot_step > _leg_edge_max_foot_step:
			_leg_edge_max_foot_step = foot_step
			_leg_edge_max_foot_step_frame = _frame_in_case
	_leg_edge_previous_foot = foot
	_leg_edge_has_previous_foot = true
	var warmup := SETTLE_FRAMES + int(data.get("leg_edge_warmup", 0))
	if _frame_in_case < warmup:
		return
	var surface: Vector3 = _ik._smoothed_target.get(side, Vector3.ZERO)
	if absf(surface.y) > 0.05:
		return
	var knee := _final_bone_world(side, &"knee")
	var top_y := float(data["leg_edge_top_y"])
	if knee.y >= top_y:
		return
	var clearance := float(data["leg_edge_x"]) - knee.x
	_leg_edge_samples += 1
	_leg_edge_worst_clearance = minf(_leg_edge_worst_clearance, clearance)
	if _frame_in_case % LEG_EDGE_MESH_SAMPLE_INTERVAL != 0:
		return
	var sample := _leg_edge_penetration_check.sample_box_volume(
			_player, _ik, _leg_edge_bones, _leg_edge_upper_box, LEG_EDGE_MESH_TOLERANCE)
	if not sample.get("available", false):
		return
	_leg_edge_mesh_samples += 1
	var vertices := int(sample["vertices"])
	if vertices > 0:
		_leg_edge_mesh_penetrating_samples += 1
		_leg_edge_mesh_vertices += vertices
		_leg_edge_mesh_max_depth = maxf(_leg_edge_mesh_max_depth, float(sample["max_depth"]))


func _sample_leg_corner_clearance(data: Dictionary) -> void:
	if not data.get("check_leg_corner", false):
		return
	var warmup := SETTLE_FRAMES + int(data.get("leg_corner_warmup", 0))
	if _frame_in_case < warmup:
		return
	var left_surface: Vector3 = _ik._smoothed_target.get(&"left", Vector3.ZERO)
	var right_surface: Vector3 = _ik._smoothed_target.get(&"right", Vector3.ZERO)
	if absf(left_surface.y) > 0.05 or absf(right_surface.y) > 0.05:
		return
	var left_knee := _final_bone_world(&"left", &"knee")
	var right_knee := _final_bone_world(&"right", &"knee")
	if left_knee.y < LEG_EDGE_TOP_Y:
		_leg_corner_samples += 1
		_leg_corner_worst_clearance = minf(
				_leg_corner_worst_clearance, LEG_CORNER_EDGE_X - left_knee.x)
	if right_knee.y < LEG_EDGE_TOP_Y:
		_leg_corner_samples += 1
		_leg_corner_worst_clearance = minf(
				_leg_corner_worst_clearance, right_knee.z - LEG_CORNER_EDGE_Z)
	if _frame_in_case % LEG_EDGE_MESH_SAMPLE_INTERVAL != 0:
		return
	var sample := _leg_edge_penetration_check.sample_box_volume(
			_player, _ik, _leg_corner_bones, _leg_corner_upper_box, LEG_EDGE_MESH_TOLERANCE)
	if not sample.get("available", false):
		return
	_leg_corner_mesh_samples += 1
	var vertices := int(sample["vertices"])
	if vertices > 0:
		_leg_corner_mesh_penetrating_samples += 1
		_leg_corner_mesh_vertices += vertices
		_leg_corner_mesh_max_depth = maxf(
				_leg_corner_mesh_max_depth, float(sample["max_depth"]))
		for bone: StringName in sample["bones"]:
			_leg_corner_mesh_bones[bone] = int(_leg_corner_mesh_bones.get(bone, 0)) \
					+ int(sample["bones"][bone])


func _sample_short_fall(data: Dictionary) -> void:
	if not data.get("check_short_fall", false) or _frame_in_case < SETTLE_FRAMES:
		return
	if not _player.is_on_floor():
		_short_fall_airborne_seen = true
		_short_fall_airborne_frames += 1
		_short_fall_animation_seen = _short_fall_animation_seen \
				or _player.body.anim_player.current_animation.get_file().contains("jump")
	elif (_short_fall_airborne_seen
			and absf(_player.global_position.y - SHORT_FALL_LOWER_Y) < 0.08):
		_short_fall_landed_lower_seen = true


func _final_bone_world(side: StringName, joint: StringName) -> Vector3:
	var bone_idx: int = _ik._bone_indices[side][joint]
	var pose: Transform3D = _ik._final_bone_poses.get(
			bone_idx, _player.skeleton.get_bone_global_pose(bone_idx))
	return _player.skeleton.global_transform * pose.origin


func _final_sole_clearance(side: StringName, surface_y: float) -> float:
	var foot_idx: int = _ik._bone_indices[side][&"foot"]
	var pose: Transform3D = _ik._final_bone_poses.get(
			foot_idx, _player.skeleton.get_bone_global_pose(foot_idx))
	var to_world := _player.skeleton.global_transform
	var foot_world: Vector3 = to_world * pose.origin
	var sole_down: Vector3 = (to_world.basis * pose.basis
			* (_ik._sole_down_local[side] as Vector3)).normalized()
	var sole_depth: float = _ik._sole_depth_below_foot.get(side, _ik.ankle_offset)
	return foot_world.y + sole_down.y * sole_depth - surface_y


func _reset_case() -> void:
	_player.ledge_safety_enabled = false
	_player.movement_input_override = Vector2.ZERO
	var data: Dictionary = _cases[_case_index]
	_player.global_position = data.get("start", START_POSITION)
	_player.rotation = Vector3(0.0, data.get("yaw", 0.0), 0.0)
	_player._look_yaw = 0.0
	_player.head.rotation.y = 0.0
	_player.third_person_arm.rotation.y = 0.0
	_player.velocity = data.get("initial_velocity", Vector3.ZERO)
	_blocked_end_position = _player.global_position
	if _ik != null:
		_ik.reset_runtime_state()
	_target_height_min = INF
	_target_height_max = -INF
	_landing_lower_contact_frame = -1
	_landing_lower_settle_frame = -1
	_landing_max_foot_step = 0.0
	_landing_max_hip_step = 0.0
	_landing_max_foot_step_frame = -1
	_landing_max_hip_step_frame = -1
	_landing_previous_points.clear()
	_landing_upper_min_clearance = INF
	_landing_upper_penetration_frames = 0
	_split_turn_previous_feet.clear()
	_split_turn_max_foot_step = 0.0
	_split_turn_max_foot_step_frame = -1
	_short_fall_airborne_seen = false
	_short_fall_landed_lower_seen = false
	_short_fall_airborne_frames = 0
	_short_fall_animation_seen = false
	_leg_edge_samples = 0
	_leg_edge_worst_clearance = INF
	_leg_edge_mesh_samples = 0
	_leg_edge_mesh_penetrating_samples = 0
	_leg_edge_mesh_vertices = 0
	_leg_edge_mesh_max_depth = 0.0
	_leg_edge_previous_foot = Vector3.ZERO
	_leg_edge_has_previous_foot = false
	_leg_edge_max_foot_step = 0.0
	_leg_edge_max_foot_step_frame = -1
	_leg_corner_samples = 0
	_leg_corner_worst_clearance = INF
	_leg_corner_mesh_samples = 0
	_leg_corner_mesh_penetrating_samples = 0
	_leg_corner_mesh_vertices = 0
	_leg_corner_mesh_max_depth = 0.0
	_leg_corner_mesh_bones.clear()
	_frame_in_case = 0


func _evaluate_case() -> void:
	var data: Dictionary = _cases[_case_index]
	_failures.append_array(JOINT_LIMIT_CHECK.failures(_ik, _player.skeleton, String(data["name"])))
	var displacement := Vector2(
			_blocked_end_position.x - _start_position.x,
			_blocked_end_position.z - _start_position.z).length()
	var recovery := Vector2(_player.global_position.x - _blocked_end_position.x,
			_player.global_position.z - _blocked_end_position.z).length()
	var left_weight := float(_ik._smoothed_ground_weight.get(&"left", 0.0))
	var right_weight := float(_ik._smoothed_ground_weight.get(&"right", 0.0))
	var contacts := "%s/%s" % [_ik.debug_contact_hit.get(&"left", false),
			_ik.debug_contact_hit.get(&"right", false)]
	_results.append(("%s start=%s blocked_end=%s end=%s moved=%.3f recovery=%.3f " + \
			"floor=%s normal=%s contacts=%s weights=%.2f/%.2f retracted=%s targets=%s/%s raw=%s/%s") % [
			data["name"], _start_position,
			_blocked_end_position, _player.global_position, displacement, recovery,
			str(_player.is_on_floor()), str(_player.get_floor_normal()), contacts, left_weight, right_weight,
			str(_ik.debug_retracted), str(_ik._smoothed_target.get(&"left", Vector3.ZERO)),
			str(_ik._smoothed_target.get(&"right", Vector3.ZERO)),
			str(_ik._ground_sampler.debug_raw_target.get(&"left", Vector3.ZERO)),
			str(_ik._ground_sampler.debug_raw_target.get(&"right", Vector3.ZERO))])
	if data.get("skip_movement_check", false):
		pass
	elif bool(data["blocked"]):
		var blocked_limit: float = data.get("blocked_limit", BLOCKED_DISTANCE_LIMIT)
		if displacement > blocked_limit:
			_failures.append("%s moved %.3fm (limit %.3fm)" % [
					data["name"], displacement, blocked_limit])
	elif displacement < PARALLEL_DISTANCE_MIN:
		_failures.append("%s moved only %.3fm (minimum %.3fm)" % [
				data["name"], displacement, PARALLEL_DISTANCE_MIN])
	if data.get("check_feet", false):
		if (not data.get("allow_recovery_motion", false)
				and (_player.global_position.x < _blocked_end_position.x - 0.005
				or _player.global_position.z > _blocked_end_position.z + 0.005)):
			_failures.append("%s recovery moved toward an unsupported landing edge" % data["name"])
		var left_hit := bool(_ik.debug_contact_hit.get(&"left", false))
		var right_hit := bool(_ik.debug_contact_hit.get(&"right", false))
		if not left_hit or not right_hit or left_weight < 0.99 or right_weight < 0.99:
			_failures.append("%s final feet contacts=%s weights=%.2f/%.2f" % [
					data["name"], contacts, left_weight, right_weight])
	if data.get("check_split_height", false):
		var root_motion := Vector2(_player.global_position.x - _start_position.x,
				_player.global_position.z - _start_position.z).length()
		var left_target: Vector3 = _ik._ground_sampler.debug_raw_target.get(
				&"left", Vector3.ZERO)
		var right_target: Vector3 = _ik._ground_sampler.debug_raw_target.get(
				&"right", Vector3.ZERO)
		var target_height_delta := absf(left_target.y - right_target.y)
		if data.get("check_root_still", false) and root_motion > 0.03:
			_failures.append("%s idle recovery moved root %.3fm" % [data["name"], root_motion])
		if target_height_delta < SPLIT_PLATFORM_DROP - 0.05:
			_failures.append("%s target height split %.3fm (expected %.3fm)" % [
					data["name"], target_height_delta, SPLIT_PLATFORM_DROP])
	if data.get("check_safe_level", false):
		var left_safe_target: Vector3 = _ik._ground_sampler.debug_raw_target.get(
				&"left", Vector3.ZERO)
		var right_safe_target: Vector3 = _ik._ground_sampler.debug_raw_target.get(
				&"right", Vector3.ZERO)
		var safe_height_delta := absf(left_safe_target.y - right_safe_target.y)
		if safe_height_delta > 0.05:
			_failures.append("%s retained unsafe target height split %.3fm" % [
					data["name"], safe_height_delta])
	if data.has("stability_side"):
		var target_range := _target_height_max - _target_height_min
		if target_range > 0.08:
			_failures.append("%s target height cycled %.3fm (limit 0.080m)" % [
					data["name"], target_range])
		var stability_side: StringName = data["stability_side"]
		var final_foot := _final_bone_world(stability_side, &"foot")
		var final_surface: Vector3 = _ik._smoothed_target.get(stability_side, Vector3.ZERO)
		var effective_offset: float = _ik._ground_sampler.debug_effective_offset.get(
				stability_side, 0.0)
		var final_height_error := absf(final_foot.y - (final_surface.y + effective_offset))
		if final_height_error > 0.08:
			_failures.append("%s final planted height error %.3fm (limit 0.080m)" % [
					data["name"], final_height_error])
	if data.has("landing_lower_side"):
		if _landing_lower_contact_frame < 0:
			_failures.append("%s never sampled lower landing contact" % data["name"])
		elif _landing_lower_settle_frame < 0:
			_failures.append("%s lower foot never reached support" % data["name"])
		elif (_landing_lower_settle_frame - _landing_lower_contact_frame
				> LANDING_LOWER_SETTLE_FRAME_LIMIT):
			_failures.append("%s lower foot took %d frames to settle (limit %d)" % [
					data["name"], _landing_lower_settle_frame - _landing_lower_contact_frame,
					LANDING_LOWER_SETTLE_FRAME_LIMIT])
		if _landing_max_foot_step > LANDING_FOOT_STEP_LIMIT:
			_failures.append("%s rendered foot snapped %.3fm at frame %d (limit %.3fm)" % [
					data["name"], _landing_max_foot_step, _landing_max_foot_step_frame,
					LANDING_FOOT_STEP_LIMIT])
		if _landing_max_hip_step > LANDING_HIP_STEP_LIMIT:
			_failures.append("%s rendered hips snapped %.3fm at frame %d (limit %.3fm)" % [
					data["name"], _landing_max_hip_step, _landing_max_hip_step_frame,
					LANDING_HIP_STEP_LIMIT])
	if data.has("landing_upper_side"):
		if not is_finite(_landing_upper_min_clearance):
			_failures.append("%s never sampled upper landing support" % data["name"])
		elif (_landing_upper_min_clearance < -LANDING_UPPER_PENETRATION_DEPTH_LIMIT
				or _landing_upper_penetration_frames > LANDING_UPPER_PENETRATION_FRAME_LIMIT):
			_failures.append(("%s upper foot penetrated %.3fm for %d frames "
					+ "(limits %.3fm/%d frames)") % [data["name"], -_landing_upper_min_clearance,
					_landing_upper_penetration_frames, LANDING_UPPER_PENETRATION_DEPTH_LIMIT,
					LANDING_UPPER_PENETRATION_FRAME_LIMIT])
	if data.get("check_split_turn_continuity", false):
		if _split_turn_max_foot_step > SPLIT_TURN_FOOT_STEP_LIMIT:
			_failures.append("%s rendered foot snapped %.3fm at frame %d (limit %.3fm)" % [
					data["name"], _split_turn_max_foot_step, _split_turn_max_foot_step_frame,
					SPLIT_TURN_FOOT_STEP_LIMIT])
	if data.has("leg_edge_lower_side"):
		if _leg_edge_samples == 0:
			_failures.append("%s never sampled the lower knee beside the slab" % data["name"])
		elif _leg_edge_worst_clearance < LEG_EDGE_CLEARANCE:
			_failures.append(("%s lower knee cleared side by %.3fm "
					+ "(minimum %.3fm)") % [data["name"], _leg_edge_worst_clearance,
					LEG_EDGE_CLEARANCE])
		if _leg_edge_mesh_samples == 0:
			_failures.append("%s never sampled the rendered leg mesh" % data["name"])
		elif _leg_edge_mesh_penetrating_samples > 0:
			_failures.append(("%s rendered leg entered slab in %d/%d samples "
					+ "vertices=%d max_depth=%.3fm") % [data["name"],
					_leg_edge_mesh_penetrating_samples, _leg_edge_mesh_samples,
					_leg_edge_mesh_vertices, _leg_edge_mesh_max_depth])
		if _leg_edge_max_foot_step > LEG_EDGE_FOOT_STEP_LIMIT:
			_failures.append(("%s lower foot snapped %.3fm at frame %d "
					+ "(limit %.3fm)") % [data["name"], _leg_edge_max_foot_step,
					_leg_edge_max_foot_step_frame, LEG_EDGE_FOOT_STEP_LIMIT])
	if data.get("check_leg_corner", false):
		if _leg_corner_samples == 0:
			_failures.append("%s never sampled lower knees beside the corner" % data["name"])
		elif _leg_corner_worst_clearance < LEG_EDGE_CLEARANCE:
			_failures.append(("%s lower knee cleared corner by %.3fm "
					+ "(minimum %.3fm)") % [data["name"], _leg_corner_worst_clearance,
					LEG_EDGE_CLEARANCE])
		if _leg_corner_mesh_samples == 0:
			_failures.append("%s never sampled rendered leg meshes at corner" % data["name"])
		elif _leg_corner_mesh_penetrating_samples > 0:
			_failures.append(("%s rendered legs entered corner slab in %d/%d samples "
					+ "vertices=%d max_depth=%.3fm bones=%s") % [data["name"],
					_leg_corner_mesh_penetrating_samples, _leg_corner_mesh_samples,
					_leg_corner_mesh_vertices, _leg_corner_mesh_max_depth,
					str(_leg_corner_mesh_bones)])
	if data.get("check_short_fall", false):
		if not _short_fall_airborne_seen:
			_failures.append("%s never became airborne" % data["name"])
		elif _short_fall_airborne_frames < SHORT_FALL_MIN_AIRBORNE_FRAMES:
			_failures.append("%s was airborne for only %d frames" % [
					data["name"], _short_fall_airborne_frames])
		if not _short_fall_animation_seen:
			_failures.append("%s never entered a fall animation" % data["name"])
		if not _short_fall_landed_lower_seen:
			_failures.append("%s never landed on the 0.90m lower surface" % data["name"])


func _finish_check() -> void:
	_player.movement_input_override = Vector2.ZERO
	_check_zero_delta_idle_support_recovery()
	_check_live_out_of_zone_lower_targets()
	_failures.append_array(SHORT_FALL_ANIMATION_CHECK.failures(_player.body))
	print("FOOT_IK_LEDGE_SAFETY_CASES %s" % "; ".join(_results))
	if not _failures.is_empty():
		print("FOOT_IK_LEDGE_SAFETY_CHECK FAIL failures=%d details=%s" % [
				_failures.size(), "; ".join(_failures)])
		get_tree().quit(1)
		return
	print("FOOT_IK_LEDGE_SAFETY_CHECK PASS cases=%d" % _cases.size())
	get_tree().quit(0)


func _check_zero_delta_idle_support_recovery() -> void:
	var side := &"left"
	var foot_idx: int = _ik._bone_indices[side][&"foot"]
	var foot_pose := _player.skeleton.get_bone_global_pose(foot_idx)
	var to_world := _player.skeleton.global_transform
	var foot_world := to_world * foot_pose.origin
	_player.velocity = Vector3.ZERO
	_player.body.anim_player.play(&"moves/unarmed_idle", 0.0)
	_ik._grounded = true
	_ik._smoothed_ground_weight[side] = 0.208333333333333
	var gait: Dictionary = _ik._gait_tracker.update(
			side, foot_pose.origin, foot_world, foot_world,
			true, 0.0, to_world, 0.0)
	var recovered_weight := float(gait["ground_weight"])
	if recovered_weight < 0.999:
		_failures.append("zero-delta supported idle weight stayed at %.3f" % recovered_weight)


func _check_live_out_of_zone_lower_targets() -> void:
	# Exact root, yaw, and retained targets from the live frame-17 recurrence.
	# Both targets hit a real lower tread, but are far outside the colored
	# stance rectangles and therefore must never be retained by the idle latch.
	_player.global_position = Vector3(14.30875, 2.101, 3.75454)
	_player.rotation.y = deg_to_rad(67.7457025658242)
	var targets := {
		&"left": Vector3(14.80368, 1.75, 2.602207),
		&"right": Vector3(15.00317, 1.75, 2.644278),
	}
	_player.velocity = Vector3.ZERO
	_ik._grounded = true
	_ik._landing_grace_time = 0.0
	var space := get_world_3d().direct_space_state
	for side: StringName in targets:
		var target: Vector3 = targets[side]
		if _ik._ground_sampler.is_target_inside_stance_zone(side, target):
			_failures.append("%s live stale lower target was accepted inside safe zone" % side)
		_ik._ground_sampler.smoothed_target[side] = target
		_ik._ground_sampler.smoothed_normal[side] = Vector3.UP
		_ik._ground_sampler.idle_lower_latched_target[side] = target
		var retained: bool = _ik._ground_sampler._latch_idle_lower_support(
				space, side, false, _player.global_position, Vector3.UP, 1.0 / 60.0)
		if retained or _ik._ground_sampler.idle_lower_latched_target.has(side):
			_failures.append("%s live stale lower target remained latched" % side)
