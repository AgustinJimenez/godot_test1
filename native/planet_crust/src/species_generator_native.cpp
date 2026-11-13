#include "species_generator_native.h"

#include <godot_cpp/classes/class_db_singleton.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/core/math.hpp>
#include <godot_cpp/variant/color.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/utility_functions.hpp>
#include <godot_cpp/variant/vector2.hpp>
#include <godot_cpp/variant/vector3i.hpp>

#include <algorithm>
#include <cmath>
#include <utility>
#include <vector>

using namespace godot;

namespace {

typedef Ref<RandomNumberGenerator> Dice;
typedef Ref<PlantSpecies> Species;

// Every random draw below is its own statement: GDScript evaluates arguments left to right, C++ does not.
double rr(const Dice &p_rng, double p_from, double p_to) {
	return p_rng->randf_range(p_from, p_to);
}

int64_t ri(const Dice &p_rng, int p_from, int p_to) {
	return p_rng->randi_range(p_from, p_to);
}

double lerpf(double p_from, double p_to, double p_weight) {
	return p_from + (p_to - p_from) * p_weight;
}

double clampf(double p_x, double p_from, double p_to) {
	return p_x < p_from ? p_from : (p_x > p_to ? p_to : p_x);
}

double smoothstep(double p_from, double p_to, double p_x) {
	if (Math::is_equal_approx(p_from, p_to)) {
		return p_from;
	}
	const double s = clampf((p_x - p_from) / (p_to - p_from), 0.0, 1.0);
	return s * s * (3.0 - 2.0 * s);
}

// How many of each form a 36-species world has; other totals scale these shares. (In the script's QUOTA order.)
const int FORM_COUNT = 12;
const int FORM_ORDER[FORM_COUNT] = {
	PlantSpecies::CONIFER, PlantSpecies::BROADLEAF, PlantSpecies::PALM, PlantSpecies::BARE_TREE, PlantSpecies::SHRUB,
	PlantSpecies::CACTUS, PlantSpecies::GRASS, PlantSpecies::TALL_GRASS, PlantSpecies::REED, PlantSpecies::FLOWER,
	PlantSpecies::FERN, PlantSpecies::MUSHROOM
};
const int QUOTA[FORM_COUNT] = { 3, 4, 1, 1, 6, 2, 4, 2, 2, 6, 3, 2 };

// Every tree species' height times this (the crown and trunk widen with the square root of it, so they do not look thin).
const double TREE_TALLER = 1.35;

// What a kind of tree is called (the name of a kind that has its own).
bool kind_noun(const String &p_kind, String &r_noun) {
	static const char *kinds[][2] = {
		{ "umbrella", "Acacia" }, { "dragon", "Dragon Tree" }, { "raintree", "Rain Tree" }, { "buttress", "Fig" },
		{ "willow", "Willow" }, { "cherry", "Cherry" }, { "blossom", "Plum" }, { "ancient", "Live Oak" },
		{ "oak", "Oak" }, { "cypress", "Cypress" }, { "giant", "Redwood" }
	};
	for (const auto &pair : kinds) {
		if (p_kind == String(pair[0])) {
			r_noun = String(pair[1]);
			return true;
		}
	}
	return false;
}

std::vector<String> nouns_of(int64_t p_form) {
	switch (p_form) {
		case PlantSpecies::CONIFER:
			return { "Spruce", "Fir", "Pine", "Cedar", "Hemlock", "Larch" };
		case PlantSpecies::BROADLEAF:
			return { "Oak", "Maple", "Beech", "Ash", "Elm", "Linden", "Poplar" };
		case PlantSpecies::PALM:
			return { "Palm", "Coconut Palm", "Fan Palm" };
		case PlantSpecies::BARE_TREE:
			return { "Snag", "Dead Tree", "Bare Tree" };
		case PlantSpecies::SHRUB:
			return { "Bush", "Hazel", "Bramble", "Juniper", "Broom", "Elder", "Holly", "Gorse" };
		case PlantSpecies::CACTUS:
			return { "Cactus", "Saguaro", "Barrel Cactus", "Prickly Pear" };
		case PlantSpecies::GRASS:
			return { "Grass", "Fescue", "Bluegrass", "Ryegrass", "Meadow Grass" };
		case PlantSpecies::TALL_GRASS:
			return { "Tallgrass", "Wheatgrass", "Pampas Grass", "Switchgrass" };
		case PlantSpecies::REED:
			return { "Reed", "Rush", "Cattail", "Sedge" };
		case PlantSpecies::FLOWER:
			return { "Daisy", "Buttercup", "Violet", "Poppy", "Cornflower", "Clover", "Aster", "Lupine", "Marigold" };
		case PlantSpecies::FERN:
			return { "Fern", "Bracken", "Shield Fern", "Lady Fern" };
		default: // MUSHROOM
			return { "Toadstool", "Cap", "Bolete", "Puffball" };
	}
}

const std::vector<String> &adjectives_cold() {
	static const std::vector<String> list = { "Northern", "Alpine", "Frost", "Boreal", "Snow" };
	return list;
}
const std::vector<String> &adjectives_hot() {
	static const std::vector<String> list = { "Southern", "Sun", "Desert", "Dry" };
	return list;
}
const std::vector<String> &adjectives_wet() {
	static const std::vector<String> list = { "Marsh", "River", "Mist", "Bog", "Water" };
	return list;
}
const std::vector<String> &adjectives_plain() {
	static const std::vector<String> list = { "Common", "Golden", "Silver", "Pale", "Dark", "Red", "Old", "Wild", "Little",
		"Great", "Mountain", "Meadow", "Woodland" };
	return list;
}

// A colour: hue, saturation and value are clamped like the script's _hsv.
Color hsv(double p_hue, double p_saturation, double p_value) {
	return Color::from_hsv((float)Math::fposmod(p_hue, 1.0), (float)clampf(p_saturation, 0.0, 1.0), (float)clampf(p_value, 0.0, 1.0));
}

// A colour with hue, saturation and value each drawn from a range (in that order).
Color rhsv(const Dice &p_rng, double p_hue_from, double p_hue_to, double p_sat_from, double p_sat_to, double p_val_from, double p_val_to) {
	const double hue = rr(p_rng, p_hue_from, p_hue_to);
	const double saturation = rr(p_rng, p_sat_from, p_sat_to);
	const double value = rr(p_rng, p_val_from, p_val_to);
	return hsv(hue, saturation, value);
}

// A flower or berry colour: anywhere on the wheel except the greens.
Color bright(const Dice &p_rng) {
	double hue = p_rng->randf();
	while (hue > 0.2 && hue < 0.45) {
		hue = p_rng->randf();
	}
	const double saturation = rr(p_rng, 0.55, 0.95);
	const double value = rr(p_rng, 0.8, 1.0);
	return hsv(hue, saturation, value);
}

// Shares of `count` by QUOTA (largest remainder, so the shares always add up to `count`).
void quotas_of(int64_t p_count, int r_shares[FORM_COUNT]) {
	int total = 0;
	for (int i = 0; i < FORM_COUNT; i++) {
		total += QUOTA[i];
	}
	std::vector<Vector2> remainders;
	int64_t given = 0;
	for (int i = 0; i < FORM_COUNT; i++) {
		const double exact = double(QUOTA[i]) * double(p_count) / double(total);
		r_shares[i] = (int)exact;
		given += (int)exact;
		remainders.push_back(Vector2((real_t)(exact - std::floor(exact)), (real_t)FORM_ORDER[i]));
	}
	// (a stable sort: GDScript's sort_custom on this few elements is an insertion sort, which keeps ties in order)
	std::stable_sort(remainders.begin(), remainders.end(), [](const Vector2 &a, const Vector2 &b) { return a.x > b.x; });
	const int64_t extra = p_count - given > 0 ? p_count - given : 0;
	for (int64_t index = 0; index < extra; index++) {
		const int form = (int)remainders[index % remainders.size()].y;
		for (int i = 0; i < FORM_COUNT; i++) {
			if (FORM_ORDER[i] == form) {
				r_shares[i] += 1;
			}
		}
	}
}

// Where it grows. `t` (0..1) spreads the species of one form along the form's main climate axis.
void niche(PlantSpecies &s, const Dice &rng, double t) {
	switch (s.form) {
		case PlantSpecies::CONIFER:
			s.heat = lerpf(0.12, 0.55, t);
			s.heat_tol = rr(rng, 0.14, 0.22);
			s.moisture = rr(rng, 0.4, 0.85);
			s.moisture_tol = rr(rng, 0.22, 0.35);
			s.above_min = 2.0;
			s.above_max = 70.0;
			s.slope_max = 0.58;
			s.density = 0.3 + 0.5 * clampf(t * 1.5, 0.0, 1.0);
			s.patch_freq = rr(rng, 1.4, 2.2);
			s.patch_strength = rr(rng, 0.0, 0.3);
			break;
		case PlantSpecies::BROADLEAF:
			s.moisture = lerpf(0.35, 0.92, t);
			s.moisture_tol = rr(rng, 0.22, 0.32);
			s.heat = rr(rng, 0.42, 0.8);
			s.heat_tol = rr(rng, 0.16, 0.26);
			s.above_min = 2.0;
			s.above_max = 45.0;
			s.slope_max = 0.55;
			s.density = lerpf(0.2, 0.85, t);
			s.patch_freq = rr(rng, 1.4, 2.2);
			s.patch_strength = rr(rng, 0.0, 0.35);
			break;
		case PlantSpecies::PALM:
			s.heat = rr(rng, 0.65, 0.8);
			s.heat_tol = 0.2;
			s.moisture = 0.4;
			s.moisture_tol = 0.6;
			s.above_min = 0.9;
			s.above_max = 3.6;
			s.slope_max = 0.4;
			s.density = 0.2;
			break;
		case PlantSpecies::BARE_TREE:
			s.heat = 0.5;
			s.heat_tol = 0.55;
			s.moisture = rr(rng, 0.3, 0.6);
			s.moisture_tol = 0.7;
			s.above_min = 1.0;
			s.above_max = 70.0;
			s.slope_max = 0.58;
			s.density = 0.07;
			s.patch_freq = 2.0;
			s.patch_strength = 0.4;
			break;
		case PlantSpecies::SHRUB:
			s.moisture = lerpf(0.3, 0.9, t);
			s.moisture_tol = rr(rng, 0.2, 0.32);
			s.heat = rr(rng, 0.3, 0.8);
			s.heat_tol = rr(rng, 0.2, 0.35);
			s.above_min = 1.5;
			s.above_max = 55.0;
			s.slope_max = 0.5;
			s.density = lerpf(0.14, 0.4, t);
			s.patch_freq = rr(rng, 1.6, 2.6);
			s.patch_strength = rr(rng, 0.0, 0.4);
			break;
		case PlantSpecies::CACTUS:
			s.heat = rr(rng, 0.62, 0.95);
			s.heat_tol = 0.25;
			s.moisture = lerpf(0.02, 0.3, t);
			s.moisture_tol = 0.2;
			s.above_min = 2.0;
			s.above_max = 40.0;
			s.slope_max = 0.5;
			s.density = rr(rng, 0.14, 0.24);
			break;
		case PlantSpecies::GRASS:
			s.moisture = lerpf(0.25, 0.9, t);
			s.moisture_tol = rr(rng, 0.25, 0.36);
			s.heat = rr(rng, 0.35, 0.75);
			s.heat_tol = rr(rng, 0.3, 0.45);
			s.above_min = 1.4;
			s.above_max = rr(rng, 28.0, 46.0);
			s.slope_max = 0.55;
			s.density = lerpf(0.3, 0.95, smoothstep(0.0, 0.7, t));
			s.patch_freq = rr(rng, 0.8, 1.6);
			s.patch_strength = rr(rng, 0.2, 0.5);
			break;
		case PlantSpecies::TALL_GRASS:
			s.moisture = lerpf(0.32, 0.7, t);
			s.moisture_tol = 0.25;
			s.heat = rr(rng, 0.4, 0.75);
			s.heat_tol = 0.3;
			s.above_min = 1.5;
			s.above_max = 35.0;
			s.slope_max = 0.5;
			s.density = rr(rng, 0.4, 0.55);
			s.patch_freq = rr(rng, 1.6, 2.2);
			s.patch_strength = 0.9;
			break;
		case PlantSpecies::REED:
			s.moisture = lerpf(0.6, 1.0, t);
			s.moisture_tol = 0.4;
			s.heat = rr(rng, 0.3, 0.8);
			s.heat_tol = 0.4;
			s.above_min = 0.9;
			s.above_max = 3.4;
			s.slope_max = 0.5;
			s.density = rr(rng, 0.5, 0.7);
			s.patch_freq = 1.5;
			s.patch_strength = 0.3;
			break;
		case PlantSpecies::FLOWER:
			s.moisture = lerpf(0.3, 0.85, t);
			s.moisture_tol = rr(rng, 0.2, 0.3);
			s.heat = rr(rng, 0.35, 0.8);
			s.heat_tol = rr(rng, 0.2, 0.3);
			s.above_min = 1.5;
			s.above_max = 32.0;
			s.slope_max = 0.4;
			s.density = rr(rng, 0.5, 0.75);
			s.patch_freq = rr(rng, 2.0, 3.0);
			s.patch_strength = rr(rng, 0.75, 0.9);
			break;
		case PlantSpecies::FERN:
			s.moisture = lerpf(0.55, 1.0, t);
			s.moisture_tol = 0.25;
			s.heat = rr(rng, 0.3, 0.7);
			s.heat_tol = 0.25;
			s.above_min = 1.5;
			s.above_max = 45.0;
			s.slope_max = 0.5;
			s.density = rr(rng, 0.25, 0.42);
			s.patch_freq = rr(rng, 1.2, 2.0);
			s.patch_strength = 0.3;
			break;
		case PlantSpecies::MUSHROOM:
			s.moisture = lerpf(0.55, 1.0, t);
			s.moisture_tol = 0.25;
			s.heat = rr(rng, 0.3, 0.7);
			s.heat_tol = 0.3;
			s.above_min = 1.2;
			s.above_max = 40.0;
			s.slope_max = 0.5;
			s.density = rr(rng, 0.1, 0.2);
			s.patch_freq = rr(rng, 2.0, 3.0);
			s.patch_strength = 0.7;
			break;
		default:
			break;
	}
}

// What it looks like: sizes, counts, colours.
void shape_forms(PlantSpecies &s, const Dice &rng) {
	switch (s.form) {
		case PlantSpecies::CONIFER: {
			const double slender = rng->randf(); // 0 broad, 1 tall and narrow
			s.height = lerpf(6.5, 13.0, slender) * rr(rng, 0.9, 1.1);
			s.crown = lerpf(2.7, 1.1, slender) * rr(rng, 0.9, 1.1);
			s.count = (int64_t)lerpf(4.0, 8.0, slender) + ri(rng, 0, 1);
			s.girth = rr(rng, 0.2, 0.38);
			s.bare = rr(rng, 0.14, 0.26);
			s.droop = rr(rng, 0.2, 0.9);
			s.wobble = rr(rng, 0.1, 0.22);
			s.bark = rhsv(rng, 0.05, 0.08, 0.5, 0.65, 0.2, 0.34);
			const double hue = rr(rng, 0.33, 0.47);
			const double saturation = rr(rng, 0.55, 0.75);
			const double value = rr(rng, 0.22, 0.36);
			s.leaf = hsv(hue, saturation, value);
			s.leaf_tip = s.leaf.lightened((float)rr(rng, 0.12, 0.22));
			s.frosted = s.heat < 0.3;
			s.variants = 3;
		} break;
		case PlantSpecies::BROADLEAF: {
			s.height = rr(rng, 6.0, 11.0);
			s.aspect = rr(rng, 0.65, 1.5);
			const double wide = rr(rng, 1.5, 3.0) / std::sqrt(s.aspect);
			s.crown = wide < s.height * 0.38 ? wide : s.height * 0.38;
			s.bare = rr(rng, 0.28, 0.5);
			s.girth = rr(rng, 0.2, 0.45);
			s.taper = rr(rng, 0.5, 0.72);
			s.count = ri(rng, 3, 6);
			s.extra = ri(rng, 0, 3); // forked branches under the crown
			if (s.moisture < 0.75 || rng->randf() < 0.6) {
				s.droop = 0.0;
			} else {
				s.droop = rr(rng, 0.5, 0.9);
			}
			s.lean = rr(rng, 0.0, 0.1);
			s.wobble = rr(rng, 0.15, 0.26);
			s.marked_bark = rng->randf() < 0.25;
			if (s.marked_bark) {
				s.bark = Color(0.86f, 0.85f, 0.8f);
			} else {
				s.bark = rhsv(rng, 0.06, 0.1, 0.35, 0.6, 0.25, 0.42);
			}
			if (s.marked_bark) { // a birch: slim, tall, pale, never weeping
				s.girth *= 0.6;
				s.height = rr(rng, 6.0, 9.0);
				s.crown *= 0.75;
				s.bare = rr(rng, 0.45, 0.6);
				s.aspect = rr(rng, 1.0, 1.4);
				s.droop = 0.0;
			}
			if (rng->randf() < 0.18) { // a species that is gold or red on its own
				s.leaf = rhsv(rng, 0.02, 0.13, 0.7, 0.9, 0.65, 0.8);
			} else {
				s.leaf = rhsv(rng, 0.17, 0.34, 0.5, 0.72, 0.38, 0.55);
			}
			s.leaf_tip = s.leaf.lightened((float)rr(rng, 0.1, 0.2));
			s.variants = 3;
		} break;
		case PlantSpecies::PALM:
			s.height = rr(rng, 4.5, 8.0);
			s.crown = rr(rng, 2.0, 3.2);
			s.count = ri(rng, 7, 10);
			s.girth = rr(rng, 0.17, 0.26);
			s.lean = rr(rng, 0.1, 0.18);
			s.bark = rhsv(rng, 0.07, 0.1, 0.4, 0.55, 0.42, 0.55);
			s.leaf = rhsv(rng, 0.27, 0.36, 0.6, 0.75, 0.4, 0.55);
			s.leaf_tip = s.leaf.lightened(0.15f);
			s.variants = 3;
			break;
		case PlantSpecies::BARE_TREE:
			s.height = rr(rng, 3.2, 6.0);
			s.count = ri(rng, 3, 6);
			s.girth = rr(rng, 0.22, 0.34);
			s.bark = rhsv(rng, 0.07, 0.1, 0.1, 0.22, 0.3, 0.45);
			s.variants = 3;
			break;
		case PlantSpecies::SHRUB:
			s.height = rr(rng, 0.8, 1.5);
			s.crown = rr(rng, 0.5, 0.95);
			s.count = ri(rng, 2, 4);
			s.wobble = rr(rng, 0.2, 0.3);
			s.leaf = rhsv(rng, 0.17, 0.36, 0.5, 0.75, 0.3, 0.5);
			s.leaf_tip = s.leaf.lightened((float)rr(rng, 0.08, 0.16));
			if (rng->randf() < 0.55) { // berries or blossom
				s.extra = ri(rng, 5, 11);
				s.accent = bright(rng);
			}
			s.variants = 3;
			break;
		case PlantSpecies::CACTUS: {
			const bool barrel = rng->randf() < 0.4;
			s.height = barrel ? rr(rng, 0.5, 0.9) : rr(rng, 1.8, 3.0);
			s.girth = barrel ? rr(rng, 0.3, 0.45) : rr(rng, 0.2, 0.3);
			s.count = barrel ? 1 : 0; // 1: barrel
			s.extra = barrel ? 0 : ri(rng, 0, 3); // arms
			s.leaf = rhsv(rng, 0.3, 0.42, 0.35, 0.55, 0.38, 0.52);
			s.leaf_tip = s.leaf.lightened(0.06f);
			const double hue = rr(rng, 0.9, 1.0);
			const double saturation = rr(rng, 0.5, 0.8);
			s.accent = hsv(hue, saturation, 0.95);
			s.variants = 2;
		} break;
		case PlantSpecies::GRASS: {
			s.height = rr(rng, 0.3, 0.8);
			s.girth = rr(rng, 0.022, 0.038); // slim blades: a real blade is a few millimetres wide
			s.count = ri(rng, 13, 20); // a clump has many
			s.droop = rr(rng, 0.1, 0.55);
			const bool golden = rng->randf() < 0.2;
			s.leaf = rhsv(rng, 0.2, 0.3, 0.5, 0.7, 0.5, 0.64);
			if (golden) {
				s.leaf_tip = rhsv(rng, 0.11, 0.16, 0.5, 0.65, 0.75, 0.88);
			} else {
				s.leaf_tip = rhsv(rng, 0.16, 0.25, 0.5, 0.65, 0.65, 0.8);
			}
			s.variants = 2;
		} break;
		case PlantSpecies::TALL_GRASS:
			s.height = rr(rng, 0.9, 1.6);
			s.girth = rr(rng, 0.035, 0.05);
			s.count = ri(rng, 8, 11);
			s.droop = rr(rng, 0.2, 0.4);
			s.extra = ri(rng, 0, 1); // seed heads
			s.accent = rhsv(rng, 0.08, 0.14, 0.4, 0.6, 0.65, 0.8);
			s.leaf = rhsv(rng, 0.2, 0.28, 0.6, 0.75, 0.4, 0.5);
			s.leaf_tip = rhsv(rng, 0.12, 0.2, 0.45, 0.6, 0.7, 0.85);
			s.variants = 2;
			break;
		case PlantSpecies::REED: {
			s.height = rr(rng, 1.0, 2.0);
			s.girth = rr(rng, 0.03, 0.045);
			s.count = ri(rng, 6, 9);
			s.droop = rr(rng, 0.05, 0.2);
			s.extra = ri(rng, 0, 1); // cattail heads
			const double hue = rr(rng, 0.06, 0.09);
			const double value = rr(rng, 0.25, 0.35);
			s.accent = hsv(hue, 0.6, value);
			s.leaf = rhsv(rng, 0.2, 0.26, 0.5, 0.65, 0.38, 0.48);
			s.leaf_tip = rhsv(rng, 0.14, 0.2, 0.4, 0.55, 0.65, 0.78);
			s.variants = 2;
		} break;
		case PlantSpecies::FLOWER:
			s.height = rr(rng, 0.3, 0.7);
			s.crown = rr(rng, 0.09, 0.16);
			s.count = ri(rng, 4, 9);
			s.extra = ri(rng, 1, 3); // stems in a clump
			s.accent = bright(rng);
			s.leaf = rhsv(rng, 0.24, 0.32, 0.6, 0.75, 0.42, 0.55);
			s.leaf_tip = s.leaf.lightened(0.12f);
			s.variants = 2;
			break;
		case PlantSpecies::FERN:
			s.height = rr(rng, 0.3, 0.55);
			s.crown = rr(rng, 0.6, 1.3);
			s.count = ri(rng, 5, 9);
			s.droop = rr(rng, 0.2, 0.6);
			s.leaf = rhsv(rng, 0.26, 0.36, 0.5, 0.72, 0.24, 0.42);
			s.leaf_tip = s.leaf.lightened(0.15f);
			s.variants = 2;
			break;
		case PlantSpecies::MUSHROOM: {
			static const Color caps[5] = { Color(0.82f, 0.18f, 0.15f), Color(0.62f, 0.42f, 0.25f), Color(0.9f, 0.78f, 0.55f),
				Color(0.85f, 0.5f, 0.2f), Color(0.55f, 0.35f, 0.6f) };
			s.height = rr(rng, 0.1, 0.3);
			s.crown = rr(rng, 0.9, 1.3); // cap radius per stalk height
			s.count = ri(rng, 1, 4);
			s.droop = rr(rng, 0.3, 0.9); // 0 flat cap .. 1 tall dome
			s.accent = caps[rng->randi() % 5];
			s.variants = 2;
		} break;
		default:
			break;
	}
	s.size_spread = s.is_tree() ? 0.2 : 0.3;
}

void shape(PlantSpecies &s, const Dice &rng) {
	shape_forms(s, rng);
	if (s.form == PlantSpecies::CONIFER || s.form == PlantSpecies::BROADLEAF || s.form == PlantSpecies::PALM || s.form == PlantSpecies::BARE_TREE) {
		s.height *= TREE_TALLER;
		s.crown *= std::sqrt(TREE_TALLER);
		s.girth *= std::sqrt(TREE_TALLER);
	}
}

// The kind of tree a species is (TreeArchetypes), from its climate: the dry heat grows flat-topped acacias and cacti, the
// wet heat rain trees and buttressed figs, a wet bank willows, the cold spruces. Its own dice, so nothing else of the
// species (or of the world) changes.
void archetype_of(PlantSpecies &s) {
	Dice dice;
	dice.instantiate();
	dice->set_seed((uint64_t)s.seed ^ 0xA2C4ULL);
	const bool hot = s.heat > 0.6;
	const bool wet = s.moisture > 0.6;
	std::vector<std::pair<String, double>> weights;
	switch (s.form) {
		case PlantSpecies::BROADLEAF:
			if (s.marked_bark) {
				weights = { { "leafy", 1.0 } }; // a birch
			} else if (s.droop > 0.4) {
				weights = { { "willow", 1.0 } };
			} else {
				weights = {
					{ "leafy", 3.0 },
					{ "oak", s.moisture > 0.4 ? 2.0 : 0.5 },
					{ "umbrella", (hot && !wet) ? 3.0 : 0.2 },
					{ "dragon", (hot && s.moisture < 0.4) ? 1.0 : 0.0 },
					{ "raintree", (hot && wet) ? 3.0 : 0.0 },
					{ "buttress", (hot && s.moisture > 0.7) ? 2.0 : 0.0 },
					{ "cherry", !hot ? 1.0 : 0.0 },
					{ "blossom", !hot ? 1.0 : 0.0 },
					{ "ancient", s.moisture > 0.5 ? 0.3 : 0.0 },
				};
			}
			break;
		case PlantSpecies::CONIFER:
			weights = { { "conifer", 4.0 }, { "cypress", s.heat > 0.4 ? 3.0 : 0.0 }, { "giant", s.moisture > 0.7 ? 0.25 : 0.0 } };
			break;
		case PlantSpecies::PALM:
			weights = { { "palm", 1.0 } };
			break;
		case PlantSpecies::BARE_TREE:
			weights = { { "dead", 1.0 } };
			break;
		case PlantSpecies::SHRUB:
			weights = { { "shrub", 3.0 }, { "bush", 1.5 } };
			break;
		case PlantSpecies::CACTUS:
			weights = { { "cactus", 1.0 } };
			break;
		case PlantSpecies::GRASS:
			weights = { { "grass", 3.0 }, { "meadow", 1.0 }, { "lawn", s.moisture > 0.65 ? 2.0 : 0.0 }, { "tussock", s.moisture < 0.45 ? 2.0 : 0.0 } };
			break;
		case PlantSpecies::TALL_GRASS:
			weights = { { "meadow", 3.0 }, { "pampas", 2.0 }, { "tussock", 1.0 } };
			break;
		case PlantSpecies::REED:
			weights = { { "reed", 1.0 } };
			break;
		case PlantSpecies::FLOWER:
			weights = { { "wildflower", 1.0 } };
			break;
		case PlantSpecies::FERN:
			weights = { { "fern", 1.0 } };
			break;
		default:
			return;
	}
	double total = 0.0;
	for (const auto &entry : weights) {
		total += entry.second;
	}
	double roll = dice->randf() * total;
	for (const auto &entry : weights) {
		roll -= entry.second;
		if (roll <= 0.0 && entry.second > 0.0) {
			s.archetype = entry.first;
			return;
		}
	}
	s.archetype = weights[0].first;
}

// A tree's size is its kind's, so the collider and the scatter read the real numbers. (The kind's genome comes from the
// native TreeArchetypes class, asked by name.)
void fit_size(const Species &p_species) {
	PlantSpecies &s = *p_species.ptr();
	if (s.archetype == String() || !s.is_tree()) {
		return;
	}
	ClassDBSingleton *db = ClassDBSingleton::get_singleton();
	if (!db->class_exists("TreeArchetypes") || !db->can_instantiate("TreeArchetypes")) {
		static bool reported = false;
		if (!reported) {
			reported = true;
			UtilityFunctions::push_error("SpeciesGenerator: no native TreeArchetypes class, tree sizes are not fitted to their kinds.");
		}
		return;
	}
	Variant maker_variant = db->instantiate("TreeArchetypes");
	Object *maker = maker_variant;
	if (maker == nullptr) {
		return;
	}
	Variant genome_variant = maker->call("for_species", p_species);
	Object *genome = genome_variant;
	if (genome == nullptr) {
		return;
	}
	s.height = (double)genome->get("height");
	s.girth = (double)genome->get("girth");
	s.crown = (double)genome->get("crown");
}

void leaf(PlantSpecies &s, int64_t p_shape, const Dice &dice, double aspect, double size, int64_t lobes, double angle) {
	s.leaf_shape = p_shape;
	s.leaf_aspect = aspect * rr(dice, 0.88, 1.14);
	s.leaf_size = size * rr(dice, 0.9, 1.12);
	s.leaf_lobes = lobes;
	s.limb_angle = angle * rr(dice, 0.9, 1.1);
}

// The leaf and the branching of a broadleaf tree, from the kind of tree its name says (a birch has small diamond leaves, a
// willow long narrow ones). Its own dice, so nothing else of the species (or of the world) changes when this is tuned.
void leaves(const Species &p_species) {
	PlantSpecies &s = *p_species.ptr();
	if (s.form != PlantSpecies::BROADLEAF) {
		return;
	}
	Dice dice;
	dice.instantiate();
	dice->set_seed((uint64_t)s.seed ^ 0x1EAFULL);
	const String noun = s.common_name.get_slice(" ", s.common_name.get_slice_count(" ") - 1);
	SpeciesGenerator::apply_leaf_traits(p_species, noun, dice);
}

void name_of(PlantSpecies &s, const Dice &rng, int64_t index, Dictionary &used) {
	const std::vector<String> nouns = nouns_of(s.form);
	String noun = nouns[(size_t)((index * 2 + (int64_t)rng->randi()) % (int64_t)nouns.size())];
	String kind;
	if (kind_noun(s.archetype, kind)) {
		noun = kind;
	} else if (s.form == PlantSpecies::BROADLEAF && s.marked_bark) { // the shape picks these two names
		noun = "Birch";
	} else if (s.form == PlantSpecies::BROADLEAF && s.droop > 0.4) {
		noun = "Willow";
	}
	const std::vector<String> *adjectives = &adjectives_plain();
	if (s.heat < 0.3) {
		adjectives = &adjectives_cold();
	} else if (s.moisture > 0.78 && s.above_max < 5.0) {
		adjectives = &adjectives_wet();
	} else if (s.heat > 0.65 && s.moisture < 0.4) {
		adjectives = &adjectives_hot();
	}
	String full;
	for (int attempt = 0; attempt < 12; attempt++) {
		full = (*adjectives)[(size_t)((int64_t)rng->randi() % (int64_t)adjectives->size())] + String(" ") + noun;
		if (!used.has(full)) {
			break;
		}
	}
	if (used.has(full)) { // out of fresh names: number it
		int64_t number = 2;
		while (used.has(full + " " + String::num_int64(number))) {
			number += 1;
		}
		full = full + " " + String::num_int64(number);
	}
	used[full] = true;
	s.common_name = full;
}

} // namespace

void SpeciesGenerator::_bind_methods() {
	ClassDB::bind_static_method("SpeciesGenerator", D_METHOD("generate", "world_seed", "count"), &SpeciesGenerator::generate);
	ClassDB::bind_static_method("SpeciesGenerator", D_METHOD("apply_leaf_traits", "species", "noun", "dice"), &SpeciesGenerator::apply_leaf_traits);
}

Array SpeciesGenerator::generate(int64_t p_world_seed, int64_t p_count) {
	int shares[FORM_COUNT];
	quotas_of(p_count, shares);
	Array made = Array(Array(), Variant::OBJECT, StringName("PlantSpecies"), Variant());
	Dictionary used;
	for (int at = 0; at < FORM_COUNT; at++) {
		const int form = FORM_ORDER[at];
		const int share = shares[at];
		for (int index = 0; index < share; index++) {
			Dice rng;
			rng.instantiate();
			rng->set_seed((uint64_t)(int64_t)UtilityFunctions::hash(Vector3i((int32_t)p_world_seed, form + 11, index + 3)));
			Species species;
			species.instantiate();
			species->form = form;
			species->id = made.size() + 1;
			species->seed = (int64_t)rng->randi();
			// the first axis spreads the species of a form over the climate
			const double spread = (double(index) + rng->randf()) / double(share);
			niche(*species.ptr(), rng, spread);
			shape(*species.ptr(), rng);
			archetype_of(*species.ptr());
			Dictionary &used_names = used;
			name_of(*species.ptr(), rng, index, used_names);
			leaves(species);
			fit_size(species);
			const double offset_x = rr(rng, -500.0, 500.0);
			const double offset_y = rr(rng, -500.0, 500.0);
			species->patch_offset = Vector2((real_t)offset_x, (real_t)offset_y);
			made.push_back(species);
		}
	}
	return made;
}

void SpeciesGenerator::apply_leaf_traits(const Ref<PlantSpecies> &p_species, const String &p_noun, const Ref<RandomNumberGenerator> &p_dice) {
	ERR_FAIL_COND(p_species.is_null() || p_dice.is_null());
	PlantSpecies &s = *p_species.ptr();
	const Dice &dice = p_dice;
	s.limb_count = ri(dice, 4, 5);
	if (p_noun == "Oak") {
		leaf(s, PlantSpecies::LOBED, dice, 1.7, 0.2, 3, 62.0);
	} else if (p_noun == "Maple") {
		leaf(s, PlantSpecies::PALMATE, dice, 1.0, 0.17, 2, 50.0);
	} else if (p_noun == "Beech") {
		leaf(s, PlantSpecies::OVAL, dice, 1.8, 0.2, 0, 52.0);
	} else if (p_noun == "Elm") {
		leaf(s, PlantSpecies::OVAL, dice, 1.6, 0.19, 0, 38.0);
	} else if (p_noun == "Ash") {
		leaf(s, PlantSpecies::LANCEOLATE, dice, 3.4, 0.2, 0, 44.0);
	} else if (p_noun == "Linden") {
		leaf(s, PlantSpecies::HEART, dice, 1.1, 0.22, 0, 48.0);
	} else if (p_noun == "Poplar") {
		leaf(s, PlantSpecies::DIAMOND, dice, 1.2, 0.18, 0, 26.0);
	} else if (p_noun == "Birch") {
		leaf(s, PlantSpecies::DIAMOND, dice, 1.3, 0.15, 0, 30.0);
	} else if (p_noun == "Willow") {
		leaf(s, PlantSpecies::LANCEOLATE, dice, 4.5, 0.17, 0, 58.0);
		s.droop = s.droop > 0.7 ? s.droop : 0.7; // a willow weeps
	} else {
		leaf(s, PlantSpecies::OVAL, dice, 1.8, 0.2, 0, 50.0);
	}
	s.leaf_edge = PlantSpecies::SMOOTH;
	if (p_noun == "Elm" || p_noun == "Birch" || p_noun == "Poplar" || p_noun == "Linden") {
		s.leaf_edge = PlantSpecies::SERRATED;
	} else if (p_noun == "Beech" || p_noun == "Willow") {
		s.leaf_edge = PlantSpecies::WAVY;
	}
	if (p_noun == "Maple" || p_noun == "Ash") {
		s.leaf_pattern = PlantSpecies::OPPOSITE;
	} else if (p_noun == "Willow") {
		s.leaf_pattern = PlantSpecies::SPIRAL;
	} else {
		s.leaf_pattern = PlantSpecies::ALTERNATE;
	}
}
