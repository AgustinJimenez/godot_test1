extends Node
## Bakes the fitted procedural wood and saves it as a picture: `-- --out=E:/folder`.

func _ready() -> void:
	var out := "E:/Temp"
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--out="):
			out = argument.substr(6)
	var baker := WoodBaker.new()
	add_child(baker)
	for name: String in WoodFits.fits():
		var image: Image = await baker.bake(name)
		image.save_png("%s/baked_%s.png" % [out, name])
		print("BAKED ", name)
	get_tree().quit()
