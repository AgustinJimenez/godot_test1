#include "hair_sim_native.h"

#include <godot_cpp/classes/image.hpp>
#include <godot_cpp/classes/mesh_instance3d.hpp>
#include <godot_cpp/classes/array_mesh.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/core/math.hpp>
#include <godot_cpp/classes/worker_thread_pool.hpp>
#include <godot_cpp/variant/callable_method_pointer.hpp>
#include <godot_cpp/variant/packed_float32_array.hpp>
#include <godot_cpp/variant/packed_vector3_array.hpp>
#include <godot_cpp/variant/string_name.hpp>

#include <algorithm>
#include <cmath>
#include <climits>
#include <cstring>

namespace godot {

void HairSim::_bind_methods() {
	ClassDB::bind_method(D_METHOD("set_hair", "hair"), &HairSim::set_hair);
	ClassDB::bind_method(D_METHOD("get_hair"), &HairSim::get_hair);
	ClassDB::bind_method(D_METHOD("set_material", "material"), &HairSim::set_material);
	ClassDB::bind_method(D_METHOD("get_material"), &HairSim::get_material);
	ClassDB::bind_method(D_METHOD("set_wind", "value"), &HairSim::set_wind);
	ClassDB::bind_method(D_METHOD("get_wind"), &HairSim::get_wind);
	ClassDB::bind_method(D_METHOD("set_weight", "value"), &HairSim::set_weight);
	ClassDB::bind_method(D_METHOD("get_weight"), &HairSim::get_weight);
	ClassDB::bind_method(D_METHOD("set_bend_stiffness", "value"), &HairSim::set_bend_stiffness);
	ClassDB::bind_method(D_METHOD("get_bend_stiffness"), &HairSim::get_bend_stiffness);
	ClassDB::bind_method(D_METHOD("set_local_stiffness", "value"), &HairSim::set_local_stiffness);
	ClassDB::bind_method(D_METHOD("get_local_stiffness"), &HairSim::get_local_stiffness);
	ClassDB::bind_method(D_METHOD("set_air_drag", "value"), &HairSim::set_air_drag);
	ClassDB::bind_method(D_METHOD("get_air_drag"), &HairSim::get_air_drag);
	ClassDB::bind_method(D_METHOD("set_max_swing", "value"), &HairSim::set_max_swing);
	ClassDB::bind_method(D_METHOD("get_max_swing"), &HairSim::get_max_swing);
	ClassDB::bind_method(D_METHOD("set_strand_damping", "value"), &HairSim::set_strand_damping);
	ClassDB::bind_method(D_METHOD("get_strand_damping"), &HairSim::get_strand_damping);
	ClassDB::bind_method(D_METHOD("set_calm_damping", "value"), &HairSim::set_calm_damping);
	ClassDB::bind_method(D_METHOD("get_calm_damping"), &HairSim::get_calm_damping);
	ClassDB::bind_method(D_METHOD("set_calm_speed", "value"), &HairSim::set_calm_speed);
	ClassDB::bind_method(D_METHOD("get_calm_speed"), &HairSim::get_calm_speed);
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
	ClassDB::bind_method(D_METHOD("set_settle_steps", "value"), &HairSim::set_settle_steps);
	ClassDB::bind_method(D_METHOD("get_settle_steps"), &HairSim::get_settle_steps);
	ClassDB::bind_method(D_METHOD("set_collisions", "capsules"), &HairSim::set_collisions);
	ClassDB::bind_method(D_METHOD("set_capsule_collision", "value"), &HairSim::set_capsule_collision);
	ClassDB::bind_method(D_METHOD("get_capsule_collision"), &HairSim::get_capsule_collision);
	ClassDB::bind_method(D_METHOD("set_surface_collision", "value"), &HairSim::set_surface_collision);
	ClassDB::bind_method(D_METHOD("get_surface_collision"), &HairSim::get_surface_collision);
	ClassDB::bind_method(D_METHOD("get_penetration_count"), &HairSim::get_penetration_count);
	ClassDB::bind_method(D_METHOD("get_mean_tip_offset"), &HairSim::get_mean_tip_offset);
	ClassDB::bind_method(D_METHOD("get_busiest_guide"), &HairSim::get_busiest_guide);
	ClassDB::bind_method(D_METHOD("get_guide_points", "guide"), &HairSim::get_guide_points);
	ClassDB::bind_method(D_METHOD("get_mean_tip_vector"), &HairSim::get_mean_tip_vector);
	ClassDB::bind_method(D_METHOD("get_guide_count"), &HairSim::get_guide_count);
	ClassDB::bind_method(D_METHOD("rebind"), &HairSim::rebind);
	ClassDB::bind_method(D_METHOD("kick", "impulse"), &HairSim::kick);
	ADD_PROPERTY(PropertyInfo(Variant::OBJECT, "hair", PROPERTY_HINT_NODE_TYPE, "MeshInstance3D"), "set_hair", "get_hair");
	ADD_PROPERTY(PropertyInfo(Variant::OBJECT, "material", PROPERTY_HINT_RESOURCE_TYPE, "ShaderMaterial"), "set_material", "get_material");
	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "gravity"), "set_gravity", "get_gravity");
	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "damping"), "set_damping", "get_damping");
	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "root_stiffness"), "set_root_stiffness", "get_root_stiffness");
	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "tip_stiffness"), "set_tip_stiffness", "get_tip_stiffness");
	ADD_PROPERTY(PropertyInfo(Variant::VECTOR3, "wind"), "set_wind", "get_wind");
	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "weight"), "set_weight", "get_weight");
	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "bend_stiffness"), "set_bend_stiffness", "get_bend_stiffness");
	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "local_stiffness"), "set_local_stiffness", "get_local_stiffness");
	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "air_drag"), "set_air_drag", "get_air_drag");
	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "max_swing"), "set_max_swing", "get_max_swing");
	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "strand_damping"), "set_strand_damping", "get_strand_damping");
	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "calm_damping"), "set_calm_damping", "get_calm_damping");
	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "calm_speed"), "set_calm_speed", "get_calm_speed");
	ADD_PROPERTY(PropertyInfo(Variant::INT, "iterations"), "set_iterations", "get_iterations");
	ADD_PROPERTY(PropertyInfo(Variant::INT, "settle_steps"), "set_settle_steps", "get_settle_steps");
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

void HairSim::build_surface_grid() {
	grid_start.clear();
	grid_items.clear();
	if (surface_p.empty()) {
		grid_dim[0] = grid_dim[1] = grid_dim[2] = 0;
		return;
	}
	int lo[3] = { INT_MAX, INT_MAX, INT_MAX }, hi[3] = { INT_MIN, INT_MIN, INT_MIN };
	std::vector<int> cell3(surface_p.size() * 3);
	for (size_t i = 0; i < surface_p.size(); i++) {
		const Vector3 &v = surface_p[i];
		const int c[3] = { int(std::floor(double(v.x) / surface_cell)), int(std::floor(double(v.y) / surface_cell)), int(std::floor(double(v.z) / surface_cell)) };
		for (int a = 0; a < 3; a++) {
			cell3[i * 3 + size_t(a)] = c[a];
			lo[a] = std::min(lo[a], c[a]);
			hi[a] = std::max(hi[a], c[a]);
		}
	}
	for (int a = 0; a < 3; a++) {
		grid_min[a] = lo[a];
		grid_dim[a] = hi[a] - lo[a] + 1;
	}
	const size_t cells = size_t(grid_dim[0]) * size_t(grid_dim[1]) * size_t(grid_dim[2]);
	grid_start.assign(cells + 1, 0);
	auto index = [&](size_t i) {
		return (size_t(cell3[i * 3] - lo[0]) * size_t(grid_dim[1]) + size_t(cell3[i * 3 + 1] - lo[1])) * size_t(grid_dim[2]) + size_t(cell3[i * 3 + 2] - lo[2]);
	};
	for (size_t i = 0; i < surface_p.size(); i++) {
		grid_start[index(i) + 1]++;
	}
	for (size_t c = 0; c < cells; c++) {
		grid_start[c + 1] += grid_start[c];
	}
	grid_items.resize(surface_p.size());
	std::vector<int> fill(grid_start.begin(), grid_start.end() - 1);
	for (size_t i = 0; i < surface_p.size(); i++) {
		grid_items[size_t(fill[index(i)]++)] = int(i);
	}
}

// The surface vertex nearest to a local point within one cell (-1 if none); r_d2 gets its squared distance.
int HairSim::nearest_surface(const Vector3 &p, double &r_d2) const {
	const int cx = int(std::floor(double(p.x) / surface_cell)) - grid_min[0];
	const int cy = int(std::floor(double(p.y) / surface_cell)) - grid_min[1];
	const int cz = int(std::floor(double(p.z) / surface_cell)) - grid_min[2];
	if (cx < -1 || cy < -1 || cz < -1 || cx > grid_dim[0] || cy > grid_dim[1] || cz > grid_dim[2]) {
		return -1;
	}
	int best = -1;
	double best_d2 = surface_cell * surface_cell;
	const int x0 = std::max(cx - 1, 0), x1 = std::min(cx + 1, grid_dim[0] - 1);
	const int y0 = std::max(cy - 1, 0), y1 = std::min(cy + 1, grid_dim[1] - 1);
	const int z0 = std::max(cz - 1, 0), z1 = std::min(cz + 1, grid_dim[2] - 1);
	for (int x = x0; x <= x1; x++) {
		for (int y = y0; y <= y1; y++) {
			// the cells of one z row are next to each other: one range
			const size_t row = (size_t(x) * size_t(grid_dim[1]) + size_t(y)) * size_t(grid_dim[2]);
			for (int k = grid_start[row + size_t(z0)]; k < grid_start[row + size_t(z1) + 1]; k++) {
				const int i = grid_items[size_t(k)];
				const double d2 = double((p - surface_p[size_t(i)]).length_squared());
				if (d2 < best_d2) {
					best_d2 = d2;
					best = i;
				}
			}
		}
	}
	r_d2 = best_d2;
	return best;
}

// Pushes a point (world) out of the body surface: the nearest surface vertex within one cell and its normal.
void HairSim::collide_surface(Vector3 &p_world, const Transform3D &p_xf, const Transform3D &p_inv) const {
	if (!surface_collision || surface_p.empty()) {
		return;
	}
	const Vector3 p = p_inv.xform(p_world);
	const int cx = int(std::floor(double(p.x) / surface_cell)) - grid_min[0];
	const int cy = int(std::floor(double(p.y) / surface_cell)) - grid_min[1];
	const int cz = int(std::floor(double(p.z) / surface_cell)) - grid_min[2];
	if (cx < -1 || cy < -1 || cz < -1 || cx > grid_dim[0] || cy > grid_dim[1] || cz > grid_dim[2]) {
		return;
	}
	// the skin around the point, smoothed (one scan): the vertices within a centimetre or so weighted by closeness. A point that slides between two vertices would otherwise be pushed along a different normal each step and shake.
	constexpr float kRadius = 0.014f;
	constexpr float kRadius2 = kRadius * kRadius;
	Vector3 sum_p, sum_n;
	float sum_w = 0.0f;
	float best_d2 = float(surface_cell * surface_cell);
	int best = -1;
	const int x0 = std::max(cx - 1, 0), x1 = std::min(cx + 1, grid_dim[0] - 1);
	const int y0 = std::max(cy - 1, 0), y1 = std::min(cy + 1, grid_dim[1] - 1);
	const int z0 = std::max(cz - 1, 0), z1 = std::min(cz + 1, grid_dim[2] - 1);
	for (int x = x0; x <= x1; x++) {
		for (int y = y0; y <= y1; y++) {
			const size_t row = (size_t(x) * size_t(grid_dim[1]) + size_t(y)) * size_t(grid_dim[2]);
			for (int k = grid_start[row + size_t(z0)]; k < grid_start[row + size_t(z1) + 1]; k++) {
				const size_t i = size_t(grid_items[size_t(k)]);
				const float d2 = (p - surface_p[i]).length_squared();
				if (d2 < best_d2) {
					best_d2 = d2;
					best = int(i);
				}
				if (d2 < kRadius2) {
					const float t = 1.0f - d2 / kRadius2; // (a smooth fall-off that needs no square root)
					const float w = t * t;
					sum_p += surface_p[i] * w;
					sum_n += surface_n[i] * w;
					sum_w += w;
				}
			}
		}
	}
	if (best < 0) {
		return;
	}
	Vector3 n = surface_n[size_t(best)];
	Vector3 on_skin = surface_p[size_t(best)];
	if (sum_w > 1e-9f && sum_n.length_squared() > 1e-12f) {
		n = sum_n.normalized();
		on_skin = sum_p / sum_w;
	}
	const double depth = double((p - on_skin).dot(n));
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
			double best_d2 = 0.0;
			const int best = nearest_surface(p, best_d2);
			if (best >= 0 && double((p - surface_p[size_t(best)]).dot(surface_n[size_t(best)])) < -0.002) {
				count++;
			}
		}
	}
	return count;
}

Vector3 HairSim::get_mean_tip_vector() const { // (the mean of the ABSOLUTE components: a swing to the left and one to the right must not cancel; as DRAWN: between the last two steps)
	if (!bound || !primed || guide_count <= 0) {
		return Vector3();
	}
	const real_t a = real_t(Math::clamp(drawn_alpha, 0.0, 1.0));
	const Transform3D inv = step_prev_xf.interpolate_with(step_last_xf, a).affine_inverse();
	const bool have_snap = snap.size() == pos.size();
	Vector3 sum;
	for (int g = 0; g < guide_count; g++) {
		const size_t i = size_t(g) * size_t(steps) + size_t(steps - 1);
		const Vector3 world = have_snap ? snap[i] + (pos[i] - snap[i]) * a : pos[i];
		const Vector3 o = inv.xform(world) - rest[i];
		sum += Vector3(std::abs(o.x), std::abs(o.y), std::abs(o.z));
	}
	return sum / real_t(guide_count);
}

PackedVector3Array HairSim::get_guide_points(int p_guide) const {
	PackedVector3Array out;
	if (p_guide < 0 || p_guide >= guide_count) {
		return out;
	}
	for (int k = 0; k < steps; k++) {
		out.push_back(pos[size_t(p_guide) * size_t(steps) + size_t(k)]);
	}
	return out;
}

Vector3 HairSim::get_busiest_guide() const {
	// x: the largest distance any point moved in the last step (metres), y: the guide it belongs to, z: how many guides moved more than 0.1 mm in the last step (for finding hair that never settles)
	double best = 0.0;
	int best_guide = -1;
	int moving = 0;
	const size_t n = size_t(steps);
	for (int g = 0; g < guide_count; g++) {
		double guide_best = 0.0;
		for (size_t k = 1; k < n; k++) {
			guide_best = std::max(guide_best, double((pos[size_t(g) * n + k] - prev[size_t(g) * n + k]).length()));
		}
		if (guide_best > 1e-4) {
			moving++;
		}
		if (guide_best > best) {
			best = guide_best;
			best_guide = g;
		}
	}
	return Vector3(real_t(best), real_t(best_guide), real_t(moving));
}

double HairSim::get_mean_tip_offset() const {
	if (!bound || !primed || guide_count <= 0) {
		return 0.0;
	}
	const Transform3D inv = last_transform.affine_inverse();
	double sum = 0.0;
	for (int g = 0; g < guide_count; g++) {
		const size_t i = size_t(g) * size_t(steps) + size_t(steps - 1);
		sum += double((inv.xform(pos[i]) - rest[i]).length());
	}
	return sum / double(guide_count);
}

void HairSim::kick(const Vector3 &p_impulse) {
	// a velocity change: move the previous positions back
	std::fill(calm_steps.begin(), calm_steps.end(), 0);
	for (size_t i = 0; i < pos.size(); i++) {
		if (i % size_t(std::max(steps, 1)) != 0) {
			prev[i] -= p_impulse * real_t(1.0 / 60.0);
		}
	}
}

// Reads the guides, the colliders and the point count from the hair mesh and makes the texture.
void HairSim::bind_mesh() {
	// a new hair that has as many guides and points as the one it replaces (a slider moved) inherits how the old one hangs and swings:
	// every point's offset from its rest place, in the head's frame. No settling, no sag in view, no cost.
	std::vector<Vector3> inherited;
	if (primed && !pos.empty() && pos.size() == rest.size()) {
		const Transform3D inv = last_transform.affine_inverse();
		inherited.resize(pos.size());
		for (size_t i = 0; i < pos.size(); i++) {
			inherited[i] = inv.xform(pos[i]) - rest[i];
		}
	}
	const int old_guides = guide_count;
	const int old_steps = steps;
	carry.clear();
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
	link2.assign(size_t(guide_count) * size_t(steps), 0.0);
	for (int g = 0; g < guide_count; g++) {
		for (int k = 2; k < steps; k++) {
			link2[size_t(g) * size_t(steps) + size_t(k)] = double(rest[size_t(g) * size_t(steps) + size_t(k)].distance_to(rest[size_t(g) * size_t(steps) + size_t(k - 2)]));
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
	calm_steps.assign(size_t(guide_count), 0);
	if (!inherited.empty() && guide_count == old_guides && old_steps >= 2) {
		if (steps == old_steps) {
			carry = inherited;
		} else {
			// another number of points per hair (the length changed): the same offsets, resampled along each hair
			carry.assign(rest.size(), Vector3());
			for (int g = 0; g < guide_count; g++) {
				for (int k = 0; k < steps; k++) {
					const double f = double(k) / double(steps - 1) * double(old_steps - 1);
					const int k0 = std::min(int(std::floor(f)), old_steps - 2);
					const real_t t = real_t(f - double(k0));
					const Vector3 &a = inherited[size_t(g) * size_t(old_steps) + size_t(k0)];
					const Vector3 &b = inherited[size_t(g) * size_t(old_steps) + size_t(k0 + 1)];
					carry[size_t(g) * size_t(steps) + size_t(k)] = a + (b - a) * t;
				}
			}
		}
	}
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

// One guide: Verlet, pull to the style, length constraints, colliders. Guides do not touch each other, so any number of them can run at once.
void HairSim::step_guide(int g) {
	const Transform3D &p_xf = sd.xf;
	const Transform3D &inverse = sd.inverse;
	const size_t n = size_t(steps);
	Vector3 *p = &pos[size_t(g) * n];
	Vector3 *q = &prev[size_t(g) * n];
	const Vector3 *r = &rest[size_t(g) * n];
	const double *len = &link[size_t(g) * (n - 1)];
	Vector3 target[kMaxSteps]; // the rest places in world space, worked out once
	for (size_t k = 0; k < n; k++) {
		target[k] = p_xf.xform(r[k]);
	}
	// a guide that has hardly moved for half a second, with the head still and no wind, sleeps (it wakes as soon as the head moves)
	int &calm = calm_steps[size_t(g)];
	if (calm >= 30 && sd.wind_dt2.length_squared() == 0.0f && (target[0] - p[0]).length_squared() < 1e-10f) {
		for (size_t k = 1; k < n; k++) {
			q[k] = p[k];
		}
		return;
	}
	Vector3 start[kMaxSteps];
	for (size_t k = 0; k < n; k++) {
		start[k] = p[k];
	}
	// the root follows the scalp
	p[0] = target[0];
	q[0] = p[0];
	// velocities (m per step); neighbouring points lose their difference in velocity (damping inside the strand: it stops the strand's own wobble, not its swing as a whole)
	Vector3 vel[kMaxSteps];
	for (size_t k = 1; k < n; k++) {
		vel[k] = p[k] - q[k];
	}
	if (strand_damping > 0.0) {
		const real_t share = real_t(0.5 * strand_damping);
		for (size_t k = 2; k < n; k++) {
			const Vector3 rel = (vel[k] - vel[k - 1]) * share;
			vel[k] -= rel;
			vel[k - 1] += rel;
		}
	}
	for (size_t k = 1; k < n; k++) {
		Vector3 velocity = vel[k];
		// the air: moving across the strand costs far more than along it, and the faster the more (quadratic), so a swing slows the way real hair does
		if (air_drag > 0.0) {
			const Vector3 tangent_raw = p[k] - p[k - 1];
			if (tangent_raw.length_squared() > 1e-12f) {
				const Vector3 tangent = tangent_raw.normalized();
				const Vector3 across = velocity - tangent * velocity.dot(tangent);
				const double across_speed = double(across.length()) * 60.0; // m/s
				velocity -= across * real_t(std::min(0.6, air_drag * (0.4 + across_speed) * sd.stiffness_scale));
			}
		}
		// small movements die out fast (friction between the hairs), big swings keep the normal damping
		const double speed_ratio = std::min(1.0, double(velocity.length()) / calm_speed);
		const double blend = speed_ratio * speed_ratio * (3.0 - 2.0 * speed_ratio);
		const double d_here = std::min(sd.damping, calm_damping + (sd.damping - calm_damping) * blend);
		velocity *= real_t(d_here);
		q[k] = p[k];
		p[k] += velocity + sd.g_dt2;
		if (sd.wind_dt2.length_squared() > 0.0f) {
			// the wind comes in gusts (each guide a little out of step with its neighbours) and catches the tips more than the roots
			const double along_wind = double(k) / double(n - 1);
			const double gust = 1.0 + 0.4 * std::sin(sd.time * 2.3 + double(g) * 0.37) + 0.2 * std::sin(sd.time * 5.1 + double(g) * 0.91);
			p[k] += sd.wind_dt2 * real_t(gust * (0.35 + 0.65 * along_wind));
		}
		// back toward the style: the rest place in the head's frame
		const double along = double(k) / double(n - 1);
		const double stiff = std::min(0.95, (root_stiffness + (tip_stiffness - root_stiffness) * along) * sd.stiffness_scale);
		p[k] += (target[k] - p[k]) * real_t(stiff);
	}
	// local shape (as in AMD TressFX): each segment keeps its angle to the one before it, so a curve or a bend at the root holds along the whole strand
	if (local_stiffness > 0.0) {
		for (size_t k = 2; k < n; k++) {
			const Vector3 rest_prev = target[k - 1] - target[k - 2];
			const Vector3 now_prev = p[k - 1] - p[k - 2];
			if (rest_prev.length_squared() < 1e-12f || now_prev.length_squared() < 1e-12f) {
				continue;
			}
			const Vector3 from_dir = rest_prev.normalized();
			const Vector3 to_dir = now_prev.normalized();
			if (from_dir.dot(to_dir) < -0.9f) {
				continue; // the segment is turned back on itself: no sensible rotation between them (the rotation would not even be unit length)
			}
			const Quaternion turn = Quaternion(from_dir, to_dir).normalized();
			const Vector3 wanted = p[k - 1] + turn.xform(target[k] - target[k - 1]);
			const Vector3 move = (wanted - p[k]) * real_t(local_stiffness);
			p[k] += move;
			if (k > 2) {
				p[k - 1] -= move * real_t(0.25);
			}
		}
	}
	// a longer chain needs more passes to stay as stiff in length (about half a pass per point)
	const int passes = std::max(iterations, int(n) / 2);
	for (int it = 0; it < passes; it++) {
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
		if (bend_stiffness > 0.0) {
			// bending: keep the distance to the point two places back (the shape of the style); the root is pinned, so a point next to it moves alone
			const double *len2 = &link2[size_t(g) * n];
			for (size_t k = 2; k < n; k++) {
				Vector3 d = p[k] - p[k - 2];
				const double dl = double(d.length());
				if (dl > 1e-9) {
					const double diff = (dl - len2[k]) / dl * bend_stiffness;
					if (k == 2) {
						p[k] -= d * real_t(diff);
					} else {
						p[k] -= d * real_t(diff * 0.5);
						p[k - 2] += d * real_t(diff * 0.5);
					}
				}
			}
		}
		for (size_t k = 1; k < n; k++) {
			for (const StepData::Capsule &c : sd.world) {
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
		}
		if (it == passes - 1) {
			// the skin is part of the last passes, so the length constraints settle against it (collision only after them left the strand fighting the skin and creeping)
			for (size_t k = 1; k < n; k++) {
				collide_surface(p[k], p_xf, inverse);
			}
		}
		p[0] = target[0];
	}
	// no stretching, whatever the head did: from the root out, every point is put back at its exact distance from the one before it (a fast turn moves the root by centimetres in one step and the few passes above cannot pull the whole chain along)
	for (size_t k = 1; k < n; k++) {
		Vector3 d = p[k] - p[k - 1];
		const double dl = double(d.length());
		if (dl > 1e-9) {
			p[k] = p[k - 1] + d * real_t(len[k - 1] / dl);
		}
	}
	// a safety limit: never farther from the rest place than max_displacement
	// ... and a limit on the swing: a point may leave its place in the style by at most `max_swing` x the length of the strand up to that point (the tip of a short lock cannot dance away), then the lengths are restored
	double arc = 0.0;
	bool clamped = false;
	for (size_t k = 1; k < n; k++) {
		arc += len[k - 1];
		const double limit = std::min(max_displacement, 0.004 + max_swing * arc);
		Vector3 off = p[k] - target[k];
		const double ol = double(off.length());
		if (ol > limit) {
			p[k] = target[k] + off * real_t(limit / ol);
			clamped = true;
		}
	}
	if (clamped) {
		for (size_t k = 1; k < n; k++) {
			Vector3 d = p[k] - p[k - 1];
			const double dl = double(d.length());
			if (dl > 1e-9) {
				p[k] = p[k - 1] + d * real_t(len[k - 1] / dl);
			}
		}
	}
	// last word: out of the skin, after everything else moved the points
	for (int pass = 0; pass < 1; pass++) {
		for (size_t k = 1; k < n; k++) {
			const Vector3 before = p[k];
			collide_surface(p[k], p_xf, inverse);
			if (before.distance_squared_to(p[k]) > 1e-12f) {
				// pushed out of the skin: the push must not turn into speed (the pull to the style would drive the point back in, and it would bounce on the skin every step)
				// and the point rests on the skin instead of sliding on it (friction: most of this step's sideways movement is undone), so it does not creep between two vertices' planes
				const Vector3 push = (p[k] - before).normalized();
				const Vector3 moved = p[k] - q[k];
				p[k] -= (moved - push * moved.dot(push)) * real_t(0.9);
				q[k] = p[k];
			}
		}
	}
	// the skin pushes may have stretched a strand (fast turns): once more, exact lengths (the skin gives way a little instead of the hair stretching)
	for (size_t k = 1; k < n; k++) {
		Vector3 d = p[k] - p[k - 1];
		const double dl = double(d.length());
		if (dl > 1e-9) {
			p[k] = p[k - 1] + d * real_t(len[k - 1] / dl);
		}
	}
	double moved_most = 0.0;
	for (size_t k = 1; k < n; k++) {
		moved_most = std::max(moved_most, double((p[k] - start[k]).length()));
	}
	calm = (moved_most < 6e-4 && (target[0] - start[0]).length_squared() < 1e-10f) ? calm + 1 : 0;

}

void HairSim::step_chunk(int p_chunk) {
	const int per = (guide_count + kChunks - 1) / kChunks;
	const int from = p_chunk * per;
	const int to = std::min(guide_count, from + per);
	for (int g = from; g < to; g++) {
		step_guide(g);
	}
}

void HairSim::step(double p_dt, const Transform3D &p_xf) {
	snap = pos;
	step_prev_xf = step_last_xf;
	step_last_xf = p_xf;
	sd.xf = p_xf;
	sd.inverse = p_xf.affine_inverse();
	sd.g_dt2 = Vector3(0.0f, real_t(-gravity * weight * p_dt * p_dt), 0.0f);
	sd.damping = 1.0 - (1.0 - damping) / weight; // a heavier hair loses less speed to the air
	sd.stiffness_scale = 1.0 / weight;
	wind_time += p_dt;
	sd.time = wind_time;
	sd.wind_dt2 = wind * real_t(p_dt * p_dt / weight);
	sd.world.clear();
	const double scale = double(p_xf.basis.get_scale().x);
	for (size_t i = 0; capsule_collision && i + 6 < capsules.size(); i += 7) {
		StepData::Capsule c;
		c.a = p_xf.xform(Vector3(capsules[i], capsules[i + 1], capsules[i + 2]));
		c.b = p_xf.xform(Vector3(capsules[i + 3], capsules[i + 4], capsules[i + 5]));
		c.r = double(capsules[i + 6]) * scale + collision_margin;
		sd.world.push_back(c);
	}
	if (guide_count < 256 || steps > kMaxSteps) {
		for (int g = 0; g < guide_count && steps <= kMaxSteps; g++) {
			step_guide(g);
		}
		return;
	}
	WorkerThreadPool *pool = WorkerThreadPool::get_singleton();
	const int64_t task = pool->add_group_task(callable_mp(this, &HairSim::step_chunk), kChunks, -1, true, String("HairSim step"));
	pool->wait_for_group_task_completion(task);
}

// Writes the offsets (mesh space) into the texture.
void HairSim::upload(double p_alpha) {
	// the picture is drawn a step behind, between the points before the last step and after it, with the head's transform from the same moment:
	// whatever the frame rate, the hair moves in the same smooth way (no catching up in jumps of one step)
	const real_t a = real_t(Math::clamp(p_alpha, 0.0, 1.0));
	const Transform3D inv = step_prev_xf.interpolate_with(step_last_xf, a).affine_inverse();
	float *w = reinterpret_cast<float *>(bytes.ptrw());
	const bool have_snap = snap.size() == pos.size();
	for (int g = 0; g < guide_count; g++) {
		for (int k = 0; k < steps; k++) {
			const size_t i = size_t(g) * size_t(steps) + size_t(k);
			const Vector3 world = have_snap ? snap[i] + (pos[i] - snap[i]) * a : pos[i];
			const Vector3 offset = inv.xform(world) - rest[i];
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
		const bool inherit = carry.size() == rest.size();
		for (int g = 0; g < guide_count; g++) {
			for (int k = 0; k < steps; k++) {
				const size_t i = size_t(g) * size_t(steps) + size_t(k);
				pos[i] = xf.xform(inherit ? rest[i] + carry[i] : rest[i]);
				prev[i] = pos[i];
			}
		}
		carry.clear();
		last_transform = xf;
		step_prev_xf = xf;
		step_last_xf = xf;
		primed = true;
		// let the hair hang first (a new hair starts in its rest pose and would sag in front of the viewer, like a bounce on every rebuild)
		// (heavily damped: the hanging pose does not depend on damping, but it is reached in a third of the steps)
		const int settle = inherit ? 0 : settle_steps;
		const double kept_damping = damping;
		damping = std::min(damping, 0.8);
		for (int i = 0; i < settle; i++) {
			step(1.0 / 60.0, xf);
		}
		damping = kept_damping;
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
	drawn_alpha = accumulator * 60.0;
	upload(drawn_alpha);
}

} // namespace godot
