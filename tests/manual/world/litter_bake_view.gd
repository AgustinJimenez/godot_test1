extends Node
## Bakes the procedural leaf litter into the ground shader's two scan maps and saves them:
## `-- --out=E:/folder` (litter_c.png, litter_n.png). Compare with the scans/leaf_*.png scan.


func _ready() -> void:
	var out := "E:/Temp"
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--out="):
			out = argument.substr(6)
	var baker := GroundBaker.new()
	add_child(baker)
	var started := Time.get_ticks_msec()
	var maps: Array[Image] = await baker.bake_litter()
	var red: Array[Image] = await baker.bake_red()
	red[0].save_png("%s/red_c.png" % out)
	red[1].save_png("%s/red_n.png" % out)
	var gravel: Array[Image] = await baker.bake_gravel()
	gravel[0].save_png("%s/gravel_c.png" % out)
	gravel[1].save_png("%s/gravel_n.png" % out)
	print("LITTER baked in %d ms" % (Time.get_ticks_msec() - started))
	maps[0].save_png("%s/litter_c.png" % out)
	maps[1].save_png("%s/litter_n.png" % out)
	get_tree().quit()
