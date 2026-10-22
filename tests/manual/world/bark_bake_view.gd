extends Node
## Bakes the fitted procedural barks and saves each as a picture: `-- --out=E:/folder` (colour, then
## the height as grey). Compare with the photographs of tools/bark and with `bark_view --compare`.

func _ready() -> void:
	var out := "E:/Temp"
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--out="):
			out = argument.substr(6)
	var baker := BarkBaker.new()
	add_child(baker)
	for name: String in BarkFits.fits():
		var started := Time.get_ticks_msec()
		var image: Image = await baker.bake(name)
		print("BAKED %s in %d ms" % [name, Time.get_ticks_msec() - started])
		image.save_png("%s/baked_%s.png" % [out, name])
		var grey := Image.create(image.get_width(), image.get_height(), false, Image.FORMAT_L8)
		for y in image.get_height():
			for x in image.get_width():
				grey.set_pixel(x, y, Color(image.get_pixel(x, y).a, 0, 0))
		grey.save_png("%s/baked_%s_height.png" % [out, name])
	get_tree().quit()
