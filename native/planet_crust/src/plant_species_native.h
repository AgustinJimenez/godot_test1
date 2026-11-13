#pragma once

// One species of plant in one world (was systems/world_gen/flora/plant_species.gd): every number that decides what
// its plants look like and where they grow. SpeciesGenerator makes them from the world seed and nothing edits them
// afterwards, so any thread may read them. Public members are also bound as properties, so scripts (and the native
// placement, through Object::get) read them by name as before.

#include <godot_cpp/classes/ref.hpp>
#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/color.hpp>
#include <godot_cpp/variant/packed_string_array.hpp>
#include <godot_cpp/variant/string.hpp>
#include <godot_cpp/variant/vector2.hpp>

namespace godot {

#define PLANT_SPECIES_FIELDS(X) 	X(int64_t, id, Variant::INT) 	X(String, common_name, Variant::STRING) 	X(int64_t, form, Variant::INT) 	X(int64_t, seed, Variant::INT) 	X(int64_t, variants, Variant::INT) 	X(String, archetype, Variant::STRING) 	X(double, height, Variant::FLOAT) 	X(double, girth, Variant::FLOAT) 	X(double, crown, Variant::FLOAT) 	X(double, aspect, Variant::FLOAT) 	X(double, bare, Variant::FLOAT) 	X(double, taper, Variant::FLOAT) 	X(int64_t, count, Variant::INT) 	X(int64_t, extra, Variant::INT) 	X(double, droop, Variant::FLOAT) 	X(double, lean, Variant::FLOAT) 	X(double, wobble, Variant::FLOAT) 	X(double, size_spread, Variant::FLOAT) 	X(bool, marked_bark, Variant::BOOL) 	X(bool, frosted, Variant::BOOL) 	X(int64_t, leaf_shape, Variant::INT) 	X(int64_t, leaf_pattern, Variant::INT) 	X(double, leaf_aspect, Variant::FLOAT) 	X(double, leaf_size, Variant::FLOAT) 	X(int64_t, leaf_lobes, Variant::INT) 	X(int64_t, leaf_edge, Variant::INT) 	X(int64_t, limb_count, Variant::INT) 	X(double, limb_angle, Variant::FLOAT) 	X(Color, leaf, Variant::COLOR) 	X(Color, leaf_tip, Variant::COLOR) 	X(Color, bark, Variant::COLOR) 	X(Color, accent, Variant::COLOR) 	X(double, moisture, Variant::FLOAT) 	X(double, moisture_tol, Variant::FLOAT) 	X(double, heat, Variant::FLOAT) 	X(double, heat_tol, Variant::FLOAT) 	X(double, above_min, Variant::FLOAT) 	X(double, above_max, Variant::FLOAT) 	X(double, slope_max, Variant::FLOAT) 	X(double, density, Variant::FLOAT) 	X(double, patch_freq, Variant::FLOAT) 	X(double, patch_strength, Variant::FLOAT) 	X(Vector2, patch_offset, Variant::VECTOR2)

class PlantSpecies : public RefCounted {
	GDCLASS(PlantSpecies, RefCounted)

protected:
	static void _bind_methods();

public:
	enum Form {
		CONIFER, BROADLEAF, PALM, BARE_TREE, SHRUB, CACTUS, GRASS, TALL_GRASS, REED, FLOWER, FERN, MUSHROOM,
	};
	// The outline of one leaf of a broadleaf tree (see PlantLeafShapes).
	enum LeafShape { OVAL, LOBED, PALMATE, HEART, LANCEOLATE, DIAMOND };
	// The edge of a leaf (the realistic look draws it; low-poly leaves keep a clean edge).
	enum LeafEdge { SMOOTH, SERRATED, WAVY };
	// How leaves sit along a twig: one per node on alternating sides, two opposite, or in a spiral.
	enum LeafPattern { ALTERNATE, OPPOSITE, SPIRAL };
	// Plants are scattered one layer at a time, each on its own grid spacing. (GRASSLAND: GRASS is a Form's name too.)
	enum Layer { CANOPY, UNDERSTORY, GRASSLAND, MEADOW, COVER };

	int64_t id = 0; // 1.. in generation order; stable for a seed
	String common_name;
	int64_t form = BROADLEAF;
	int64_t seed = 0; // the dice of its meshes
	int64_t variants = 3; // how many different meshes it makes
	String archetype; // the kind of tree it is (TreeArchetypes.NAMES), picked by its climate; "" none

	// Shape. Metres at scale 1.
	double height = 8.0; // whole plant (grass: blade length, mushroom: cap stalk)
	double girth = 0.3; // trunk radius at the base (grass: blade half width)
	double crown = 2.0; // crown radius (palm: frond length, shrub: lump size, flower: petal length)
	double aspect = 1.0; // broadleaf crown height / width
	double bare = 0.3; // fraction of the height that is bare trunk
	double taper = 0.6; // top trunk radius / base radius
	int64_t count = 5; // tiers, crown lumps, fronds, blades, petals or caps, by form
	int64_t extra = 0; // berries, arms, stems per clump, seed heads: by form
	double droop = 0.3; // weeping crowns, bending blades and fronds
	double lean = 0.0; // trunk lean as a fraction of the height
	double wobble = 0.12; // how irregular the mesh is
	double size_spread = 0.25; // +- size difference between individuals
	bool marked_bark = false; // dark patches on pale bark
	bool frosted = false; // white snow on the leaves (cold species)

	// Broadleaf crown: branches and single leaves (TreeGenome.from_species).
	int64_t leaf_shape = OVAL;
	int64_t leaf_pattern = ALTERNATE;
	double leaf_aspect = 1.8; // leaf length / leaf width
	double leaf_size = 0.2; // leaf length as a fraction of the crown radius
	int64_t leaf_lobes = 0; // lobes per side (lobed leaves)
	int64_t leaf_edge = SMOOTH;
	int64_t limb_count = 4; // main limbs leaving the trunk top
	double limb_angle = 50.0; // degrees from vertical the limbs leave at

	// Colours (sRGB, like the old palette).
	Color leaf = Color(0.26, 0.5, 0.18);
	Color leaf_tip = Color(0.4, 0.6, 0.25);
	Color bark = Color(0.33, 0.23, 0.15);
	Color accent = Color(1, 1, 1); // flowers, berries, caps, seed heads

	// Niche: where it grows. 0..1 moisture and heat (TerrainNoise), metres above the local water level.
	double moisture = 0.5;
	double moisture_tol = 0.3;
	double heat = 0.5;
	double heat_tol = 0.3;
	double above_min = 1.5;
	double above_max = 60.0;
	double slope_max = 0.5;
	double density = 0.5; // chance a spot is planted where the fit is perfect
	double patch_freq = 0.05; // 1 / metres of the clumps it grows in
	double patch_strength = 0.0; // 0 even .. 1 only inside the clumps
	Vector2 patch_offset; // decorrelates one species' clumps from the next

#define PS_ACCESSORS(TYPE, NAME, VT) 	TYPE get_##NAME() const { return NAME; } 	void set_##NAME(TYPE p_value) { NAME = p_value; }
	PLANT_SPECIES_FIELDS(PS_ACCESSORS)
#undef PS_ACCESSORS

	static PackedStringArray form_names(); // the Form names in enum order (a native enum has no keys())
	int64_t layer() const;
	bool is_tree() const;
	// 0 where it cannot live .. 1 at its ideal spot.
	double fitness(double p_wet, double p_warm, double p_above, double p_steep) const;
	// Radius and height of the trunk collider; Vector2.ZERO when walking through it is fine.
	Vector2 footprint() const;
	String summary() const;
};

} // namespace godot

VARIANT_ENUM_CAST(PlantSpecies::Form);
VARIANT_ENUM_CAST(PlantSpecies::LeafShape);
VARIANT_ENUM_CAST(PlantSpecies::LeafEdge);
VARIANT_ENUM_CAST(PlantSpecies::LeafPattern);
VARIANT_ENUM_CAST(PlantSpecies::Layer);
