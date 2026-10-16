class_name PlantMeshes
extends RefCounted
## Turns a PlantSpecies into a mesh: picks the builder of its growth form and runs it with the dice
## of that species and variant (so a variant is always the same mesh, and no two variants match).


## Leafy trees and conifers come from the one TreeGrower (traits in a TreeGenome); false draws them
## with the old builders (kept until the new one is checked, see AGENT_TASKS/042).
static var use_tree_grower := true


## `lod` 1: the lighter version of a tree for trees at a distance (other plants ignore it).
static func build(species: PlantSpecies, variant: int, detailed: bool,
		leafless := false, lod := 0) -> ArrayMesh:
	var rng := _rng(species, variant)
	var builder := MeshBuilder.new()
	builder.detailed = detailed
	builder.leafless = leafless
	match species.form:
		PlantSpecies.Form.CONIFER:
			if use_tree_grower:
				TreeGrower.build(builder, TreeArchetypes.for_species(species), rng, lod)
			else:
				PlantConiferBuilders.build(builder, species, rng)
		PlantSpecies.Form.BROADLEAF:
			if use_tree_grower:
				TreeGrower.build(builder, TreeArchetypes.for_species(species), rng, lod)
			else:
				PlantTreeBuilders.broadleaf(builder, species, rng)
		PlantSpecies.Form.PALM, PlantSpecies.Form.BARE_TREE:
			TreeGrower.build(builder, TreeArchetypes.for_species(species), rng, lod)
		PlantSpecies.Form.MUSHROOM:
			PlantGroundBuilders.mushroom(builder, species, rng)
		_: # shrubs, cacti, grasses, reeds, flowers and ferns
			TreeGrower.build(builder, TreeArchetypes.for_species(species), rng, maxi(lod, 1))
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
