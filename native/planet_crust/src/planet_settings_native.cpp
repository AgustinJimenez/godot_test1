#include "planet_settings_native.h"

#include <godot_cpp/classes/random_number_generator.hpp>
#include <godot_cpp/core/math.hpp>

#include <algorithm>
#include <cmath>

using namespace godot;

void PlanetSettings::_bind_methods() {
#define B(VT, N) NP_BIND(PlanetSettings, VT, N)
	B(Variant::INT, world_seed)
	B(Variant::FLOAT, radius)
	B(Variant::FLOAT, sea_level)
	B(Variant::FLOAT, relief)
	B(Variant::FLOAT, ocean_fraction)
	B(Variant::FLOAT, water_layer)
	B(Variant::INT, crust_samples)
	B(Variant::INT, species_count)
	B(Variant::BOOL, plants_on)
	B(Variant::BOOL, animals_on)
	B(Variant::FLOAT, plant_density)
	B(Variant::FLOAT, rock_density)
	B(Variant::FLOAT, lake_depth_share)
	B(Variant::BOOL, sea_on)
	B(Variant::BOOL, hydrology_on)
	B(Variant::INT, drainage_cells)
	B(Variant::FLOAT, day_seconds)
	B(Variant::FLOAT, year_days)
	B(Variant::FLOAT, month_days)
	B(Variant::FLOAT, axial_tilt)
	B(Variant::FLOAT, start_hour)
	B(Variant::FLOAT, start_year)
	B(Variant::FLOAT, time_scale)
	B(Variant::FLOAT, star_mass)
	B(Variant::FLOAT, star_readability)
	B(Variant::FLOAT, eccentricity)
	B(Variant::FLOAT, perihelion_share)
	B(Variant::FLOAT, greenhouse)
	B(Variant::FLOAT, insolation)
	B(Variant::INT, universe_seed)
	B(Variant::INT, universe_system)
	B(Variant::INT, universe_planet)
	B(Variant::INT, universe_sunlike)
	B(Variant::FLOAT, air_height)
	B(Variant::INT, plates)
	B(Variant::INT, tile_cells)
	B(Variant::FLOAT, tile_max)
	B(Variant::FLOAT, split_factor)
	B(Variant::FLOAT, collide_tiles)
#undef B
	ClassDB::bind_method(D_METHOD("vary"), &PlanetSettings::vary);
	ClassDB::bind_static_method("PlanetSettings", D_METHOD("earth", "scale"), &PlanetSettings::earth, DEFVAL(1.0));
	ClassDB::bind_method(D_METHOD("max_level"), &PlanetSettings::max_level);
}

// Makes this world its own, from its seed: how much water it holds and how far its axis leans (the rest stays as it was set).
void PlanetSettings::vary() {
	Ref<RandomNumberGenerator> roll;
	roll.instantiate();
	roll->set_seed(world_seed);
	water_layer *= std::exp(roll->randf_range(std::log(0.3), std::log(2.8))); // (from a dry world to a water one)
	axial_tilt = roll->randf_range(8.0, 38.0);
	greenhouse = roll->randf_range(0.85, 1.25);
}

// The Earth: its size, its day, year and month, its tilt and orbit, its oceans, around the Sun; `scale` makes a smaller Earth to work on.
Ref<PlanetSettings> PlanetSettings::earth(double p_scale) {
	Ref<PlanetSettings> made;
	made.instantiate();
	made->world_seed = 1337;
	made->radius = 6371000.0 * p_scale;
	made->ocean_fraction = 0.71;
	made->drainage_cells = CLAMP((int64_t)std::llround(512.0 * p_scale), 96, 512);
	made->water_layer = 2000.0 * p_scale;
	made->plates = 15;
	made->day_seconds = 86400.0;
	made->year_days = 365.25;
	made->month_days = 29.53;
	made->axial_tilt = 23.44;
	made->eccentricity = 0.0167;
	made->perihelion_share = 0.789;
	made->star_mass = 1.0;
	made->insolation = 1.0;
	made->start_year = 0.12;
	made->start_hour = 9.0;
	return made;
}

// How many times a cube face is halved to get the finest tiles.
int64_t PlanetSettings::max_level() const {
	double face_arc = radius * Math_PI * 0.5;
	return std::max((int64_t)std::ceil(std::log(face_arc / tile_max) / std::log(2.0)), (int64_t)0);
}
