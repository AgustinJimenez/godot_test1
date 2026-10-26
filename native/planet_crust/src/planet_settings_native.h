#pragma once

// PlanetSettings (was systems/planet/planet_settings.gd): every number a planet is made from. Same seed + same settings = same planet.

#include "native_props.h"

#include <godot_cpp/classes/resource.hpp>
#include <godot_cpp/classes/ref.hpp>

namespace godot {

class PlanetSettings : public Resource {
	GDCLASS(PlanetSettings, Resource)

protected:
	static void _bind_methods();

public:
	NP_FIELD(int64_t, world_seed, 1337)
	NP_FIELD(double, radius, 20000.0) // m, the sea level sphere (Earth: 6,371,000)
	NP_FIELD(double, sea_level, 0.0) // m above `radius`
	NP_FIELD(double, relief, 0.0) // m from the sea to the highest ranges; 0: from the radius (at least 300)
	NP_FIELD(double, ocean_fraction, 0.7)
	NP_FIELD(double, water_layer, 0.0) // m: the planet's water as a layer over the whole planet (Earth 2,700); 0: use ocean_fraction
	NP_FIELD(int64_t, crust_samples, 6000)
	NP_FIELD(int64_t, species_count, 120)
	NP_FIELD(bool, plants_on, false)
	NP_FIELD(bool, animals_on, false)
	NP_FIELD(double, plant_density, 1.0)
	NP_FIELD(double, rock_density, 1.0)
	NP_FIELD(double, lake_depth_share, 0.08)
	NP_FIELD(bool, sea_on, true)
	NP_FIELD(bool, hydrology_on, true)
	NP_FIELD(int64_t, drainage_cells, 0)
	NP_FIELD(double, day_seconds, 1440.0)
	NP_FIELD(double, year_days, 16.0)
	NP_FIELD(double, month_days, 3.5)
	NP_FIELD(double, axial_tilt, 23.4)
	NP_FIELD(double, start_hour, 9.0)
	NP_FIELD(double, start_year, 0.12)
	NP_FIELD(double, time_scale, 1.0)
	NP_FIELD(double, star_mass, 1.0)
	NP_FIELD(double, star_readability, 0.0)
	NP_FIELD(double, eccentricity, 0.0)
	NP_FIELD(double, perihelion_share, 0.0)
	NP_FIELD(double, greenhouse, 1.0)
	NP_FIELD(double, insolation, 1.0)
	NP_FIELD(int64_t, universe_seed, 0)
	NP_FIELD(int64_t, universe_system, 0)
	NP_FIELD(int64_t, universe_planet, 0)
	NP_FIELD(int64_t, universe_sunlike, 1)
	NP_FIELD(double, air_height, 100000.0)
	NP_FIELD(int64_t, plates, 14)
	NP_FIELD(int64_t, tile_cells, 48)
	NP_FIELD(double, tile_max, 128.0)
	NP_FIELD(double, split_factor, 2.0)
	NP_FIELD(double, collide_tiles, 1.2)

	void vary();
	static Ref<PlanetSettings> earth(double p_scale = 1.0);
	int64_t max_level() const;
};

} // namespace godot
