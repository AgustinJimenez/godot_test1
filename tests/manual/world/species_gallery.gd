extends Node3D
## Shows every plant species of a seed side by side (a column per species, variants behind it).
## Keys: 1 trees, 2 shrubs and cacti, 3 grasses and reeds, 4 flowers, ferns and mushrooms,
## R a new random seed, D low-poly / realistic meshes, A autumn on / off.

const PAGES := [
	{"name": "Trees", "forms": [PlantSpecies.Form.CONIFER, PlantSpecies.Form.BROADLEAF,
			PlantSpecies.Form.PALM, PlantSpecies.Form.BARE_TREE], "scale": 1.0, "gap": 7.0},
	{"name": "Shrubs and cacti", "forms": [PlantSpecies.Form.SHRUB, PlantSpecies.Form.CACTUS],
			"scale": 1.6, "gap": 3.0},
	{"name": "Grasses and reeds", "forms": [PlantSpecies.Form.GRASS, PlantSpecies.Form.TALL_GRASS,
			PlantSpecies.Form.REED], "scale": 2.0, "gap": 2.0},
	{"name": "Flowers, ferns, mushrooms", "forms": [PlantSpecies.Form.FLOWER,
			PlantSpecies.Form.FERN, PlantSpecies.Form.MUSHROOM], "scale": 2.2, "gap": 1.6},
]

var seed_value := 1337
var page := 0
var detailed := false
var autumn := false
var _registry: SpeciesRegistry
var _plants: Node3D
var _camera: Camera3D
var _label: Label


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	for arg in args:
		if arg.begins_with("--seed="):
			seed_value = int(arg.get_slice("=", 1))
		elif arg.begins_with("--page="):
			page = clampi(int(arg.get_slice("=", 1)) - 1, 0, PAGES.size() - 1)
		elif arg == "--detailed":
			detailed = true
	_build_stage()
	_show()


func _build_stage() -> void:
	var environment := Environment.new()
	environment.background_mode = Environment.BG_SKY
	environment.sky = Sky.new()
	environment.sky.sky_material = ProceduralSkyMaterial.new()
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	var world_environment := WorldEnvironment.new()
	world_environment.environment = environment
	add_child(world_environment)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50.0, -35.0, 0.0)
	sun.shadow_enabled = true
	add_child(sun)
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(400.0, 120.0)
	ground.mesh = plane
	var ground_material := StandardMaterial3D.new()
	ground_material.albedo_color = Color(0.42, 0.52, 0.3)
	ground.material_override = ground_material
	add_child(ground)
	_camera = Camera3D.new()
	_camera.fov = 45.0
	add_child(_camera)
	var layer := CanvasLayer.new()
	add_child(layer)
	_label = Label.new()
	_label.position = Vector2(16, 12)
	layer.add_child(_label)


func _show() -> void:
	if _plants != null:
		_plants.queue_free()
	WorldWind.set_realism(1.0 if detailed else 0.0)
	WorldWind.set_autumn(1.0 if autumn else 0.0)
	_registry = SpeciesRegistry.new(seed_value, 36)
	_plants = Node3D.new()
	add_child(_plants)
	var info: Dictionary = PAGES[page]
	var shown: Array[PlantSpecies] = []
	for one in _registry.species:
		if one.form in (info["forms"] as Array):
			shown.append(one)
	var gap: float = info["gap"]
	var scale: float = info["scale"]
	var tallest := 1.0
	for index in shown.size():
		var one := shown[index]
		var x := (float(index) - float(shown.size() - 1) * 0.5) * gap
		for variant in one.variants:
			var instance := MeshInstance3D.new()
			instance.mesh = _registry.mesh(one.id, variant, detailed)
			instance.material_override = FloraMeshes.material()
			instance.scale = Vector3.ONE * scale
			instance.position = Vector3(x, 0.0, -float(variant) * gap * 0.9)
			_plants.add_child(instance)
		tallest = maxf(tallest, one.height * scale)
		var tag := Label3D.new()
		tag.text = "%s\n%s" % [one.common_name, PlantSpecies.Form.keys()[one.form]]
		tag.font_size = 48
		tag.pixel_size = 0.0016 * gap
		tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		tag.position = Vector3(x, -0.0, gap * 0.9)
		tag.no_depth_test = true
		_plants.add_child(tag)
	var span := float(shown.size()) * gap
	var distance := maxf(span * 0.6, tallest * 2.1)
	_camera.position = Vector3(0.0, tallest * 0.55 + 1.0, distance * 0.9)
	_camera.look_at(Vector3(0.0, tallest * 0.4, -gap), Vector3.UP)
	_label.text = "%s  seed %d  %s%s   [1-4] page  [R] new seed  [D] realistic  [A] autumn" % [
			info["name"], seed_value, "realistic" if detailed else "low-poly",
			"  autumn" if autumn else ""]


func _unhandled_key_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	match key.keycode:
		KEY_1, KEY_2, KEY_3, KEY_4:
			page = key.keycode - KEY_1
		KEY_R:
			seed_value = randi() % 100000
		KEY_D:
			detailed = not detailed
		KEY_A:
			autumn = not autumn
		_:
			return
	_show()
