extends Control
## The photograph and the procedural version of one surface, as two plain squares side by side
## (no object, no projection, same size). Run it (F6) and use:
##   Left / Right  the previous / next surface      H  colour <-> height lit from the upper left
##   G  the grooved oak, maple, cedar (PLANET_BARK_GROOVES)      Z  zoom 1x / 2x / 4x      Esc  quit
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
var _shot := ""
var _save_bake := ""
var _panel: PanelContainer
var _sliders: Array[HSlider] = []


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var back := ColorRect.new()
	back.color = Color(0.12, 0.12, 0.13)
	back.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(back)
	var column := VBoxContainer.new()
	column.set_anchors_preset(Control.PRESET_FULL_RECT)
	column.add_theme_constant_override(&"separation", 6)
	add_child(column)
	_title = Label.new()
	_title.add_theme_font_size_override(&"font_size", 20)
	column.add_child(_title)
	var row := HBoxContainer.new()
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override(&"separation", 10)
	column.add_child(row)
	_left = _square(row)
	_right = _square(row)
	_build_panel()
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--surface="):
			_index = clampi(int(argument.get_slice("=", 1)), 0, SURFACES.size() - 1)
		elif argument.begins_with("--shot="):
			_shot = argument.substr(7)
		elif argument.begins_with("--save-bake="):
			_save_bake = argument.substr(12)
		elif argument == "--height":
			_height_mode = true
		elif argument.begins_with("--zoom="):
			_zoom = float(argument.get_slice("=", 1))
	await _show()
	if _shot != "":
		await get_tree().create_timer(0.5).timeout
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
	if key == null or not key.pressed or _busy:
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
	_title.text += "   (arrows: surface, H: colour or height, G: grooves %s)" % grooves
	var colour := Image.load_from_file(PHOTOS % [entry[1], "diff.jpg"])
	var height := Image.load_from_file(PHOTOS % [entry[1], "disp.png"])
	_photo_colour = ImageTexture.create_from_image(colour) if colour != null else null
	_photo_height = ImageTexture.create_from_image(height) if height != null else null
	_photo_range = _range_of(height)
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
	hint.text = "boulder numbers (R: reset, C: copy)"
	box.add_child(hint)
	for index in BoulderParams.LIST.size():
		var entry: Array = BoulderParams.LIST[index]
		var label := Label.new()
		label.text = "%s  %.3f" % [entry[0], BoulderParams.values[index]]
		label.add_theme_font_size_override(&"font_size", 12)
		box.add_child(label)
		var slider := HSlider.new()
		slider.min_value = entry[2]
		slider.max_value = entry[3]
		slider.step = (float(entry[3]) - float(entry[2])) / 200.0
		slider.value = BoulderParams.values[index]
		slider.value_changed.connect(_on_slider.bind(index, label))
		slider.drag_ended.connect(func(_changed: bool) -> void: _rebake())
		box.add_child(slider)
		_sliders.append(slider)
	_panel.visible = false


func _on_slider(value: float, index: int, label: Label) -> void:
	BoulderParams.values[index] = value
	label.text = "%s  %.3f" % [BoulderParams.LIST[index][0], value]


func _sync_sliders() -> void:
	for index in _sliders.size():
		_sliders[index].value = BoulderParams.values[index]


func _rebake() -> void:
	if _busy:
		return
	_busy = true
	var entry: Array = SURFACES[_index]
	_baked = ImageTexture.create_from_image(await _bake(entry[2], entry[3]))
	_apply()
	_busy = false


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
	var left := _left.material as ShaderMaterial
	var right := _right.material as ShaderMaterial
	_left.texture = _photo_height if _height_mode else _photo_colour
	_right.texture = _baked
	left.set_shader_parameter(&"tex", _left.texture)
	left.set_shader_parameter(&"mode", 2 if _height_mode else 0)
	left.set_shader_parameter(&"height_range", _photo_range)
	left.set_shader_parameter(&"zoom", _zoom)
	right.set_shader_parameter(&"zoom", _zoom)
	right.set_shader_parameter(&"tex", _right.texture)
	right.set_shader_parameter(&"mode", 1 if _height_mode else 0)
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
	else:
		image = await node.bake(surface)
	node.queue_free()
	return image
