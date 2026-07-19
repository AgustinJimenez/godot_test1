class_name CharacterImportMaterialFixups
extends RefCounted

## Automatic material corrections applied to freshly session-imported FBX
## characters (see character_editor.gd's _create_custom_character_adapter,
## the only caller) - extracted as a standalone utility purely to keep
## character_editor.gd under a manageable size; every function here is pure
## (only reads/writes the meshes/images passed in, no editor UI state) and
## was moved verbatim, not rewritten.


## Session-imported characters' materials sometimes come in with
## transparency wrongly enabled - observed directly on a real import (via
## a temporary live-bridge diagnostic, not guessed): every material had
## transparency = TRANSPARENCY_ALPHA_DEPTH_PRE_PASS and albedo_color.a =
## 0.8, making the whole character semi-transparent and letting other
## meshes (e.g. eyeballs) show through skin/clothes. Most likely Godot's
## FBX importer auto-detecting an alpha channel in the source texture and
## assuming it means the surface should be translucent. The curated
## characters already render correctly without this, so it's only applied
## to the import pipeline, not every character load - a character mesh
## being non-transparent is the correct default here, not a real texture
## effect being lost.
static func disable_mesh_transparency(meshes: Array[MeshInstance3D]) -> void:
	for mesh_part in meshes:
		for i in mesh_part.get_surface_override_material_count():
			var mat: Material = mesh_part.get_active_material(i)
			if mat is BaseMaterial3D:
				var base_material: BaseMaterial3D = mat
				base_material.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
				var albedo := base_material.albedo_color
				albedo.a = 1.0
				base_material.albedo_color = albedo


## Some imported characters ship extra PBR-ish textures (normal map,
## roughness/AO) alongside the color texture that never get wired into any
## material - observed directly (via visual inspection, not guessed) on
## Ch28_nonPBR: Godot's FBX importer only assigned albedo_texture, leaving
## 3 more extracted "_1"/"_2"/"_3" PNGs as orphaned files, even though "_3"
## is visibly a real tangent-space normal map (dominant blue channel, real
## wrinkle/seam detail) and "_2" a real roughness/AO map (grayscale,
## following the same UV layout as albedo). Confirmed this isn't the
## import pipeline's fault: Ch08_nonPBR (imported the normal way, not
## through this feature) has byte-identical .import settings and DOES get
## its normal map auto-wired - the difference is in what each FBX's own
## material graph references, which Godot's importer can only follow, not
## infer. This scans sibling "<basename>_N.png" files next to the albedo
## texture and classifies each by actual pixel content instead of assuming
## a fixed slot order, since that order isn't guaranteed across sources.
static func fix_unwired_textures(meshes: Array[MeshInstance3D], model_path: String) -> void:
	var dir_path := model_path.get_base_dir()
	var base_name := model_path.get_file().get_basename()
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	var candidate_paths: Array[String] = []
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		if (entry.begins_with(base_name + "_")
				and entry.get_extension().to_lower() in ["png", "jpg", "jpeg"]):
			candidate_paths.append(dir_path.path_join(entry))
		entry = dir.get_next()
	dir.list_dir_end()
	if candidate_paths.is_empty():
		return

	var seen_materials: Array[BaseMaterial3D] = []
	for mesh_part in meshes:
		for i in mesh_part.get_surface_override_material_count():
			var mat: Material = mesh_part.get_active_material(i)
			if not (mat is BaseMaterial3D):
				continue
			var base_material: BaseMaterial3D = mat
			if base_material in seen_materials:
				continue
			seen_materials.append(base_material)
			if base_material.normal_texture != null and base_material.roughness_texture != null:
				continue
			var albedo_path := (
					base_material.albedo_texture.resource_path if base_material.albedo_texture else "")
			for tex_path in candidate_paths:
				if tex_path == albedo_path:
					continue
				var raw_image := Image.load_from_file(ProjectSettings.globalize_path(tex_path))
				if raw_image == null:
					continue
				match classify_texture_role(raw_image):
					"normal":
						if base_material.normal_texture == null:
							base_material.normal_enabled = true
							base_material.normal_texture = linear_texture_from_image(raw_image)
					"roughness":
						if base_material.roughness_texture == null:
							invert_image_values(raw_image)
							base_material.roughness_texture = linear_texture_from_image(raw_image)


## Normal/roughness maps encode literal numeric values (surface direction,
## roughness amount), not perceptual color, so they must reach the shader
## as linear data - loading via `load(tex_path)` (ResourceLoader) instead
## would use the imported/compressed resource, which Godot by default
## stores in an sRGB-flagged GPU format for any texture it doesn't know is
## non-color data (exactly this case - these files were never recognized
## as normal/roughness maps by the FBX import in the first place). Sampling
## an sRGB-stored texture applies a gamma decode in hardware before the
## shader ever sees it, silently brightening the roughness map's values
## and making the whole character look shinier/wetter than authored -
## confirmed via research, not guessed (see the doc comment on
## classify_texture_role's caller). Building a fresh ImageTexture directly
## from the raw Image bypasses that decision entirely: it's just raw bytes
## uploaded as a plain, non-sRGB-flagged texture, sampled literally.
static func linear_texture_from_image(image: Image) -> ImageTexture:
	return ImageTexture.create_from_image(image)


## The "nonPBR" characters' grayscale channel map (identified by
## classify_texture_role as "roughness") turned out to be an old-style
## gloss/specular map, not a modern roughness map - confirmed with real
## pixel data, not guessed: sampled fabric regions read 0.04-0.20 and shoes
## read literal 0.0 (pure black). Those are exactly backwards for Godot's
## roughness_texture convention (0 = mirror-smooth, 1 = fully matte) - shoes
## rendered as a perfect mirror is what gave the "wet latex" look. Gloss
## and roughness are the same concept on an inverted scale (gloss: bright =
## shiny; roughness: bright = matte), so inverting each channel converts
## one into the other. Mutates in place (Image, not a Resource - safe,
## this copy is never shared with anything else in the project).
static func invert_image_values(image: Image) -> void:
	if image.is_compressed():
		image.decompress()
	# Raw byte-array arithmetic instead of get_pixel()/set_pixel() in a
	# loop - a real source texture here is 4096x4096 (16.7M pixels), and
	# per-pixel Color-object round trips at that scale are slow enough to
	# be worth avoiding even with the import spinner now giving cover for
	# it. Normalizing to RGBA8 first keeps the byte-stride assumption
	# below (4 bytes/pixel, alpha untouched) correct regardless of
	# whatever format the source PNG decoded to.
	if image.get_format() != Image.FORMAT_RGBA8:
		image.convert(Image.FORMAT_RGBA8)
	var data := image.get_data()
	for i in range(0, data.size(), 4):
		data[i] = 255 - data[i]
		data[i + 1] = 255 - data[i + 1]
		data[i + 2] = 255 - data[i + 2]
	image.set_data(
			image.get_width(), image.get_height(), image.has_mipmaps(), image.get_format(), data)


## Samples a grid of pixels to guess what a texture encodes, rather than
## trusting filename order (not consistent across sources - see
## fix_unwired_textures's doc comment):
## - Tangent-space normal maps are dominated by the blue channel (the
##   mostly-forward-facing Z component, encoded as roughly (128,128,255) at
##   a flat surface) - real surface detail shows as small deviations from
##   that, not a shift away from blue being dominant.
## - Roughness/AO/specular maps are low-saturation (grayscale) with real
##   tonal variation, unlike a flat color mask.
## - Anything else (color texture, mostly-flat/empty image) is left alone.
##
## Takes an already-loaded Image (see fix_unwired_textures - loaded via
## Image.load_from_file() reading the raw source PNG bytes directly, not
## `load(path)` + get_image(); the imported/compressed resource distorts
## normal maps enough to break the blue-channel check below, see
## linear_texture_from_image's doc comment for the same underlying cause).
static func classify_texture_role(image: Image) -> String:
	var sample_size := 24
	var width := image.get_width()
	var height := image.get_height()
	if width < sample_size or height < sample_size:
		return "unknown"
	var blue_dominant_votes := 0
	# Colorful/near-black/near-white pixels are excluded from the
	# grayscale+variance tally entirely, not just weighted down - large
	## areas of near-black fabric in a genuine color texture are trivially
	# "grayscale" (r=g=b=0) regardless of the image's real hue content, and
	# counted them straight into "roughness" votes on a real test case
	# (Ch28's own albedo texture, dominated by black clothing) before this
	# fix. Saturation is only meaningful once a pixel has enough brightness
	# to judge in the first place.
	var colorful_votes := 0
	var grayscale_votes := 0
	var judged_count := 0
	var luma_samples: Array[float] = []
	for gy in sample_size:
		for gx in sample_size:
			var x := int((float(gx) + 0.5) / sample_size * width)
			var y := int((float(gy) + 0.5) / sample_size * height)
			var pixel := image.get_pixel(x, y)
			if pixel.b > pixel.r + 0.12 and pixel.b > pixel.g + 0.12:
				blue_dominant_votes += 1
			var value := maxf(pixel.r, maxf(pixel.g, pixel.b))
			var saturation := 0.0 if value < 0.001 else (
					value - minf(pixel.r, minf(pixel.g, pixel.b))) / value
			if value > 0.12 and value < 0.95:
				judged_count += 1
				if saturation > 0.15:
					colorful_votes += 1
				else:
					grayscale_votes += 1
			luma_samples.append(0.299 * pixel.r + 0.587 * pixel.g + 0.114 * pixel.b)
	var total_samples := sample_size * sample_size
	if blue_dominant_votes > total_samples * 0.6:
		return "normal"
	if judged_count < total_samples * 0.1:
		return "unknown"
	if colorful_votes > judged_count * 0.1:
		return "unknown"  # real color content somewhere - treat as an albedo/detail texture
	var total_variance := 0.0
	for i in range(1, luma_samples.size()):
		total_variance += absf(luma_samples[i] - luma_samples[i - 1])
	# Roughness/AO maps have real tonal variation across the atlas (skin vs
	# fabric vs rubber sole read differently) - a flat gray color mask
	# wouldn't, so requiring both grayscale-ness AND variance rules that out.
	if grayscale_votes > judged_count * 0.6 and total_variance / total_samples > 0.01:
		return "roughness"
	return "unknown"
