#include "voxel_generator_planet.h"

#include "core/object/class_db.h"

#include <algorithm>
#include <vector>

namespace zylann::voxel {

VoxelGeneratorPlanet::VoxelGeneratorPlanet() {
	_cave_a.instantiate();
	_cave_b.instantiate();
	_cavern.instantiate();
	set_cave_seed(0);
}

int VoxelGeneratorPlanet::get_used_channels_mask() const {
	return 1 << VoxelBuffer::CHANNEL_SDF;
}

int VoxelGeneratorPlanet::lattice_for(const Parameters &p_params, int p_lod) const {
	if (p_lod <= p_params.exact_lods) {
		return 1;
	}
	return MAX(1, p_lod <= p_params.mid_lods ? p_params.lattice_mid : p_params.lattice_far);
}

// The planet's heights (m) in the given directions, by a call to its native `heights_of` (one call, many points).
bool VoxelGeneratorPlanet::heights_of(const Ref<RefCounted> &p_noise, const PackedVector3Array &p_dirs, PackedFloat32Array &r_heights) {
	Variant dirs_variant = p_dirs;
	const Variant *args[1] = { &dirs_variant };
	Callable::CallError error;
	Variant answer = p_noise->callp(StringName("heights_of"), args, 1, error);
	if (error.error != Callable::CallError::CALL_OK || answer.get_type() != Variant::PACKED_FLOAT32_ARRAY) {
		ERR_PRINT_ONCE("VoxelGeneratorPlanet: the noise has no heights_of(dirs) -> PackedFloat32Array.");
		return false;
	}
	r_heights = answer;
	return true;
}

// The water level of the river under each direction (x of the answer; -1e9 where there is none), by the noise's `river_waters_of`.
bool VoxelGeneratorPlanet::river_levels(const Ref<RefCounted> &p_noise, const PackedVector3Array &p_dirs, PackedVector3Array &r_waters) {
	Variant dirs_variant = p_dirs;
	const Variant *args[1] = { &dirs_variant };
	Callable::CallError error;
	Variant answer = p_noise->callp(StringName("river_waters_of"), args, 1, error);
	if (error.error != Callable::CallError::CALL_OK || answer.get_type() != Variant::PACKED_VECTOR3_ARRAY) {
		ERR_PRINT_ONCE("VoxelGeneratorPlanet: the noise has no river_waters_of(dirs) -> PackedVector3Array.");
		return false;
	}
	r_waters = answer;
	return true;
}

// The water as a volume: under the water's level (the sea's, or the river's) and not deeper than WATER_DEPTH under the ground line, so it is
// empty where the ground is above both. The heights and levels depend on the direction alone: they are asked on a grid across the block
// (tangent to the sphere at its middle) and interpolated, not at every node of a 3D lattice.
void VoxelGeneratorPlanet::generate_water(VoxelBuffer &p_out, const Vector3 &p_origin, int p_lod, const Parameters &p_params, const Ref<RefCounted> &p_noise) {
	const Vector3i size = p_out.get_size();
	const double step = double(1 << p_lod);
	const Vector3 centre = p_origin + Vector3(size) * step * 0.5;
	const double half = Vector3(size).length() * step * 0.5;
	const double centre_length = centre.length();
	const double none = 1000.0; // (outside the water: positive, however far)
	// no sea above its level, no river far above the ground or under it
	if (p_params.water == 1 && centre_length - half > p_params.radius + p_params.sea_level) {
		p_out.clear_channel_f(VoxelBuffer::CHANNEL_SDF, none);
		return;
	}
	const Vector3 up = centre / centre_length;
	const Vector3 e1 = up.cross(Math::abs(up.y) < 0.9 ? Vector3(0, 1, 0) : Vector3(1, 0, 0)).normalized();
	const Vector3 e2 = up.cross(e1);
	const double spacing = double(MAX(2, p_lod <= p_params.mid_lods ? p_params.lattice_mid : p_params.lattice_far)) * step;
	const int n = int(Math::ceil(2.0 * half / spacing)) + 2;
	PackedVector3Array dirs;
	dirs.resize(n * n);
	Vector3 *dir_write = dirs.ptrw();
	for (int j = 0; j < n; ++j) {
		for (int i = 0; i < n; ++i) {
			const Vector3 at = up * centre_length + e1 * (i * spacing - half) + e2 * (j * spacing - half);
			dir_write[j * n + i] = p_params.frame.xform(at).normalized();
		}
	}
	PackedFloat32Array grounds;
	if (!heights_of(p_noise, dirs, grounds)) {
		p_out.clear_channel_f(VoxelBuffer::CHANNEL_SDF, none);
		return;
	}
	std::vector<float> levels(n * n, (float)p_params.sea_level);
	bool any = p_params.water == 1;
	double highest = p_params.sea_level;
	double lowest_ground = 1.0e30;
	for (int k = 0; k < n * n; ++k) {
		lowest_ground = MIN(lowest_ground, (double)grounds[k]);
	}
	if (p_params.water == 2) {
		PackedVector3Array waters;
		if (!river_levels(p_noise, dirs, waters)) {
			p_out.clear_channel_f(VoxelBuffer::CHANNEL_SDF, none);
			return;
		}
		highest = -1.0e30;
		for (int k = 0; k < n * n; ++k) {
			const float level = waters[k].x;
			if (level > p_params.sea_level) {
				levels[k] = level;
				any = true;
				highest = MAX(highest, (double)level);
			} else {
				levels[k] = grounds[k] - 1000.0f; // (no river here: no water)
			}
		}
	}
	// (spacing of slack: the ground between the grid's points can dip under what they show)
	if (!any || centre_length - half > p_params.radius + highest + 1.0 || centre_length + half < p_params.radius + lowest_ground - WATER_DEPTH - spacing) {
		p_out.clear_channel_f(VoxelBuffer::CHANNEL_SDF, none);
		return;
	}
	const double inverse = 1.0 / spacing;
	const float *ground_read = grounds.ptr();
	int count = 0;
	for (int z = 0; z < size.z; ++z) {
		for (int x = 0; x < size.x; ++x) {
			for (int y = 0; y < size.y; ++y, ++count) {
				const Vector3 p = p_origin + Vector3(x, y, z) * step;
				const Vector3 d = p - centre;
				const double gu = CLAMP((d.dot(e1) + half) * inverse, 0.0, double(n - 1) - 0.001);
				const double gv = CLAMP((d.dot(e2) + half) * inverse, 0.0, double(n - 1) - 0.001);
				const int iu = int(gu), iv = int(gv);
				const double tu = gu - iu, tv = gv - iv;
				const int at = iv * n + iu;
				const double ground = Math::lerp(Math::lerp((double)ground_read[at], (double)ground_read[at + 1], tu), Math::lerp((double)ground_read[at + n], (double)ground_read[at + n + 1], tu), tv);
				const double level = Math::lerp(Math::lerp((double)levels[at], (double)levels[at + 1], tu), Math::lerp((double)levels[at + n], (double)levels[at + n + 1], tu), tv);
				const double distance = p.length() - p_params.radius;
				p_out.set_voxel_f((float)(MAX(distance - level, (ground - WATER_DEPTH) - distance) / step), x, y, z, VoxelBuffer::CHANNEL_SDF);
			}
		}
	}
}

VoxelGenerator::Result VoxelGeneratorPlanet::generate_block(VoxelGenerator::VoxelQueryData input) {
	Result result;
	Parameters params;
	Ref<RefCounted> noise;
	Ref<FastNoiseLite> cave_a;
	Ref<FastNoiseLite> cave_b;
	Ref<FastNoiseLite> cavern;
	{
		RWLockRead rlock(_parameters_lock);
		params = _parameters;
		noise = _noise;
		cave_a = _cave_a;
		cave_b = _cave_b;
		cavern = _cavern;
	}
	VoxelBuffer &out_buffer = input.voxel_buffer;
	const Vector3i size = out_buffer.get_size();
	const int lod = input.lod;
	const double step = double(1 << lod);
	const Vector3 origin = Vector3(input.origin_in_voxels);
	const double half_diagonal = Vector3(size).length() * step * 0.5;
	const Vector3 centre = origin + Vector3(size) * step * 0.5;
	if (params.water != 0 && noise.is_valid() && !(params.water == 2 && lod > RIVER_MAX_LOD)) {
		generate_water(out_buffer, origin, lod, params, noise);
		return result;
	}
	const double centre_dist = centre.length() - params.radius;
	if (params.water != 0 || noise.is_null() || Math::abs(centre_dist) > RELIEF_MARGIN + half_diagonal) {
		out_buffer.clear_channel_f(VoxelBuffer::CHANNEL_SDF, params.water != 0 ? 1000.0 : centre_dist / step); // (no water: far, or no rivers seen from far)
		return result;
	}

	// the planet's heights on a lattice of nodes `spacing` voxels apart (one more node past the block's end). The finest levels
	// (up to exact_lods) are exact at the surface: the voxels within SURFACE_BAND voxels of the lattice's ground are asked again
	// one by one (a lattice alone left a hole in the collision), the rest keep the lattice's height.
	const bool refine = lod <= params.exact_lods && params.lattice_mid > 1;
	const int spacing = refine ? params.lattice_mid : lattice_for(params, lod);
	const int mx = (size.x - 1) / spacing + 2;
	const int my = (size.y - 1) / spacing + 2;
	const int mz = (size.z - 1) / spacing + 2;
	PackedVector3Array dirs;
	dirs.resize(mx * my * mz);
	Vector3 *dir_write = dirs.ptrw();
	int n = 0;
	for (int kz = 0; kz < mz; ++kz) {
		for (int kx = 0; kx < mx; ++kx) {
			for (int ky = 0; ky < my; ++ky) {
				const Vector3 at = origin + Vector3(kx, ky, kz) * (spacing * step);
				dir_write[n++] = params.frame.xform(at).normalized();
			}
		}
	}
	PackedFloat32Array lattice_heights;
	if (!heights_of(noise, dirs, lattice_heights)) {
		out_buffer.clear_channel_f(VoxelBuffer::CHANNEL_SDF, centre_dist / step);
		return result;
	}
	const float *node = lattice_heights.ptr();
	auto node_at = [&](int kx, int ky, int kz) -> double {
		return node[(kz * mx + kx) * my + ky];
	};

	const int volume = size.x * size.y * size.z;
	std::vector<float> sdf_values(volume);
	std::vector<int> band; // the voxels asked again
	PackedVector3Array band_dirs;
	const double inv_spacing = 1.0 / spacing;
	int i = 0;
	for (int z = 0; z < size.z; ++z) {
		const int kz = z / spacing;
		const double tz = (z - kz * spacing) * inv_spacing;
		for (int x = 0; x < size.x; ++x) {
			const int kx = x / spacing;
			const double tx = (x - kx * spacing) * inv_spacing;
			for (int y = 0; y < size.y; ++y, ++i) {
				const int ky = y / spacing;
				const double ty = (y - ky * spacing) * inv_spacing;
				const double h00 = Math::lerp(node_at(kx, ky, kz), node_at(kx, ky + 1, kz), ty);
				const double h10 = Math::lerp(node_at(kx + 1, ky, kz), node_at(kx + 1, ky + 1, kz), ty);
				const double h01 = Math::lerp(node_at(kx, ky, kz + 1), node_at(kx, ky + 1, kz + 1), ty);
				const double h11 = Math::lerp(node_at(kx + 1, ky, kz + 1), node_at(kx + 1, ky + 1, kz + 1), ty);
				const double height = Math::lerp(Math::lerp(h00, h10, tx), Math::lerp(h01, h11, tx), tz);
				const Vector3 p = origin + Vector3(x, y, z) * step;
				const double sdf = (p.length() - (params.radius + height)) / step;
				sdf_values[i] = (float)sdf;
				if (refine && Math::abs(sdf) <= SURFACE_BAND) {
					band.push_back(i);
					band_dirs.push_back(params.frame.xform(p).normalized());
				}
			}
		}
	}
	if (!band.empty()) {
		PackedFloat32Array exact;
		if (heights_of(noise, band_dirs, exact)) {
			const float *exact_read = exact.ptr();
			for (size_t k = 0; k < band.size(); ++k) {
				const int index = band[k];
				const int y = index % size.y;
				const int x = (index / size.y) % size.x;
				const int z = index / (size.y * size.x);
				const Vector3 p = origin + Vector3(x, y, z) * step;
				sdf_values[index] = (float)((p.length() - (params.radius + exact_read[k])) / step);
			}
		}
	}

	const bool carve = params.caves && lod <= CAVE_MAX_LOD && cave_a.is_valid() && cave_b.is_valid();
	i = 0;
	for (int z = 0; z < size.z; ++z) {
		for (int x = 0; x < size.x; ++x) {
			for (int y = 0; y < size.y; ++y, ++i) {
				double sdf = sdf_values[i];
				if (carve && sdf < 0.0 && sdf > -CAVE_DEPTH / step) {
					const Vector3 p = origin + Vector3(x, y, z) * step;
					const double field = MAX(Math::abs((double)cave_a->get_noise_3d(p.x, p.y, p.z)),
							Math::abs((double)cave_b->get_noise_3d(p.x, p.y, p.z)));
					sdf = MAX(sdf, (CAVE_WIDTH - field) * CAVE_SCALE / step);
					const double depth = -sdf_values[i] * step; // (of the rock this voxel would have: the chambers keep a roof)
					const double shut = CLAMP((depth - CAVERN_ROOF) / 30.0, 0.0, 1.0);
					if (shut > 0.0) {
						const double room = (double)cavern->get_noise_3d(p.x, p.y, p.z) - CAVERN_LEVEL - (1.0 - shut) * 2.0;
						sdf = MAX(sdf, room * CAVERN_SCALE / step);
					}
				}
				out_buffer.set_voxel_f(sdf, x, y, z, VoxelBuffer::CHANNEL_SDF);
			}
		}
	}
	{
		RWLockWrite wlock(_parameters_lock);
		++_blocks_made;
	}
	return result;
}

void VoxelGeneratorPlanet::set_radius(double p_radius) {
	RWLockWrite wlock(_parameters_lock);
	_parameters.radius = p_radius;
}
double VoxelGeneratorPlanet::get_radius() const {
	RWLockRead rlock(_parameters_lock);
	return _parameters.radius;
}
void VoxelGeneratorPlanet::set_noise(const Ref<RefCounted> &p_noise) {
	RWLockWrite wlock(_parameters_lock);
	_noise = p_noise;
}
Ref<RefCounted> VoxelGeneratorPlanet::get_noise() const {
	RWLockRead rlock(_parameters_lock);
	return _noise;
}
void VoxelGeneratorPlanet::set_frame(const Basis &p_frame) {
	RWLockWrite wlock(_parameters_lock);
	_parameters.frame = p_frame;
}
Basis VoxelGeneratorPlanet::get_frame() const {
	RWLockRead rlock(_parameters_lock);
	return _parameters.frame;
}
void VoxelGeneratorPlanet::set_exact_lods(int p_lods) {
	RWLockWrite wlock(_parameters_lock);
	_parameters.exact_lods = p_lods;
}
int VoxelGeneratorPlanet::get_exact_lods() const {
	RWLockRead rlock(_parameters_lock);
	return _parameters.exact_lods;
}
void VoxelGeneratorPlanet::set_mid_lods(int p_lods) {
	RWLockWrite wlock(_parameters_lock);
	_parameters.mid_lods = p_lods;
}
int VoxelGeneratorPlanet::get_mid_lods() const {
	RWLockRead rlock(_parameters_lock);
	return _parameters.mid_lods;
}
void VoxelGeneratorPlanet::set_lattice_mid(int p_spacing) {
	RWLockWrite wlock(_parameters_lock);
	_parameters.lattice_mid = MAX(1, p_spacing);
}
int VoxelGeneratorPlanet::get_lattice_mid() const {
	RWLockRead rlock(_parameters_lock);
	return _parameters.lattice_mid;
}
void VoxelGeneratorPlanet::set_lattice_far(int p_spacing) {
	RWLockWrite wlock(_parameters_lock);
	_parameters.lattice_far = MAX(1, p_spacing);
}
int VoxelGeneratorPlanet::get_lattice_far() const {
	RWLockRead rlock(_parameters_lock);
	return _parameters.lattice_far;
}
void VoxelGeneratorPlanet::set_water(int p_mode) {
	RWLockWrite wlock(_parameters_lock);
	_parameters.water = CLAMP(p_mode, 0, 2);
}
int VoxelGeneratorPlanet::get_water() const {
	RWLockRead rlock(_parameters_lock);
	return _parameters.water;
}
void VoxelGeneratorPlanet::set_sea_level(double p_level) {
	RWLockWrite wlock(_parameters_lock);
	_parameters.sea_level = p_level;
}
double VoxelGeneratorPlanet::get_sea_level() const {
	RWLockRead rlock(_parameters_lock);
	return _parameters.sea_level;
}
void VoxelGeneratorPlanet::set_caves(bool p_on) {
	RWLockWrite wlock(_parameters_lock);
	_parameters.caves = p_on;
}
bool VoxelGeneratorPlanet::get_caves() const {
	RWLockRead rlock(_parameters_lock);
	return _parameters.caves;
}
void VoxelGeneratorPlanet::set_cave_seed(int p_seed) {
	RWLockWrite wlock(_parameters_lock);
	_cave_seed = p_seed;
	const int offsets[2] = { 11, 29 }; // (the same two noises as the GDScript twin)
	Ref<FastNoiseLite> noises[2] = { _cave_a, _cave_b };
	for (int i = 0; i < 2; ++i) {
		noises[i]->set_noise_type(FastNoiseLite::TYPE_SIMPLEX);
		noises[i]->set_frequency(CAVE_FREQUENCY);
		noises[i]->set_seed(p_seed + offsets[i]);
	}
	_cavern->set_noise_type(FastNoiseLite::TYPE_SIMPLEX);
	_cavern->set_frequency(CAVERN_FREQUENCY);
	_cavern->set_seed(p_seed + 53);
}
int VoxelGeneratorPlanet::get_cave_seed() const {
	RWLockRead rlock(_parameters_lock);
	return _cave_seed;
}
int64_t VoxelGeneratorPlanet::get_blocks_made() const {
	RWLockRead rlock(_parameters_lock);
	return _blocks_made;
}

double VoxelGeneratorPlanet::get_cave_field(const Vector3 &p_position) const {
	RWLockRead rlock(_parameters_lock);
	return MAX(Math::abs((double)_cave_a->get_noise_3d(p_position.x, p_position.y, p_position.z)),
			Math::abs((double)_cave_b->get_noise_3d(p_position.x, p_position.y, p_position.z)));
}

void VoxelGeneratorPlanet::_bind_methods() {
	ClassDB::bind_method(D_METHOD("set_radius", "radius"), &VoxelGeneratorPlanet::set_radius);
	ClassDB::bind_method(D_METHOD("get_radius"), &VoxelGeneratorPlanet::get_radius);
	ClassDB::bind_method(D_METHOD("set_noise", "noise"), &VoxelGeneratorPlanet::set_noise);
	ClassDB::bind_method(D_METHOD("get_noise"), &VoxelGeneratorPlanet::get_noise);
	ClassDB::bind_method(D_METHOD("set_frame", "frame"), &VoxelGeneratorPlanet::set_frame);
	ClassDB::bind_method(D_METHOD("get_frame"), &VoxelGeneratorPlanet::get_frame);
	ClassDB::bind_method(D_METHOD("set_exact_lods", "lods"), &VoxelGeneratorPlanet::set_exact_lods);
	ClassDB::bind_method(D_METHOD("get_exact_lods"), &VoxelGeneratorPlanet::get_exact_lods);
	ClassDB::bind_method(D_METHOD("set_mid_lods", "lods"), &VoxelGeneratorPlanet::set_mid_lods);
	ClassDB::bind_method(D_METHOD("get_mid_lods"), &VoxelGeneratorPlanet::get_mid_lods);
	ClassDB::bind_method(D_METHOD("set_lattice_mid", "spacing"), &VoxelGeneratorPlanet::set_lattice_mid);
	ClassDB::bind_method(D_METHOD("get_lattice_mid"), &VoxelGeneratorPlanet::get_lattice_mid);
	ClassDB::bind_method(D_METHOD("set_lattice_far", "spacing"), &VoxelGeneratorPlanet::set_lattice_far);
	ClassDB::bind_method(D_METHOD("get_lattice_far"), &VoxelGeneratorPlanet::get_lattice_far);
	ClassDB::bind_method(D_METHOD("set_caves", "on"), &VoxelGeneratorPlanet::set_caves);
	ClassDB::bind_method(D_METHOD("get_caves"), &VoxelGeneratorPlanet::get_caves);
	ClassDB::bind_method(D_METHOD("set_cave_seed", "seed"), &VoxelGeneratorPlanet::set_cave_seed);
	ClassDB::bind_method(D_METHOD("get_cave_seed"), &VoxelGeneratorPlanet::get_cave_seed);
	ClassDB::bind_method(D_METHOD("set_water", "mode"), &VoxelGeneratorPlanet::set_water);
	ClassDB::bind_method(D_METHOD("get_water"), &VoxelGeneratorPlanet::get_water);
	ClassDB::bind_method(D_METHOD("set_sea_level", "level"), &VoxelGeneratorPlanet::set_sea_level);
	ClassDB::bind_method(D_METHOD("get_sea_level"), &VoxelGeneratorPlanet::get_sea_level);
	ClassDB::bind_method(D_METHOD("get_blocks_made"), &VoxelGeneratorPlanet::get_blocks_made);
	ClassDB::bind_method(D_METHOD("get_cave_field", "position"), &VoxelGeneratorPlanet::get_cave_field);

	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "radius"), "set_radius", "get_radius");
	ADD_PROPERTY(PropertyInfo(Variant::OBJECT, "noise", PROPERTY_HINT_NONE, "", PROPERTY_USAGE_NONE), "set_noise", "get_noise");
	ADD_PROPERTY(PropertyInfo(Variant::BASIS, "frame"), "set_frame", "get_frame");
	ADD_PROPERTY(PropertyInfo(Variant::INT, "exact_lods"), "set_exact_lods", "get_exact_lods");
	ADD_PROPERTY(PropertyInfo(Variant::INT, "mid_lods"), "set_mid_lods", "get_mid_lods");
	ADD_PROPERTY(PropertyInfo(Variant::INT, "lattice_mid"), "set_lattice_mid", "get_lattice_mid");
	ADD_PROPERTY(PropertyInfo(Variant::INT, "lattice_far"), "set_lattice_far", "get_lattice_far");
	ADD_PROPERTY(PropertyInfo(Variant::BOOL, "caves"), "set_caves", "get_caves");
	ADD_PROPERTY(PropertyInfo(Variant::INT, "cave_seed"), "set_cave_seed", "get_cave_seed");
	ADD_PROPERTY(PropertyInfo(Variant::INT, "water"), "set_water", "get_water");
	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "sea_level"), "set_sea_level", "get_sea_level");
}

} // namespace zylann::voxel
