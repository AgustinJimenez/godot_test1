class_name BarkBaker
extends Node
## Draws the procedural barks (BarkFits, fitted to photographs by tools/bark) once, each into
## a tile: colour in rgb, the height in alpha (the layout of the photographed atlas). Add the node
## to the tree and `await bake(name)` for an Image.

const SHADER := preload("res://shaders/world/bark_bake.gdshader")
const SIZE := 1024


## The tile of one fitted bark (`name` is a key of BarkFits.FITS) as an Image (RGBA8).
func bake(name: String, seed_value := 1.0) -> Image:
	var fit: Dictionary = BarkFits.fits()[name]
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
	material.set_shader_parameter(&"shading", Vector3(fit["gain"], fit["mottle"], 0.18))
	rect.material = material
	viewport.add_child(rect)
	add_child(viewport)
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var image := viewport.get_texture().get_image()
	viewport.queue_free()
	return image


## The six-slot bark array of the plant shader: the fitted procedural barks baked into their slots
## and the photographed atlas kept in the others (slots: oak, pine, ash, maple, palm, cedar).
## `await baker.make_array()`; set the result as `bark_photo` on FloraMeshes.material().
func make_array() -> Texture2DArray:
	var layers: Array[Image] = []
	var atlas := Image.load_from_file("res://assets/textures/bark/bark_atlas.png")
	var fits := BarkFits.fits()
	# only the barks whose procedural look has been judged as good as the photograph (willow so far;
	# pine reads as leaves and ash is too rough, see AGENT_TASKS/085)
	var baked := {"bark_willow_02": 0, "trident_maple_bark": 3}
	for slot in 6:
		var image: Image = null
		for name: String in baked:
			if baked[name] == slot and fits.has(name):
				image = await bake(name)
		if image == null:
			image = atlas.get_region(Rect2i((slot % 3) * SIZE, (slot / 3) * SIZE, SIZE, SIZE))
		image.generate_mipmaps()
		layers.append(image)
	var array := Texture2DArray.new()
	array.create_from_images(layers)
	return array
