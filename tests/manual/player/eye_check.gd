extends Node3D
## The first-person camera rides the head: a player on a floor walks while the look sweeps up, down
## and round, and every frame the camera's pivot is compared with the head bone as the skeleton
## really draws it (a BoneAttachment3D, the way the hair is attached). Run:
##   godot --path . res://tests/manual/player/eye_check.tscn [-- --shots=DIR]
## Prints EYE_CHECK PASS/FAIL, the biggest gap to the bone's frame (m) and the nearest and the
## farthest the eye gets from the head bone's origin (the head mesh is about 0.1 m round it).

const FRAMES := 600
const PLAYER := preload("res://actors/player/player.tscn")

var _player: Player
var _attach: BoneAttachment3D
var _frame := 0
var _worst_gap := 0.0
var _nearest := INF
var _farthest := 0.0
var _shots := ""


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--shots="):
			_shots = arg.trim_prefix("--shots=")
	var floor_body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(400.0, 1.0, 400.0)
	shape.shape = box
	floor_body.add_child(shape)
	floor_body.position = Vector3(0.0, -0.5, 0.0)
	add_child(floor_body)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50.0, 30.0, 0.0)
	add_child(sun)
	_player = PLAYER.instantiate()
	add_child(_player)
	_player.position = Vector3(0.0, 0.1, 0.0)


func _process(_delta: float) -> void:
	_frame += 1
	if _frame == 5:
		_attach = BoneAttachment3D.new()
		_attach.bone_name = _player.skeleton.get_bone_name(_player._head_bone_idx)
		_player.skeleton.add_child(_attach)
	if _frame < 30:
		return
	if _frame == 40:
		Input.action_press(&"move_forward")
	var t := float(_frame) * 0.02
	_player._look_pitch = sin(t * 1.3) * deg_to_rad(80.0)
	_player._look_yaw = sin(t * 0.9) * deg_to_rad(55.0)
	if _frame % 5 == 0 and _frame >= 60:
		_measure()
	if _shots != "" and _frame in [100, 160, 220, 300, 380]:
		get_viewport().get_texture().get_image().save_png("%s/eye_%d.png" % [_shots, _frame])
	if _frame >= FRAMES:
		var verdict := "PASS" if _worst_gap < 0.003 and _nearest > 0.12 else "FAIL"
		print("EYE_CHECK %s worst_gap=%.4f m, eye from the head bone: %.3f .. %.3f m" % [
				verdict, _worst_gap, _nearest, _farthest])
		get_tree().quit()


func _measure() -> void:
	var bone_world := _attach.global_transform
	var want := bone_world * _player._eye_socket
	var have := _player.head.global_transform
	_worst_gap = maxf(_worst_gap, want.origin.distance_to(have.origin))
	var from_bone := have.origin.distance_to(bone_world.origin)
	_nearest = minf(_nearest, from_bone)
	_farthest = maxf(_farthest, from_bone)
