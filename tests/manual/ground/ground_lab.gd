extends Node
## The ground lab: a flat patch of the real ground shader (planet_ground), with the real small stones (PlanetTurf's gravel) and the
## sun of your choice. Without `out=` it stays open with an orbit camera (drag with the mouse to circle the focus, wheel to zoom,
## middle drag to move the focus) and a panel of sliders for everything below; with `out=` it saves one picture and quits, so a look
## can be reproduced from the command line and compared with a photograph (put the photo in E:/Temp/claude/refs/, outside the
## project, and pass it as `ref=`: it is placed beside the render).
##   godot --path . res://tests/manual/ground/ground_lab.tscn -- out=E:/path/picture.png [options]
##     soil=laterite|brown|sand|black|grey|forest   the soil (colour, iron, organic matter, stones, depth, paleness of the rock)
##     view=low|eye|down|photo|far|top|macro   the camera: 25 cm above the ground, standing looking down ahead (the default), nearly
##       straight down, standing looking out, from above, a hand's breadth
##     detail=0..3   the ground detail (the graphics setting)   chips=0|1   the real stones   sun=ELEVATION,AZIMUTH (degrees)
##     stones=0..1   how stony   seed=N   which patch of ground   ref=PATH   a photograph beside the render   size=WIDTHxHEIGHT
##     iron=0..1 organic=0..1 pale=0..1 depth=0..1   the soil's numbers   spacing=M   the grid of the stones   density=X   their odds
##     tilt=DEGREES   leans the patch over (70: a cliff face)
##     strength=0..1   the ground shader's detail strength   fov=DEGREES
## Prints GROUND_LAB with the numbers of the run.

const SOILS := ["laterite", "brown", "sand", "black", "grey", "forest"]

var _frames := 0
var _out := "ground_lab.png"
var _ref := ""
var _options := {}
var _camera: Camera3D
var _live := false
var _focus := Vector3(0.0, 0.0, -0.5)
var _yaw := 0.0
var _pitch := 0.9
var _distance := 2.2

## What the sliders change.
var _soil_name := "laterite"
var _values := {}
var _sliders := {}
var _patch_node: MeshInstance3D
var _chip_nodes: Array[Node] = []
var _chip_root := Node3D.new() # (the stones lean over with the patch)
var _sun: DirectionalLight3D
var _chips_on := true
var _rebuild_wanted := false
var _chips_wanted := false


func _ready() -> void:
	var root := get_tree().root
	for arg in OS.get_cmdline_user_args():
		var parts := arg.split("=", true, 1)
		if parts.size() == 2:
			_options[parts[0]] = parts[1]
	_live = not _options.has("out")
	_out = _options.get("out", _out)
	_ref = _options.get("ref", "")
	_soil_name = _options.get("soil", "laterite")
	var preset := _soil(_soil_name)
	var sun_parts: PackedStringArray = String(_options.get("sun", "38,215")).split(",")
	_values = {
		"detail": float(_options.get("detail", "1")), "seed": float(_options.get("seed", "1")),
		"sun_elevation": float(sun_parts[0]), "sun_azimuth": float(sun_parts[1]) if sun_parts.size() > 1 else 215.0,
		"stones": float(_options.get("stones", str(preset["stones"]))), "iron": float(_options.get("iron", str(preset["iron"]))),
		"organic": float(_options.get("organic", str(preset["organic"]))), "pale": float(_options.get("pale", str(preset["pale"]))),
		"depth": float(_options.get("depth", str(preset["depth"]))), "spacing": float(_options.get("spacing", "0.12")),
		"density": float(_options.get("density", "1.0")), "strength": float(_options.get("strength", "0.8")),
		"fov": float(_options.get("fov", "55")), "tilt": float(_options.get("tilt", "0")),
		"mosaic_strength": 0.9, "mosaic_big_per_m": 15.0, "mosaic_mid_per_m": 42.0, "mosaic_small_per_m": 150.0, "mosaic_big_cover": 0.13,
		"mosaic_mid_cover": 0.42, "mosaic_angular": 0.8, "mosaic_gap": 0.75, "mosaic_tilt": 1.4, "mosaic_tone": 0.7, "mosaic_pebbles": 0.11,
		"mosaic_seed": 1.0, "mosaic_desat": 0.6, "mosaic_grain": 0.85,
		"cliff_row_height": 0.45, "cliff_col_width": 1.1, "cliff_warp": 0.4, "cliff_lip": 0.09, "cliff_terraces": 0.5, "cliff_cracks": 0.55,
		"cliff_sand": 0.5, "cliff_tone": 0.6, "cliff_relief": 1.0, "cliff_seed": 3.0, "cliff_hue": 0.5,
	}
	_chips_on = _options.get("chips", "1") != "0"
	var size_parts: PackedStringArray = String(_options.get("size", "1600x900")).split("x")
	if not _live:
		root.size = Vector2i(int(size_parts[0]), int(size_parts[1]))

	# the globals the planet sets
	RenderingServer.global_shader_parameter_set(&"realism", 1.0)
	RenderingServer.global_shader_parameter_set(&"snow_cover", 0.0)
	RenderingServer.global_shader_parameter_set(&"anchor_from_world", Projection.IDENTITY)
	RenderingServer.global_shader_parameter_set(&"anchor_wrap", Vector3.ZERO)
	RenderingServer.global_shader_parameter_set(&"anchor_up", Vector3.UP)
	RenderingServer.global_shader_parameter_set(&"anchor_phase", 0.0)
	RenderingServer.global_shader_parameter_set(&"cloud_centre", Vector3(0.0, -20000.0, 0.0))

	add_child(_chip_root)
	_sun = DirectionalLight3D.new()
	_sun.shadow_enabled = true
	_sun.directional_shadow_max_distance = 30.0
	add_child(_sun)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color(0.62, 0.74, 0.9)
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color(0.55, 0.62, 0.75)
	environment.environment.ambient_light_energy = 0.7
	add_child(environment)

	_camera = Camera3D.new()
	add_child(_camera)
	_camera.fov = _values["fov"]
	_set_view(_options.get("view", "eye"))
	_apply_sun()
	for key: String in _values:
		if key.begins_with("cliff_") or key.begins_with("mosaic_"):
			if _options.has(key):
				_values[key] = float(_options[key]) # (the command line sets them too: cliff_lip=0.12)
			PlanetTile.ground_material().set_shader_parameter(key, _values[key])
	_rebuild()
	if _live:
		_build_panel()
	print("GROUND_LAB soil=%s view=%s %s chips=%s" % [_soil_name, _options.get("view", "eye"), _values, _chips_on])


## The camera of a named view, as the orbit's focus, yaw, pitch and distance.
func _set_view(view: String) -> void:
	_yaw = 0.0
	match view:
		"low":
			_focus = Vector3(0.0, 0.0, -2.0)
			_pitch = 0.07
			_distance = 3.8
		"top":
			_focus = Vector3.ZERO
			_pitch = 1.4
			_distance = 2.4
		"macro":
			_focus = Vector3.ZERO
			_pitch = 0.75
			_distance = 0.56
		"photo": # as close as a photograph taken standing over the ground: about 70 cm across
			_focus = Vector3.ZERO
			_pitch = 1.54
			_distance = 0.7
		"down":
			_focus = Vector3.ZERO
			_pitch = 1.34
			_distance = 1.5
		"far":
			_focus = Vector3(0.0, 0.0, -2.2)
			_pitch = 0.43
			_distance = 3.9
		_: # eye: standing, looking down at the ground a couple of metres ahead (no horizon)
			_focus = Vector3(0.0, 0.0, -0.5)
			_pitch = 0.9
			_distance = 2.2
	_place_camera()


func _apply_sun() -> void:
	var elevation := deg_to_rad(float(_values["sun_elevation"]))
	var azimuth := deg_to_rad(float(_values["sun_azimuth"]))
	var toward_sun := Vector3(cos(elevation) * sin(azimuth), sin(elevation), cos(elevation) * cos(azimuth))
	RenderingServer.global_shader_parameter_set(&"cloud_sun_world", toward_sun)
	_sun.look_at_from_position(Vector3.ZERO, -toward_sun)


## The ground and the stones made again from the values.
func _rebuild() -> void:
	RenderingServer.global_shader_parameter_set(&"ground_detail", float(_values["detail"]))
	if _patch_node != null:
		_patch_node.queue_free()
	_patch_node = _patch(_preset(), float(_values["stones"]), int(_values["seed"]))
	add_child(_patch_node)
	var tilt := deg_to_rad(float(_values["tilt"])) # (the patch leant over: a slope, a cliff face at 70 or more)
	_patch_node.basis = Basis(Vector3.RIGHT, -tilt)
	_patch_node.position = Vector3(0.0, 0.0, -2.0) - _patch_node.basis * Vector3(0.0, 0.0, -2.0)
	PlanetTile.ground_material().set_shader_parameter(&"detail_strength", float(_values["strength"]))
	_rebuild_chips()
	_chip_root.basis = _patch_node.basis
	_chip_root.position = _patch_node.position


func _rebuild_chips() -> void:
	for node in _chip_nodes:
		node.queue_free()
	_chip_nodes.clear()
	if _chips_on:
		_scatter_chips(int(_values["seed"]), float(_values["stones"]))


## The soil of the name with the sliders' numbers over it.
func _preset() -> Dictionary:
	var preset := _soil(_soil_name)
	for key in ["iron", "organic", "pale", "depth"]:
		preset[key] = _values[key]
	return preset


## A soil: the colour of the ground, its iron, its organic matter, how stony, how deep, and the rock it came from.
func _soil(name: String) -> Dictionary:
	match name:
		"brown":
			return {"colour": Color(0.38, 0.27, 0.17), "iron": 0.15, "organic": 0.55, "stones": 0.5, "depth": 0.6, "pale": 0.4}
		"sand":
			return {"colour": Color(0.78, 0.68, 0.46), "iron": 0.1, "organic": 0.3, "stones": 0.25, "depth": 0.5, "pale": 0.6}
		"black":
			return {"colour": Color(0.17, 0.12, 0.09), "iron": 0.0, "organic": 0.9, "stones": 0.2, "depth": 0.9, "pale": 0.3}
		"grey":
			return {"colour": Color(0.46, 0.44, 0.4), "iron": 0.0, "organic": 0.45, "stones": 0.8, "depth": 0.3, "pale": 0.7}
		"forest":
			return {"colour": Color(0.22, 0.16, 0.1), "iron": 0.05, "organic": 0.8, "stones": 0.3, "depth": 0.8, "pale": 0.4}
		_:
			return {"colour": Color(0.55, 0.27, 0.17), "iron": 0.9, "organic": 0.45, "stones": 0.7, "depth": 0.4, "pale": 0.35}


## The patch: 12 x 12 m, 96 quads, every vertex with the soil's numbers (what PlanetTile and the crust give the real ground).
func _patch(preset: Dictionary, stones: float, seed_value: int) -> MeshInstance3D:
	var cells := 96
	var size := 12.0
	var colour: Color = preset["colour"]
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var colours := PackedColorArray()
	var smooth := PackedByteArray()
	var geology := PackedByteArray()
	var lie := PackedByteArray()
	var indices := PackedInt32Array()
	var noise := FastNoiseLite.new()
	noise.seed = seed_value
	noise.frequency = 0.08
	for row in cells + 1:
		for column in cells + 1:
			var x := (float(column) / cells - 0.5) * size
			var z := (float(row) / cells - 0.5) * size - 2.0
			vertices.append(Vector3(x, 0.025 * noise.get_noise_2d(x, z), z)) # (a very gentle swell)
			normals.append(Vector3.UP)
			colours.append(Color(colour.r, colour.g, colour.b, preset["iron"]))
			smooth.append_array(PackedByteArray([int(colour.r * 255), int(colour.g * 255), int(colour.b * 255), int(float(preset["organic"]) * 255)]))
			geology.append_array(PackedByteArray([int(0.6 * 255), int(0.5 * 255), int(float(preset["pale"]) * 255), int(0.3 * 255)]))
			lie.append_array(PackedByteArray([int(stones * 255), int(float(preset["depth"]) * 255), 0, 0]))
	for row in cells:
		for column in cells:
			var i := row * (cells + 1) + column
			indices.append_array(PackedInt32Array([i, i + 1, i + cells + 1, i + 1, i + cells + 2, i + cells + 1]))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colours
	arrays[Mesh.ARRAY_CUSTOM0] = smooth
	arrays[Mesh.ARRAY_CUSTOM1] = geology
	arrays[Mesh.ARRAY_CUSTOM2] = lie
	arrays[Mesh.ARRAY_INDEX] = indices
	var flags := (Mesh.ARRAY_CUSTOM_RGBA8_UNORM << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT) | (Mesh.ARRAY_CUSTOM_RGBA8_UNORM << Mesh.ARRAY_FORMAT_CUSTOM1_SHIFT) \
			| (Mesh.ARRAY_CUSTOM_RGBA8_UNORM << Mesh.ARRAY_FORMAT_CUSTOM2_SHIFT)
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {}, flags)
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = PlanetTile.ground_material()
	return instance


## The real small stones on the patch (the native placement the planet uses), with the same chips and the same shadows.
func _scatter_chips(seed_value: int, stones: float) -> void:
	if not ClassDB.class_exists(&"PlanetScatterNative"):
		print("GROUND_LAB no native library: no stones")
		return
	var native: Object = ClassDB.instantiate(&"PlanetScatterNative")
	var cells := 12
	var side := cells + 3
	var positions := PackedVector3Array()
	var field := PackedFloat32Array()
	for row in side:
		for column in side:
			positions.append(Vector3((float(column - 1) / cells - 0.5) * 12.0, 0.0, (float(row - 1) / cells - 0.5) * 12.0 - 2.0))
			field.append(1.0 - stones) # (the more stones, the less grass: the more chips)
	var buffers: Array = native.call(&"gravel_chunk", positions, field, cells, 12.0, 0.0, 0.0, 12.0, 12.0, float(_values["spacing"]),
			float(_values["density"]), seed_value, FloraMeshes.CHIP_VARIANTS)
	for variant in buffers.size():
		var buffer: PackedFloat32Array = buffers[variant]
		if buffer.is_empty():
			continue
		var multi := MultiMesh.new()
		multi.transform_format = MultiMesh.TRANSFORM_3D
		multi.use_colors = true
		multi.mesh = FloraMeshes.chip(variant)
		multi.instance_count = buffer.size() / 16
		multi.buffer = buffer
		var instance := MultiMeshInstance3D.new()
		instance.multimesh = multi
		instance.material_override = FloraMeshes.material()
		_chip_root.add_child(instance)
		_chip_nodes.append(instance)
	print("GROUND_LAB stones ", ", ".join(Array(buffers.map(func(buffer: PackedFloat32Array) -> int: return buffer.size() / 16))))


## The panel: a slider for each number, a choice of soil and the stones on or off. A change that makes the ground again waits until the
## mouse button is let go (the patch takes a moment).
func _build_panel() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var panel := PanelContainer.new()
	panel.position = Vector2(10.0, 10.0)
	layer.add_child(panel)
	var column := VBoxContainer.new()
	column.custom_minimum_size = Vector2(340.0, 0.0)
	panel.add_child(column)
	var soil := OptionButton.new()
	for name in SOILS:
		soil.add_item(name)
	soil.select(SOILS.find(_soil_name))
	soil.item_selected.connect(func(index: int) -> void:
		_soil_name = SOILS[index]
		var preset := _soil(_soil_name)
		for key in ["iron", "organic", "pale", "depth", "stones"]:
			_values[key] = preset[key]
			_sync(key)
		_rebuild())
	column.add_child(soil)
	var chips := CheckBox.new()
	chips.text = "real stones"
	chips.button_pressed = _chips_on
	chips.toggled.connect(func(on: bool) -> void:
		_chips_on = on
		_rebuild_chips())
	column.add_child(chips)
	var procedural := CheckBox.new()
	procedural.text = "cliff computed in the shader (off: the baked pictures)"
	procedural.button_pressed = true
	procedural.toggled.connect(func(on: bool) -> void:
		PlanetTile.ground_material().set_shader_parameter(&"cliff_procedural", on))
	column.add_child(procedural)
	# (key, label, min, max, step, what it remakes: 0 nothing, 1 the sun, 2 the stones, 3 the ground)
	var rows := [
		["sun_elevation", "sun height (deg)", 2.0, 88.0, 1.0, 1], ["sun_azimuth", "sun direction (deg)", 0.0, 360.0, 1.0, 1],
		["detail", "ground detail (0-3)", 0.0, 3.0, 1.0, 3], ["strength", "detail strength", 0.0, 1.0, 0.05, 3],
		["stones", "how stony", 0.0, 1.0, 0.05, 3], ["iron", "iron (red soil)", 0.0, 1.0, 0.05, 3],
		["organic", "organic matter", 0.0, 1.0, 0.05, 3], ["pale", "pale rock", 0.0, 1.0, 0.05, 3], ["depth", "soil depth", 0.0, 1.0, 0.05, 3],
		["spacing", "stone grid (m)", 0.04, 0.4, 0.01, 2], ["density", "stone odds", 0.0, 3.0, 0.1, 2],
		["tilt", "lean the patch (-90 = cliff)", -90.0, 90.0, 1.0, 3], ["seed", "patch (seed)", 1.0, 99.0, 1.0, 3], ["fov", "field of view", 20.0, 100.0, 1.0, 0],
		["mosaic_strength", "mosaic: strength", 0.0, 1.0, 0.05, 4], ["mosaic_big_per_m", "mosaic: large per m", 2.0, 40.0, 0.5, 4],
		["mosaic_mid_per_m", "mosaic: medium per m", 8.0, 100.0, 1.0, 4], ["mosaic_small_per_m", "mosaic: small per m", 30.0, 300.0, 5.0, 4],
		["mosaic_big_cover", "mosaic: large cover", 0.0, 1.0, 0.05, 4], ["mosaic_mid_cover", "mosaic: medium cover", 0.0, 1.0, 0.05, 4],
		["mosaic_angular", "mosaic: sharpness", 0.0, 1.0, 0.05, 4], ["mosaic_gap", "mosaic: dark gaps", 0.0, 1.0, 0.05, 4],
		["mosaic_tilt", "mosaic: plate lean", 0.0, 2.0, 0.05, 4], ["mosaic_tone", "mosaic: tone spread", 0.0, 1.0, 0.05, 4],
		["mosaic_pebbles", "mosaic: pebbles", 0.0, 0.5, 0.01, 4], ["mosaic_desat", "mosaic: desaturation", 0.0, 1.0, 0.05, 4], ["mosaic_grain", "mosaic: fine grain", 0.0, 1.0, 0.05, 4], ["mosaic_seed", "mosaic: layout (seed)", 1.0, 99.0, 1.0, 4],
		["cliff_row_height", "cliff: bed thickness (m)", 0.15, 1.5, 0.01, 4], ["cliff_col_width", "cliff: slab width (m)", 0.3, 3.0, 0.05, 4],
		["cliff_warp", "cliff: edge wander (m)", 0.0, 1.0, 0.01, 4], ["cliff_lip", "cliff: lip width (m)", 0.01, 0.3, 0.005, 4],
		["cliff_terraces", "cliff: terracing", 0.0, 1.0, 0.05, 4], ["cliff_cracks", "cliff: cracked slabs", 0.0, 1.0, 0.05, 4],
		["cliff_sand", "cliff: sand shelves", 0.0, 1.0, 0.05, 4], ["cliff_tone", "cliff: tone patches", 0.0, 1.0, 0.05, 4],
		["cliff_relief", "cliff: relief", 0.0, 4.0, 0.1, 4], ["cliff_seed", "cliff: layout (seed)", 1.0, 99.0, 1.0, 4],
		["cliff_hue", "cliff: sandstone hue", 0.0, 1.0, 0.05, 4],
	]
	for row: Array in rows:
		var line := HBoxContainer.new()
		var label := Label.new()
		label.text = row[1]
		label.custom_minimum_size = Vector2(150.0, 0.0)
		line.add_child(label)
		var slider := HSlider.new()
		slider.min_value = row[2]
		slider.max_value = row[3]
		slider.step = row[4]
		slider.value = _values[row[0]]
		slider.custom_minimum_size = Vector2(120.0, 0.0)
		slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		line.add_child(slider)
		var number := Label.new()
		number.text = "%.2f" % slider.value
		number.custom_minimum_size = Vector2(44.0, 0.0)
		line.add_child(number)
		column.add_child(line)
		_sliders[row[0]] = [slider, number]
		var key: String = row[0]
		var remakes: int = row[5]
		slider.value_changed.connect(func(value: float) -> void:
			_values[key] = value
			number.text = "%.2f" % value
			if key == "fov":
				_camera.fov = value
			elif remakes == 1:
				_apply_sun()
			elif remakes == 2:
				_chips_wanted = true
			elif remakes == 3:
				_rebuild_wanted = true
			elif remakes == 4:
				PlanetTile.ground_material().set_shader_parameter(key, value))
	var hint := Label.new()
	hint.text = "drag: orbit   wheel: zoom   middle drag: move focus"
	column.add_child(hint)


## Move a slider to the value without remaking anything on its account.
func _sync(key: String) -> void:
	if _sliders.has(key):
		var pair: Array = _sliders[key]
		(pair[0] as HSlider).set_value_no_signal(_values[key])
		(pair[1] as Label).text = "%.2f" % _values[key]


func _unhandled_input(event: InputEvent) -> void:
	if not _live or _camera == null:
		return
	if event is InputEventMouseMotion:
		var motion := event as InputEventMouseMotion
		if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) or Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
			_yaw -= motion.relative.x * 0.005
			_pitch = clampf(_pitch + motion.relative.y * 0.005, 0.05, 1.55)
		elif Input.is_mouse_button_pressed(MOUSE_BUTTON_MIDDLE):
			var side := Vector3(cos(_yaw), 0.0, -sin(_yaw))
			var ahead := Vector3(-sin(_yaw), 0.0, -cos(_yaw))
			_focus += (-side * motion.relative.x + ahead * motion.relative.y) * 0.002 * _distance
	elif event is InputEventMouseButton and event.is_pressed():
		var button := event as InputEventMouseButton
		if button.button_index == MOUSE_BUTTON_WHEEL_UP:
			_distance = maxf(_distance * 0.9, 0.25)
		elif button.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_distance = minf(_distance * 1.1, 14.0)


## The orbit camera: always looking at `_focus` on the ground, `_distance` away, `_pitch` above the ground, `_yaw` round it.
func _place_camera() -> void:
	var offset := Vector3(sin(_yaw) * cos(_pitch), sin(_pitch), cos(_yaw) * cos(_pitch)) * _distance
	_camera.look_at_from_position(_focus + offset, _focus)


func _process(_delta: float) -> void:
	var root := get_tree().root
	if _live:
		_place_camera()
		# the ground and the stones are made again once the mouse button is up (a slider being dragged changes many times a second)
		if not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
			if _rebuild_wanted:
				_rebuild_wanted = false
				_chips_wanted = false
				_rebuild()
			elif _chips_wanted:
				_chips_wanted = false
				_rebuild_chips()
		return
	_frames += 1
	if _frames == 40:
		var image := root.get_texture().get_image()
		if _ref != "" and FileAccess.file_exists(_ref):
			var reference := Image.load_from_file(_ref)
			if reference != null:
				reference.convert(Image.FORMAT_RGB8)
				image.convert(Image.FORMAT_RGB8)
				var scale := float(image.get_height()) / float(reference.get_height())
				reference.resize(int(reference.get_width() * scale), image.get_height(), Image.INTERPOLATE_LANCZOS)
				var both := Image.create(image.get_width() + reference.get_width(), image.get_height(), false, Image.FORMAT_RGB8)
				both.blit_rect(image, Rect2i(Vector2i.ZERO, image.get_size()), Vector2i.ZERO)
				both.blit_rect(reference, Rect2i(Vector2i.ZERO, reference.get_size()), Vector2i(image.get_width(), 0))
				image = both
		image.save_png(_out)
		get_tree().quit()
