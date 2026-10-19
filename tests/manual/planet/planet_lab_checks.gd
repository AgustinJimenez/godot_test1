class_name PlanetLabChecks
extends RefCounted
## Checks of the planet lab that need no scene of their own (the lab calls them and quits).


## `--water-check` (headless): water of the crust (rivers and lakes) over a spread of points.
static func water_check(tree: SceneTree) -> bool:
	if not "--water-check" in OS.get_cmdline_user_args():
		return false
	var made := PlanetSettings.new()
	made.hydrology_on = true
	made.drainage_cells = 96 # (the crust cuts the rivers along the drainage)
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--seed="):
			made.world_seed = arg.trim_prefix("--seed=").to_int()
		elif arg.begins_with("--radius="):
			made.radius = arg.trim_prefix("--radius=").to_float()
	var noise := PlanetNoise.new(made)
	# the crust's rivers and lakes: over a spread of points of the planet there is some water (a river here and there,
	# not everywhere), and it is rarely over the sea or under the ground (a river's mouth and its banks, a few in a hundred)
	var points := 0
	var wet := 0
	var over_sea := 0
	var under_ground := 0
	var widest := Vector3.ZERO
	var rng := RandomNumberGenerator.new()
	rng.seed = made.world_seed
	for index in 40000:
		var dir := Vector3(rng.randfn(), rng.randfn(), rng.randfn()).normalized()
		var ground := noise.height(dir.x, dir.y, dir.z)
		points += 1
		var level := noise.water_at(dir, ground)
		if level > -INF:
			wet += 1
			widest = dir
			if ground < 0.0:
				over_sea += 1
			if level < ground - 0.31:
				under_ground += 1
	var verdict := "PASS" if wet > 0 and wet < points / 3 and over_sea + under_ground <= points / 100 else "FAIL"
	print("WATER_CHECK %s points=%d wet=%d over_sea=%d under_ground=%d" % [verdict, points, wet, over_sea,
			under_ground])
	print("RIVER_AT %f,%f,%f" % [widest.x, widest.y, widest.z])
	tree.quit()
	return true
