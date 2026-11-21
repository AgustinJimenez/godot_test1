extends SceneTree
## Regression suite for tests/manual/dg_game_sample_locomotion/.
##
## Two layers:
##   1. Pure state-machine checks: predicates named after the UFunctions
##      recovered from DGGameSample.exe (WantsToTransition*, CanEarlyOutAnyTurn*).
##   2. In-tree body checks: acceleration, braking to idle, turn in place,
##      crouch capsule swap and airborne state, stepped on a real floor - plus the recovered
##      floor/step geometry (44.765 deg walkable slope, 0.45 m auto-step, 0.40 m floor snap).
##
## Run: godot --headless --fixed-fps 60 --path . \
##        --script res://tests/automated/dg_game_sample_locomotion/dg_game_sample_locomotion_test.gd
## Exit code 0 = pass, 1 = failure.

const BODY_SCRIPT := preload(
	"res://tests/manual/dg_game_sample_locomotion/dg_game_sample_locomotion_body.gd"
)
const MACHINE_SCRIPT := preload(
	"res://tests/manual/dg_game_sample_locomotion/dg_game_sample_locomotion_state_machine.gd"
)
const TUNING_SCRIPT := preload(
	"res://tests/manual/dg_game_sample_locomotion/dg_game_sample_locomotion_tuning.gd"
)
const VISUAL_SCRIPT := preload(
	"res://tests/manual/dg_game_sample_locomotion/dg_game_sample_locomotion_visual.gd"
)

const PHYSICS_DELTA := 1.0 / 60.0

var _fails := 0
var _checks := 0
## Static geometry created by the terrain tests, freed by `_clear_terrain`.
var _terrain: Array[Node3D] = []


func _init() -> void:
	_run_all.call_deferred()


func _check(label: String, ok: bool, detail: String) -> void:
	_checks += 1
	if not ok:
		_fails += 1
	print("  %s  %-52s %s" % ["PASS" if ok else "FAIL", label, detail])


func _make_machine() -> DGGameSampleLocomotionStateMachine:
	var machine: DGGameSampleLocomotionStateMachine = MACHINE_SCRIPT.new()
	machine.tuning = TUNING_SCRIPT.new()
	return machine


func _run_all() -> void:
	print("== DG_GAME_SAMPLE locomotion model ==")
	_test_idle_to_move_gate()
	_test_idle_to_turn_gate()
	_test_move_to_idle_gate()
	_test_turn_early_out_on_release()
	await _test_body_accelerates_and_stops()
	await _test_body_turn_in_place()
	await _test_body_crouch()
	await _test_body_airborne()
	await _test_floor_settings()
	await _test_body_walks_up_ramp()
	await _test_body_refuses_too_steep_ramp()
	await _test_body_climbs_step()
	await _test_body_refuses_tall_step()
	await _test_body_snaps_down_step()
	await _test_visual_layer()
	print("== %d checks, %d failed ==" % [_checks, _fails])
	quit(1 if _fails > 0 else 0)


# ------------------------------------------------------- state machine only --

func _test_idle_to_move_gate() -> void:
	var machine := _make_machine()
	machine.input_magnitude = 0.9
	machine.angle_to_input_deg = 10.0
	machine.tick(PHYSICS_DELTA)
	_check(
		"idle -> move under the turn threshold",
		machine.state_name() == &"Move",
		machine.state_name()
	)


func _test_idle_to_turn_gate() -> void:
	var machine := _make_machine()
	machine.input_magnitude = 0.9
	machine.angle_to_input_deg = 120.0
	machine.tick(PHYSICS_DELTA)
	_check(
		"idle -> turn beyond the turn threshold",
		machine.state_name() == &"Turn",
		machine.state_name()
	)
	machine.angle_to_input_deg = 0.0
	machine.input_magnitude = 0.0
	for _step in 120:
		machine.tick(PHYSICS_DELTA)
	_check("turn finishes back to idle", machine.state_name() == &"Idle", machine.state_name())


func _test_move_to_idle_gate() -> void:
	var machine := _make_machine()
	machine.input_magnitude = 0.9
	machine.angle_to_input_deg = 0.0
	machine.tick(PHYSICS_DELTA)
	machine.input_magnitude = 0.0
	machine.planar_speed = 0.1
	machine.tick(PHYSICS_DELTA)
	_check(
		"move -> idle once input and speed drop",
		machine.state_name() == &"Idle",
		machine.state_name()
	)


func _test_turn_early_out_on_release() -> void:
	var machine := _make_machine()
	machine.input_magnitude = 0.9
	machine.angle_to_input_deg = 150.0
	machine.tick(PHYSICS_DELTA)
	var started := machine.state_name()
	machine.input_magnitude = 0.0
	for _step in 40:
		machine.tick(PHYSICS_DELTA)
	_check(
		"turn can be cancelled after the minimum hold",
		started == &"Turn" and machine.state_name() == &"Idle",
		"%s -> %s" % [started, machine.state_name()]
	)


# ------------------------------------------------------------------- body --

func _make_body(
	spawn := Vector3(0.0, 0.05, 0.0), with_floor := true
) -> DGGameSampleLocomotionBody:
	if with_floor:
		_add_static_box(Vector3(80.0, 1.0, 80.0), Vector3(0.0, -0.5, 0.0))

	var body: DGGameSampleLocomotionBody = BODY_SCRIPT.new()
	body.tuning = TUNING_SCRIPT.new()
	body.position = spawn
	root.add_child(body)
	return body


# -------------------------------------------------------- terrain helpers --

func _add_static_box(
	size: Vector3, position: Vector3, rotation_x_deg := 0.0
) -> StaticBody3D:
	var static_body := StaticBody3D.new()
	static_body.name = "Terrain"
	static_body.position = position
	static_body.rotation_degrees.x = rotation_x_deg
	root.add_child(static_body)

	var mesh := BoxMesh.new()
	mesh.size = size
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	static_body.add_child(instance)

	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	static_body.add_child(shape)

	_terrain.append(static_body)
	return static_body


## Ramp whose top surface reaches y = 0 at z = 0 and rises toward -Z, so a body walking in -Z
## walks uphill. The box is sunk by its own thickness: only the surface matters here.
func _add_ramp(angle_deg: float, length: float, width := 6.0) -> StaticBody3D:
	var theta := deg_to_rad(angle_deg)
	var thickness := 0.4
	var centre := Vector3(
		0.0,
		length * 0.5 * sin(theta) - thickness * 0.5 * cos(theta),
		-length * 0.5 * cos(theta) - thickness * 0.5 * sin(theta)
	)
	return _add_static_box(Vector3(width, thickness, length), centre, rad_to_deg(theta))


func _clear_terrain() -> void:
	for node in _terrain:
		node.queue_free()
	_terrain.clear()


func _test_body_accelerates_and_stops() -> void:
	var body := await _settle_body()
	for _step in 45:
		body.set_move_input(Vector3(0.0, 0.0, -1.0), 1.0)
		await physics_frame
	var moving_speed := body.get_planar_speed()
	var moving_state := body.get_state_name()
	for _step in 90:
		body.set_move_input(Vector3.ZERO, 0.0)
		await physics_frame
	var stopped_speed := body.get_planar_speed()
	_check(
		"forward input accelerates into Move",
		moving_state == &"Move" and moving_speed > 2.0,
		"state %s, %.2f m/s" % [moving_state, moving_speed]
	)
	_check(
		"released input brakes back to Idle",
		body.get_state_name() == &"Idle" and stopped_speed < 0.3,
		"state %s, %.2f m/s" % [body.get_state_name(), stopped_speed]
	)
	body.queue_free()


func _test_body_turn_in_place() -> void:
	var body := await _settle_body()
	var start_yaw := body.facing_yaw
	for _step in 80:
		body.set_move_input(Vector3(1.0, 0.0, 0.0), 1.0)
		await physics_frame
	var turned := absf(rad_to_deg(wrapf(body.facing_yaw - start_yaw, -PI, PI)))
	_check("turn in place reaches a 90 deg heading", turned > 70.0, "%.1f deg turned" % turned)
	body.set_move_input(Vector3.ZERO, 0.0)
	for _step in 30:
		await physics_frame
	body.queue_free()


func _test_body_crouch() -> void:
	var body := await _settle_body()
	var standing := body.get_capsule_height()
	body.set_crouch(true)
	for _step in 40:
		await physics_frame
	var crouched := body.get_capsule_height()
	_check(
		"crouch shrinks the capsule",
		crouched < standing - 0.4,
		"%.2f m -> %.2f m" % [standing, crouched]
	)
	body.queue_free()


func _test_body_airborne() -> void:
	var body := await _settle_body()
	body.request_jump()
	for _step in 12:
		body.set_move_input(Vector3.ZERO, 0.0)
		await physics_frame
	var airborne := body.get_state_name()
	await _settle_body_frames(200)
	_check(
		"jump enters Air and lands back on the ground",
		airborne == &"Air" and body.is_on_floor(),
		"air state %s, landed %s" % [airborne, body.is_on_floor()]
	)
	body.queue_free()


# ----------------------------------------------------------- terrain checks --

func _test_floor_settings() -> void:
	var body := await _settle_body()
	var angle := rad_to_deg(body.floor_max_angle)
	_check(
		"walkable floor angle is the recovered 44.765 deg",
		absf(angle - 44.765083) < 0.01,
		"%.4f deg" % angle
	)
	_check(
		"floor snap length is 0.40 m",
		is_equal_approx(body.floor_snap_length, 0.40),
		"%.2f m" % body.floor_snap_length
	)
	body.queue_free()


func _test_body_walks_up_ramp() -> void:
	for angle in [20.0, 40.0]:
		_clear_terrain()
		_add_static_box(Vector3(80.0, 1.0, 80.0), Vector3(0.0, -0.5, 0.0))
		_add_ramp(angle, 24.0)
		var body := _make_body(Vector3(0.0, 0.05, 2.0), false)
		await _settle_body_frames(8)
		var steepest := 0.0
		for _step in 150:
			body.set_move_input(Vector3(0.0, 0.0, -1.0), 1.0)
			await physics_frame
			steepest = maxf(steepest, body.get_slope_deg())
		var climb := body.global_position.y
		_check(
			"body climbs a %.0f deg ramp" % angle,
			climb > 1.0 and body.is_on_floor(),
			"y %.2f m, on floor %s" % [climb, body.is_on_floor()]
		)
		_check(
			"slope reported along the movement direction (%.0f deg)" % angle,
			absf(steepest - angle) < 3.0,
			"%.1f deg measured" % steepest
		)
		body.queue_free()
		_clear_terrain()


func _test_body_refuses_too_steep_ramp() -> void:
	_clear_terrain()
	_add_static_box(Vector3(80.0, 1.0, 80.0), Vector3(0.0, -0.5, 0.0))
	_add_ramp(50.0, 16.0)
	var body := _make_body(Vector3(0.0, 0.05, 2.0), false)
	await _settle_body_frames(8)
	for _step in 150:
		body.set_move_input(Vector3(0.0, 0.0, -1.0), 1.0)
		await physics_frame
	var climb := body.global_position.y
	_check(
		"a 50 deg ramp is not walkable",
		climb < 0.35,
		"y %.2f m (walkable limit is 44.77 deg)" % climb
	)
	body.queue_free()
	_clear_terrain()


func _test_body_climbs_step() -> void:
	_clear_terrain()
	_add_static_box(Vector3(80.0, 1.0, 80.0), Vector3(0.0, -0.5, 0.0))
	# 0.35 m riser: taller than the capsule's rounded base can roll over, well under the
	# recovered 45 cm MaxStepHeight, so it only goes up if the step-up assist works.
	_add_static_box(Vector3(6.0, 0.35, 12.0), Vector3(0.0, 0.175, -8.0))
	var body := _make_body(Vector3(0.0, 0.05, 0.0), false)
	await _settle_body_frames(8)
	for _step in 150:
		body.set_move_input(Vector3(0.0, 0.0, -1.0), 1.0)
		await physics_frame
	var climb := body.global_position.y
	_check(
		"0.35 m step is climbed (MaxStepHeight assist)",
		climb > 0.30 and body.is_on_floor(),
		"y %.2f m, on floor %s" % [climb, body.is_on_floor()]
	)
	body.queue_free()
	_clear_terrain()


func _test_body_refuses_tall_step() -> void:
	_clear_terrain()
	_add_static_box(Vector3(80.0, 1.0, 80.0), Vector3(0.0, -0.5, 0.0))
	# 0.60 m riser: above MaxStepHeight, so it must stay a wall.
	_add_static_box(Vector3(6.0, 0.60, 12.0), Vector3(0.0, 0.30, -8.0))
	var body := _make_body(Vector3(0.0, 0.05, 0.0), false)
	await _settle_body_frames(8)
	for _step in 150:
		body.set_move_input(Vector3(0.0, 0.0, -1.0), 1.0)
		await physics_frame
	var climb := body.global_position.y
	_check(
		"a 0.60 m step is not climbed",
		climb < 0.20,
		"y %.2f m (MaxStepHeight is 0.45 m)" % climb
	)
	body.queue_free()
	_clear_terrain()


func _test_body_snaps_down_step() -> void:
	_clear_terrain()
	_add_static_box(Vector3(80.0, 1.0, 80.0), Vector3(0.0, -0.5, 0.0))
	# Walk off a 0.35 m platform. The capsule rolls over the nose, so it is ungrounded for a
	# couple of frames; the swept floor stick (0.40 m) must catch it instead of a free fall.
	# A real fall from 0.35 m takes ~16 frames at 60 Hz, so 4 frames is the discriminator.
	_add_static_box(Vector3(6.0, 0.35, 6.0), Vector3(0.0, 0.175, 3.0))
	var body := _make_body(Vector3(0.0, 0.36, 3.0), false)
	await _settle_body_frames(20)
	var air_frames := 0
	for _step in 120:
		body.set_move_input(Vector3(0.0, 0.0, -1.0), 1.0)
		await physics_frame
		if not body.is_grounded():
			air_frames += 1
	var climb := body.global_position.y
	_check(
		"a 0.35 m drop is snapped, not a fall",
		air_frames <= 4 and climb < 0.06 and body.is_grounded(),
		"%d ungrounded frames, y %.2f m" % [air_frames, climb]
	)
	body.queue_free()
	_clear_terrain()


func _test_visual_layer() -> void:
	var body := await _settle_body()
	var visual: DGGameSampleLocomotionVisual = VISUAL_SCRIPT.new()
	visual.body = body
	body.add_child(visual)
	body.set_placeholder_visible(false)
	await _settle_body_frames(4)
	_check(
		"visual layer builds a skeleton and animation tree",
		visual.skeleton != null and visual.tree != null and visual.player != null,
		"skeleton %s, tree %s" % [visual.skeleton != null, visual.tree != null]
	)
	for _step in 4:
		visual.sync(PHYSICS_DELTA)
		await physics_frame
	var start_clip := visual.playback_name()
	for _step in 40:
		body.set_move_input(Vector3(0.0, 0.0, -1.0), 1.0)
		visual.sync(PHYSICS_DELTA)
		await physics_frame
	var moving_blend := visual.blend_position().length()
	for _step in 60:
		body.set_move_input(Vector3.ZERO, 0.0)
		visual.sync(PHYSICS_DELTA)
		await physics_frame
	var stopped_blend := visual.blend_position().length()
	_check(
		"animation follows the body state",
		start_clip == &"Locomotion" and visual.playback_name() == &"Locomotion",
		"%s -> %s" % [start_clip, visual.playback_name()]
	)
	_check(
		"blend position tracks planar speed",
		moving_blend > 1.5 and stopped_blend < 0.4,
		"%.2f m/s moving, %.2f m/s stopped" % [moving_blend, stopped_blend]
	)
	visual.queue_free()
	body.queue_free()


# ----------------------------------------------------------------- helpers --

func _settle_body() -> DGGameSampleLocomotionBody:
	var body := _make_body()
	await _settle_body_frames(8)
	return body


func _settle_body_frames(frames: int) -> void:
	for _step in frames:
		await physics_frame
