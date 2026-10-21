extends Node3D
## Looks at the standing rocks (FloraMeshes.Kind.SPIRE) side by side: `--shot=PATH` saves a picture.

func _ready() -> void:
	var material := StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
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
		instance.material_override = material
		instance.position = Vector3(-10.0 + index * 4.0, 0.0, 0.0)
		add_child(instance)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-35.0, -40.0, 0.0)
	add_child(sun)
	var camera := Camera3D.new()
	camera.position = Vector3(0.0, 2.5, 12.0)
	camera.look_at_from_position(camera.position, Vector3(0.0, 2.0, 0.0))
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
