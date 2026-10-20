#pragma once

// The planet's year of temperatures (the energy balance of PlanetSeasons on its coarse grid), run
// natively: the same steps as the script, which keeps the numbers (the sunlight of each row at each
// moment comes in from the script, which owns the orbit).

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/packed_byte_array.hpp>
#include <godot_cpp/variant/packed_float32_array.hpp>
#include <godot_cpp/variant/packed_vector3_array.hpp>

namespace godot {

class PlanetSeasonsNative : public RefCounted {
	GDCLASS(PlanetSeasonsNative, RefCounted)

protected:
	static void _bind_methods();

public:
	// `sea`: 1 where a cell is sea (width x height, rows from the north); `lights`: for every one of
	// `snapshots` moments of the year the sunlight of each row. Returns {"mean": the year's mean
	// grid, "cycle": the `snapshots` pictures of the last year}.
	// The rain of the climate map (PlanetClimate._advect_row and _smooth): air moves along every row on the
	// prevailing wind, picking up water over the sea and dropping it over land. `elevation` is in units of
	// relief, `ocean` 1 on the sea, `temperature` degrees C at sea level.
	PackedFloat32Array rain(const PackedFloat32Array &p_elevation, const PackedByteArray &p_ocean,
			const PackedFloat32Array &p_temperature, int p_width, int p_height, double p_rain_base,
			double p_rain_scale, const Dictionary &p_belts = Dictionary()) const;
	// the unit directions of a width x height grid of cell centres (rows from the north pole, columns from the west)
	PackedVector3Array grid_dirs(int p_width, int p_height) const;
	PackedByteArray mark_sea(const PackedFloat32Array &p_grounds, int p_width, int p_height,
			const Dictionary &p_dry) const;
	Dictionary add_currents(const PackedByteArray &p_sea, const Array &p_cycle,
			const PackedFloat32Array &p_mean, int p_width, int p_height,
			const Dictionary &p_currents) const;
	PackedFloat32Array blend(const PackedFloat32Array &p_first,
			const PackedFloat32Array &p_next, double p_weight) const;
	PackedFloat32Array light_grid(int p_snapshots, int p_height,
			const Dictionary &p_orbit) const;
	// {"elevation": the heights in units of `relief`, "ocean": 1 where the ground is under the sea level (0)}
	Dictionary elevation_and_ocean(const PackedFloat32Array &p_grounds, double p_relief) const;
	Dictionary run(const PackedByteArray &p_sea, const PackedFloat32Array &p_lights, int p_width, int p_height,
			int p_snapshots, double p_wind, int p_max_years, double p_wind_k,
			const Dictionary &p_heat) const;
};

} // namespace godot
