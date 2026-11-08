extends SceneTree
## Where is the lab camera relative to the character, and which way does the mesh face?


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var scene_path := "res://tests/manual/dg_game_sample_locomotion/dg_game_sample_locomotion_lab.tscn"
	var packed := load(scene_path) as PackedScene
	var lab := packed.instantiate()
	get_root().add_child(lab)
	for i in 20:
		await physics_frame
	var body: Node3D = lab.get("body")
	var cam: Camera3D = get_root().get_viewport().get_camera_3d()
	if body == null or cam == null:
		print("missing body/camera")
		quit()
		return
	var to_cam: Vector3 = cam.global_position - body.global_position
	var fwd: Vector3 = body.global_transform.basis * Vector3(0.0, 0.0, -1.0)
	print("body pos ", body.global_position)
	print("camera pos ", cam.global_position)
	print("to camera ", to_cam.normalized(), " body forward ", fwd.normalized())
	print("dot(to_cam, forward) = ", to_cam.normalized().dot(fwd.normalized()))
	# model facing: the head mesh's face normal is not available, so use the mesh bounds
	var player := body.get_node_or_null("LocomotionVisual")
	print("visual: ", player)
	quit()
