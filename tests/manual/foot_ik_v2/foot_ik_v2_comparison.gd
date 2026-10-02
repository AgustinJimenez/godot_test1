extends Node3D
## A/B row for Foot IK v2 (the v1 `foot_ik_animation_comparison` idea): per animation one character
## with IK OFF (raw animation) next to one with v2 ON on a flat pad, so any
## difference between the pair is the IK's. Keys: A/D pan, W/S closer/farther, Q/E height, Shift
## faster. Headless: 240 frames, then per animation the IK passes and the worst ON-vs-OFF pose
## difference per bone (frames 120+, the OFF twin is a disabled v2 that publishes the raw pose).

const INSTALL := preload("res://actors/player/foot_ik_v2/foot_ik_v2_install.gd")
const SPACING := 2.2
const LABEL_HEIGHT := 2.25
## [label, animation, fake walking speed m/s]: v2 treats a still character as idle (it squats to
## put a swinging foot on the floor), so each host reports the speed its animation is meant for.
const ANIMATIONS: Array[Array] = [
	["IDLE", &"unarmed_idle", 0.0], ["WALK", &"unarmed_walk", 1.6], ["RUN", &"unarmed_sprint", 5.0],
	["STRAFE LEFT", &"unarmed_walk_left", 1.4], ["STRAFE RIGHT", &"unarmed_walk_right", 1.4],
	["DIAG FWD-LEFT", &"unarmed_walk_fwd_left", 1.6],
	["DIAG FWD-RIGHT", &"unarmed_walk_fwd_right", 1.6],
	["CROUCH WALK", &"unarmed_crouch_walk", 1.0],
]

var _camera := Camera3D.new()
var _frames := 0
var _modifiers: Array[FootIKV2Modifier] = []
var _off_mods: Array[FootIKV2Modifier] = [] # disabled v2 twin: publishes the raw animation
var _worst: Array[float] = []
var _worst_bone: Array[String] = []
var _by_bone: Array[Dictionary] = [] # per animation: bone name -> worst diff
var _pending_off: FootIKV2Modifier
var _hosts: Array[CharacterBody3D] = []
var _speeds: Array[float] = []


func _ready() -> void:
	var count := ANIMATIONS.size() * 2
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
	for index in count:
		_build_dummy(index, ANIMATIONS[index / 2] as Array, index % 2 == 1, count)
	_camera.position = Vector3(0.0, 1.5, 6.0)
	add_child(_camera)
	_camera.current = true


func _process(delta: float) -> void:
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
	if _frames > 120:
		_measure()
	if _frames == 240 and DisplayServer.get_name() == "headless":
		for index in _modifiers.size():
			var modifier := _modifiers[index]
			print("[V2_COMPARISON] ", modifier.player_body.anim_player.current_animation,
					" passes=", modifier.debug_passes, " max_diff_m=%.6f" % _worst[index],
					" bone=", _worst_bone[index], " ", _by_bone[index])
		get_tree().quit()


## Largest distance between the IK-off and IK-on published pose (leg and body bones, relative to
## each character's own origin), per animation.
func _measure() -> void:
	for index in _modifiers.size():
		var on := _modifiers[index]
		var off := _off_mods[index]
		if on.final_frame != off.final_frame:
			continue
		var on_root := on.get_skeleton().global_position
		var off_root := off.get_skeleton().global_position
		for bone: int in on.final_pose:
			var diff := ((on.final_pose[bone] as Transform3D).origin - on_root
					- ((off.final_pose[bone] as Transform3D).origin - off_root)).length()
			if diff > _worst[index]:
				_worst[index] = diff
				_worst_bone[index] = on.get_skeleton().get_bone_name(bone)
			var bone_name := on.get_skeleton().get_bone_name(bone)
			_by_bone[index][bone_name] = maxf(float(_by_bone[index].get(bone_name, 0.0)), diff)


func _key(code: Key) -> float:
	return 1.0 if Input.is_key_pressed(code) else 0.0


func _build_dummy(index: int, data: Array, ik_on: bool, count: int) -> void:
	var lane_x := (index - (count - 1) * 0.5) * SPACING
	var root := CharacterBody3D.new()
	root.position = Vector3(lane_x, 0.0, 0.0)
	var capsule := CollisionShape3D.new()
	capsule.shape = CapsuleShape3D.new()
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
