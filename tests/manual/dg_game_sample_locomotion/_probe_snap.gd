extends SceneTree
## Evidence probe for `_stick_to_floor` in the body: walk off a 0.35 m platform and print the
## frames around the nose. Godot's own floor snap only fires on the first frame a floor is lost,
## and this capsule rolls over the nose without a floor contact on that frame, so without the
## sweep the body is airborne here (y ~0.28, is_on_floor() false) and then free-falls.

const DIR := "res://tests/manual/dg_game_sample_locomotion/"
const BODY := preload(DIR + "dg_game_sample_locomotion_body.gd")
const TUNING := preload(DIR + "dg_game_sample_locomotion_tuning.gd")


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var root := Node3D.new()
	get_root().add_child(root)
	_add_box(root, Vector3(80.0, 1.0, 80.0), Vector3(0.0, -0.5, 0.0))
	_add_box(root, Vector3(6.0, 0.35, 6.0), Vector3(0.0, 0.175, 3.0))

	var body: CharacterBody3D = BODY.new()
	body.tuning = TUNING.new()
	body.position = Vector3(0.0, 0.36, 3.0)
	root.add_child(body)
	for i in 20:
		await physics_frame
	print("settled: y %.3f floor %s snap %.2f" % [
		body.global_position.y, body.is_on_floor(), body.floor_snap_length
	])

	var printed := 0
	for i in 120:
		body.set_move_input(Vector3(0.0, 0.0, -1.0), 1.0)
		await physics_frame
		if body.global_position.z < 0.2 and printed < 14:
			print("frame %d  z %6.3f  y %6.3f  vy %6.3f  floor %s grounded %s" % [
				i, body.global_position.z, body.global_position.y, body.velocity.y,
				body.is_on_floor(), body.is_grounded()
			])
			printed += 1
	print("final: y %.3f floor %s" % [body.global_position.y, body.is_on_floor()])
	quit()


func _add_box(root: Node3D, size: Vector3, position: Vector3) -> void:
	var static_body := StaticBody3D.new()
	static_body.position = position
	root.add_child(static_body)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	static_body.add_child(shape)
