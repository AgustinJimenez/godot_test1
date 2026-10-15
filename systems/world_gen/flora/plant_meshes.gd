class_name PlantMeshes
extends RefCounted
## Turns a PlantSpecies into a mesh: picks the builder of its growth form and runs it with the dice
## of that species and variant (so a variant is always the same mesh, and no two variants match).


static func build(species: PlantSpecies, variant: int, detailed: bool,
		leafless := false) -> ArrayMesh:
	var rng := _rng(species, variant)
	var builder := MeshBuilder.new()
	builder.detailed = detailed
	builder.leafless = leafless
	match species.form:
		PlantSpecies.Form.CONIFER:
			PlantConiferBuilders.build(builder, species, rng)
		PlantSpecies.Form.BROADLEAF:
			PlantTreeBuilders.broadleaf(builder, species, rng)
		PlantSpecies.Form.PALM:
			PlantTreeBuilders.palm(builder, species, rng)
		PlantSpecies.Form.BARE_TREE:
			PlantTreeBuilders.bare_tree(builder, species, rng)
		PlantSpecies.Form.SHRUB:
			PlantGroundBuilders.shrub(builder, species, rng)
		PlantSpecies.Form.CACTUS:
			PlantGroundBuilders.cactus(builder, species, rng)
		PlantSpecies.Form.GRASS, PlantSpecies.Form.TALL_GRASS:
			PlantGroundBuilders.grass(builder, species, rng)
		PlantSpecies.Form.REED:
			PlantGroundBuilders.reed(builder, species, rng)
		PlantSpecies.Form.FLOWER:
			PlantGroundBuilders.flower(builder, species, rng)
		PlantSpecies.Form.FERN:
			PlantGroundBuilders.fern(builder, species, rng)
		PlantSpecies.Form.MUSHROOM:
			PlantGroundBuilders.mushroom(builder, species, rng)
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
