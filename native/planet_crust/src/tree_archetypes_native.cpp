#include "tree_archetypes_native.h"

#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/core/math.hpp>

#include <cstring>

using namespace godot;

namespace {

Array ints3(int64_t p_a, int64_t p_b, int64_t p_c) {
	Array out;
	out.push_back(p_a);
	out.push_back(p_b);
	out.push_back(p_c);
	return out;
}
Array nums3(double p_a, double p_b, double p_c) {
	Array out;
	out.push_back(p_a);
	out.push_back(p_b);
	out.push_back(p_c);
	return out;
}

const char *const NAME_LIST[] = { "leafy", "conifer", "umbrella", "giant", "oak", "ancient", "dragon",
	"willow", "cypress", "bush", "shrub", "groundcover",
	"clump", "palm",
	"dead", "cactus", "fern", "grass", "lawn", "meadow", "reed", "pampas", "tussock", "wildflower",
	"cherry", "blossom",
	"raintree", "buttress" };
const char *const PLANT_LIST[] = { "shrub", "groundcover", "fern", "grass", "lawn", "meadow", "reed",
	"pampas", "tussock", "wildflower" };

// Plausible range of each numeric trait: [min, max]. A draw never leaves it. (The order is the script's: the dice are thrown in it.)
struct Range {
	const char *name;
	double low;
	double high;
};
const Range RANGES[] = {
	{ "height", 0.1, 45.0 }, { "girth", 0.01, 2.6 }, { "taper", 0.25, 0.95 }, { "lean", 0.0, 0.3 },
	{ "trunk_part", 0.05, 1.0 }, { "root_flare", 0.0, 1.0 }, { "crown", 0.15, 14.0 },
	{ "aspect", 0.4, 2.0 }, { "droop", 0.0, 1.0 }, { "limbs", 3, 10 }, { "flutes", 0, 8 },
	{ "foliage_mass", 0.0, 1.0 },
	{ "flute_depth", 0.0, 0.4 }, { "trunk_bend", 0.0, 1.0 },
	{ "trunk_lumps", 0.0, 1.0 }, { "roots", 0, 10 }, { "root_reach", 0.5, 3.0 }, { "twist", 0.0, 1.0 },
	{ "stems", 1, 6 },
	{ "stem_spread", 0.05, 0.5 }, { "limb_angle", 15.0, 90.0 },
	{ "limb_length", 0.5, 3.0 }, { "limb_thickness", 0.3, 1.3 }, { "nodes_spacing", 0.3, 2.0 },
	{ "curve", 0.0, 1.4 }, { "lift", -0.1, 0.4 }, { "sag", 0.0, 0.3 }, { "tip_radius", 0.05, 0.8 },
	{ "children", 1, 7 }, { "twig_radius", 0.2, 1.0 }, { "child_radius", 0.3, 0.9 },
	{ "child_length", 0.2, 0.9 },
	{ "child_forward", 0.0, 1.5 }, { "child_side", 0.0, 1.5 }, { "child_up", -0.5, 1.0 },
	{ "leaf_aspect", 0.8, 5.0 }, { "leaf_size", 0.08, 0.45 }, { "needle_size", 0.2, 1.5 },
	{ "leaf_density", 0.0, 1.0 }, { "rib_width", 0.005, 0.06 }, { "flower_size", 0.02, 0.15 },
	{ "bark_rough", 0.5, 3.0 }, { "petals", 4, 10 }, { "flower_cup", 0.0, 1.0 },
	{ "blossom_size", 0.03, 0.4 }, { "blossom_density", 0.1, 1.0 }, { "fronds", 6, 24 },
	{ "frond_length", 0.2, 8.0 },
	{ "frond_arch", 0.1, 1.0 }, { "frond_droop", 0.1, 1.0 }, { "leaflet", 0.0, 0.4 },
};
// Sizes that vary by proportion (a bush and a giant both change by a few percent, not by metres).
const char *const PROPORTIONAL[] = { "height", "girth", "crown", "frond_length", "leaflet", "rib_width" };
// Traits that are a choice from a list, not a number (blended by picking one side).
const char *const CHOICES[] = { "blossom_kind", "leaf_shape", "leaf_edge", "leaf_pattern", "foliage", "profile" };

template <size_t N>
bool in_list(const char *const (&p_list)[N], const char *p_name) {
	for (size_t i = 0; i < N; i++) {
		if (std::strcmp(p_list[i], p_name) == 0) {
			return true;
		}
	}
	return false;
}

// (randf_range answers a float in some builds and a double in others)
double rr(const Ref<RandomNumberGenerator> &p_rng, double p_from, double p_to) {
	return (double)p_rng->randf_range(p_from, p_to);
}

int64_t roundi(double p_value) {
	return (int64_t)Math::round(p_value);
}

double clampf(double p_value, double p_low, double p_high) {
	return p_value < p_low ? p_low : (p_value > p_high ? p_high : p_value);
}

double lerpf(double p_from, double p_to, double p_weight) {
	return p_from + (p_to - p_from) * p_weight;
}

// Every numeric trait moved a little (by `amount` of its range): a proportion for the sizes, a share of the range for the rest.
Variant moved(const Variant &p_value, double p_low, double p_high, const Ref<RandomNumberGenerator> &p_rng, double p_amount, bool p_proportional) {
	if (p_proportional) {
		const double shift = rr(p_rng, -1.0, 1.0);
		return clampf((double)p_value * Math::exp(shift * p_amount * 2.5), p_low, p_high);
	}
	const double shift = rr(p_rng, -1.0, 1.0);
	const double result = clampf((double)p_value + shift * (p_high - p_low) * p_amount, p_low, p_high);
	if (p_value.get_type() == Variant::INT) {
		return roundi(result);
	}
	return result;
}

// A real tree is not a clean model: now and then a crooked trunk, swellings, a few roots, and a fluted foot.
void imperfect(TreeGenome &g, const Ref<RandomNumberGenerator> &p_rng, double p_chance) {
	if (g.height < 3.0 || g.foliage == TreeGenome::FROND) {
		return;
	}
	if (p_rng->randf() < p_chance) {
		g.trunk_lumps = Math::max(g.trunk_lumps, rr(p_rng, 0.2, 0.8));
	}
	if (p_rng->randf() < p_chance * 0.7) {
		g.trunk_bend = Math::max(g.trunk_bend, rr(p_rng, 0.1, 0.5));
	}
	if (g.girth > 0.5 && p_rng->randf() < p_chance) {
		g.roots = Math::max(g.roots, (int64_t)p_rng->randi_range(4, 8));
		g.root_reach = Math::max(g.root_reach, rr(p_rng, 0.7, 2.0));
	}
	if (g.girth > 0.8 && p_rng->randf() < p_chance * 0.5) {
		g.flutes = Math::max(g.flutes, (int64_t)p_rng->randi_range(4, 7));
		g.flute_depth = Math::max(g.flute_depth, rr(p_rng, 0.12, 0.3));
	}
}

// Every flowering plant its own flowers: colour, petal count, flat or cupped, the middle.
void vary_flowers(TreeGenome &g, const Ref<RandomNumberGenerator> &p_rng) {
	if (g.flower.a > 0.0f) {
		const double hue = p_rng->randf();
		const double saturation = rr(p_rng, 0.0, 0.9);
		const double value = rr(p_rng, 0.8, 1.0);
		g.flower = Color::from_hsv((float)hue, (float)saturation, (float)value);
		g.petals = p_rng->randi_range(4, 10);
		const double first = p_rng->randf();
		const double second = p_rng->randf();
		g.flower_cup = first * second * 1.0; // mostly open, now and then a tulip
		g.flower_size = g.flower_size * rr(p_rng, 0.7, 1.5);
	}
	if (g.blossom.a > 0.0f) {
		const double hue = rr(p_rng, 0.0, 1.0);
		const double saturation = rr(p_rng, 0.0, 0.6);
		const double value = rr(p_rng, 0.85, 1.0);
		g.blossom = Color::from_hsv((float)hue, (float)saturation, (float)value);
		g.petals = p_rng->randi_range(4, 8);
		g.blossom_kind = (int64_t)(p_rng->randi() % 3);
	}
	const Color centres[4] = { Color(0.9f, 0.68f, 0.1f), Color(0.55f, 0.35f, 0.1f), Color(0.95f, 0.9f, 0.7f), Color(0.7f, 0.2f, 0.2f) };
	g.flower_centre = centres[p_rng->randi() % 4];
}

// Every numeric trait moved a little (by `amount` of its range), the colours too.
void nudge(TreeGenome &g, const Ref<RandomNumberGenerator> &p_rng, double p_amount) {
	for (const Range &range : RANGES) {
		const StringName key(range.name);
		Variant value = g.get(key);
		if (value.get_type() == Variant::ARRAY) {
			Array arr = value; // (the genome's own array: the elements are moved in place)
			for (int index = 0; index < arr.size(); index++) {
				arr[index] = moved(arr[index], range.low, range.high, p_rng, p_amount, false);
			}
		} else {
			g.set(key, moved(value, range.low, range.high, p_rng, p_amount, in_list(PROPORTIONAL, range.name)));
		}
	}
	const double hue_shift = rr(p_rng, -0.04, 0.04);
	const double hue = Math::fposmod((double)g.leaf.get_h() + hue_shift * p_amount * 5.0, 1.0);
	const double saturation_shift = rr(p_rng, -0.1, 0.1);
	const double saturation = clampf((double)g.leaf.get_s() + saturation_shift, 0.3, 0.9);
	const double value_shift = rr(p_rng, -0.08, 0.08);
	const double value = clampf((double)g.leaf.get_v() + value_shift, 0.2, 0.7);
	g.leaf = Color::from_hsv((float)hue, (float)saturation, (float)value);
	g.leaf_tip = g.leaf.lightened(0.15f);
	g.bark = g.bark.lightened((float)rr(p_rng, -0.08, 0.08));
	vary_flowers(g, p_rng);
	imperfect(g, p_rng, p_amount * 5.0);
}

// One trait pushed somewhere unusual; returns what it did (for the label).
String exotic(TreeGenome &g, const Ref<RandomNumberGenerator> &p_rng) {
	switch (p_rng->randi() % 7) {
		case 6:
			g.blossom = Color(1, 1, 1, 1);
			g.blossom_kind = (int64_t)(p_rng->randi() % 3);
			return "in blossom";
		case 0:
			g.foliage = TreeGenome::NEEDLE;
			g.tips_only = true;
			g.leader = false;
			g.whorled = false;
			return "tufts at the tips";
		case 1:
			g.leader = !g.leader;
			g.whorled = g.leader;
			return g.leader ? "trunk to the top" : "forking trunk";
		case 2:
			g.leaf_shape = (int64_t)(p_rng->randi() % 6);
			g.leaf_edge = (int64_t)(p_rng->randi() % 3);
			return "other leaves";
		case 3:
			g.leaf_density = rr(p_rng, 0.2, 0.6);
			return "sparse leaves";
		case 4:
			g.limb_length = rr(p_rng, 1.3, 1.9);
			g.crown = Math::min(g.crown * 1.3, 10.0);
			return "very wide";
		default:
			g.girth = Math::min(g.girth * rr(p_rng, 1.5, 2.2), 2.6);
			g.root_flare = rr(p_rng, 0.4, 0.9);
			return "very thick trunk";
	}
}

// Makes the traits agree with each other after a blend or a nudge.
void settle(TreeGenome &g) {
	if (g.leader) {
		g.whorled = true;
		g.profile = TreeGenome::CONE;
		if (g.foliage == TreeGenome::BLADE) {
			g.nodes_spacing = Math::max(g.nodes_spacing, 1.0); // single leaves are costly: few whorls
		}
	}
	if (g.foliage == TreeGenome::FROND) {
		g.leader = false;
		g.trunk_part = Math::max(g.trunk_part, 0.9);
		g.frond_length = Math::max(g.frond_length, g.height * 0.2);
	}
	if (g.leaf_shape == PlantSpecies::LOBED && g.leaf_lobes == 0) {
		g.leaf_lobes = 2;
	}
	// branches never shorter than a share of the height, or they look stitched to the trunk
	g.crown = Math::max(g.crown, g.height * (g.leader ? 0.12 : 0.1));
	g.limbs = (int64_t)clampf((double)g.limbs, 3.0, 10.0);
	g.depth = g.depth > 3 ? 3 : Math::max(g.depth, (int64_t)2);
	g.nodes_from = clampf(g.nodes_from, 0.02, 0.9);
}

} // namespace

void TreeArchetypes::_bind_methods() {
	ClassDB::bind_static_method("TreeArchetypes", D_METHOD("names"), &TreeArchetypes::names);
	ClassDB::bind_static_method("TreeArchetypes", D_METHOD("plants"), &TreeArchetypes::plants);
	ClassDB::bind_static_method("TreeArchetypes", D_METHOD("make", "kind", "leafy", "conifer"), &TreeArchetypes::make);
	ClassDB::bind_static_method("TreeArchetypes", D_METHOD("for_species", "species"), &TreeArchetypes::for_species);
	ClassDB::bind_static_method("TreeArchetypes", D_METHOD("draw", "rng", "leafy", "conifer", "randomness", "exotic", "info", "pool"), &TreeArchetypes::draw, DEFVAL(Array()));
	ClassDB::bind_static_method("TreeArchetypes", D_METHOD("blend", "a", "b", "weight", "rng"), &TreeArchetypes::blend);
}

Array TreeArchetypes::names() {
	Array out;
	for (const char *name : NAME_LIST) {
		out.push_back(String(name));
	}
	return out;
}

Array TreeArchetypes::plants() {
	Array out;
	for (const char *name : PLANT_LIST) {
		out.push_back(String(name));
	}
	return out;
}

Ref<TreeGenome> TreeArchetypes::make(const String &p_kind, const Ref<PlantSpecies> &p_leafy, const Ref<PlantSpecies> &p_conifer) {
	const String kind = p_kind;
	Ref<TreeGenome> made;
	if (kind == "conifer") {
		made = TreeGenome::from_species(p_conifer);
	} else if (kind == "giant") {
		made = TreeGenome::from_species(p_conifer);
		TreeGenome &g = *made.ptr();
		g.height = 42.0;
		g.girth = 2.0;
		g.root_flare = 0.7;
		g.column = 0.22;
		g.trunk_part = 0.5;
		g.nodes_from = 0.5;
		g.crown = 5.0;
		g.nodes_spacing = 1.8;
		g.limbs = 5;
		g.droop = 0.5;
	} else if (kind == "cypress") {
		made = TreeGenome::from_species(p_conifer);
		TreeGenome &g = *made.ptr();
		g.height = 16.0;
		g.girth = 0.5;
		g.column = 0.3;
		g.trunk_part = 0.05;
		g.nodes_from = 0.08;
		g.crown = 1.9;
		g.nodes_spacing = 0.6;
		g.limbs = 4;
		g.droop = 0.0;
	} else if (kind == "umbrella") {
		made = TreeGenome::from_species(p_leafy);
		TreeGenome &g = *made.ptr();
		g.height = 14.0;
		g.girth = 1.45;
		g.taper = 0.8;
		g.trunk_part = 0.5;
		g.root_flare = 0.2;
		g.crown = 4.0;
		g.aspect = 0.45;
		g.limbs = 5;
		g.limb_angle = 82.0;
		g.limb_length = 1.1;
		g.limb_thickness = 0.8;
		g.curve = nums3(0.5, 0.9, 1.2);
		g.lift = nums3(0.05, 0.04, 0.0);
		g.leaf_size = 0.16;
	} else if (kind == "oak") {
		made = TreeGenome::from_species(p_leafy);
		TreeGenome &g = *made.ptr();
		// measured on a reference oak pack: trunk radius about 3% of the height, forks at 15 to 25% of it, the crown as wide as it is
		// tall (radius about 45% of the height), its widest at a third up
		g.height = 12.0;
		g.girth = 0.5;
		g.taper = 0.7;
		g.trunk_part = 0.3;
		g.root_flare = 0.25;
		g.crown = 5.2;
		g.aspect = 0.85;
		g.limbs = 7;
		g.limb_angle = 78.0;
		g.limb_length = 1.2;
		g.limb_thickness = 0.85;
		g.avoid = true;
		g.curve = nums3(1.2, 1.2, 1.4);
		g.lift = nums3(0.14, 0.05, 0.0);
		g.sag = nums3(0.0, 0.03, 0.08);
		g.leaf_size = 0.14;
	} else if (kind == "ancient") {
		// an ancient live oak (the Angel Oak): a huge short trunk, limbs as thick as small trees that wind out sideways and almost
		// touch the ground, thick branches off them
		made = make("oak", p_leafy, p_conifer);
		TreeGenome &g = *made.ptr();
		g.height = 14.0;
		g.girth = 2.0;
		g.taper = 0.78;
		g.trunk_part = 0.3;
		g.root_flare = 0.55;
		g.crown = 5.0;
		g.limbs = 7;
		g.limb_angle = 84.0;
		g.limb_length = 1.45;
		g.limb_thickness = 1.0;
		g.leaf_density = 0.6;
		g.leaf_size = 0.14;
		g.leaf_shape = PlantSpecies::OVAL;
		g.leaf_edge = PlantSpecies::SMOOTH;
		g.leaf_aspect = 2.2;
		g.leaf = Color(0.16f, 0.34f, 0.12f);
		g.leaf_tip = Color(0.26f, 0.44f, 0.17f);
		g.twist = 0.6;
		g.foliage_mass = 1.0;
		g.mass_size = 2.2;
		g.avoid = true;
		g.limb_length = 2.3;
		g.rings = ints3(5, 4, 3);
		g.sides = ints3(7, 5, 4);
		g.sides_real = ints3(9, 6, 4);
		g.curve = nums3(1.3, 1.3, 1.5);
		g.lift = nums3(0.07, 0.02, 0.0);
		g.child_up = 0.0;
		g.aspect = 0.35;
		g.sag = nums3(0.0, 0.03, 0.08);
		g.tip_radius = nums3(0.85, 0.75, 0.15);
		g.child_radius = 0.75;
		g.twig_radius = 0.4;
		g.children = ints3(6, 5, 0);
		g.child_length = nums3(0.7, 0.55, 0.0);
		g.children_from = 0.15;
		g.roots = 8;
		g.root_reach = 1.4;
		g.trunk_lumps = 0.6;
		g.trunk_bend = 0.3;
		g.flutes = 5;
		g.flute_depth = 0.22;
		g.bark = Color(0.3f, 0.3f, 0.2f);
	} else if (kind == "willow") {
		made = TreeGenome::from_species(p_leafy);
		TreeGenome &g = *made.ptr();
		// a reference willow is 24 m tall and 32 m wide, leafy to within 1.5 m of the ground
		g.height = 11.0;
		g.girth = 0.45;
		g.trunk_part = 0.13;
		g.crown = 6.4;
		g.limbs = 5;
		g.limb_angle = 58.0;
		g.droop = 0.9;
		g.leaf_shape = PlantSpecies::LANCEOLATE;
		g.leaf_aspect = 4.5;
		g.leaf_size = 0.17;
		g.leaf_pattern = PlantSpecies::SPIRAL;
		g.sag = nums3(0.05, 0.1, 0.2);
	} else if (kind == "bush") {
		// almost no trunk: many thin stems fanning out from the ground
		made = TreeGenome::from_species(p_leafy);
		TreeGenome &g = *made.ptr();
		g.height = 1.6;
		g.girth = 0.035;
		g.taper = 1.0;
		g.trunk_part = 0.05;
		g.root_flare = 0.0;
		g.crown = 0.8;
		g.aspect = 1.2;
		g.limbs = 10;
		g.limb_angle = 38.0;
		g.limb_length = 1.0;
		g.limb_thickness = 1.0;
		g.trunk_sides = 6;
		g.leaf_size = 0.2;
		g.bark = Color(0.36f, 0.28f, 0.2f);
	} else if (kind == "palm") {
		// one bare leaning trunk, a crown of long arching fronds
		made = TreeGenome::from_species(p_leafy);
		TreeGenome &g = *made.ptr();
		g.height = 9.0;
		g.girth = 0.22;
		g.taper = 0.7;
		g.lean = 0.1;
		g.trunk_part = 0.97;
		g.foliage = TreeGenome::FROND;
		g.fronds = 14;
		g.frond_length = 3.2;
		g.frond_arch = 0.5;
		g.frond_droop = 0.6;
		g.leaflet = 0.2;
		g.bark = Color(0.45f, 0.36f, 0.26f);
		g.bark_rings = 0.4;
		g.leaf = Color(0.22f, 0.45f, 0.16f);
		g.leaf_tip = Color(0.36f, 0.58f, 0.22f);
	} else if (kind == "dead") {
		// a dead tree: grey, rough, bare crooked limbs
		made = make("oak", p_leafy, p_conifer);
		TreeGenome &g = *made.ptr();
		g.height = 9.0;
		g.girth = 0.45;
		g.taper = 0.55;
		g.trunk_part = 0.3;
		g.crown = 3.2;
		g.limbs = 5;
		g.limb_angle = 55.0;
		g.limb_length = 1.0;
		g.curve = nums3(1.0, 1.2, 1.4);
		g.leaf_density = 0.0;
		g.bark = Color(0.42f, 0.38f, 0.34f);
		g.bark_rough = 1.8;
	} else if (kind == "cactus") {
		// a candelabra cactus: a short thick green trunk, arms that turn up
		made = TreeGenome::from_species(p_leafy);
		TreeGenome &g = *made.ptr();
		g.height = 5.0;
		g.girth = 0.28;
		g.taper = 0.9;
		g.trunk_part = 0.35;
		g.crown = 1.5;
		g.aspect = 1.0;
		g.limbs = 3;
		g.limb_angle = 85.0;
		g.limb_length = 1.1;
		g.limb_thickness = 0.7;
		g.depth = 1;
		g.rings = ints3(5, 3, 2);
		g.sides = ints3(8, 5, 4);
		g.sides_real = ints3(10, 6, 4);
		g.curve = nums3(1.3, 0.0, 0.0);
		g.lift = nums3(1.2, 0.0, 0.0);
		g.tip_radius = nums3(0.9, 0.9, 0.9);
		g.trunk_sides = 8;
		g.trunk_dark = 0.1;
		g.bark_rough = 0.3;
		g.leaf_density = 0.0;
		g.bark = Color(0.25f, 0.45f, 0.25f);
	} else if (kind == "fern" || kind == "grass" || kind == "lawn" || kind == "meadow" || kind == "reed" || kind == "pampas" || kind == "tussock" || kind == "wildflower") {
		// low plants of fronds or blades straight from the ground
		made = make("palm", p_leafy, p_conifer);
		TreeGenome &g = *made.ptr();
		g.height = 0.12;
		g.girth = 0.01;
		g.taper = 1.0;
		g.lean = 0.0;
		g.bark_rings = 0.0;
		g.bark = Color(0.3f, 0.4f, 0.2f);
		if (kind == "fern") {
			g.fronds = 11;
			g.frond_length = 0.7;
			g.frond_arch = 0.9;
			g.frond_droop = 0.8;
			g.leaflet = 0.28;
			g.leaf = Color(0.2f, 0.5f, 0.2f);
			g.leaf_tip = Color(0.32f, 0.62f, 0.26f);
		} else if (kind == "lawn") {
			g.fronds = 60;
			g.frond_length = 0.14;
			g.frond_arch = 0.2;
			g.frond_droop = 0.5;
			g.leaflet = 0.0;
			g.rib_width = 0.05;
			g.leaf = Color(0.3f, 0.5f, 0.15f);
			g.leaf_tip = Color(0.42f, 0.62f, 0.22f);
		} else if (kind == "meadow") {
			g.fronds = 26;
			g.frond_length = 0.9;
			g.frond_arch = 0.35;
			g.frond_droop = 0.7;
			g.leaflet = 0.0;
			g.rib_width = 0.025;
			g.leaf = Color(0.42f, 0.55f, 0.2f);
			g.leaf_tip = Color(0.7f, 0.68f, 0.35f);
		} else if (kind == "reed") {
			g.fronds = 16;
			g.frond_length = 1.8;
			g.frond_arch = 0.6;
			g.frond_droop = 0.25;
			g.leaflet = 0.0;
			g.rib_width = 0.03;
			g.leaf = Color(0.3f, 0.45f, 0.16f);
			g.leaf_tip = Color(0.5f, 0.6f, 0.25f);
		} else if (kind == "pampas") {
			g.fronds = 40;
			g.frond_length = 1.5;
			g.frond_arch = 0.5;
			g.frond_droop = 0.85;
			g.leaflet = 0.0;
			g.rib_width = 0.02;
			g.leaf = Color(0.45f, 0.55f, 0.25f);
			g.leaf_tip = Color(0.75f, 0.72f, 0.45f);
			g.flower = Color(0.93f, 0.9f, 0.78f, 1.0f);
			g.flower_size = 0.1;
			g.flower_cup = 0.9;
		} else if (kind == "tussock") {
			g.fronds = 50;
			g.frond_length = 0.6;
			g.frond_arch = 0.3;
			g.frond_droop = 0.95;
			g.leaflet = 0.0;
			g.rib_width = 0.02;
			g.leaf = Color(0.5f, 0.5f, 0.2f);
			g.leaf_tip = Color(0.78f, 0.66f, 0.3f);
		} else if (kind == "grass") {
			g.fronds = 34;
			g.frond_length = 0.5;
			g.frond_arch = 0.25;
			g.frond_droop = 0.4;
			g.leaflet = 0.0;
			g.rib_width = 0.035;
			g.leaf = Color(0.4f, 0.55f, 0.18f);
			g.leaf_tip = Color(0.58f, 0.68f, 0.28f);
		} else {
			g.fronds = 7;
			g.frond_length = 0.5;
			g.frond_arch = 0.1;
			g.frond_droop = 0.0;
			g.leaflet = 0.0;
			g.rib_width = 0.035;
			g.leaf = Color(0.35f, 0.52f, 0.2f);
			g.leaf_tip = Color(0.5f, 0.65f, 0.28f);
			g.flower = Color(0.95f, 0.8f, 0.2f, 1.0f);
			g.flower_size = 0.08;
		}
	} else if (kind == "raintree") {
		// a rain tree: a short thick trunk, then a vast dome of feathery leaves on spreading limbs
		made = make("umbrella", p_leafy, p_conifer);
		TreeGenome &g = *made.ptr();
		g.height = 22.0;
		g.girth = 1.3;
		g.trunk_part = 0.3;
		g.crown = 7.5;
		g.aspect = 0.6;
		g.limbs = 6;
		g.limb_angle = 68.0;
		g.limb_length = 1.25;
		g.limb_thickness = 0.9;
		g.avoid = true;
		g.compound = true;
		g.foliage_mass = 0.7;
		g.mass_size = 0.5; // pads the size of a hand of leaves, not a door
		g.leaf_size = 0.28;
		g.leaf = Color(0.3f, 0.5f, 0.14f);
		g.leaf_tip = Color(0.45f, 0.65f, 0.22f);
		g.bark = Color(0.28f, 0.22f, 0.17f);
		g.children = ints3(4, 3, 0);
		g.rings = ints3(5, 4, 3);
		g.sides = ints3(6, 5, 4);
		g.sides_real = ints3(8, 6, 4);
		g.roots = 5;
		g.root_reach = 0.8;
		g.trunk_lumps = 0.4;
	} else if (kind == "buttress") {
		// an old swamp-type tree: a fluted trunk, widening into roots that run over the ground, bumpy and crooked, several stems
		// growing together
		made = TreeGenome::from_species(p_leafy);
		TreeGenome &g = *made.ptr();
		g.height = 20.0;
		g.girth = 1.0;
		g.taper = 0.5;
		g.trunk_part = 0.55;
		g.crown = 4.5;
		g.stems = 2;
		g.stem_spread = 0.1;
		g.flutes = 6;
		g.flute_depth = 0.28;
		g.roots = 8;
		g.root_reach = 1.6;
		g.root_flare = 0.6;
		g.trunk_lumps = 0.7;
		g.trunk_bend = 0.25;
		g.bark = Color(0.45f, 0.33f, 0.24f);
		g.leaf_size = 0.26;
	} else if (kind == "cherry" || kind == "blossom") {
		// a tree in flower: a bird cherry's hanging white stems, or a spring tree with pink blossom covering bare twigs
		made = TreeGenome::from_species(p_leafy);
		TreeGenome &g = *made.ptr();
		const bool cherry = kind == "cherry";
		g.height = cherry ? 9.0 : 6.5;
		g.girth = 0.3;
		g.crown = cherry ? 3.0 : 3.4;
		g.leaf_density = cherry ? 0.45 : 0.15;
		g.leaf_size = 0.14;
		g.petals = 5;
		g.leaf = Color(0.3f, 0.5f, 0.2f);
		g.leaf_tip = Color(0.42f, 0.6f, 0.28f);
		g.blossom_size = cherry ? 0.14 : 0.26;
		if (cherry) {
			g.blossom = Color(0.97f, 0.97f, 0.95f, 1.0f);
			g.blossom_kind = TreeGenome::RACEME;
			g.blossom_density = 1.0;
			g.flower_cup = 0.15;
		} else {
			g.blossom = Color(0.98f, 0.7f, 0.78f, 1.0f);
			g.blossom_kind = TreeGenome::SINGLE;
			g.blossom_density = 0.9;
			g.flower_cup = 0.3;
		}
	} else if (kind == "clump") {
		// a birch or hazel clump: several slim stems from one root
		made = TreeGenome::from_species(p_leafy);
		TreeGenome &g = *made.ptr();
		g.height = 10.0;
		g.girth = 0.14;
		g.taper = 0.6;
		g.stems = 4;
		g.stem_spread = 0.22;
		g.trunk_part = 0.55;
		g.crown = 1.7;
		g.limbs = 4;
		g.limb_angle = 35.0;
		g.leaf_size = 0.15;
		g.bark = Color(0.78f, 0.74f, 0.68f);
		g.marked_bark = true;
	} else if (kind == "shrub" || kind == "groundcover") {
		// knee-high and below: many fine stems, small leaves
		made = make("bush", p_leafy, p_conifer);
		TreeGenome &g = *made.ptr();
		const bool low = kind == "groundcover";
		g.height = low ? 0.3 : 0.7;
		g.girth = low ? 0.012 : 0.02;
		g.crown = low ? 0.3 : 0.45;
		g.aspect = low ? 0.8 : 1.0;
		g.limbs = low ? 8 : 9;
		g.limb_angle = low ? 65.0 : 50.0;
		g.leaf_size = low ? 0.12 : 0.15;
	} else if (kind == "dragon") {
		// thick trunk, limbs that fork again and again into an umbrella of bare branches, the leaves only in a tuft layer at the very ends
		made = TreeGenome::from_species(p_conifer);
		TreeGenome &g = *made.ptr();
		g.leader = false;
		g.whorled = false;
		g.profile = TreeGenome::DOME;
		g.foliage = TreeGenome::NEEDLE;
		g.tips_only = true;
		g.carry_on = true;
		g.children_planar = false;
		g.frosted = false;
		g.depth = 3;
		g.rings = ints3(5, 4, 3);
		g.sides = ints3(9, 6, 4);
		g.sides_real = ints3(11, 8, 5);
		g.curve = nums3(0.4, 0.5, 0.6);
		g.wander = nums3(0.05, 0.05, 0.05);
		g.lift = nums3(0.1, 0.1, 0.0);
		g.sag = nums3(0.0, 0.0, 0.0);
		g.droop_sag = nums3(0.0, 0.0, 0.0);
		g.sway = nums3(0.16, 0.2, 0.22);
		g.tip_radius = nums3(0.4, 0.3, 0.1);
		g.children = ints3(7, 7, 0);
		g.child_length = nums3(0.5, 0.45, 0.0);
		g.child_forward = 0.8;
		g.child_side = 0.55;
		g.child_up = 0.25;
		g.child_radius = 0.7;
		g.height = 9.0;
		g.girth = 1.3;
		g.taper = 0.75;
		g.trunk_part = 0.55;
		g.root_flare = 0.1;
		g.column = -1.0;
		g.trunk_sides = 14;
		g.crown = 4.6;
		g.aspect = 0.5;
		g.limbs = 8;
		g.limb_angle = 66.0;
		g.limb_length = 1.2;
		g.limb_thickness = 0.8;
		g.needle_size = 1.0;
		g.bark = Color(0.55f, 0.45f, 0.38f);
		g.leaf = Color(0.38f, 0.45f, 0.16f);
		g.leaf_tip = Color(0.55f, 0.6f, 0.25f);
	} else {
		made = TreeGenome::from_species(p_leafy); // "leafy" and anything unknown
	}
	return made;
}

Ref<TreeGenome> TreeArchetypes::for_species(const Ref<PlantSpecies> &p_species) {
	ERR_FAIL_COND_V(p_species.is_null(), Ref<TreeGenome>());
	const PlantSpecies &s = *p_species.ptr();
	if (s.archetype == String("")) {
		return TreeGenome::from_species(p_species);
	}
	Ref<TreeGenome> made = make(s.archetype, p_species, p_species);
	TreeGenome &g = *made.ptr();
	Ref<RandomNumberGenerator> rng;
	rng.instantiate();
	rng->set_seed(s.seed ^ 0x7A11);
	nudge(g, rng, 0.08);
	if (s.archetype != String("cactus") && s.archetype != String("dead")) {
		g.leaf = s.leaf;
		g.leaf_tip = s.leaf_tip;
		g.bark = s.bark;
	}
	g.frosted = s.frosted;
	if (g.flower.a > 0.0f) {
		g.flower = s.accent;
	}
	if (!s.is_tree()) {
		g.frond_parts = 4; // a world has thousands of these: short, few
		g.fronds = Math::min(g.fronds, (int64_t)16);
		if (g.leaflet < 0.02) { // a blade of grass: wider, stands straighter
			g.rib_width = Math::max(g.rib_width * 2.0, 0.05);
			g.frond_droop *= 0.5;
		}
	}
	settle(g);
	return made;
}

Ref<TreeGenome> TreeArchetypes::draw(const Ref<RandomNumberGenerator> &p_rng, const Ref<PlantSpecies> &p_leafy, const Ref<PlantSpecies> &p_conifer,
		double p_randomness, double p_exotic, Array p_info, Array p_pool) {
	Array kinds = p_pool.is_empty() ? names() : p_pool;
	const int64_t count = kinds.size();
	const String first = kinds[(int64_t)(p_rng->randi() % count)];
	Ref<TreeGenome> made = make(first, p_leafy, p_conifer);
	String recipe = first;
	if (p_rng->randf() < 0.25 + 0.6 * p_randomness) {
		const String second = kinds[(int64_t)(p_rng->randi() % count)];
		if (second != first) {
			const double weight = rr(p_rng, 0.2, 0.8);
			made = blend(made, make(second, p_leafy, p_conifer), weight, p_rng);
			recipe = first + String(" ") + String::num((1.0 - weight) * 100.0, 0) + String("% + ") + second + String(" ") + String::num(weight * 100.0, 0) + String("%");
		}
	}
	nudge(*made.ptr(), p_rng, 0.04 + 0.2 * p_randomness);
	if (p_rng->randf() < p_exotic) {
		recipe += String(" + ") + exotic(*made.ptr(), p_rng);
	}
	settle(*made.ptr());
	p_info.clear();
	p_info.append(recipe);
	return made;
}

Ref<TreeGenome> TreeArchetypes::blend(const Ref<TreeGenome> &p_a, const Ref<TreeGenome> &p_b, double p_weight, const Ref<RandomNumberGenerator> &p_rng) {
	Ref<TreeGenome> out;
	out.instantiate();
	ERR_FAIL_COND_V(p_a.is_null() || p_b.is_null(), out);
	int count = 0;
	const char *const *field_names = TreeGenome::field_names(count);
	for (int i = 0; i < count; i++) {
		const char *name = field_names[i];
		const StringName key(name);
		const Variant from_a = p_a->get(key);
		const Variant from_b = p_b->get(key);
		const bool pick_b = p_rng->randf() < p_weight;
		switch (from_a.get_type()) {
			case Variant::FLOAT:
				out->set(key, lerpf((double)from_a, (double)from_b, p_weight));
				break;
			case Variant::INT:
				if (in_list(CHOICES, name)) {
					out->set(key, pick_b ? from_b : from_a);
				} else {
					out->set(key, roundi(lerpf((double)from_a, (double)from_b, p_weight)));
				}
				break;
			case Variant::BOOL:
				out->set(key, pick_b ? from_b : from_a);
				break;
			case Variant::COLOR:
				out->set(key, ((Color)from_a).lerp((Color)from_b, (float)p_weight));
				break;
			case Variant::ARRAY: {
				Array source_a = from_a;
				Array source_b = from_b;
				Array mixed = source_a.duplicate();
				for (int index = 0; index < mixed.size(); index++) {
					const Variant low = source_a[index];
					const Variant high = source_b[index];
					if (low.get_type() == Variant::INT) {
						mixed[index] = roundi(lerpf((double)low, (double)high, p_weight));
					} else {
						mixed[index] = lerpf((double)low, (double)high, p_weight);
					}
				}
				out->set(key, mixed);
			} break;
			default:
				break;
		}
	}
	return out;
}
