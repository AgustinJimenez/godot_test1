class_name LumpBaker
extends Node
## Draws the procedural rock face (LumpFits, fitted to photographs by tools/bark) once
## into a tile: colour in rgb, the height in alpha.

const SHADER := preload("res://shaders/world/lump_bake.gdshader")
const SIZE := 1024
## how much of the photograph's staining each rock shows (the others keep the plain tones)
const STAIN_AMOUNT := {"rock_06": 1.0}
## how much the lumps follow the 16 x 16 picture of the photograph (0: fully procedural)
const GUIDE_MIX := 0.8


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
	material.set_shader_parameter(&"p", fit["params"])
	material.set_shader_parameter(&"tile_cm", fit["tile_cm"])
	material.set_shader_parameter(&"height_range", fit["height_range"])
	var colours := PackedVector3Array()
	for colour: Color in fit["ramp"]:
		colours.append(Vector3(colour.r, colour.g, colour.b))
	material.set_shader_parameter(&"ramp", colours)
	material.set_shader_parameter(&"seed", seed_value)
	var light: Color = fit["light"]
	var dark: Color = fit["dark"]
	material.set_shader_parameter(&"light_colour", Vector3(light.r, light.g, light.b))
	material.set_shader_parameter(&"dark_colour", Vector3(dark.r, dark.g, dark.b))
	material.set_shader_parameter(&"dark_share", float(fit["dark_share"]) * float(STAIN_AMOUNT.get(name, 0.0)))
	material.set_shader_parameter(&"guide", fit["guide"])
	material.set_shader_parameter(&"guide_mix", GUIDE_MIX)
	rect.material = material
	viewport.add_child(rect)
	add_child(viewport)
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var image := viewport.get_texture().get_image()
	viewport.queue_free()
	return image
