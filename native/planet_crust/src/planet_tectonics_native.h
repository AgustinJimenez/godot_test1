#pragma once

// PlanetTectonics (was systems/planet/planet_tectonics.gd): the plates of a planet and the land they make. A pure function of the direction and
// the seed. PlanetNoise hands its numbers (`_seeds`, `_spin`, `_continental` and the three noises) to the native crust.

#include "native_props.h"

#include <godot_cpp/classes/fast_noise_lite.hpp>
#include <godot_cpp/classes/ref.hpp>
#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/classes/random_number_generator.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/packed_vector3_array.hpp>
#include <godot_cpp/variant/vector3.hpp>

namespace godot {

class PlanetTectonics : public RefCounted {
	GDCLASS(PlanetTectonics, RefCounted)

	static constexpr double CONTINENT = 0.10; // base height of a continental plate (units of relief)
	static constexpr double OCEAN = -0.42; // base height of an oceanic plate
	static constexpr double BOUNDARY = 0.08; // radians: how wide a boundary's effect is (about 500 km on Earth)
	static constexpr double WARP = 0.20; // how far the plate edges are bent
	static constexpr double SOFT = 0.14; // radians: how fast a plate's say fades as it gets further than the nearest

	PackedVector3Array seeds; // the middle of each plate
	PackedVector3Array spin; // each plate's rotation (its velocity at p is spin x p)
	Array continental_; // (bool each)
	Ref<FastNoiseLite> warp_noise, ridge_noise, interior_noise;

	static double between(const Ref<RandomNumberGenerator> &p_rng, double p_low, double p_high);
	static void setup_noise(const Ref<FastNoiseLite> &p_noise, int64_t p_seed, double p_frequency, int p_octaves);
	Vector3 plate_shift(const Vector3 &p_dir) const;
	double boundary(int p_a, int p_b, const Vector3 &p_q, double p_edge) const;
	bool land(int p_index) const { return (bool)continental_[p_index]; }

protected:
	static void _bind_methods();

public:
	static double get_continent() { return CONTINENT; }
	static double get_ocean() { return OCEAN; }
	static double get_boundary() { return BOUNDARY; }
	static double get_soft() { return SOFT; }

	// `PlanetTectonics.new(world_seed, plates)` of the script
	static Ref<PlanetTectonics> create(int64_t p_world_seed, int64_t p_plates);

	PackedVector3Array get__seeds() const { return seeds; }
	void set__seeds(const PackedVector3Array &p_v) { seeds = p_v; }
	PackedVector3Array get__spin() const { return spin; }
	void set__spin(const PackedVector3Array &p_v) { spin = p_v; }
	Array get__continental() const { return continental_; }
	void set__continental(const Array &p_v) { continental_ = p_v; }
	Ref<FastNoiseLite> get__warp() const { return warp_noise; }
	void set__warp(const Ref<FastNoiseLite> &p_v) { warp_noise = p_v; }
	Ref<FastNoiseLite> get__ridge() const { return ridge_noise; }
	void set__ridge(const Ref<FastNoiseLite> &p_v) { ridge_noise = p_v; }
	Ref<FastNoiseLite> get__interior() const { return interior_noise; }
	void set__interior(const Ref<FastNoiseLite> &p_v) { interior_noise = p_v; }

	double height(const Vector3 &p_dir) const;
	Vector3 plate_at(const Vector3 &p_dir) const;
};

} // namespace godot
