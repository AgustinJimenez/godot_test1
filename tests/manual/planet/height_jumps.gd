## Looks for cliffs the height function should not have: samples random land points along a 100 m line
## at 0.5 m and reports any step over 8 m. Run: godot --headless -s tests/manual/planet/height_jumps.gd -- --seed=8
## (found the erosion noise cliffs of AGENT_TASKS/071: 22 of 596 lines before the fix, none after)
extends SceneTree

func _init() -> void:
	var seed_value := 8
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--seed="):
			seed_value = int(arg.substr(7))
	var settings := PlanetSettings.earth(1.0)
	settings.world_seed = seed_value
	var noise := PlanetNoise.new(settings)
	var rng := RandomNumberGenerator.new()
	rng.seed = 12345
	var bad := 0
	var checked := 0
	var report: PackedStringArray = []
	var step := 0.5 / settings.radius
	for sample in 1400:
		var dir := Vector3(rng.randfn(), rng.randfn(), rng.randfn()).normalized()
		var h0 := noise.height(dir.x, dir.y, dir.z)
		if h0 < -50.0:
			continue # (the deep sea is smooth and slow to ask)
		checked += 1
		var east := dir.cross(Vector3.UP).normalized()
		var prev := h0
		var worst := 0.0
		var worst_at := 0
		for k in range(1, 201):
			var d := (dir + east * k * step).normalized()
			var h := noise.height(d.x, d.y, d.z)
			if absf(h - prev) > worst:
				worst = absf(h - prev)
				worst_at = k
			prev = h
		if worst > 8.0:
			bad += 1
			report.append("  %.5f,%.5f,%.5f jump %.0f m at +%.1f m (h %.0f)" % [dir.x, dir.y, dir.z, worst, worst_at * 0.5, h0])
	print("HEIGHT JUMPS seed ", seed_value, " lines checked ", checked, " with a jump >8 m per 0.5 m: ", bad)
	for line in report.slice(0, 12):
		print(line)
	quit()
