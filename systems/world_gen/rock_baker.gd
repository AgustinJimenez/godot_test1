class_name RockBaker
extends Node
## Draws the procedural rocks (RockFits, fitted to photographs by tools/bark) once, each into a
## tile: colour in rgb, the height in alpha (the layout of the photographed rock atlas).

const SHADER := preload("res://shaders/world/rock_bake.gdshader")
const SIZE := 1024


## The tile of one fitted rock (`name` is a key of RockFits.fits()) as an Image (RGBA8).
func bake(name: String, seed_value := 1.0) -> Image:
	var fit: Dictionary = RockFits.fits()[name]
	var viewport := SubViewport.new()
	viewport.size = Vector2i(SIZE, SIZE)
	viewport.disable_3d = true
	viewport.transparent_bg = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	var rect := ColorRect.new()
	rect.size = Vector2(SIZE, SIZE)
	var material := ShaderMaterial.new()
	material.shader = SHADER
	material.set_shader_parameter(&"p", fit["params"])
	material.set_shader_parameter(&"tile_cm", fit["tile_cm"])
	material.set_shader_parameter(&"height_range", fit["height_range"])
	var colours := PackedVector3Array()
	for colour: Color in fit["ramp"]:
		colours.append(Vector3(colour.r, colour.g, colour.b))
	material.set_shader_parameter(&"ramp", colours)
	material.set_shader_parameter(&"seed", seed_value)
	var mean: Color = fit["mean"]
	material.set_shader_parameter(&"mean_colour", Vector3(mean.r, mean.g, mean.b))
	material.set_shader_parameter(&"shading", Vector3(fit["gain"], fit["mottle"], 0.0))
	rect.material = material
	viewport.add_child(rect)
	add_child(viewport)
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var image := viewport.get_texture().get_image()
	viewport.queue_free()
	return image


## The six-slot rock array of the plant shader: the fitted procedural rocks baked into their slots,
## the photographed atlas kept in the others.
func make_array() -> Texture2DArray:
	var layers: Array[Image] = []
	var atlas := Image.load_from_file("res://assets/textures/rock/rock_atlas.png")
	var fits := RockFits.fits()
	var baked := {}
	if OS.has_environment("PLANET_PROCEDURAL_ROCKS"): # (the blocks-and-cracks fits: not good yet)
		for name: String in fits:
			baked[int(fits[name]["slot"])] = name
	var lumps := LumpBaker.new() # (smooth lumps: the rock face, the two mottled boulders)
	add_child(lumps)
	var lump_slots := {0: "rock_boulder_dry", 1: "rock_face_04", 2: "rock_08", 3: "rock_06"}
	var cells := PlateBaker.new() # (rounded cells with a crack network: the pitted mossy rock, slot 4)
	add_child(cells)
	for slot in 6:
		var image: Image = null
		if slot == 4 and OS.has_environment("PLANET_PROCEDURAL_CELLS"):
			image = await cells.bake("rock_pitted_mossy")
		elif lump_slots.has(slot) and OS.has_environment("PLANET_PROCEDURAL_LUMPS"):
			image = await lumps.bake(lump_slots[slot])
		elif baked.has(slot):
			image = await bake(baked[slot])
		else:
			image = atlas.get_region(Rect2i((slot % 3) * SIZE, (slot / 3) * SIZE, SIZE, SIZE))
		image.generate_mipmaps()
		layers.append(image)
	var array := Texture2DArray.new()
	array.create_from_images(layers)
	return array
