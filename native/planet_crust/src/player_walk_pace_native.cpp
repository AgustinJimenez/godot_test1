#include "player_walk_pace_native.h"

#include <godot_cpp/core/class_db.hpp>

#include <algorithm>
#include <cmath>

using namespace godot;

namespace {
const double UPHILL_SLOWDOWN = 0.6; // speed lost per unit of rise over run (0.5 = 27 degrees -> -30%)
const double UPHILL_MIN_SCALE = 0.45;
const double UPHILL_SCALE_RATE = 2.0; // per second
const double STAIR_STEP_SPEED = 0.7; // m/s of ground the stair clip's steps cover at normal playback

double move_toward_d(double p_from, double p_to, double p_delta) {
	return std::abs(p_to - p_from) <= p_delta ? p_to : p_from + (p_to > p_from ? 1.0 : -1.0) * p_delta;
}
} // namespace

void PlayerWalkPaceNative::_bind_methods() {
	ClassDB::bind_method(D_METHOD("pace", "speed", "walking_pace", "on_stairs", "on_floor", "floor_normal", "wish", "delta", "stair_scale"), &PlayerWalkPaceNative::pace);
	ClassDB::bind_method(D_METHOD("get_uphill_scale"), &PlayerWalkPaceNative::get_uphill_scale);
}

PackedFloat64Array PlayerWalkPaceNative::pace(double p_speed, bool p_walking_pace, bool p_on_stairs, bool p_on_floor, const Vector3 &p_floor_normal, const Vector3 &p_wish, double p_delta, double p_stair_scale) {
	const double stair_mix = (p_walking_pace && p_on_stairs) ? 1.0 : 0.0;
	double slope_target = 1.0;
	const double wish_length = p_wish.length();
	if (p_walking_pace && !p_on_stairs && p_on_floor && wish_length * wish_length > 0.0001 && p_floor_normal.y > 0.01) {
		// rise over run along the walk
		const double gradient = std::max(-((double)p_floor_normal.x * (double)p_wish.x + (double)p_floor_normal.z * (double)p_wish.z) / ((double)p_floor_normal.y * wish_length), 0.0);
		slope_target = std::clamp(1.0 - UPHILL_SLOWDOWN * gradient, UPHILL_MIN_SCALE, 1.0);
	}
	uphill_scale = move_toward_d(uphill_scale, slope_target, p_delta * UPHILL_SCALE_RATE);
	const double speed = p_speed * (1.0 + (p_stair_scale - 1.0) * stair_mix) * uphill_scale;
	const bool stair_off = std::abs(p_stair_scale - 1.0) <= 0.00001 * std::max(std::abs(p_stair_scale), 1.0);
	const double stair_playback = stair_off ? 1.0 : speed / STAIR_STEP_SPEED;
	const double playback = stair_mix > 0.0 ? 1.0 + (stair_playback - 1.0) * stair_mix : 1.0;
	PackedFloat64Array result;
	result.push_back(speed);
	result.push_back(playback * (stair_mix <= 0.0 ? uphill_scale : 1.0));
	return result;
}
