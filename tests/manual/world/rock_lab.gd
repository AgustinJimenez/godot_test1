extends SceneTree
## A row of the scenery meshes in the realistic look, lit by one sun, saved as a picture:
##   godot --path . -s tests/manual/world/rock_lab.gd -- E:/path/picture.png [rock|pebbles|litter|twigs]

var _frames := 0
var _path := "rock_lab.png"


func _initialize() -> void:
	var kind_name := "rock"
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		_path = args[0]
	if args.size() > 1:
		kind_name = args[1]
	RenderingServer.global_shader_parameter_set(&"realism", 1.0)
	FloraMeshes.detailed = true
	var kind: FloraMeshes.Kind = {"rock": FloraMeshes.Kind.ROCK, "pebbles": FloraMeshes.Kind.PEBBLES,
			"litter": FloraMeshes.Kind.LITTER, "twigs": FloraMeshes.Kind.TWIGS}[kind_name]
	var count := FloraMeshes.variant_count(kind)
	for index in count:
		var instance := MeshInstance3D.new()
		instance.mesh = FloraMeshes.mesh(kind, index, true)
		instance.material_override = FloraMeshes.material()
		instance.position = Vector3((float(index) - float(count - 1) * 0.5) * 2.4, 0.0, 0.0)
		root.add_child(instance)
	var floor_mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(40.0, 20.0)
	floor_mesh.mesh = plane
	var floor_material := StandardMaterial3D.new()
	floor_material.albedo_color = Color(0.25, 0.4, 0.15)
	floor_mesh.material_override = floor_material
	root.add_child(floor_mesh)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-40.0, -35.0, 0.0)
	root.add_child(sun)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color(0.6, 0.75, 0.9)
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color(0.6, 0.65, 0.75)
	root.add_child(environment)
	var camera := Camera3D.new()
	root.add_child(camera)
	camera.look_at_from_position(Vector3(0.0, 2.6 if kind != FloraMeshes.Kind.ROCK else 2.0, 7.0 if kind != FloraMeshes.Kind.ROCK else 6.5),
			Vector3(0.0, 0.4, 0.0))
	root.size = Vector2i(1600, 700)


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames == 20:
		root.get_texture().get_image().save_png(_path)
		quit()
	return false
