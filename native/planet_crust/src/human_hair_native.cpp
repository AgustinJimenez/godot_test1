#include "human_hair_native.h"

#include <godot_cpp/classes/mesh.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/core/math.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/color.hpp>
#include <godot_cpp/variant/packed_color_array.hpp>
#include <godot_cpp/variant/packed_float32_array.hpp>
#include <godot_cpp/variant/packed_int32_array.hpp>
#include <godot_cpp/variant/packed_vector2_array.hpp>
#include <godot_cpp/variant/packed_string_array.hpp>
#include <godot_cpp/variant/packed_vector3_array.hpp>
#include <godot_cpp/variant/string_name.hpp>
#include <godot_cpp/variant/typed_array.hpp>
#include <godot_cpp/variant/utility_functions.hpp>
#include <godot_cpp/variant/vector3.hpp>

#include <algorithm>
#include <cmath>
#include <cstdint>
#include <unordered_map>
#include <vector>

namespace godot {

namespace {

// A small deterministic dice (SplitMix64): the same numbers on every engine build, whatever its float precision.
struct Dice {
	uint64_t state;
	// the seed goes through the mixer first: with state = seed * G, the stream of seed + 1 was the stream of seed shifted by one number
	static uint64_t mix(uint64_t z) {
		z = (z ^ (z >> 30)) * 0xBF58476D1CE4E5B9ULL;
		z = (z ^ (z >> 27)) * 0x94D049BB133111EBULL;
		return z ^ (z >> 31);
	}
	explicit Dice(uint64_t p_seed) :
			state(mix(p_seed + 0x1234567ULL) * 0x9E3779B97F4A7C15ULL) {}
	uint64_t next() {
		state += 0x9E3779B97F4A7C15ULL;
		uint64_t z = state;
		z = (z ^ (z >> 30)) * 0xBF58476D1CE4E5B9ULL;
		z = (z ^ (z >> 27)) * 0x94D049BB133111EBULL;
		return z ^ (z >> 31);
	}
	double unit() { return double(next() >> 11) * (1.0 / 9007199254740992.0); }
	double range(double p_low, double p_high) { return p_low + (p_high - p_low) * unit(); }
};

double param(const Dictionary &p_params, const char *p_key, double p_default) {
	StringName key(p_key); // (a Dictionary finds a String key by its StringName: they are the same key)
	return p_params.has(key) ? double(p_params[key]) : p_default;
}

// A tangent for the scalp cap (it has no strands): any direction along the surface.
Vector3 cap_tangent(const Vector3 &p_normal) {
	Vector3 t = p_normal.cross(Vector3(0.0f, 1.0f, 0.0f));
	if (t.length() < 1e-4f) {
		t = Vector3(1.0f, 0.0f, 0.0f);
	}
	return t.normalized();
}

// Nearest-vertex lookup over the body, to keep the hair out of the head, ears and shoulders.
struct VertexGrid {
	double cell = 0.04;
	std::unordered_map<int64_t, std::vector<int>> cells;
	const std::vector<Vector3> *vertices = nullptr;
	const std::vector<Vector3> *normals = nullptr;

	static int64_t key(int p_x, int p_y, int p_z) {
		return (int64_t(p_x + 4096) << 40) ^ (int64_t(p_y + 4096) << 20) ^ int64_t(p_z + 4096);
	}
	int cell_of(double p_value) const { return int(std::floor(p_value / cell)); }

	void build(const std::vector<Vector3> &p_vertices, const std::vector<Vector3> &p_normals, double p_cell) {
		cell = p_cell;
		vertices = &p_vertices;
		normals = &p_normals;
		for (size_t i = 0; i < p_vertices.size(); i++) {
			const Vector3 &v = p_vertices[i];
			cells[key(cell_of(v.x), cell_of(v.y), cell_of(v.z))].push_back(int(i));
		}
	}
	// The body vertex nearest to `p_point` (within the neighbouring cells), or -1; r_distance_squared is its distance.
	int nearest(const Vector3 &p_point, double &r_distance_squared) const {
		const int cx = cell_of(p_point.x), cy = cell_of(p_point.y), cz = cell_of(p_point.z);
		double best = 1e9;
		int best_index = -1;
		for (int x = cx - 1; x <= cx + 1; x++) {
			for (int y = cy - 1; y <= cy + 1; y++) {
				for (int z = cz - 1; z <= cz + 1; z++) {
					auto found = cells.find(key(x, y, z));
					if (found == cells.end()) {
						continue;
					}
					for (int index : found->second) {
						const double d = (*vertices)[index].distance_squared_to(p_point);
						if (d < best) {
							best = d;
							best_index = index;
						}
					}
				}
			}
		}
		r_distance_squared = best;
		return best_index;
	}
	// Push `r_point` out of the surface when it is closer to it than `p_clearance` (measured along the nearest vertex's normal).
	void push_out(Vector3 &r_point, double p_clearance) const {
		double best = 0.0;
		const int best_index = nearest(r_point, best);
		if (best_index < 0 || best > 0.05 * 0.05) {
			return;
		}
		const Vector3 v = (*vertices)[best_index];
		const Vector3 n = (*normals)[best_index];
		const double side = (r_point - v).dot(n);
		if (side < p_clearance) {
			r_point += n * (p_clearance - side);
		}
	}
};

// How the whole scalp moved and grew in one blend shape: a scale and a move (about the scalp's centre), found by least squares.
struct HeadFit {
	Vector3 base_centre, shape_centre;
	double scale = 1.0;
	Vector3 delta_at(const Vector3 &p_point) const { return shape_centre + (p_point - base_centre) * real_t(scale) - p_point; }
};

HeadFit fit_head(const std::vector<Vector3> &p_vertices, const std::vector<Vector3> &p_deltas, const std::vector<int> &p_scalp) {
	HeadFit fit;
	if (p_scalp.empty()) {
		return fit;
	}
	Vector3 base_sum, shape_sum;
	for (int i : p_scalp) {
		base_sum += p_vertices[i];
		shape_sum += p_vertices[i] + p_deltas[i];
	}
	fit.base_centre = base_sum / real_t(p_scalp.size());
	fit.shape_centre = shape_sum / real_t(p_scalp.size());
	double along = 0.0, norm = 0.0;
	for (int i : p_scalp) {
		const Vector3 a = p_vertices[i] - fit.base_centre;
		const Vector3 b = p_vertices[i] + p_deltas[i] - fit.shape_centre;
		along += a.dot(b);
		norm += a.dot(a);
	}
	fit.scale = norm > 1e-9 ? Math::clamp(along / norm, 0.5, 2.0) : 1.0;
	return fit;
}

} // namespace

void HumanHairBody::_bind_methods() {
	ClassDB::bind_method(D_METHOD("is_valid"), &HumanHairBody::is_valid);
	ClassDB::bind_method(D_METHOD("get_vertex_count"), &HumanHairBody::get_vertex_count);
	ClassDB::bind_method(D_METHOD("get_shape_count"), &HumanHairBody::get_shape_count);
}

bool HumanHairBody::is_valid() const {
	return !vertices.empty() && normals.size() == vertices.size() && indices.size() >= 3;
}

Ref<HumanHairBody> HumanHairBody::from_mesh(const Ref<ArrayMesh> &p_mesh) {
	Ref<HumanHairBody> body;
	body.instantiate();
	if (p_mesh.is_null() || p_mesh->get_surface_count() < 1) {
		return body;
	}
	Array arrays = p_mesh->surface_get_arrays(0);
	PackedVector3Array vertices = arrays[Mesh::ARRAY_VERTEX];
	PackedVector3Array normals = arrays[Mesh::ARRAY_NORMAL];
	PackedInt32Array indices = arrays[Mesh::ARRAY_INDEX];
	const int count = vertices.size();
	if (count == 0 || normals.size() != count || indices.size() < 3) {
		return body;
	}
	body->vertices.assign(vertices.ptr(), vertices.ptr() + count);
	body->normals.assign(normals.ptr(), normals.ptr() + count);
	body->indices.assign(indices.ptr(), indices.ptr() + indices.size());
	for (int32_t index : body->indices) {
		if (index < 0 || index >= count) {
			body->vertices.clear(); // a corrupt mesh: no hair rather than a crash
			body->normals.clear();
			body->indices.clear();
			return body;
		}
	}
	const int shape_count = p_mesh->get_blend_shape_count();
	Array shapes = p_mesh->surface_get_blend_shape_arrays(0);
	const bool normalized = p_mesh->get_blend_shape_mode() == Mesh::BLEND_SHAPE_MODE_NORMALIZED;
	for (int s = 0; s < shape_count && s < shapes.size(); s++) {
		Array shape = shapes[s];
		PackedVector3Array positions = shape[Mesh::ARRAY_VERTEX];
		std::vector<Vector3> delta(count);
		if (positions.size() == count) {
			for (int i = 0; i < count; i++) {
				delta[i] = normalized ? positions[i] - body->vertices[i] : positions[i];
			}
		}
		body->shape_deltas.push_back(std::move(delta));
		body->shape_names.push_back(p_mesh->get_blend_shape_name(s));
	}
	return body;
}

void HumanHair::_bind_methods() {
	ClassDB::bind_static_method("HumanHair", D_METHOD("prepare", "body", "refresh"), &HumanHair::prepare, DEFVAL(false));
	ClassDB::bind_static_method("HumanHair", D_METHOD("build_arrays", "body_data", "params"), &HumanHair::build_arrays);
	ClassDB::bind_static_method("HumanHair", D_METHOD("make_mesh", "built"), &HumanHair::make_mesh);
	ClassDB::bind_static_method("HumanHair", D_METHOD("build", "body", "params"), &HumanHair::build);
	ClassDB::bind_static_method("HumanHair", D_METHOD("default_params"), &HumanHair::default_params);
	ClassDB::bind_static_method("HumanHair", D_METHOD("default_params_for", "gender"), &HumanHair::default_params_for);
}

Dictionary HumanHair::default_params() {
	Dictionary d;
	d["seed"] = 1;
	d["length"] = 0.12;
	d["locks"] = 2600;
	d["lock_width"] = 0.018;
	d["volume"] = 1.0;
	d["curl"] = 0.0;
	d["fringe"] = 0.4;
	d["parting"] = 0.0;
	d["gravity"] = 1.0;
	d["side_trim"] = 0.0;
	d["eye_drop"] = 0.105;
	return d;
}

Dictionary HumanHair::default_params_for(const String &p_gender) {
	Dictionary d = default_params();
	const String gender = p_gender.to_lower();
	// the drop of the eye centres below the top of the head, from tools/blender/landmarks/*.json (male eyes 1.6388 m under a 1.747 m crown, female 1.4989 under 1.606)
	d["eye_drop"] = gender == "female" ? 0.107 : (gender == "male" ? 0.108 : 0.105);
	return d;
}

Ref<HumanHairBody> HumanHair::prepare(const Ref<ArrayMesh> &p_body, bool p_refresh) {
	if (p_body.is_null()) {
		Ref<HumanHairBody> none;
		none.instantiate();
		return none;
	}
	const StringName meta_key("human_hair_body");
	if (!p_refresh && p_body->has_meta(meta_key)) {
		Ref<HumanHairBody> cached = p_body->get_meta(meta_key);
		// (the meta survives duplicate(): a copy with other vertices or shapes must not get the old read)
		if (cached.is_valid() && cached->get_vertex_count() == int64_t(p_body->surface_get_array_len(0)) && cached->get_shape_count() == int64_t(p_body->get_blend_shape_count())) {
			return cached;
		}
	}
	Ref<HumanHairBody> body = HumanHairBody::from_mesh(p_body);
	p_body->set_meta(meta_key, body);
	return body;
}

Dictionary HumanHair::build_arrays(const Ref<HumanHairBody> &p_body, const Dictionary &p_params) {
	Dictionary built;
	if (p_body.is_null() || !p_body->is_valid()) {
		return built;
	}
	const std::vector<Vector3> &vertices = p_body->vertices;
	const std::vector<Vector3> &normals = p_body->normals;
	const std::vector<int32_t> &indices = p_body->indices;
	const int vertex_count = int(vertices.size());
	const int index_count = int(indices.size());

	uint64_t seed = 1;
	if (p_params.has(StringName("seed"))) {
		seed = uint64_t(int64_t(p_params[StringName("seed")]));
	}
	const double length = std::max(0.01, param(p_params, "length", 0.12));
	const int requested_locks = int(Math::clamp(param(p_params, "locks", 2600), 1.0, 9000.0));
	const double requested_width = std::max(0.002, param(p_params, "lock_width", 0.018));
	// very short hair gets narrower locks (a ribbon wider than the hair is long looks like a flat plate) and more of them
	const double lock_width = std::min(requested_width, 0.002 + length * 0.25);
	const int lock_count = int(std::min(9000.0, double(requested_locks) * requested_width / lock_width));
	const double volume = std::max(0.0, param(p_params, "volume", 1.0));
	const double curl = std::max(0.0, param(p_params, "curl", 0.0));
	const double fringe = Math::clamp(param(p_params, "fringe", 0.4), 0.0, 1.0);
	const double parting = Math::clamp(param(p_params, "parting", 0.0), -1.0, 1.0);
	const double gravity = std::max(0.0, param(p_params, "gravity", 1.0));
	const double side_trim = Math::clamp(param(p_params, "side_trim", 0.0), 0.0, 1.0);
	const double eye_drop = param(p_params, "eye_drop", 0.105);

	// --- the head: top, centre and size, found from the body itself
	double top_y = -1e9;
	for (int i = 0; i < vertex_count; i++) {
		top_y = std::max(top_y, double(vertices[i].y));
	}
	const double eye_y = top_y - eye_drop;
	double z_front = -1e9, z_back = 1e9;
	double half_width = 0.0;
	int head_count = 0;
	for (int i = 0; i < vertex_count; i++) {
		const Vector3 &v = vertices[i];
		if (v.y > top_y - 0.2 && v.y < top_y - 0.04) {
			z_front = std::max(z_front, double(v.z));
			z_back = std::min(z_back, double(v.z));
			head_count++;
			half_width = std::max(half_width, double(std::abs(v.x)));
		}
	}
	if (head_count == 0) {
		return built;
	}
	// the middle of the skull, between the front of the face and the back of the head (an average of the vertices would be pulled forward by the face)
	const double centre_z = 0.5 * (z_front + z_back);
	const Vector3 head_centre(0.0f, real_t(eye_y), real_t(centre_z));
	const Vector3 crown(real_t(parting * half_width * 0.45), real_t(top_y), real_t(centre_z - 0.015));

	// --- the scalp: the vertices above the hairline (low at the nape, higher at the temples and the forehead)
	auto hairline = [&](const Vector3 &v) {
		const double azimuth = std::abs(std::atan2(double(v.x), double(v.z - centre_z))); // 0 front .. pi back
		const double front_y = eye_y + 0.068;
		const double side_y = eye_y + 0.014;
		const double back_y = eye_y - 0.065;
		const double a = Math::clamp((azimuth - 0.9) / 0.6, 0.0, 1.0);       // front .. side
		const double b = Math::clamp((azimuth - 1.8) / 0.9, 0.0, 1.0);       // side .. back
		const double front_side = front_y + (side_y - front_y) * (a * a * (3.0 - 2.0 * a));
		return front_side + (back_y - side_y) * (b * b * (3.0 - 2.0 * b));
	};
	std::vector<char> scalp(vertex_count, 0);
	std::vector<int> scalp_ids;
	for (int i = 0; i < vertex_count; i++) {
		const Vector3 &v = vertices[i];
		const double from_axis = std::hypot(double(v.x), double(v.z - centre_z));
		// the skull is a ring around the head axis: vertices close to the axis are the underside of the jaw (where the angle round the centre means nothing), not scalp
		if (from_axis < half_width * 1.7 && (from_axis > half_width * 0.6 || v.y > eye_y + 0.02) && v.y > hairline(v)) { // (near the axis only the top of the head counts)
			scalp[i] = 1;
			scalp_ids.push_back(i);
		}
	}
	std::vector<int> scalp_triangles; // first index of each triangle whose three vertices are scalp
	std::vector<double> cumulative_area;
	double total_area = 0.0;
	for (int t = 0; t + 2 < index_count; t += 3) {
		const int a = indices[t], b = indices[t + 1], c = indices[t + 2];
		if (int(scalp[a]) + int(scalp[b]) + int(scalp[c]) >= 2) { // two corners above the hairline are enough: the coarse mesh at the back of the head leaves holes otherwise
			const double area = 0.5 * (vertices[b] - vertices[a]).cross(vertices[c] - vertices[a]).length();
			total_area += area;
			scalp_triangles.push_back(t);
			cumulative_area.push_back(total_area);
		}
	}
	if (scalp_triangles.empty()) {
		return built;
	}

	VertexGrid grid;
	grid.build(vertices, normals, 0.04);
	VertexGrid near_grid; // cells as wide as the reach of the follow below, so the nearest vertex within it is always found
	near_grid.build(vertices, normals, 0.09);

	// the neck: a vertical column under the chin that hair must never pass through (a strand that ends up inside it is pushed out the way it came from)
	const double neck_top = top_y - 0.22;
	const double neck_bottom = top_y - 0.31;
	double neck_x = 0.0, neck_z = 0.0, neck_radius = 0.055;
	int neck_count = 0;
	for (int i = 0; i < vertex_count; i++) {
		const Vector3 &v = vertices[i];
		if (v.y > neck_bottom && v.y < neck_top && std::abs(v.x) < 0.1) {
			neck_x += v.x;
			neck_z += v.z;
			neck_count++;
		}
	}
	if (neck_count > 20) {
		neck_x /= neck_count;
		neck_z /= neck_count;
		double radius_sum = 0.0;
		for (int i = 0; i < vertex_count; i++) {
			const Vector3 &v = vertices[i];
			if (v.y > neck_bottom && v.y < neck_top && std::abs(v.x) < 0.1) {
				radius_sum += std::hypot(double(v.x) - neck_x, double(v.z) - neck_z);
			}
		}
		neck_radius = radius_sum / neck_count;
	}

	// --- output buffers (a vertex remembers which body vertex it follows and how far along its strand it is)
	std::vector<Vector3> out_vertices, out_normals;
	std::vector<Vector2> out_uvs;
	std::vector<Color> out_colors;
	std::vector<Vector3> out_tangents;
	std::vector<int32_t> out_indices;
	std::vector<int> out_bound;
	std::vector<float> out_s; // 0 at the root (and on the cap), 1 at the tip
	std::vector<char> out_cap;

	auto add_vertex = [&](const Vector3 &p_position, const Vector3 &p_normal, const Vector2 &p_uv, const Color &p_color, int p_bound, const Vector3 &p_tangent, float p_s, bool p_cap) {
		out_vertices.push_back(p_position);
		out_normals.push_back(p_normal);
		out_uvs.push_back(p_uv);
		out_colors.push_back(p_color);
		out_tangents.push_back(p_tangent);
		out_bound.push_back(p_bound);
		out_s.push_back(p_s);
		out_cap.push_back(p_cap ? 1 : 0);
		return int(out_vertices.size()) - 1;
	};

	// --- the cap: the scalp triangles lifted a hair's breadth, fading out toward the hairline (alpha), blue = 1 marks it for the shader
	std::vector<int> cap_index(vertex_count, -1);
	for (int t : scalp_triangles) {
		for (int k = 0; k < 3; k++) {
			const int v = indices[t + k];
			if (cap_index[v] < 0) {
				const double fade = Math::clamp((double(vertices[v].y) - hairline(vertices[v])) / 0.014, 0.0, 1.0);
				cap_index[v] = add_vertex(vertices[v] + normals[v] * 0.0018f, normals[v], Vector2(0.5f, 0.5f), Color(0.5f, 0.0f, 1.0f, float(fade)), v, cap_tangent(normals[v]), 0.0f, true);
			}
		}
		out_indices.push_back(cap_index[indices[t]]);
		out_indices.push_back(cap_index[indices[t + 1]]);
		out_indices.push_back(cap_index[indices[t + 2]]);
	}

	// --- the locks
	const int plain_steps = std::max(5, std::min(11, int(length / 0.02) + 5));
	// curls need more points per strand: a coil drawn with four points a turn is a zigzag
	const int steps = curl > 0.05 ? std::max(plain_steps, std::min(18, int(length / 0.008) + 5)) : plain_steps;
	const double gravity_amount = Math::clamp(length / 0.15, 0.25, 1.6) * gravity;
	const double head_scale_x = std::max(half_width, 0.05);
	for (int lock = 0; lock < lock_count; lock++) {
		// one dice per lock: whether a lock is kept near a float rounding edge cannot shift the numbers of every lock after it
		Dice dice(seed + uint64_t(lock) * 0x2545F4914F6CDD1DULL);
		// a root on the scalp, chosen by area
		const double pick = dice.unit() * total_area;
		const int tri = int(std::lower_bound(cumulative_area.begin(), cumulative_area.end(), pick) - cumulative_area.begin());
		const int t = scalp_triangles[std::min(tri, int(scalp_triangles.size()) - 1)];
		const int ia = indices[t], ib = indices[t + 1], ic = indices[t + 2];
		double u = dice.unit(), w = dice.unit();
		if (u + w > 1.0) {
			u = 1.0 - u;
			w = 1.0 - w;
		}
		const double a_weight = 1.0 - u - w;
		const Vector3 root = vertices[ia] * real_t(a_weight) + vertices[ib] * real_t(u) + vertices[ic] * real_t(w);
		Vector3 normal = (normals[ia] * real_t(a_weight) + normals[ib] * real_t(u) + normals[ic] * real_t(w)).normalized();
		// the hairline fades out: few, short locks right at its edge instead of a hard line
		const double above_hairline = double(root.y) - hairline(root);
		const double feather = Math::clamp(above_hairline / 0.016, 0.0, 1.0);
		if (above_hairline <= 0.0 || dice.unit() > 0.15 + 0.85 * feather) { // never below the hairline
			continue;
		}
		int bound = ia;
		if (u >= a_weight && u >= w) {
			bound = ib;
		} else if (w >= a_weight && w >= u) {
			bound = ic;
		}

		// the way the hair is combed here: away from the crown, along the scalp
		Vector3 radial = (root - crown);
		radial.y = 0.0f; // combed along the ground plane, so nothing at the crown is combed straight up
		if (radial.length() < 0.02f) {
			radial = Vector3(0.0f, 0.0f, 1.0f); // right at the crown: combed forward, like the rest of the top
		}
		radial = radial.normalized();
		Vector3 flow = radial - normal * real_t(radial.dot(normal));
		if (flow.length() < 0.25f) {
			// the comb direction is nearly along the surface normal (a steep patch facing it): project a fixed forward direction instead (the projection of the
			// radial one collapses to nothing there and its sign flips from one root to the next)
			const Vector3 forward(0.0f, 0.0f, 1.0f);
			flow = forward - normal * real_t(forward.dot(normal));
			if (flow.length() < 0.05f) {
				flow = Vector3(1.0f, 0.0f, 0.0f) - normal * normal.x;
			}
		}
		flow = flow.normalized();
		if (flow.z > 0.0f) {
			Vector3 swept_back(flow.x * 0.3f, flow.y, -flow.z);
			flow = swept_back.lerp(flow, real_t(fringe)).normalized();
		}
		const double side_of_part = (root.x - crown.x) >= 0.0 ? 1.0 : -1.0;
		// the front splits at the parting: hair there is pushed to either side so it does not hang straight over the face
		const double front_share = Math::clamp((double(root.z) - centre_z) / std::max(half_width, 0.05), 0.0, 1.0);
		flow = (flow + Vector3(real_t(side_of_part * (0.14 + 0.7 * front_share)), 0.0f, 0.0f)).normalized();

		// grow it
		// the top keeps its length; the sides and back are trimmed by side_trim (a short back and sides)
		const double topness = Math::clamp((double(root.y) - (eye_y + 0.03)) / std::max(top_y - eye_y - 0.03, 0.02), 0.0, 1.0);
		const double trim = 1.0 - side_trim * (1.0 - topness);
		// the front (bangs, face-framing locks) is shorter than the rest, so it ends near the cheek instead of hanging past the chin
		const double this_length = length * trim * (1.0 - 0.45 * front_share) * (0.5 + 0.5 * feather) * dice.range(0.9, 1.1);
		if (this_length < 0.004) {
			continue; // (a lock shorter than 4 mm: side_trim 1 on the sides and back)
		}
		const double step_length = this_length / (steps - 1);
		const double phase = dice.range(0.0, 6.2831853);
		const double stiffness = dice.range(0.9, 1.1);
		std::vector<Vector3> points;
		points.reserve(steps);
		// The hair drapes: it starts lying along the scalp in the combed direction, gravity pulls it down a little more every step, and the head
		// holds it up (it is pushed out of the surface and walks along it), so it follows the curve of the skull and falls freely where the head ends.
		Vector3 position = root + normal * 0.002f;
		Vector3 direction = (flow * 0.95f + normal * 0.15f).normalized();
		points.push_back(position);
		const double pull = Math::clamp(0.26 + 0.2 * gravity_amount, 0.06, 0.6) / stiffness; // how much of each step bends toward the ground
		const double curl_radius = curl * (0.004 + 0.3 * step_length);                      // the radius of the coil the strand is wound into afterwards
		const double clearance = 0.0025 + 0.006 * volume + 0.8 * curl_radius;               // how far the strand rides above the skin (a coil needs room)
		for (int k = 1; k < steps; k++) {
			const double s = double(k) / (steps - 1);
			direction = (direction * real_t(1.0 - pull) + Vector3(0.0f, -1.0f, 0.0f) * real_t(pull) + flow * 0.05f).normalized();
			Vector3 step = direction * real_t(step_length);
			Vector3 candidate = position + step;
			// a little volume: stay off the head by a margin that grows along the strand
			Vector3 from_centre = candidate - head_centre;
			const double ry = std::max(top_y - eye_y, 0.05);
			const double rx = head_scale_x;
			const double rz = std::max(half_width * 1.15, 0.05);
			const double q = std::sqrt((from_centre.x / rx) * (from_centre.x / rx) + (from_centre.y / ry) * (from_centre.y / ry) + (from_centre.z / rz) * (from_centre.z / rz));
			const double margin = 1.0 + 0.01 + 0.04 * volume * std::min(1.0, s * 2.0);
			if (q > 1e-6 && q < margin && candidate.y > eye_y - 0.02) {
				candidate = head_centre + from_centre * real_t(margin / q);
			}
			grid.push_out(candidate, clearance);
			grid.push_out(candidate, clearance);
			if (neck_count > 20 && candidate.y < neck_top + 0.02 && candidate.y > neck_bottom - 0.12) {
				Vector3 outward_dir(real_t(position.x - neck_x), 0.0f, real_t(position.z - neck_z));
				if (outward_dir.length() < 1e-4f) {
					outward_dir = Vector3(0.0f, 0.0f, -1.0f);
				}
				outward_dir = outward_dir.normalized();
				const double reach = std::hypot(double(candidate.x) - neck_x, double(candidate.z) - neck_z);
				if (reach < neck_radius + 0.008) {
					candidate.x = real_t(neck_x + outward_dir.x * (neck_radius + 0.008));
					candidate.z = real_t(neck_z + outward_dir.z * (neck_radius + 0.008));
				}
			}
			// walk along what the head did to the step (sliding over the surface), keeping the segment length
			Vector3 moved = candidate - position;
			if (moved.length() > 1e-6f) {
				direction = moved.normalized();
				candidate = position + direction * real_t(step_length);
			}
			position = candidate;
			points.push_back(position);
		}

		// curls: wind the strand into a helix around its spine (the root stays on the scalp, the coil grows over the first few points)
		if (curl > 0.0) {
			const std::vector<Vector3> spine = points;
			const double turn = 0.5 + 1.2 * curl + 0.4 * dice.unit(); // radians a coil turns between two points: slow waves for a little curl, tight coils for a lot
			for (int k = 1; k < steps; k++) {
				const Vector3 tangent = (spine[std::min(k + 1, steps - 1)] - spine[k - 1]).normalized();
				Vector3 side = tangent.cross(Vector3(0.0f, 1.0f, 0.0f));
				if (side.length() < 1e-4f) {
					side = Vector3(1.0f, 0.0f, 0.0f);
				}
				side = side.normalized();
				const Vector3 up = side.cross(tangent).normalized();
				const double angle = phase + k * turn;
				const double ramp = std::min(1.0, k / 3.0);
				points[k] = spine[k] + (side * real_t(std::cos(angle)) + up * real_t(std::sin(angle))) * real_t(curl_radius * ramp);
			}
		}

		// the ribbon
		const float brightness = float(dice.unit());
		const float chance = float(dice.unit());
		const int first = int(out_vertices.size());
		Vector3 previous_side;
		for (int k = 0; k < steps; k++) {
			const double s = double(k) / (steps - 1);
			const Vector3 tangent = (points[std::min(k + 1, steps - 1)] - points[std::max(k - 1, 0)]).normalized();
			Vector3 outward = (points[k] - head_centre).normalized();
			Vector3 side = tangent.cross(outward);
			if (side.length() < 1e-5f) {
				side = Vector3(1.0f, 0.0f, 0.0f);
			}
			side = side.normalized();
			if (k > 0 && side.dot(previous_side) < 0.0f) {
				side = -side; // (the coil sweeps the strand through "outward" every turn: keep the ribbon's side from the point before)
			}
			previous_side = side;
			const double width = lock_width * (1.0 - 0.65 * std::pow(s, 1.6)) * (0.75 + 0.25 * std::min(1.0, s * 6.0));
			const Vector3 face = side.cross(tangent).normalized();
			const Color color(brightness, chance, 0.0f, 1.0f);
			add_vertex(points[k] - side * real_t(width * 0.5), face, Vector2(0.0f, float(s)), color, bound, tangent, float(s), false);
			add_vertex(points[k] + side * real_t(width * 0.5), face, Vector2(1.0f, float(s)), color, bound, tangent, float(s), false);
		}
		for (int k = 0; k + 1 < steps; k++) {
			const int l0 = first + 2 * k, r0 = l0 + 1, l1 = l0 + 2, r1 = l0 + 3;
			out_indices.push_back(l0);
			out_indices.push_back(r0);
			out_indices.push_back(r1);
			out_indices.push_back(l0);
			out_indices.push_back(r1);
			out_indices.push_back(l1);
		}
	}

	// --- the blend shapes. Each hair vertex follows the head by a fit of the whole scalp (scale and move) to the shape, plus the residual of the body vertex its lock
	// starts on (fading out along the strand: roots stay on the scalp, tips follow the head), and hair that hangs below the eyes on the neck and shoulders follows
	// the nearest body vertex instead (Weight and Muscle grow the shoulders, which the head fit does not know about).
	const int out_count = int(out_vertices.size());
	std::vector<int> near_vertex(out_count, -1);
	std::vector<float> near_weight(out_count, 0.0f);
	for (int i = 0; i < out_count; i++) {
		if (out_cap[i] != 0) {
			continue;
		}
		const double below = (eye_y - 0.03) - double(out_vertices[i].y);
		if (below <= 0.0) {
			continue;
		}
		double distance_squared = 0.0;
		const int nearest = near_grid.nearest(out_vertices[i], distance_squared);
		if (nearest < 0) {
			continue;
		}
		const double closeness = Math::clamp(1.0 - std::sqrt(distance_squared) / 0.09, 0.0, 1.0);
		const double depth = Math::clamp(below / 0.1, 0.0, 1.0);
		near_vertex[i] = nearest;
		near_weight[i] = float(closeness * depth * depth * (3.0 - 2.0 * depth));
	}

	Array blend_arrays;
	PackedStringArray blend_names;
	for (size_t s = 0; s < p_body->shape_deltas.size(); s++) {
		const std::vector<Vector3> &delta = p_body->shape_deltas[s];
		const HeadFit fit = fit_head(vertices, delta, scalp_ids);
		PackedVector3Array shape_positions;
		shape_positions.resize(out_count);
		Vector3 *write = shape_positions.ptrw();
		for (int i = 0; i < out_count; i++) {
			const int b = out_bound[i];
			const double along = out_cap[i] != 0 ? 0.0 : double(out_s[i]);
			const Vector3 residual = delta[b] - fit.delta_at(vertices[b]);
			const real_t decay = real_t(Math::clamp(1.0 - along * 2.0, 0.0, 1.0));
			Vector3 move = fit.delta_at(out_vertices[i]) + residual * decay;
			if (near_vertex[i] >= 0 && near_weight[i] > 0.0f) {
				move = move.lerp(delta[near_vertex[i]], near_weight[i]);
			}
			write[i] = out_vertices[i] + move;
		}
		PackedVector3Array normals_copy;
		normals_copy.resize(out_count);
		PackedFloat32Array tangents_copy;
		tangents_copy.resize(out_count * 4);
		Vector3 *normal_write = normals_copy.ptrw();
		float *tangent_write = tangents_copy.ptrw();
		for (int i = 0; i < out_count; i++) {
			normal_write[i] = out_normals[i];
			tangent_write[i * 4] = float(out_tangents[i].x);
			tangent_write[i * 4 + 1] = float(out_tangents[i].y);
			tangent_write[i * 4 + 2] = float(out_tangents[i].z);
			tangent_write[i * 4 + 3] = 1.0f;
		}
		// The shapes are NORMALIZED: each carries the full positions and the base normals and tangents. (A zero normal or tangent delta is not "no change": the
		// engine stores shape normals as unit vectors, so a zero decodes to a vector pointing backwards and the blend pulls every hair normal toward it; and the
		// mesh bounds would be built from the offsets.)
		Array shape;
		shape.resize(Mesh::ARRAY_MAX);
		shape[Mesh::ARRAY_VERTEX] = shape_positions;
		shape[Mesh::ARRAY_NORMAL] = normals_copy;
		shape[Mesh::ARRAY_TANGENT] = tangents_copy;
		blend_arrays.push_back(shape);
		blend_names.push_back(String(p_body->shape_names[s]));
	}

	// --- the arrays of the surface
	PackedVector3Array vertex_array;
	PackedVector3Array normal_array;
	PackedVector2Array uv_array;
	PackedVector2Array rest_array; // UV2: the rest place (x + y, z + y) for the shader
	PackedColorArray color_array;
	PackedFloat32Array tangent_array;
	PackedInt32Array index_array;
	vertex_array.resize(out_count);
	normal_array.resize(out_count);
	uv_array.resize(out_count);
	rest_array.resize(out_count);
	color_array.resize(out_count);
	tangent_array.resize(out_count * 4);
	{
		Vector3 *vw = vertex_array.ptrw();
		Vector3 *nw = normal_array.ptrw();
		Vector2 *uw = uv_array.ptrw();
		Vector2 *rw = rest_array.ptrw();
		Color *cw = color_array.ptrw();
		float *tw = tangent_array.ptrw();
		for (int i = 0; i < out_count; i++) {
			vw[i] = out_vertices[i];
			nw[i] = out_normals[i];
			uw[i] = out_uvs[i];
			rw[i] = Vector2(out_vertices[i].x + out_vertices[i].y, out_vertices[i].z + out_vertices[i].y);
			cw[i] = out_colors[i];
			tw[i * 4] = float(out_tangents[i].x);
			tw[i * 4 + 1] = float(out_tangents[i].y);
			tw[i * 4 + 2] = float(out_tangents[i].z);
			tw[i * 4 + 3] = 1.0f;
		}
	}
	index_array.resize(int64_t(out_indices.size()));
	{
		int32_t *iw = index_array.ptrw();
		for (size_t i = 0; i < out_indices.size(); i++) {
			iw[i] = out_indices[i];
		}
	}
	Array arrays;
	arrays.resize(Mesh::ARRAY_MAX);
	arrays[Mesh::ARRAY_VERTEX] = vertex_array;
	arrays[Mesh::ARRAY_NORMAL] = normal_array;
	arrays[Mesh::ARRAY_COLOR] = color_array;
	arrays[Mesh::ARRAY_TANGENT] = tangent_array;
	arrays[Mesh::ARRAY_TEX_UV] = uv_array;
	arrays[Mesh::ARRAY_TEX_UV2] = rest_array;
	arrays[Mesh::ARRAY_INDEX] = index_array;
	built["arrays"] = arrays;
	built["blend_arrays"] = blend_arrays;
	built["blend_names"] = blend_names;
	return built;
}

Ref<ArrayMesh> HumanHair::make_mesh(const Dictionary &p_built) {
	Ref<ArrayMesh> result;
	if (!p_built.has("arrays")) {
		return result;
	}
	Array arrays = p_built["arrays"];
	Array blend_arrays = p_built["blend_arrays"];
	PackedStringArray blend_names = p_built["blend_names"];
	result.instantiate();
	for (int i = 0; i < blend_names.size(); i++) {
		result->add_blend_shape(StringName(blend_names[i]));
	}
	result->set_blend_shape_mode(Mesh::BLEND_SHAPE_MODE_NORMALIZED);
	result->add_surface_from_arrays(Mesh::PRIMITIVE_TRIANGLES, arrays, blend_arrays);
	return result;
}

Ref<ArrayMesh> HumanHair::build(const Ref<ArrayMesh> &p_body, const Dictionary &p_params) {
	return make_mesh(build_arrays(prepare(p_body), p_params));
}

} // namespace godot
