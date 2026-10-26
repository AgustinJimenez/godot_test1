#include "planet_weather_native.h"
#include "planet_settings_native.h"

#include <godot_cpp/classes/object.hpp>
#include <godot_cpp/classes/random_number_generator.hpp>

#include <algorithm>
#include <cmath>

using namespace godot;

static const double TAU_D = 6.283185307179586476925286766559;

static double smooth_step(double p_from, double p_to, double p_x) {
	if (p_from == p_to) {
		return p_x < p_from ? 0.0 : 1.0;
	}
	double s = CLAMP((p_x - p_from) / (p_to - p_from), 0.0, 1.0);
	return s * s * (3.0 - 2.0 * s);
}

static double lerp_d(double p_a, double p_b, double p_t) {
	return p_a + (p_b - p_a) * p_t;
}

static double positive_mod_d(double p_x, double p_y) {
	double value = std::fmod(p_x, p_y);
	if ((value < 0.0 && p_y > 0.0) || (value > 0.0 && p_y < 0.0)) {
		value += p_y;
	}
	return value;
}

void PlanetWeather::_bind_methods() {
	BIND_ENUM_CONSTANT(CLEAR);
	BIND_ENUM_CONSTANT(CLOUDY);
	BIND_ENUM_CONSTANT(RAIN);
	BIND_ENUM_CONSTANT(STORM);
	BIND_ENUM_CONSTANT(FOG);
	BIND_ENUM_CONSTANT(SNOW);
	ClassDB::bind_static_method("PlanetWeather", D_METHOD("get_wind_turn"), &PlanetWeather::get_wind_turn);
	ClassDB::bind_static_method("PlanetWeather", D_METHOD("create", "noise"), &PlanetWeather::create);
	ClassDB::bind_static_method("PlanetWeather", D_METHOD("zonal_wind", "lat", "wind_k"), &PlanetWeather::zonal_wind, DEFVAL(4.0));
	ClassDB::bind_method(D_METHOD("config"), &PlanetWeather::config);
	ClassDB::bind_method(D_METHOD("wind_k"), &PlanetWeather::wind_k);
	ClassDB::bind_method(D_METHOD("readiness", "dir", "clock", "macro"), &PlanetWeather::readiness, DEFVAL(NAN));
	ClassDB::bind_method(D_METHOD("cloud", "dir", "clock", "macro"), &PlanetWeather::cloud, DEFVAL(NAN));
	ClassDB::bind_method(D_METHOD("cloud_cells", "dir", "clock", "macro"), &PlanetWeather::cloud_cells, DEFVAL(NAN));
	ClassDB::bind_method(D_METHOD("at", "dir", "ground", "clock"), &PlanetWeather::at);
}

Object *PlanetWeather::noise() const {
	return ObjectDB::get_instance(noise_id);
}

Ref<PlanetClimate> PlanetWeather::climate() const {
	return noise()->get("climate");
}

void PlanetWeather::setup_noise(const Ref<FastNoiseLite> &p_source, int64_t p_seed, double p_frequency, int p_octaves) {
	p_source->set_noise_type(FastNoiseLite::TYPE_SIMPLEX_SMOOTH);
	p_source->set_seed((int32_t)p_seed);
	p_source->set_frequency(p_frequency);
	p_source->set_fractal_type(FastNoiseLite::FRACTAL_FBM);
	p_source->set_fractal_octaves(p_octaves);
}

// [seed, frequency, octaves, fractal type] (PlanetNoise.noise_config)
Array PlanetWeather::noise_config(const Ref<FastNoiseLite> &p_source) {
	Array config;
	config.append(p_source->get_seed());
	config.append(p_source->get_frequency());
	config.append(p_source->get_fractal_octaves());
	config.append((int)p_source->get_fractal_type());
	return config;
}

Ref<PlanetWeather> PlanetWeather::create(Object *p_noise) {
	Ref<PlanetWeather> made;
	made.instantiate();
	PlanetWeather &self = **made;
	self.noise_id = p_noise->get_instance_id();
	self.big_a.instantiate();
	self.big_b.instantiate();
	self.small.instantiate();
	self.warp.instantiate();
	self.pool.instantiate();
	Ref<PlanetSettings> settings = p_noise->get("settings");
	int64_t seed_value = settings->get_world_seed();
	setup_noise(self.big_a, seed_value + 31, 1.7, 3);
	setup_noise(self.big_b, seed_value + 32, 1.7, 3);
	setup_noise(self.small, seed_value + 33, 6.5, 3);
	setup_noise(self.warp, seed_value + 34, 2.4, 3);
	Ref<RandomNumberGenerator> rng;
	rng.instantiate();
	rng->set_seed((uint64_t)(seed_value + 36));
	Ref<PlanetClimate> climate = p_noise->get("climate");
	Dictionary circulation = climate->get_circulation();
	self.belt_shift = Math::deg_to_rad((double)circulation["itcz_lat"]) + rng->randf_range(-0.12, 0.12);
	self.belt_power = rng->randf_range(0.08, 0.95);
	self.storm_shift = Math::deg_to_rad((double)circulation["storm_lat"] - 48.0);
	self.storm_power = rng->randf_range(0.5, 1.3);
	self.sink_power = rng->randf_range(0.7, 1.2);
	self.wind_k_ = circulation["wind_k"];
	self.sink_shift = Math::deg_to_rad((double)circulation["dry_lat"] - 27.5);
	self.pool_break = rng->randf_range(0.5, 1.4);
	setup_noise(self.pool, seed_value + 35, rng->randf_range(0.8, 1.9), 2);
	Object *crust = p_noise->get("native");
	if (crust != nullptr) {
		crust->call("set_weather", self.config()); // gives the native crust this weather's noises and numbers, so the map's cloud layers are native
	}
	return made;
}

// The noises and numbers of this weather (what the native crust and the GPU's cloud cover are given).
Dictionary PlanetWeather::config() const {
	Dictionary c;
	c["big_a"] = noise_config(big_a);
	c["big_b"] = noise_config(big_b);
	c["small"] = noise_config(small);
	c["warp"] = noise_config(warp);
	c["pool"] = noise_config(pool);
	c["belt_shift"] = belt_shift;
	c["belt_power"] = belt_power;
	c["storm_shift"] = storm_shift;
	c["storm_power"] = storm_power;
	c["sink_shift"] = sink_shift;
	c["sink_power"] = sink_power;
	c["pool_break"] = pool_break;
	c["wind_k"] = wind_k_;
	c["season_mean"] = climate()->get_seasons()->get_mean();
	return c;
}

// The east-west wind at latitude `lat` (radians) as a share of the strongest: negative blows toward the west (the trade winds and the polar
// easterlies), positive toward the east (the westerlies of the middle latitudes).
double PlanetWeather::zonal_wind(double p_lat, double p_wind_k) {
	return -std::cos(p_lat * p_wind_k);
}

// How much cloud the air at `dir` is ready to make (0..1): moisture times lift, held down under the subtropical highs.
double PlanetWeather::readiness(const Vector3 &p_dir, const Ref<PlanetClock> &p_clock, double p_macro) const {
	double lat = std::asin(CLAMP((double)p_dir.y, -1.0, 1.0));
	double declination = p_clock->declination();
	double moist = moisture(p_dir, p_clock, p_macro);
	double south = lat < 0.0 ? -1.0 : 1.0;
	// the belt where the trade winds meet follows the sun, but not all the way
	// (the belt is broken up by longitude: strong over the warm pools, weak over the cold tongues)
	double pool_noise = pool->get_noise_3d(p_dir.x, p_dir.y, p_dir.z);
	double pools = 0.5 + 0.5 * pool_noise;
	double pools_factor = lerp_d(1.0 - 0.65 * pool_break, 1.0 + 0.4 * pool_break, smooth_step(0.2, 0.8, pools));
	double trade_belt = 0.75 * belt_power * pools_factor * std::exp(-std::pow((lat - 0.4 * declination - belt_shift) / 0.17, 2.0));
	// the storm tracks of the middle latitudes, a little poleward in the summer; they lean: they run poleward toward the east
	double lean = 0.12 * std::sin(std::atan2(p_dir.z, p_dir.x) * 2.0 + pool_noise * 3.0);
	double storm_lat = south * (0.87 + lean + storm_shift) + 0.3 * declination;
	double storms = 0.55 * storm_power * std::exp(-std::pow((lat - storm_lat) / 0.2, 2.0));
	// the subtropical highs, where the air sinks
	double high_lat = south * (0.48 + sink_shift) + 0.3 * declination;
	double sinking = sink_power * std::exp(-std::pow((lat - high_lat) / 0.15, 2.0));
	double wet = CLAMP((double)climate()->sample(p_dir).y / 1.2, 0.0, 1.0);
	// moisture alone makes some cloud; the trade winds' belt lifts the moist air; the storm tracks lift whatever air they find
	double ready = 0.06 + 0.3 * moist + 0.8 * trade_belt * moist;
	ready += 0.9 * storms * (0.5 + 0.5 * moist) + 0.2 * wet * moist;
	ready += 0.25 * smooth_step(0.9, 1.4, std::abs(lat)); // the cloud decks of the polar regions
	ready += monsoon(p_dir, p_clock, wet, p_macro);
	// warm pools and cold tongues change the whole cloudiness, whatever made it (seed by seed)
	ready *= lerp_d(1.0 - 0.4 * pool_break, 1.0 + 0.3 * pool_break, smooth_step(0.25, 0.75, pools));
	return CLAMP(ready * (1.0 - 0.65 * sinking), 0.0, 1.0);
}

// The monsoon: in the warm half of the year a big land mass in the low latitudes heats more than the sea beside it, its air rises and draws
// the moist air in from the sea (a wet season); in the cool half the air sinks (a dry season). Found from the land's own temperature
// against its yearly mean.
double PlanetWeather::monsoon(const Vector3 &p_dir, const Ref<PlanetClock> &p_clock, double p_wet, double p_macro) const {
	if (macro_of(p_dir, p_macro) < 0.0) {
		return 0.0;
	}
	double lat = std::asin(CLAMP((double)p_dir.y, -1.0, 1.0));
	double tropics = std::exp(-std::pow(lat / 0.6, 2.0));
	Ref<PlanetSeasons> seasons = climate()->get_seasons();
	double anomaly = seasons->at(p_dir, p_clock->year_share()) - seasons->mean_at(p_dir);
	double wetter = smooth_step(0.0, 8.0, anomaly);
	double drier = smooth_step(0.0, 8.0, -anomaly);
	return tropics * (0.5 * wetter * (0.3 + p_wet) - 0.2 * drier);
}

// The height before the rivers at `dir`: `macro` when the caller has it already, else worked out here.
double PlanetWeather::macro_of(const Vector3 &p_dir, double p_macro) const {
	return !std::isnan(p_macro) ? p_macro : (double)noise()->call("macro_height", p_dir.x, p_dir.y, p_dir.z);
}

// The moisture the air picks up at `dir` now (0..1): a warm sea gives off a great deal, wet land some, a frozen or dry place little.
double PlanetWeather::moisture(const Vector3 &p_dir, const Ref<PlanetClock> &p_clock, double p_macro) const {
	double degrees = climate()->get_seasons()->at(p_dir, p_clock->year_share());
	if (macro_of(p_dir, p_macro) < 0.0) {
		return 0.25 + 0.75 * smooth_step(-30.0, 30.0, degrees);
	}
	double wet = CLAMP((double)climate()->sample(p_dir).y / 1.2, 0.0, 1.0);
	return wet * (0.25 + 0.75 * smooth_step(-30.0, 25.0, degrees));
}

// Where the cloud is: 0 clear sky .. 1 thick cloud, at `dir` at the clock's moment.
double PlanetWeather::cloud(const Vector3 &p_dir, const Ref<PlanetClock> &p_clock, double p_macro) const {
	return cloud_cells(p_dir, p_clock, p_macro).x;
}

// The cloud and, with it, the strength of the small clumps inside the systems (-1..1: the cells where a thick cloud rains hard are the high ones).
Vector2 PlanetWeather::cloud_cells(const Vector3 &p_dir, const Ref<PlanetClock> &p_clock, double p_macro) const {
	double ready = readiness(p_dir, p_clock, p_macro);
	double days = p_clock->absolute_days();
	double lat = std::asin(CLAMP((double)p_dir.y, -1.0, 1.0));
	double morph = 0.5 + 0.5 * std::sin(days * 0.45);
	// the winds carry each latitude at its own speed, which would stretch the pattern into long streaks as days go by: it is drawn twice,
	// drifted for at most SHEAR_DAYS each, and the two are faded into each other
	double first = positive_mod_d(days, SHEAR_DAYS);
	double second = positive_mod_d(days + SHEAR_DAYS * 0.5, SHEAR_DAYS);
	double weight = 1.0 - std::abs(2.0 * first / SHEAR_DAYS - 1.0);
	double pattern = 0.0;
	double cells = 0.0;
	for (int turn = 0; turn < 2; turn++) {
		double drift = turn == 0 ? first : second;
		double shift = zonal_wind(lat, wind_k_) * WIND_TURN * TAU_D * drift;
		double lon = std::atan2(p_dir.z, p_dir.x) - shift;
		Vector3 carried(std::cos(lat) * std::cos(lon), p_dir.y, std::cos(lat) * std::sin(lon));
		// the air swirls: the place the pattern is read from is pushed round by a slow noise
		double bend_x = warp->get_noise_3d(carried.x, carried.y, carried.z);
		double bend_y = warp->get_noise_3d(carried.z + 7.3, carried.x - 3.1, carried.y + 1.7);
		Vector3 bent = (carried + Vector3(bend_x, bend_y, bend_x - bend_y) * WARP).normalized();
		carried = bent;
		double big = lerp_d(big_a->get_noise_3d(carried.x, carried.y, carried.z), big_b->get_noise_3d(carried.x, carried.y, carried.z), morph);
		double clumps = small->get_noise_3d(carried.x, carried.y, carried.z);
		double share = turn == 0 ? weight : 1.0 - weight;
		pattern += CLAMP(0.5 + 0.5 * (0.75 * big + 0.35 * clumps), 0.0, 1.0) * share;
		cells += clumps * share;
	}
	double threshold = 0.97 - ready * 0.8;
	return Vector2(smooth_step(threshold - 0.12, threshold + 0.12, pattern), cells);
}

// The weather at `dir` (`ground` metres above the sea) right now: {"kind", "cloud", "ready"}.
Dictionary PlanetWeather::at(const Vector3 &p_dir, double p_ground, const Ref<PlanetClock> &p_clock) const {
	double ready = readiness(p_dir, p_clock, NAN);
	Vector2 cells = cloud_cells(p_dir, p_clock, NAN);
	double cover = cells.x;
	double degrees = noise()->call("temperature_now", p_dir.x, p_dir.y, p_dir.z, p_ground, p_clock);
	int kind = CLEAR;
	if (cover > 0.35) {
		kind = CLOUDY;
	}
	if (cover > 0.8 && ready > 0.45 && cells.y > 0.05) {
		kind = RAIN;
		if (ready > 0.8 && cells.y > 0.3 && degrees > 20.0) {
			kind = STORM;
		}
		if (degrees < 0.5) {
			kind = SNOW;
		}
	} else if (cover < 0.45 && ready > 0.4) {
		// fog: a still, wet morning (the air has cooled in the night)
		double hour = p_clock->local_hour(p_dir);
		if (hour > 3.0 && hour < 8.5 && moisture(p_dir, p_clock, NAN) > 0.5) {
			kind = FOG;
		}
	}
	Dictionary result;
	result["kind"] = kind;
	result["cloud"] = cover;
	result["ready"] = ready;
	result["degrees"] = degrees;
	return result;
}
