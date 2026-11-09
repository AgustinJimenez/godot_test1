#include "voxel_generator_planet.h"

#include "core/object/class_db.h"

namespace zylann::voxel {

VoxelGeneratorPlanet::VoxelGeneratorPlanet() {
	_cave_a.instantiate();
	_cave_b.instantiate();
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

VoxelGenerator::Result VoxelGeneratorPlanet::generate_block(VoxelGenerator::VoxelQueryData input) {
	Result result;
	Parameters params;
	Ref<RefCounted> noise;
	Ref<FastNoiseLite> cave_a;
	Ref<FastNoiseLite> cave_b;
	{
		RWLockRead rlock(_parameters_lock);
		params = _parameters;
		noise = _noise;
		cave_a = _cave_a;
		cave_b = _cave_b;
	}
	VoxelBuffer &out_buffer = input.voxel_buffer;
	const Vector3i size = out_buffer.get_size();
	const int lod = input.lod;
	const double step = double(1 << lod);
	const Vector3 origin = Vector3(input.origin_in_voxels);
	const double half_diagonal = Vector3(size).length() * step * 0.5;
	const Vector3 centre = origin + Vector3(size) * step * 0.5;
	const double centre_dist = centre.length() - params.radius;
	if (noise.is_null() || Math::abs(centre_dist) > RELIEF_MARGIN + half_diagonal) {
		out_buffer.clear_channel_f(VoxelBuffer::CHANNEL_SDF, centre_dist / step);
		return result;
	}

	// the planet's heights on a lattice of nodes `spacing` voxels apart (one more node past the block's end)
	const int spacing = lattice_for(params, lod);
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
	Variant dirs_variant = dirs;
	const Variant *args[1] = { &dirs_variant };
	Callable::CallError error;
	Variant answer = noise->callp(StringName("heights_of"), args, 1, error);
	if (error.error != Callable::CallError::CALL_OK || answer.get_type() != Variant::PACKED_FLOAT32_ARRAY) {
		ERR_PRINT_ONCE("VoxelGeneratorPlanet: the noise has no heights_of(dirs) -> PackedFloat32Array.");
		out_buffer.clear_channel_f(VoxelBuffer::CHANNEL_SDF, centre_dist / step);
		return result;
	}
	const PackedFloat32Array lattice_heights = answer;
	const float *node = lattice_heights.ptr();
	auto node_at = [&](int kx, int ky, int kz) -> double {
		return node[(kz * mx + kx) * my + ky];
	};

	const bool carve = params.caves && lod <= CAVE_MAX_LOD && cave_a.is_valid() && cave_b.is_valid();
	const double inv_spacing = 1.0 / spacing;
	for (int z = 0; z < size.z; ++z) {
		const int kz = z / spacing;
		const double tz = (z - kz * spacing) * inv_spacing;
		for (int x = 0; x < size.x; ++x) {
			const int kx = x / spacing;
			const double tx = (x - kx * spacing) * inv_spacing;
			for (int y = 0; y < size.y; ++y) {
				const int ky = y / spacing;
				const double ty = (y - ky * spacing) * inv_spacing;
				const double h00 = Math::lerp(node_at(kx, ky, kz), node_at(kx, ky + 1, kz), ty);
				const double h10 = Math::lerp(node_at(kx + 1, ky, kz), node_at(kx + 1, ky + 1, kz), ty);
				const double h01 = Math::lerp(node_at(kx, ky, kz + 1), node_at(kx, ky + 1, kz + 1), ty);
				const double h11 = Math::lerp(node_at(kx + 1, ky, kz + 1), node_at(kx + 1, ky + 1, kz + 1), ty);
				const double height = Math::lerp(Math::lerp(h00, h10, tx), Math::lerp(h01, h11, tx), tz);
				const Vector3 p = origin + Vector3(x, y, z) * step;
				double sdf = (p.length() - (params.radius + height)) / step;
				if (carve && sdf < 0.0 && sdf > -CAVE_DEPTH / step) {
					const double field = MAX(Math::abs((double)cave_a->get_noise_3d(p.x, p.y, p.z)),
							Math::abs((double)cave_b->get_noise_3d(p.x, p.y, p.z)));
					sdf = MAX(sdf, (CAVE_WIDTH - field) * CAVE_SCALE / step);
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
}

} // namespace zylann::voxel
