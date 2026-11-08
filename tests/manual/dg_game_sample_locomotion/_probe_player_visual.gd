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
	quit()
