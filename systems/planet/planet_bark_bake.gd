class_name PlanetBarkBake
extends Node
## What the planet bakes once when it starts (kept in script because the bakers are coroutines that wait for frames):
## the procedural barks, rocks, ground scans and boards are drawn into the plant and ground shaders (photo atlases till then).
## PlanetWorld makes one of these, adds it as a child and calls `run`.

## The procedural barks and rocks are drawn once into the plant shader (photo atlases till then).
## Every procedural surface that has an opt-in (its PLANET_PROCEDURAL_* / PLANET_BARK_* switch).
const PROCEDURAL_SWITCHES: Array[String] = [
	"PLANET_PROCEDURAL_PINE", "PLANET_PROCEDURAL_ASH", "PLANET_PROCEDURAL_PALM",
	"PLANET_PROCEDURAL_LITTER", "PLANET_PROCEDURAL_GRAVEL", "PLANET_PROCEDURAL_RED",
	"PLANET_PROCEDURAL_WOOD", "PLANET_PROCEDURAL_LUMPS", "PLANET_PROCEDURAL_CELLS",
	"PLANET_BARK_GROOVES"]


## One switch for all of them: the environment variable PLANET_PROCEDURAL_ALL, or a file named
## `procedural_all` in the project folder (from the editor: create it, run, delete it).
func _procedural_all_requested() -> bool:
	return (OS.has_environment("PLANET_PROCEDURAL_ALL")
			or FileAccess.file_exists("res://procedural_all"))


## Runs the bakes (a coroutine: it returns at its first wait).
func run() -> void:
	if _procedural_all_requested():
		for switch in PROCEDURAL_SWITCHES:
			OS.set_environment(switch, "1")
		print("PROCEDURAL_ALL: every procedural surface is on")
	if OS.has_environment("PLANET_STOCH_BARK"): # (a test: AGENT_TASKS/086)
		FloraMeshes.material().set_shader_parameter(&"stoch_tiling", true)
	if OS.has_environment("PLANET_PROCEDURAL_LITTER") and DisplayServer.get_name() != "headless":
		var litter := GroundBaker.new() # (the forest floor's leaf scan from the fitted generator)
		add_child(litter)
		var maps: Array[Image] = await litter.bake_litter()
		for image in maps:
			image.generate_mipmaps()
		PlanetTile.ground_material().set_shader_parameter(&"scan_leaf_c",
				ImageTexture.create_from_image(maps[0]))
		PlanetTile.ground_material().set_shader_parameter(&"scan_leaf_n",
				ImageTexture.create_from_image(maps[1]))
		PlanetTile.ground_material().set_shader_parameter(&"scan_leaf_mean",
				GroundBaker.mean_linear(maps[0]))
		PlanetTile.ground_material().set_shader_parameter(&"scan_leaf_size",
				GroundBaker.LITTER_TILE_M)
		litter.queue_free()
	if OS.has_environment("PLANET_PROCEDURAL_RED") and DisplayServer.get_name() != "headless":
		var red := GroundBaker.new() # (the red soil scan from the fitted soil generator)
		add_child(red)
		var red_maps: Array[Image] = await red.bake_red()
		for image in red_maps:
			image.generate_mipmaps()
		var red_ground := PlanetTile.ground_material()
		red_ground.set_shader_parameter(&"scan_red_c", ImageTexture.create_from_image(red_maps[0]))
		red_ground.set_shader_parameter(&"scan_red_n", ImageTexture.create_from_image(red_maps[1]))
		red_ground.set_shader_parameter(&"scan_red_mean", GroundBaker.mean_linear(red_maps[0]))
		red_ground.set_shader_parameter(&"scan_red_size", GroundBaker.RED_TILE_M)
		red.queue_free()
	if OS.has_environment("PLANET_PROCEDURAL_GRAVEL") and DisplayServer.get_name() != "headless":
		var gravel := GroundBaker.new() # (the gravel scan from the fitted chips)
		add_child(gravel)
		var gravel_maps: Array[Image] = await gravel.bake_gravel()
		for image in gravel_maps:
			image.generate_mipmaps()
		var ground := PlanetTile.ground_material()
		ground.set_shader_parameter(&"scan_gravel_c", ImageTexture.create_from_image(gravel_maps[0]))
		ground.set_shader_parameter(&"scan_gravel_n", ImageTexture.create_from_image(gravel_maps[1]))
		ground.set_shader_parameter(&"scan_gravel_mean", GroundBaker.mean_linear(gravel_maps[0]))
		ground.set_shader_parameter(&"scan_gravel_size", GroundBaker.GRAVEL_TILE_M)
		gravel.queue_free()
	if OS.has_environment("PLANET_PROCEDURAL_WOOD") and DisplayServer.get_name() != "headless":
		var wood := WoodBaker.new() # (the cabins' boards from the fitted generator)
		add_child(wood)
		var tile: Image = await wood.bake("oak_wood_planks")
		tile.generate_mipmaps()
		var boards := FloraMeshes.structure_material()
		boards.set_shader_parameter(&"wood_tile", ImageTexture.create_from_image(tile))
		boards.set_shader_parameter(&"wood_tile_on", 1.0)
		boards.set_shader_parameter(&"wood_tile_m", 1.2)
		wood.queue_free()
	if OS.has_environment("PLANET_PHOTO_BARK") or DisplayServer.get_name() == "headless":
		return # (the photographs for every bark; the procedural oak is the default: AGENT_TASKS/085)
	var baker := BarkBaker.new()
	add_child(baker)
	var array: Texture2DArray = await baker.make_array()
	FloraMeshes.material().set_shader_parameter(&"bark_photo", array)
	FloraMeshes.material().set_shader_parameter(&"tall_slot", 1.0) # (the baked cedar is square)
	if OS.has_environment("PLANET_PROCEDURAL_PALM"):
		FloraMeshes.material().set_shader_parameter(&"tall_palm", 1.0) # (so are the baked rings)
	baker.queue_free()
	if (OS.has_environment("PLANET_PROCEDURAL_ROCKS")
			or OS.has_environment("PLANET_PROCEDURAL_LUMPS")
			or OS.has_environment("PLANET_PROCEDURAL_CELLS")): # (not good enough yet: AGENT_TASKS/084)
		var rocks := RockBaker.new()
		add_child(rocks)
		var rock_array: Texture2DArray = await rocks.make_array()
		FloraMeshes.material().set_shader_parameter(&"rock_photo", rock_array)
		rocks.queue_free()
