## How stony the planet is: the share of land points by stoniness (godot --headless --path . -s tests/manual/planet/stoniness_check.gd), and a place of middling and of high stoniness to look at
extends SceneTree
func _init() -> void:
	var settings := PlanetSettings.earth()
	settings.world_seed = 8
	var noise := PlanetNoise.new(settings)
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	var cells := 4
	var side := cells + 3
	var counts := [0, 0, 0, 0, 0]
	var total := 0
	var by_area := {}
	for i in 4000:
		var dir := Vector3(rng.randfn(), rng.randfn(), rng.randfn()).normalized()
		var h := noise.height(dir.x, dir.y, dir.z)
		if h < 3.0:
			continue
		var dirs := PackedVector3Array()
		var heights := PackedFloat32Array()
		var normals := PackedVector3Array()
		for k in side * side:
			dirs.append(dir)
			heights.append(h)
			normals.append(Vector3.UP)
		var m: PackedByteArray = noise.native.call(&"ground_materials", dirs, heights, normals, cells)
		var at := (side + 1) * 10
		var stony := float(m[at + 6]) / 255.0
		var bucket := int(clampf(stony * 5.0, 0.0, 4.0))
		counts[bucket] += 1
		if bucket == 4 and not by_area.has("high") and noise.is_solid_ground(dir):
			by_area["high"] = dir
		if bucket == 2 and not by_area.has("mid") and noise.is_solid_ground(dir):
			by_area["mid"] = dir
		total += 1
	print("STONINESS of %d land points (flat ground): 0-0.2 %.0f%%  0.2-0.4 %.0f%%  0.4-0.6 %.0f%%  0.6-0.8 %.0f%%  0.8-1 %.0f%%" % [total,
			counts[0] * 100.0 / total, counts[1] * 100.0 / total, counts[2] * 100.0 / total, counts[3] * 100.0 / total, counts[4] * 100.0 / total])
	for key in by_area:
		var d: Vector3 = by_area[key]
		print("DIR %s %f,%f,%f" % [key, d.x, d.y, d.z])
	quit()
