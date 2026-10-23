class_name PlateBaker
extends Node
## Draws the procedural plated bark (PlateFits, fitted to photographs by tools/bark) once into a
## tile: colour in rgb, the height in alpha.

const SHADER := preload("res://shaders/world/plate_bake.gdshader")
const SIZE := 1024
## how much each plate takes its own colour from the photograph's palette
const PALETTE_MIX := 0.85


## The tile of one fitted plated bark (`name` is a key of PlateFits.fits()) as an Image (RGBA8).
func bake(name: String, seed_value := 1.0) -> Image:
	var fit: Dictionary = PlateFits.fits()[name]
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
	var palette := PackedVector3Array()
	for colour: Color in fit["palette"]:
		palette.append(Vector3(colour.r, colour.g, colour.b))
	var shares: Array = fit["palette_shares"]
	material.set_shader_parameter(&"palette", palette)
	material.set_shader_parameter(&"palette_shares", Vector3(shares[0], shares[1], shares[2]))
	material.set_shader_parameter(&"palette_mix", PALETTE_MIX)
	rect.material = material
	viewport.add_child(rect)
	add_child(viewport)
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var image := viewport.get_texture().get_image()
	viewport.queue_free()
	return image
