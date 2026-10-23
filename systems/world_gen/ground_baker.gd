class_name GroundBaker
extends Node
## Makes the two maps of a ground "scan" (the ground shader's `scan_*_c`: colour + occlusion, and
## `scan_*_n`: normal + roughness) from a procedural tile baked by BarkBaker (colour in rgb, height
## in alpha): the photographed scan can then go. Add to the tree and `await bake_litter()`.

const SHADER := preload("res://shaders/world/ground_maps.gdshader")


## [colour map, normal map] (Images) of the fitted leaf litter.
func bake_litter() -> Array[Image]:
	var baker := BarkBaker.new()
	add_child(baker)
	# the bark colour model (cavity gain, mottling) is far too strong for litter: leaves take the
	# photograph's colours one by one and nothing else
	var fits := LitterFits.fits()
	fits["forest_leaves_03"]["gain"] = 0.6
	fits["forest_leaves_03"]["mottle"] = 0.0
	var tile: Image = await baker.bake("forest_leaves_03", 1.0, fits)
	baker.queue_free()
	var texture := ImageTexture.create_from_image(tile)
	var maps: Array[Image] = []
	for mode in 2:
		maps.append(await _pass(texture, mode))
	return maps


func _pass(tile: Texture2D, mode: int) -> Image:
	var size := tile.get_size()
	var viewport := SubViewport.new()
	viewport.size = Vector2i(size)
	viewport.disable_3d = true
	viewport.transparent_bg = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	var rect := ColorRect.new()
	rect.size = size
	var material := ShaderMaterial.new()
	material.shader = SHADER
	material.set_shader_parameter(&"tile", tile)
	material.set_shader_parameter(&"mode", mode)
	rect.material = material
	viewport.add_child(rect)
	add_child(viewport)
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var image := viewport.get_texture().get_image()
	viewport.queue_free()
	return image
