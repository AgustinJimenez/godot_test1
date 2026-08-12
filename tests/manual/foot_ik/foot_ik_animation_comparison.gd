extends Node3D
## Compact A/B reference group for seeing what Foot IK changes during locomotion.
## All six bodies remain stationary so animation and IK pose differences can be
## inspected without chasing a moving reference or observing harness-reset artifacts.

const PLAYER_BODY := preload("res://actors/player/player_body.gd")
const PLAYER_SCENE := preload("res://actors/player/player.tscn")
const TRACE_WRITER := preload("res://tests/manual/foot_ik/foot_ik_trace_writer.gd")
const GROUP_CENTER := Vector3(8.75, 0.0, -7.0)
const DUMMY_SPACING := 2.5
const PAD_SIZE := Vector3(16.5, 0.1, 12.0)
const LABEL_HEIGHT := 2.25
const CROUCH_ROW_Z := -10.5
const CROUCH_TRAVEL := 1.5
const CROUCH_TRACE_FILE := "user://foot_ik_crouch_strafe_comparison.jsonl"
const CASES: Array[Dictionary] = [
	{"label": "WALK IN PLACE\nIK OFF", "animation": &"unarmed_walk", "ik": false},
	{"label": "WALK IN PLACE\nIK ON", "animation": &"unarmed_walk", "ik": true},
	{"label": "RUN IN PLACE\nIK OFF", "animation": &"unarmed_sprint", "ik": false},
	{"label": "RUN IN PLACE\nIK ON", "animation": &"unarmed_sprint", "ik": true},
	{
		"label": "CROUCH WALK FORWARD\nIK OFF",
		"animation": &"unarmed_crouch_walk",
		"ik": false,
	},
	{
		"label": "CROUCH WALK FORWARD\nIK ON",
		"animation": &"unarmed_crouch_walk",
		"ik": true,
	},
]

var _crouch_dummies: Array[Dictionary] = []
var _crouch_direction := 1.0
var _sample_scheduled := false
var _trace_writer := TRACE_WRITER.new(CROUCH_TRACE_FILE, 1200)


func _ready() -> void:
	_build_comparison_pad()
	for index in CASES.size():
		_build_dummy(index, CASES[index])
	_build_crouch_dummy(0, false)
	_build_crouch_dummy(1, true)


func _physics_process(_delta: float) -> void:
	if _crouch_dummies.is_empty():
		return
	var leader := _crouch_dummies[0]["player"] as Player
	var origin_x := float(_crouch_dummies[0]["origin_x"])
	if absf(leader.global_position.x - origin_x) >= CROUCH_TRAVEL:
		_crouch_direction = -signf(leader.global_position.x - origin_x)
	for dummy: Dictionary in _crouch_dummies:
		(dummy["player"] as Player).movement_input_override = Vector2(_crouch_direction, 0.0)
	if not _sample_scheduled:
		_sample_scheduled = true
		call_deferred(&"_capture_crouch_comparison")


func _build_comparison_pad() -> void:
	var pad := CSGBox3D.new()
	pad.name = &"ComparisonPad"
	pad.size = PAD_SIZE
	pad.position = GROUP_CENTER + Vector3(0.0, -PAD_SIZE.y * 0.5, 0.0)
	pad.use_collision = true
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.19, 0.23, 0.2)
	material.roughness = 0.9
	pad.material = material
	add_child(pad)


func _build_dummy(index: int, data: Dictionary) -> void:
	var lane_x := GROUP_CENTER.x + (index - (CASES.size() - 1) * 0.5) * DUMMY_SPACING
	var motion_root := Node3D.new()
	motion_root.name = StringName("ComparisonDummy%d" % index)
	motion_root.position = Vector3(lane_x, 0.0, GROUP_CENTER.z)
	add_child(motion_root)

	var body := PLAYER_BODY.new() as PlayerBody
	body.name = &"Body"
	motion_root.add_child(body)
	body.play_debug_anim(data["animation"] as StringName, 0.0)
	_set_ik_active(body, data["ik"])
	_build_label(str(data["label"]), Vector3(lane_x, LABEL_HEIGHT, GROUP_CENTER.z))


func _build_crouch_dummy(index: int, ik_enabled: bool) -> void:
	var lane_x := GROUP_CENTER.x + (index - 0.5) * DUMMY_SPACING
	var player := PLAYER_SCENE.instantiate() as Player
	player.name = StringName("CrouchStrafe%s" % ("IkOn" if ik_enabled else "IkOff"))
	player.position = Vector3(lane_x, 0.05, CROUCH_ROW_Z)
	player.movement_input_override = Vector2(1.0, 0.0)
	player.gameplay_action_input_enabled = false
	player._crouched = true
	add_child(player)
	for camera: Node in player.find_children("*", "Camera3D", true, false):
		(camera as Camera3D).current = false
	player.hud.visible = false
	player.hud.set_process_unhandled_input(false)
	player.set_process_unhandled_input(false)
	var modifier := _find_ik(player.body)
	modifier.set_debug_enabled(ik_enabled)
	(
		_crouch_dummies
		. append(
			{
				"player": player,
				"modifier": modifier,
				"origin_x": lane_x,
				"ik": ik_enabled,
			}
		)
	)
	_build_label(
		"CROUCH STRAFE\nIK %s" % ("ON" if ik_enabled else "OFF"),
		Vector3(lane_x, LABEL_HEIGHT, CROUCH_ROW_Z)
	)


func _set_ik_active(body: PlayerBody, enabled: bool) -> void:
	_find_ik(body).set_debug_enabled(enabled)


func _find_ik(body: PlayerBody) -> PlayerFootIKModifier:
	for child in body.skeleton.get_children():
		if child is PlayerFootIKModifier:
			return child
	return null


func _capture_crouch_comparison() -> void:
	_sample_scheduled = false
	if _crouch_dummies.size() != 2:
		return
	var authored := _crouch_dummies[0]
	var corrected := _crouch_dummies[1]
	var authored_player := authored["player"] as Player
	var corrected_player := corrected["player"] as Player
	var corrected_ik := corrected["modifier"] as PlayerFootIKModifier
	var trace := {
		"frame": Engine.get_physics_frames(),
		"direction": _crouch_direction,
		"authored_root": authored_player.global_position,
		"ik_root": corrected_player.global_position,
		"animation": corrected_player.body.anim_player.current_animation,
		"time": corrected_player.body.anim_player.current_animation_position,
		"feet": {},
		"arms":
		{
			"authored": _arm_rotations(authored_player.body),
			"ik": _arm_rotations(corrected_player.body),
		},
	}
	for side: StringName in [&"left", &"right"]:
		var authored_ik := authored["modifier"] as PlayerFootIKModifier
		var authored_indices := authored_ik._bone_indices[side] as Dictionary
		var corrected_indices := corrected_ik._bone_indices[side] as Dictionary
		var authored_poses := _leg_poses(authored_player, authored_ik, authored_indices, false)
		var corrected_poses := _leg_poses(corrected_player, corrected_ik, corrected_indices, true)
		var axis := (
			(
				(authored_poses["knee"] as Transform3D).origin
				- (authored_poses["hip"] as Transform3D).origin
			)
			. normalized()
		)
		var authored_rotation := (
			(authored_poses["hip"] as Transform3D).basis.get_rotation_quaternion().normalized()
		)
		var corrected_rotation := (
			(corrected_poses["hip"] as Transform3D).basis.get_rotation_quaternion().normalized()
		)
		var delta := corrected_rotation * authored_rotation.inverse()
		trace["feet"][side] = {
			"procedural_hip_twist_deg": _twist_degrees(delta, axis),
			"authored": _leg_geometry(authored_poses, authored_ik._leg_lengths[side]),
			"ik": _leg_geometry(corrected_poses, corrected_ik._leg_lengths[side]),
			"stance": corrected_ik._gait_tracker.is_locomotion_stance_active(side),
			"locked": corrected_ik._gait_tracker.is_locomotion_target_locked(side),
		}
	_trace_writer.capture(JSON.stringify(trace))


func _arm_rotations(body: PlayerBody) -> Dictionary:
	var result := {}
	for role: StringName in [
		&"LeftShoulder",
		&"LeftArm",
		&"LeftForeArm",
		&"LeftHand",
		&"RightShoulder",
		&"RightArm",
		&"RightForeArm",
		&"RightHand"
	]:
		var index := body.skeleton.find_bone(body.resolve_bone_name(role))
		if index < 0:
			continue
		var rotation := (
			body.skeleton.get_bone_global_pose(index).basis.get_rotation_quaternion().normalized()
		)
		result[role] = [rotation.x, rotation.y, rotation.z, rotation.w]
	return result


func _leg_poses(
	player: Player, modifier: PlayerFootIKModifier, indices: Dictionary, use_final: bool
) -> Dictionary:
	var result := {}
	for joint: StringName in [&"hip", &"knee", &"foot"]:
		var index: int = indices[joint]
		result[joint] = (
			modifier._final_bone_poses[index] as Transform3D
			if use_final and not modifier._pose_suppressed and modifier._final_bone_poses.has(index)
			else player.skeleton.get_bone_global_pose(index)
		)
	return result


func _leg_geometry(poses: Dictionary, references: Dictionary) -> Dictionary:
	var hip := poses["hip"] as Transform3D
	var knee := poses["knee"] as Transform3D
	var foot := poses["foot"] as Transform3D
	var upper := hip.origin.distance_to(knee.origin)
	var lower := knee.origin.distance_to(foot.origin)
	return {
		"upper": upper,
		"upper_reference": float(references["upper"]),
		"lower": lower,
		"lower_reference": float(references["lower"]),
		"hip_scale": hip.basis.get_scale(),
		"knee_scale": knee.basis.get_scale(),
		"foot_scale": foot.basis.get_scale(),
		"thigh_swing_deg": rad_to_deg((knee.origin - hip.origin).angle_to(Vector3.DOWN)),
	}


func _twist_degrees(rotation: Quaternion, axis: Vector3) -> float:
	var vector := Vector3(rotation.x, rotation.y, rotation.z)
	var projected := axis * vector.dot(axis)
	var twist := Quaternion(projected.x, projected.y, projected.z, rotation.w).normalized()
	return rad_to_deg(2.0 * acos(clampf(absf(twist.w), 0.0, 1.0)))


func _build_label(text: String, world_position: Vector3) -> void:
	var label := Label3D.new()
	label.text = text
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.font_size = 36
	label.outline_size = 8
	label.modulate = Color.WHITE
	label.outline_modulate = Color.BLACK
	label.position = world_position
	add_child(label)
