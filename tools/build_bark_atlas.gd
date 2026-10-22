extends SceneTree
## Builds an atlas of Poly Haven (CC0) maps: 1024 px slots in 3 columns x 2 rows, the photo's colour
## in rgb and its height in alpha. By default the bark atlas (assets/textures/bark/bark_atlas.png):
## willow (oak), pine, tree_bark_03 (ash), trident maple, palm, japanese cedar.
## Run: godot --headless --path . -s tools/build_bark_atlas.gd -- <folder with the downloads>
##   [--out=res://assets/textures/rock/rock_atlas.png --slots=name1,name2,...]
## (each slot name has <name>_diff.jpg and <name>_disp.png in the folder).
## Then write the .import (see AGENTS.md "Surface relief from photographs").

const SLOTS: Array[String] = ["bark_willow_02", "pine_bark", "tree_bark_03", "trident_maple_bark",
		"palm_tree_bark", "japanese_cedar_bark"]
const CELL := 1024
const TARGET_LUMINANCE := 0.1


func _init() -> void:
	var folder := OS.get_cmdline_user_args()[0]
	var out := "res://assets/textures/bark/bark_atlas.png"
	var slots := SLOTS
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--out="):
			out = argument.trim_prefix("--out=")
		if argument.begins_with("--slots="):
			var parsed: Array[String] = []
			for part in argument.trim_prefix("--slots=").split(","):
				parsed.append(part)
			slots = parsed
	var atlas := Image.create(CELL * 3, CELL * 2, false, Image.FORMAT_RGBA8)
	for slot in slots.size():
		var colour := Image.load_from_file("%s/%s_diff.jpg" % [folder, slots[slot]])
		var height_path := "%s/%s_disp.png" % [folder, slots[slot]]
		var height := Image.load_from_file(height_path)
		colour.convert(Image.FORMAT_RGBA8)
		colour.resize(CELL, CELL, Image.INTERPOLATE_LANCZOS)
		height.convert(Image.FORMAT_L8)
		height.resize(CELL, CELL, Image.INTERPOLATE_LANCZOS)
		# the heights stretched to use the whole range (the photos' relief is low contrast)
		var low := 1.0
		var high := 0.0
		for y in CELL:
			for x in CELL:
				var h := height.get_pixel(x, y).r
				low = minf(low, h)
				high = maxf(high, h)
		# the colours brought to a bark albedo (mean linear luminance about 0.1): a dark photo is lifted
		var sum := 0.0
		for y in range(0, CELL, 4):
			for x in range(0, CELL, 4):
				var s := colour.get_pixel(x, y).srgb_to_linear()
				sum += 0.2126 * s.r + 0.7152 * s.g + 0.0722 * s.b
		var mean_lum := sum / float(CELL / 4 * CELL / 4)
		var gain := clampf(TARGET_LUMINANCE / maxf(mean_lum, 0.001), 1.0, 2.6)
		print("  mean luminance %.3f, gain %.2f" % [mean_lum, gain])
		var lo_cut := lerpf(low, high, 0.02)
		var hi_cut := lerpf(low, high, 0.98)
		for y in CELL:
			for x in CELL:
				var c := colour.get_pixel(x, y)
				c = (c.srgb_to_linear() * gain).linear_to_srgb()
				var span := maxf(hi_cut - lo_cut, 0.001)
				var h := clampf((height.get_pixel(x, y).r - lo_cut) / span, 0.0, 1.0)
				colour.set_pixel(x, y, Color(c.r, c.g, c.b, h))
		atlas.blit_rect(colour, Rect2i(0, 0, CELL, CELL), Vector2i((slot % 3) * CELL, (slot / 3) * CELL))
		print("slot %d %s: height %.2f..%.2f" % [slot, slots[slot], low, high])
	atlas.save_png(out)
	quit()
