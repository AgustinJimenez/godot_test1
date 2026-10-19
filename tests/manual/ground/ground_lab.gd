extends Node
## The ground lab: a flat patch of the real ground shader (planet_ground), with the real small stones (PlanetTurf's gravel) and the
## sun of your choice, seen from fixed cameras, saved as a picture. To make a look reproducible and to compare it with a photograph
## (put the photo in E:/Temp/claude/refs/, outside the project, and pass it as `ref=`: it is placed beside the render).
##   godot --path . res://tests/manual/ground/ground_lab.tscn -- out=E:/path/picture.png [options]
##     soil=laterite|brown|sand|black|grey|forest   the soil (what the crust gives: colour, iron, organic matter, stones, depth)
##     view=low|eye|down|far|top|macro   the camera: 25 cm above the ground looking along it, standing looking down ahead (the default), nearly straight down, standing looking out, from above, a hand's breadth
##     detail=0..3   the ground detail (the graphics setting)   chips=0|1   the real stones   sun=ELEVATION,AZIMUTH (degrees)
##   (with no `out=` the lab stays open: drag with the mouse to circle the focus, wheel zooms, middle drag moves the focus)
##     stones=0..1   how stony   seed=N   which patch of ground   ref=PATH   a photograph beside the render   size=WIDTHxHEIGHT
## Prints GROUND_LAB with the numbers of the run.

var _frames := 0
var _out := "ground_lab.png"
var _ref := ""
var _options := {}
var _camera: Camera3D
var _live := false ## no `out=`: stay open with an orbit camera (drag to circle the focus, wheel to zoom, middle drag to move it)
var _focus := Vector3(0.0, 0.0, -0.5)
var _yaw := 0.0
var _pitch := 0.9
var _distance := 2.2


func _ready() -> void:
	var root := get_tree().root
	for arg in OS.get_cmdline_user_args():
		var parts := arg.split("=", true, 1)
		if parts.size() == 2:
			_options[parts[0]] = parts[1]
	_live = not _options.has("out")
	_out = _options.get("out", _out)
	_ref = _options.get("ref", "")
	var soil: String = _options.get("soil", "laterite")
	var detail := float(_options.get("detail", "1"))
	var seed_value := int(_options.get("seed", "1"))
	var view: String = _options.get("view", "eye")
	var size_parts: PackedStringArray = String(_options.get("size", "1600x900")).split("x")
	root.size = Vector2i(int(size_parts[0]), int(size_parts[1]))

	# the globals the planet sets
	RenderingServer.global_shader_parameter_set(&"realism", 1.0)
	RenderingServer.global_shader_parameter_set(&"ground_detail", detail)
	RenderingServer.global_shader_parameter_set(&"snow_cover", 0.0)
	RenderingServer.global_shader_parameter_set(&"anchor_from_world", Projection.IDENTITY)
	RenderingServer.global_shader_parameter_set(&"anchor_wrap", Vector3.ZERO)
	RenderingServer.global_shader_parameter_set(&"anchor_up", Vector3.UP)
	RenderingServer.global_shader_parameter_set(&"anchor_phase", 0.0)
	var sun_parts: PackedStringArray = String(_options.get("sun", "38,215")).split(",")
	var elevation := deg_to_rad(float(sun_parts[0]))
	var azimuth := deg_to_rad(float(sun_parts[1]) if sun_parts.size() > 1 else 215.0)
	var toward_sun := Vector3(cos(elevation) * sin(azimuth), sin(elevation), cos(elevation) * cos(azimuth))
	RenderingServer.global_shader_parameter_set(&"cloud_sun_world", toward_sun)
	RenderingServer.global_shader_parameter_set(&"cloud_centre", Vector3(0.0, -20000.0, 0.0))

	var preset := _soil(soil)
	var stones := float(_options.get("stones", str(preset["stones"])))
	var patch := _patch(preset, stones, seed_value)
	add_child(patch)

	if _options.get("chips", "1") != "0":
		_scatter_chips(seed_value, preset, stones)

	var sun := DirectionalLight3D.new()
	sun.look_at_from_position(Vector3.ZERO, -toward_sun)
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 30.0
	add_child(sun)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color(0.62, 0.74, 0.9)
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color(0.55, 0.62, 0.75)
	environment.environment.ambient_light_energy = 0.7
	add_child(environment)

	var camera := Camera3D.new()
	_camera = camera
	add_child(camera)
	camera.fov = 55.0
	match view:
		"low":
			camera.look_at_from_position(Vector3(0.0, 0.25, 1.8), Vector3(0.0, 0.0, -2.0))
		"top":
			camera.look_at_from_position(Vector3(0.0, 2.4, 0.4), Vector3(0.0, 0.0, 0.0))
		"macro":
			camera.look_at_from_position(Vector3(0.0, 0.35, 0.45), Vector3(0.0, 0.0, 0.0))
		"down":
			camera.look_at_from_position(Vector3(0.0, 1.5, 0.35), Vector3(0.0, 0.0, 0.0))
		"far":
			camera.look_at_from_position(Vector3(0.0, 1.7, 1.6), Vector3(0.0, 0.0, -2.2))
		_: # eye: standing, looking down at the ground a couple of metres ahead (no horizon)
			camera.look_at_from_position(Vector3(0.0, 1.6, 1.2), Vector3(0.0, 0.0, -0.5))
	print("GROUND_LAB soil=%s view=%s detail=%.0f stones=%.2f seed=%d chips=%s" % [soil, view, detail, stones, seed_value,
			_options.get("chips", "1")])


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
func _scatter_chips(seed_value: int, preset: Dictionary, stones: float) -> void:
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
	var buffers: Array = native.call(&"gravel_chunk", positions, field, cells, 12.0, 0.0, 0.0, 12.0, 12.0, 0.12, 1.0, seed_value,
			FloraMeshes.CHIP_VARIANTS)
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
		instance.position = Vector3.ZERO
		add_child(instance)
	print("GROUND_LAB stones ", ", ".join(Array(buffers.map(func(buffer: PackedFloat32Array) -> int: return buffer.size() / 16))))


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
		return
	_frames += 1
	if _frames == 40:
		var image := root.get_texture().get_image()
		if _ref != "" and FileAccess.file_exists(_ref):
			var reference := Image.load_from_file(_ref)
			if reference != null:
				var scale := float(image.get_height()) / float(reference.get_height())
				reference.resize(int(reference.get_width() * scale), image.get_height(), Image.INTERPOLATE_LANCZOS)
				var both := Image.create(image.get_width() + reference.get_width(), image.get_height(), false, Image.FORMAT_RGB8)
				both.blit_rect(image, Rect2i(Vector2i.ZERO, image.get_size()), Vector2i.ZERO)
				both.blit_rect(reference, Rect2i(Vector2i.ZERO, reference.get_size()), Vector2i(image.get_width(), 0))
				image = both
		image.save_png(_out)
		get_tree().quit()
