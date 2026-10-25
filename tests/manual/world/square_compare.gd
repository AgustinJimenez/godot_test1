extends Control
## The photograph and the procedural version of one surface, as two plain squares side by side
## (no object, no projection, same size). Run it (F6) and use:
##   Left / Right  the previous / next surface      H  colour <-> height lit from the upper left
##   G  the grooved oak, maple, cedar (PLANET_BARK_GROOVES)      Z  zoom 1x / 2x / 4x      Esc  quit
##   O  the surface as an object (rocks: a rock, barks: a trunk), photograph left, ours right: drag turns,
##   wheel zooms, V the next rock shape / tree     `--object`, `--variant=N`, `--orbit=yaw,pitch,distance`
## `--surface=N` starts on the Nth surface, `--shot=PATH` saves a picture and quits, `--height`
## starts on the height view, `--zoom=2` or 4.

const SHADER := preload("res://shaders/world/square_lit.gdshader")
const PHOTOS := "res://tools/bark/bark_downloads/%s_%s"
## label, photograph name, baker kind, baked name
const SURFACES: Array = [
	["oak bark (willow photo)", "bark_willow_02", "bark", "bark_willow_02"],
	["maple bark", "trident_maple_bark", "bark", "trident_maple_bark"],
	["cedar bark", "japanese_cedar_bark", "bark", "japanese_cedar_bark"],
	["ash bark", "tree_bark_03", "bark", "tree_bark_03"],
	["pine bark", "pine_bark", "bark", "pine_bark"],
	["palm bark (rings)", "palm_tree_bark", "ring", "palm_tree_bark"],
	["leaf litter", "forest_leaves_03", "litter", ""],
	["gravel", "gravel_soil", "chip", "gravel_soil"],
	["red soil", "red_soil", "soil", "red_soil"],
	["rock: boulder", "rock_boulder_dry", "lump", "rock_boulder_dry"],
	["rock: face", "rock_face_04", "lump", "rock_face_04"],
	["rock: mottled", "rock_08", "lump", "rock_08"],
	["rock: webbed", "rock_06", "lump", "rock_06"],
	["rock: pitted (cells)", "rock_pitted_mossy", "plate", "rock_pitted_mossy"],
	["wood boards", "oak_wood_planks", "wood", "oak_wood_planks"],
]
## surfaces that also have an object (O): the photograph name -> the rock slot / the bark kind
const ROCK_SLOTS := {"rock_boulder_dry": 0, "rock_face_04": 1, "rock_08": 2, "rock_06": 3,
		"rock_pitted_mossy": 4}
const BARK_KINDS := {"bark_willow_02": 0, "trident_maple_bark": 4, "japanese_cedar_bark": 6,
		"tree_bark_03": 3, "pine_bark": 2, "palm_tree_bark": 5}

var _index := 0
var _height_mode := false
var _zoom := 1.0
var _photo_colour: Texture2D
var _photo_height: Texture2D
var _baked: Texture2D
var _photo_range := Vector2(0.0, 1.0)
var _left: TextureRect
var _right: TextureRect
var _title: Label
var _busy := false
var _derived: Array = [] # our bake's roughness, AO, normal and ARM maps (the boulder only)
var _save_maps := ""
var _extra_at_start := 0
var _extra := 0 # 0: colour or height (H); 1..: the photograph's other maps (M)
var _extra_textures: Array = [] # [label, ImageTexture] of the maps found for this surface
var _rebake_queued := false
var _shot := ""
var _save_bake := ""
var _panel: PanelContainer
var _sliders: Array[HSlider] = []
var _labels: Array[Label] = []
var _object_mode := false # O: a rock or a tree trunk instead of the flat squares
var _object_busy := false
var _views: Array = [] # per side: [SubViewportContainer, MeshInstance3D, Camera3D]
var _orbit := Vector3(0.6, 0.3, 5.0) # yaw, pitch, distance (drag, wheel)
var _target := Vector3(0.0, 0.6, 0.0)
var _variant := 0 # V: the next rock shape / tree
var _seed := 1.0 # the variation seed (settings row): the boulder rolled and turned, the other lumps re-drawn
var _seed_box: SpinBox
var _resolution := 1024 # X: the lump rocks baked at 1024 or 2048 pixels (the photograph stays as it is)
var _turn := true # T: the camera turns round the object by itself (a drag turns it by hand)
var _dragging := false
const RESOLUTIONS: Array[int] = [512, 1024, 2048]
var _res_option: OptionButton
var _pom_check: CheckBox
var _turn_check: CheckBox
var _depth_slider: HSlider
var _depth_label: Label
var _pom := true # P: parallax and self-shadow on the rocks (rock_pom)
var _pom_depth := 0.05 # [ and ]: metres the rock's whole relief is worth (rock_pom_depth)
var _atlas: Image
var _bark_array: Texture2DArray
var _bark_grooves := false
var _registry: SpeciesRegistry
var _trees: Array[PlantSpecies] = []


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var back := ColorRect.new()
	back.color = Color(0.12, 0.12, 0.13)
	back.set_anchors_preset(Control.PRESET_FULL_RECT)
	back.mouse_filter = Control.MOUSE_FILTER_IGNORE # (a drag on the object view must reach _unhandled_input)
	add_child(back)
	var column := VBoxContainer.new()
	column.set_anchors_preset(Control.PRESET_FULL_RECT)
	column.add_theme_constant_override(&"separation", 6)
	add_child(column)
	_title = Label.new()
	_title.add_theme_font_size_override(&"font_size", 20)
	_title.clip_text = true # (a long or changing title must not change the layout)
	_title.custom_minimum_size = Vector2(0.0, 28.0)
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	column.add_child(_title)
	column.add_child(_build_settings())
	var row := HBoxContainer.new()
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override(&"separation", 10)
	column.add_child(row)
	_left = _square(row)
	_right = _square(row)
	for side in 2:
		_views.append(_object_view(row))
	_build_panel()
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--surface="):
			_index = clampi(int(argument.get_slice("=", 1)), 0, SURFACES.size() - 1)
		elif argument.begins_with("--shot="):
			_shot = argument.substr(7)
		elif argument.begins_with("--save-bake="):
			_save_bake = argument.substr(12)
		elif argument.begins_with("--param="):
			var pair := argument.substr(8).split(":")
			for index in BoulderParams.LIST.size():
				if BoulderParams.LIST[index][0] == pair[0]:
					BoulderParams.values[index] = float(pair[1])
		elif argument == "--object":
			_object_mode = true
		elif argument.begins_with("--seed="):
			_seed = float(argument.get_slice("=", 1))
		elif argument.begins_with("--res="):
			_resolution = int(argument.get_slice("=", 1))
		elif argument == "--no-match":
			ColourMatch.enabled = false
		elif argument == "--no-turn":
			_turn = false
		elif argument == "--no-pom":
			_pom = false
		elif argument.begins_with("--pom-depth="):
			_pom_depth = float(argument.get_slice("=", 1))
		elif argument.begins_with("--variant="):
			_variant = int(argument.get_slice("=", 1))
		elif argument.begins_with("--orbit="): # yaw,pitch,distance
			var numbers := argument.substr(8).split(",")
			_orbit = Vector3(float(numbers[0]), float(numbers[1]), float(numbers[2]))
		elif argument == "--height":
			_height_mode = true
		elif argument.begins_with("--save-maps="):
			_save_maps = argument.substr(12)
		elif argument.begins_with("--extra="):
			_extra_at_start = int(argument.get_slice("=", 1))
		elif argument.begins_with("--zoom="):
			_zoom = float(argument.get_slice("=", 1))
	await _show()
	if _extra_at_start > 0:
		_extra = _extra_at_start
		_apply()
	if _shot != "":
		while _object_busy:
			await get_tree().process_frame
		await get_tree().create_timer(1.0 if _object_mode else 0.5).timeout
		get_viewport().get_texture().get_image().save_png(_shot)
		if _save_bake != "":
			_baked.get_image().save_png(_save_bake)
		get_tree().quit()


func _square(parent: Control) -> TextureRect:
	var square := TextureRect.new()
	square.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	square.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	square.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	square.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var material := ShaderMaterial.new()
	material.shader = SHADER
	square.material = material
	parent.add_child(square)
	return square


func _unhandled_key_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or _busy or _object_busy:
		return
	match key.keycode:
		KEY_RIGHT:
			_index = (_index + 1) % SURFACES.size()
			await _show()
		KEY_LEFT:
			_index = (_index + SURFACES.size() - 1) % SURFACES.size()
			await _show()
		KEY_H:
			_height_mode = not _height_mode
			_extra = 0
			_apply()
		KEY_M:
			_cycle_map()
		KEY_O:
			_object_mode = not _object_mode
			_apply()
		KEY_V:
			_variant += 1
			_apply()
		KEY_P:
			_pom = not _pom
			_apply()
		KEY_T:
			_turn = not _turn
			_sync_settings()
		KEY_X:
			_resolution = 2048 if _resolution < 2000 else 1024
			await _rebake()
		KEY_BRACKETLEFT:
			_pom_depth *= 0.5
			_apply()
		KEY_BRACKETRIGHT:
			_pom_depth *= 2.0
			_apply()
		KEY_Z:
			_zoom = 2.0 if _zoom < 1.5 else (4.0 if _zoom < 3.0 else 1.0)
			_apply()
		KEY_G:
			if OS.has_environment("PLANET_BARK_GROOVES"):
				OS.unset_environment("PLANET_BARK_GROOVES")
			else:
				OS.set_environment("PLANET_BARK_GROOVES", "1")
			await _show()
		KEY_C:
			var text := ""
			for index in BoulderParams.LIST.size():
				text += "%s=%.4f " % [BoulderParams.LIST[index][0], BoulderParams.values[index]]
			DisplayServer.clipboard_set(text)
		KEY_R:
			BoulderParams.values = BoulderParams.defaults()
			_sync_sliders()
			await _rebake()
		KEY_ESCAPE:
			get_tree().quit()


func _show() -> void:
	_busy = true
	var entry: Array = SURFACES[_index]
	var grooves := "ON" if OS.has_environment("PLANET_BARK_GROOVES") else "off"
	_title.text = "%s  [%d/%d]   left: photograph   right: procedural" % [
			entry[0], _index + 1, SURFACES.size()]
	_title.text += "   (arrows: surface, H: colour or height, M: other maps, O: object, V: other object, P: parallax %s ([ ] depth %.0f mm), T: turn, G: grooves %s)" % [
			"on" if _pom else "off", _pom_depth * 1000.0, grooves]
	var colour := Image.load_from_file(PHOTOS % [entry[1], "diff.jpg"])
	var height := Image.load_from_file(PHOTOS % [entry[1], "disp.png"])
	_photo_colour = ImageTexture.create_from_image(colour) if colour != null else null
	_photo_height = ImageTexture.create_from_image(height) if height != null else null
	_photo_range = _range_of(height)
	_load_extra_maps(entry[1])
	var baked: Image = await _bake(entry[2], entry[3])
	_baked = ImageTexture.create_from_image(baked)
	_panel.visible = entry[3] == "rock_boulder_dry" and _shot == ""
	_apply()
	_busy = false


func _build_panel() -> void:
	## The boulder's numbers as sliders (BoulderParams.LIST); the bake is redone when one is let go.
	_panel = PanelContainer.new()
	_panel.set_anchors_preset(Control.PRESET_RIGHT_WIDE)
	_panel.offset_left = -270.0
	_panel.offset_top = 40.0
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.1, 0.1, 0.11, 0.97)
	_panel.add_theme_stylebox_override(&"panel", style)
	add_child(_panel)
	var scroll := ScrollContainer.new()
	_panel.add_child(scroll)
	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(250.0, 0.0)
	scroll.add_child(box)
	var hint := Label.new()
	hint.text = "boulder numbers (R reset, C copy): only those that change the bake"
	box.add_child(hint)
	for index in BoulderParams.LIST.size():
		var entry: Array = BoulderParams.LIST[index]
		var label := Label.new()
		label.text = "%s  %.3f" % [entry[0], BoulderParams.values[index]]
		label.add_theme_font_size_override(&"font_size", 12)
		box.add_child(label)
		label.visible = BoulderParams.is_live(entry[0])
		_labels.append(label)
		var slider := HSlider.new()
		slider.min_value = entry[2]
		slider.max_value = entry[3]
		var span := float(entry[3]) - float(entry[2])
		slider.step = 1.0 if BoulderParams.SWITCHES.has(entry[0]) else span / 200.0
		slider.value_changed.connect(_on_slider.bind(index, label))
		slider.drag_ended.connect(func(_changed: bool) -> void: _rebake())
		slider.visible = BoulderParams.is_live(entry[0])
		box.add_child(slider)
		_sliders.append(slider)
	_panel.visible = false


func _on_slider(value: float, index: int, label: Label) -> void:
	BoulderParams.values[index] = value
	label.text = "%s  %.3f" % [BoulderParams.LIST[index][0], value]
	if index == BoulderParams.traced_index():
		_show_live_sliders()


func _sync_sliders() -> void:
	for index in _sliders.size():
		_sliders[index].value = BoulderParams.values[index]


func _rebake() -> void:
	if _busy:
		_rebake_queued = true # (released during a bake: bake again with the newest values after)
		return
	_busy = true
	var entry: Array = SURFACES[_index]
	_title.text = "baking at %d px ... (a few seconds)" % _resolution
	var started := Time.get_ticks_msec()
	_baked = ImageTexture.create_from_image(await _bake(entry[2], entry[3]))
	_apply()
	_title.text = "%s  [%d/%d]   %d px, baked in %.1f s with the sliders' values (X: 1024 / 2048)" % [
			entry[0], _index + 1, SURFACES.size(), _baked.get_width(),
			(Time.get_ticks_msec() - started) / 1000.0]
	_busy = false
	if _rebake_queued:
		_rebake_queued = false
		_rebake()


func _range_of(image: Image) -> Vector2:
	if image == null:
		return Vector2(0.0, 1.0)
	var small := image.duplicate() as Image
	small.resize(96, 96, Image.INTERPOLATE_BILINEAR)
	var low := 1.0
	var high := 0.0
	for y in 96:
		for x in 96:
			var value := small.get_pixel(x, y).r
			low = minf(low, value)
			high = maxf(high, value)
	return Vector2(low, maxf(high, low + 0.001))


func _apply() -> void:
	_sync_settings()
	_update_objects()
	var left := _left.material as ShaderMaterial
	var right := _right.material as ShaderMaterial
	_left.texture = _photo_height if _height_mode else _photo_colour
	var left_mode := 2 if _height_mode else 0
	if _extra > 0 and _extra <= _extra_textures.size():
		_left.texture = _extra_textures[_extra - 1][1]
		left_mode = 0 # (a plain picture of that map)
	_right.texture = _baked
	if _extra > 0 and _extra <= _derived.size():
		_right.texture = _derived[_extra - 1] # (our version of the map the left square shows)
	left.set_shader_parameter(&"tex", _left.texture)
	left.set_shader_parameter(&"mode", left_mode)
	left.set_shader_parameter(&"height_range", _photo_range)
	left.set_shader_parameter(&"zoom", _zoom)
	right.set_shader_parameter(&"zoom", _zoom)
	right.set_shader_parameter(&"tex", _right.texture)
	right.set_shader_parameter(&"mode", 0 if _extra > 0 else (1 if _height_mode else 0))
	right.set_shader_parameter(&"height_range", Vector2(0.0, 1.0))


func _bake(kind: String, surface: String) -> Image:
	var node: Node
	match kind:
		"bark":
			node = BarkBaker.new()
		"ring":
			node = RingBaker.new()
		"chip":
			node = ChipBaker.new()
		"soil":
			node = SoilBaker.new()
		"lump":
			node = LumpBaker.new()
			(node as LumpBaker).resolution = _resolution
		"plate":
			node = PlateBaker.new()
		"wood":
			node = WoodBaker.new()
		_:
			node = GroundBaker.new()
	add_child(node)
	var image: Image
	if kind == "litter":
		image = await (node as GroundBaker).litter_tile()
	elif kind == "lump":
		image = await (node as LumpBaker).bake(surface, _seed)
	else:
		image = await node.bake(surface)
	_derived.clear()
	if kind == "lump" and surface == "rock_boulder_dry":
		# the other maps of our bake, in the photograph's order (roughness, AO, normal, ARM)
		for mode: int in [2, 1, 0, 3]:
			var map_image: Image = await (node as LumpBaker).derive_map(image, mode)
			_derived.append(ImageTexture.create_from_image(map_image))
			if _save_maps != "":
				map_image.save_png("%s_%d.png" % [_save_maps, mode])
	node.queue_free()
	return image


func _show_live_sliders() -> void:
	for i in _sliders.size():
		var live := BoulderParams.is_live(BoulderParams.LIST[i][0])
		_sliders[i].visible = live
		_labels[i].visible = live


## M: the left square shows the photograph's other maps in turn.
## The right square keeps our bake: it has no roughness, occlusion or normal map of its own yet.
func _cycle_map() -> void:
	if _extra_textures.is_empty():
		return
	_extra = (_extra + 1) % (_extra_textures.size() + 1)
	_apply()
	var entry: Array = SURFACES[_index]
	var what := "colour or height (H)"
	if _extra > 0:
		what = String(_extra_textures[_extra - 1][0])
	_title.text = "%s  [%d/%d]   left: the photograph's %s   right: ours (derived)" % [
			entry[0], _index + 1, SURFACES.size(), what]


func _load_extra_maps(photo_name: String) -> void:
	_extra = 0
	_extra_textures.clear()
	for pair: Array in [["roughness", "rough.jpg"], ["ambient occlusion", "ao.jpg"],
			["normal map (OpenGL)", "nor_gl.jpg"], ["packed arm map", "arm.jpg"]]:
		var image := Image.load_from_file(PHOTOS % [photo_name, pair[1]])
		if image != null:
			_extra_textures.append([pair[0], ImageTexture.create_from_image(image)])


## One side of the object view: a viewport with its own world (the same scene, another material).
func _object_view(row: Control) -> Array:
	var container := SubViewportContainer.new()
	container.stretch = true
	container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	container.visible = false
	row.add_child(container)
	var port := SubViewport.new()
	port.own_world_3d = true
	port.msaa_3d = Viewport.MSAA_4X
	container.add_child(port)
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(40.0, 40.0)
	ground.mesh = plane
	var sand := StandardMaterial3D.new()
	sand.albedo_color = Color(0.8, 0.72, 0.52)
	ground.material_override = sand
	port.add_child(ground)
	var instance := MeshInstance3D.new()
	port.add_child(instance)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-35.0, -40.0, 0.0)
	sun.shadow_enabled = true
	port.add_child(sun)
	var camera := Camera3D.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.5, 0.7, 0.95)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.6, 0.65, 0.75)
	camera.environment = environment
	camera.fov = 40.0
	port.add_child(camera)
	return [container, instance, camera]


## O: shows the surface as an object when it has one (the rock of that slot, a trunk of that bark),
## the photograph's version left and ours right; the other surfaces keep the flat squares.
func _update_objects() -> void:
	var photo_name: String = SURFACES[_index][1]
	var has_object := ROCK_SLOTS.has(photo_name) or BARK_KINDS.has(photo_name)
	var shown := _object_mode and has_object
	_left.visible = not shown
	_right.visible = not shown
	for view: Array in _views:
		(view[0] as Control).visible = shown
	if not shown:
		return
	_object_busy = true
	if ROCK_SLOTS.has(photo_name):
		_show_rock(ROCK_SLOTS[photo_name])
	else:
		await _show_tree(BARK_KINDS[photo_name])
	_orbit_cameras()
	_object_busy = false


func _show_rock(slot: int) -> void:
	FloraMeshes.detailed = true
	WorldWind.set_realism(1.0)
	if _atlas == null:
		_atlas = Image.load_from_file("res://assets/textures/rock/rock_atlas.png")
	var size := RockBaker.SIZE
	var photo := _atlas.get_region(Rect2i((slot % 3) * size, (slot / 3) * size, size, size))
	var ours: Image = _baked.get_image() if _baked != null else photo
	var variants := FloraMeshes.variant_count(FloraMeshes.Kind.ROCK)
	var mesh := FloraMeshes.mesh(FloraMeshes.Kind.ROCK, _variant % variants, true)
	_target = Vector3(0.0, 0.5, 0.0)
	for side in 2:
		var material := FloraMeshes.material().duplicate() as ShaderMaterial
		material.set_shader_parameter(&"rock_photo", _rock_array(photo if side == 0 else ours))
		material.set_shader_parameter(&"rock_force", float(slot))
		material.set_shader_parameter(&"rock_pom", 1.0 if _pom else 0.0)
		material.set_shader_parameter(&"rock_pom_depth", _pom_depth)
		_put_object(side, mesh, material, Vector3.ONE * 1.4)


## The six slots of the rock array all hold this picture (rock_force picks the slot).
func _rock_array(image: Image) -> Texture2DArray:
	var layer := image.duplicate() as Image
	layer.convert(Image.FORMAT_RGBA8)
	layer.generate_mipmaps()
	var layers: Array[Image] = []
	for slot in 6:
		layers.append(layer)
	var array := Texture2DArray.new()
	array.create_from_images(layers)
	return array


func _show_tree(kind: int) -> void:
	FloraMeshes.detailed = true
	WorldWind.set_realism(1.0)
	var grooves := OS.has_environment("PLANET_BARK_GROOVES")
	if _bark_array == null or grooves != _bark_grooves:
		_title.text = "baking the bark of every tree ... (a few seconds)"
		var baker := BarkBaker.new()
		add_child(baker)
		_bark_array = await baker.make_array(true)
		_bark_grooves = grooves
		baker.queue_free()
		_title.text = "%s  [%d/%d]   left: photograph   right: procedural" % [
				SURFACES[_index][0], _index + 1, SURFACES.size()]
	if _registry == null:
		_registry = SpeciesRegistry.new(1337, 60)
		for one in _registry.species:
			if one.is_tree():
				_trees.append(one)
	var chosen: PlantSpecies = _trees[_variant % _trees.size()]
	var mesh := _registry.mesh(chosen.id, 0, true, 0)
	_target = Vector3(0.0, 1.0, 0.0)
	for side in 2:
		var material := FloraMeshes.material().duplicate() as ShaderMaterial
		material.set_shader_parameter(&"bark_style_force", Vector2(0.3, 0.4)) # (same lichen both)
		material.set_shader_parameter(&"bark_force", float(kind))
		if side == 1:
			material.set_shader_parameter(&"bark_photo", _bark_array)
			material.set_shader_parameter(&"tall_slot", 1.0) # (the baked cedar is a square metre)
			material.set_shader_parameter(&"tall_palm", 1.0)
		_put_object(side, mesh, material, Vector3.ONE)


func _put_object(side: int, mesh: Mesh, material: Material, object_scale: Vector3) -> void:
	var instance := _views[side][1] as MeshInstance3D
	instance.mesh = mesh
	instance.material_override = material
	instance.scale = object_scale


func _orbit_cameras() -> void:
	for view: Array in _views:
		var camera := view[2] as Camera3D
		var offset := Vector3(sin(_orbit.x) * cos(_orbit.y), sin(_orbit.y), cos(_orbit.x) * cos(_orbit.y))
		camera.look_at_from_position(_target + offset * _orbit.z, _target)


## Dragging and the wheel turn and zoom the camera. _input, not _unhandled_input: the viewports and
## containers of the layout take mouse motion before it gets there. Not over a slider or a button.
func _input(event: InputEvent) -> void:
	if not _object_mode:
		return
	var hovered := get_viewport().gui_get_hovered_control()
	if hovered is Range or hovered is BaseButton or (hovered != null and _panel.is_ancestor_of(hovered)):
		return
	var motion := event as InputEventMouseMotion
	_dragging = motion != null and (motion.button_mask & MOUSE_BUTTON_MASK_LEFT) != 0
	if motion != null and (motion.button_mask & MOUSE_BUTTON_MASK_LEFT) != 0:
		_orbit.x -= motion.relative.x * 0.01
		_orbit.y = clampf(_orbit.y + motion.relative.y * 0.01, 0.05, 1.4)
		_orbit_cameras()
	var button := event as InputEventMouseButton
	if button != null and button.pressed:
		if button.button_index == MOUSE_BUTTON_WHEEL_UP:
			_orbit.z = maxf(_orbit.z * 0.9, 0.8)
			_orbit_cameras()
		elif button.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_orbit.z = minf(_orbit.z * 1.1, 12.0)
			_orbit_cameras()


## The turntable: a slow turn round the object (T stops it, a drag takes over while the button is down).
func _process(delta: float) -> void:
	if _object_mode and _turn and not _dragging and not _object_busy and _shot == "":
		_orbit.x += delta * 0.35
		_orbit_cameras()


## The settings row: the lump bake's resolution (it rebakes), parallax, the turntable and the relief depth.
## No control takes the keyboard focus, so the arrow keys still change the surface.
func _build_settings() -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override(&"separation", 14)
	var res_label := Label.new()
	res_label.text = "bake resolution (px)"
	row.add_child(res_label)
	_res_option = OptionButton.new()
	_res_option.focus_mode = Control.FOCUS_NONE
	for value in RESOLUTIONS:
		_res_option.add_item(str(value), value)
	_res_option.item_selected.connect(func(index: int) -> void:
		_resolution = RESOLUTIONS[index]
		_rebake())
	row.add_child(_res_option)
	var seed_label := Label.new()
	seed_label.text = "variation seed"
	row.add_child(seed_label)
	_seed_box = SpinBox.new()
	_seed_box.min_value = 1.0
	_seed_box.max_value = 999.0
	_seed_box.step = 1.0
	_seed_box.get_line_edit().focus_mode = Control.FOCUS_NONE
	_seed_box.value_changed.connect(func(value: float) -> void:
		_seed = value
		_rebake())
	row.add_child(_seed_box)
	_pom_check = CheckBox.new()
	_pom_check.text = "parallax + self-shadow (rocks)"
	_pom_check.focus_mode = Control.FOCUS_NONE
	_pom_check.toggled.connect(func(on: bool) -> void:
		_pom = on
		_update_objects())
	row.add_child(_pom_check)
	_depth_label = Label.new()
	row.add_child(_depth_label)
	_depth_slider = HSlider.new()
	_depth_slider.focus_mode = Control.FOCUS_NONE
	_depth_slider.custom_minimum_size = Vector2(140.0, 0.0)
	_depth_slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_depth_slider.min_value = 5.0
	_depth_slider.max_value = 300.0
	_depth_slider.step = 1.0
	_depth_slider.value_changed.connect(func(value: float) -> void:
		_depth_label.text = "relief depth %d mm" % int(value))
	_depth_slider.drag_ended.connect(func(_changed: bool) -> void:
		_pom_depth = _depth_slider.value / 1000.0
		_update_objects())
	row.add_child(_depth_slider)
	_turn_check = CheckBox.new()
	_turn_check.text = "turntable"
	_turn_check.focus_mode = Control.FOCUS_NONE
	_turn_check.toggled.connect(func(on: bool) -> void: _turn = on)
	row.add_child(_turn_check)
	return row


func _sync_settings() -> void:
	if _res_option == null:
		return
	_res_option.select(maxi(RESOLUTIONS.find(_resolution), 0))
	_res_option.disabled = SURFACES[_index][2] != "lump" # (only the lump rocks have a resolution setting)
	_seed_box.editable = SURFACES[_index][2] == "lump"
	_seed_box.set_value_no_signal(_seed)
	_pom_check.set_pressed_no_signal(_pom)
	_turn_check.set_pressed_no_signal(_turn)
	_depth_slider.set_value_no_signal(_pom_depth * 1000.0)
	_depth_label.text = "relief depth %d mm" % int(_pom_depth * 1000.0)
