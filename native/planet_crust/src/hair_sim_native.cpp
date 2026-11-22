#include "hair_sim_native.h"

#include <godot_cpp/classes/image.hpp>
#include <godot_cpp/classes/mesh_instance3d.hpp>
#include <godot_cpp/classes/array_mesh.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/core/math.hpp>
#include <godot_cpp/variant/packed_float32_array.hpp>
#include <godot_cpp/variant/packed_vector3_array.hpp>
#include <godot_cpp/variant/string_name.hpp>

#include <algorithm>
#include <cmath>
#include <cstring>

namespace godot {

void HairSim::_bind_methods() {
	ClassDB::bind_method(D_METHOD("set_hair", "hair"), &HairSim::set_hair);
	ClassDB::bind_method(D_METHOD("get_hair"), &HairSim::get_hair);
	ClassDB::bind_method(D_METHOD("set_material", "material"), &HairSim::set_material);
	ClassDB::bind_method(D_METHOD("get_material"), &HairSim::get_material);
	ClassDB::bind_method(D_METHOD("set_gravity", "value"), &HairSim::set_gravity);
	ClassDB::bind_method(D_METHOD("get_gravity"), &HairSim::get_gravity);
	ClassDB::bind_method(D_METHOD("set_damping", "value"), &HairSim::set_damping);
	ClassDB::bind_method(D_METHOD("get_damping"), &HairSim::get_damping);
	ClassDB::bind_method(D_METHOD("set_root_stiffness", "value"), &HairSim::set_root_stiffness);
	ClassDB::bind_method(D_METHOD("get_root_stiffness"), &HairSim::get_root_stiffness);
	ClassDB::bind_method(D_METHOD("set_tip_stiffness", "value"), &HairSim::set_tip_stiffness);
	ClassDB::bind_method(D_METHOD("get_tip_stiffness"), &HairSim::get_tip_stiffness);
	ClassDB::bind_method(D_METHOD("set_iterations", "value"), &HairSim::set_iterations);
	ClassDB::bind_method(D_METHOD("get_iterations"), &HairSim::get_iterations);
	ClassDB::bind_method(D_METHOD("set_collisions", "capsules"), &HairSim::set_collisions);
	ClassDB::bind_method(D_METHOD("set_surface_collision", "value"), &HairSim::set_surface_collision);
	ClassDB::bind_method(D_METHOD("get_surface_collision"), &HairSim::get_surface_collision);
	ClassDB::bind_method(D_METHOD("get_penetration_count"), &HairSim::get_penetration_count);
	ClassDB::bind_method(D_METHOD("get_guide_count"), &HairSim::get_guide_count);
	ClassDB::bind_method(D_METHOD("rebind"), &HairSim::rebind);
	ClassDB::bind_method(D_METHOD("kick", "impulse"), &HairSim::kick);
	ADD_PROPERTY(PropertyInfo(Variant::OBJECT, "hair", PROPERTY_HINT_NODE_TYPE, "MeshInstance3D"), "set_hair", "get_hair");
	ADD_PROPERTY(PropertyInfo(Variant::OBJECT, "material", PROPERTY_HINT_RESOURCE_TYPE, "ShaderMaterial"), "set_material", "get_material");
	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "gravity"), "set_gravity", "get_gravity");
	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "damping"), "set_damping", "get_damping");
	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "root_stiffness"), "set_root_stiffness", "get_root_stiffness");
	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "tip_stiffness"), "set_tip_stiffness", "get_tip_stiffness");
	ADD_PROPERTY(PropertyInfo(Variant::INT, "iterations"), "set_iterations", "get_iterations");
}

void HairSim::set_hair(Object *p_hair) {
	hair_id = p_hair != nullptr ? p_hair->get_instance_id() : ObjectID();
	bound = false;
}

Object *HairSim::get_hair() const {
	return ObjectDB::get_instance(hair_id);
}

void HairSim::set_material(Object *p_material) {
	material_id = p_material != nullptr ? p_material->get_instance_id() : ObjectID();
	bound = false;
}

Object *HairSim::get_material() const {
	return ObjectDB::get_instance(material_id);
}

void HairSim::set_collisions(const PackedFloat32Array &p_capsules) {
	capsules.assign(size_t(p_capsules.size()), 0.0f);
	for (int64_t i = 0; i < p_capsules.size(); i++) {
		capsules[size_t(i)] = p_capsules[i];
	}
}

static int64_t cell_key(int x, int y, int z) {
	return (int64_t(x + 512) << 40) | (int64_t(y + 512) << 20) | int64_t(z + 512);
}

void HairSim::build_surface_grid() {
	surface_grid.clear();
	for (size_t i = 0; i < surface_p.size(); i++) {
		const Vector3 &v = surface_p[i];
		surface_grid[cell_key(int(std::floor(double(v.x) / surface_cell)), int(std::floor(double(v.y) / surface_cell)), int(std::floor(double(v.z) / surface_cell)))].push_back(int(i));
	}
}

// Pushes a point (world) out of the body surface: the nearest surface vertex within one cell and its normal.
void HairSim::collide_surface(Vector3 &p_world, const Transform3D &p_xf, const Transform3D &p_inv) const {
	if (!surface_collision || surface_p.empty()) {
		return;
	}
	const Vector3 p = p_inv.xform(p_world);
	const int cx = int(std::floor(double(p.x) / surface_cell));
	const int cy = int(std::floor(double(p.y) / surface_cell));
	const int cz = int(std::floor(double(p.z) / surface_cell));
	int best = -1;
	double best_d2 = surface_cell * surface_cell;
	for (int dx = -1; dx <= 1; dx++) {
		for (int dy = -1; dy <= 1; dy++) {
			for (int dz = -1; dz <= 1; dz++) {
				const auto it = surface_grid.find(cell_key(cx + dx, cy + dy, cz + dz));
				if (it == surface_grid.end()) {
					continue;
				}
				for (const int i : it->second) {
					const double d2 = double((p - surface_p[size_t(i)]).length_squared());
					if (d2 < best_d2) {
						best_d2 = d2;
						best = i;
					}
				}
			}
		}
	}
	if (best < 0) {
		return;
	}
	const Vector3 &n = surface_n[size_t(best)];
	const double depth = double((p - surface_p[size_t(best)]).dot(n));
	if (depth < surface_margin) {
		const Vector3 fixed = p + n * real_t(surface_margin - depth);
		p_world = p_xf.xform(fixed);
	}
}

int HairSim::get_penetration_count() {
	MeshInstance3D *mi = Object::cast_to<MeshInstance3D>(get_hair());
	if (mi == nullptr || !bound) {
		return -1;
	}
	const Transform3D inv = mi->get_global_transform().affine_inverse();
	int count = 0;
	for (size_t g = 0; g < size_t(guide_count); g++) {
		for (size_t k = 1; k < size_t(steps); k++) {
			const Vector3 p = inv.xform(pos[g * size_t(steps) + k]);
			int best = -1;
			double best_d2 = surface_cell * surface_cell;
			const int cx = int(std::floor(double(p.x) / surface_cell)), cy = int(std::floor(double(p.y) / surface_cell)), cz = int(std::floor(double(p.z) / surface_cell));
			for (int dx = -1; dx <= 1; dx++) {
				for (int dy = -1; dy <= 1; dy++) {
					for (int dz = -1; dz <= 1; dz++) {
						const auto it = surface_grid.find(cell_key(cx + dx, cy + dy, cz + dz));
						if (it == surface_grid.end()) {
							continue;
						}
						for (const int i : it->second) {
							const double d2 = double((p - surface_p[size_t(i)]).length_squared());
							if (d2 < best_d2) {
								best_d2 = d2;
								best = i;
							}
						}
					}
				}
			}
			if (best >= 0 && double((p - surface_p[size_t(best)]).dot(surface_n[size_t(best)])) < -0.002) {
				count++;
			}
		}
	}
	return count;
}

void HairSim::kick(const Vector3 &p_impulse) {
	// a velocity change: move the previous positions back
	for (size_t i = 0; i < pos.size(); i++) {
		if (i % size_t(std::max(steps, 1)) != 0) {
			prev[i] -= p_impulse * real_t(1.0 / 60.0);
		}
	}
}

// Reads the guides, the colliders and the point count from the hair mesh and makes the texture.
void HairSim::bind_mesh() {
	bound = false;
	primed = false;
	MeshInstance3D *mi = Object::cast_to<MeshInstance3D>(get_hair());
	if (mi == nullptr) {
		return;
	}
	Ref<ArrayMesh> mesh = mi->get_mesh();
	if (mesh.is_null() || !mesh->has_meta("hair_guides")) {
		return;
	}
	PackedVector3Array guides = mesh->get_meta("hair_guides");
	guide_count = int(int64_t(mesh->get_meta("hair_guide_count")));
	steps = int(int64_t(mesh->get_meta("hair_guide_steps")));
	if (guide_count <= 0 || steps < 2 || guides.size() != int64_t(guide_count) * steps) {
		return;
	}
	rest.assign(size_t(guides.size()), Vector3());
	for (int64_t i = 0; i < guides.size(); i++) {
		rest[size_t(i)] = guides[i];
	}
	link.assign(size_t(guide_count) * size_t(steps - 1), 0.0);
	for (int g = 0; g < guide_count; g++) {
		for (int k = 0; k < steps - 1; k++) {
			link[size_t(g) * size_t(steps - 1) + size_t(k)] = double(rest[size_t(g) * size_t(steps) + size_t(k + 1)].distance_to(rest[size_t(g) * size_t(steps) + size_t(k)]));
		}
	}
	if (mesh->has_meta("hair_colliders")) {
		set_collisions(mesh->get_meta("hair_colliders"));
	}
	surface_p.clear();
	surface_n.clear();
	if (mesh->has_meta("hair_surface_points") && mesh->has_meta("hair_surface_normals")) {
		PackedVector3Array sp = mesh->get_meta("hair_surface_points");
		PackedVector3Array sn = mesh->get_meta("hair_surface_normals");
		if (sp.size() == sn.size()) {
			surface_p.assign(sp.ptr(), sp.ptr() + sp.size());
			surface_n.assign(sn.ptr(), sn.ptr() + sn.size());
		}
	}
	build_surface_grid();
	pos.assign(rest.size(), Vector3());
	prev.assign(rest.size(), Vector3());
	bytes.resize(int64_t(guide_count) * steps * 3 * 4);
	bytes.fill(0);
	Ref<Image> image = Image::create_from_data(steps, guide_count, false, Image::FORMAT_RGBF, bytes);
	texture = ImageTexture::create_from_image(image);
	ShaderMaterial *material = Object::cast_to<ShaderMaterial>(get_material());
	if (material != nullptr) {
		material->set_shader_parameter(StringName("sim_tex"), texture);
		material->set_shader_parameter(StringName("use_sim"), true);
	}
	bound = true;
}

void HairSim::step(double p_dt, const Transform3D &p_xf) {
	const Vector3 g_dt2 = Vector3(0.0f, real_t(-gravity * p_dt * p_dt), 0.0f);
	const Basis basis = p_xf.basis;
	// colliders to world
	struct Capsule {
		Vector3 a, b;
		double r;
	};
	std::vector<Capsule> world;
	const double scale = double(basis.get_scale().x);
	for (size_t i = 0; i + 6 < capsules.size(); i += 7) {
		Capsule c;
		c.a = p_xf.xform(Vector3(capsules[i], capsules[i + 1], capsules[i + 2]));
		c.b = p_xf.xform(Vector3(capsules[i + 3], capsules[i + 4], capsules[i + 5]));
		c.r = double(capsules[i + 6]) * scale + collision_margin;
		world.push_back(c);
	}
	const Transform3D inverse = p_xf.affine_inverse();
	const size_t n = size_t(steps);
	for (int g = 0; g < guide_count; g++) {
		Vector3 *p = &pos[size_t(g) * n];
		Vector3 *q = &prev[size_t(g) * n];
		const Vector3 *r = &rest[size_t(g) * n];
		const double *len = &link[size_t(g) * (n - 1)];
		// the root follows the scalp
		p[0] = p_xf.xform(r[0]);
		q[0] = p[0];
		for (size_t k = 1; k < n; k++) {
			const Vector3 velocity = (p[k] - q[k]) * real_t(damping);
			q[k] = p[k];
			p[k] += velocity + g_dt2;
			// back toward the style: the rest place in the head's frame
			const double along = double(k) / double(n - 1);
			const double stiff = root_stiffness + (tip_stiffness - root_stiffness) * along;
			p[k] += (p_xf.xform(r[k]) - p[k]) * real_t(stiff);
		}
		for (int it = 0; it < iterations; it++) {
			for (size_t k = 1; k < n; k++) {
				Vector3 d = p[k] - p[k - 1];
				const double dl = double(d.length());
				if (dl > 1e-9) {
					const double diff = (dl - len[k - 1]) / dl;
					if (k == 1) {
						p[k] -= d * real_t(diff);
					} else {
						p[k] -= d * real_t(diff * 0.5);
						p[k - 1] += d * real_t(diff * 0.5);
					}
				}
			}
			for (size_t k = 1; k < n; k++) {
				for (const Capsule &c : world) {
					const Vector3 ab = c.b - c.a;
					const double ab2 = double(ab.length_squared());
					double t = ab2 > 1e-12 ? double((p[k] - c.a).dot(ab)) / ab2 : 0.0;
					t = std::max(0.0, std::min(1.0, t));
					const Vector3 closest = c.a + ab * real_t(t);
					Vector3 out = p[k] - closest;
					const double dist = double(out.length());
					if (dist < c.r) {
						if (dist > 1e-9) {
							p[k] = closest + out * real_t(c.r / dist);
						} else {
							p[k] = closest + Vector3(0.0f, 0.0f, real_t(c.r));
						}
					}
				}
				collide_surface(p[k], p_xf, inverse);
			}
			p[0] = p_xf.xform(r[0]);
		}
		// a safety limit: never farther from the rest place than max_displacement
		for (size_t k = 1; k < n; k++) {
			const Vector3 target = p_xf.xform(r[k]);
			Vector3 off = p[k] - target;
			const double ol = double(off.length());
			if (ol > max_displacement) {
				p[k] = target + off * real_t(max_displacement / ol);
			}
		}
		// last word: out of the skin, after everything else moved the points (twice: a push can end next to another vertex)
		for (int pass = 0; pass < 2; pass++) {
			for (size_t k = 1; k < n; k++) {
				collide_surface(p[k], p_xf, inverse);
			}
		}
	}
}

// Writes the offsets (mesh space) into the texture.
void HairSim::upload(const Transform3D &p_xf) {
	const Transform3D inv = p_xf.affine_inverse();
	float *w = reinterpret_cast<float *>(bytes.ptrw());
	for (int g = 0; g < guide_count; g++) {
		for (int k = 0; k < steps; k++) {
			const size_t i = size_t(g) * size_t(steps) + size_t(k);
			const Vector3 offset = inv.xform(pos[i]) - rest[i];
			const size_t o = i * 3;
			w[o] = float(offset.x);
			w[o + 1] = float(offset.y);
			w[o + 2] = float(offset.z);
		}
	}
	Ref<Image> image = Image::create_from_data(steps, guide_count, false, Image::FORMAT_RGBF, bytes);
	texture->update(image);
}

void HairSim::_process(double p_delta) {
	if (p_delta <= 0.0) {
		return;
	}
	MeshInstance3D *mi = Object::cast_to<MeshInstance3D>(get_hair());
	if (mi == nullptr || !mi->is_inside_tree()) {
		return;
	}
	if (!bound) {
		bind_mesh();
		if (!bound) {
			return;
		}
	}
	const Transform3D xf = mi->get_global_transform();
	if (!primed) {
		for (int g = 0; g < guide_count; g++) {
			for (int k = 0; k < steps; k++) {
				const size_t i = size_t(g) * size_t(steps) + size_t(k);
				pos[i] = xf.xform(rest[i]);
				prev[i] = pos[i];
			}
		}
		last_transform = xf;
		primed = true;
	}
	accumulator += std::min(p_delta, 0.1);
	int ticks = 0;
	while (accumulator >= 1.0 / 60.0 && ticks < 4) {
		// the head moves between ticks: interpolate its transform so the pinned roots move smoothly
		const double t = double(ticks + 1) / std::max(1.0, std::floor(accumulator * 60.0));
		(void)t;
		step(1.0 / 60.0, xf);
		accumulator -= 1.0 / 60.0;
		ticks++;
	}
	last_transform = xf;
	upload(xf);
}

} // namespace godot
