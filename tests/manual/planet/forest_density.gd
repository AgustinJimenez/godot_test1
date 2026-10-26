extends Node
## How many plants of each layer a hectare gets at several wetnesses (seed 8): godot --headless
## --path . res://tests/manual/planet/forest_density.tscn


func _ready() -> void:
	var settings := PlanetSettings.earth()
	settings.world_seed = 8
	var noise := PlanetNoise.create(settings)
	var spots := {0.30: Vector3(0.216485,-0.689424,-0.691251), 0.45: Vector3(-0.063721,0.401967,
			0.913434),
			0.60: Vector3(-0.765716,-0.586536,0.263922), 0.85: Vector3(-0.665889,-0.723404,0.182422)}
	var cells := 48
	var side := cells + 3
	var size := 76.0
	for wet: float in spots:
		var dir: Vector3 = spots[wet].normalized()
		var e1 := dir.cross(Vector3.UP).normalized()
		var e3 := e1.cross(dir).normalized()
		var h := noise.height(dir.x, dir.y, dir.z)
		var totals := {"trees": 0, "shrubs": 0, "grass": 0, "flowers": 0, "cover": 0}
		var tiles := 0
		# a 6 x 6 block of tiles round the spot
		for tx in range(-1, 2):
			for tz in range(-1, 2):
				var positions := PackedVector3Array()
				var dirs := PackedVector3Array()
				var heights := PackedFloat32Array()
				for row in side:
					for col in side:
						var x := (float(col - 1) / float(cells) + tx) * size
						var z := (float(row - 1) / float(cells) + tz) * size
						positions.append(Vector3(x, 0.0, z))
						dirs.append((dir + (e1 * x + e3 * z) / settings.radius).normalized())
						heights.append(h)
				var placed: Dictionary = noise.scatter_native.call(&"scatter", {
					"key": tx * 100 + tz, "positions": positions, "dirs": dirs, "heights": heights,
					"cells": cells, "size": size, "detail": 3, "collide": false, "clearing": Vector3.ZERO,
					"fine": true, "grass_fine": true})
				tiles += 1
				var keys: PackedInt32Array = placed["keys"]
				for index in keys.size():
					var key := keys[index]
					if key < 100000 or key >= 200000:
						continue
					var one = noise.species.by_id((key - 100000) / 100)
					var count: int = (placed["buffers"][index] as PackedFloat32Array).size() / 16
					match one.layer():
						PlantSpecies.Layer.CANOPY: totals["trees"] += count
						PlantSpecies.Layer.UNDERSTORY: totals["shrubs"] += count
						PlantSpecies.Layer.GRASS: totals["grass"] += count
						PlantSpecies.Layer.MEADOW: totals["flowers"] += count
						_: totals["cover"] += count
		var per_hectare := 10000.0 / (size * size * tiles)
		print(("WET %.2f at %.0f m: per hectare  trees %.1f  shrubs %.1f  grass tufts %.0f  "
				+ "flowers %.1f  cover %.1f") % [wet, h,
				totals["trees"] * per_hectare, totals["shrubs"] * per_hectare, totals["grass"] * per_hectare,
				totals["flowers"] * per_hectare, totals["cover"] * per_hectare])
	get_tree().quit()
