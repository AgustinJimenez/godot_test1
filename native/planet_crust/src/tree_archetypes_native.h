#pragma once

// Recognisable kinds of tree, each as a TreeGenome, and the random draw that makes new trees out of them (was
// systems/world_gen/flora/tree_archetypes.gd; the same numbers and the same dice in the same order, so a species grows the same tree).
// Every method is static and bound on the class `TreeArchetypes`. The script's constants NAMES and PLANTS are the static
// methods names() and plants() (a native class cannot carry an array as a constant).

#include "plant_species_native.h"
#include "tree_genome_native.h"

#include <godot_cpp/classes/random_number_generator.hpp>
#include <godot_cpp/classes/ref.hpp>
#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/string.hpp>

namespace godot {

class TreeArchetypes : public RefCounted {
	GDCLASS(TreeArchetypes, RefCounted)

protected:
	static void _bind_methods();

public:
	// Every kind, in the order of the script's NAMES (an Array of Strings), and the low plants among them (PLANTS).
	static Array names();
	static Array plants();

	// The genome of the named kind. `leafy` and `conifer` are the species that give the colours and the base numbers of the two plain kinds.
	static Ref<TreeGenome> make(const String &p_kind, const Ref<PlantSpecies> &p_leafy, const Ref<PlantSpecies> &p_conifer);
	// The genome of a world species: its kind (`archetype`) nudged by its own dice, in its own colours. Always the same for a species.
	static Ref<TreeGenome> for_species(const Ref<PlantSpecies> &p_species);
	// A new random tree from the kinds above (`info` gets one String: what it was made of; `pool`: the kinds drawn from, default all).
	static Ref<TreeGenome> draw(const Ref<RandomNumberGenerator> &p_rng, const Ref<PlantSpecies> &p_leafy, const Ref<PlantSpecies> &p_conifer,
			double p_randomness, double p_exotic, Array p_info, Array p_pool = Array());
	// A new genome between `a` (weight 0) and `b` (weight 1): numbers are mixed, a choice or a flag is taken from one side or the other.
	static Ref<TreeGenome> blend(const Ref<TreeGenome> &p_a, const Ref<TreeGenome> &p_b, double p_weight, const Ref<RandomNumberGenerator> &p_rng);
};

} // namespace godot
