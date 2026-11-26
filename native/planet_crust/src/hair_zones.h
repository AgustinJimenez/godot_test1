#pragma once
// Hair zones: the scalp split into named zones (front, top, crown, left side, right side, back, nape), so a hairstyle can change its settings
// zone by zone (a mohawk: long spiky top, bare sides; curly lower sides, straight top). The zones come from the head landmarks HumanHair::build_arrays
// already works out; a point's zone weights blend softly over ~1.5 cm at a border, so a change in one zone has no seam.
// The character faces +Z: its LEFT side is +X.

#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/vector3.hpp>

#include <array>

namespace godot {

enum HairZone {
	ZONE_FRONT,
	ZONE_TOP,
	ZONE_CROWN,
	ZONE_LEFT,
	ZONE_RIGHT,
	ZONE_BACK,
	ZONE_NAPE,
	ZONE_COUNT
};

// the zone names as the lab and saved styles write them ("front", "top", "crown", "left_side", "right_side", "back", "nape")
extern const char *const HAIR_ZONE_KEYS[ZONE_COUNT];

// the head landmarks the zones are cut from (all in the body's space)
struct HairZoneFrame {
	Vector3 crown;
	double centre_z = 0.0;    // halfway between the front and the back of the head
	double front_scale = 0.1; // ~ half the head's depth
	double eye_y = 0.0;
	double top_y = 0.0;
};

using HairZoneWeights = std::array<float, ZONE_COUNT>;

// the zone a point is in (no blending)
int hair_zone_at(const HairZoneFrame &p_frame, const Vector3 &p_point);
// the zone weights at a point: the zone sampled at the point and around it (up to 1.5 cm), as shares that sum to 1
HairZoneWeights hair_zone_weights(const HairZoneFrame &p_frame, const Vector3 &p_point);
// the zone with the largest weight
int hair_zone_dominant(const HairZoneWeights &p_weights);

// The settings a zone can change, as read from the params (with the same limits as the whole-head reads). `amount` is the share of locks that grow
// (1 = all, 0 = a bare zone); the whole head always has 1.
struct HairLook {
	double length = 0.12, volume = 1.0, curl = 0.0, wave = 0.0, clumping = 0.6, fringe = 0.4, sweep = 0.0, hug = 0.0, quiff = 0.0, swept = 0.0,
			spike = 0.0, gravity = 1.0, messy = 0.0, gaps = 0.0, wisps = 0.0, tousle = 0.0, amount = 1.0;
};
constexpr int HAIR_LOOK_KEY_COUNT = 17;
extern const char *const HAIR_LOOK_KEYS[HAIR_LOOK_KEY_COUNT]; // "length", "volume", ... "amount" (the order of HairLook's fields)

// the whole head's settings and every zone's overrides (only the keys a zone names are set)
struct HairZoneLooks {
	bool any = false; // (no zone overrides anything: every lock uses the head's settings)
	HairLook head;
	HairLook zone[ZONE_COUNT];
	bool set[ZONE_COUNT][HAIR_LOOK_KEY_COUNT] = {};
};

// The head's settings from the params, and the zone overrides from params["zones"] ({zone key: {setting: value}}); unknown zones and settings are ignored.
HairZoneLooks hair_zone_looks(const Dictionary &p_params);
// a lock's settings: the head's, moved toward each zone's override by that zone's weight
HairLook hair_look_at(const HairZoneLooks &p_looks, const HairZoneWeights &p_weights);
// the largest value of a setting over the head and every zone that sets it (the build-wide point counts follow the longest, curliest, wavier hair)
double hair_look_max(const HairZoneLooks &p_looks, int p_key);

} // namespace godot
