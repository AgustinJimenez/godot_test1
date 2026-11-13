#include "plant_species_native.h"

#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/core/math.hpp>

using namespace godot;

namespace {
double smooth_step(double p_from, double p_to, double p_x) {
	double t = Math::clamp((p_x - p_from) / (p_to - p_from), 0.0, 1.0);
	return t * t * (3.0 - 2.0 * t);
}
} // namespace

void PlantSpecies::_bind_methods() {
	BIND_ENUM_CONSTANT(CONIFER);
	BIND_ENUM_CONSTANT(BROADLEAF);
	BIND_ENUM_CONSTANT(PALM);
	BIND_ENUM_CONSTANT(BARE_TREE);
	BIND_ENUM_CONSTANT(SHRUB);
	BIND_ENUM_CONSTANT(CACTUS);
	BIND_ENUM_CONSTANT(GRASS);
	BIND_ENUM_CONSTANT(TALL_GRASS);
	BIND_ENUM_CONSTANT(REED);
	BIND_ENUM_CONSTANT(FLOWER);
	BIND_ENUM_CONSTANT(FERN);
	BIND_ENUM_CONSTANT(MUSHROOM);
	BIND_ENUM_CONSTANT(OVAL);
	BIND_ENUM_CONSTANT(LOBED);
	BIND_ENUM_CONSTANT(PALMATE);
	BIND_ENUM_CONSTANT(HEART);
	BIND_ENUM_CONSTANT(LANCEOLATE);
	BIND_ENUM_CONSTANT(DIAMOND);
	BIND_ENUM_CONSTANT(SMOOTH);
	BIND_ENUM_CONSTANT(SERRATED);
	BIND_ENUM_CONSTANT(WAVY);
	BIND_ENUM_CONSTANT(ALTERNATE);
	BIND_ENUM_CONSTANT(OPPOSITE);
	BIND_ENUM_CONSTANT(SPIRAL);
	BIND_ENUM_CONSTANT(CANOPY);
	BIND_ENUM_CONSTANT(UNDERSTORY);
	BIND_ENUM_CONSTANT(GRASSLAND);
	BIND_ENUM_CONSTANT(MEADOW);
	BIND_ENUM_CONSTANT(COVER);

#define PS_BIND(TYPE, NAME, VT) 	ClassDB::bind_method(D_METHOD("get_" #NAME), &PlantSpecies::get_##NAME); 	ClassDB::bind_method(D_METHOD("set_" #NAME, "value"), &PlantSpecies::set_##NAME); 	ADD_PROPERTY(PropertyInfo(VT, #NAME), "set_" #NAME, "get_" #NAME);
	PLANT_SPECIES_FIELDS(PS_BIND)
#undef PS_BIND

	ClassDB::bind_static_method("PlantSpecies", D_METHOD("form_names"), &PlantSpecies::form_names);
	ClassDB::bind_method(D_METHOD("layer"), &PlantSpecies::layer);
	ClassDB::bind_method(D_METHOD("is_tree"), &PlantSpecies::is_tree);
	ClassDB::bind_method(D_METHOD("fitness", "wet", "warm", "above", "steep"), &PlantSpecies::fitness);
	ClassDB::bind_method(D_METHOD("footprint"), &PlantSpecies::footprint);
	ClassDB::bind_method(D_METHOD("summary"), &PlantSpecies::summary);
}

PackedStringArray PlantSpecies::form_names() {
	PackedStringArray names;
	for (const char *name : { "CONIFER", "BROADLEAF", "PALM", "BARE_TREE", "SHRUB", "CACTUS", "GRASS", "TALL_GRASS", "REED", "FLOWER", "FERN", "MUSHROOM" }) {
		names.push_back(name);
	}
	return names;
}

int64_t PlantSpecies::layer() const {
	switch (form) {
		case CONIFER:
		case BROADLEAF:
		case PALM:
		case BARE_TREE:
			return CANOPY;
		case SHRUB:
		case CACTUS:
			return UNDERSTORY;
		case GRASS:
		case REED:
			return GRASSLAND;
		case FLOWER:
			return MEADOW;
		default:
			return COVER; // TALL_GRASS, FERN, MUSHROOM
	}
}

bool PlantSpecies::is_tree() const {
	return layer() == CANOPY;
}

double PlantSpecies::fitness(double p_wet, double p_warm, double p_above, double p_steep) const {
	if (p_above < above_min - 0.5 || p_above > above_max || p_steep > slope_max) {
		return 0.0;
	}
	const double dry = (p_wet - moisture) / moisture_tol;
	const double cold = (p_warm - heat) / heat_tol;
	const double off = dry * dry + cold * cold;
	if (off > 6.0) {
		return 0.0; // exp(-6) is nothing: skip the rest of the maths for plants far out of their climate
	}
	const double edge = smooth_step(above_min - 0.5, above_min + 0.5, p_above) * (1.0 - smooth_step(above_max - 4.0, above_max, p_above)) * (1.0 - smooth_step(slope_max - 0.12, slope_max, p_steep));
	return Math::exp(-off) * edge;
}

Vector2 PlantSpecies::footprint() const {
	switch (form) {
		case CONIFER:
		case BROADLEAF:
		case PALM:
		case BARE_TREE:
			return Vector2(Math::max(girth * 0.9, 0.18), Math::clamp(height * 0.6, 1.5, 4.0));
		case CACTUS:
			return Vector2(Math::max(girth, 0.2), Math::min(height, 2.5));
		default:
			return Vector2();
	}
}

String PlantSpecies::summary() const {
	static const char *names[] = { "CONIFER", "BROADLEAF", "PALM", "BARE_TREE", "SHRUB", "CACTUS", "GRASS", "TALL_GRASS", "REED", "FLOWER", "FERN", "MUSHROOM" };
	return String("#%02d %-9s %-22s h=%4.1f  wet %.2f+-%.2f  heat %.2f+-%.2f  above %.1f..%.0f  dens %.2f") % Array::make(id, names[form], common_name, height, moisture, moisture_tol, heat, heat_tol, above_min, above_max, density);
}
