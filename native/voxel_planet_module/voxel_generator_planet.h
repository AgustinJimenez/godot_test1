#ifndef VOXEL_GENERATOR_PLANET_H
#define VOXEL_GENERATOR_PLANET_H

// The planet's ground as voxels (task 096): the signed distance to the ground is |p| - (radius + the planet's height in the
// direction of p), solid is negative. The heights come from the planet's own native `PlanetNoise.heights_of` (the planet_crust
// extension; called by name, one call a block), sampled on a lattice and interpolated between (the lattice widens with the LOD),
// and the caves are the crossing of two simplex noises. The GDScript twin is tests/manual/voxel/real_planet_generator.gd.

#include "../voxel/generators/voxel_generator.h"
#include "../voxel/storage/voxel_buffer.h"
#include "../voxel/util/thread/rw_lock.h"

#include "core/math/basis.h"
#include "core/object/ref_counted.h"
#include "modules/noise/fastnoise_lite.h"

namespace zylann::voxel {

class VoxelGeneratorPlanet : public VoxelGenerator {
	GDCLASS(VoxelGeneratorPlanet, VoxelGenerator)

public:
	VoxelGeneratorPlanet();

	int get_used_channels_mask() const override;
	Result generate_block(VoxelGenerator::VoxelQueryData input) override;

	void set_radius(double p_radius);
	double get_radius() const;
	void set_noise(const Ref<RefCounted> &p_noise);
	Ref<RefCounted> get_noise() const;
	void set_frame(const Basis &p_frame);
	Basis get_frame() const;
	void set_exact_lods(int p_lods);
	int get_exact_lods() const;
	void set_mid_lods(int p_lods);
	int get_mid_lods() const;
	void set_lattice_mid(int p_spacing);
	int get_lattice_mid() const;
	void set_lattice_far(int p_spacing);
	int get_lattice_far() const;
	void set_caves(bool p_on);
	bool get_caves() const;
	void set_cave_seed(int p_seed);
	// 0: the ground; 1: the sea; 2: the rivers (the water as a thin volume over the ground, task 096; the noise answers river_waters_of)
	void set_water(int p_mode);
	int get_water() const;
	void set_sea_level(double p_level);
	double get_sea_level() const;
	int get_cave_seed() const;
	int64_t get_blocks_made() const;
	// How far a point is from the middle of a tunnel, in noise units (under 0.06: inside one)
	double get_cave_field(const Vector3 &p_position) const;

protected:
	static void _bind_methods();

private:
	// beyond this far from the surface (m) no ground height can change the sign: the block is filled without asking the planet
	static constexpr double RELIEF_MARGIN = 12000.0;
	static constexpr double SURFACE_BAND = 3.0; // voxels either side of the lattice's ground that the exact levels ask again
	static constexpr double CAVE_DEPTH = 200.0; // m below the ground the tunnels reach
	static constexpr int CAVE_MAX_LOD = 3; // the coarsest level that still carves them
	static constexpr double CAVE_FREQUENCY = 1.0 / 110.0;
	static constexpr double CAVE_WIDTH = 0.06; // noise units either side of the zero surfaces (about 4 m of radius)
	static constexpr double CAVE_SCALE = 110.0 / 1.5; // metres of distance per noise unit
	static constexpr double WATER_DEPTH = 6.0; // m of water kept under the ground line (what a dig can open)
	static constexpr int RIVER_MAX_LOD = 3; // the coarsest level that still has the rivers

	struct Parameters {
		double radius = 6371000.0;
		Basis frame; // turns a world direction into the planet's own
		int exact_lods = 1; // levels up to this ask for every voxel
		int mid_lods = 3; // levels up to this use lattice_mid
		int lattice_mid = 2;
		int lattice_far = 4;
		bool caves = false;
		int water = 0;
		double sea_level = 0.0;
	};

	int lattice_for(const Parameters &p_params, int p_lod) const;
	static bool heights_of(const Ref<RefCounted> &p_noise, const PackedVector3Array &p_dirs, PackedFloat32Array &r_heights);
	static bool river_levels(const Ref<RefCounted> &p_noise, const PackedVector3Array &p_dirs, PackedVector3Array &r_waters);
	void generate_water(VoxelBuffer &p_out, const Vector3 &p_origin, int p_lod, const Parameters &p_params, const Ref<RefCounted> &p_noise);

	Parameters _parameters;
	Ref<RefCounted> _noise;
	Ref<FastNoiseLite> _cave_a;
	Ref<FastNoiseLite> _cave_b;
	int _cave_seed = 0;
	int64_t _blocks_made = 0;
	RWLock _parameters_lock;
};

} // namespace zylann::voxel

#endif // VOXEL_GENERATOR_PLANET_H
