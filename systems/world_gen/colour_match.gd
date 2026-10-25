class_name ColourMatch
extends RefCounted
## Last step of a bake: the colour is moved to the statistics of the photograph it imitates (mean per channel, strength of
## the coarse patches, strength of the fine detail). FITS is written by tools/bark/colour_match.py from bakes made with
## `enabled` off; a surface without an entry is left as it is.

const SHADER := preload("res://shaders/world/colour_match.gdshader")
const FITS := {
	"bark_willow_02": {"mean": Vector3(0.4916, 0.4388, 0.3879), "gain": Vector3(1.0556, 1.0541, 1.0536), "low": 1.273, "detail": 1.020},
	"trident_maple_bark": {"mean": Vector3(0.2789, 0.2177, 0.1541), "gain": Vector3(1.0974, 1.0955, 1.0919), "low": 0.940, "detail": 0.913},
	"japanese_cedar_bark": {"mean": Vector3(0.3297, 0.2603, 0.1986), "gain": Vector3(0.8555, 0.7950, 0.7055), "low": 0.529, "detail": 0.491},
	"tree_bark_03": {"mean": Vector3(0.5438, 0.5296, 0.4178), "gain": Vector3(1.0277, 0.9992, 0.9527), "low": 1.127, "detail": 1.012},
	"pine_bark": {"mean": Vector3(0.4188, 0.3100, 0.2065), "gain": Vector3(0.9600, 1.0494, 1.2203), "low": 0.582, "detail": 0.535},
	"palm_tree_bark": {"mean": Vector3(0.6336, 0.5889, 0.5319), "gain": Vector3(0.9668, 0.9589, 0.9517), "low": 1.329, "detail": 1.065},
	"forest_leaves_03": {"mean": Vector3(0.2406, 0.1896, 0.1109), "gain": Vector3(1.1223, 1.1147, 1.1225), "low": 0.847, "detail": 1.298},
	"gravel_soil": {"mean": Vector3(0.4309, 0.3981, 0.3706), "gain": Vector3(0.9051, 0.8883, 0.8351), "low": 0.874, "detail": 1.328},
	"red_soil": {"mean": Vector3(0.5787, 0.4326, 0.3275), "gain": Vector3(0.9865, 1.0887, 1.1818), "low": 1.105, "detail": 0.936},
	"rock_face_04": {"mean": Vector3(0.3023, 0.2564, 0.2047), "gain": Vector3(1.0969, 1.0896, 1.0817), "low": 1.066, "detail": 1.206},
	"rock_08": {"mean": Vector3(0.4851, 0.4255, 0.3458), "gain": Vector3(1.1478, 1.1472, 1.1462), "low": 0.515, "detail": 0.949},
	"rock_06": {"mean": Vector3(0.5301, 0.4105, 0.2941), "gain": Vector3(0.9302, 0.9284, 0.9299), "low": 0.707, "detail": 1.162},
	"plate_rock_pitted_mossy": {"mean": Vector3(0.7863, 0.6201, 0.4610), "gain": Vector3(0.9734, 0.9867, 1.0041), "low": 0.948, "detail": 0.987},
	"oak_wood_planks": {"mean": Vector3(0.6238, 0.4514, 0.3214), "gain": Vector3(1.0193, 1.0207, 1.0191), "low": 0.714, "detail": 0.658},
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
	rect.material = material
	viewport.add_child(rect)
	host.add_child(viewport)
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var result := viewport.get_texture().get_image()
	viewport.queue_free()
	return result
