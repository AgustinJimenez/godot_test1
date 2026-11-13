#include "tree_genome_native.h"

#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/core/math.hpp>

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

struct FieldInfo {
	const char *name;
	Variant::Type type;
};
const FieldInfo FIELDS[] = {
#define TG_INFO(TYPE, NAME, VT) { #NAME, VT },
	TREE_GENOME_FIELDS(TG_INFO)
#undef TG_INFO
};
const int FIELD_COUNT = (int)(sizeof(FIELDS) / sizeof(FIELDS[0]));
const char *const *field_name_table() {
	static const char *names[FIELD_COUNT];
	static bool ready = false;
	if (!ready) {
		for (int i = 0; i < FIELD_COUNT; i++) {
			names[i] = FIELDS[i].name;
		}
		ready = true;
	}
	return names;
}
} // namespace

TreeGenome::TreeGenome() {
	rings = ints3(6, 5, 3);
	sides = ints3(11, 8, 5);
	sides_real = ints3(12, 10, 6);
	curve = nums3(0.5, 0.8, 1.2);
	wander = nums3(0.06, 0.08, 0.1);
	lift = nums3(0.08, 0.05, 0.0);
	sag = nums3(0.0, 0.04, 0.1);
	droop_sag = nums3(0.0, 0.14, 0.3);
	sway = nums3(0.16, 0.2, 0.22);
	tip_radius = nums3(0.4, 0.25, 0.05);
	children = ints3(4, 4, 0);
	child_length = nums3(0.55, 0.5, 0.0);
}

void TreeGenome::_bind_methods() {
	BIND_ENUM_CONSTANT(CONE);
	BIND_ENUM_CONSTANT(DOME);
	BIND_ENUM_CONSTANT(SINGLE);
	BIND_ENUM_CONSTANT(RACEME);
	BIND_ENUM_CONSTANT(UMBEL);
	BIND_ENUM_CONSTANT(BLADE);
	BIND_ENUM_CONSTANT(NEEDLE);
	BIND_ENUM_CONSTANT(FROND);

#define TG_BIND(TYPE, NAME, VT) \
	ClassDB::bind_method(D_METHOD("get_" #NAME), &TreeGenome::get_##NAME); \
	ClassDB::bind_method(D_METHOD("set_" #NAME, "value"), &TreeGenome::set_##NAME); \
	ADD_PROPERTY(PropertyInfo(VT, #NAME), "set_" #NAME, "get_" #NAME);
	TREE_GENOME_FIELDS(TG_BIND)
#undef TG_BIND

	ClassDB::bind_method(D_METHOD("to_dictionary"), &TreeGenome::to_dictionary);
	ClassDB::bind_static_method("TreeGenome", D_METHOD("from_species", "species"), &TreeGenome::from_species);
}

const char *const *TreeGenome::field_names(int &r_count) {
	r_count = FIELD_COUNT;
	return field_name_table();
}

Variant::Type TreeGenome::field_type(int p_index) {
	return FIELDS[p_index].type;
}

Dictionary TreeGenome::to_dictionary() const {
	Dictionary out;
#define TG_OUT(TYPE, NAME, VT) out[String(#NAME)] = Variant(NAME);
	TREE_GENOME_FIELDS(TG_OUT)
#undef TG_OUT
	return out;
}

namespace {
void leafy(TreeGenome &g, const PlantSpecies &s) {
	g.taper = s.taper;
	g.lean = s.lean;
	g.aspect = s.aspect;
	g.marked_bark = s.marked_bark;
	g.limbs = s.limb_count;
	g.limb_angle = s.limb_angle;
	g.leaf_shape = s.leaf_shape;
	g.leaf_aspect = s.leaf_aspect;
	g.leaf_size = s.leaf_size;
	g.leaf_lobes = s.leaf_lobes;
	g.leaf_edge = s.leaf_edge;
	g.leaf_pattern = s.leaf_pattern;
}

void conifer(TreeGenome &g) {
	g.leader = true;
	g.profile = TreeGenome::CONE;
	g.whorled = true;
	g.limbs = 5;
	g.nodes_spacing = Math::clamp(g.crown * 0.35, 0.5, 0.9);
	g.nodes_from = g.trunk_part * 0.75;
	g.trunk_sides = 12;
	g.trunk_wobble = 0.03;
	g.trunk_dark = 0.3;
	g.depth = 2;
	g.rings = ints3(3, 2, 0);
	g.sides = ints3(5, 3, 0);
	g.sides_real = ints3(7, 4, 0);
	g.curve = nums3(0.0, 0.0, 0.0);
	g.wander = nums3(0.08, 0.08, 0.0);
	g.lift = nums3(0.275, 0.3, 0.0); // per ring: a branch turns up toward its tip
	g.sag = nums3(0.0, 0.0, 0.0);
	g.droop_sag = nums3(0.0, 0.0, 0.0);
	g.sway = nums3(0.2, 0.25, 0.0);
	g.tip_radius = nums3(0.18, 0.18, 0.0);
	g.children = ints3(2, 0, 0);
	g.child_radius = 0.55;
	g.child_length = nums3(0.42, 0.0, 0.0);
	g.child_length_a = 1.15;
	g.child_length_b = 0.6;
	g.children_from = 0.3;
	g.children_to = 0.9;
	g.children_planar = true;
	g.child_forward = 0.75;
	g.child_side = 0.7;
	g.child_up = -0.1;
	g.carry_on = false;
	g.foliage = TreeGenome::NEEDLE;
	g.needle_size = 0.45;
}
} // namespace

Ref<TreeGenome> TreeGenome::from_species(const Ref<PlantSpecies> &p_species) {
	Ref<TreeGenome> out;
	out.instantiate();
	ERR_FAIL_COND_V(p_species.is_null(), out);
	const PlantSpecies &s = *p_species.ptr();
	TreeGenome &g = *out.ptr();
	g.height = s.height;
	g.girth = s.girth;
	g.bark = s.bark;
	g.leaf = s.leaf;
	g.leaf_tip = s.leaf_tip;
	g.frosted = s.frosted;
	g.crown = s.crown;
	g.droop = s.droop;
	g.trunk_part = s.bare;
	if (s.form == PlantSpecies::CONIFER) {
		conifer(g);
	} else {
		leafy(g, s);
	}
	return out;
}
