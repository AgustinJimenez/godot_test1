extends Node3D
## Narrow platform lab: a wide start platform, a 0.3 m beam 1 m above the floor, a wide end
## platform. Headless (`-- --balance-check`) a scripted player walks the whole way; it prints one
## BALANCE_CHECK line: slow on the beam, arms out, never fell, full speed again at the end.

const PLAYER_SCENE := preload("res://actors/player/player.tscn")
const INSTALL_V2 := preload("res://actors/player/foot_ik_v2/foot_ik_v2_install.gd")
const INSTALL_CLIMB := preload("res://actors/player/climb/player_climb_install.gd")

const HEIGHT := 1.0
const BEAM_WIDTH := 0.3
const BEAM_FROM := -1.0 # z where the beam starts (it runs to -6)
const BEAM_TO := -6.0
const SLOW_LIMIT := 1.3 # m/s on the beam
const FAST_MIN := 2.5 # m/s on the end platform

var player: Player
var climb: PlayerClimb
var _checking := false
var _beam_speed := 0.0
var _end_speed := 0.0
var _arm_weight := 0.0
var _arm_spread := 0.0
var _lowest_y := INF
var _frame := 0
var _shots := false


func _ready() -> void:
	_checking = "--balance-check" in OS.get_cmdline_user_args()
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-50.0, 35.0, 0.0)
	add_child(light)
	_add_box(Vector3(0.0, -0.2, 0.0), Vector3(60.0, 0.4, 60.0))
	_add_box(Vector3(0.0, HEIGHT * 0.5, 1.5), Vector3(4.0, HEIGHT, 5.0)) # start
	_add_box(Vector3(0.0, HEIGHT * 0.5, (BEAM_FROM + BEAM_TO) * 0.5),
			Vector3(BEAM_WIDTH, HEIGHT, BEAM_FROM - BEAM_TO)) # beam
	_add_box(Vector3(0.0, HEIGHT * 0.5, BEAM_TO - 2.5), Vector3(4.0, HEIGHT, 5.0)) # end
	player = PLAYER_SCENE.instantiate() as Player
	add_child(player)
	player.global_position = Vector3(0.0, HEIGHT + 0.05, 2.5)
	INSTALL_V2.install(player.body, player.skeleton)
	climb = INSTALL_CLIMB.install(player)
	if "--balance-shots" in OS.get_cmdline_user_args():
		var camera := Camera3D.new()
		add_child(camera)
		camera.look_at_from_position(Vector3(3.0, 2.2, -3.5), Vector3(0.0, 1.5, -3.5))
		camera.make_current()
		_shots = true


func _add_box(at: Vector3, size: Vector3) -> void:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	var mesh := MeshInstance3D.new()
	var box_mesh := BoxMesh.new()
	box_mesh.size = size
	mesh.mesh = box_mesh
	body.add_child(mesh)
	add_child(body)
	body.position = at


func _process(_delta: float) -> void:
	if _shots and _frame % 60 == 30 and player.global_position.z < -1.5:
		get_viewport().get_texture().get_image().save_png("/tmp/balance_%d.png" % _frame)


func _physics_process(_delta: float) -> void:
	_frame += 1
	if not _checking:
		return
	player.movement_input_override = Vector2(0.0, -1.0) if _frame > 60 else Vector2.ZERO
	var z := player.global_position.z
	var speed := Vector2(player.velocity.x, player.velocity.z).length()
	_lowest_y = minf(_lowest_y, player.global_position.y)
	if z < BEAM_FROM - 1.2 and z > BEAM_TO + 0.5: # on the beam, after the arms had time
		_beam_speed = maxf(_beam_speed, speed)
		if z < BEAM_FROM - 2.0 and climb.hands.targets.has(&"left"):
			_arm_weight = maxf(_arm_weight, climb.hands.weight)
			_arm_spread = maxf(_arm_spread, ((climb.hands.targets[&"right"] as Vector3)
					- (climb.hands.targets[&"left"] as Vector3)).length())
	if z < BEAM_TO - 1.5:
		_end_speed = maxf(_end_speed, speed)
	if z < BEAM_TO - 3.0 or _frame > 1500:
		_finish()


func _finish() -> void:
	var failures: Array[String] = []
	if _lowest_y < HEIGHT - 0.2:
		failures.append("fell off (lowest y %.2f)" % _lowest_y)
	if _beam_speed > SLOW_LIMIT or _beam_speed <= 0.0:
		failures.append("beam speed %.2f (limit %.1f)" % [_beam_speed, SLOW_LIMIT])
	if _arm_weight < 0.9 or _arm_spread < 1.2:
		failures.append("arms not out (weight %.2f, spread %.2f)" % [_arm_weight, _arm_spread])
	if _end_speed < FAST_MIN:
		failures.append("end platform speed %.2f (min %.1f)" % [_end_speed, FAST_MIN])
	print("BALANCE_CHECK %s beam_speed=%.2f arm_weight=%.2f arm_spread=%.2f end_speed=%.2f %s" % [
			"PASS" if failures.is_empty() else "FAIL", _beam_speed, _arm_weight, _arm_spread,
			_end_speed, "; ".join(failures)])
	get_tree().quit()
