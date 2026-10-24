extends Node
## Bakes the fitted procedural rock face (LumpFits) and saves it: `-- --out=E:/folder`
## (lump_colour.png, lump_height.png). Compare with fits/rock_face_04_lump_vs.png.


func _ready() -> void:
	var out := "E:/Temp"
	var rock := "rock_face_04"
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--out="):
			out = argument.substr(6)
		if argument.begins_with("--rock="):
			rock = argument.substr(7)
	var baker := LumpBaker.new()
	add_child(baker)
	var image: Image = await baker.bake(rock)
	image.save_png("%s/lump_colour.png" % out)
	var grey := Image.create(image.get_width(), image.get_height(), false, Image.FORMAT_L8)
	for y in image.get_height():
		for x in image.get_width():
			grey.set_pixel(x, y, Color(image.get_pixel(x, y).a, 0, 0))
	grey.save_png("%s/lump_height.png" % out)
	get_tree().quit()
