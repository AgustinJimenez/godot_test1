extends SceneTree
## Probes the the player visual: does the locomotion model drive his clips?

const DIR := "res://tests/manual/dg_game_sample_locomotion/"
const BODY := preload(DIR + "dg_game_sample_locomotion_body.gd")
const VIS := preload(DIR + "dg_player_visual.gd")
const TUNING := preload(DIR + "dg_game_sample_locomotion_tuning.gd")


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var root := Node3D.new()
	get_root().add_child(root)
	var body: Node3D = BODY.new()
	body.tuning = TUNING.new()
	root.add_child(body)
	var vis := VIS.new()
	vis.body = body
	body.add_child(vis)
	var floor_body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(60.0, 1.0, 60.0)
	shape.shape = box
	floor_body.add_child(shape)
	floor_body.position = Vector3(0.0, -0.5, 0.0)
	root.add_child(floor_body)
	for i in 10:
		vis.sync(1.0 / 60.0)
		await physics_frame
	print("clips: ", vis.available_clips())
	print("state after idle: ", vis.playback_name())

	for i in 90:
		body.set_move_input(Vector3(0.0, 0.0, -1.0), 1.0)
		vis.sync(1.0 / 60.0)
		await physics_frame
	print("state moving: ", vis.playback_name(), " blend ", vis.blend_position(),
			" speed ", body.velocity.length())

	var pl: AnimationPlayer = vis.player
	print("animation count: ", pl.get_animation_list().size())
	print("player speed_scale: ", pl.speed_scale)

	# --- air: jump, fall, land -------------------------------------------------
	body.set_move_input(Vector3.ZERO, 0.0)
	for i in 30:
		vis.sync(1.0 / 60.0)
		await physics_frame
	print("state before jump: ", vis.playback_name(), " on_floor ", body.is_on_floor())

	var seq: Array[StringName] = []
	body.request_jump()
	var airborne := 0
	for i in 240:
		vis.sync(1.0 / 60.0)
		await physics_frame
		var s := vis.playback_name()
		if seq.is_empty() or seq[seq.size() - 1] != s:
			seq.append(s)
		if not body.is_on_floor():
			airborne += 1
	print("air sequence: ", seq)
	print("airborne frames: ", airborne, " (+-", airborne / 60.0, " s)")
	print("state after landing: ", vis.playback_name(), " on_floor ", body.is_on_floor())
	quit()
