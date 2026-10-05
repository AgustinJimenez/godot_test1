extends Node3D
## A/B row for Foot IK v2 (the v1 `foot_ik_animation_comparison` idea): per animation one character
## with IK OFF (raw animation) next to one with v2 ON on a flat pad, so any
## difference between the pair is the IK's. Keys: A/D pan, W/S closer/farther, Q/E height, Shift
## faster. A label over each ON character shows the live diff (green < 3 cm, red >= 10 cm).
## Headless: 240 frames, then per animation the IK passes and the worst ON-vs-OFF pose
## difference per bone (frames 120+, the OFF twin is a disabled v2 that publishes the raw pose).

const INSTALL := preload("res://actors/player/foot_ik_v2/foot_ik_v2_install.gd")
const SPACING := 2.2
const LABEL_HEIGHT := 2.25
const SETTLE_FRAMES := 120 # the worst-case run ignores the start-up
const DIFF_OK := 0.03 # m: green up to here, fading to red at DIFF_BAD
const DIFF_BAD := 0.10
## v1's verdict rule: a joint is "DIFF" when its rotation is off by more than ROT_BAD degrees, or
## by more than ROT_WARN together with POS_WARN metres of position.
const ROT_BAD := 12.0
const ROT_WARN := 8.0
const POS_WARN := 0.05
const JOINT_ROLES: Array[String] = ["hip", "knee", "foot", "toe"]
## [label, animation, fake walking speed m/s]: v2 treats a still character as idle (it squats to
## put a swinging foot on the floor), so each host reports the speed its animation is meant for.
const ANIMATIONS: Array[Array] = [
	["IDLE", &"unarmed_idle", 0.0], ["WALK", &"unarmed_walk", 1.6], ["RUN", &"unarmed_sprint", 5.0],
	["STRAFE LEFT", &"unarmed_walk_left", 1.4], ["STRAFE RIGHT", &"unarmed_walk_right", 1.4],
	["DIAG FWD-LEFT", &"unarmed_walk_fwd_left", 1.6],
	["DIAG FWD-RIGHT", &"unarmed_walk_fwd_right", 1.6],
	["CROUCH WALK", &"unarmed_crouch_walk", 1.0],
]

## Set before the node enters the tree: part of the lab, so no stage, camera or keys of its own.
var embedded := false
var _camera := Camera3D.new()
var _frames := 0
var _modifiers: Array[FootIKV2Modifier] = []
var _off_mods: Array[FootIKV2Modifier] = [] # disabled v2 twin: publishes the raw animation
var _worst: Array[float] = []
var _worst_bone: Array[String] = []
var _by_bone: Array[Dictionary] = [] # per animation: bone name -> worst diff
var _foot: Array[Dictionary] = [] # per animation: foot tilt and ankle / ball height ON vs OFF
var _pending_off: FootIKV2Modifier
var _diff_labels: Array[Label3D] = []
var _markers: Array[Dictionary] = [] # per animation: "left_knee" -> red sphere on a DIFF joint
var _hosts: Array[CharacterBody3D] = []
var _speeds: Array[float] = []


func _ready() -> void:
	PlayerTempWalk.use_in_headless = "--temp-walk" in OS.get_cmdline_user_args()
	var count := ANIMATIONS.size() * 2
	if embedded:
		_camera.free() # never added to the tree: would leak at exit
	if not embedded:
		_build_stage(count)
	for index in count:
		_build_dummy(index, ANIMATIONS[index / 2] as Array, index % 2 == 1, count)
	if not embedded:
		_camera.position = Vector3(0.0, 1.5, 6.0)
		add_child(_camera)
		_camera.current = true


## Own environment, light and pad, for the stand-alone scene (the lab brings its own).
func _build_stage(count: int) -> void:
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.08, 0.09, 0.11)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.6, 0.62, 0.68)
	add_child(env)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-50.0, 30.0, 0.0)
	add_child(light)
	var pad := CSGBox3D.new()
	pad.size = Vector3(count * SPACING + 4.0, 0.1, 8.0)
	pad.position = Vector3(0.0, -0.05, 0.0)
	pad.use_collision = true
	add_child(pad)


func _process(delta: float) -> void:
	if embedded:
		return
	var speed := (12.0 if Input.is_key_pressed(KEY_SHIFT) else 4.0) * delta
	_camera.position.x += (Input.get_axis(&"ui_left", &"ui_right") + _key(KEY_D) - _key(KEY_A)) * speed
	_camera.position.z += (_key(KEY_S) - _key(KEY_W)) * speed
	_camera.position.y += (_key(KEY_E) - _key(KEY_Q)) * speed


func _physics_process(_delta: float) -> void:
	_frames += 1
	for index in _hosts.size(): # floor contact first, then the speed the skeleton update will read
		_hosts[index].velocity = Vector3.DOWN
		_hosts[index].move_and_slide()
		_hosts[index].velocity = Vector3(0.0, 0.0, -_speeds[index])
	if _frames > 10:
		_measure()
	if _frames == 240 and not embedded and DisplayServer.get_name() == "headless":
		for index in _modifiers.size():
			var modifier := _modifiers[index]
			print("[V2_COMPARISON] ", modifier.player_body.anim_player.current_animation,
					" passes=", modifier.debug_passes, " max_diff_m=%.6f" % _worst[index],
					" bone=", _worst_bone[index], " ", _foot_summary(index), " ", _by_bone[index])
		get_tree().quit()


func _foot_summary(index: int) -> String:
	var stats := _foot[index]
	return "foot_deg_mean=%.2f foot_deg_max=%.2f ankle_dy_m=%.4f ball_dy_m=%.4f" % [
			float(stats["deg_sum"]) / maxf(float(stats["n"]), 1.0), stats["deg_max"],
			stats["ankle_dy"], stats["ball_dy"]]


## The IK-off vs IK-on published pose distance (leg and body bones, relative to each character's own
## origin): shown live over each ON character; the worst per animation is kept for headless runs.
func _measure() -> void:
	for index in _modifiers.size():
		var on := _modifiers[index]
		var off := _off_mods[index]
		if on.final_frame != off.final_frame:
			continue
		var on_root := on.get_skeleton().global_position
		var off_root := off.get_skeleton().global_position
		var now := 0.0
		var now_bone := ""
		for bone: int in on.final_pose:
			var diff := ((on.final_pose[bone] as Transform3D).origin - on_root
					- ((off.final_pose[bone] as Transform3D).origin - off_root)).length()
			var bone_name := on.get_skeleton().get_bone_name(bone)
			if diff > now:
				now = diff
				now_bone = bone_name
			if _frames > SETTLE_FRAMES:
				_by_bone[index][bone_name] = maxf(float(_by_bone[index].get(bone_name, 0.0)), diff)
		_measure_feet(index, on, off, on_root.y - off_root.y)
		if _frames > SETTLE_FRAMES and now > _worst[index]:
			_worst[index] = now
			_worst_bone[index] = now_bone
		var errors := _joint_errors(index, on, off, on_root, off_root)
		var stats := _foot[index]
		var label := _diff_labels[index]
		label.text = "%s\nworst %.1f cm (%s)\nfoot turn %.1f deg (mean %.1f)  ankle %+.1f cm" % [
				"SYNCED" if errors.is_empty() else "DIFF: " + ", ".join(errors.slice(0, 2)),
				now * 100.0, now_bone, stats["deg_now"],
				float(stats["deg_sum"]) / maxf(float(stats["n"]), 1.0), float(stats["ankle_now"]) * 100.0]
		label.modulate = Color(0.4, 1.0, 0.4) if errors.is_empty() else Color(1.0, 0.35, 0.35)
		if _frames > SETTLE_FRAMES and not errors.is_empty() and _frames % 60 == 0:
			print("[V2_DIFF] ", on.player_body.anim_player.current_animation, " ", ", ".join(errors))


## What the leg bones' positions cannot show: how far each foot is turned from the animation (a
## tilted sole lifts the heel or toe off the floor) and how far the ankle / ball are raised or sunk.
## Heights are relative to each character's own origin. The live values are shown over every pair;
## the worst (after the start-up) is kept per animation for the headless run.
func _measure_feet(index: int, on: FootIKV2Modifier, off: FootIKV2Modifier, root_dy: float) -> void:
	var stats := _foot[index]
	var skeleton := on.get_skeleton()
	var settled := _frames > SETTLE_FRAMES
	var worst_deg := 0.0
	var ankle_now := 0.0
	for side in ["l", "r"]:
		var foot := skeleton.find_bone("foot_" + side)
		var ball := skeleton.find_bone("ball_" + side)
		if foot < 0 or ball < 0 or not on.final_pose.has(foot) or not on.final_pose.has(ball):
			continue
		var on_foot := on.final_pose[foot] as Transform3D
		var off_foot := off.final_pose[foot] as Transform3D
		worst_deg = maxf(worst_deg, rad_to_deg(
				on_foot.basis.get_rotation_quaternion().angle_to(off_foot.basis.get_rotation_quaternion())))
		var ankle_dy := on_foot.origin.y - off_foot.origin.y - root_dy
		var ball_dy := (on.final_pose[ball] as Transform3D).origin.y \
				- (off.final_pose[ball] as Transform3D).origin.y - root_dy
		if absf(ankle_dy) > absf(ankle_now):
			ankle_now = ankle_dy
		if settled:
			stats["ankle_dy"] = maxf(float(stats["ankle_dy"]), absf(ankle_dy))
			stats["ball_dy"] = maxf(float(stats["ball_dy"]), absf(ball_dy))
	stats["deg_now"] = worst_deg
	stats["ankle_now"] = ankle_now
	if settled:
		stats["deg_sum"] = float(stats["deg_sum"]) + worst_deg
		stats["deg_max"] = maxf(float(stats["deg_max"]), worst_deg)
		stats["n"] = int(stats["n"]) + 1


## v1's per-joint verdict over the hip, knee, foot and toe of both legs: the joints whose rotation
## or position is off the animation's, as "Left Knee (9.1 deg)", worst first. A red sphere marks
## each one on the IK character. Positions are relative to each character's own origin.
func _joint_errors(index: int, on: FootIKV2Modifier, off: FootIKV2Modifier, on_root: Vector3,
		off_root: Vector3) -> Array[String]:
	var found: Array[Array] = []
	for side: StringName in on._legs:
		for role: String in JOINT_ROLES:
			var bone := int((on._legs[side] as Dictionary)[role])
			var marker := _markers[index].get("%s_%s" % [side, role]) as MeshInstance3D
			var bad := false
			if on.final_pose.has(bone) and off.final_pose.has(bone):
				var on_pose := on.final_pose[bone] as Transform3D
				var off_pose := off.final_pose[bone] as Transform3D
				var deg := rad_to_deg(on_pose.basis.orthonormalized().get_rotation_quaternion()
						.angle_to(off_pose.basis.orthonormalized().get_rotation_quaternion()))
				var apart := ((on_pose.origin - on_root) - (off_pose.origin - off_root)).length()
				bad = deg > ROT_BAD or (deg > ROT_WARN and apart > POS_WARN)
				if bad:
					found.append([deg, "%s %s (%.1f deg)" % [
							String(side).capitalize(), role.capitalize(), deg]])
					marker.global_position = on_pose.origin
			marker.visible = bad
	found.sort_custom(func(a: Array, b: Array) -> bool: return float(a[0]) > float(b[0]))
	var errors: Array[String] = []
	for entry in found:
		errors.append(str(entry[1]))
	return errors


func _key(code: Key) -> float:
	return 1.0 if Input.is_key_pressed(code) else 0.0


func _build_dummy(index: int, data: Array, ik_on: bool, count: int) -> void:
	var lane_x := (index - (count - 1) * 0.5) * SPACING
	var root := CharacterBody3D.new()
	root.collision_layer = 0 # the player walks through the dummies, they only need the floor
	root.position = Vector3(lane_x, 0.0, 0.0)
	var capsule := CollisionShape3D.new()
	capsule.shape = CapsuleShape3D.new()
	(capsule.shape as CapsuleShape3D).radius = 0.35 # the player scene's capsule
	(capsule.shape as CapsuleShape3D).height = 1.8
	capsule.position.y = 0.9
	root.add_child(capsule)
	add_child(root)
	_hosts.append(root)
	_speeds.append(float(data[2]))
	var body := PlayerBody.new()
	body.name = &"Body"
	root.add_child(body)
	body.play_debug_anim(data[1] as StringName, 0.0)
	var v1: PlayerFootIKModifier = body._foot_ik_modifier
	if ik_on:
		_modifiers.append(INSTALL.install(body, body.skeleton, v1))
		_off_mods.append(_pending_off)
		_worst.append(0.0)
		_worst_bone.append("")
		_by_bone.append({})
		_markers.append(_build_markers())
		_foot.append({"deg_sum": 0.0, "deg_max": 0.0, "n": 0, "ankle_dy": 0.0, "ball_dy": 0.0,
			"deg_now": 0.0, "ankle_now": 0.0})
	else:
		v1.set_debug_enabled(false)
		_pending_off = INSTALL.install(body, body.skeleton, v1)
		_pending_off.enabled = false
	var label := Label3D.new()
	label.text = "%s\nIK %s" % [data[0], "ON" if ik_on else "OFF"]
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.font_size = 36
	label.outline_size = 8
	label.modulate = Color(0.4, 1.0, 0.5) if ik_on else Color(1.0, 0.6, 0.4)
	label.position = Vector3(lane_x, LABEL_HEIGHT, 0.0)
	add_child(label)
	if ik_on:
		var diff := Label3D.new()
		diff.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		diff.font_size = 30
		diff.outline_size = 8
		diff.position = Vector3(lane_x, LABEL_HEIGHT - 0.4, 0.0)
		add_child(diff)
		_diff_labels.append(diff)


## One red sphere per leg joint (hidden until that joint is a DIFF), keyed "left_knee" and so on.
func _build_markers() -> Dictionary:
	var markers := {}
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(1.0, 0.1, 0.1)
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	for side in ["left", "right"]:
		for role in JOINT_ROLES:
			var marker := MeshInstance3D.new()
			var sphere := SphereMesh.new()
			sphere.radius = 0.04
			sphere.height = 0.08
			sphere.material = material
			marker.mesh = sphere
			marker.visible = false
			add_child(marker)
			markers["%s_%s" % [side, role]] = marker
	return markers
