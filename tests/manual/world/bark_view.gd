extends Node3D
## Looks at the bark of one tree species close up, in the plant shader: `--species=N` (the Nth tree
## of seed 1337), `--shot=PATH` saves a picture, `--height=M` where on the trunk, `--dist=M`,
## `--compare`: the same tree twice, photographs left, baked procedural bark right. With no options
## (F6 in the editor) it shows that comparison of tree 0 at 3.4 m.

const KIND_NAMES: Array[String] = ["oak", "birch", "pine", "ash", "maple", "palm (rings)", "cedar"]
## kinds with a procedural version in the game (BarkBaker); the others show the photograph twice
const PROCEDURAL: Array[int] = [0, 2, 3, 4, 6]

var _kind := -1
var _materials: Array[ShaderMaterial] = []
var _label: Label


## Left / right arrow: the previous / next kind of bark, on both trees.
func _unhandled_key_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed:
		return
	if key.keycode == KEY_RIGHT:
		_show_kind((_kind + 1) % KIND_NAMES.size())
	elif key.keycode == KEY_LEFT:
		_show_kind((_kind + KIND_NAMES.size() - 1) % KIND_NAMES.size())


func _show_kind(kind: int) -> void:
	_kind = kind
	for material in _materials:
		material.set_shader_parameter(&"bark_style_force", Vector2(0.3, 0.4)) # (same lichen both)
		material.set_shader_parameter(&"bark_force", float(kind))
	if _label != null:
		var how := "procedural" if kind in PROCEDURAL else "(no procedural version yet)"
		_label.text = "%s [%d/%d]  left: photo  right: %s  (arrow keys: other bark)" % [
				KIND_NAMES[kind], kind + 1, KIND_NAMES.size(), how]


func _ready() -> void:
	FloraMeshes.detailed = true
	WorldWind.set_realism(1.0)
	var number := 0
	var shot := ""
	var height := 1.0
	var dist := 3.4 if OS.get_cmdline_user_args().is_empty() else 1.3
	var rise := 0.0
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--species="):
			number = int(argument.get_slice("=", 1))
		elif argument.begins_with("--shot="):
			shot = argument.substr(7)
		elif argument.begins_with("--height="):
			height = float(argument.get_slice("=", 1))
		elif argument.begins_with("--dist="):
			dist = float(argument.get_slice("=", 1))
		elif argument.begins_with("--rise="): # (camera metres above the target: an angled view)
			rise = float(argument.get_slice("=", 1))
	var registry := SpeciesRegistry.new(1337, 60)
	var trees: Array[PlantSpecies] = []
	for one in registry.species:
		if one.is_tree():
			trees.append(one)
	var chosen: PlantSpecies = trees[number % trees.size()]
	print("BARK species ", chosen.id, " ", chosen.common_name if "common_name" in chosen else "")
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--kind="):
			FloraMeshes.material().set_shader_parameter(&"bark_force", float(argument.get_slice("=", 1)))
		if argument.begins_with("--debug="):
			FloraMeshes.material().set_shader_parameter(&"bark_debug", float(argument.get_slice("=", 1)))
	_materials = [FloraMeshes.material()]
	var instance := MeshInstance3D.new()
	instance.mesh = registry.mesh(chosen.id, 0, true, 0)
	instance.material_override = FloraMeshes.material()
	add_child(instance)
	var args := OS.get_cmdline_user_args()
	if "--compare" in args or args.is_empty(): # (run from the editor, no options: the comparison)
		instance.position.x = -0.9
		var plain := MeshInstance3D.new()
		plain.mesh = instance.mesh
		var procedural := FloraMeshes.material().duplicate() as ShaderMaterial
		var baker := BarkBaker.new()
		add_child(baker)
		procedural.set_shader_parameter(&"bark_photo", await baker.make_array(true))
		plain.material_override = procedural
		_materials.append(procedural)
		plain.position.x = 0.9
		add_child(plain)
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(40.0, 40.0)
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
	camera.fov = 40.0
	add_child(camera)
	camera.look_at_from_position(Vector3(dist * 0.6, height + rise, dist), Vector3(0.0, height, 0.0))
	var layer := CanvasLayer.new()
	_label = Label.new()
	_label.position = Vector2(16.0, 12.0)
	_label.add_theme_font_size_override(&"font_size", 22)
	_label.add_theme_color_override(&"font_shadow_color", Color.BLACK)
	layer.add_child(_label)
	add_child(layer)
	var start_kind := 0
	for argument in args:
		if argument.begins_with("--kind="):
			start_kind = int(argument.get_slice("=", 1))
	_show_kind(clampi(start_kind, 0, KIND_NAMES.size() - 1))
	if shot != "":
		await get_tree().create_timer(1.5).timeout
		get_viewport().get_texture().get_image().save_png(shot)
		get_tree().quit()
