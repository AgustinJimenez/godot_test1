extends Node3D
## Looks at one cabin (the plant shader's board wood): `-- --shot=PATH`, `--procedural` bakes the
## fitted boards (WoodFits) in place of the plain procedural ones.


func _ready() -> void:
	FloraMeshes.detailed = true
	WorldWind.set_realism(1.0)
	var shot := ""
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--shot="):
			shot = argument.substr(7)
		if argument == "--procedural":
			var baker := WoodBaker.new()
			add_child(baker)
			var tile: Image = await baker.bake("oak_wood_planks")
			tile.generate_mipmaps()
			var boards := FloraMeshes.structure_material()
			boards.set_shader_parameter(&"wood_tile", ImageTexture.create_from_image(tile))
			boards.set_shader_parameter(&"wood_tile_on", 1.0)
	var chunk := Node3D.new()
	add_child(chunk)
	var structures := WorldStructures.new()
	var plan := {"position": Vector3.ZERO, "yaw": 0.4, "kind": WorldStructures.Kind.CABIN}
	structures.build(chunk, plan, 1337)
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(60.0, 60.0)
	ground.mesh = plane
	add_child(ground)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-35.0, -30.0, 0.0)
	sun.shadow_enabled = true
	add_child(sun)
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.6, 0.75, 0.95)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.55, 0.6, 0.7)
	var camera := Camera3D.new()
	camera.environment = environment
	add_child(camera)
	camera.look_at_from_position(Vector3(5.0, 2.2, 6.0), Vector3(0.0, 1.3, 0.0))
	if shot != "":
		await get_tree().create_timer(1.5).timeout
		get_viewport().get_texture().get_image().save_png(shot)
		get_tree().quit()
