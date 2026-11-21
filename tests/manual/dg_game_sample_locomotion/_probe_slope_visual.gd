extends SceneTree
## Probes the game-rig visual on slopes and stairs: which clip states own the frame.
##   1. Walk up a 20 deg ramp -> SlopeUp (the game's authored uphill cycle).
##   2. Walk off a 0.35 m platform -> Locomotion throughout (a stair, not a fall).
##   3. Walk along the flat ring -> Locomotion, as a control.

const DIR := "res://tests/manual/dg_game_sample_locomotion/"
const BODY := preload(DIR + "dg_game_sample_locomotion_body.gd")
const VIS := preload(DIR + "dg_player_visual.gd")
const TUNING := preload(DIR + "dg_game_sample_locomotion_tuning.gd")


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	await _ramp_phase()
	await _step_phase(0.35)
	await _step_phase(0.60)
	quit()


func _ramp_phase() -> void:
	var root := await _build_world(Vector3(0.0, 0.05, 2.0))
	_add_ramp(root, 20.0, 24.0)
	var body: Node3D = root.get_node("Body")
	var vis: Node3D = root.get_node("Body/LocomotionVisual")
	await _frames(10)
	var seq: Array = []
	for i in 150:
		body.set_move_input(Vector3(0.0, 0.0, -1.0), 1.0)
		vis.sync(1.0 / 60.0)
		await physics_frame
		_record(seq, vis.playback_name(), "slope %.1f" % body.get_slope_deg())
		if i == 60:
			print("debug: slope %.1f  vel %s  has SlopeUp %s  nodes %s" % [
				body.get_slope_deg(), body.velocity,
				vis.machine_has(&"SlopeUp"), vis.tree.tree_root.get_node_list()
			])
	print("ramp states: ", seq)
	print("ramp end: y %.2f m, slope %.1f deg, on floor %s" % [
		body.global_position.y, body.get_slope_deg(), body.is_on_floor()
	])
	root.queue_free()
	await _frames(4)


func _step_phase(height: float) -> void:
	var root := await _build_world(Vector3(0.0, height + 0.01, 3.0))
	_add_box(root, Vector3(6.0, height, 6.0), Vector3(0.0, height * 0.5, 3.0))
	var body: Node3D = root.get_node("Body")
	var vis: Node3D = root.get_node("Body/LocomotionVisual")
	await _frames(20)
	var seq: Array = []
	for i in 120:
		body.set_move_input(Vector3(0.0, 0.0, -1.0), 1.0)
		vis.sync(1.0 / 60.0)
		await physics_frame
		_record(seq, vis.playback_name(), "y %.2f" % body.global_position.y)
	print("stair %.2f m: %s" % [height, seq])
	print("stair %.2f m end: y %.2f m, grounded %s" % [
		height, body.global_position.y, body.is_grounded()
	])
	root.queue_free()
	await _frames(4)


func _record(seq: Array, state: StringName, note: String) -> void:
	if seq.is_empty() or seq[seq.size() - 1][0] != state:
		seq.append([state, note])


func _build_world(spawn: Vector3) -> Node3D:
	var root := Node3D.new()
	get_root().add_child(root)
	_add_box(root, Vector3(80.0, 1.0, 80.0), Vector3(0.0, -0.5, 0.0))
	var body: Node3D = BODY.new()
	body.name = "Body"
	body.tuning = TUNING.new()
	body.position = spawn
	root.add_child(body)
	body.set_placeholder_visible(false)
	var vis := VIS.new()
	# Not "Visual": the body builds its own placeholder with that name.
	vis.name = "LocomotionVisual"
	vis.body = body
	body.add_child(vis)
	return root


func _add_box(root: Node3D, size: Vector3, position: Vector3, rotation_x_deg := 0.0) -> void:
	var static_body := StaticBody3D.new()
	static_body.position = position
	static_body.rotation_degrees.x = rotation_x_deg
	root.add_child(static_body)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	static_body.add_child(shape)


func _add_ramp(root: Node3D, angle_deg: float, length: float) -> void:
	var theta := deg_to_rad(angle_deg)
	var thickness := 0.4
	var centre := Vector3(
		0.0,
		length * 0.5 * sin(theta) - thickness * 0.5 * cos(theta),
		-length * 0.5 * cos(theta) - thickness * 0.5 * sin(theta)
	)
	_add_box(root, Vector3(6.0, thickness, length), centre, rad_to_deg(theta))


func _frames(count: int) -> void:
	for i in count:
		await physics_frame
