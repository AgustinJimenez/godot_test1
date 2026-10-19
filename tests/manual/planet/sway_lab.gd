extends SceneTree
## A tree whose branches bend as a body walks through it, saved as pictures (before, during, after):
##   godot --path . -s tests/manual/planet/sway_lab.gd -- E:/path/prefix arch:oak|form:SHRUB [lift]
## `lift`: metres the body is raised (a tall oak's branches start high); the pictures are prefix_0.png, _1.png, _2.png.

var _tree: PlanetSwayTree
var _more: Array[PlanetSwayTree] = [] # (the turf: a row of tufts)
var _frames := 0
var _prefix := "sway"
var _lift := 0.0
var _reach := 0.0


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	_prefix = args[0]
	var kind := args[1] if args.size() > 1 else "form:SHRUB"
	_lift = args[2].to_float() if args.size() > 2 else 0.0
	RenderingServer.global_shader_parameter_set(&"realism", 1.0)
	FloraMeshes.detailed = true
	var archetype := kind.trim_prefix("arch:") if kind.begins_with("arch:") else ""
	var form: int = PlantSpecies.Form.keys().find(kind.trim_prefix("form:"))
	var chosen: PlantSpecies = null
	for one in SpeciesRegistry.new(8, 36).species:
		if (archetype != "" and one.archetype == archetype) or (archetype == "" and one.form == form):
			chosen = one
			break
	var turf := kind == "turf"
	var mesh := FloraMeshes.turf_tuft(0) if turf else PlantMeshes.build(chosen, 0, true)
	_tree = PlanetSwayTree.new()
	if not _tree.setup(mesh, FloraMeshes.material(), Color(1, 1, 1, 1)):
		print("SWAY_LAB no branches")
		quit(1)
		return
	root.add_child(_tree)
	_reach = 1.5 if turf else maxf(chosen.crown * 1.2, 1.5)
	if turf:
		for index in 24: # a patch of turf: the walker passes through the middle
			var more := PlanetSwayTree.new()
			more.setup(FloraMeshes.turf_tuft(index), FloraMeshes.material(), Color(0.9, 0.95, 0.9, 1.0))
			more.position = Vector3(randf_range(-1.6, 1.6), 0.0, randf_range(-0.9, 0.9))
			more.rotation.y = randf() * TAU
			more.scale = Vector3.ONE * randf_range(0.8, 1.5)
			root.add_child(more)
			_more.append(more)
	var floor_mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(60.0, 40.0)
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
	var height := 0.5 if turf else maxf(chosen.height, 2.0)
	camera.look_at_from_position(Vector3(0.0, height * 0.55, height * 1.3 + 1.2), Vector3(0.0, height * 0.5, 0.0))
	if turf:
		camera.look_at_from_position(Vector3(0.0, 0.55, 2.4), Vector3(0.0, 0.15, 0.0))
		floor_material.albedo_color = Color(0.42, 0.3, 0.22)
	root.size = Vector2i(1100, 800)
	print("SWAY_LAB ", "turf" if turf else chosen.summary(), " branches=", (mesh.get_meta(&"branches") as PackedFloat32Array).size() / 10)


## The walker's x at a frame: from the left of the tree to its right over the first 120 frames, then gone.
func _body_x(frame: int) -> float:
	return lerpf(-_reach, _reach, clampf(float(frame) / 120.0, 0.0, 1.0))


func _process(_delta: float) -> bool:
	_frames += 1
	var body := PackedFloat32Array()
	if _frames <= 120:
		var x := _body_x(_frames)
		body = PackedFloat32Array([x, _lift, 0.0, x, _lift + 1.8, 0.0, 0.4])
	_tree.step(body, 1.0 / 60.0)
	for more in _more:
		var inverse := more.global_transform.affine_inverse()
		var local := PackedFloat32Array()
		if not body.is_empty():
			var a := inverse * Vector3(body[0], body[1], body[2])
			var b := inverse * Vector3(body[3], body[4], body[5])
			local = PackedFloat32Array([a.x, a.y, a.z, b.x, b.y, b.z, body[6] / more.scale.x])
		more.step(local, 1.0 / 60.0)
	if _frames == 5 or _frames == 62 or _frames == 400:
		root.get_texture().get_image().save_png("%s_%d.png" % [_prefix, 0 if _frames == 5 else (1 if _frames == 62 else 2)])
		print("SWAY_LAB frame ", _frames, " most turned ", snappedf(_tree.most_turned(), 0.001), " rad")
	if _frames == 401:
		quit()
	return false
