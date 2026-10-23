extends Node3D
## Looks at the rocks in the plant shader (realistic look): the standing rocks (Kind.SPIRE) at the
## back and boulders (Kind.ROCK) in front. `--shot=PATH` saves a picture, `--dist=M` how far the
## camera is (12), `--procedural` leaves the photographed rock out (to compare).

func _ready() -> void:
	FloraMeshes.detailed = true
	WorldWind.set_realism(1.0)
	var dist := 12.0
	var shot := ""
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--shot="):
			shot = argument.substr(7)
		if argument.begins_with("--dist="):
			dist = argument.substr(7).to_float()
		if argument == "--procedural":
			FloraMeshes.material().set_shader_parameter(&"rock_photo_on", 0.0)
		if argument == "--baked": # (the procedural rocks baked from RockFits in the photograph's place)
			var baker := RockBaker.new()
			add_child(baker)
			FloraMeshes.material().set_shader_parameter(&"rock_photo", await baker.make_array())
	var floor_mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(60.0, 30.0)
	floor_mesh.mesh = plane
	var sand := StandardMaterial3D.new()
	sand.albedo_color = Color(0.8, 0.72, 0.52)
	floor_mesh.material_override = sand
	add_child(floor_mesh)
	for index in 6:
		var instance := MeshInstance3D.new()
		instance.mesh = FloraMeshes.mesh(FloraMeshes.Kind.SPIRE, index % 3, true)
		instance.material_override = FloraMeshes.material()
		instance.position = Vector3(-10.0 + index * 4.0, 0.0, 0.0)
		add_child(instance)
		var boulder := MeshInstance3D.new()
		boulder.mesh = FloraMeshes.mesh(FloraMeshes.Kind.ROCK, index, true)
		boulder.material_override = FloraMeshes.material()
		boulder.position = Vector3(-10.0 + index * 4.0, 0.0, 4.0)
		boulder.scale = Vector3.ONE * 1.4
		add_child(boulder)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-35.0, -40.0, 0.0)
	add_child(sun)
	var camera := Camera3D.new()
	camera.position = Vector3(0.0, 2.5, dist)
	camera.look_at_from_position(camera.position, Vector3(0.0, 1.2, 2.0))
	add_child(camera)
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.5, 0.7, 0.95)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.6, 0.65, 0.75)
	camera.environment = environment
	await get_tree().create_timer(1.0).timeout
	if shot != "":
		get_viewport().get_texture().get_image().save_png(shot)
	get_tree().quit()
