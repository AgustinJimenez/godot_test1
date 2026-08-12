class_name FootIkLocomotionCases
extends RefCounted
## Declarative flat-floor cases shared by the Foot IK regression tools.

const CASES: Array[Dictionary] = [
	{
		"name": &"idle",
		"animation": &"moves/unarmed_idle",
		"sprint": false,
		"movement": Vector2.ZERO,
		"sample_frames": 120,
		"expect_same_pose": true,
	},
	{
		"name": &"crouch_idle",
		"animation": &"moves/unarmed_crouch_idle",
		"sprint": false,
		"crouched": true,
		"movement": Vector2.ZERO,
		"sample_frames": 120,
		"expect_same_pose": true,
	},
	{"name": &"walk", "animation": &"moves/unarmed_walk", "sprint": false, "check_reach": true},
	{
		"name": &"walk_back",
		"animation": &"moves/unarmed_walk",
		"sprint": false,
		"movement": Vector2(0.0, 1.0),
		"check_reach": true
	},
	{
		"name": &"walk_left",
		"animation": &"moves/unarmed_walk",
		"sprint": false,
		"movement": Vector2(-1.0, 0.0)
	},
	{
		"name": &"walk_right",
		"animation": &"moves/unarmed_walk",
		"sprint": false,
		"movement": Vector2(1.0, 0.0)
	},
	{
		"name": &"sprint",
		"animation": &"moves/unarmed_sprint",
		"sprint": true,
		"check_reach": true,
		"frame_allowance": 7.0
	},
	{
		"name": &"sprint_left",
		"animation": &"moves/unarmed_sprint",
		"sprint": true,
		"movement": Vector2(-1.0, -1.0),
		"check_reach": true,
		"frame_allowance": 7.0,
		"peak_allowance": 2.5
	},
	{
		"name": &"sprint_right",
		"animation": &"moves/unarmed_sprint",
		"sprint": true,
		"movement": Vector2(1.0, -1.0),
		"check_reach": true,
		"frame_allowance": 7.0,
		"peak_allowance": 2.5
	},
	{
		"name": &"crouch_walk",
		"animation": &"moves/unarmed_crouch_walk",
		"sprint": false,
		"crouched": true,
		"frame_allowance": 4.5,
		"check_reach": true,
	},
	{
		"name": &"crouch_back",
		"animation": &"moves/unarmed_crouch_walk",
		"sprint": false,
		"crouched": true,
		"movement": Vector2(0.0, 1.0),
		"frame_allowance": 4.5,
		"check_reach": true,
	},
	{
		"name": &"crouch_left",
		"animation": &"moves/unarmed_crouch_left",
		"sprint": false,
		"crouched": true,
		"movement": Vector2(-1.0, 0.0),
		"frame_allowance": 4.5,
	},
	{
		"name": &"crouch_strafe",
		"animation": &"moves/unarmed_crouch_right",
		"sprint": false,
		"crouched": true,
		"pre_crouched": true,
		"pre_animation": &"moves/unarmed_crouch_idle",
		"pre_frames": 90,
		"pre_movement": Vector2.ZERO,
		"movement": Vector2(1.0, 0.0),
		"settle_frames": 0,
		"frame_allowance": 4.5,
	},
	{
		"name": &"crouch_strafe_to_forward",
		"animation": &"moves/unarmed_crouch_walk",
		"sprint": false,
		"crouched": true,
		"pre_crouched": true,
		"pre_animation": &"moves/unarmed_crouch_right",
		"pre_frames": 75,
		"pre_movement": Vector2(1.0, 0.0),
		"movement": Vector2(0.0, -1.0),
		"settle_frames": 0,
		"sample_frames": 120,
		"frame_allowance": 4.5,
	},
	{
		"name": &"sprint_to_crouch_walk",
		"animation": &"moves/unarmed_crouch_walk",
		"sprint": true,
		"crouched": true,
		"pre_animation": &"moves/unarmed_sprint",
		"pre_frames": 60,
		"settle_frames": 0,
		"sample_frames": 120,
		"frame_allowance": 4.5,
	},
	{
		"name": &"crouch_walk_to_sprint",
		"animation": &"moves/unarmed_sprint",
		"sprint": true,
		"crouched": false,
		"pre_animation": &"moves/unarmed_crouch_walk",
		"pre_crouched": true,
		"pre_frames": 60,
		"settle_frames": 0,
		"sample_frames": 120,
		"frame_allowance": 7.0,
	},
	{
		"name": &"sprint_slow",
		"animation": &"moves/unarmed_sprint",
		"sprint": true,
		"time_scale": 0.05,
		"sample_frames": 720,
		"joints": [&"LeftFoot", &"LeftToeBase", &"RightFoot", &"RightToeBase"],
	},
]


static func verify_directional_clips(body: PlayerBody) -> bool:
	var failed_any := false
	var forward := body.anim_player.get_animation("moves/unarmed_crouch_walk")
	var forward_rotation := _hips_rotation(forward, 0)
	for clip_name: StringName in [&"unarmed_crouch_left", &"unarmed_crouch_right"]:
		var animation := body.anim_player.get_animation("moves/%s" % clip_name)
		var loop_delta := _horizontal_loop_delta(animation)
		var facing_delta := HumanoidRetargeter.horizontal_facing_delta(
			animation, forward, body.skeleton
		)
		var first_rotation := _hips_rotation(animation, 0)
		var last_rotation := _hips_rotation(animation, -1)
		var arm_motion := _maximum_arm_rotation_step(animation, body)
		var failed := (
			loop_delta > 0.001 or facing_delta > deg_to_rad(1.0) or float(arm_motion["angle"]) > 5.0
		)
		failed_any = failed_any or failed
		print(
			"FOOT_IK_DIRECTIONAL_IN_PLACE_CHECK ",
			"FAIL" if failed else "PASS",
			" clip=",
			clip_name,
			" horizontal_loop_delta_m=",
			snappedf(loop_delta, 0.000001),
			" hips_loop_rotation_deg=",
			snappedf(rad_to_deg(first_rotation.angle_to(last_rotation)), 0.001),
			" forward_start_rotation_delta_deg=",
			snappedf(rad_to_deg(forward_rotation.angle_to(first_rotation)), 0.001),
			" horizontal_facing_delta_deg=",
			snappedf(rad_to_deg(facing_delta), 0.001),
			" arm_rotation_step_deg=",
			snappedf(float(arm_motion["angle"]), 0.001),
			" arm_rotation_bone=",
			arm_motion["bone"],
			" arm_rotation_seam=",
			arm_motion["seam"]
		)
	return failed_any


static func _horizontal_loop_delta(animation: Animation) -> float:
	for track in animation.get_track_count():
		if animation.track_get_type(track) != Animation.TYPE_POSITION_3D:
			continue
		var count := animation.track_get_key_count(track)
		if count < 2:
			return INF
		var first := animation.track_get_key_value(track, 0) as Vector3
		var last := animation.track_get_key_value(track, count - 1) as Vector3
		return Vector2(last.x - first.x, last.z - first.z).length()
	return INF


static func _maximum_arm_rotation_step(animation: Animation, body: PlayerBody) -> Dictionary:
	var result := {"angle": 0.0, "bone": &"", "seam": false}
	var arm_bones: Array[StringName] = []
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
		arm_bones.append(body.resolve_bone_name(role))
	for track in animation.get_track_count():
		if animation.track_get_type(track) != Animation.TYPE_ROTATION_3D:
			continue
		var path := animation.track_get_path(track)
		if path.get_subname_count() == 0 or StringName(path.get_subname(0)) not in arm_bones:
			continue
		for key in animation.track_get_key_count(track):
			var count := animation.track_get_key_count(track)
			var previous := count - 1 if key == 0 else key - 1
			var a := animation.track_get_key_value(track, previous) as Quaternion
			var b := animation.track_get_key_value(track, key) as Quaternion
			var angle := rad_to_deg(a.angle_to(b))
			if angle > float(result["angle"]):
				result = {"angle": angle, "bone": path.get_subname(0), "seam": key == 0}
	return result


static func _hips_rotation(animation: Animation, key_index: int) -> Quaternion:
	var hips_path := NodePath()
	for track in animation.get_track_count():
		if animation.track_get_type(track) == Animation.TYPE_POSITION_3D:
			hips_path = animation.track_get_path(track)
			break
	for track in animation.get_track_count():
		if (
			animation.track_get_type(track) != Animation.TYPE_ROTATION_3D
			or animation.track_get_path(track) != hips_path
		):
			continue
		var count := animation.track_get_key_count(track)
		var resolved := key_index if key_index >= 0 else count - 1
		return animation.track_get_key_value(track, resolved) as Quaternion
	return Quaternion.IDENTITY
