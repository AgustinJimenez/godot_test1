extends Node3D
## Ledge climbing lab: a wall with a 2.5 m ledge. Headless (`-- --climb-check`) a scripted player
## runs at the wall, jumps, catches the ledge, shimmies right, pulls up and ends standing on top;
## it prints one CLIMB_CHECK line. Interactive: walk and jump at the wall yourself.

const PLAYER_SCENE := preload("res://actors/player/player.tscn")
const INSTALL_V2 := preload("res://actors/player/foot_ik_v2/foot_ik_v2_install.gd")
const INSTALL_CLIMB := preload("res://actors/player/climb/player_climb_install.gd")

const WALL_TOP := 2.5
const WALL_HALF_WIDTH := 3.0
const START := Vector3(0.0, 0.05, 3.2)
const HAND_TOLERANCE := 0.06 # m between a hand and its hold point
const SHIMMY_FRAMES := 60
# standing on the wall top at its back edge and its two side edges (the top is z -1..0)
const EDGE_SPOTS := [Vector3(0.0, WALL_TOP, -0.85), Vector3(-2.85, WALL_TOP, -0.5),
		Vector3(2.85, WALL_TOP, -0.5)]

var player: Player
var climb: PlayerClimb
var _frame := 0
var _phase := "settle"
var _phase_frame := 0
var _hang_frames := 0
var _hang_hand_error := 0.0
var _last_hand_error := 0.0
var _shimmy_start := 0.0
var _shimmy_moved := 0.0
var _checking := false
var _shots := false
var _jump_release := false
var _released: Array[StringName] = [] # actions pressed by the script, let go next frame
var _hung_from_top := -1.0 # y of the body hanging after a drop from the top, -1 = never
var _leap_speed := 0.0
var _regrabbed := false
var _e_hang := false
var _walk_off_y := -1.0
var _hops := 0
var _edges_hung := 0
var _edge_index := 0
var _end_y := -1.0
var _failures: Array[String] = []


func _ready() -> void:
	_checking = "--climb-check" in OS.get_cmdline_user_args()
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-50.0, 35.0, 0.0)
	add_child(light)
	_add_box(Vector3(0.0, -0.2, 0.0), Vector3(40.0, 0.4, 40.0))
	_add_box(Vector3(0.0, WALL_TOP * 0.5, -0.5), Vector3(WALL_HALF_WIDTH * 2.0, WALL_TOP, 1.0))
	player = PLAYER_SCENE.instantiate() as Player
	add_child(player)
	player.global_position = START
	player.floor_max_angle = deg_to_rad(60.0)
	INSTALL_V2.install(player.body, player.skeleton)
	climb = INSTALL_CLIMB.install(player)
	if "--climb-shots" in OS.get_cmdline_user_args(): # side camera, PNGs of the hang and mantle
		var camera := Camera3D.new()
		add_child(camera)
		camera.look_at_from_position(Vector3(2.6, 1.9, 2.4), Vector3(0.0, 1.9, 0.0))
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


func _physics_process(_delta: float) -> void:
	_frame += 1
	_phase_frame += 1
	if _jump_release:
		Input.action_release(&"jump")
		_jump_release = false
	for action: StringName in _released:
		Input.action_release(action)
	_released.clear()
	if not _checking:
		return
	match _phase:
		"settle":
			player.movement_input_override = Vector2.ZERO
			if _phase_frame > 60:
				_next("run")
		"run":
			player.movement_input_override = Vector2(0.0, -1.0)
			if player.global_position.z < 1.9:
				Input.action_press(&"jump")
				_jump_release = true
				_next("jump")
		"jump":
			if climb.state == PlayerClimb.State.HANG:
				_next("hang")
			elif _phase_frame > 120:
				_fail("never caught the ledge (state %d, z %.2f, y %.2f)" % [
						climb.state, player.global_position.z, player.global_position.y])
		"hang":
			player.movement_input_override = Vector2.ZERO
			if _phase_frame == 30:
				_hang_hand_error = _last_hand_error
				_shimmy_start = player.global_position.x
				_next("shimmy")
		"shimmy":
			player.movement_input_override = Vector2(1.0, 0.0)
			if _phase_frame >= SHIMMY_FRAMES:
				_shimmy_moved = player.global_position.x - _shimmy_start
				_hops = climb.shuffle.hops
				_next("mantle")
		"mantle":
			player.movement_input_override = Vector2(0.0, -1.0)
			if climb.state == PlayerClimb.State.FREE and _phase_frame > 20:
				_next("stand")
		"stand":
			player.movement_input_override = Vector2.ZERO
			if _phase_frame > 60:
				if absf(player.global_position.y - WALL_TOP) > 0.1 or not player.is_on_floor():
					_failures.append("not standing on top (y %.2f)" % player.global_position.y)
				_next("edge")
		"edge": # back at the wall edge facing off it: crouch lowers into a hang
			if _phase_frame == 1:
				player.global_position = Vector3(0.0, WALL_TOP, -0.3)
				player.velocity = Vector3.ZERO
				climb.face(Vector3(0.0, 0.0, 1.0), 1.0)
			elif _phase_frame == 10:
				_press(&"crouch")
			elif _phase_frame > 20: # the lowering clip takes a couple of seconds
				if climb.state == PlayerClimb.State.HANG:
					_hung_from_top = player.global_position.y
					_next("leap")
				elif _phase_frame > 300:
					_fail("crouch at the edge did not hang (state %d)" % climb.state)
		"leap": # jump from the hang: up, then the ledge is caught again
			if _phase_frame == 30:
				_press(&"jump")
			elif _phase_frame == 32:
				_leap_speed = player.velocity.y
			elif _phase_frame > 32 and climb.state == PlayerClimb.State.HANG:
				_regrabbed = true
				_next("drop")
			elif _phase_frame > 200:
				_next("drop")
		"drop": # crouch lets go and the body falls to the ground
			if _phase_frame == 30 and climb.state == PlayerClimb.State.HANG:
				_press(&"crouch")
			if _phase_frame > 150:
				_end_y = player.global_position.y
				_next("edges")
		"edges": # E on the back and both side edges of the wall hangs from each
			var spot: Vector3 = EDGE_SPOTS[_edge_index]
			if _phase_frame == 1:
				player.global_position = spot
				player.velocity = Vector3.ZERO
			elif _phase_frame == 38:
				_press(&"interact")
			elif _phase_frame == 220:
				_edges_hung += 1 if climb.state == PlayerClimb.State.HANG else 0
				climb.release()
				_edge_index += 1
				_phase_frame = 0
				if _edge_index >= EDGE_SPOTS.size():
					_next("edge_e")
		"edge_e": # on the edge facing AWAY from it: E turns round and hangs
			if _phase_frame == 1:
				player.global_position = Vector3(0.0, WALL_TOP, -0.3)
				player.velocity = Vector3.ZERO
				climb.face(Vector3(0.0, 0.0, -1.0), 1.0)
			elif _phase_frame == 40:
				_press(&"interact")
			elif _phase_frame == 240:
				_e_hang = climb.state == PlayerClimb.State.HANG
				climb.release()
				player.global_position = Vector3(0.0, WALL_TOP, -0.3)
				player.velocity = Vector3.ZERO
				climb.face(Vector3(0.0, 0.0, 1.0), 1.0)
				_next("walk_off")
		"walk_off": # holding forward into the 2.5 m drop commits to the fall
			player.movement_input_override = Vector2(0.0, -1.0)
			if _phase_frame > 200:
				_walk_off_y = player.global_position.y
				_finish()


func _press(action: StringName) -> void:
	Input.action_press(action)
	_released.append(action)


func _process(_delta: float) -> void:
	_last_hand_error = _hand_error() # the skeleton is posed by now (the physics tick runs before it)
	if _shots and ((_phase == "hang" and _phase_frame in [5, 25])
			or (_phase == "shimmy" and _phase_frame in [8, 16, 24, 32])
			or (_phase == "mantle" and _phase_frame in [10, 35, 60, 85, 110])):
		get_viewport().get_texture().get_image().save_png("/tmp/climb_%s_%d.png" % [_phase, _phase_frame])


func _next(phase: String) -> void:
	_phase = phase
	_phase_frame = 0


## Distance from each wrist (as the hand modifier left it: the skeleton is re-posed after the
## modifiers, so the bone read back later is the animation again) to its hold point, worst of the
## two (m).
func _hand_error() -> float:
	var worst := 0.0
	for side: StringName in [&"left", &"right"]:
		if not climb.hands.targets.has(side) or not climb.hands.debug_wrist.has(side):
			return INF
		worst = maxf(worst, (climb.hands.debug_wrist[side] as Vector3).distance_to(
				climb.hands.targets[side] as Vector3))
	return worst


func _fail(reason: String) -> void:
	_failures.append(reason)
	_finish()


func _finish() -> void:
	if _hang_hand_error > HAND_TOLERANCE:
		_failures.append("hands %.3f m from the ledge (limit %.2f)" % [
				_hang_hand_error, HAND_TOLERANCE])
	if _shimmy_moved < 0.5:
		_failures.append("shimmied only %.2f m" % _shimmy_moved)
	if _edges_hung < EDGE_SPOTS.size() or _hops < 2:
		_failures.append("E hung from %d of %d edges, %d hand hops" % [
				_edges_hung, EDGE_SPOTS.size(), _hops])
	if not _e_hang or _walk_off_y > 0.2:
		_failures.append("E at the edge hung %s, walking off ended at y %.2f" % [_e_hang, _walk_off_y])
	if _hung_from_top < 0.0 or _leap_speed < 4.0 or not _regrabbed or _end_y > 0.2:
		_failures.append("drop-to-hang %.2f, leap speed %.1f, regrab %s, end y %.2f" % [
				_hung_from_top, _leap_speed, _regrabbed, _end_y])
	var line := "CLIMB_CHECK %s hand_error=%.3f shimmy=%.2f hang_y=%.2f leap=%.1f regrab=%s " \
			+ "e=%s edges=%d hops=%d off_y=%.2f end_y=%.2f %s"
	print(line % ["PASS" if _failures.is_empty() else "FAIL", _hang_hand_error, _shimmy_moved,
			_hung_from_top, _leap_speed, _regrabbed, _e_hang, _edges_hung, _hops, _walk_off_y, _end_y,
			"; ".join(_failures)])
	get_tree().quit()
