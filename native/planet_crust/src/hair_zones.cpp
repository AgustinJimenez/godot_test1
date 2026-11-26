#include "hair_zones.h"

#include <algorithm>
#include <cmath>

#include <godot_cpp/variant/string_name.hpp>
#include <godot_cpp/variant/variant.hpp>

namespace godot {

const char *const HAIR_ZONE_KEYS[ZONE_COUNT] = { "front", "top", "crown", "left_side", "right_side", "back", "nape" };

int hair_zone_at(const HairZoneFrame &p_frame, const Vector3 &p_point) {
	// how high on the head (0 at 3 cm above the eyes, 1 at the top), how far forward (front_scale units from the middle) and how far from the crown
	const double t = std::clamp((double(p_point.y) - (p_frame.eye_y + 0.03)) / std::max(p_frame.top_y - p_frame.eye_y - 0.03, 0.02), 0.0, 1.0);
	const double fz = (double(p_point.z) - p_frame.centre_z) / p_frame.front_scale;
	const double crown_d = std::hypot(double(p_point.x) - double(p_frame.crown.x), double(p_point.z) - double(p_frame.crown.z));
	if (crown_d < 0.045 && t > 0.5) {
		return ZONE_CROWN;
	}
	if (fz > 0.5 && std::abs(double(p_point.x)) < 0.055) {
		return ZONE_FRONT; // (the forehead's hair; the temples, farther out, belong to the sides)
	}
	if (t >= 0.62) {
		return ZONE_TOP;
	}
	if (fz < -0.35) {
		return t < 0.3 ? ZONE_NAPE : ZONE_BACK;
	}
	return p_point.x >= 0.0f ? ZONE_LEFT : ZONE_RIGHT;
}

HairZoneWeights hair_zone_weights(const HairZoneFrame &p_frame, const Vector3 &p_point) {
	// 13 samples: the point twice and 0.75 / 1.5 cm to either side along x, y and z. A zone's weight is its share: 1 well inside a zone, blending
	// over ~1.5 cm at a border (the samples see the same zones as the hard cut, so the blend is centred on it).
	HairZoneWeights weights{};
	const float step[2] = { 0.0075f, 0.015f };
	weights[size_t(hair_zone_at(p_frame, p_point))] += 2.0f;
	for (int axis = 0; axis < 3; axis++) {
		for (int s = 0; s < 2; s++) {
			for (int sign = -1; sign <= 1; sign += 2) {
				Vector3 q = p_point;
				q[axis] += step[s] * float(sign);
				weights[size_t(hair_zone_at(p_frame, q))] += 1.0f;
			}
		}
	}
	for (float &w : weights) {
		w /= 14.0f;
	}
	return weights;
}

int hair_zone_dominant(const HairZoneWeights &p_weights) {
	return int(std::max_element(p_weights.begin(), p_weights.end()) - p_weights.begin());
}

const char *const HAIR_LOOK_KEYS[HAIR_LOOK_KEY_COUNT] = { "length", "volume", "curl", "wave", "clumping", "fringe", "sweep", "hug", "quiff", "swept", "spike",
	"gravity", "messy", "gaps", "wisps", "tousle", "amount" };

namespace {

double *look_field(HairLook &p_look, int p_key) {
	double *fields[HAIR_LOOK_KEY_COUNT] = { &p_look.length, &p_look.volume, &p_look.curl, &p_look.wave, &p_look.clumping, &p_look.fringe, &p_look.sweep,
		&p_look.hug, &p_look.quiff, &p_look.swept, &p_look.spike, &p_look.gravity, &p_look.messy, &p_look.gaps, &p_look.wisps, &p_look.tousle,
		&p_look.amount };
	return fields[p_key];
}

// the same limits as the whole-head reads in HumanHair::build_arrays
double limit(int p_key, double p_value) {
	switch (p_key) {
		case 0: return std::max(0.01, p_value);  // length
		case 1: return std::max(0.0, p_value);   // volume
		case 2: return std::max(0.0, p_value);   // curl
		case 11: return std::max(0.0, p_value);  // gravity
		default: return std::clamp(p_value, 0.0, 1.0);
	}
}

} // namespace

HairZoneLooks hair_zone_looks(const Dictionary &p_params) {
	HairZoneLooks looks;
	for (int k = 0; k < HAIR_LOOK_KEY_COUNT - 1; k++) { // (not `amount`: the whole head has all its hair)
		const StringName key(HAIR_LOOK_KEYS[k]);
		if (p_params.has(key)) {
			*look_field(looks.head, k) = limit(k, double(p_params[key]));
		}
	}
	for (int z = 0; z < ZONE_COUNT; z++) {
		looks.zone[z] = looks.head;
	}
	const StringName zones_key("zones");
	if (!p_params.has(zones_key) || p_params[zones_key].get_type() != Variant::DICTIONARY) {
		return looks;
	}
	const Dictionary zones = p_params[zones_key];
	for (int z = 0; z < ZONE_COUNT; z++) {
		const StringName zone_key(HAIR_ZONE_KEYS[z]);
		if (!zones.has(zone_key) || zones[zone_key].get_type() != Variant::DICTIONARY) {
			continue;
		}
		const Dictionary overrides = zones[zone_key];
		for (int k = 0; k < HAIR_LOOK_KEY_COUNT; k++) {
			const StringName key(HAIR_LOOK_KEYS[k]);
			if (overrides.has(key)) {
				*look_field(looks.zone[z], k) = limit(k, double(overrides[key]));
				looks.set[z][k] = true;
				looks.any = true;
			}
		}
	}
	return looks;
}

HairLook hair_look_at(const HairZoneLooks &p_looks, const HairZoneWeights &p_weights) {
	HairLook look = p_looks.head;
	if (!p_looks.any) {
		return look;
	}
	for (int z = 0; z < ZONE_COUNT; z++) {
		const double w = double(p_weights[size_t(z)]);
		if (w <= 0.0) {
			continue;
		}
		HairLook zone_look = p_looks.zone[z];
		HairLook head = p_looks.head;
		for (int k = 0; k < HAIR_LOOK_KEY_COUNT; k++) {
			if (p_looks.set[z][k]) {
				*look_field(look, k) += w * (*look_field(zone_look, k) - *look_field(head, k));
			}
		}
	}
	return look;
}

double hair_look_max(const HairZoneLooks &p_looks, int p_key) {
	HairLook head = p_looks.head;
	double best = *look_field(head, p_key);
	for (int z = 0; z < ZONE_COUNT; z++) {
		if (p_looks.set[z][p_key]) {
			HairLook zone_look = p_looks.zone[z];
			best = std::max(best, *look_field(zone_look, p_key));
		}
	}
	return best;
}

} // namespace godot
