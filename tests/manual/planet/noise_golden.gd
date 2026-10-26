extends Node
## A golden-number check of the planet's numbers (PlanetNoise and what it owns): prints one line of values for a
## fixed spread of points, and a hash of them. Run before and after changing how they are computed:
##   godot --headless --path . res://tests/manual/planet/noise_golden.tscn [-- --out=PATH]
## writes the values to PATH (one number per line) so two runs can be diffed; prints NOISE_GOLDEN <hash> <count>.


## The hash of the values when this was written (the port of PlanetNoise to C++); update it when the planet's numbers change on purpose.
const EXPECTED := "2a0e912b2726a61d15fe4e0351e99cac"


func _ready() -> void:
	var made := PlanetSettings.new()
	made.world_seed = 4242
	made.radius = 60000.0
	made.hydrology_on = true
	made.drainage_cells = 96
	made.ocean_fraction = 0.6
	var noise := PlanetNoise.create(made)
	var out := PackedStringArray()
	var rng := RandomNumberGenerator.new()
	rng.seed = 99
	var clock := PlanetClock.new()
	clock.day_seconds = made.day_seconds
	clock.year_days = made.year_days
	clock.start(0.3, 14.0, Vector3(0, 0, 1))
	var dirs := PackedVector3Array()
	for index in 120:
		dirs.append(Vector3(rng.randfn(), rng.randfn(), rng.randfn()).normalized())
	for dir in dirs:
		var ground := noise.height(dir.x, dir.y, dir.z)
		out.append("h %.5f" % ground)
		out.append("m %.5f" % noise.macro_height(dir.x, dir.y, dir.z))
		out.append("moist %.5f heat %.5f temp %.5f" % [noise.moisture(dir.x, dir.y, dir.z),
				noise.heat(dir.x, dir.y, dir.z, ground), noise.temperature(dir.x, dir.y, dir.z, ground)])
		out.append("now %.5f detail %.5f" % [noise.temperature_now(dir.x, dir.y, dir.z, ground, clock),
				noise.detail(dir.x, dir.y, dir.z)])
		out.append("biome %d water %.4f near %s" % [noise.biome(dir.x, dir.y, dir.z, ground, 0.3),
				noise.water_at(dir, ground), str(noise.near_water(dir, ground, 20.0))])
		out.append("flow %s" % str(noise.flow_at(dir)))
		out.append("cloud %.5f ready %.5f" % [noise.weather.cloud(dir, clock), noise.weather.readiness(dir, clock)])
		out.append("clim %s tec %.5f" % [str(noise.climate.sample(dir)), noise.tectonics.height(dir)])
		out.append("plate %s" % str(noise.tectonics.plate_at(dir)))
		out.append("weather %s" % str(noise.weather.at(dir, maxf(ground, 0.0), clock)))
	var steeps := PackedFloat32Array()
	for index in dirs.size():
		steeps.append(float(index % 10) * 0.08)
	var grounds := noise.heights_of(dirs)
	var colours := noise.colours_of(dirs, grounds, steeps)
	for index in dirs.size():
		out.append("c %.4f %.4f %.4f g %.4f" % [colours[index].r, colours[index].g, colours[index].b, grounds[index]])
	var macros := noise.macro_heights_of(dirs)
	for value in macros:
		out.append("mh %.4f" % value)
	for value in noise.macro_heights_of(dirs, 500.0):
		out.append("bh %.4f" % value)
	out.append("sea %.6f relief %.3f" % [noise._sea, noise.relief])
	out.append("spawn %s" % str(noise.find_spawn()))
	out.append("solid %s" % str(noise.solid_spawn(Vector3(0.3, 0.8, 0.5).normalized())))
	out.append("desert %s" % str(noise.find_spawn(true)))
	out.append("solid? %s" % str(noise.is_solid_ground(Vector3(0.1, 0.2, 0.97).normalized())))
	var text := "\n".join(out)
	var hash_value := text.md5_text()
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			var file := FileAccess.open(arg.trim_prefix("--out="), FileAccess.WRITE)
			file.store_string(text)
			file.close()
	print("NOISE_GOLDEN %s %s %d" % ["PASS" if hash_value == EXPECTED else "FAIL", hash_value, out.size()])
	get_tree().quit()
