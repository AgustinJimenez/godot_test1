#include "planet_climate_native.h"

#include "planet_drainage_native.h"
#include "planet_seasons_native.h"
#include "planet_settings_native.h"

#include <godot_cpp/classes/random_number_generator.hpp>
#include <godot_cpp/variant/utility_functions.hpp>

#include <algorithm>
#include <cmath>

using namespace godot;

static const double TAU_D = 6.283185307179586476925286766559;
static const double PI_D = 3.14159265358979323846;

static double positive_mod_d(double p_x, double p_y) {
	double value = std::fmod(p_x, p_y);
	if ((value < 0.0 && p_y > 0.0) || (value > 0.0 && p_y < 0.0)) {
		value += p_y;
	}
	return value;
}

static int positive_mod_i(int p_x, int p_y) {
	int value = p_x % p_y;
	if (value < 0) {
		value += p_y;
	}
	return value;
}

// ---- PlanetSeasons ----

void PlanetSeasons::_bind_methods() {
	BIND_CONSTANT(WIDTH);
	BIND_CONSTANT(HEIGHT);
	BIND_CONSTANT(SNAPSHOTS);
	BIND_CONSTANT(PASSES);
	BIND_CONSTANT(MAX_YEARS);
	ClassDB::bind_static_method("PlanetSeasons", D_METHOD("dry"), &PlanetSeasons::dry);
	ClassDB::bind_static_method("PlanetSeasons", D_METHOD("currents"), &PlanetSeasons::currents);
	ClassDB::bind_static_method("PlanetSeasons", D_METHOD("heat"), &PlanetSeasons::heat);
	NP_BIND(PlanetSeasons, Variant::PACKED_FLOAT32_ARRAY, mean)
	NP_BIND(PlanetSeasons, Variant::FLOAT, greenhouse)
	NP_BIND(PlanetSeasons, Variant::FLOAT, wind_k)
	NP_BIND(PlanetSeasons, Variant::FLOAT, wind)
	NP_BIND(PlanetSeasons, Variant::BOOL, native_year)
	ClassDB::bind_method(D_METHOD("build", "noise", "clock"), &PlanetSeasons::build);
	ClassDB::bind_method(D_METHOD("coast_contrast"), &PlanetSeasons::coast_contrast);
	ClassDB::bind_method(D_METHOD("at", "dir", "year_share"), &PlanetSeasons::at);
	ClassDB::bind_method(D_METHOD("blended", "year_share"), &PlanetSeasons::blended);
	ClassDB::bind_method(D_METHOD("mean_at", "dir"), &PlanetSeasons::mean_at);
}

Dictionary PlanetSeasons::dry() {
	Dictionary d;
	d["max_distance"] = 99;
	d["belt_lat"] = 26.0;
	d["belt_width"] = 13.0;
	d["distance"] = 6.0;
	d["base"] = 0.3;
	d["belt_power"] = 0.9;
	d["scale"] = 100.0;
	return d;
}

Dictionary PlanetSeasons::currents() {
	Dictionary d;
	d["cold_lat"] = 22.0;
	d["cold_width"] = 14.0;
	d["warm_lat"] = 36.0;
	d["warm_width"] = 16.0;
	d["cold_power"] = 5.0;
	d["warm_power"] = 4.0;
	d["reach"] = 3;
	return d;
}

Dictionary PlanetSeasons::heat() {
	Dictionary d;
	d["emit"] = EMIT;
	d["floor"] = FLOOR;
	d["snow_albedo"] = SNOW_ALBEDO;
	d["land_tau"] = LAND_TAU;
	d["sea_tau"] = SEA_TAU;
	d["mix"] = MIX;
	d["hot"] = HOT;
	d["passes"] = PASSES;
	return d;
}

// Runs the planet through its year (`clock` carries the orbit and the tilt) until the cycle repeats.
void PlanetSeasons::build(Object *p_noise, const Ref<PlanetClock> &p_clock) {
	Ref<PlanetSeasonsNative> grid;
	grid.instantiate();
	PackedVector3Array dirs = grid->grid_dirs(WIDTH, HEIGHT);
	PackedFloat32Array grounds = p_noise->call("macro_heights_of", dirs);
	sea_ = grid->mark_sea(grounds, WIDTH, HEIGHT, dry());
	// the year, natively: the sunlight of every row at every moment, the orbit being the clock's
	Dictionary orbit;
	orbit["tilt"] = p_clock->get_axial_tilt();
	orbit["eccentricity"] = p_clock->get_eccentricity();
	orbit["perihelion"] = p_clock->get_perihelion_share();
	orbit["insolation"] = p_clock->get_insolation();
	orbit["greenhouse"] = greenhouse;
	PackedFloat32Array lights = grid->light_grid(SNAPSHOTS, HEIGHT, orbit);
	Dictionary made = grid->run(sea_, lights, WIDTH, HEIGHT, SNAPSHOTS, wind, MAX_YEARS, wind_k, heat());
	mean = made["mean"];
	Dictionary corrected = grid->add_currents(sea_, made["cycle"], mean, WIDTH, HEIGHT, currents());
	mean = corrected["mean"];
	cycle_ = corrected["cycle"];
}

// How much wider the yearly swing of temperature is on the land where the wind comes off the land than where it comes off the sea (degrees C,
// the middle latitudes of both hemispheres). For the lab: it should grow with `wind`.
double PlanetSeasons::coast_contrast() const {
	double windward = 0.0;
	double leeward = 0.0;
	int windward_count = 0;
	int leeward_count = 0;
	for (int row = 0; row < HEIGHT; row++) {
		double lat = std::abs((0.5 - ((double)row + 0.5) / (double)HEIGHT) * PI_D);
		if (lat < Math::deg_to_rad(35.0) || lat > Math::deg_to_rad(65.0)) {
			continue;
		}
		for (int column = 0; column < WIDTH; column++) {
			int index = row * WIDTH + column;
			if (sea_[index] == 1) {
				continue;
			}
			bool west_sea = sea_[row * WIDTH + (column + WIDTH - 1) % WIDTH] == 1;
			bool east_sea = sea_[row * WIDTH + (column + 1) % WIDTH] == 1;
			if (west_sea == east_sea) {
				continue;
			}
			double low = INFINITY;
			double high = -INFINITY;
			for (int i = 0; i < cycle_.size(); i++) {
				PackedFloat32Array picture = cycle_[i];
				low = std::min(low, (double)picture[index]);
				high = std::max(high, (double)picture[index]);
			}
			if (west_sea) {
				windward += high - low;
				windward_count += 1;
			} else {
				leeward += high - low;
				leeward_count += 1;
			}
		}
	}
	if (windward_count == 0 || leeward_count == 0) {
		return 0.0;
	}
	return leeward / (double)leeward_count - windward / (double)windward_count;
}

// Degrees C at sea level at the unit direction, `year_share` through the year (0 the northern spring equinox), read off the cycle.
double PlanetSeasons::at(const Vector3 &p_dir, double p_year_share) const {
	double position = positive_mod_d(p_year_share, 1.0) * (double)SNAPSHOTS;
	int first = (int)std::floor(position) % SNAPSHOTS;
	double blend = position - std::floor(position);
	double a = look(cycle_[first], p_dir);
	double b = look(cycle_[(first + 1) % SNAPSHOTS], p_dir);
	return a + (b - a) * blend;
}

// The whole grid at `year_share`: the two pictures of the cycle round it, blended.
PackedFloat32Array PlanetSeasons::blended(double p_year_share) const {
	double position = positive_mod_d(p_year_share, 1.0) * (double)SNAPSHOTS;
	int first = (int)std::floor(position) % SNAPSHOTS;
	double blend = position - std::floor(position);
	PackedFloat32Array a = cycle_[first];
	PackedFloat32Array b = cycle_[(first + 1) % SNAPSHOTS];
	Ref<PlanetSeasonsNative> seasons;
	seasons.instantiate();
	return seasons->blend(a, b, blend);
}

double PlanetSeasons::mean_at(const Vector3 &p_dir) const {
	return look(mean, p_dir);
}

double PlanetSeasons::look(const PackedFloat32Array &p_grid, const Vector3 &p_dir) {
	double lat = std::asin(CLAMP((double)p_dir.y, -1.0, 1.0));
	double lon = std::atan2(p_dir.z, p_dir.x);
	double fx = (lon + PI_D) / TAU_D * (double)WIDTH - 0.5;
	double fy = (0.5 - lat / PI_D) * (double)HEIGHT - 0.5;
	int x0 = (int)std::floor(fx);
	int y0 = (int)std::floor(fy);
	double tx = fx - (double)x0;
	double ty = fy - (double)y0;
	double total = 0.0;
	for (int dy = 0; dy < 2; dy++) {
		for (int dx = 0; dx < 2; dx++) {
			double weight = (dx == 1 ? tx : 1.0 - tx) * (dy == 1 ? ty : 1.0 - ty);
			total += p_grid[CLAMP(y0 + dy, 0, HEIGHT - 1) * WIDTH + positive_mod_i(x0 + dx, WIDTH)] * weight;
		}
	}
	return total;
}

// ---- PlanetClimate ----

PlanetClimate::PlanetClimate() {
	seasons_.instantiate();
	circulation_["itcz_lat"] = 0.0;
	circulation_["itcz_width"] = 9.0;
	circulation_["itcz_power"] = 0.8;
	circulation_["storm_lat"] = 48.0;
	circulation_["storm_power"] = 0.3;
	circulation_["dry_lat"] = 27.0;
	circulation_["dry_power"] = 0.55;
	circulation_["wind_low"] = 30.0;
	circulation_["wind_high"] = 60.0;
	circulation_["wind_k"] = 3.0;
}

void PlanetClimate::_bind_methods() {
	BIND_CONSTANT(WIDTH);
	BIND_CONSTANT(HEIGHT);
	ClassDB::bind_method(D_METHOD("get_seasons"), &PlanetClimate::get_seasons);
	ClassDB::bind_method(D_METHOD("set_seasons", "value"), &PlanetClimate::set_seasons);
	ADD_PROPERTY(PropertyInfo(Variant::OBJECT, "seasons", PROPERTY_HINT_RESOURCE_TYPE, "PlanetSeasons", PROPERTY_USAGE_NO_EDITOR), "set_seasons", "get_seasons");
	ClassDB::bind_method(D_METHOD("get_circulation"), &PlanetClimate::get_circulation);
	ClassDB::bind_method(D_METHOD("set_circulation", "value"), &PlanetClimate::set_circulation);
	ADD_PROPERTY(PropertyInfo(Variant::DICTIONARY, "circulation", PROPERTY_HINT_NONE, "", PROPERTY_USAGE_NO_EDITOR), "set_circulation", "get_circulation");
	NP_BIND_STATE(PlanetClimate, Variant::BOOL, native_rain)
	ClassDB::bind_method(D_METHOD("build", "noise"), &PlanetClimate::build);
	ClassDB::bind_method(D_METHOD("rain_grid"), &PlanetClimate::rain_grid);
	ClassDB::bind_method(D_METHOD("temperature_grid"), &PlanetClimate::temperature_grid);
	ClassDB::bind_method(D_METHOD("sea_temperature", "dir"), &PlanetClimate::sea_temperature);
	ClassDB::bind_method(D_METHOD("sample", "dir"), &PlanetClimate::sample);
}

void PlanetClimate::build(Object *p_noise) {
	Ref<PlanetSettings> settings = p_noise->get("settings");
	double relief = p_noise->get("relief");
	draw_circulation(settings->get_world_seed());
	Ref<PlanetSeasonsNative> air;
	air.instantiate();
	PackedVector3Array dirs = air->grid_dirs(WIDTH, HEIGHT); // (all the grid's heights in one go, on several threads)
	PackedFloat32Array grounds = p_noise->call("heights_of", dirs);
	Dictionary split = air->elevation_and_ocean(grounds, relief);
	PackedFloat32Array elevation = split["elevation"]; // in units of relief
	PackedByteArray ocean = split["ocean"];
	Ref<PlanetClock> clock; // the orbit and the tilt of this planet, for the seasons
	clock.instantiate();
	clock->set_day_seconds(settings->get_day_seconds());
	clock->set_year_days(settings->get_year_days());
	clock->set_axial_tilt(Math::deg_to_rad(settings->get_axial_tilt()));
	clock->set_insolation(settings->get_insolation());
	clock->set_eccentricity(settings->get_eccentricity());
	clock->set_perihelion_share(settings->get_perihelion_share());
	seasons_->set_wind_k(circulation_["wind_k"]);
	seasons_->set_greenhouse(settings->get_greenhouse());
	seasons_->build(p_noise, clock);
	Ref<PlanetDrainageNative> sampler;
	sampler.instantiate();
	temperature_ = sampler->sample_grid(seasons_->get_mean(), PlanetSeasons::WIDTH, PlanetSeasons::HEIGHT, dirs);
	rain_ = air->rain(elevation, ocean, temperature_, WIDTH, HEIGHT, RAIN_BASE, RAIN_SCALE, circulation_);
}

// Draws this planet's circulation from the seed (no two planets share one wet belt at the equator, one storm belt at 48 and one dry belt at 27).
void PlanetClimate::draw_circulation(int64_t p_world_seed) {
	Ref<RandomNumberGenerator> rng;
	rng.instantiate();
	rng->set_seed((uint64_t)(p_world_seed + 50));
	Dictionary c;
	c["itcz_lat"] = rng->randf_range(-6.0, 6.0);
	c["itcz_width"] = rng->randf_range(6.0, 13.0);
	c["itcz_power"] = rng->randf_range(0.35, 1.0);
	c["storm_lat"] = rng->randf_range(40.0, 56.0);
	c["storm_power"] = rng->randf_range(0.15, 0.45);
	c["dry_lat"] = rng->randf_range(20.0, 33.0);
	c["dry_power"] = rng->randf_range(0.3, 0.7);
	// the winds: -cos(k * latitude), k = how many belts of wind (a faster spinning planet has more)
	double k = rng->randf_range(2.6, 5.2);
	c["wind_k"] = k;
	c["wind_low"] = Math::rad_to_deg(PI_D * 0.5 / k);
	c["wind_high"] = std::min(Math::rad_to_deg(PI_D * 1.5 / k), 90.0);
	circulation_ = c;
}

// The year's mean temperature at sea level at the direction (15 before the climate is built).
double PlanetClimate::sea_temperature(const Vector3 &p_dir) const {
	return !temperature_.is_empty() ? sample(p_dir).x : 15.0;
}

// (sea level temperature in degrees C, averaged over the year; rain 0..1.6) at the unit direction.
Vector2 PlanetClimate::sample(const Vector3 &p_dir) const {
	double lat = std::asin(CLAMP((double)p_dir.y, -1.0, 1.0));
	double lon = std::atan2(p_dir.z, p_dir.x);
	double fx = (lon + PI_D) / TAU_D * (double)WIDTH - 0.5;
	double fy = (0.5 - lat / PI_D) * (double)HEIGHT - 0.5;
	int x0 = (int)std::floor(fx);
	int y0 = (int)std::floor(fy);
	double tx = fx - (double)x0;
	double ty = fy - (double)y0;
	double temperature = 0.0;
	double rain = 0.0;
	for (int dy = 0; dy < 2; dy++) {
		for (int dx = 0; dx < 2; dx++) {
			double weight = (dx == 1 ? tx : 1.0 - tx) * (dy == 1 ? ty : 1.0 - ty);
			int index = CLAMP(y0 + dy, 0, HEIGHT - 1) * WIDTH + positive_mod_i(x0 + dx, WIDTH);
			temperature += temperature_[index] * weight;
			rain += rain_[index] * weight;
		}
	}
	return Vector2(temperature, rain);
}
