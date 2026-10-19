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
	if OS.has_environment("LAB_PUSH"): # someone pushing through the plants: "x,y,z,reach"
		var push := OS.get_environment("LAB_PUSH").split(",")
		RenderingServer.global_shader_parameter_set(&"pusher_a", Vector4(push[0].to_float(), push[1].to_float(),
				push[2].to_float(), push[3].to_float()))
	FloraMeshes.detailed = not OS.has_environment("LAB_LOW") # LAB_LOW=1: the cheaper meshes of the default ground detail
	var kind: FloraMeshes.Kind = FloraMeshes.Kind.ROCK
	var shown := 0.0 # the height of what is shown, for the camera
	if kind_name.begins_with("form:") or kind_name.begins_with("arch:"): # the plants of one growth form (form:PALM) or tree kind (arch:oak)
		var form: int = PlantSpecies.Form.keys().find(kind_name.trim_prefix("form:"))
		var archetype := kind_name.trim_prefix("arch:") if kind_name.begins_with("arch:") else ""
		var found := 0
		for one in SpeciesRegistry.new(8, 36).species:
			if found >= 5 or (one.archetype != archetype if archetype != "" else one.form != form):
				continue
			var instance := MeshInstance3D.new()
			instance.mesh = PlantMeshes.build(one, 0, true)
			instance.material_override = FloraMeshes.material()
			instance.position = Vector3((float(found) - 2.0) * maxf(one.crown * 2.2, 2.4), 0.0, 0.0)
			root.add_child(instance)
			print(one.summary())
			shown = maxf(shown, one.height)
			found += 1
	else:
		kind = {"rock": FloraMeshes.Kind.ROCK, "pebbles": FloraMeshes.Kind.PEBBLES,
				"litter": FloraMeshes.Kind.LITTER, "twigs": FloraMeshes.Kind.TWIGS,
				"spire": FloraMeshes.Kind.SPIRE, "log": FloraMeshes.Kind.LOG, "stump": FloraMeshes.Kind.STUMP}[kind_name]
		var count := FloraMeshes.variant_count(kind)
		for index in count:
			var instance := MeshInstance3D.new()
			instance.mesh = FloraMeshes.mesh(kind, index, true)
			instance.material_override = FloraMeshes.material()
			instance.position = Vector3((float(index) - float(count - 1) * 0.5) * (6.0 if kind == FloraMeshes.Kind.SPIRE else 2.4), 0.0, 0.0)
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
	if shown > 0.0 and args.size() > 2: # a close look: args[2] = "x,y,z" of the camera, looking at the origin's column
		var parts := args[2].split(",")
		camera.look_at_from_position(Vector3(parts[0].to_float(), parts[1].to_float(), parts[2].to_float()),
				Vector3(parts[0].to_float(), parts[1].to_float(), 0.0))
	elif shown > 0.0:
		camera.look_at_from_position(Vector3(0.0, shown * 0.7, shown * 1.1 + 3.0), Vector3(0.0, shown * 0.75, 0.0))
	else:
		var far := 15.0 if kind == FloraMeshes.Kind.SPIRE else (7.0 if kind != FloraMeshes.Kind.ROCK else 6.5)
		camera.look_at_from_position(Vector3(0.0, far * 0.3, far), Vector3(0.0, 2.0 if kind == FloraMeshes.Kind.SPIRE else 0.4, 0.0))
	root.size = Vector2i(1600, 700)


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames == 20:
		root.get_texture().get_image().save_png(_path)
		quit()
	return false
