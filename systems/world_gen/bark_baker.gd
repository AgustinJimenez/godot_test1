class_name BarkBaker
extends Node
## Draws the procedural barks (BarkFits, fitted to photographs by tools/bark) once, each into
## a tile: colour in rgb, the height in alpha (the layout of the photographed atlas). Add the node
## to the tree and `await bake(name)` for an Image.
const SHADER := preload("res://shaders/world/bark_bake.gdshader")
const SIZE := 1024
## how much each flake takes its own colour from the photograph's palette (only barks whose
## colour is not a function of the height: the pine's orange scales on grey)
## deeper fissures for the craggy barks (cavity shading and gap darkness, 0..1)
const DEPTH_BOOST := {"pine_bark": 1.0, "tree_bark_03": 0.5}
## how much more the baked height is spread than the photograph's (a deeper parallax and masks)
const HEIGHT_SPREAD := {"pine_bark": 2.2}
## the dark groove network round every raised flake (0..1)
const EDGE_DARK := {"pine_bark": 1.0, "tree_bark_03": 0.4}
## a whole-bark darkening where the albedo lift of the colour model comes out too light
const BRIGHTNESS := {"forest_leaves_03": 0.85, "pine_bark": 0.92, "tree_bark_03": 1.3,
	"trident_maple_bark": 0.52, "japanese_cedar_bark": 0.62, "bark_willow_02": 0.92}
## the same options tried on the barks that ship (opt-in: PLANET_BARK_GROOVES=1)
const GROOVED_EDGE := {
	"bark_willow_02": 0.6, "trident_maple_bark": 0.5, "japanese_cedar_bark": 0.4}
const GROOVED_BRIGHTNESS := {
	"bark_willow_02": 1.0, "trident_maple_bark": 0.8, "japanese_cedar_bark": 0.85}
## less contrast where the bake is far more contrasty than the photograph (0..1)
const FLATTEN := {"pine_bark": 0.3, "tree_bark_03": 0.8, "japanese_cedar_bark": 0.45,
	"trident_maple_bark": 0.3, "bark_willow_02": 0.4}
const GROOVED_FLATTEN := {
	"bark_willow_02": 0.3, "trident_maple_bark": 0.0, "japanese_cedar_bark": 0.4}
## sharpness: micro-contrast and pixel grain on the colour (0..1; every bark gets this default)
const CRISP := 1.0
## fine colour mottling where the fitted shapes are much larger than the photograph's speckle
const FINE_MOTTLE := {
	"trident_maple_bark": 0.4, "japanese_cedar_bark": 0.15, "bark_willow_02": 0.15}
## pull the colour toward grey where the fitted ramp is more saturated than the photograph
const DESATURATE := {"tree_bark_03": 0.32, "japanese_cedar_bark": 0.25, "pine_bark": -0.45}
const PALETTE_MIX := {"pine_bark": 0.95, "forest_leaves_03": 0.9}


## The tile of one fitted bark (`name` is a key of BarkFits.FITS) as an Image (RGBA8).
func bake(name: String, seed_value := 1.0, source := {}) -> Image:
	var fit: Dictionary = (source if not source.is_empty() else BarkFits.fits())[name]
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
	if fit.has("palette"):
		var palette := PackedVector3Array()
		for colour: Color in fit["palette"]:
			palette.append(Vector3(colour.r, colour.g, colour.b))
		var shares: Array = fit["palette_shares"]
		material.set_shader_parameter(&"palette", palette)
		material.set_shader_parameter(&"palette_shares", Vector3(shares[0], shares[1], shares[2]))
		material.set_shader_parameter(&"palette_mix", float(PALETTE_MIX.get(name, 0.0)))
		material.set_shader_parameter(&"palette_flat", 1.0 if name == "forest_leaves_03" else 0.0)
	var brightness: float = float(BRIGHTNESS.get(name, 1.0))
	var edge: float = float(EDGE_DARK.get(name, 0.0))
	if OS.has_environment("PLANET_BARK_GROOVES"):
		brightness = float(GROOVED_BRIGHTNESS.get(name, brightness))
		edge = float(GROOVED_EDGE.get(name, edge))
	var flat: float = float(FLATTEN.get(name, 0.0))
	if OS.has_environment("PLANET_BARK_GROOVES"):
		flat = float(GROOVED_FLATTEN.get(name, flat))
	material.set_shader_parameter(&"crisp", CRISP if name != "forest_leaves_03" else 0.55)
	material.set_shader_parameter(&"fine_mottle", float(FINE_MOTTLE.get(name, 0.0)))
	material.set_shader_parameter(&"desaturate", float(DESATURATE.get(name, 0.0)))
	material.set_shader_parameter(&"flatten", flat)
	material.set_shader_parameter(&"brightness", brightness)
	material.set_shader_parameter(&"edge_dark", edge)
	material.set_shader_parameter(&"depth_boost", float(DEPTH_BOOST.get(name, 0.0)))
	material.set_shader_parameter(&"alpha_map", Vector3(
			float(fit.get("alpha_scale", 1.0)) * float(HEIGHT_SPREAD.get(name, 1.0)),
			float(fit.get("alpha_from", 0.5)), float(fit.get("alpha_to", 0.5))))
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
## `await baker.make_array()` (`true`: every fit, for the viewer); set it as `bark_photo`.
func make_array(all_fits := false) -> Texture2DArray:
	var layers: Array[Image] = []
	var atlas := Image.load_from_file("res://assets/textures/bark/bark_atlas.png")
	var fits := BarkFits.fits()
	# only the barks whose procedural look has been judged as good as the photograph (willow so far;
	# pine reads as leaves and ash is too rough, see AGENT_TASKS/085)
	var plate_images := {}
	var baked := {"bark_willow_02": 0, "trident_maple_bark": 3, "japanese_cedar_bark": 5}
	if all_fits: # (the viewer: every fitted bark, to compare with the photographs)
		baked = {"bark_willow_02": 0, "pine_bark": 1, "tree_bark_03": 2, "trident_maple_bark": 3,
				"japanese_cedar_bark": 5}
	# the pine and the ringed palm: in the viewer, or opt-in in the game (not as good as
	# the photographs yet)
	if OS.has_environment("PLANET_PROCEDURAL_ASH"): # (long narrow ridged flakes: close on the sheet)
		baked["tree_bark_03"] = 2
	if OS.has_environment("PLANET_PROCEDURAL_PINE"): # (long narrow flakes, a plain-square sheet match)
		baked["pine_bark"] = 1
	if all_fits or OS.has_environment("PLANET_PROCEDURAL_PALM"):
		var rings := RingBaker.new() # (the palm: ring bands, not flakes)
		add_child(rings)
		plate_images[4] = await rings.bake("palm_tree_bark")
	for slot in 6:
		var image: Image = plate_images.get(slot)
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
