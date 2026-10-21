extends Node3D
## Looks at fallen leaves (FloraMeshes.Kind.LITTER) in the plant shader, close up: `--shot=PATH`.

func _ready() -> void:
	FloraMeshes.detailed = not OS.has_environment("LAB_LOW")
	WorldWind.set_realism(1.0 if FloraMeshes.detailed else 0.0)
	var material: Material
	material = FloraMeshes.material()
	var floor_mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(60.0, 30.0)
	floor_mesh.mesh = plane
	var sand := StandardMaterial3D.new()
	sand.albedo_color = Color(0.8, 0.72, 0.52)
	floor_mesh.material_override = sand
	add_child(floor_mesh)
	for index in 3:
		var instance := MeshInstance3D.new()
		instance.mesh = FloraMeshes.mesh(FloraMeshes.Kind.LITTER, index + 1, FloraMeshes.detailed)
		instance.material_override = material
		instance.position = Vector3(-6.0 + index * 6.0, 0.0, 0.0)
		instance.scale = Vector3.ONE * 5.0
		add_child(instance)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-35.0, -40.0, 0.0)
	add_child(sun)
	var camera := Camera3D.new()
	camera.fov = 35.0
	camera.position = Vector3(0.0, 5.0, 4.0)
	camera.look_at_from_position(camera.position, Vector3(0.0, 0.0, 0.0))
	add_child(camera)
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.5, 0.7, 0.95)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.6, 0.65, 0.75)
	camera.environment = environment
	await get_tree().create_timer(1.0).timeout
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--shot="):
			get_viewport().get_texture().get_image().save_png(argument.substr(7))
	get_tree().quit()
