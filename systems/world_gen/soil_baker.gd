class_name SoilBaker
extends Node
## Draws the procedural fine soil (SoilFits, fitted to photographs by tools/bark) once
## into a tile: colour in rgb, the height in alpha.

const SHADER := preload("res://shaders/world/soil_bake.gdshader")
const SIZE := 1024


## The tile of one fitted fine soil (`name` is a key of SoilFits.fits()) as an Image (RGBA8).
func bake(name: String, seed_value := 1.0) -> Image:
	var fit: Dictionary = SoilFits.fits()[name]
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
	var sand: Color = fit["sand"]
	var red: Color = fit["red"]
	material.set_shader_parameter(&"sand_colour", Vector3(sand.r, sand.g, sand.b))
	material.set_shader_parameter(&"red_colour", Vector3(red.r, red.g, red.b))
	material.set_shader_parameter(&"red_share", fit["red_share"])
	material.set_shader_parameter(&"seed", seed_value)
	rect.material = material
	viewport.add_child(rect)
	add_child(viewport)
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var image := viewport.get_texture().get_image()
	viewport.queue_free()
	return image
