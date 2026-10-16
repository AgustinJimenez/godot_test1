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
		var level := lod if species.is_tree() else maxi(lod, 1)
		TreeGrower.build(builder, TreeArchetypes.for_species(species), rng, level)
	return builder.commit()


## The cheap horizon version; only trees have one (the others are never drawn that far).
static func build_far(species: PlantSpecies, variant: int) -> ArrayMesh:
	var builder := MeshBuilder.new()
	PlantTreeBuilders.far(builder, species, _rng(species, variant + 50))
	return builder.commit()


static func has_far(species: PlantSpecies) -> bool:
	return species.form == PlantSpecies.Form.CONIFER or species.form == PlantSpecies.Form.BROADLEAF


static func _rng(species: PlantSpecies, variant: int) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = species.seed * 31 + variant * 104729 + 17
	return rng
