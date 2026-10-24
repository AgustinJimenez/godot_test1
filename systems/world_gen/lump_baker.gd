class_name LumpBaker
extends Node
## Draws the procedural rock face (LumpFits, fitted to photographs by tools/bark) once
## into a tile: colour in rgb, the height in alpha.

const SHADER := preload("res://shaders/world/lump_bake.gdshader")
const COLOUR_PASS := preload("res://shaders/world/lump_colour_pass.gdshader")
const MAPS_PASS := preload("res://shaders/world/lump_maps_pass.gdshader")
const SIZE := 1024
var _edge_tex: ImageTexture # kept from the bake: the boulder's derived maps read the same layout
var _lobe_tex: ImageTexture
var _lobe_count := 0
var _crack_tex: ImageTexture
## how much of the photograph's staining each rock shows (the others keep the plain tones)
const STAIN_AMOUNT := {"rock_06": 1.0}
## how much the lumps follow the 16 x 16 picture of the photograph (0: fully procedural)
const GUIDE_MIX := 0.8
## the boulder ignores the guide: its 16 x 16 cells drew straight bands across the plates
const GUIDE_MIX_OF := {"rock_boulder_dry": 0.0}
## how much of the fine (12) and mid (14) relief each rock keeps (the boulder is smooth)
const CALM := {"rock_boulder_dry": 1.0}
## depth of a few long wiggly cracks (0: none): the mottled rock photograph has them
const WIGGLE_CRACKS := {"rock_08": 0.07}
## height of the rimmed lobes (0: none): the boulder photograph has rounded plates with raised rims
const RIM_LOBES := {"rock_boulder_dry": 0.045}


## The tile of one fitted rock face (`name` is a key of LumpFits.fits()) as an Image (RGBA8).
func bake(name: String, seed_value := 1.0) -> Image:
	var fit: Dictionary = LumpFits.fits()[name]
	var viewport := SubViewport.new()
	viewport.size = Vector2i(SIZE, SIZE)
	viewport.disable_3d = true
	viewport.transparent_bg = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	var rect := ColorRect.new()
	rect.size = Vector2(SIZE, SIZE)
	var material := ShaderMaterial.new()
	material.shader = SHADER
	var params: PackedFloat32Array = fit["params"].duplicate()
	var calm: float = CALM.get(name, 1.0)
	params[12] *= calm
	params[14] *= calm
	material.set_shader_parameter(&"p", params)
	material.set_shader_parameter(&"wiggle_cracks", WIGGLE_CRACKS.get(name, 0.0))
	material.set_shader_parameter(&"bp", BoulderParams.as_packed())
	if name == "rock_boulder_dry":
		_set_features(material)
	material.set_shader_parameter(&"rim_lobes", RIM_LOBES.get(name, 0.0))
	material.set_shader_parameter(&"tile_cm", fit["tile_cm"])
	# the guide and the fine relief lift parts above the fitted range: widen it, no flat clipping
	var range_fit: Vector2 = fit["height_range"]
	material.set_shader_parameter(&"height_range",
			Vector2(range_fit.x - 0.25 * (range_fit.y - range_fit.x),
					range_fit.y + 0.35 * (range_fit.y - range_fit.x)))
	var colours := PackedVector3Array()
	for colour: Color in fit["ramp"]:
		colours.append(Vector3(colour.r, colour.g, colour.b))
	material.set_shader_parameter(&"ramp", colours)
	material.set_shader_parameter(&"seed", seed_value)
	var light: Color = fit["light"]
	var dark: Color = fit["dark"]
	material.set_shader_parameter(&"light_colour", Vector3(light.r, light.g, light.b))
	material.set_shader_parameter(&"dark_colour", Vector3(dark.r, dark.g, dark.b))
	var stain: float = float(fit["dark_share"]) * float(STAIN_AMOUNT.get(name, 0.0))
	material.set_shader_parameter(&"dark_share", stain)
	material.set_shader_parameter(&"guide", fit["guide"])
	material.set_shader_parameter(&"guide_mix", _guide_mix(name))
	rect.material = material
	viewport.add_child(rect)
	add_child(viewport)
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var image := viewport.get_texture().get_image()
	viewport.queue_free()
	if name == "rock_boulder_dry":
		image = await _colour_pass(image)
	return image


func _guide_mix(name: String) -> float:
	if name == "rock_boulder_dry" and BoulderParams.values[29] > 0.5:
		return 0.8 # (the traced lobes carry the layout; the guide gives the big swells)
	return GUIDE_MIX_OF.get(name, GUIDE_MIX)


## The traced lobes (outlines) and pits as two float textures (BoulderFeatures, generated).
func _set_features(material: ShaderMaterial) -> void:
	var stride := BoulderFeatures.LOBE_STRIDE
	var data := BoulderFeatures.lobes()
	var lobe_count := data.size() / stride
	var lobes := Image.create(2 + 48 + 1, maxi(lobe_count, 1), false, Image.FORMAT_RGBAF)
	for row in lobe_count:
		var base := row * stride
		lobes.set_pixel(0, row, Color(data[base], data[base + 1], data[base + 2], data[base + 3]))
		lobes.set_pixel(1, row,
				Color(data[base + 4], data[base + 5], data[base + 6], data[base + 7]))
		for k in 48:
			lobes.set_pixel(2 + k, row,
					Color(data[base + 8 + 2 * k], data[base + 9 + 2 * k], 0, 0))
		lobes.set_pixel(50, row, Color(data[base + 104], data[base + 105], data[base + 106], 1.0))
	var points := BoulderFeatures.specks()
	var speck_count := points.size() / BoulderFeatures.SPECK_STRIDE
	var specks := Image.create(maxi(speck_count, 1), 1, false, Image.FORMAT_RGBAF)
	for i in speck_count:
		var at := i * BoulderFeatures.SPECK_STRIDE
		specks.set_pixel(i, 0,
				Color(points[at], points[at + 1], points[at + 2], points[at + 3]))
	_lobe_tex = ImageTexture.create_from_image(lobes)
	_lobe_count = lobe_count
	material.set_shader_parameter(&"lobe_tex", _lobe_tex)
	material.set_shader_parameter(&"speck_tex", ImageTexture.create_from_image(specks))
	material.set_shader_parameter(&"n_lobes", lobe_count)
	material.set_shader_parameter(&"n_specks", speck_count)
	var grid := BoulderFeatures.SWELL_SIZE
	var values := BoulderFeatures.swell()
	var swell := Image.create(grid, grid, false, Image.FORMAT_RF)
	for y in grid:
		for x in grid:
			swell.set_pixel(x, y, Color(values[y * grid + x], 0, 0, 0))
	_crack_tex = _crack_texture()
	material.set_shader_parameter(&"crack_tex", _crack_tex)
	_edge_tex = _edge_texture()
	material.set_shader_parameter(&"edge_tex", _edge_tex)
	var rgb := FileAccess.get_file_as_bytes("res://systems/world_gen/boulder_colour.bin")
	var colour_grid := int(sqrt(rgb.size() / 3.0))
	var grid_image := Image.create_from_data(
			colour_grid, colour_grid, false, Image.FORMAT_RGB8, rgb)
	material.set_shader_parameter(&"swell_colour_tex", ImageTexture.create_from_image(grid_image))
	material.set_shader_parameter(&"swell_tex", ImageTexture.create_from_image(swell))
	material.set_shader_parameter(&"n_swell", grid)


const EDGE_RADIUS := 7 # px a point's step profile reaches either side of the edge
const EDGE_TANGENT_SIGMA := 3.5 # px along the edge
const EDGE_RISE := 1.6 # px: how sharp the step is across the edge
const EDGE_STEP_MAX := 0.25 # the step byte 255 (extract_edges.py)
const EDGE_SPACING := 3.0 # px between the points along a curve


## Draws the stored edge points (x, y, step, angle; 6 bytes each) into a float image.
## Every point is a small step profile across its edge (up on the uphill side, down on
## the other), a Gaussian along the edge so that neighbouring points overlap smoothly.
func _edge_texture() -> ImageTexture:
	var size := 1024
	var data := FileAccess.get_file_as_bytes("res://systems/world_gen/boulder_edges.bin")
	var field := PackedFloat32Array()
	field.resize(size * size)
	var count := data.size() / 6
	var norm := EDGE_SPACING / (EDGE_TANGENT_SIGMA * sqrt(TAU))
	for i in count:
		var base := i * 6
		var cx := data.decode_u16(base)
		var cy := data.decode_u16(base + 2)
		var amp := float(data[base + 4]) / 255.0 * EDGE_STEP_MAX
		var angle := float(data[base + 5]) / 255.0 * TAU
		var nx := cos(angle)
		var ny := sin(angle)
		for dy in range(-EDGE_RADIUS, EDGE_RADIUS + 1):
			var y := posmod(cy + dy, size) # (the tile wraps: a stamp at the border continues on the other side)
			for dx in range(-EDGE_RADIUS, EDGE_RADIUS + 1):
				var x := posmod(cx + dx, size)
				var across := dx * nx + dy * ny
				var along := -dx * ny + dy * nx
				var weight := exp(-0.5 * pow(along / EDGE_TANGENT_SIGMA, 2.0)) * norm
				var profile := 0.5 * amp * tanh(across / EDGE_RISE)
				profile *= exp(-pow(across / float(EDGE_RADIUS), 2.0))
				field[y * size + x] += profile * weight
	var image := Image.create_from_data(size, size, false, Image.FORMAT_RF, field.to_byte_array())
	return ImageTexture.create_from_image(image)


## The boulder's second pass: colour detail derived from the generated height.
## Cavities come out darker and convex tops lighter.
func _colour_pass(first: Image) -> Image:
	var viewport := SubViewport.new()
	viewport.size = first.get_size()
	viewport.disable_3d = true
	viewport.transparent_bg = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	var rect := ColorRect.new()
	rect.size = Vector2(first.get_size())
	var material := ShaderMaterial.new()
	material.shader = COLOUR_PASS
	material.set_shader_parameter(&"first_pass", ImageTexture.create_from_image(first))
	material.set_shader_parameter(&"texel", 1.0 / float(first.get_width()))
	material.set_shader_parameter(&"strength", BoulderParams.values[37])
	material.set_shader_parameter(&"chroma", BoulderParams.values[38])
	material.set_shader_parameter(&"clip_level", BoulderParams.values[42])
	material.set_shader_parameter(&"small_scale", BoulderParams.values[43])
	material.set_shader_parameter(&"up_scale", BoulderParams.values[47])
	rect.material = material
	viewport.add_child(rect)
	add_child(viewport)
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var image := viewport.get_texture().get_image()
	viewport.queue_free()
	return image


## One of the boulder's other material maps derived from its bake (colour in rgb, height in alpha):
## 0 normal (OpenGL), 1 ambient occlusion, 2 roughness, 3 the packed ARM map.
## The relations are in lump_maps_pass.gdshader.
func derive_map(baked: Image, mode: int) -> Image:
	var viewport := SubViewport.new()
	viewport.size = baked.get_size()
	viewport.disable_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	var rect := ColorRect.new()
	rect.size = Vector2(baked.get_size())
	var material := ShaderMaterial.new()
	material.shader = MAPS_PASS
	material.set_shader_parameter(&"baked", ImageTexture.create_from_image(baked))
	material.set_shader_parameter(&"mode", mode)
	material.set_shader_parameter(&"texel", 1.0 / float(baked.get_width()))
	material.set_shader_parameter(&"tile_px", float(baked.get_width()))
	material.set_shader_parameter(&"edge_tex", _edge_tex)
	material.set_shader_parameter(&"crack_tex", _crack_tex)
	material.set_shader_parameter(&"lobe_tex", _lobe_tex)
	material.set_shader_parameter(&"n_lobes", _lobe_count)
	rect.material = material
	viewport.add_child(rect)
	add_child(viewport)
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var image := viewport.get_texture().get_image()
	viewport.queue_free()
	return image


## The thin cracks (x, y, strength, width; 6 bytes each, from extract_cracks.py) as an image.
## Each crack pixel is a small cross so that the lines stay continuous at any slope.
func _crack_texture() -> ImageTexture:
	var size := 1024
	var data := FileAccess.get_file_as_bytes("res://systems/world_gen/boulder_cracks.bin")
	var field := PackedFloat32Array()
	field.resize(size * size)
	for i in data.size() / 6:
		var base := i * 6
		var cx := data.decode_u16(base)
		var cy := data.decode_u16(base + 2)
		var strength := float(data[base + 4]) / 255.0
		for dy in range(-1, 2):
			for dx in range(-1, 2):
				var x := posmod(cx + dx, size)
				var y := posmod(cy + dy, size)
				var weight := 0.3
				if dx == 0 and dy == 0:
					weight = 1.0
				elif dx == 0 or dy == 0:
					weight = 0.55
				field[y * size + x] = maxf(field[y * size + x], strength * weight)
	var image := Image.create_from_data(size, size, false, Image.FORMAT_RF, field.to_byte_array())
	return ImageTexture.create_from_image(image)
