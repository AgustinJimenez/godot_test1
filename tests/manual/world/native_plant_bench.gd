extends SceneTree
## Times the native plant grower against the scripts (godot --headless -s this file).


func _init() -> void:
	var registry := SpeciesRegistry.new(8, 36)
	for detailed in [false, true]:
		var native_ms := 0
		var script_ms := 0
		var native_tris := 0
		var script_tris := 0
		for one in registry.species:
			if one.form == PlantSpecies.Form.MUSHROOM:
				continue
			for variant in 3:
				var rng := RandomNumberGenerator.new()
				rng.seed = one.seed * 31 + variant * 104729 + 17
				var genome := TreeArchetypes.for_species(one)
				var level := 0 if one.is_tree() else 1
				var start := Time.get_ticks_usec()
				var grown: Dictionary = ClassDB.instantiate(&"PlantMeshNative").grow(
						genome.to_dictionary(), rng.seed, detailed, false, level, true)
				native_ms += Time.get_ticks_usec() - start
				native_tris += int(grown["triangles"])
				var builder := MeshBuilder.new()
				builder.detailed = detailed
				start = Time.get_ticks_usec()
				TreeGrower.build(builder, TreeArchetypes.for_species(one), rng, level)
				script_ms += Time.get_ticks_usec() - start
				script_tris += builder.triangle_count()
		print("detailed=%s native %d ms (%d tris), script %d ms (%d tris)" % [detailed,
				native_ms / 1000, native_tris, script_ms / 1000, script_tris])
	quit()
