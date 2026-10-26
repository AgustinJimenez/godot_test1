## Looks for walls and knife edges: samples land lines of 120 m at 1 m and reports where the ground
## climbs more than
## 2.2 m in 1 m (a 65 degree wall) or its slope changes by more than 1.6 within 2 m (a knife edge).
## Run: godot --headless -s tests/manual/planet/steep_walls.gd -- --seed=8 [--scale=0.1]
extends SceneTree

func _init() -> void:
	var seed_value := 8
	var scale := 0.1
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--seed="):
			seed_value = int(arg.substr(7))
		elif arg.begins_with("--scale="):
			scale = float(arg.substr(8))
	var settings := PlanetSettings.earth(scale)
	settings.world_seed = seed_value
	var noise := PlanetNoise.create(settings)
	var rng := RandomNumberGenerator.new()
	rng.seed = 777
	var walls := 0
	var edges := 0
	var checked := 0
	var report: PackedStringArray = []
	var step := 1.0 / settings.radius
	for sample in 1500:
		var dir := Vector3(rng.randfn(), rng.randfn(), rng.randfn()).normalized()
		var h0 := noise.height(dir.x, dir.y, dir.z)
		if h0 < 30.0:
			continue
		checked += 1
		var east := dir.cross(Vector3.UP).normalized()
		var prev := h0
		var prev_slope := 0.0
		var steepest := 0.0
		var sharpest := 0.0
		var at_wall := 0
		var at_edge := 0
		for k in range(1, 121):
			var d := (dir + east * k * step).normalized()
			var h := noise.height(d.x, d.y, d.z)
			var slope := h - prev
			if absf(slope) > steepest:
				steepest = absf(slope)
				at_wall = k
			if k > 1 and absf(slope - prev_slope) > sharpest:
				sharpest = absf(slope - prev_slope)
				at_edge = k
			prev = h
			prev_slope = slope
		if steepest > 2.2:
			walls += 1
		if sharpest > 1.6:
			edges += 1
		if steepest > 2.2 or sharpest > 1.6:
			var profile := ""
			for q in range(maxi(at_wall - 4, 1), mini(at_wall + 5, 121)):
				var dq := (dir + east * q * step).normalized()
				profile += " %.1f" % noise.height(dq.x, dq.y, dq.z)
			report.append(profile)
			report.append("  %.8f,%.8f,%.8f wall %.1f m/m at +%d, kink %.1f at +%d (h %.0f)" % [dir.x, dir.y,
					dir.z, steepest, at_wall, sharpest, at_edge, h0])
	print(("STEEP WALLS seed %d scale %.2f: %d land lines, %d with a wall over 65 degrees, "
			+ "%d with a knife edge") % [seed_value, scale, checked, walls, edges])
	for line in report.slice(0, 10):
		print(line)
	quit()
