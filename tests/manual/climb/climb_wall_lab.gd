extends Node3D
## Wall-of-holds lab: a 6 m wall studded with holds (a brick grid, group `climb_hold`) topped by a
## ledge. Headless (`-- --wall-check`) a scripted player jumps onto the lowest holds, climbs up,
## sideways, diagonally and back down; it prints one WALL_CHECK line.

const PLAYER_SCENE := preload("res://actors/player/player.tscn")
const INSTALL_V2 := preload("res://actors/player/foot_ik_v2/foot_ik_v2_install.gd")
const INSTALL_CLIMB := preload("res://actors/player/climb/player_climb_install.gd")

const WALL_X := 8.0
const WALL_TOP := 6.0
const HOLD_COLUMNS := 9
const HOLD_SPACING := Vector2(0.45, 0.4) # m between holds, sideways and up
const HOLD_BOTTOM := 2.2
const HOLD_TOP := 5.4
const START := Vector3(WALL_X, 0.05, 3.2)
# (name, stick, seconds, what the climb has to have done by the end of it)
const STEPS := [
	["up", Vector2(0.0, -1.0), 1.5],
	["right", Vector2(1.0, 0.0), 2.5],
	["up_left", Vector2(-1.0, -1.0), 1.5],
	["down", Vector2(0.0, 1.0), 2.0],
	["top", Vector2(0.0, -1.0), 7.0], # all the way up and over the ledge
]

var player: Player
var climb: PlayerClimb
var _checking := false
var _shots := false
var _frame := 0
var _phase := "settle"
var _phase_frame := 0
var _step := 0
var _step_start := Vector3.ZERO
var _moved: Dictionary = {}
var _foot_error := 0.0
var _foot_frames := 0
var _jump_release := false
var _failures: Array[String] = []


func _ready() -> void:
	_checking = "--wall-check" in OS.get_cmdline_user_args()
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-50.0, 35.0, 0.0)
	add_child(light)
	_add_box(Vector3(0.0, -0.2, 0.0), Vector3(60.0, 0.4, 60.0))
	_add_box(Vector3(WALL_X, WALL_TOP * 0.5, -0.5), Vector3(8.0, WALL_TOP, 1.0))
	_add_holds()
	player = PLAYER_SCENE.instantiate() as Player
	add_child(player)
	player.global_position = START
	INSTALL_V2.install(player.body, player.skeleton, player.body._foot_ik_modifier)
	climb = INSTALL_CLIMB.install(player)
	if "--wall-shots" in OS.get_cmdline_user_args():
		var camera := Camera3D.new()
		add_child(camera)
		camera.look_at_from_position(Vector3(WALL_X + 3.2, 3.6, 3.4), Vector3(WALL_X, 3.4, 0.0))
		camera.make_current()
		_shots = true


func _add_holds() -> void:
	var holds := ClimbHoldWall.new()
	holds.columns = HOLD_COLUMNS
	holds.rows = int((HOLD_TOP - HOLD_BOTTOM) / HOLD_SPACING.y) + 1
	holds.spacing = HOLD_SPACING
	add_child(holds)
	holds.position = Vector3(WALL_X, HOLD_BOTTOM, 0.0)


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
	if _shots and _phase == "climb" and _phase_frame % 45 == 20:
		get_viewport().get_texture().get_image().save_png(
				"/tmp/wall_%d_%d.png" % [_step, _phase_frame])


func _physics_process(_delta: float) -> void:
	_frame += 1
	_phase_frame += 1
	if _jump_release:
		Input.action_release(&"jump")
		_jump_release = false
	if not _checking:
		return
	match _phase:
		"settle":
			if _phase_frame > 60:
				_next("run")
		"run":
			player.movement_input_override = Vector2(0.0, -1.0)
			if player.global_position.z < 1.7:
				Input.action_press(&"jump")
				_jump_release = true
				_next("jump")
		"jump":
			player.movement_input_override = Vector2.ZERO
			if climb.state == PlayerClimb.State.WALL:
				_begin_step()
			elif _phase_frame > 150:
				_fail("never caught a hold (state %d, y %.2f)" % [
						climb.state, player.global_position.y])
		"climb":
			for side: StringName in climb.hands.foot_targets:
				if climb.hands.debug_ankle.has(side) and climb.state == PlayerClimb.State.WALL:
					_foot_frames += 1
					_foot_error = maxf(_foot_error, (climb.hands.debug_ankle[side] as Vector3).distance_to(
							climb.hands.foot_targets[side] as Vector3))
			var step: Array = STEPS[_step]
			# once over the top, stop (holding on would walk off the back of the 1 m wide top)
			player.movement_input_override = (Vector2.ZERO if climb.state == PlayerClimb.State.FREE
					else step[1] as Vector2)
			if _phase_frame >= int(float(step[2]) * 60.0):
				_end_step()
		"release":
			player.movement_input_override = Vector2.ZERO
			if _phase_frame > 90:
				_finish()


func _begin_step() -> void:
	_phase = "climb"
	_phase_frame = 0
	_step_start = player.global_position


func _end_step() -> void:
	_moved[STEPS[_step][0]] = player.global_position - _step_start
	_step += 1
	if _step >= STEPS.size() or climb.state != PlayerClimb.State.WALL:
		_phase = "release"
		_phase_frame = 0
		return
	_begin_step()


func _next(phase: String) -> void:
	_phase = phase
	_phase_frame = 0


func _fail(reason: String) -> void:
	_failures.append(reason)
	_finish()


func _finish() -> void:
	var up: Vector3 = _moved.get("up", Vector3.ZERO)
	var right: Vector3 = _moved.get("right", Vector3.ZERO)
	var up_left: Vector3 = _moved.get("up_left", Vector3.ZERO)
	var down: Vector3 = _moved.get("down", Vector3.ZERO)
	if up.y < 1.0:
		_failures.append("climbed up only %.2f m" % up.y)
	if right.x < 0.8:
		_failures.append("traversed right only %.2f m" % right.x)
	if up_left.y < 0.4 or up_left.x > -0.3:
		_failures.append("diagonal moved (%.2f, %.2f)" % [up_left.x, up_left.y])
	if down.y > -0.8:
		_failures.append("climbed down only %.2f m" % -down.y)
	if _foot_frames < 30:
		_failures.append("feet found a hold on only %d frames" % _foot_frames)
	if absf(player.global_position.y - WALL_TOP) > 0.1 or not player.is_on_floor():
		_failures.append("not standing on the wall top (y %.2f)" % player.global_position.y)
	print("WALL_CHECK %s feet=%d/%.3f up=%.2f right=%.2f diag=(%.2f,%.2f) down=%.2f y=%.2f %s" % [
			"PASS" if _failures.is_empty() else "FAIL", _foot_frames, _foot_error, up.y, right.x,
			up_left.x, up_left.y, down.y, player.global_position.y,
			"; ".join(_failures)])
	get_tree().quit()
