class_name PlantMeshes
extends RefCounted
## Turns a PlantSpecies into a mesh: picks the builder of its growth form and runs it with the dice
## of that species and variant (so a variant is always the same mesh, and no two variants match).


## `lod` 1: the lighter version of a tree for trees at a distance.
static func build(species: PlantSpecies, variant: int, detailed: bool,
		leafless := false, lod := 0) -> ArrayMesh:
	var rng := _rng(species, variant)
	var builder := MeshBuilder.new()
	builder.detailed = detailed
	builder.leafless = leafless
	if species.form == PlantSpecies.Form.MUSHROOM:
		PlantGroundBuilders.mushroom(builder, species, rng)
	else: # every other plant is grown by TreeGrower; the small ones always in the light version
		var level := lod if species.is_tree() else maxi(lod, 0 if detailed else 1)
		var genome := TreeArchetypes.for_species(species)
		var native := _native()
		if native != null:
			return _from_native(native.grow(genome.to_dictionary(), rng.seed, detailed, leafless,
					level, builder.leaf_cards))
		TreeGrower.build(builder, genome, rng, level)
	return builder.commit()


## The cheap horizon version; only trees have one (the others are never drawn that far).
static func build_far(species: PlantSpecies, variant: int) -> ArrayMesh:
	var builder := MeshBuilder.new()
	PlantTreeBuilders.far(builder, species, _rng(species, variant + 50))
	return builder.commit()


static func has_far(species: PlantSpecies) -> bool:
	return species.form == PlantSpecies.Form.CONIFER or species.form == PlantSpecies.Form.BROADLEAF


## The native grower, one for each thread (null where the library is not built: the scripts grow the plant).
static func _native() -> Object:
	if not ClassDB.class_exists(&"PlantMeshNative"):
		return null
	return ClassDB.instantiate(&"PlantMeshNative")


static func _from_native(grown: Dictionary) -> ArrayMesh:
	var mesh := ArrayMesh.new()
	if int(grown["triangles"]) == 0:
		return mesh
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = grown["vertices"]
	arrays[Mesh.ARRAY_NORMAL] = grown["normals"]
	arrays[Mesh.ARRAY_COLOR] = grown["colors"]
	if not (grown["uvs"] as PackedVector2Array).is_empty():
		arrays[Mesh.ARRAY_TEX_UV] = grown["uvs"]
		arrays[Mesh.ARRAY_TEX_UV2] = grown["uv2s"]
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


static func _rng(species: PlantSpecies, variant: int) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = species.seed * 31 + variant * 104729 + 17
	return rng
