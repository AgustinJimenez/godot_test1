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
		var maker := _native()
		if maker != null:
			return mesh_from(maker.mushroom({"height": species.height, "crown": species.crown,
					"droop": species.droop, "count": species.count, "accent": species.accent}, rng.seed,
					detailed))
		PlantGroundBuilders.mushroom(builder, species, rng)
	else: # every other plant is grown by TreeGrower; the small ones always in the light version
		var level := lod if species.is_tree() else maxi(lod, 0 if detailed else 1)
		var genome := TreeArchetypes.for_species(species)
		var native := _native()
		if native != null:
			return mesh_from(native.grow(genome.to_dictionary(), rng.seed, detailed, leafless,
					level, builder.leaf_cards))
		TreeGrower.build(builder, genome, rng, level)
	return builder.commit()


## The cheap horizon version; only trees have one (the others are never drawn that far).
static func build_far(species: PlantSpecies, variant: int) -> ArrayMesh:
	var maker := _native()
	if maker != null:
		return mesh_from(maker.far_tree({"conifer": species.form == PlantSpecies.Form.CONIFER,
				"leaf": species.leaf, "leaf_tip": species.leaf_tip, "bark": species.bark,
				"height": species.height, "crown": species.crown, "aspect": species.aspect,
				"bare": species.bare, "girth": species.girth}, _rng(species, variant + 50).seed))
	var builder := MeshBuilder.new()
	PlantTreeBuilders.far(builder, species, _rng(species, variant + 50))
	return builder.commit()


static func has_far(species: PlantSpecies) -> bool:
	return species.form == PlantSpecies.Form.CONIFER or species.form == PlantSpecies.Form.BROADLEAF


## The native grower, one for each thread (null where the library is not built: the scripts grow the
## plant).
static func _native() -> Object:
	if not ClassDB.class_exists(&"PlantMeshNative"):
		return null
	return ClassDB.instantiate(&"PlantMeshNative")


## The mesh of the arrays a PlantMeshNative call answers with.
static func mesh_from(grown: Dictionary) -> ArrayMesh:
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
	var flags := 0
	var branches: PackedFloat32Array = grown.get("branches", PackedFloat32Array())
	if branches.size() > 10: # one row of ten per branch, the first is the trunk: a plant that can bend
		# CUSTOM0.x: which branch the vertex is on (0: the trunk)
		arrays[Mesh.ARRAY_CUSTOM0] = grown["branch_ids"]
		flags |= Mesh.ARRAY_CUSTOM_R_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {}, flags)
	if branches.size() > 10:
		# parent, level, foot, tip, radius, length of every branch (see PlantMeshNative)
		mesh.set_meta(&"branches", branches)
	# the thick low limbs a person can walk into (the placed trees get colliders from them)
	if grown.has("capsules"):
		mesh.set_meta(&"capsules", grown["capsules"])
	return mesh


static func _rng(species: PlantSpecies, variant: int) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = species.seed * 31 + variant * 104729 + 17
	return rng
