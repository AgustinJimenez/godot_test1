extends Node3D
## A/B row for Foot IK v2 (the v1 `foot_ik_animation_comparison` idea): per animation one character
## with IK OFF (raw animation) next to one with v2 ON, standing still on a flat pad, so any
## difference between the pair is the IK's. Keys: A/D pan, W/S closer/farther, Q/E height, Shift
## faster. Headless: runs 120 frames and prints how many IK passes each ON character did.

const INSTALL := preload("res://actors/player/foot_ik_v2/foot_ik_v2_install.gd")
const SPACING := 2.2
const LABEL_HEIGHT := 2.25
const ANIMATIONS: Array[Array] = [
	["IDLE", &"unarmed_idle"], ["WALK", &"unarmed_walk"], ["RUN", &"unarmed_sprint"],
	["STRAFE LEFT", &"unarmed_walk_left"], ["STRAFE RIGHT", &"unarmed_walk_right"],
	["DIAG FWD-LEFT", &"unarmed_walk_fwd_left"], ["DIAG FWD-RIGHT", &"unarmed_walk_fwd_right"],
	["CROUCH WALK", &"unarmed_crouch_walk"],
]

var _camera := Camera3D.new()
var _frames := 0
var _modifiers: Array[FootIKV2Modifier] = []


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
	if _frames == 120 and DisplayServer.get_name() == "headless":
		for modifier: FootIKV2Modifier in _modifiers:
			print("[V2_COMPARISON] ", modifier.player_body.anim_player.current_animation,
					" passes=", modifier.debug_passes)
		get_tree().quit()


func _key(code: Key) -> float:
	return 1.0 if Input.is_key_pressed(code) else 0.0


func _build_dummy(index: int, data: Array, ik_on: bool, count: int) -> void:
	var lane_x := (index - (count - 1) * 0.5) * SPACING
	var root := Node3D.new()
	root.position = Vector3(lane_x, 0.0, 0.0)
	add_child(root)
	var body := PlayerBody.new()
	body.name = &"Body"
	root.add_child(body)
	body.play_debug_anim(data[1] as StringName, 0.0)
	var v1: PlayerFootIKModifier = body._foot_ik_modifier
	if ik_on:
		_modifiers.append(INSTALL.install(body, body.skeleton, v1))
	else:
		v1.set_debug_enabled(false)
	var label := Label3D.new()
	label.text = "%s\nIK %s" % [data[0], "ON" if ik_on else "OFF"]
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.font_size = 36
	label.outline_size = 8
	label.modulate = Color(0.4, 1.0, 0.5) if ik_on else Color(1.0, 0.6, 0.4)
	label.position = Vector3(lane_x, LABEL_HEIGHT, 0.0)
	add_child(label)
