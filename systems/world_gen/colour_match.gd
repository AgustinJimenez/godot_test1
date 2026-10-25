class_name ColourMatch
extends RefCounted
## Last step of a bake: the colour is moved to the statistics of the photograph it imitates (mean per channel, strength of
## the coarse patches, strength of the fine detail). FITS is written by tools/bark/colour_match.py from bakes made with
## `enabled` off; a surface without an entry is left as it is.

const SHADER := preload("res://shaders/world/colour_match.gdshader")
const FITS := {
	"plate_rock_pitted_mossy": {"mean": Vector3(0.7783, 0.6099, 0.4826), "gain": Vector3(0.9833, 1.0032, 0.9591), "low": 0.926, "detail": 1.099, "sat": 0.761},
	"palm_tree_bark": {"mean": Vector3(0.6193, 0.5716, 0.5128), "gain": Vector3(0.9892, 0.9879, 0.9872), "low": 1.408, "detail": 1.600, "sat": 1.026},
	"oak_wood_planks": {"mean": Vector3(0.6282, 0.4525, 0.3202), "gain": Vector3(1.0122, 1.0181, 1.0232), "low": 0.751, "detail": 0.732, "sat": 1.015},
	"pine_bark": {"mean": Vector3(0.4295, 0.3099, 0.2535), "gain": Vector3(0.9361, 1.0498, 0.9940), "low": 0.304, "detail": 0.400, "sat": 0.500},
	"red_soil": {"mean": Vector3(0.5821, 0.4750, 0.4015), "gain": Vector3(0.9808, 0.9914, 0.9642), "low": 1.098, "detail": 1.046, "sat": 0.772},
	"gravel_soil": {"mean": Vector3(0.2201, 0.1982, 0.2195), "gain": Vector3(1.7720, 1.7838, 1.4103), "low": 1.600, "detail": 1.600, "sat": 2.000},
	"bark_willow_02": {"mean": Vector3(0.4943, 0.4382, 0.3840), "gain": Vector3(1.0498, 1.0557, 1.0644), "low": 1.273, "detail": 1.020, "sat": 1.064},
	"trident_maple_bark": {"mean": Vector3(0.2841, 0.2166, 0.1463), "gain": Vector3(1.0774, 1.1015, 1.1503), "low": 0.940, "detail": 0.913, "sat": 1.104},
	"japanese_cedar_bark": {"mean": Vector3(0.3343, 0.2591, 0.1923), "gain": Vector3(0.8438, 0.7986, 0.7284), "low": 0.529, "detail": 0.491, "sat": 1.083},
	"tree_bark_03": {"mean": Vector3(0.5496, 0.5317, 0.3907), "gain": Vector3(1.0169, 0.9952, 1.0187), "low": 1.127, "detail": 1.012, "sat": 1.261},
	"forest_leaves_03": {"mean": Vector3(0.2466, 0.1887, 0.0995), "gain": Vector3(1.0952, 1.1200, 1.2517), "low": 0.847, "detail": 1.298, "sat": 1.134},
	"rock_face_04": {"mean": Vector3(0.3072, 0.2554, 0.1968), "gain": Vector3(1.0793, 1.0941, 1.1247), "low": 1.066, "detail": 1.206, "sat": 1.131},
	"rock_08": {"mean": Vector3(0.4928, 0.4241, 0.3323), "gain": Vector3(1.1299, 1.1510, 1.1927), "low": 0.515, "detail": 0.949, "sat": 1.152},
	"rock_06": {"mean": Vector3(0.5235, 0.4121, 0.3035), "gain": Vector3(0.9418, 0.9248, 0.9008), "low": 0.707, "detail": 1.162, "sat": 0.932},
}
## off while the fits are measured (square_compare --no-match)
static var enabled := true


## `name` is the photograph's name. Returns `image` itself when nothing applies.
static func apply(host: Node, image: Image, name: String) -> Image:
	if not enabled or not FITS.has(name):
		return image
	var fit: Dictionary = FITS[name]
	var size := image.get_width()
	var source := image.duplicate() as Image
	source.convert(Image.FORMAT_RGBA8)
	source.generate_mipmaps()
	var viewport := SubViewport.new()
	viewport.size = Vector2i(size, size)
	viewport.disable_3d = true
	viewport.transparent_bg = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	var rect := ColorRect.new()
	rect.size = Vector2(size, size)
	var material := ShaderMaterial.new()
	material.shader = SHADER
	material.set_shader_parameter(&"src", ImageTexture.create_from_image(source))
	material.set_shader_parameter(&"lod", log(float(size) / 32.0) / log(2.0))
	material.set_shader_parameter(&"mean_value", fit["mean"])
	material.set_shader_parameter(&"mean_gain", fit["gain"])
	material.set_shader_parameter(&"low_gain", fit["low"])
	material.set_shader_parameter(&"detail_gain", fit["detail"])
	material.set_shader_parameter(&"sat_gain", fit.get("sat", 1.0))
	rect.material = material
	viewport.add_child(rect)
	host.add_child(viewport)
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var result := viewport.get_texture().get_image()
	viewport.queue_free()
	return result
