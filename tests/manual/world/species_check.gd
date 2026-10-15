extends Node
## Headless acceptance check of the plant species system (041). Run:
##   godot --headless --path . res://tests/manual/world/species_check.tscn
## Prints SPECIES_CHECK PASS / FAIL lines and quits with 0 (all pass) or 1.

const SEEDS := [1337, 42, 99999]
const TRIANGLE_BUDGET := 12000 ## per mesh, detailed look included

var _failures: Array[String] = []


func _ready() -> void:
	_check_shape_of_the_list()
	_check_determinism()
	_check_coverage()
	_check_meshes()
	for failure in _failures:
		print("SPECIES_CHECK FAIL ", failure)
	print("SPECIES_CHECK ", "PASS" if _failures.is_empty() else "FAIL (%d)" % _failures.size())
	get_tree().quit(0 if _failures.is_empty() else 1)


func _fail(message: String) -> void:
	_failures.append(message)


func _make(seed_value: int, count := 36) -> SpeciesRegistry:
	return SpeciesRegistry.new(seed_value, count)


## 36 species, unique names, every form and every layer present, ids 1..N.
func _check_shape_of_the_list() -> void:
	for seed_value: int in SEEDS:
		var registry := _make(seed_value)
		if registry.species.size() != 36:
			_fail("seed %d: %d species, wanted 36" % [seed_value, registry.species.size()])
		var names := {}
		var forms := {}
		for one in registry.species:
			if names.has(one.common_name):
				_fail("seed %d: duplicate name %s" % [seed_value, one.common_name])
			names[one.common_name] = true
			forms[one.form] = true
		if forms.size() != PlantSpecies.Form.size():
			_fail("seed %d: only %d of %d growth forms" % [
					seed_value, forms.size(), PlantSpecies.Form.size()])
		for layer: int in PlantSpecies.Layer.values():
			if registry.in_layer(layer as PlantSpecies.Layer).is_empty():
				_fail("seed %d: layer %d has no species" % [seed_value, layer])
	for count in [12, 20, 36, 60]:
		if _make(7, count).species.size() != count:
			_fail("count %d did not give %d species" % [count, count])
	var first := _make(1337)
	print("SPECIES seed 1337 (%d):" % first.species.size())
	for one in first.species:
		print("  ", one.summary())


## The same seed twice gives the same species; different seeds give a different world.
func _check_determinism() -> void:
	var summaries: Array[String] = []
	for seed_value: int in SEEDS:
		var first := _summary(_make(seed_value))
		if first != _summary(_make(seed_value)):
			_fail("seed %d: two runs differ" % seed_value)
		summaries.append(first)
	if summaries[0] == summaries[1] or summaries[1] == summaries[2]:
		_fail("different seeds gave identical species")


func _summary(registry: SpeciesRegistry) -> String:
	var lines: Array[String] = []
	for one in registry.species:
		lines.append("%s|%d|%.4f|%s|%s" % [one.summary(), one.seed, one.height, one.leaf.to_html(),
				one.accent.to_html()])
	return "\n".join(lines)


## Over ordinary land (not ice, not open water) every layer finds something that can grow.
func _check_coverage() -> void:
	for seed_value: int in SEEDS:
		var registry := _make(seed_value)
		for layer: int in [PlantSpecies.Layer.CANOPY, PlantSpecies.Layer.GRASS]:
			var covered := 0
			var total := 0
			for wet in [0.3, 0.45, 0.6, 0.75, 0.9]:
				for warm in [0.35, 0.5, 0.65]:
					for above in [4.0, 12.0, 25.0]:
						total += 1
						var best := 0.0
						for one in registry.in_layer(layer as PlantSpecies.Layer):
							best = maxf(best, one.fitness(wet, warm, above, 0.2) * one.density)
						if best > 0.05:
							covered += 1
			if covered < total * 0.8:
				_fail("seed %d layer %d: only %d of %d ordinary spots can grow anything" % [
						seed_value, layer, covered, total])
			print("COVERAGE seed %d layer %d: %d / %d" % [seed_value, layer, covered, total])


## Every species builds a non-empty mesh in both looks, inside the triangle budget.
func _check_meshes() -> void:
	var started := Time.get_ticks_msec()
	var registry := _make(1337)
	var worst := 0
	var meshes := 0
	for one in registry.species:
		for variant in one.variants:
			for detailed in [false, true]:
				var mesh := registry.mesh(one.id, variant, detailed)
				meshes += 1
				var triangles := _triangles(mesh)
				worst = maxi(worst, triangles)
				if triangles == 0:
					_fail("%s variant %d (detailed %s) is empty" % [one.common_name, variant, detailed])
				elif triangles > TRIANGLE_BUDGET:
					_fail("%s variant %d (detailed %s) has %d triangles" % [
							one.common_name, variant, detailed, triangles])
		if PlantMeshes.has_far(one) and _triangles(registry.far_mesh(one.id, 0)) == 0:
			_fail("%s has an empty horizon mesh" % one.common_name)
	print("MESHES %d built in %d ms, most triangles in one: %d" % [meshes,
			Time.get_ticks_msec() - started, worst])


func _triangles(mesh: ArrayMesh) -> int:
	if mesh.get_surface_count() == 0:
		return 0
	return (mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 3
