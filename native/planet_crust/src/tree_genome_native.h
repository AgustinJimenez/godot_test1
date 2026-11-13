#pragma once

// The traits of one tree (was systems/world_gen/flora/tree_genome.gd): everything the tree grower needs. Spruce and oak are not
// different kinds of thing, only different numbers. Every trait is also a bound property (declaration order = the script's, which
// TreeArchetypes.blend relies on for its dice), and to_dictionary() hands them all to PlantMeshNative::grow.

#include "plant_species_native.h"

#include <godot_cpp/classes/ref.hpp>
#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/color.hpp>
#include <godot_cpp/variant/dictionary.hpp>

namespace godot {

// (type, name, variant type): in the order the script declares them.
#define TREE_GENOME_FIELDS(X) \
	X(double, height, Variant::FLOAT) \
	X(double, girth, Variant::FLOAT) \
	X(double, taper, Variant::FLOAT) \
	X(double, lean, Variant::FLOAT) \
	X(bool, leader, Variant::BOOL) \
	X(double, trunk_part, Variant::FLOAT) \
	X(double, column, Variant::FLOAT) \
	X(double, root_flare, Variant::FLOAT) \
	X(int64_t, stems, Variant::INT) \
	X(double, stem_spread, Variant::FLOAT) \
	X(int64_t, flutes, Variant::INT) \
	X(double, flute_depth, Variant::FLOAT) \
	X(double, trunk_bend, Variant::FLOAT) \
	X(double, trunk_lumps, Variant::FLOAT) \
	X(int64_t, roots, Variant::INT) \
	X(double, root_reach, Variant::FLOAT) \
	X(int64_t, trunk_sides, Variant::INT) \
	X(double, trunk_wobble, Variant::FLOAT) \
	X(double, bark_rings, Variant::FLOAT) \
	X(double, bark_rough, Variant::FLOAT) \
	X(double, trunk_dark, Variant::FLOAT) \
	X(bool, marked_bark, Variant::BOOL) \
	X(int64_t, profile, Variant::INT) \
	X(double, crown, Variant::FLOAT) \
	X(double, aspect, Variant::FLOAT) \
	X(double, droop, Variant::FLOAT) \
	X(bool, whorled, Variant::BOOL) \
	X(int64_t, limbs, Variant::INT) \
	X(double, nodes_spacing, Variant::FLOAT) \
	X(double, nodes_from, Variant::FLOAT) \
	X(double, limb_angle, Variant::FLOAT) \
	X(double, limb_length, Variant::FLOAT) \
	X(double, limb_thickness, Variant::FLOAT) \
	X(int64_t, depth, Variant::INT) \
	X(Array, rings, Variant::ARRAY) \
	X(Array, sides, Variant::ARRAY) \
	X(Array, sides_real, Variant::ARRAY) \
	X(Array, curve, Variant::ARRAY) \
	X(bool, avoid, Variant::BOOL) \
	X(double, twist, Variant::FLOAT) \
	X(Array, wander, Variant::ARRAY) \
	X(Array, lift, Variant::ARRAY) \
	X(Array, sag, Variant::ARRAY) \
	X(Array, droop_sag, Variant::ARRAY) \
	X(Array, sway, Variant::ARRAY) \
	X(Array, tip_radius, Variant::ARRAY) \
	X(Array, children, Variant::ARRAY) \
	X(double, twig_radius, Variant::FLOAT) \
	X(double, child_radius, Variant::FLOAT) \
	X(Array, child_length, Variant::ARRAY) \
	X(double, child_length_a, Variant::FLOAT) \
	X(double, child_length_b, Variant::FLOAT) \
	X(double, children_from, Variant::FLOAT) \
	X(double, children_to, Variant::FLOAT) \
	X(bool, children_planar, Variant::BOOL) \
	X(double, child_forward, Variant::FLOAT) \
	X(double, child_side, Variant::FLOAT) \
	X(double, child_up, Variant::FLOAT) \
	X(bool, carry_on, Variant::BOOL) \
	X(double, bury, Variant::FLOAT) \
	X(int64_t, foliage, Variant::INT) \
	X(int64_t, leaf_shape, Variant::INT) \
	X(double, leaf_aspect, Variant::FLOAT) \
	X(double, leaf_size, Variant::FLOAT) \
	X(int64_t, leaf_lobes, Variant::INT) \
	X(int64_t, leaf_edge, Variant::INT) \
	X(int64_t, leaf_pattern, Variant::INT) \
	X(double, needle_size, Variant::FLOAT) \
	X(bool, tips_only, Variant::BOOL) \
	X(int64_t, frond_parts, Variant::INT) \
	X(int64_t, fronds, Variant::INT) \
	X(double, frond_length, Variant::FLOAT) \
	X(double, frond_arch, Variant::FLOAT) \
	X(double, frond_droop, Variant::FLOAT) \
	X(double, leaflet, Variant::FLOAT) \
	X(double, rib_width, Variant::FLOAT) \
	X(Color, flower, Variant::COLOR) \
	X(double, flower_size, Variant::FLOAT) \
	X(Color, flower_centre, Variant::COLOR) \
	X(double, flower_cup, Variant::FLOAT) \
	X(int64_t, petals, Variant::INT) \
	X(Color, blossom, Variant::COLOR) \
	X(int64_t, blossom_kind, Variant::INT) \
	X(double, blossom_size, Variant::FLOAT) \
	X(double, blossom_density, Variant::FLOAT) \
	X(bool, compound, Variant::BOOL) \
	X(double, foliage_mass, Variant::FLOAT) \
	X(double, mass_size, Variant::FLOAT) \
	X(double, leaf_density, Variant::FLOAT) \
	X(Color, bark, Variant::COLOR) \
	X(Color, leaf, Variant::COLOR) \
	X(Color, leaf_tip, Variant::COLOR) \
	X(bool, frosted, Variant::BOOL)

class TreeGenome : public RefCounted {
	GDCLASS(TreeGenome, RefCounted)

protected:
	static void _bind_methods();

public:
	// How far a branch can reach at each height: a cone (long below, short above) or a dome.
	enum Profile { CONE, DOME };
	// How a tree carries blossom: one or two flowers per twig, a hanging stem of them, a round cluster.
	enum Bloom { SINGLE, RACEME, UMBEL };
	// What a branch carries: single leaves, sprays of needles, or (a palm) big fronds.
	enum Foliage { BLADE, NEEDLE, FROND };

	// Trunk
	double height = 8.0; // metres (the grower varies it a little per tree)
	double girth = 0.3; // trunk radius at the foot
	double taper = 0.6; // top radius / foot radius of a trunk that ends in limbs
	double lean = 0.0; // the trunk's lean at the top, as a fraction of the height
	bool leader = false; // one trunk to the top, narrowing to a point
	double trunk_part = 0.3; // the bare part of the trunk, as a fraction of the height
	double column = -1.0; // a leader trunk's radius at the top, as a share of the foot's (-1: a cone)
	double root_flare = 0.0;
	int64_t stems = 1;
	double stem_spread = 0.25;
	int64_t flutes = 0;
	double flute_depth = 0.0;
	double trunk_bend = 0.0;
	double trunk_lumps = 0.0;
	int64_t roots = 0;
	double root_reach = 1.0;
	int64_t trunk_sides = 14;
	double trunk_wobble = 0.05;
	double bark_rings = 0.0;
	double bark_rough = 1.0;
	double trunk_dark = 0.25;
	bool marked_bark = false;

	// Where the branches leave the trunk
	int64_t profile = DOME;
	double crown = 2.0;
	double aspect = 1.0;
	double droop = 0.0;
	bool whorled = false;
	int64_t limbs = 4;
	double nodes_spacing = 0.0;
	double nodes_from = 0.0;
	double limb_angle = 50.0;
	double limb_length = 1.0;
	double limb_thickness = 0.7;

	// Branches, by level (0 limb, 1 branch, 2 twig)
	int64_t depth = 3;
	Array rings; // ints
	Array sides; // ints
	Array sides_real; // ints
	Array curve; // floats
	bool avoid = false;
	double twist = 0.0;
	Array wander;
	Array lift;
	Array sag;
	Array droop_sag;
	Array sway;
	Array tip_radius;
	Array children; // ints
	double twig_radius = 1.0;
	double child_radius = 0.6;
	Array child_length;
	double child_length_a = 1.25;
	double child_length_b = 0.5;
	double children_from = 0.3;
	double children_to = 0.85;
	bool children_planar = false;
	double child_forward = 0.4;
	double child_side = 0.9;
	double child_up = 0.25;
	bool carry_on = true;
	double bury = 0.4;

	// Foliage
	int64_t foliage = BLADE;
	int64_t leaf_shape = PlantSpecies::OVAL;
	double leaf_aspect = 1.8;
	double leaf_size = 0.2;
	int64_t leaf_lobes = 0;
	int64_t leaf_edge = PlantSpecies::SMOOTH;
	int64_t leaf_pattern = PlantSpecies::ALTERNATE;
	double needle_size = 0.45;
	bool tips_only = false;
	int64_t frond_parts = 9;
	int64_t fronds = 14;
	double frond_length = 3.0;
	double frond_arch = 0.5;
	double frond_droop = 0.5;
	double leaflet = 0.22;
	double rib_width = 0.012;
	Color flower = Color(0.0f, 0.0f, 0.0f, 0.0f); // a flower at the tip of each frond (alpha 0: none)
	double flower_size = 0.05;
	Color flower_centre = Color(0.9f, 0.68f, 0.1f);
	double flower_cup = 0.4;
	int64_t petals = 5;
	Color blossom = Color(0.0f, 0.0f, 0.0f, 0.0f); // colour of the blossom on a tree's twigs (alpha 0: none)
	int64_t blossom_kind = SINGLE;
	double blossom_size = 0.07;
	double blossom_density = 0.5;
	bool compound = false;
	double foliage_mass = 0.0;
	double mass_size = 1.0;
	double leaf_density = 1.0;

	// Colours (sRGB)
	Color bark = Color(0.33f, 0.23f, 0.15f);
	Color leaf = Color(0.26f, 0.5f, 0.18f);
	Color leaf_tip = Color(0.4f, 0.6f, 0.25f);
	bool frosted = false;

	TreeGenome();

#define TG_ACCESSORS(TYPE, NAME, VT) \
	TYPE get_##NAME() const { return NAME; } \
	void set_##NAME(TYPE p_value) { NAME = p_value; }
	TREE_GENOME_FIELDS(TG_ACCESSORS)
#undef TG_ACCESSORS

	// Every trait by name, for the native grower (PlantMeshNative reads this).
	Dictionary to_dictionary() const;
	// The names of the traits, in declaration order, and the Variant type of each (for blending).
	static const char *const *field_names(int &r_count);
	static Variant::Type field_type(int p_index);

	// The genome of a leafy or conifer species, as the old builders drew them.
	static Ref<TreeGenome> from_species(const Ref<PlantSpecies> &p_species);
};

} // namespace godot

VARIANT_ENUM_CAST(TreeGenome::Profile);
VARIANT_ENUM_CAST(TreeGenome::Bloom);
VARIANT_ENUM_CAST(TreeGenome::Foliage);
