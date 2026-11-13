#pragma once

// Makes the species of a world from its seed (was systems/world_gen/flora/species_generator.gd): the same seed always
// gives the same list, and the same list as the script gave (the dice are drawn in the script's order). Each growth form
// gets a share of the total (QUOTA); within a form the species are spread over the climate (stratified, so a world never
// ends up with five spruces for the same weather) and each draws its own shape numbers and colours. Nothing here touches
// meshes; PlantMeshes turns a species into one.
//
// `_fit_size` needs the genome of a tree kind: it asks the native `TreeArchetypes` class (static `for_species(species)`
// returning an object with `height`, `girth`, `crown`) at run time by name, so this file does not include it.

#include <godot_cpp/classes/random_number_generator.hpp>
#include <godot_cpp/classes/ref.hpp>
#include <godot_cpp/classes/ref.hpp>
#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/string.hpp>

#include "plant_species_native.h"

namespace godot {

class SpeciesGenerator : public RefCounted {
	GDCLASS(SpeciesGenerator, RefCounted)

protected:
	static void _bind_methods();

public:
	// The species of the world with this seed; `count` is the total (36 by default in WorldSettings). A typed
	// Array[PlantSpecies].
	static Array generate(int64_t p_world_seed, int64_t p_count);
	// The leaf and branching traits of a broadleaf species for the kind of tree `noun` (Oak, Maple, Beech, Elm, Ash,
	// Linden, Poplar, Birch or Willow). Public so a lab can try any kind.
	static void apply_leaf_traits(const Ref<PlantSpecies> &p_species, const String &p_noun, const Ref<RandomNumberGenerator> &p_dice);
};

} // namespace godot
