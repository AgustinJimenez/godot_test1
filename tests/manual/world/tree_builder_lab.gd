extends Node3D
## One tree and every trait that makes it, live. The panel on the left has a slider for each trait
## of
## the TreeGenome (see systems/world_gen/flora/tree_genome.gd); move one and the tree is grown again
## at once. "Generate random" draws all the traits at random (from a leafy or a conifer start), "New
## dice" keeps the traits and only regrows the branches differently, the presets go back to a
## leafy tree or a conifer. Mouse: drag the left button over the tree to turn around it, wheel to
## zoom, right button drag to pan. The label shows the triangle count of what is on screen.
## Command line (after --): --seed=N  --lowpoly

const ROWS := [
	{"group": "Trunk"},
	{"name": "height", "prop": "height", "min": 0.1, "max": 45.0, "step": 0.05},
	{"name": "girth (trunk radius)", "prop": "girth", "min": 0.01, "max": 2.6, "step": 0.005},
	{"name": "root flare", "prop": "root_flare", "min": 0.0, "max": 1.0, "step": 0.01},
	{"name": "column top (leader, <0 cone)", "prop": "column", "min": -0.01, "max": 1.0, "step": 0.01},
	{"name": "taper", "prop": "taper", "min": 0.25, "max": 0.95, "step": 0.01},
	{"name": "trunk flutes", "prop": "flutes", "min": 0, "max": 8, "step": 1},
	{"name": "flute depth", "prop": "flute_depth", "min": 0.0, "max": 0.4, "step": 0.01},
	{"name": "trunk bend", "prop": "trunk_bend", "min": 0.0, "max": 1.0, "step": 0.01},
	{"name": "trunk lumps", "prop": "trunk_lumps", "min": 0.0, "max": 1.0, "step": 0.01},
	{"name": "roots", "prop": "roots", "min": 0, "max": 10, "step": 1},
	{"name": "root reach", "prop": "root_reach", "min": 0.5, "max": 3.0, "step": 0.05},
	{"name": "stems (a clump)", "prop": "stems", "min": 1, "max": 6, "step": 1},
	{"name": "stem spread", "prop": "stem_spread", "min": 0.05, "max": 0.5, "step": 0.01},
	{"name": "lean", "prop": "lean", "min": 0.0, "max": 0.3, "step": 0.01},
	{"name": "bare trunk part", "prop": "trunk_part", "min": 0.05, "max": 1.0, "step": 0.01},
	{"group": "Where the branches leave"},
	{"name": "crown radius", "prop": "crown", "min": 0.15, "max": 14.0, "step": 0.05},
	{"name": "crown height / width", "prop": "aspect", "min": 0.4, "max": 2.0, "step": 0.01},
	{"name": "droop", "prop": "droop", "min": 0.0, "max": 1.0, "step": 0.01},
	{"name": "limbs / per node", "prop": "limbs", "min": 3, "max": 10, "step": 1},
	{"name": "limb angle", "prop": "limb_angle", "min": 15.0, "max": 90.0, "step": 1.0},
	{"name": "limb length", "prop": "limb_length", "min": 0.5, "max": 3.0, "step": 0.01},
	{"name": "limb thickness", "prop": "limb_thickness", "min": 0.3, "max": 1.3, "step": 0.01},
	{"name": "node spacing (leader)", "prop": "nodes_spacing", "min": 0.3, "max": 2.0, "step": 0.05},
	{"group": "Branches"},
	{"name": "twist (S-curves)", "prop": "twist", "min": 0.0, "max": 1.0, "step": 0.01},
	{"name": "limb curve", "prop": "curve", "idx": 0, "min": 0.0, "max": 3.0, "step": 0.01},
	{"name": "limb lift", "prop": "lift", "idx": 0, "min": -0.1, "max": 0.4, "step": 0.01},
	{"name": "limb sag", "prop": "sag", "idx": 0, "min": 0.0, "max": 0.3, "step": 0.01},
	{"name": "branch curve", "prop": "curve", "idx": 1, "min": 0.0, "max": 2.5, "step": 0.01},
	{"name": "twig curve", "prop": "curve", "idx": 2, "min": 0.0, "max": 2.0, "step": 0.01},
	{"name": "limb tip thickness", "prop": "tip_radius", "idx": 0, "min": 0.05, "max": 0.8,
			"step": 0.01},
	{"name": "branches per limb", "prop": "children", "idx": 0, "min": 1, "max": 7, "step": 1},
	{"name": "twigs per branch", "prop": "children", "idx": 1, "min": 0, "max": 7, "step": 1},
	{"name": "twig thickness", "prop": "twig_radius", "min": 0.2, "max": 1.0, "step": 0.01},
	{"name": "child thickness", "prop": "child_radius", "min": 0.3, "max": 0.9, "step": 0.01},
	{"name": "branch length", "prop": "child_length", "idx": 0, "min": 0.2, "max": 0.9,
			"step": 0.01},
	{"name": "twig length", "prop": "child_length", "idx": 1, "min": 0.2, "max": 0.9, "step": 0.01},
	{"name": "child: along parent", "prop": "child_forward", "min": 0.0, "max": 1.5, "step": 0.01},
	{"name": "child: away", "prop": "child_side", "min": 0.0, "max": 1.5, "step": 0.01},
	{"name": "child: up", "prop": "child_up", "min": -0.5, "max": 1.0, "step": 0.01},
	{"group": "Leaves"},
	{"name": "leaf length / width", "prop": "leaf_aspect", "min": 0.8, "max": 5.0, "step": 0.05},
	{"name": "leaf size", "prop": "leaf_size", "min": 0.08, "max": 0.45, "step": 0.005},
	{"name": "lobes", "prop": "leaf_lobes", "min": 0, "max": 4, "step": 1},
	{"name": "needle size", "prop": "needle_size", "min": 0.2, "max": 1.5, "step": 0.01},
	{"name": "fronds (palm)", "prop": "fronds", "min": 6, "max": 24, "step": 1},
	{"name": "frond length", "prop": "frond_length", "min": 0.2, "max": 8.0, "step": 0.05},
	{"name": "frond arch", "prop": "frond_arch", "min": 0.1, "max": 1.0, "step": 0.01},
	{"name": "frond droop", "prop": "frond_droop", "min": 0.1, "max": 1.0, "step": 0.01},
	{"name": "leaflet length", "prop": "leaflet", "min": 0.0, "max": 0.4, "step": 0.01},
	{"name": "blade width", "prop": "rib_width", "min": 0.005, "max": 0.06, "step": 0.001},
	{"name": "flower size", "prop": "flower_size", "min": 0.02, "max": 0.15, "step": 0.005},
	{"name": "bark roughness", "prop": "bark_rough", "min": 0.5, "max": 3.0, "step": 0.05},
	{"name": "petals", "prop": "petals", "min": 4, "max": 10, "step": 1},
	{"name": "flower cup (0 flat .. 1 tulip)", "prop": "flower_cup", "min": 0.0, "max": 1.0,
			"step": 0.01},
	{"name": "blossom size", "prop": "blossom_size", "min": 0.03, "max": 0.4, "step": 0.005},
	{"name": "blossom share of twigs", "prop": "blossom_density", "min": 0.1, "max": 1.0,
			"step": 0.01},
	{"name": "foliage clumps", "prop": "foliage_mass", "min": 0.0, "max": 1.0, "step": 0.01},
	{"name": "clump size", "prop": "mass_size", "min": 0.5, "max": 4.0, "step": 0.05},
	{"name": "leaf density", "prop": "leaf_density", "min": 0.0, "max": 1.0, "step": 0.01},
]
const OPTIONS := [
	{"name": "leaf shape", "prop": "leaf_shape", "items": ["oval", "lobed", "palmate", "heart",
			"narrow", "diamond"]},
	{"name": "leaf edge", "prop": "leaf_edge", "items": ["smooth", "serrated", "wavy"]},
	{"name": "leaf pattern", "prop": "leaf_pattern", "items": ["alternate", "opposite", "spiral"]},
	{"name": "foliage", "prop": "foliage", "items": ["blades", "needles", "fronds"]},
	{"name": "blossom kind", "prop": "blossom_kind", "items": ["single", "raceme", "umbel"]},
]
const FLAGS := [
	{"name": "one trunk to the top (leader)", "prop": "leader"},
	{"name": "branches in whorls", "prop": "whorled"},
	{"name": "children left / right (fir)", "prop": "children_planar"},
	{"name": "last child carries on", "prop": "carry_on"},
	{"name": "frosted needles", "prop": "frosted"},
	{"name": "needles only at the tips", "prop": "tips_only"},
	{"name": "branches avoid each other", "prop": "avoid"},
	{"name": "feathery compound leaves", "prop": "compound"},
]

var genome: TreeGenome
var dice := 1
var detailed := true
var leafless := false
var lod := 0
var wind := 0
var randomness := 0.3 ## how far "Generate random" strays from its archetypes: 0 none .. 1 anything
var exotic := 0.2 ## how often "Generate random" pushes a trait somewhere unusual
var _recipe := "" ## what the current tree was made of
var _mesh: MeshInstance3D
var _camera: Camera3D
var _panel_info: Label
var _sliders: Dictionary = {} # row index -> HSlider
var _value_labels: Dictionary = {}
var _option_buttons: Dictionary = {}
var _flag_boxes: Dictionary = {}
var _species_leafy: PlantSpecies
var _species_conifer: PlantSpecies
var _yaw := 0.6
var _pitch := 0.15
var _distance := 14.0
var _target := Vector3(0.0, 4.0, 0.0)
var _rebuilding := false
var _random := RandomNumberGenerator.new()


func _ready() -> void:
	var seed_value := 1337
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--seed="):
			seed_value = int(arg.get_slice("=", 1))
		elif arg == "--lowpoly":
			detailed = false
	_random.seed = seed_value
	var registry := SpeciesRegistry.new(seed_value, 36)
	for one in registry.species:
		if one.form == PlantSpecies.Form.BROADLEAF and _species_leafy == null:
			_species_leafy = one
		elif one.form == PlantSpecies.Form.CONIFER and _species_conifer == null:
			_species_conifer = one
	_build_stage()
	_build_panel()
	_preset(false)


func _slider_row(parent: Control, title: String, start: float, apply: Callable) -> void:
	var row := HBoxContainer.new()
	parent.add_child(row)
	var label := Label.new()
	label.text = "%s %.2f" % [title, start]
	label.custom_minimum_size = Vector2(130, 0)
	row.add_child(label)
	var slider := HSlider.new()
	slider.max_value = 1.0
	slider.step = 0.01
	slider.value = start
	slider.custom_minimum_size = Vector2(240, 0)
	slider.focus_mode = Control.FOCUS_NONE
	slider.value_changed.connect(func(value: float) -> void:
		apply.call(value)
		label.text = "%s %.2f" % [title, value])
	row.add_child(slider)


## A person (about 1.8 m) standing beside the tree, to judge its size; a capsule if the model fails.
func _add_scale_figure() -> void:
	var figure: Node3D = null
	var path := "res://assets/models/universal_animation_library/UAL1_Standard.glb"
	var scene := load(path) as PackedScene
	if scene != null:
		figure = scene.instantiate() as Node3D
	if figure == null or figure.find_children("*", "MeshInstance3D").is_empty():
		var capsule := MeshInstance3D.new()
		capsule.mesh = CapsuleMesh.new()
		(capsule.mesh as CapsuleMesh).height = 1.8
		capsule.position.y = 0.9
		figure = Node3D.new()
		figure.add_child(capsule)
	figure.position = Vector3(2.0, 0.0, 0.0)
	add_child(figure)


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
	plane.size = Vector2(200.0, 200.0)
	ground.mesh = plane
	var ground_material := StandardMaterial3D.new()
	ground_material.albedo_color = Color(0.5, 0.5, 0.42)
	ground.material_override = ground_material
	add_child(ground)
	_add_scale_figure()
	_mesh = MeshInstance3D.new()
	_mesh.material_override = FloraMeshes.material()
	add_child(_mesh)
	_camera = Camera3D.new()
	_camera.fov = 45.0
	add_child(_camera)


func _build_panel() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var panel := PanelContainer.new()
	panel.position = Vector2(8, 8)
	panel.custom_minimum_size = Vector2(400, 0)
	panel.size = Vector2(400, 1000)
	layer.add_child(panel)
	var outer := VBoxContainer.new()
	panel.add_child(outer)
	_panel_info = Label.new()
	outer.add_child(_panel_info)
	var buttons := HFlowContainer.new()
	outer.add_child(buttons)
	_button(buttons, "Generate random", func() -> void: _generate_random())
	_button(buttons, "New dice", func() -> void:
		dice = _random.randi()
		_regrow())
	_button(buttons, "Leafy preset", func() -> void: _preset(false))
	_button(buttons, "Conifer preset", func() -> void: _preset(true))
	for kind in TreeArchetypes.NAMES.slice(2):
		_button(buttons, kind.capitalize(), func() -> void: _archetype(kind))
	_button(buttons, "Copy properties", func() -> void: _copy_properties())
	_slider_row(outer, "randomness", randomness, func(value: float) -> void: randomness = value)
	_slider_row(outer, "exoticness", exotic, func(value: float) -> void: exotic = value)
	var checks := HFlowContainer.new()
	outer.add_child(checks)
	_check(checks, "realistic", detailed, func(on: bool) -> void:
		detailed = on
		_regrow())
	_check(checks, "no leaves", leafless, func(on: bool) -> void:
		leafless = on
		_regrow())
	_check(checks, "distance version", lod == 1, func(on: bool) -> void:
		lod = 1 if on else 0
		_regrow())
	_check(checks, "wind", wind == 1, func(on: bool) -> void:
		wind = 1 if on else 0
		_apply_globals())
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(390, 820)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	outer.add_child(scroll)
	var list := VBoxContainer.new()
	list.custom_minimum_size = Vector2(370, 0)
	scroll.add_child(list)
	for option: Dictionary in OPTIONS:
		_add_option(list, option)
	for flag: Dictionary in FLAGS:
		_add_flag(list, flag)
	for index in ROWS.size():
		var row: Dictionary = ROWS[index]
		if row.has("group"):
			var heading := Label.new()
			heading.text = "— %s —" % row["group"]
			heading.add_theme_color_override("font_color", Color(0.7, 0.9, 1.0))
			list.add_child(heading)
		else:
			_add_slider(list, index, row)


func _button(parent: Node, text: String, action: Callable) -> void:
	var button := Button.new()
	button.text = text
	button.focus_mode = Control.FOCUS_NONE
	button.pressed.connect(action)
	parent.add_child(button)


func _check(parent: Node, text: String, on: bool, action: Callable) -> void:
	var box := CheckBox.new()
	box.text = text
	box.button_pressed = on
	box.focus_mode = Control.FOCUS_NONE
	box.toggled.connect(action)
	parent.add_child(box)


func _add_slider(list: Node, index: int, row: Dictionary) -> void:
	var line := HBoxContainer.new()
	list.add_child(line)
	var name_label := Label.new()
	name_label.text = row["name"]
	name_label.custom_minimum_size = Vector2(150, 0)
	line.add_child(name_label)
	var slider := HSlider.new()
	slider.min_value = row["min"]
	slider.max_value = row["max"]
	slider.step = row["step"]
	slider.custom_minimum_size = Vector2(150, 0)
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.focus_mode = Control.FOCUS_NONE
	slider.value_changed.connect(_on_slider.bind(index))
	line.add_child(slider)
	var value_label := Label.new()
	value_label.custom_minimum_size = Vector2(46, 0)
	line.add_child(value_label)
	_sliders[index] = slider
	_value_labels[index] = value_label


func _add_option(list: Node, option: Dictionary) -> void:
	var line := HBoxContainer.new()
	list.add_child(line)
	var name_label := Label.new()
	name_label.text = option["name"]
	name_label.custom_minimum_size = Vector2(150, 0)
	line.add_child(name_label)
	var button := OptionButton.new()
	for item: String in option["items"]:
		button.add_item(item)
	button.focus_mode = Control.FOCUS_NONE
	button.item_selected.connect(func(selected: int) -> void:
		if _rebuilding:
			return
		genome.set(option["prop"], selected)
		_regrow())
	line.add_child(button)
	_option_buttons[option["prop"]] = button


func _add_flag(list: Node, flag: Dictionary) -> void:
	var box := CheckBox.new()
	box.text = flag["name"]
	box.focus_mode = Control.FOCUS_NONE
	box.toggled.connect(func(on: bool) -> void:
		if _rebuilding:
			return
		genome.set(flag["prop"], on)
		_regrow())
	list.add_child(box)
	_flag_boxes[flag["prop"]] = box


func _read(row: Dictionary) -> float:
	var value: Variant = genome.get(row["prop"])
	if row.has("idx"):
		return float(value[row["idx"]])
	return float(value)


func _put(row: Dictionary, value: float) -> void:
	var current: Variant = genome.get(row["prop"])
	if row.has("idx"):
		var old: Variant = current[row["idx"]]
		current[row["idx"]] = int(value) if typeof(old) == TYPE_INT else value
	else:
		genome.set(row["prop"], int(value) if typeof(current) == TYPE_INT else value)


func _on_slider(value: float, index: int) -> void:
	if _rebuilding:
		return
	_put(ROWS[index], value)
	_value_labels[index].text = _format(ROWS[index], value)
	_regrow()


func _format(row: Dictionary, value: float) -> String:
	return "%d" % int(value) if float(row["step"]) >= 1.0 else "%.2f" % value


## Loads the traits of a leafy tree or a conifer (read off the first such species of the seed).
func _preset(conifer: bool) -> void:
	genome = TreeGenome.from_species(_species_conifer if conifer else _species_leafy)
	_show_genome()
	_regrow()


## One of the named kinds of tree in TreeArchetypes (umbrella, giant, oak, dragon, ancient...).
func _archetype(kind: String) -> void:
	genome = TreeArchetypes.make(kind, _species_leafy, _species_conifer)
	_recipe = kind
	dice = _random.randi()
	_show_genome()
	_regrow()
## A new tree drawn from the archetypes (see TreeArchetypes.draw).
func _generate_random() -> void:
	var info: Array = []
	genome = TreeArchetypes.draw(_random, _species_leafy, _species_conifer, randomness, exotic, info)
	_recipe = info[0]
	dice = _random.randi()
	_show_genome()
	_regrow()


## Every slider, option and flag takes its value from the genome.
func _show_genome() -> void:
	_rebuilding = true
	for index: int in _sliders:
		var row: Dictionary = ROWS[index]
		var value := _read(row)
		(_sliders[index] as HSlider).value = value
		(_value_labels[index] as Label).text = _format(row, value)
	for prop: String in _option_buttons:
		(_option_buttons[prop] as OptionButton).select(int(genome.get(prop)))
	for prop: String in _flag_boxes:
		(_flag_boxes[prop] as CheckBox).button_pressed = bool(genome.get(prop))
	_rebuilding = false




## Every trait of the tree as text, onto the clipboard (to paste into a note or a message).
func _copy_properties() -> void:
	var names := {"leaf_shape": PlantSpecies.LeafShape.keys(),
			"leaf_edge": PlantSpecies.LeafEdge.keys(),
			"leaf_pattern": PlantSpecies.LeafPattern.keys(), "foliage": TreeGenome.Foliage.keys(),
			"profile": TreeGenome.Profile.keys()}
	var lines: PackedStringArray = ["TreeGenome (tree_builder_lab)"]
	for info: Dictionary in genome.get_property_list():
		if not (int(info["usage"]) & PROPERTY_USAGE_SCRIPT_VARIABLE):
			continue
		var key: String = info["name"]
		var value: Variant = genome.get(key)
		if names.has(key):
			lines.append("%s = %s" % [key, names[key][int(value)]])
		elif value is Color:
			lines.append("%s = #%s" % [key, (value as Color).to_html(false)])
		elif value is float:
			lines.append("%s = %.3f" % [key, value])
		else:
			lines.append("%s = %s" % [key, str(value)])
	lines.append("dice (random seed of the branches) = %d" % dice)
	lines.append("look = %s, %s, %s" % ["realistic" if detailed else "low-poly",
			"no leaves" if leafless else "leaves", "distance version" if lod == 1 else "full"])
	lines.append("triangles = %s" % _panel_info.text.get_slice(" ", 0))
	DisplayServer.clipboard_set("\n".join(lines))
	_panel_info.text = "copied %d lines to the clipboard" % lines.size()


func _apply_globals() -> void:
	WorldWind.set_realism(1.0 if detailed else 0.0)
	WorldWind.set_wind([0.0, 0.6][wind], Vector2(1.0, 0.3).normalized())


## Grows the tree from the genome and shows it.
func _regrow() -> void:
	if genome == null:
		return
	_apply_globals()
	var builder := MeshBuilder.new()
	builder.detailed = detailed
	builder.leafless = leafless
	var rng := RandomNumberGenerator.new()
	rng.seed = dice
	var capped := TreeGrower.build(builder, genome, rng, lod)
	_mesh.mesh = builder.commit()
	_target = Vector3(0.0, genome.height * 0.45, 0.0)
	_place_camera()
	_panel_info.text = "%d triangles%s   (%s, %s)   %s" % [builder.triangle_count(),
			"  CAPPED: too many branches and leaves" if capped else "",
			"realistic" if detailed else "low-poly", "distance version" if lod == 1 else "full", _recipe]


## How big the plant is, for framing: 1 for a tree of 9 m.
func _plant_size() -> float:
	if genome.foliage == TreeGenome.Foliage.FROND:
		return maxf(genome.height / 9.0, genome.frond_length / 3.0)
	return maxf(maxf(genome.height / 9.0, genome.crown * genome.limb_length / 1.2), 0.12)


func _place_camera() -> void:
	var offset := Vector3(sin(_yaw) * cos(_pitch), sin(_pitch), cos(_yaw) * cos(_pitch)) \
			* _distance * _plant_size()
	_camera.position = _target + offset
	_camera.position.y = maxf(_camera.position.y, 0.1)
	_camera.look_at(_target, Vector3.UP)


func _unhandled_input(event: InputEvent) -> void:
	var button := event as InputEventMouseButton
	if button != null and button.pressed:
		if button.button_index == MOUSE_BUTTON_WHEEL_UP:
			_distance = maxf(_distance * 0.9, 2.0)
			_place_camera()
		elif button.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_distance = minf(_distance * 1.1, 60.0)
			_place_camera()
	var motion := event as InputEventMouseMotion
	if motion != null and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		_yaw -= motion.relative.x * 0.006
		_pitch = clampf(_pitch + motion.relative.y * 0.006, -0.2, 1.45)
		_place_camera()
	elif motion != null and Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
		_target.y = clampf(_target.y + motion.relative.y * 0.02, 0.2, 20.0)
		_place_camera()
