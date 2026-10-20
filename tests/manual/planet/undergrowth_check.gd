extends Node
## The undergrowth a walker pushes through: places a tile of plants on wet ground and asks the
## native drag at a shrub, at a
## spot with no plant near, and in the middle of the tile. Prints UNDERGROWTH_CHECK PASS when a
## shrub holds the walker back
## (drag above 0.2), open ground does not (under 0.05) and the numbers stay under 1.
## godot --headless --path . res://tests/manual/planet/undergrowth_check.tscn


func _ready() -> void:
	var settings := PlanetSettings.earth(0.1)
	settings.world_seed = 8
	var noise := PlanetNoise.new(settings)
	var dir := Vector3(-0.665889, -0.723404, 0.182422).normalized()
	var e1 := dir.cross(Vector3.UP).normalized()
	var e3 := e1.cross(dir).normalized()
	var h := noise.height(dir.x, dir.y, dir.z)
	var cells := 48
	var side := cells + 3
	var size := 76.0
	var positions := PackedVector3Array()
	var dirs := PackedVector3Array()
	var heights := PackedFloat32Array()
	for row in side:
		for col in side:
			var x := (float(col - 1) / float(cells) - 0.5) * size
			var z := (float(row - 1) / float(cells) - 0.5) * size
			positions.append(Vector3(x, 0.0, z))
			dirs.append((dir + (e1 * x + e3 * z) / settings.radius).normalized())
			heights.append(h)
	var placed: Dictionary = noise.scatter_native.call(&"scatter", {
		"key": 1, "positions": positions, "dirs": dirs, "heights": heights, "cells": cells, "size": size,
		"detail": 3, "collide": false, "clearing": Vector3.ZERO, "fine": true, "grass_fine": true})
	var stems: PackedFloat32Array = placed["stems"]
	var strongest := 0.0
	var at_strongest := Vector2.ZERO
	for index in stems.size() / 4:
		if stems[index * 4 + 3] > strongest:
			strongest = stems[index * 4 + 3]
			at_strongest = Vector2(stems[index * 4], stems[index * 4 + 1])
	var on_shrub: float = noise.scatter_native.call(&"drag", stems, at_strongest.x, at_strongest.y)
	var far_away: float = noise.scatter_native.call(&"drag", stems, 5000.0, 5000.0)
	var ok := stems.size() > 0 and on_shrub > 0.2 and far_away < 0.05 and on_shrub <= 1.0
	print(("UNDERGROWTH_CHECK %s stems=%d on the thickest stem %.2f (its own drag %.2f), "
			+ "far away %.3f") % [
			"PASS" if ok else "FAIL", stems.size() / 4, on_shrub, strongest, far_away])
	get_tree().quit(0 if ok else 1)
