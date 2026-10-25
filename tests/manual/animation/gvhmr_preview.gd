extends Node3D
## The GVHMR clip on its own SMPL-X body (left) and retargeted onto a catalog character (right); --shot=<png> saves
## a picture after --at=<seconds> and quits. Args: source=, target_model=, clip= (a retargeted .res).

func _ready() -> void:
	var options := {"at": "2.0"}
	for argument in OS.get_cmdline_user_args():
		var pair := argument.split("=", true, 1)
		if pair.size() == 2:
			options[pair[0]] = pair[1]
	var left: Node3D = Node3D.new()
	var left_player: AnimationPlayer
	if options.has("source"): # (without a source fbx only the retargeted character is shown)
		left = (load(options["source"]) as PackedScene).instantiate()
		left.position = Vector3(-1.2, 0.0, 0.0)
		add_child(left)
		left_player = left.find_child("AnimationPlayer", true, false) as AnimationPlayer
		left_player.play(left_player.get_animation_list()[0])
	var right: Node3D = (load(options["target_model"]) as PackedScene).instantiate()
	right.position = Vector3(0.0, 0.0, 0.0) if not options.has("source") else Vector3(1.2, 0.0, 0.0)
	add_child(right)
	var right_player := right.find_child("AnimationPlayer", true, false) as AnimationPlayer
	var library: AnimationLibrary = right_player.get_animation_library(&"")
	if library == null:
		library = AnimationLibrary.new()
		right_player.add_animation_library(&"", library)
	library.add_animation(&"clip", load(options["clip"]))
	print("player root_node ", right_player.root_node, " animations ", right_player.get_animation_list())
	var skeleton := right.find_child("Skeleton3D", true, false) as Skeleton3D
	right_player.play(&"clip")
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(12, 12)
	ground.mesh = plane
	add_child(ground)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-45, -30, 0)
	add_child(sun)
	var camera := Camera3D.new()
	add_child(camera)
	camera.look_at_from_position(Vector3(0, 1.4, 5.5), Vector3(0, 0.9, 0))
	if options.has("cam"): # cam=x,y,z,tx,ty,tz
		var v := String(options["cam"]).split(",")
		camera.look_at_from_position(Vector3(float(v[0]), float(v[1]), float(v[2])), Vector3(float(v[3]), float(v[4]), float(v[5])))
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.5, 0.65, 0.85)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.7, 0.7, 0.75)
	camera.environment = environment
	# the source body is turned to face the way the retargeted character does (their rest poses face different ways)
	await get_tree().process_frame
	await get_tree().process_frame
	if options.has("source"):
		var source_skeleton := left.find_child("Skeleton3D", true, false) as Skeleton3D
		var target_skeleton := skeleton
		var src_axis := _axis(source_skeleton, "left_hip", "right_hip")
		var map: Dictionary = {"LeftUpLeg": "mixamorig_LeftUpLeg", "RightUpLeg": "mixamorig_RightUpLeg"}
		if options.has("manifest"):
			map = JSON.parse_string(FileAccess.get_file_as_string(options["manifest"]))["humanoid_map"]
		var dst_axis := _axis(target_skeleton, map["LeftUpLeg"], map["RightUpLeg"])
		left.rotation.y = Vector3(src_axis.x, 0.0, src_axis.z).signed_angle_to(
				Vector3(dst_axis.x, 0.0, dst_axis.z), Vector3.UP)
	await get_tree().create_timer(float(options["at"])).timeout
	if options.has("shot"):
		get_viewport().get_texture().get_image().save_png(options["shot"])
		get_tree().quit()


func _axis(skeleton: Skeleton3D, left_bone: String, right_bone: String) -> Vector3:
	var a := skeleton.get_bone_global_pose(skeleton.find_bone(left_bone)).origin
	var b := skeleton.get_bone_global_pose(skeleton.find_bone(right_bone)).origin
	return b - a
