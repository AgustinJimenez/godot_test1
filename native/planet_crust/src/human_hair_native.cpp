#include <chrono>
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

// the body shapes the hair follows as blend shapes (a cheap head fit per shape); all other shapes (face, age) are baked into the body before the hair is built
static bool is_hair_shape(const StringName &p_name) {
	const String name(p_name);
	return name.begins_with("height_") || name.begins_with("weight_") || name.begins_with("muscle_");
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
		if (!is_hair_shape(p_mesh->get_blend_shape_name(s))) {
			continue; // the face and age shapes are not blend shapes of the hair (each costs ~40 bytes per hair vertex, millions of vertices): they are baked into the body the hair is built on
		}
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
	ClassDB::bind_static_method("HumanHair", D_METHOD("bake_shapes", "body", "names", "values"), &HumanHair::bake_shapes);
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
	d["sweep"] = 0.0;
	d["hug"] = 0.0;
	d["quiff"] = 0.0;
	d["spike"] = 0.0; // 0..1: the hair stands off the skin (spiky styles): the first segments point away from the head, gravity and the skull pull hardly bend them
	d["extras"] = 1.0; // 1: extra locks along the front hairline, parting, crown, nape (they fill gaps but crowd those places); 0: only the evenly spaced follicles
	d["swept"] = 0.0;
	d["parting"] = 0.0;
	d["gravity"] = 1.0;
	d["side_trim"] = 0.0;
	d["eye_drop"] = 0.105;
	d["strands"] = 0;
	d["points"] = 0;
	d["strand_width"] = 0.0004; // (still wider than a real hair, 0.07 mm: with fewer hairs than a head, thinner ribbons left specks of skin between them; 0.4 mm is solid)
	d["clump"] = 0.007;
	d["messy"] = 0.0; // 0..1: every lock gets its own length, drift and wobble, so locks differ and cross (wet, tousled hair)
	d["cover"] = 0.0;  // (off by default: it added about 6% guides and showed no visible gain yet) 0..1: after the hair is shaped, patches of the scalp with little hair near them (under a lifted quiff, beside a parting) get extra roots; 0 = off
	d["lock_share"] = 1.0; // 0.01..1: a lower level of detail keeps only the first share of the follicles the full hair accepts (the spacing and every lock's dice are those of the full hair, so the lower level is a SUBSET of it: the same guides, the same shapes, nothing changes style)
	d["tousle"] = 0.0; // 0..1: some locks on the top of the head lift off the scalp and arch over (a tousled pile), the others lie as combed
	d["wet"] = 0.0;  // 0..1: wet hair: the hairs of a lock stick together and end in a point, it hangs heavy and flat, fewer stray hairs, smooth waves
	d["back_length"] = 0.0; // 0..1: the hair behind the crown is longer than the top (up to +60%), a layered cut
	d["beard"] = 0.0;        // 0..1: a short beard and moustache on the jaw, cheeks and chin (0: none; the amount is the density)
	d["beard_length"] = 0.012; // metres
	d["beard_zone"] = 0.0;     // 0: full beard (cheeks, jaw, chin, moustache); 1: goatee (moustache and a chin patch, bare cheeks)
	d["strips"] = 0.0; // 0..1: the front hair falls as separate strips (about 1.3 cm wide) with gaps between them, each strip its own length
	d["gaps"] = 0.0;  // 0..1: patches of the scalp grow no locks and the rest clump tighter, so the hair parts into separate clumps with the layer below showing between them
	d["wisps"] = 0.0; // 0..1: more hairs stray from their lock as long, wavy wisps
	d["wave"] = 0.0;  // 0..1: every hair gets a slow sideways wave of its own (waves of 3-6 cm, a few mm wide)
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

Ref<ArrayMesh> HumanHair::bake_shapes(const Ref<ArrayMesh> &p_body, const PackedStringArray &p_names, const PackedFloat32Array &p_values) {
	Ref<ArrayMesh> out;
	if (p_body.is_null() || p_body->get_surface_count() < 1) {
		return out;
	}
	Array arrays = p_body->surface_get_arrays(0);
	PackedVector3Array positions = arrays[Mesh::ARRAY_VERTEX];
	const int count = int(positions.size());
	const bool normalized = p_body->get_blend_shape_mode() == Mesh::BLEND_SHAPE_MODE_NORMALIZED;
	Array shapes = p_body->surface_get_blend_shape_arrays(0);
	const int shape_count = p_body->get_blend_shape_count();
	std::vector<Vector3> baked(positions.ptr(), positions.ptr() + count);
	std::vector<std::vector<Vector3>> kept_deltas;
	std::vector<StringName> kept_names;
	for (int s = 0; s < shape_count && s < shapes.size(); s++) {
		const StringName shape_name = p_body->get_blend_shape_name(s);
		Array shape = shapes[s];
		PackedVector3Array shape_positions = shape[Mesh::ARRAY_VERTEX];
		if (shape_positions.size() != count) {
			continue;
		}
		std::vector<Vector3> delta(count);
		for (int i = 0; i < count; i++) {
			delta[size_t(i)] = normalized ? shape_positions[i] - positions[i] : shape_positions[i];
		}
		double weight = 0.0;
		for (int n = 0; n < p_names.size() && n < p_values.size(); n++) {
			if (StringName(p_names[n]) == shape_name) {
				weight = double(p_values[n]);
			}
		}
		if (weight != 0.0) {
			for (int i = 0; i < count; i++) {
				baked[size_t(i)] += delta[size_t(i)] * real_t(weight);
			}
		}
		if (is_hair_shape(shape_name)) {
			kept_deltas.push_back(std::move(delta));
			kept_names.push_back(shape_name);
		}
	}
	PackedVector3Array new_positions;
	new_positions.resize(count);
	for (int i = 0; i < count; i++) {
		new_positions[i] = baked[size_t(i)];
	}
	arrays[Mesh::ARRAY_VERTEX] = new_positions;
	Array blend;
	for (size_t k = 0; k < kept_deltas.size(); k++) {
		Array shape;
		shape.resize(Mesh::ARRAY_MAX);
		PackedVector3Array shape_positions;
		shape_positions.resize(count);
		for (int i = 0; i < count; i++) {
			shape_positions[i] = baked[size_t(i)] + kept_deltas[k][size_t(i)];
		}
		shape[Mesh::ARRAY_VERTEX] = shape_positions;
		PackedVector3Array shape_normals = arrays[Mesh::ARRAY_NORMAL];
		shape[Mesh::ARRAY_NORMAL] = shape_normals;
		blend.push_back(shape);
	}
	out.instantiate();
	for (size_t k = 0; k < kept_names.size(); k++) {
		out->add_blend_shape(kept_names[k]);
	}
	out->set_blend_shape_mode(Mesh::BLEND_SHAPE_MODE_NORMALIZED);
	out->add_surface_from_arrays(Mesh::PRIMITIVE_TRIANGLES, arrays, blend);
	return out;
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
	if (param(p_params, "length", 0.12) < 0.005) {
		return built; // a length of (nearly) zero is a bald head: no hair, no scalp layer
	}
	const double length = std::max(0.01, param(p_params, "length", 0.12));
	const int requested_locks = int(Math::clamp(param(p_params, "locks", 2600), 1.0, 9000.0));
	const double requested_width = std::max(0.002, param(p_params, "lock_width", 0.018));
	// very short hair gets narrower locks (a ribbon wider than the hair is long looks like a flat plate) and more of them
	const double lock_width = std::min(requested_width, 0.002 + length * 0.25);
	// strands mode: every guide lock grows `strands` single hairs (thin ribbons of strand_width) that follow it, clumped within `clump` metres
	int strands = int(Math::clamp(param(p_params, "strands", 0), 0.0, 96.0));
	const double strand_width = Math::clamp(param(p_params, "strand_width", 0.0004), 0.00005, 0.004);
	const double clump = Math::clamp(param(p_params, "clump", 0.007), 0.0, 0.03);
	const int plain_lock_count = int(std::min(9000.0, double(requested_locks) * requested_width / lock_width));
	const double lock_share = Math::clamp(param(p_params, "lock_share", 1.0), 0.01, 1.0);
	const int lock_count = strands > 0 ? std::min(requested_locks, 6000) : plain_lock_count; // (single hairs: the number of follicles is what was asked, whatever the lock width of a short style)
	const double wetness = Math::clamp(param(p_params, "wet", 0.0), 0.0, 1.0);
	const double tousle = Math::clamp(param(p_params, "tousle", 0.0), 0.0, 1.0);
	const double cover = Math::clamp(param(p_params, "cover", 0.0), 0.0, 1.0);
	const bool cover_debug = param(p_params, "cover_debug", 0.0) > 0.5;
	const double volume = std::max(0.0, param(p_params, "volume", 1.0)) * (1.0 - 0.45 * wetness); // (wet hair is heavy: it lies on the head)
	const double curl = std::max(0.0, param(p_params, "curl", 0.0));
	const double fringe = Math::clamp(param(p_params, "fringe", 0.4), 0.0, 1.0);
	const double hug = Math::clamp(param(p_params, "hug", 0.0), 0.0, 1.0); // 0: hair hangs from the crown; 1: it follows the curve of the skull (short, stiff hair lying on the head)
	const double quiff = Math::clamp(param(p_params, "quiff", 0.0), 0.0, 1.0); // the front of the hair lifts off the forehead and rolls back (a pompadour / quiff)
	const double spike = Math::clamp(param(p_params, "spike", 0.0), 0.0, 1.0) * Math::clamp(1.0 - (length - 0.08) / 0.1, 0.0, 1.0); // (fades out on longer hair: a long hair does not stand up, it would make a hat)
	const double swept = Math::clamp(param(p_params, "swept", 0.0), 0.0, 1.0); // 0: the front splits at the parting, to both sides; 1: all of it falls over to the side away from the parting
	const double sweep = Math::clamp(param(p_params, "sweep", 0.0), 0.0, 1.0); // 0: combed away from the crown; 1: all of it combed straight back (slicked back)
	const double parting = Math::clamp(param(p_params, "parting", 0.0), -1.0, 1.0);
	const double gravity = std::max(0.0, param(p_params, "gravity", 1.0)) * (1.0 + 0.6 * wetness);
	const double side_trim = Math::clamp(param(p_params, "side_trim", 0.0), 0.0, 1.0);
	const double messy = Math::clamp(param(p_params, "messy", 0.0), 0.0, 1.0);
	const double wave = Math::clamp(param(p_params, "wave", 0.0), 0.0, 1.0);
	const double gaps = Math::clamp(param(p_params, "gaps", 0.0), 0.0, 1.0);
	const double strips = Math::clamp(param(p_params, "strips", 0.0), 0.0, 1.0);
	const double beard = Math::clamp(param(p_params, "beard", 0.0), 0.0, 1.0);
	const double back_long = Math::clamp(param(p_params, "back_length", 0.0), 0.0, 1.0);
	const double beard_length = Math::clamp(param(p_params, "beard_length", 0.012), 0.002, 0.06);
	const bool goatee = param(p_params, "beard_zone", 0.0) > 0.5;
	const double wisps = Math::clamp(param(p_params, "wisps", 0.0), 0.0, 1.0);
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
	// the scale of "how far to the front" (front_here, front_share, ...): from the head DEPTH, not its width: a wide head (head_wide) made front_here smaller everywhere, so fewer roots counted as the front and the fringe fell over the face. 0.8 x the half depth equals the half width of the default heads (0.0883 / 0.1103).
	const double front_scale = std::max(0.8 * 0.5 * (z_front - z_back), 0.05);
	const Vector3 crown(real_t(parting * half_width * 0.45), real_t(top_y), real_t(centre_z - 0.015));

	// --- the scalp: the vertices above the hairline (low at the nape, higher at the temples and the forehead)
	auto hairline = [&](const Vector3 &v) {
		const double azimuth = std::abs(std::atan2(double(v.x), double(v.z - centre_z))); // 0 front .. pi back
		const double front_y = eye_y + 0.068;
		const double side_y = eye_y + 0.014;
		const double back_y = eye_y - 0.088 + 0.045 * side_trim * side_trim; // (the nape: real hair grows down to about the middle of the back of the neck; a short back and sides (fade) is clippered higher up)
		const double a = Math::clamp((azimuth - 0.7) / 0.7, 0.0, 1.0);       // front .. side (down to the sideburn by the front of the ear): a long slope, so the temple is a round curve, not a corner
		const double b = Math::clamp((azimuth - 1.3) / 0.9, 0.0, 1.0);       // side .. back
		const double front_side = front_y + (side_y - front_y) * (a * a * (3.0 - 2.0 * a));
		const double line = front_side + (back_y - side_y) * (b * b * (3.0 - 2.0 * b));
		// Measured on the body: the ear spans azimuth 1.70 .. 1.93. In front of it the hair runs down into a sideburn (temple above, then the sideburn to mid-ear height); above the
		// ear it starts just over the top of the ear (so short hair does not drape over it like a muff); behind it the hairline slopes down to the nape.
		auto smooth = [](double t) {
			t = Math::clamp(t, 0.0, 1.0);
			return t * t * (3.0 - 2.0 * t);
		};
		const double sideburn = smooth((azimuth - 1.05) / 0.5) * (1.0 - smooth((azimuth - 1.6) / 0.1)); // (a longer slope down into the sideburn: a notch with square corners looked cut out)
		double h = line + ((eye_y - 0.012) - line) * sideburn;
		const double ear = smooth((azimuth - 1.6) / 0.1) * (1.0 - smooth((azimuth - 1.86) / 0.1));
		h = std::max(h, h + (eye_y + (0.006) - h) * ear); // (the hair comes down to the top of the ear: higher left a bare notch of skin above it, lower covered the ear like a muff)
		return h;
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
		const Vector3 tri_centre = (vertices[a] + vertices[b] + vertices[c]) / 3.0f;
		const double tri_axis = std::hypot(double(tri_centre.x), double(tri_centre.z - centre_z));
		const bool centre_on_scalp = tri_axis < half_width * 1.7 && (tri_axis > half_width * 0.6 || tri_centre.y > eye_y + 0.02) && tri_centre.y > hairline(tri_centre);
		if (int(scalp[a]) + int(scalp[b]) + int(scalp[c]) >= 2 || (int(scalp[a]) + int(scalp[b]) + int(scalp[c]) >= 1 && centre_on_scalp)) { // two corners above the hairline are enough (the coarse mesh at the back of the head leaves holes otherwise), or one when the middle of the triangle is above it
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
	std::vector<float> out_guide; // the guide strand each hair vertex follows when the hair is simulated (-1: the scalp layer, which does not move)
	std::vector<Vector3> guide_rest; // the rest points of every guide strand (`steps` per guide, in the body's space)
	int current_guide = -1;
	int guide_count = 0;

	auto add_vertex = [&](const Vector3 &p_position, const Vector3 &p_normal, const Vector2 &p_uv, const Color &p_color, int p_bound, const Vector3 &p_tangent, float p_s, bool p_cap) {
		out_vertices.push_back(p_position);
		out_normals.push_back(p_normal);
		out_uvs.push_back(p_uv);
		out_colors.push_back(p_color);
		out_tangents.push_back(p_tangent);
		out_bound.push_back(p_bound);
		out_s.push_back(p_s);
		out_cap.push_back(p_cap ? 1 : 0);
		out_guide.push_back(p_cap ? -1.0f : float(current_guide));
		return int(out_vertices.size()) - 1;
	};

	// --- the cap: the scalp triangles lifted a hair's breadth, fading out toward the hairline (alpha), blue = 1 marks it for the shader
	std::vector<int> cap_index(vertex_count, -1);
	for (int t : scalp_triangles) {
		for (int k = 0; k < 3; k++) {
			const int v = indices[t + k];
			if (cap_index[v] < 0) {
				// signed height above the hairline, -1..1 for +-1.4 cm, stored as 0..1: below the line it keeps counting down, so the shader's cut runs along the true hairline across a triangle (clamping at 0 pushed the cut into steps of one triangle)
				const double fade = 0.5 + 0.5 * Math::clamp((double(vertices[v].y) - hairline(vertices[v])) / 0.014, -1.0, 1.0);
				// how shaved the scalp is here (the hair there is cut short by side_trim): the shader shows more stubble and skin where it is high
				const double cap_topness = Math::clamp((double(vertices[v].y) - (eye_y + 0.03)) / std::max(top_y - eye_y - 0.03, 0.02), 0.0, 1.0);
				const double cap_front = Math::clamp((double(vertices[v].z) - centre_z) / front_scale, 0.0, 1.0);
				const double shaved = side_trim * (1.0 - cap_topness) * (1.0 - cap_front); // (the front hairline keeps its hair: only the sides and back are clippered)
				cap_index[v] = add_vertex(vertices[v] + normals[v] * 0.0018f, normals[v], Vector2(0.5f, 0.5f), Color(0.5f, float(shaved), 1.0f, float(fade)), v, cap_tangent(normals[v]), 0.0f, true);
			}
		}
		out_indices.push_back(cap_index[indices[t]]);
		out_indices.push_back(cap_index[indices[t + 1]]);
		out_indices.push_back(cap_index[indices[t + 2]]);
	}

	const auto build_clock = std::chrono::steady_clock::now();
	auto lap = [&](const char *name) {
		if (cover_debug) {
			godot::UtilityFunctions::print("HUMAN_TIME ", name, " at ms ", std::chrono::duration<double, std::milli>(std::chrono::steady_clock::now() - build_clock).count());
		}
	};
	// --- the locks
	const int plain_steps = std::max(7, std::min(14, int(length / 0.015) + 6));
	// curls need more points per strand: a coil drawn with four points a turn is a zigzag
	const int steps_plain = curl > 0.05 ? std::max(plain_steps, std::min(18, int(length / 0.008) + 5)) : plain_steps;
	// single hairs are many: fewer points each (a hair is nearly straight over a few millimetres) keeps the vertex count in check
	// `points` (3..16) sets the points per hair directly (2 vertices each): fewer is cheaper, more drapes smoother. 0 = automatic.
	const int points_param = int(Math::clamp(param(p_params, "points", 0), 0.0, 16.0));
	const int steps = points_param >= 3 ? points_param : (strands > 0 ? std::min(steps_plain, 9) : steps_plain);
	if (strands > 0) {
		// a guard against too many hairs: the simulation draws the hair with one compute group per few thousand vertices and the device allows 65,535 groups; a request of 560,000+ hairs
		// (a bad guess of hairs per lock) built so many vertices that the simulation failed and the head came out bald. Keep the vertex count under a budget by lowering the hairs per lock.
		// measured: the failing build had 5,494,653 vertices in 85,854 groups = 64 vertices per group, so the limit is 65,535 x 64 = 4,194,240 vertices for the whole mesh (head hair, beard, cap)
		const double beard_vertices = 500000.0 * Math::clamp(param(p_params, "beard", 0.0), 0.0, 1.0);
		const double max_vertices = Math::clamp(param(p_params, "max_vertices", 4150000.0), 200000.0, 12000000.0) - beard_vertices;
		const double expected_vertices = double(lock_count) * 1.4 * double(strands) * 0.8 * 2.0 * double(steps); // (1.4 guides per lock is the least seen: the real count varies from 1.4 to 2.4 with the style, so this only catches absurd requests; the lab checks the real vertex count after the build)
		if (expected_vertices > max_vertices) {
			strands = std::max(2, int(double(strands) * max_vertices / expected_vertices));
		}
	}
	const double gravity_amount = Math::clamp(length / 0.15, 0.25, 1.6) * gravity;
	const double head_scale_x = std::max(half_width, 0.05);
	// long hair with a fringe: more locks along the front hairline, so bangs are a curtain and the forehead does not show between a few thin locks
	const double front_density = 0.15; // (fixed: a head has the same follicles whatever the style; the style only changes how the hairs lie)
	(void)fringe; // (a quiff stands up and leaves the front hairline bare too)
	const bool use_extras = false; // (the style-dependent extras are off: only the fixed follicle set below)
	const int fringe_extra = int(double(lock_count) * (1.5 + 3.0 * front_density) * (1.0 + 1.5 * quiff));
	const int crown_extra = lock_count * 6; // (always: the whorl is where every direction of the flow meets, and a few locks there are needed whatever else is off) // extra locks around the crown: the hair there splays out from the whorl and leaves slits of skin
	// roots by dart throwing (the "Poisson" spacing the Blender hair add-on uses): a root closer than `min_gap` to an accepted one is dropped. Roots chosen purely at random clump and leave gaps
	// (the bare specks), at the same number of locks. The main locks draw up to 3x as often, until `lock_count` are accepted; the extra locks come after.
	const int main_draws = lock_count * 3;
	const double min_gap = 0.7 * std::sqrt(total_area / double(std::max(lock_count, 1)));
	std::unordered_map<int64_t, std::vector<Vector3>> root_cells;
	auto cell_key = [&](int cx, int cy, int cz) { return (int64_t(cx) * 73856093LL) ^ (int64_t(cy) * 19349663LL) ^ (int64_t(cz) * 83492791LL); };
	int accepted_main = 0;
	// Coverage pass: the hair is first grown as guides only (cheap) to see which patches of the scalp end up with little hair near them (a lifted quiff, a parting, an ear notch);
	// extra roots are then added there and the real build runs. Roots alone leave gaps wherever the hair is shaped away from them.
	struct FillRoot {
		int t;
		double u, w;
	};
	std::vector<FillRoot> fills;
	std::vector<Vector3> cover_points;
	const int base_total = main_draws + fringe_extra + crown_extra;
	int fill_count = 0;
	const int passes = cover > 0.0 ? 2 : 1;
	for (int pass = 0; pass < passes; pass++) {
	const bool guides_only = passes == 2 && pass == 0;
	if (pass == passes - 1) {
		root_cells.clear();
		accepted_main = 0;
	}
	for (int lock = 0; lock < base_total + fill_count; lock++) {
		if (lock < main_draws && accepted_main >= std::max(1, int(double(lock_count) * lock_share))) {
			lock = main_draws - 1; // (enough locks: on to the extras)
			continue;
		}
		// one dice per lock: whether a lock is kept near a float rounding edge cannot shift the numbers of every lock after it
		Dice dice(seed + uint64_t(lock) * 0x2545F4914F6CDD1DULL);
		// a root on the scalp, chosen by area
		const bool is_fill = lock >= base_total;
		const double pick = dice.unit() * total_area;
		const int tri = int(std::lower_bound(cumulative_area.begin(), cumulative_area.end(), pick) - cumulative_area.begin());
		const int t = is_fill ? fills[size_t(lock - base_total)].t : scalp_triangles[std::min(tri, int(scalp_triangles.size()) - 1)];
		const int ia = indices[t], ib = indices[t + 1], ic = indices[t + 2];
		double u = dice.unit(), w = dice.unit();
		if (u + w > 1.0) {
			u = 1.0 - u;
			w = 1.0 - w;
		}
		if (is_fill) {
			u = fills[size_t(lock - base_total)].u;
			w = fills[size_t(lock - base_total)].w;
		}
		const double a_weight = 1.0 - u - w;
		const Vector3 root = vertices[ia] * real_t(a_weight) + vertices[ib] * real_t(u) + vertices[ic] * real_t(w);
		Vector3 normal = (normals[ia] * real_t(a_weight) + normals[ib] * real_t(u) + normals[ic] * real_t(w)).normalized();
		// the hairline fades out: few, short locks right at its edge instead of a hard line
		const double above_hairline = double(root.y) - hairline(root);
		const double feather = Math::clamp(above_hairline / 0.016, 0.0, 1.0);
		if (above_hairline <= 0.0 || (strands == 0 && dice.unit() > 0.15 + 0.85 * feather)) { // never below the hairline (single hairs thin out toward the edge by hairs per lock instead, below: a few whole locks left a row of separate blobs)
			continue;
		}
		if (lock >= main_draws && lock_share < 1.0) {
			// the extra locks (hairline, crown, nape) thin out with the level too, by a hash of the lock number, not by the lock's dice: a lock kept at a low level is also kept at every higher level (a subset)
			const double keep_hash = std::sin(double(lock) * 12.9898 + 78.233) * 43758.5453;
			if ((keep_hash - std::floor(keep_hash)) > std::pow(lock_share, 0.55)) {
				continue;
			}
		}
		if (lock >= main_draws && !is_fill) {
			// the extra locks: along the front hairline (the first 4.5 cm of the forehead's hair, thinned by how much fringe there is) and around the crown
			const double extra_front = Math::clamp((double(root.z) - centre_z) / front_scale, 0.0, 1.0);
			const bool front_ok = extra_front >= 0.55 && above_hairline <= 0.045 + 0.06 * quiff && dice.unit() <= (0.25 + 0.5 * front_density) * (1.0 + 1.5 * quiff); // (a quiff lifts the front hair off the scalp: more roots over the area it leaves, or the skin shows under the lift)
			const double crown_dist = std::hypot(double(root.x) - double(crown.x), double(root.z) - double(crown.z));
			const double crown_near = std::max(0.0, 1.0 - crown_dist / 0.05);
			const bool crown_ok = crown_dist < 0.05 && dice.unit() < 0.04 + 0.3 * crown_near * crown_near + (crown_dist < 0.015 ? 0.7 : 0.0); // (densest right at the whorl, where the hair splays most)
			// the nape and the lower back: the hair is cut short there and tapers into the hairline, so a plain share of locks left slits of skin
			const bool back_ok = double(root.z) < centre_z - 0.4 * half_width && above_hairline < 0.07 && dice.unit() < 0.3;
			const bool fill_ok = dice.unit() < 0.02; // a thin random fill everywhere: the odd gap between locks (a speck of skin) is covered
			const bool edge_ok = strands > 0 && above_hairline < 0.02 && dice.unit() < 0.5; // (the edge of the hairline, most of all above the ears and at the temples: sparse there it read as a bald patch) // more (thin) locks along the hairline itself: an even edge instead of one tuft per lock
			// along the parting line the hair diverges, so a strip there is thin: more locks that lie close to the line fill it
			const bool part_ok = std::abs(double(root.x) - double(crown.x)) < 0.025 && double(root.z) > double(crown.z) - 0.03 && dice.unit() < 0.35;
			if (!crown_ok && !part_ok && !front_ok && !edge_ok) { // (the whorl and the parting line always get their extra locks: the scalp patch under them is too coarse for the mesh there)
				continue;
			}
		}
		if (lock < main_draws) {
			const int cx = int(std::floor(double(root.x) / min_gap)), cy = int(std::floor(double(root.y) / min_gap)), cz = int(std::floor(double(root.z) / min_gap));
			bool too_close = false;
			for (int dx = -1; dx <= 1 && !too_close; dx++) {
				for (int dy = -1; dy <= 1 && !too_close; dy++) {
					for (int dz = -1; dz <= 1 && !too_close; dz++) {
						auto it = root_cells.find(cell_key(cx + dx, cy + dy, cz + dz));
						if (it == root_cells.end()) {
							continue;
						}
						for (const Vector3 &other : it->second) {
							if ((other - root).length_squared() < real_t(min_gap * min_gap)) {
								too_close = true;
								break;
							}
						}
					}
				}
			}
			if (too_close) {
				continue;
			}
			root_cells[cell_key(cx, cy, cz)].push_back(root);
			accepted_main++;
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
		{
			// a whorl: close to the crown the hair spirals instead of fanning straight out (strands that all point away from one spot leave the crown itself bare, since
			// the number of hairs crossing a circle of radius d falls to nothing as d goes to zero)
			const double crown_d = std::hypot(double(root.x) - double(crown.x), double(root.z) - double(crown.z));
			const double core = 1.0 - Math::clamp(crown_d / 0.05, 0.0, 1.0); // 1 at the crown, 0 five cm away
			if (core > 0.0) {
				// at the very crown the hair goes round it (tangent), farther out it fans away (radial): no hole where everything points away from one spot
				radial = (radial * real_t(1.0 - 0.85 * core * core) + Vector3(-radial.z, 0.0f, radial.x) * real_t(1.6 * core)).normalized();
			}
		}
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
		{
			// the crown: hair within 9 cm of it (more and more toward it) goes the same way (back), so it covers the crown itself; fanning out of one point left a bare patch there
			const double crown_dist = std::hypot(double(root.x) - double(crown.x), double(root.z) - double(crown.z));
			const double crown_core = Math::clamp(1.0 - crown_dist / 0.09, 0.0, 1.0);
			if (crown_core > 0.0) {
				const Vector3 back_dir(0.0f, 0.0f, -1.0f);
				Vector3 along = back_dir - normal * real_t(back_dir.dot(normal));
				if (along.length() > 0.25f) {
					flow = flow.lerp(along.normalized(), real_t(std::min(0.95, 1.4 * crown_core))).normalized();
				}
			}
		}
		if (sweep > 0.0) {
			// slicked back: along the scalp toward the nape, from the forehead over the top and down the back
			const Vector3 back(0.0f, 0.0f, -1.0f);
			Vector3 along_back = back - normal * real_t(back.dot(normal));
			if (along_back.length() < 0.25f) {
				along_back = Vector3(0.0f, -1.0f, 0.0f) - normal * real_t(normal.y * -1.0f); // (the back of the head faces back: comb down it)
			}
			if (along_back.length() > 1e-4f) {
				flow = flow.lerp(along_back.normalized(), real_t(sweep)).normalized();
			}
		}
		const double front_here = Math::clamp((double(root.z) - centre_z) / front_scale, 0.0, 1.0);
		const double near_front_edge = Math::clamp(1.0 - above_hairline / 0.10, 0.0, 1.0); // the lift is strongest at the hairline and fades over the next 10 cm
		const double lift = quiff * front_here * near_front_edge;
		const double lift_start = lift;
		if (lift > 0.0) {
			flow = (flow + Vector3(0.0f, real_t(2.0 * lift), 0.0f)).normalized(); // up off the forehead; gravity and the sweep roll it back over the top
		}
		// never combed upward: on a back-sloping part of the scalp the combed direction points up, and a lock rooted at the crown then stands up like an antenna
		const real_t max_up = real_t(0.1 + 0.55 * lift);
		if (flow.y > max_up) {
			flow.y = max_up;
			flow = flow.normalized();
		}
		if (flow.z > 0.0f && front_here > 0.45 - 0.4 * Math::clamp((length - 0.1) / 0.1, 0.0, 1.0)) { // (long hair: nearly the whole forward half is combed back by `fringe`, or it falls over the face) // (only the front: flipping all of the forward half to run back leaves a hole at the crown where the two halves meet)
			Vector3 swept_back(flow.x * 0.3f, flow.y, -flow.z);
			flow = swept_back.lerp(flow, real_t(fringe)).normalized();
		}
		const double part_length_scale = Math::clamp((length - 0.03) / 0.1, 0.0, 1.0); // (no parting at all on very short hair: a crack down the middle of a buzz cut) // short hair splits less: pushed sideways over a few cm it empties a wide strip along the parting (the density there was a fifth of that at the sides)
		double side_of_part = (root.x - crown.x) >= 0.0 ? 1.0 : -1.0;
		if (swept > 0.0) {
			const double away = parting >= 0.0 ? -1.0 : 1.0; // from the parting the hair falls over to the other side
			side_of_part += (away - side_of_part) * swept;
		}
		// the front splits at the parting: hair there is pushed to either side so it does not hang straight over the face
		const double front_share = Math::clamp((double(root.z) - centre_z) / front_scale, 0.0, 1.0);
		// right at the parting line the hair splits gently (a hard push opened a 2 cm gap that showed the scalp layer as a flat block); farther from it the full push
		const double part_soft = Math::clamp(1.5 * std::abs(double(root.x) - double(crown.x)) / (0.03 + 0.03 * quiff) - 0.5 - 1.2 * quiff, -0.5 - 1.2 * quiff, 1.0); // (a wider, stronger cross-over on a quiff: its hair stands up and leaves a slit along the line) // the two sides lean slightly toward each other at the line (-0.5), neutral 6 mm away, full push 3 cm away: the hair crosses over the line, so there is no slit
		const double part_push = (1.0 - Math::clamp((0.0 - (double(root.z) - double(crown.z))) / 0.05, 0.0, 1.0)) * std::min(0.3, (0.14 * Math::clamp(front_share * 2.5, 0.0, 1.0) + 0.7 * front_share) * part_soft * part_length_scale); // (a cap: the front hair goes back more than it goes to the side)
		flow = (flow + Vector3(real_t(side_of_part * part_push), 0.0f, 0.0f)).normalized();

		double strip_length = 1.0;
		if (strips > 0.0 && front_share > 0.25) {
			// the fringe: strips across the forehead (a hash of the strip number, so every lock of a strip agrees): some strips are missing, the others differ in length
			const int strip_id = int(std::floor((double(root.x) - double(crown.x)) / 0.013));
			auto strip_hash = [](int id, double salt) {
				const double h = std::sin(double(id) * 78.233 + salt * 12.9898) * 43758.5453;
				return h - std::floor(h);
			};
			const double above_line = Math::clamp((double(root.y) - hairline(root)) / 0.035, 0.0, 1.0); // (right at the hairline no strip is missing: its roots are what covers the forehead's edge, a gap there shows bare skin)
			if (strip_hash(strip_id, 1.0) < strips * 0.4 * Math::clamp((front_share - 0.25) * 4.0, 0.0, 1.0) * above_line) {
				continue;
			}
			strip_length = 1.0 + strips * (strip_hash(strip_id, 5.0) - 0.4) * 0.8 * Math::clamp((front_share - 0.25) * 4.0, 0.0, 1.0);
		}
		if (gaps > 0.0) {
			// clump gaps: a smooth patchy field over the head (patches of about 2.5 cm): where it is low no lock grows, so the hair splits into clumps with gaps between them
			auto cell = [](int ix, int iy) {
				const double h = std::sin(double(ix) * 127.1 + double(iy) * 311.7) * 43758.5453;
				return h - std::floor(h);
			};
			const double gx = (double(root.x) + double(root.y)) * 40.0, gy = (double(root.z) + double(root.y)) * 40.0;
			const int ix = int(std::floor(gx)), iy = int(std::floor(gy));
			double fx = gx - ix, fy = gy - iy;
			fx = fx * fx * (3.0 - 2.0 * fx);
			fy = fy * fy * (3.0 - 2.0 * fy);
			const double patch = (cell(ix, iy) * (1.0 - fx) + cell(ix + 1, iy) * fx) * (1.0 - fy) + (cell(ix, iy + 1) * (1.0 - fx) + cell(ix + 1, iy + 1) * fx) * fy;
			if (patch < gaps * 0.75 && double(root.y) < top_y - 0.012) {
				continue; // (not on the very top: the crown has to stay covered)
			}
		}
		// grow it
		// the top keeps its length; the sides and back are trimmed by side_trim (a short back and sides)
		const double topness = Math::clamp((double(root.y) - (eye_y + 0.03)) / std::max(top_y - eye_y - 0.03, 0.02), 0.0, 1.0);
		// the hair tapers short where it meets the skin at the sides and back (a fade, not a ledge): close to the hairline it is a quarter of its length, over the next 3.5 cm it grows to full
		const double taper_t = Math::clamp((double(root.y) - hairline(root)) / (0.035 + 0.04 * side_trim), 0.0, 1.0); // (a fade: the more the sides are cut, the longer the gradient up to the full length)
		const double taper = 1.0 - (1.0 - front_share) * (0.75 + 0.2 * side_trim * side_trim) * side_trim * (1.0 - taper_t * taper_t * (3.0 - 2.0 * taper_t));
		const double crown_keep = Math::clamp(1.0 - std::hypot(double(root.x) - double(crown.x), double(root.z) - double(crown.z)) / 0.07, 0.0, 1.0); // near the crown the hair is never trimmed: it has to cover the whorl
		const double trim = std::max((1.0 - side_trim * (1.0 - topness)) * taper, crown_keep);
		// the front (bangs, face-framing locks) is shorter than the rest, so it ends near the cheek instead of hanging past the chin
		double this_length = length * trim * (1.0 - 0.45 * front_share * (1.0 - quiff)) * (0.5 + 0.5 * feather) * dice.range(0.9, 1.1);
		if (side_trim > 0.5 && topness < 0.6) {
			// a clipper cut leaves stubble, not bare skin: the cut sides and back keep a few millimetres of hair
			this_length = std::max(this_length, 0.0030 * side_trim * dice.range(0.8, 1.2) * (0.5 + 0.5 * feather));
		}
		this_length *= strip_length;
		if (back_long > 0.0) {
			this_length *= 1.0 + 0.6 * back_long * Math::clamp((centre_z - double(root.z)) / front_scale + 0.1, 0.0, 1.0) * (1.0 - topness * 0.7); // (longer behind the crown, shorter on top)
		}
		if (messy > 0.0) {
			this_length *= 1.0 + messy * dice.range(-0.3, 0.3); // (a messy head: no two locks are as long)
		}
		this_length = std::max(this_length, 0.0015); // (a follicle always grows a hair: a cut style makes it short, it does not remove it)
		if (this_length < 0.0015) {
			continue; // (a lock shorter than 4 mm: side_trim 1 on the sides and back)
		}
		const double step_length = this_length / (steps - 1);   // the mean segment (the coil radius below scales with it)
		// Short segments near the root, longer toward the tip: a long straight first segment is a chord across the skull (a head is about 9 cm in radius), so the hair
		// would leave the crown at once instead of lying along it. Segment k is `segment[k]` metres.
		std::vector<double> segment(size_t(steps - 1));
		double segment_sum = 0.0;
		for (int k = 0; k < steps - 1; k++) {
			segment[size_t(k)] = 0.3 + 1.4 * double(k) / double(std::max(steps - 2, 1)); // 0.3 x the mean at the root, 1.7 x at the tip
			segment_sum += segment[size_t(k)];
		}
		for (int k = 0; k < steps - 1; k++) {
			segment[size_t(k)] *= this_length / segment_sum;
		}
		const double phase = dice.range(0.0, 6.2831853);
		const double stiffness = dice.range(0.9, 1.1);
		std::vector<Vector3> points;
		points.reserve(steps);
		// The hair drapes: it starts lying along the scalp in the combed direction, gravity pulls it down a little more every step, and the head
		// holds it up (it is pushed out of the surface and walks along it), so it follows the curve of the skull and falls freely where the head ends.
		Vector3 position = root + normal * 0.0035f;
		// tousle: a share of the locks on the top (the more tousle, the more of them) stands up off the scalp, each by its own amount, and gravity then bends it over (an arch)
		double tousle_lock = 0.0;
		if (tousle > 0.0) {
			const double chance_up = dice.unit();
			const double amount_up = dice.range(0.3, 1.0);
			if (chance_up < 0.15 + 0.6 * tousle) {
				tousle_lock = tousle * amount_up * Math::clamp((topness - 0.35) / 0.4, 0.0, 1.0);
			}
		}
		Vector3 direction = (flow * real_t(0.95 - 0.5 * spike - 0.3 * tousle_lock) + normal * real_t(0.04 + 1.4 * spike + 2.4 * tousle_lock)).normalized();
		points.push_back(position);
		const double pull = Math::clamp(0.26 + 0.2 * gravity_amount, 0.06, 0.6) / stiffness; // how much of each step bends toward the ground
		const double curl_radius = curl * (0.004 + 0.3 * step_length);                      // the radius of the coil the strand is wound into afterwards
		const double on_top = Math::clamp((double(root.y) - (top_y - 0.06)) / 0.04, 0.0, 1.0); // 1 at the very top of the head: there the hair lies close (volume lifts the sides, not the crown: tufts rose in a ridge up there)
		const double clearance = (0.0045 + 0.006 * volume) * (1.0 - 0.5 * on_top) + 0.8 * curl_radius; // (a nearest-vertex plane runs under the skin in a dent, so hair there was hidden)               // how far the strand rides above the skin (a coil needs room)
		for (int k = 1; k < steps; k++) {
			const double s = double(k) / (steps - 1);
			// combed-back hair is held on the head by the comb (and the product): gravity only takes it near the tips
			const double held = 1.0 - 0.75 * sweep * Math::clamp(1.0 - (length - 0.12) / 0.13, 0.0, 1.0) * (1.0 - s * s); // (a comb holds short hair against gravity; long hair just falls: held straight out it made wings at the temples)
			const double attract = std::max(sweep, hug) * (1.0 - 0.8 * lift_start * (1.0 - Math::clamp(s * 1.6, 0.0, 1.0))); // (a quiff is not drawn back to the skull at its root)
			if (attract > 0.0) {
				// ... and it follows the skull: drawn toward the head, so it lies along the curve of the crown and down the back instead of streaming off into the air
				Vector3 outward = position - head_centre;
				if (outward.length() > 1e-4f) {
					direction = (direction - outward.normalized() * real_t(0.35 * attract)).normalized();
				}
			}
			const double pull_here = pull * std::min(1.0, 5.0 / double(steps - 1)) * held * (1.0 - 0.85 * spike * (1.0 - Math::clamp(s * 1.3, 0.0, 1.0))) * (1.0 - 0.95 * tousle_lock * (1.0 - Math::clamp(s * 1.0, 0.0, 1.0))) * (1.0 - 0.6 * lift_start * (1.0 - Math::clamp(s * 1.6, 0.0, 1.0))); // a quiff stands up first and only then falls (gravity hardly bends it near the root)
			direction = (direction * real_t(1.0 - pull_here) + Vector3(0.0f, -1.0f, 0.0f) * real_t(pull_here) + flow * real_t(0.05 + 0.3 * sweep * (1.0 - s))).normalized();
			const double seg = segment[size_t(k - 1)];
			Vector3 step = direction * real_t(seg);
			if (lift_start > 0.0 && step.y > 0.0f) {
				// a quiff eases into its ceiling instead of hitting it: a hard kink there (the strand rises, then runs flat) made the simulated strand flip between two shapes for ever
				const double headroom = (double(root.y) + 0.012 + 0.034 * lift_start) - double(position.y);
				step.y *= real_t(Math::clamp(headroom / 0.014, 0.0, 1.0));
			}
			Vector3 candidate = position + step;
			// a little volume: stay off the head by a margin that grows along the strand
			Vector3 from_centre = candidate - head_centre;
			const double ry = std::max(top_y - eye_y, 0.05);
			const double rx = head_scale_x;
			const double rz = std::max(half_width * 1.15, 0.05);
			const double q = std::sqrt((from_centre.x / rx) * (from_centre.x / rx) + (from_centre.y / ry) * (from_centre.y / ry) + (from_centre.z / rz) * (from_centre.z / rz));
			const double margin = 1.0 + 0.01 + 0.04 * volume * std::min(1.0, s * 2.0) * (1.0 - 0.6 * on_top) + 0.38 * lift_start * std::min(1.0, s * 2.0);
			if (q > 1e-6 && q < margin && candidate.y > eye_y - 0.02) {
				candidate = head_centre + from_centre * real_t(margin / q);
			}
			grid.push_out(candidate, clearance);
			grid.push_out(candidate, clearance);
			// nothing grows higher over the crown than the volume allows (a few locks rooted right at the top were lifted off the scalp by the push-out, step after step, and stood up like antennas)
			candidate.y = std::min(candidate.y, real_t(top_y + 0.002 + 0.004 * volume + 0.035 * spike + 0.09 * tousle_lock));
			if (lift_start > 0.0) {
				candidate.y = std::min(candidate.y, real_t(root.y + 0.012 + 0.034 * lift_start)); // a quiff stands a few cm off the forehead, not like an antenna
			}
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
				candidate = position + direction * real_t(seg);
			}
			position = candidate;
			points.push_back(position);
		}

		// round the corners: the drape above moves a point at a time (it is pushed off the head, held under the ceiling, turned by gravity), which leaves sharp kinks in the path.
		// A few passes of neighbour averaging make the strand a smooth curve (the root stays on the scalp; a tip is only drawn toward its neighbours).
		for (int pass = 0; pass < 3; pass++) {
			std::vector<Vector3> smoothed = points;
			for (int k = 1; k + 1 < steps; k++) {
				smoothed[size_t(k)] = points[size_t(k)] * 0.5f + (points[size_t(k - 1)] + points[size_t(k + 1)]) * 0.25f;
			}
			if (steps > 3) {
				smoothed[size_t(steps - 1)] = points[size_t(steps - 1)] * 0.7f + (points[size_t(steps - 2)] + (points[size_t(steps - 2)] - points[size_t(steps - 3)])) * 0.15f + points[size_t(steps - 1)] * 0.15f;
			}
			points = smoothed;
		}

		// messy: each lock drifts away from the way it was combed and wobbles, so neighbouring locks cross and part (the lock keeps its root)
		if (messy > 0.0 && steps > 3) {
			const double drift_angle = dice.range(0.0, 6.2831853);
			const double wobble_phase_a = dice.range(0.0, 6.2831853);
			const double wobble_phase_b = dice.range(0.0, 6.2831853);
			const double wobble_rate = dice.range(1.0, 2.2);
			const double amount = messy * Math::clamp(this_length / 0.10, 0.3, 1.8) * 0.032;
			const std::vector<Vector3> spine = points;
			for (int k = 1; k < steps; k++) {
				const double s = double(k) / (steps - 1);
				const Vector3 tangent = (spine[std::min(k + 1, steps - 1)] - spine[k - 1]).normalized();
				Vector3 side = tangent.cross(Vector3(0.0f, 1.0f, 0.0f));
				if (side.length() < 1e-4f) {
					side = Vector3(1.0f, 0.0f, 0.0f);
				}
				side = side.normalized();
				const Vector3 up = side.cross(tangent).normalized();
				const double ramp = s * s * (3.0 - 2.0 * s);
				const double sway = std::sin(wobble_phase_a + s * 5.0 * wobble_rate) * 0.6 + std::sin(wobble_phase_b + s * 9.0) * 0.4;
				const Vector3 push = (side * real_t(std::cos(drift_angle)) + up * real_t(0.45 * std::sin(drift_angle))) * real_t(amount * (0.8 * s + sway * ramp)); // (mostly sideways: a drift away from the head puffed the top up)
				points[k] = spine[k] + push;
				grid.push_out(points[k], clearance);
			}
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
				// the coil is only as wide as the segments allow (a coil bigger than the segment flips the ribbon, and the segments near the root are short)
				const double fit = std::min(1.0, segment[size_t(k - 1)] / std::max(step_length, 1e-6));
				points[k] = spine[k] + (side * real_t(std::cos(angle)) + up * real_t(std::sin(angle))) * real_t(curl_radius * ramp * fit);
			}
		}

		// the ribbon (strands mode: `strands` single hairs around the guide, each one a hair-thin ribbon)
		const int copies = strands > 0 ? std::max(2, int(double(strands) * (0.6 + 0.4 * feather) * 1.0)) : 1; // (stubble: fewer hairs, so the skin shows through it as it does on a clippered head)
		if (front_share > 0.25 && length > 0.14) {
			// long hair must not hang straight down over the middle of the face: a lock with a point in front of the forehead/brow box moves sideways from there on (to the side it started on), so it frames the face
			const double face_z = centre_z + 0.8 * (z_front - centre_z);
			for (int k = 1; k < steps; k++) {
				const Vector3 &pt = points[size_t(k)];
				if (double(pt.z) > face_z && std::abs(double(pt.x)) < 0.05 && double(pt.y) < eye_y + 0.075 && double(pt.y) > eye_y - 0.09) {
					const double sgn = (root.x - crown.x) >= 0.0f ? 1.0 : -1.0;
					const double sweep_x = sgn * (0.05 - std::abs(double(pt.x)) + 0.01);
					for (int j = k; j < steps; j++) {
						points[size_t(j)].x += real_t(sweep_x * std::min(1.0, double(j - k + 1) / 3.0));
						points[size_t(j)].z -= real_t(0.012 * std::min(1.0, double(j - k + 1) / 3.0));
					}
					break;
				}
			}
		}
		const std::vector<Vector3> guide_points = points;
		if (guides_only) {
			for (const Vector3 &g : guide_points) {
				cover_points.push_back(g);
			}
			continue; // (the coverage pass only needs where the guides go)
		}
		current_guide = guide_count++;
		for (int k = 0; k < steps; k++) {
			guide_rest.push_back(guide_points[size_t(k)]);
		}
		// the frames of the guide (they do not depend on the hair): worked out once for all the hairs of the lock
		std::vector<Vector3> frame_side, frame_up;
		if (strands > 0) {
			frame_side.resize(size_t(steps));
			frame_up.resize(size_t(steps));
			for (int k = 0; k < steps; k++) {
				const Vector3 tan_k = (guide_points[std::min(k + 1, steps - 1)] - guide_points[std::max(k - 1, 0)]).normalized();
				Vector3 side_k = tan_k.cross(Vector3(0.0f, 1.0f, 0.0f));
				if (side_k.length() < 1e-4f) {
					side_k = Vector3(1.0f, 0.0f, 0.0f);
				}
				side_k = side_k.normalized();
				frame_side[size_t(k)] = side_k;
				frame_up[size_t(k)] = side_k.cross(tan_k).normalized();
			}
		}
		for (int copy = 0; copy < copies; copy++) {
		if (strands > 0) {
			const double angle0 = dice.range(0.0, 6.2831853);
			const double near_line = parting != 0.0 ? Math::clamp(1.0 - std::abs(double(root.x) - double(crown.x)) / 0.018, 0.0, 1.0) : 0.0;
			const double near_crown = Math::clamp(1.0 - std::hypot(double(root.x) - double(crown.x), double(root.z) - double(crown.z)) / 0.03, 0.0, 1.0);
			// flyaways: about one hair in a hundred strays from its lock, wider and lifting off the head, so the outline is not a clean edge (a hash of the root, so the dice of the other hairs do not shift)
			const double stray_hash = std::abs(std::sin(double(root.x) * 127.1 + double(root.z) * 311.7 + double(copy) * 17.3 + double(root.y) * 71.9)) * 43758.5453;
			const bool flyaway = (stray_hash - std::floor(stray_hash)) < (0.006 + 0.05 * wisps) * (1.0 - 0.6 * wetness) && this_length > 0.02 && front_share < 0.35; // (no stray hairs from the front: on long hair they were single straight lines across the forehead)
			const double radius0 = clump * (1.0 - 0.6 * gaps) * (1.0 - 0.65 * wetness) * (1.0 - 0.7 * std::min(1.0, 2.0 * lift_start)) * (1.0 + 1.6 * std::max(near_line, near_crown)) * (0.8 + 0.2 * std::min(1.0, this_length / 0.05)) * (1.0 + 1.5 * std::max(0.0, 1.0 - this_length / 0.04) * Math::clamp((this_length - 0.001) / 0.004, 0.0, 1.0)) * (1.0 + 2.2 * Math::clamp((this_length - 0.08) / 0.2, 0.0, 1.0)) * std::sqrt(dice.unit()); // (long hair too: the hairs of one follicle fan out as they lengthen, so a fringe is a curtain, not separate strings) // (short hair spreads wider, not narrower: at 2-3 cm the hairs are shorter than the gap between follicles) // (hairs of a follicle at the parting line or the crown spread wider, over the slit) // (a short lock spreads less: its hairs fanned out into small stars at the hairline)
			for (int k = 0; k < steps; k++) {
				const double s = double(k) / (steps - 1);
				const Vector3 &side_k = frame_side[size_t(k)];
				const Vector3 &up_k = frame_up[size_t(k)];
				const double ramp = Math::clamp(s * 3.0, 0.0, 1.0) * (0.6 + 0.4 * s); // the hairs leave the root together and spread toward the tips
				const double wobble = angle0 + s * 0.35; // nearly parallel to the guide: a spiral here makes the hairs frizz
				Vector3 offset = (side_k * float(std::cos(wobble)) + up_k * float(std::sin(wobble))) * float(radius0 * ramp);
				if (lift_start <= 0.0 && offset.y > 0.0f) {
					// near the top of the head a hair spread out of its lock may not rise: the offset's upward part fades out (a clamp on the height made flat kinks, drawn as thin angular lines above the head)
					const double room = Math::clamp((double(top_y) + 0.004 - double(guide_points[k].y)) / 0.02, 0.0, 1.0);
					offset.y *= real_t(room);
				}
				if (lift_start <= 0.0 && !flyaway) {
					// a hair spread out of its lock slides along the head, it does not leave it: the part of the offset that points away from the head is mostly removed (hairs floated a few cm off the dome as thin ghost lines)
					const Vector3 away = (guide_points[k] - head_centre).normalized();
					const real_t out = offset.dot(away);
					if (out > 0.0f) {
						offset -= away * out * real_t(0.9 * (1.0 - std::min(1.0, s * 1.5)));
					}
				}
				if (flyaway) {
					const Vector3 away_k = (guide_points[k] - head_centre).normalized();
					offset = offset * real_t(2.0 + 3.0 * wisps) + away_k * float((0.006 + 0.02 * wisps) * s * s) + side_k * float((0.006 + 0.02 * wisps) * s * std::sin(angle0)) + up_k * float(0.012 * wisps * s * std::sin(angle0 * 2.3 + s * 11.0));
				}
				if (wetness > 0.0) {
					offset *= real_t(1.0 - 0.85 * wetness * s * s); // (wet: the hairs of a lock converge toward the tip and end in a point)
				}
				points[k] = guide_points[k] + offset;
			}
		}
		if (strands > 0 && steps > 3) {
			// the hair's own path rounded once more (the spread, the ceiling and the crown clamps leave corners that the guide's smoothing does not touch)
			std::vector<Vector3> soft = points;
			for (int k = 1; k + 1 < steps; k++) {
				soft[size_t(k)] = points[size_t(k)] * 0.5f + (points[size_t(k - 1)] + points[size_t(k + 1)]) * 0.25f;
			}
			points = soft;
		}
		const float brightness = float(dice.unit());
		const float chance = float(dice.unit());
		if (strands > 0 && wave > 0.0 && steps > 3) {
			// the wave goes on AFTER the path was rounded, so the smoothing cannot flatten it: a slow wave of the lock's own (shared phase, a little of the hair's own), growing toward the tip
			const double wave_phase = phase + double(brightness) * 0.75 * (1.0 - 0.85 * wetness);
			const double wave_rate = 0.8 + 0.6 * (phase * 0.37 - std::floor(phase * 0.37));
			for (int k = 1; k < steps; k++) {
				const double s = double(k) / (steps - 1);
				const double ramp = Math::clamp(s * 3.0, 0.0, 1.0) * (0.6 + 0.4 * s);
				const double wave_amp = wave * 0.017 * ramp * s;
				points[size_t(k)] += frame_side[size_t(k)] * real_t(wave_amp * std::sin(wave_phase + s * 6.2831853 * wave_rate * 2.2)) + frame_up[size_t(k)] * real_t(wave_amp * 0.5 * std::cos(wave_phase * 1.3 + s * 6.2831853 * wave_rate * 1.7));
			}
		}
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
			const double width = strands > 0 ? strand_width * (1.0 + 0.5 * Math::clamp((length - 0.08) / 0.2, 0.0, 1.0)) * (1.0 - 0.85 * std::pow(s, 1.4)) : lock_width * (1.0 - 0.9 * std::pow(s, 1.6)) * (0.75 + 0.25 * std::min(1.0, s * 6.0));
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
		} // (one hair, or one ribbon)
	}
	if (guides_only) {
		const double reach = 0.012; // a scalp spot is covered by the hair whose guide points are within this distance, up to 1.5 cm above it
		const double shell = 0.015;
		std::unordered_map<int64_t, std::vector<int>> point_cells;
		for (int i = 0; i < int(cover_points.size()); i++) {
			const Vector3 &g = cover_points[size_t(i)];
			point_cells[cell_key(int(std::floor(double(g.x) / reach)), int(std::floor(double(g.y) / reach)), int(std::floor(double(g.z) / reach)))].push_back(i);
		}
		struct Spot {
			int t;
			double u, w;
			Vector3 position, normal;
			int count;
		};
		std::vector<Spot> spots;
		const int spot_count = 9000;
		for (int k = 0; k < spot_count; k++) {
			Dice sd(seed + 0xC0FEULL + uint64_t(k) * 0x9E3779B97F4A7C15ULL);
			const double pick = sd.unit() * total_area;
			const int tri = int(std::lower_bound(cumulative_area.begin(), cumulative_area.end(), pick) - cumulative_area.begin());
			const int t = scalp_triangles[std::min(tri, int(scalp_triangles.size()) - 1)];
			double u = sd.unit(), w = sd.unit();
			if (u + w > 1.0) {
				u = 1.0 - u;
				w = 1.0 - w;
			}
			const int a = indices[t], b = indices[t + 1], c = indices[t + 2];
			const double aw = 1.0 - u - w;
			const Vector3 position = vertices[a] * real_t(aw) + vertices[b] * real_t(u) + vertices[c] * real_t(w);
			if (double(position.y) - hairline(position) <= 0.012) {
				continue; // (the hairline edge has its own roots)
			}
			const Vector3 normal = (normals[a] * real_t(aw) + normals[b] * real_t(u) + normals[c] * real_t(w)).normalized();
			int count = 0;
			const int cx = int(std::floor(double(position.x) / reach)), cy = int(std::floor(double(position.y) / reach)), cz = int(std::floor(double(position.z) / reach));
			for (int dx = -1; dx <= 1; dx++) {
				for (int dy = -1; dy <= 1; dy++) {
					for (int dz = -1; dz <= 1; dz++) {
						auto it = point_cells.find(cell_key(cx + dx, cy + dy, cz + dz));
						if (it == point_cells.end()) {
							continue;
						}
						for (int index : it->second) {
							const Vector3 d = cover_points[size_t(index)] - position;
							const double height = double(d.dot(normal));
							if (double(d.length()) < reach && height > -0.002 && height < shell) {
								count++;
							}
						}
					}
				}
			}
			spots.push_back({ t, u, w, position, normal, count });
		}
		if (!spots.empty()) {
			std::vector<int> sorted_counts;
			for (const Spot &sp : spots) {
				sorted_counts.push_back(sp.count);
			}
			std::nth_element(sorted_counts.begin(), sorted_counts.begin() + sorted_counts.size() / 2, sorted_counts.end());
			const double median = double(sorted_counts[sorted_counts.size() / 2]);
			const double wanted = (0.3 + 0.4 * cover) * median;
			std::vector<Vector3> taken;
			const size_t fill_cap = size_t(std::max(1, lock_count / 3));
			for (const Spot &sp : spots) {
				if (double(sp.count) >= wanted || fills.size() >= fill_cap) {
					continue;
				}
				bool near_taken = false;
				for (const Vector3 &q : taken) {
					if ((q - sp.position).length() < real_t(reach * 0.6)) {
						near_taken = true;
						break;
					}
				}
				if (near_taken) {
					continue;
				}
				taken.push_back(sp.position);
				const int add = Math::clamp(int(std::ceil((wanted - double(sp.count)) / 3.0)), 1, 3);
				fills.push_back({ sp.t, sp.u, sp.w });
				for (int extra = 1; extra < add; extra++) {
					Dice jd(seed + 0xF111ULL + uint64_t(fills.size()) * 0x2545F4914F6CDD1DULL);
					double u2 = std::clamp(sp.u + jd.range(-0.15, 0.15), 0.0, 1.0), w2 = std::clamp(sp.w + jd.range(-0.15, 0.15), 0.0, 1.0);
					if (u2 + w2 > 1.0) {
						const double scale = 1.0 / (u2 + w2);
						u2 *= scale;
						w2 *= scale;
					}
					fills.push_back({ sp.t, u2, w2 });
				}
			}
			fill_count = int(fills.size());
			if (cover_debug) {
				int below = 0;
				for (const Spot &sp : spots) {
					below += double(sp.count) < wanted ? 1 : 0;
				}
				godot::UtilityFunctions::print("HUMAN_COVER spots ", int(spots.size()), " median ", median, " wanted ", wanted, " below ", below, " fills ", fill_count);
			}
		}
	}
	} // (the passes)

	lap("locks done");
	const auto beard_clock_start = std::chrono::steady_clock::now();
	const int vertices_before_beard = int(out_vertices.size());
	// --- the beard: short single hairs on the lower face (static: they do not simulate), from follicles spread by area over the jaw, chin and cheeks, growing down and out along the skin
	if (beard > 0.0) {
		const double face_scale = Math::clamp(half_width / 0.0883, 0.85, 1.15); // (the face features sit at distances from the eye line that go with the size of the head: the numbers below are for the male body)
		std::vector<int> beard_triangles;
		std::vector<double> beard_area;
		double beard_total = 0.0;
		// the neckline: the beard stops at a line under the jaw that rises from the chin toward the neck (real beards end above the Adam's apple, the neck below is clean)
		auto beard_floor = [&](double z) {
			return -0.135 + 0.05 * Math::clamp(((z_front - 0.035) - z) / 0.07, 0.0, 1.0);
		};
		auto in_beard_region = [&](const Vector3 &c, const Vector3 &n) {
			const double dy = (double(c.y) - eye_y) / face_scale;
			const double ax = std::abs(double(c.x));
			if (double(c.z) < centre_z - 0.05 * half_width) {
				return false; // (the front of the head only; the sideburns belong to the scalp hair)
			}
			const double upper = -0.047 + 0.042 * Math::clamp((ax - 0.03) / 0.04, 0.0, 1.0); // the cheek line rises toward the ears
			if (dy > upper || dy < beard_floor(double(c.z)) || ax > half_width * 0.98) {
				return false;
			}
			if (n.z < -0.3f && n.y > -0.3f) {
				return false; // (facing away: the side of the neck)
			}
			if (goatee) {
				const bool moustache_band = ax < 0.034 && dy > -0.075 && dy < -0.044;
				const bool chin_patch = ax < 0.014 + 0.006 * Math::clamp((-0.085 - dy) / 0.03, 0.0, 1.0) && dy < -0.078;
				if (!moustache_band && !chin_patch) {
					return false; // (a goatee: no cheeks, no jaw line)
				}
			}
			const double lip_x = ax / 0.03, lip_y = (dy + 0.072) / 0.011; // (lips; the band between nose and lips gets the moustache)
			if (lip_x * lip_x + lip_y * lip_y < 1.0) {
				return false; // (the mouth: no hair on the lips)
			}
			return true;
		};
		for (int t = 0; t + 2 < index_count; t += 3) {
			const int a = indices[t], b = indices[t + 1], c = indices[t + 2];
			const Vector3 centre = (vertices[a] + vertices[b] + vertices[c]) / 3.0f;
			const Vector3 n = (normals[a] + normals[b] + normals[c]).normalized();
			if (in_beard_region(centre, n)) {
				beard_total += 0.5 * (vertices[b] - vertices[a]).cross(vertices[c] - vertices[a]).length();
				beard_triangles.push_back(t);
				beard_area.push_back(beard_total);
			}
		}
		if (cover_debug) {
			godot::UtilityFunctions::print("HUMAN_BEARD half_width ", half_width, " eye_drop ", top_y - eye_y, " head height ", top_y, " z_front ", z_front, " centre_z ", centre_z);
		}
		if (!beard_triangles.empty()) {
			current_guide = -1; // (static hairs)
			int beard_hair_total = 0;
			// (no flat layer under the beard: a dim dot around each follicle instead, below)
			const int follicles = int(24000.0 * beard);
			const int beard_steps = 3;
			for (int f = 0; f < follicles; f++) {
				Dice dice(seed + 0xBEA2DULL + uint64_t(f) * 0x2545F4914F6CDD1DULL);
				const double pick = dice.unit() * beard_total;
				const int tri = int(std::lower_bound(beard_area.begin(), beard_area.end(), pick) - beard_area.begin());
				const int t = beard_triangles[std::min(tri, int(beard_triangles.size()) - 1)];
				const int ia = indices[t], ib = indices[t + 1], ic = indices[t + 2];
				double u = dice.unit(), w = dice.unit();
				if (u + w > 1.0) {
					u = 1.0 - u;
					w = 1.0 - w;
				}
				const double aw = 1.0 - u - w;
				const Vector3 root = vertices[ia] * real_t(aw) + vertices[ib] * real_t(u) + vertices[ic] * real_t(w);
				const Vector3 normal = (normals[ia] * real_t(aw) + normals[ib] * real_t(u) + normals[ic] * real_t(w)).normalized();
				int bound = ia;
				if (u >= aw && u >= w) {
					bound = ib;
				} else if (w >= aw && w >= u) {
					bound = ic;
				}
				const double dy = (double(root.y) - eye_y) / face_scale;
				const double upper_edge = -0.047 + 0.042 * Math::clamp((std::abs(double(root.x)) - 0.03) / 0.04, 0.0, 1.0);
				const bool in_moustache = std::abs(double(root.x)) < 0.04 && dy > -0.075 && dy < -0.044; // (the band between the nose and the lips)
				const double edge_plain = std::min(std::min(Math::clamp((upper_edge - dy) / 0.014, 0.0, 1.0), Math::clamp((dy - beard_floor(double(root.z))) / 0.05, 0.3, 1.0)), Math::clamp((double(root.z) - (centre_z - 0.05 * half_width)) / 0.06, 0.15, 1.0)); // (a soft edge along the cheek line above, the jaw below and toward the ear) // (the cheek line: shorter and thinner right at the edge)
				const double edge = in_moustache ? std::max(edge_plain, 0.95 * Math::clamp((upper_edge - dy) / 0.012, 0.0, 1.0)) : edge_plain; // (the moustache is full right up to the nose, not faded like the cheek line)
				if (dice.unit() > 0.2 + 0.8 * edge * edge) {
					continue;
				}
				{
					// a dim dot of hair colour on the skin around this follicle (about 2 mm): the shadow of the roots, so the skin between the hairs is not pale but the paint is only where there are hairs
					Vector3 axis_u = normal.cross(Vector3(0.0f, 1.0f, 0.0f));
					if (axis_u.length() < 1e-3f) {
						axis_u = Vector3(1.0f, 0.0f, 0.0f);
					}
					axis_u = axis_u.normalized();
					const Vector3 axis_v = normal.cross(axis_u).normalized();
					const double turn = dice.range(0.0, 6.2831853);
					const real_t dot_radius = real_t(0.0016 * dice.range(0.8, 1.3));
					const Vector3 ring_u = (axis_u * real_t(std::cos(turn)) + axis_v * real_t(std::sin(turn))) * dot_radius;
					const Vector3 ring_v = (axis_v * real_t(std::cos(turn)) - axis_u * real_t(std::sin(turn))) * dot_radius;
					const Color dot_colour(0.5f, 0.0f, 1.0f, float(0.5 + 0.018 * edge)); // (the cap shader turns this into a low, mottled opacity)
					const Vector3 dot_centre = root + normal * 0.0012f;
					const int d0 = add_vertex(dot_centre - ring_u - ring_v, normal, Vector2(0.5f, 0.5f), dot_colour, bound, cap_tangent(normal), 0.0f, true);
					const int d1 = add_vertex(dot_centre + ring_u - ring_v, normal, Vector2(0.5f, 0.5f), dot_colour, bound, cap_tangent(normal), 0.0f, true);
					const int d2 = add_vertex(dot_centre + ring_u + ring_v, normal, Vector2(0.5f, 0.5f), dot_colour, bound, cap_tangent(normal), 0.0f, true);
					const int d3 = add_vertex(dot_centre - ring_u + ring_v, normal, Vector2(0.5f, 0.5f), dot_colour, bound, cap_tangent(normal), 0.0f, true);
					out_indices.push_back(d0);
					out_indices.push_back(d1);
					out_indices.push_back(d2);
					out_indices.push_back(d0);
					out_indices.push_back(d2);
					out_indices.push_back(d3);
				}
				const double below_lip = Math::clamp(((dy + 0.072) / 0.011 + 1.0) / 1.6, 0.0, 1.0); // (0 at the lower lip, 1 about 1.8 cm under it: right under the lip the hairs are short, they would lie across the mouth)
				const double hair_length = beard_length * dice.range(0.5, 1.6) * (0.5 + 0.5 * edge) * (0.45 + 0.55 * below_lip) * (in_moustache ? 1.0 : 1.0);
				// the growth direction (a field over the face): on the cheeks down and a little back toward the ear, under the jaw down and forward toward the chin, on the chin down and out,
				// on the moustache band outward from the middle (and down); each follicle's hairs fan out a little. The field is projected onto the skin.
				const double ax_root = std::abs(double(root.x));
				const double side = root.x >= 0.0f ? 1.0 : -1.0;
				Vector3 want(0.0f, -1.0f, 0.0f);
				if (dy > -0.047 - 0.022 && dy < -0.047 + 0.003 && ax_root < 0.04) {
					want = Vector3(real_t(side * 0.9), -0.12f, 0.05f); // (the moustache: out from the middle and only a little down, so it does not hang over the lips)
				} else if (normal.y < -0.35f) {
					want = Vector3(real_t(side * 0.1), -0.25f, 1.0f); // (under the jaw: toward the chin)
				} else if (ax_root < 0.022 && dy < -0.09) {
					want = Vector3(real_t(side * 0.25), -1.0f, 0.35f); // (the chin: down and a little forward and out)
				} else {
					want = Vector3(real_t(side * 0.2), -1.0f, -0.35f); // (the cheeks: down, a little back and out)
				}
				Vector3 along = want - normal * real_t(want.dot(normal));
				if (along.length() < 0.2f) {
					along = Vector3(real_t(root.x >= 0.0f ? 1.0f : -1.0f), 0.0f, 0.0f) - normal * real_t(normal.x);
				}
				const Vector3 direction = (along.normalized() * 0.9f + normal * 0.25f + Vector3(real_t(dice.range(-0.18, 0.18)), real_t(dice.range(-0.1, 0.1)), real_t(dice.range(-0.18, 0.18)))).normalized();
				const int hairs = in_moustache ? 9 : 6;
				for (int h = 0; h < hairs; h++) {
					beard_hair_total++;
					std::vector<Vector3> bp;
					Vector3 position = root + normal * 0.0008f + Vector3(real_t(dice.range(-0.0012, 0.0012)), real_t(dice.range(-0.0012, 0.0012)), real_t(dice.range(-0.0012, 0.0012)));
					Vector3 dir = (direction + Vector3(real_t(dice.range(-0.6, 0.6)), real_t(dice.range(-0.3, 0.3)), real_t(dice.range(-0.6, 0.6)))).normalized();
					bp.push_back(position);
					const double seg = hair_length * dice.range(0.8, 1.15) / (beard_steps - 1);
					for (int k = 1; k < beard_steps; k++) {
						dir = (dir * 0.7f + Vector3(0.0f, in_moustache ? -0.06f : -0.2f, 0.0f) + Vector3(real_t(dice.range(-0.3, 0.3)), real_t(dice.range(-0.1, 0.1)), real_t(dice.range(-0.3, 0.3)))).normalized();
						position += dir * real_t(seg);
						grid.push_out(position, 0.0010);
						bp.push_back(position);
					}
					// a curl: the middle and the tip of the hair bend sideways (to one side, by an amount of its own), so the hairs are not straight combed strands
					{
						Vector3 bend = normal.cross((bp[size_t(beard_steps - 1)] - bp[0]).normalized());
						if (bend.length() > 1e-3f) {
							bend = bend.normalized();
							const double lean = hair_length * dice.range(-0.45, 0.45);
							bp[1] += bend * real_t(lean);
							bp[size_t(beard_steps - 1)] += bend * real_t(lean * dice.range(-0.4, 1.2));
						}
					}
					// no hair may lie across the mouth gap: a point of the hair inside the lip ellipse (made a little larger) pulls the whole hair back toward its root
					for (int pass = 0; pass < 3; pass++) {
						bool across = false;
						for (int k = 1; k < beard_steps; k++) {
							const double pdy = (double(bp[size_t(k)].y) - eye_y) / face_scale;
							const double qx = std::abs(double(bp[size_t(k)].x)) / 0.034, qy = (pdy + 0.072) / 0.0135;
							if (qx * qx + qy * qy < 1.0 && double(bp[size_t(k)].z) > centre_z + 0.5 * half_width) {
								across = true;
							}
						}
						if (!across) {
							break;
						}
						for (int k = 1; k < beard_steps; k++) {
							bp[size_t(k)] = bp[0] + (bp[size_t(k)] - bp[0]) * 0.55f;
						}
					}
					const float brightness = float(dice.unit());
					const float chance = float(dice.unit());
					const int first = int(out_vertices.size());
					for (int k = 0; k < beard_steps; k++) {
						const double sv = double(k) / (beard_steps - 1);
						const Vector3 tangent = (bp[size_t(std::min(k + 1, beard_steps - 1))] - bp[size_t(std::max(k - 1, 0))]).normalized();
						Vector3 side = tangent.cross(normal);
						if (side.length() < 1e-5f) {
							side = Vector3(1.0f, 0.0f, 0.0f);
						}
						side = side.normalized();
						const Vector3 face = side.cross(tangent).normalized();
						const double width = std::min(strand_width, 0.0004) * 0.7 * (1.0 - 0.5 * std::pow(sv, 1.6));   // (a rounder tip: a beard hair is blunt where it was cut)
						const Color color(brightness, chance, 0.3f, 1.0f); // (blue 0.3 marks a beard hair for the shader: depth shading, clumps)
						add_vertex(bp[size_t(k)] - side * real_t(width * 0.5), face, Vector2(0.0f, float(sv)), color, bound, tangent, float(sv), false);
						add_vertex(bp[size_t(k)] + side * real_t(width * 0.5), face, Vector2(1.0f, float(sv)), color, bound, tangent, float(sv), false);
					}
					for (int k = 0; k + 1 < beard_steps; k++) {
						const int l0 = first + 2 * k, r0 = l0 + 1, l1 = l0 + 2, r1 = l0 + 3;
						out_indices.push_back(l0);
						out_indices.push_back(r0);
						out_indices.push_back(r1);
						out_indices.push_back(l0);
						out_indices.push_back(r1);
						out_indices.push_back(l1);
					}
				}
			}
			if (cover_debug) {
				godot::UtilityFunctions::print("HUMAN_BEARD hairs ", beard_hair_total, " triangles ", int(beard_triangles.size()), " area cm2 ", beard_total * 10000.0, " width mm ", std::min(strand_width, 0.0004) * 0.7 * 1000.0);
			}
		}
	}

	const int beard_vertex_count = int(out_vertices.size()) - vertices_before_beard;
	if (cover_debug) {
		godot::UtilityFunctions::print("HUMAN_TIME beard block ms ", std::chrono::duration<double, std::milli>(std::chrono::steady_clock::now() - beard_clock_start).count(), " (vertices so far ", int(out_vertices.size()), ")");
	}
	lap("beard done");
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
		int nearest;
		if (i >= vertices_before_beard && i < vertices_before_beard + beard_vertex_count) {
			// a beard hair is a few mm from the body vertex it was bound to (the nearest to its root): no grid search for these 480,000 vertices (it was most of the beard's build time)
			nearest = out_bound[i];
			distance_squared = double((vertices[nearest] - out_vertices[i]).length_squared());
		} else {
			nearest = near_grid.nearest(out_vertices[i], distance_squared);
		}
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

	lap("blend shapes done");
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
	// CUSTOM0 (4 floats a vertex): x = the guide strand this vertex follows (-1 = none), y = the point along it (0 at the root .. steps - 1 at the tip)
	PackedFloat32Array custom_array;
	custom_array.resize(int64_t(out_count) * 4);
	{
		float *cw = custom_array.ptrw();
		for (int i = 0; i < out_count; i++) {
			cw[i * 4] = out_guide[size_t(i)];
			cw[i * 4 + 1] = out_cap[size_t(i)] != 0 ? 0.0f : out_s[size_t(i)] * float(steps - 1);
			cw[i * 4 + 2] = 0.0f;
			cw[i * 4 + 3] = 0.0f;
		}
	}
	arrays[Mesh::ARRAY_CUSTOM0] = custom_array;
	PackedVector3Array guide_array;
	guide_array.resize(int64_t(guide_rest.size()));
	for (size_t i = 0; i < guide_rest.size(); i++) {
		guide_array[int64_t(i)] = guide_rest[i];
	}
	// how much of each body vertex is scalp (0 at and below the hairline, 1 a little above it): the skin shader darkens the skin there, so a gap in the hair shows a dark scalp, not pale skin
	PackedFloat32Array scalp_weight;
	scalp_weight.resize(vertex_count);
	for (int i = 0; i < vertex_count; i++) {
		float w = 0.0f;
		if (scalp[i]) {
			w = float(Math::clamp((double(vertices[i].y) - hairline(vertices[i])) / 0.025, 0.0, 1.0));
			w = 0.55f + 0.45f * (w * w * (3.0f - 2.0f * w)); // (already half dark at the hairline: hairs there are the most spread out, and the edge row of the scalp is where skin showed)
		}
		scalp_weight[i] = w;
	}
	built["scalp_weight"] = scalp_weight;
	built["beard_vertices"] = beard_vertex_count;
	built["guides"] = guide_array;
	built["guide_count"] = guide_count;
	built["guide_steps"] = steps;
	// Colliders for the hair simulation, in the body's space: capsules (ax, ay, az, bx, by, bz, radius): the head, the neck and the shoulders.
	PackedFloat32Array collider_array;
	auto add_capsule = [&](const Vector3 &a, const Vector3 &b, double r) {
		collider_array.push_back(a.x);
		collider_array.push_back(a.y);
		collider_array.push_back(a.z);
		collider_array.push_back(b.x);
		collider_array.push_back(b.y);
		collider_array.push_back(b.z);
		collider_array.push_back(float(r));
	};
	add_capsule(head_centre + Vector3(0.0f, 0.02f, 0.0f), head_centre + Vector3(0.0f, 0.02f, 0.0f), half_width * 1.02);
	if (neck_count > 20) {
		add_capsule(Vector3(real_t(neck_x), real_t(neck_bottom - 0.05), real_t(neck_z)), Vector3(real_t(neck_x), real_t(neck_top), real_t(neck_z)), neck_radius * 1.02);
	}
	{
		// the shoulders: a horizontal capsule through the band of the body just under the neck (where the shoulders are widest)
		double x_low = 1e9, x_high = -1e9, z_low = 1e9, z_high = -1e9, y_sum = 0.0;
		int band = 0;
		for (int i = 0; i < vertex_count; i++) {
			const Vector3 v = vertices[i];
			if (v.y > top_y - 0.36 && v.y < top_y - 0.26) {
				x_low = std::min(x_low, double(v.x));
				x_high = std::max(x_high, double(v.x));
				z_low = std::min(z_low, double(v.z));
				z_high = std::max(z_high, double(v.z));
				y_sum += v.y;
				band++;
			}
		}
		if (band > 50) {
			const double r = Math::clamp((z_high - z_low) * 0.42, 0.035, 0.09);
			const double y = y_sum / band;
			const double z = 0.5 * (z_low + z_high);
			add_capsule(Vector3(real_t(x_low + r), real_t(y), real_t(z)), Vector3(real_t(x_high - r), real_t(y), real_t(z)), r);
		}
	}
	built["colliders"] = collider_array;
	// The body surface under the head (points and normals), for the hair simulation: hair must not go through the chest, breasts or arms either.
	{
		PackedVector3Array surface_points, surface_normals;
		for (int i = 0; i < vertex_count; i++) {
			if (vertices[i].y > top_y - 0.75) {
				surface_points.push_back(vertices[i]);
				surface_normals.push_back(normals[i]);
			}
		}
		built["surface_points"] = surface_points;
		built["surface_normals"] = surface_normals;
	}
	built["arrays"] = arrays;
	built["blend_arrays"] = blend_arrays;
	built["blend_names"] = blend_names;
	lap("arrays done");
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
	const uint64_t flags = uint64_t(Mesh::ARRAY_CUSTOM_RGBA_FLOAT) << Mesh::ARRAY_FORMAT_CUSTOM0_SHIFT;
	result->add_surface_from_arrays(Mesh::PRIMITIVE_TRIANGLES, arrays, blend_arrays, Dictionary(), flags);
	// what a hair simulation needs, kept with the mesh
	if (p_built.has("guides")) {
		result->set_meta("hair_guides", p_built["guides"]);
		result->set_meta("hair_scalp_weight", p_built["scalp_weight"]);
		result->set_meta("hair_beard_vertices", p_built.get("beard_vertices", 0));
		result->set_meta("hair_guide_count", p_built["guide_count"]);
		result->set_meta("hair_guide_steps", p_built["guide_steps"]);
		result->set_meta("hair_colliders", p_built["colliders"]);
		result->set_meta("hair_surface_points", p_built["surface_points"]);
		result->set_meta("hair_surface_normals", p_built["surface_normals"]);
	}
	return result;
}

Ref<ArrayMesh> HumanHair::build(const Ref<ArrayMesh> &p_body, const Dictionary &p_params) {
	return make_mesh(build_arrays(prepare(p_body), p_params));
}

} // namespace godot
