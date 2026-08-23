extends Node3D

const PREVIEW_SCENE := preload("res://tests/manual/foot_ik/foot_ik_preview.tscn")

var _preview: Node3D
var _player: Player
var _modifier: PlayerFootIKModifier
var _skel: Skeleton3D
var _current_case_idx := 0

var _test_cases := [
	{
		"name": "forward_020_stairs",
		"stair_height": 0.20,
		"offset": Vector3(0.0, 0.0, 0.0),
		"dir": Vector3(0.0, 0.0, 1.0),
		"frames": 50,
	},
	{
		"name": "diagonal_020_stairs",
		"stair_height": 0.20,
		"offset": Vector3(-0.5, 0.0, 0.0),
		"dir": Vector3(0.3, 0.0, 0.95).normalized(),
		"frames": 50,
	},
	{
		"name": "lateral_right_020_stairs",
		"stair_height": 0.20,
		"offset": Vector3(-0.8, 0.4, 1.5),
		"dir": Vector3(1.0, 0.0, 0.0),
		"frames": 40,
	},
	{
		"name": "lateral_left_020_stairs",
		"stair_height": 0.20,
		"offset": Vector3(0.8, 0.4, 1.5),
		"dir": Vector3(-1.0, 0.0, 0.0),
		"frames": 40,
	},
	{
		"name": "lateral_right_flat",
		"stair_height": 0.20,
		"offset": Vector3(-1.0, 0.0, -1.0),
		"dir": Vector3(1.0, 0.0, 0.0),
		"frames": 40,
	},
	{
		"name": "lateral_left_flat",
		"stair_height": 0.20,
		"offset": Vector3(1.0, 0.0, -1.0),
		"dir": Vector3(-1.0, 0.0, 0.0),
		"frames": 40,
	},
	{
		"name": "forward_035_stairs",
		"stair_height": 0.35,
		"offset": Vector3(0.0, 0.0, 0.0),
		"dir": Vector3(0.0, 0.0, 1.0),
		"frames": 50,
	},
	{
		"name": "diagonal_035_stairs",
		"stair_height": 0.35,
		"offset": Vector3(-0.4, 0.0, 0.0),
		"dir": Vector3(0.25, 0.0, 0.96).normalized(),
		"frames": 50,
	},
]

var _case_frame := 0
var _worst_toe_clip := 0.0
var _worst_foot_float := 0.0
var _planted_frames: Dictionary = {&"left": 0, &"right": 0}
var _swing_frames: Dictionary = {&"left": 0, &"right": 0}
var _prev_foot_pos: Dictionary = {}
var _foot_travel: Dictionary = {&"left": 0.0, &"right": 0.0}


func _find_skel(player: Player) -> Skeleton3D:
	if player != null and player.body != null and player.body.character != null:
		return player.body.character.find_child("Skeleton3D", true, false) as Skeleton3D
	if player != null and player.skeleton != null:
		return player.skeleton
	return null


func _find_foot_ik(player: Player) -> PlayerFootIKModifier:
	var skel := _find_skel(player)
	if skel != null:
		for child in skel.get_children():
			if child is PlayerFootIKModifier:
				return child
	return null


func _ready() -> void:
	_preview = PREVIEW_SCENE.instantiate()
	add_child(_preview)
	_player = _preview.get_node(^"Player") as Player
	_skel = _find_skel(_player)
	_modifier = _find_foot_ik(_player)
	FootIKStairSurfaces.configure_player(_player)
	_start_case(0)


func _start_case(idx: int) -> void:
	if idx >= _test_cases.size():
		print("\n=== ALL DIAGONAL & LATERAL STAIR TESTS COMPLETED SUCCESSFULLY ===")
		get_tree().quit(0)
		return
	_current_case_idx = idx
	_case_frame = 0
	_worst_toe_clip = 0.0
	_worst_foot_float = 0.0
	_planted_frames = {&"left": 0, &"right": 0}
	_swing_frames = {&"left": 0, &"right": 0}
	_prev_foot_pos.clear()
	_foot_travel = {&"left": 0.0, &"right": 0.0}
	if _modifier == null:
		_modifier = _find_foot_ik(_player)
	var tc: Dictionary = _test_cases[idx]

	# Find matching stair walker origin in preview
	var start_base := Vector3.ZERO
	for walker: Dictionary in _preview._stair_walkers:
		if is_equal_approx(float(walker["stair_height"]), float(tc["stair_height"])):
			start_base = walker["start_position"]
			_player = walker["player"] as Player
			_skel = _player.skeleton
			_modifier = _find_foot_ik(_player)
			break

	var dir: Vector3 = tc["dir"]
	_player.set_physics_process(true)
	_player.global_position = start_base + (tc["offset"] as Vector3)
	_player.velocity = dir * 3.2
	_player.movement_input_override = Vector2(dir.x, dir.z)
	_player.step_height = float(tc["stair_height"]) + 0.05
	if _modifier != null:
		_modifier.ray_up = float(tc["stair_height"]) + 0.3
		_modifier.ray_down = float(tc["stair_height"]) + 0.4
		_modifier.reset_runtime_state()


func _physics_process(_delta: float) -> void:
	if _current_case_idx >= _test_cases.size():
		return

	var tc: Dictionary = _test_cases[_current_case_idx]
	_case_frame += 1
	_player.velocity = (tc["dir"] as Vector3) * 3.2
	_player.move_and_slide()

	_audit_frame(tc["name"])

	if _case_frame >= int(tc["frames"]):
		print("CASE %s: clip=%.3fm float=%.3fm L(p=%d,s=%d,t=%.2fm) R(p=%d,s=%d,t=%.2fm)" % [
			tc["name"], _worst_toe_clip, _worst_foot_float,
			_planted_frames[&"left"], _swing_frames[&"left"], _foot_travel[&"left"],
			_planted_frames[&"right"], _swing_frames[&"right"], _foot_travel[&"right"],
		])
		if _foot_travel[&"left"] < 0.5 or _foot_travel[&"right"] < 0.5:
			push_error("FAIL: One or both legs failed to travel during case %s" % tc["name"])
			get_tree().quit(1)
			return
		_start_case(_current_case_idx + 1)


func _audit_frame(_case_name: String) -> void:
	if _modifier == null or _skel == null or _modifier._bone_indices.is_empty():
		return
	var space := _skel.get_world_3d().direct_space_state
	var to_world := _skel.global_transform

	for side: StringName in [&"left", &"right"]:
		var toe_idx: int = _modifier._bone_indices[side]["toe"]
		var foot_idx: int = _modifier._bone_indices[side]["foot"]
		var toe_pos: Vector3 = to_world * _modifier._final_bone_poses[toe_idx].origin
		var foot_pos: Vector3 = to_world * _modifier._final_bone_poses[foot_idx].origin
		var gw: float = _modifier._smoothed_ground_weight.get(side, 0.0)

		if _prev_foot_pos.has(side):
			var prev: Vector3 = _prev_foot_pos[side]
			_foot_travel[side] += foot_pos.distance_to(prev)
		_prev_foot_pos[side] = foot_pos

		if gw >= 0.8:
			_planted_frames[side] += 1
		else:
			_swing_frames[side] += 1

		var ground_hit: Vector3 = _ray(space, foot_pos + Vector3.UP * 0.5, Vector3.DOWN * 2.0)
		var toe_hit: Vector3 = _ray(space, toe_pos + Vector3.UP * 0.5, Vector3.DOWN * 2.0)

		if gw >= 0.8:
			if toe_hit != Vector3.ZERO:
				var toe_clip: float = toe_hit.y - toe_pos.y
				if toe_clip > _worst_toe_clip:
					_worst_toe_clip = toe_clip
			if ground_hit != Vector3.ZERO:
				var sole_y: float = foot_pos.y - _modifier.ankle_offset
				var float_gap: float = sole_y - ground_hit.y
				if float_gap > _worst_foot_float:
					_worst_foot_float = float_gap


func _ray(space: PhysicsDirectSpaceState3D, from: Vector3, motion: Vector3) -> Vector3:
	var query := PhysicsRayQueryParameters3D.create(from, from + motion)
	query.collision_mask = FootIKStairSurfaces.CONTACT_COLLISION_LAYER
	var result := space.intersect_ray(query)
	if result.is_empty():
		return Vector3.ZERO
	return result["position"]
