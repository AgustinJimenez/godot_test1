#include "human_body_hair_native.h"

#include "human_hair_native.h"

#include <godot_cpp/classes/mesh.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/core/math.hpp>
#include <godot_cpp/variant/packed_color_array.hpp>
#include <godot_cpp/variant/packed_float32_array.hpp>
#include <godot_cpp/variant/packed_int32_array.hpp>
#include <godot_cpp/variant/packed_string_array.hpp>
#include <godot_cpp/variant/packed_vector2_array.hpp>
#include <godot_cpp/variant/packed_vector3_array.hpp>

#include <algorithm>
#include <array>
#include <cmath>
#include <cstdint>
#include <vector>

namespace godot {

namespace {

// a small deterministic random stream (splitmix64), one per follicle so a hair does not change when another area's amount does
struct BodyDice {
	uint64_t state;
	explicit BodyDice(uint64_t p_seed) :
			state(p_seed * 0x9E3779B97F4A7C15ULL + 0x632BE59BD9B4E019ULL) {}
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

double read(const Dictionary &p_params, const char *p_key, double p_default) {
	const Variant value = p_params.get(p_key, p_default);
	const Variant::Type type = value.get_type();
	return (type == Variant::FLOAT || type == Variant::INT) ? double(value) : p_default;
}

// the areas (the order of AREA_NAMES); NONE grows no hair (head, neck, hands, feet, the groin and the joints' tops)
enum BodyArea { AREA_CHEST, AREA_BELLY, AREA_BACK, AREA_UPPER_ARM, AREA_FOREARM, AREA_THIGH, AREA_SHIN, AREA_ARMPIT, AREA_COUNT, AREA_NONE = -1 };
const char *const AREA_NAMES[AREA_COUNT] = { "chest", "belly", "back", "upper_arm", "forearm", "thigh", "shin", "armpit" };
// hairs per square metre at full amount (terminal hair on a hairy man: about 10-15 a square centimetre on the chest and the forearms, a dense tuft in the armpit)
// (the upper arm: terminal hair "rarely" grows there, Wikipedia "Body hair"; it is mostly fine hair near the elbow)
const double AREA_DENSITY[AREA_COUNT] = { 110000.0, 60000.0, 25000.0, 10000.0, 90000.0, 40000.0, 80000.0, 300000.0 };
// the length of each area's hairs as a share of the length setting (the chest's)
const double AREA_LENGTH[AREA_COUNT] = { 1.0, 0.9, 0.8, 0.6, 0.75, 0.65, 0.8, 1.6 };
// how much of the curl setting each area takes (chest and armpit hair coils, limb hair lies straighter)
const double AREA_CURL[AREA_COUNT] = { 1.0, 0.8, 0.6, 0.4, 0.35, 0.4, 0.35, 1.3 };

struct Limb {
	Vector3 a, b;   // from the joint near the body to the far one
	double radius;
	double start;   // the share of the line, from a, where the hair starts (the top of the shoulder, the groin)
	double end;     // where it ends (before the wrist, the ankle)
	BodyArea area;
};

struct Frame {
	bool has_torso = false;
	std::vector<Limb> limbs;
	double neck_y = 0.0, hips_y = 0.0, nipple_y = 0.0, nipple_x = 0.1, shoulder_x = 0.18;
	double spread = 0.0;   // the amount (0..1): a hairier man's hair spreads further (the areas below grow outward from where hair starts), not only thicker
	double node_y = 0.0;   // the chest's parting on the upper breastbone: the hair above it grows up, below it down (Wikipedia "Chest hair")
	double navel_y = 0.0;
	Vector3 armpit[2];
	bool has_armpits = false;
};

struct AreaHit {
	BodyArea area = AREA_NONE;
	double share = 0.0;   // 0..1: the density inside the area (falls off at its edges)
	Vector3 along;        // the limb's direction (a to b) for the limbs
	double side = 1.0;    // +1 on the body's left (+X), -1 on its right
};

double smooth(double p_edge0, double p_edge1, double p_x) {
	const double t = Math::clamp((p_x - p_edge0) / (p_edge1 - p_edge0), 0.0, 1.0);
	return t * t * (3.0 - 2.0 * t);
}

AreaHit area_at(const Frame &p_frame, const Vector3 &p_point, const Vector3 &p_normal) {
	AreaHit hit;
	hit.side = p_point.x >= 0.0f ? 1.0 : -1.0;
	if (p_frame.has_armpits) {
		for (int s = 0; s < 2; s++) {
			const double d = double(p_point.distance_to(p_frame.armpit[s]));
			if (d < 0.05) {
				hit.area = AREA_ARMPIT;
				hit.share = 1.0 - smooth(0.025, 0.05, d);
				return hit;
			}
		}
	}
	// the limbs: the band round each limb's line (the nearest line within its radius)
	double best = 1e9;
	const Limb *best_limb = nullptr;
	double best_t = 0.0;
	for (const Limb &limb : p_frame.limbs) {
		const Vector3 axis = limb.b - limb.a;
		const double length_squared = double(axis.length_squared());
		if (length_squared < 1e-6) {
			continue;
		}
		const double t = double((p_point - limb.a).dot(axis)) / length_squared;
		if (t < -0.1 || t > 1.1) {
			continue;
		}
		const Vector3 closest = limb.a + axis * real_t(Math::clamp(t, 0.0, 1.0));
		const double d = double(p_point.distance_to(closest)) / limb.radius;
		if (d < 1.0 && d < best) {
			best = d;
			best_limb = &limb;
			best_t = t;
		}
	}
	if (best_limb != nullptr) {
		if (best_t < best_limb->start || best_t > best_limb->end) {
			return hit; // (the shoulder's top, the groin, the hand, the foot)
		}
		hit.area = best_limb->area;
		hit.along = (best_limb->b - best_limb->a).normalized();
		hit.share = smooth(best_limb->start, best_limb->start + 0.12, best_t) * (1.0 - smooth(best_limb->end - 0.1, best_limb->end, best_t));
		if (hit.area == AREA_THIGH) {
			// the inner thigh has little hair; the front and the outside more
			const double inner = Math::clamp(-hit.side * double(p_normal.x), 0.0, 1.0);
			hit.share *= 1.0 - 0.7 * inner;
		}
		if (hit.area == AREA_FOREARM || hit.area == AREA_UPPER_ARM) {
			// the inside of the arm (toward the body in the rest pose) has less hair than the back of the forearm
			const double inner = Math::clamp(-hit.side * double(p_normal.x), 0.0, 1.0);
			hit.share *= 1.0 - 0.6 * inner;
		}
		if (hit.area == AREA_FOREARM) {
			hit.share *= 0.35 + 0.65 * smooth(0.15, 0.85, best_t); // (terminal forearm hair is concentrated at the wrist end, Wikipedia "Body hair")
		}
		if (hit.area == AREA_UPPER_ARM) {
			hit.share *= 0.3 + 0.7 * smooth(0.4, 1.0, best_t);   // (what there is sits toward the elbow)
		}
		if (hit.area == AREA_SHIN) {
			hit.share *= 0.6 + 0.4 * smooth(0.05, 0.4, best_t);  // (the knee itself is thinner than the shin below it)
		}
		return hit;
	}
	if (!p_frame.has_torso) {
		return hit;
	}
	const double y = double(p_point.y);
	const double ax = std::abs(double(p_point.x));
	if (y > p_frame.neck_y - 0.06 || y < p_frame.hips_y - 0.1 || ax > p_frame.shoulder_x * 1.05) {
		return hit; // (the neck and the head, below the pubis, the hands and the arms beyond the shoulders)
	}
	if (p_normal.z > 0.15f) {
		const double chest_low = p_frame.nipple_y - 0.1;
		const double spread = p_frame.spread;
		if (y > chest_low) {
			// the chest, after the four areas of Setty's study of 1,400 men (Wikipedia "Chest hair"): sternal (the middle of the breastbone, 74% of men),
			// pectoral (the breast, 77%), infraclavicular (just under the inner end of the collar bone, 63%) and circumareolar (a ring round the nipple,
			// 16%); the most common pattern has the first three (57%). Hair starts on the breastbone and round the nipples and spreads over the breast
			// and up under the collar bones as the man is hairier: the amount widens the areas.
			hit.area = AREA_CHEST;
			const double sternal = 1.0 - smooth(0.02, 0.045, ax);
			double areola = 0.0;
			if (p_frame.nipple_x > 0.0) {
				const double dx = ax - p_frame.nipple_x, dy = y - p_frame.nipple_y;
				areola = 0.8 * (1.0 - smooth(0.025, 0.05, std::sqrt(dx * dx + dy * dy)));
			}
			const double across = ax / (p_frame.nipple_x + 0.07);
			const double reach = 0.3 + 0.45 * spread;   // (how far out over the breast it has spread)
			double pectoral = (1.0 - smooth(reach, reach + 0.35, across)) * smooth(0.0, 0.45, spread);
			// above the nipples only the inner part goes on up to the collar bones (the infraclavicular area), and only on hairier men
			const double upper = smooth(p_frame.nipple_y + 0.04, p_frame.nipple_y + 0.11, y);
			pectoral *= 1.0 - upper * (1.0 - (1.0 - smooth(0.05, 0.1, ax)) * smooth(0.25, 0.65, spread));
			hit.share = std::max(std::max(sternal * smooth(chest_low - 0.02, chest_low + 0.02, y), areola), pectoral * smooth(chest_low, chest_low + 0.04, y));
			hit.share *= 1.0 - smooth(p_frame.neck_y - 0.13, p_frame.neck_y - 0.06, y);
			return hit;
		}
		// the belly: the line from the chest past the navel to the pubis (the "happy trail"; thin above the navel, widening below it), and on a hairy
		// man the belly round it filling in from the line outward
		hit.area = AREA_BELLY;
		const double below_navel = smooth(p_frame.navel_y, p_frame.navel_y - 0.08, y);
		const double line_width = 0.012 + 0.025 * below_navel;
		const double line = (1.0 - smooth(line_width, line_width + 0.02, ax)) * (0.55 + 0.45 * below_navel + 0.3 * spread);
		const double broad = smooth(0.4, 1.0, spread) * (0.15 + 0.25 * below_navel) * (1.0 - smooth(0.04, 0.07 + 0.05 * spread, ax));
		hit.share = Math::clamp(std::max(line, broad), 0.0, 1.0);
		return hit;
	}
	if (p_normal.z < -0.15f && y > p_frame.hips_y + 0.03) {
		// the back: the shoulders and the upper back more than the lower back
		hit.area = AREA_BACK;
		hit.share = 0.35 + 0.65 * smooth(p_frame.hips_y + 0.1, p_frame.neck_y - 0.12, y);
		return hit;
	}
	return hit;
}

} // namespace

void HumanBodyHair::_bind_methods() {
	ClassDB::bind_static_method("HumanBodyHair", D_METHOD("build_arrays", "body_data", "params"), &HumanBodyHair::build_arrays);
	ClassDB::bind_static_method("HumanBodyHair", D_METHOD("default_params"), &HumanBodyHair::default_params);
}

Dictionary HumanBodyHair::default_params() {
	Dictionary d;
	d["seed"] = 1;
	d["amount"] = 0.0;
	d["chest"] = 1.0;
	d["belly"] = 1.0;
	d["back"] = 0.3;
	d["arms"] = 1.0;
	d["legs"] = 1.0;
	d["armpits"] = 1.0;
	d["length"] = 0.012;
	d["curl"] = 0.4;
	d["max_hairs"] = 60000;
	return d;
}

Dictionary HumanBodyHair::build_arrays(const Ref<HumanHairBody> &p_body, const Dictionary &p_params) {
	Dictionary built;
	if (p_body.is_null() || !p_body->is_valid()) {
		return built;
	}
	const std::vector<Vector3> &vertices = p_body->vertices;
	const std::vector<Vector3> &normals = p_body->normals;
	const std::vector<int32_t> &indices = p_body->indices;
	const int vertex_count = int(vertices.size());
	const int index_count = int(indices.size());

	const uint64_t seed = uint64_t(int64_t(read(p_params, "seed", 1.0)));
	const double amount = Math::clamp(read(p_params, "amount", 0.0), 0.0, 1.0);
	const double length = Math::clamp(read(p_params, "length", 0.012), 0.001, 0.06);
	const double curl = Math::clamp(read(p_params, "curl", 0.4), 0.0, 1.0);
	const int max_hairs = int(Math::clamp(read(p_params, "max_hairs", 60000.0), 0.0, 200000.0));
	double area_amount[AREA_COUNT];
	area_amount[AREA_CHEST] = Math::clamp(read(p_params, "chest", 1.0), 0.0, 1.0);
	area_amount[AREA_BELLY] = Math::clamp(read(p_params, "belly", 1.0), 0.0, 1.0);
	area_amount[AREA_BACK] = Math::clamp(read(p_params, "back", 0.3), 0.0, 1.0);
	area_amount[AREA_UPPER_ARM] = area_amount[AREA_FOREARM] = Math::clamp(read(p_params, "arms", 1.0), 0.0, 1.0);
	area_amount[AREA_THIGH] = area_amount[AREA_SHIN] = Math::clamp(read(p_params, "legs", 1.0), 0.0, 1.0);
	area_amount[AREA_ARMPIT] = Math::clamp(read(p_params, "armpits", 1.0), 0.0, 1.0);

	// --- the frame from the joints
	Frame frame;
	const Dictionary joints = p_params.get("joints", Dictionary());
	auto joint = [&](const char *p_name, Vector3 &r_out) {
		const Variant v = joints.get(p_name, Variant());
		if (v.get_type() != Variant::VECTOR3) {
			return false;
		}
		r_out = v;
		return true;
	};
	for (int s = 0; s < 2; s++) {
		const char *suffix = s == 0 ? "_l" : "_r";
		Vector3 shoulder, elbow, wrist, hip, knee, ankle;
		const String sh = String("shoulder") + suffix, el = String("elbow") + suffix, wr = String("wrist") + suffix;
		const String hp = String("hip") + suffix, kn = String("knee") + suffix, an = String("ankle") + suffix;
		const bool arm = joint(sh.utf8().get_data(), shoulder) && joint(el.utf8().get_data(), elbow) && joint(wr.utf8().get_data(), wrist);
		if (arm) {
			frame.limbs.push_back({ shoulder, elbow, 0.075, 0.22, 1.0, AREA_UPPER_ARM });
			frame.limbs.push_back({ elbow, wrist, 0.06, 0.0, 0.97, AREA_FOREARM });
			frame.shoulder_x = std::max(frame.shoulder_x, std::abs(double(shoulder.x)) * 0.95);
			// the armpit: under the shoulder joint, a little in toward the body and back
			frame.armpit[s] = shoulder + Vector3(real_t(-0.025 * (shoulder.x >= 0.0f ? 1.0 : -1.0)), -0.075f, -0.01f);
			frame.has_armpits = true;
		}
		if (joint(hp.utf8().get_data(), hip) && joint(kn.utf8().get_data(), knee) && joint(an.utf8().get_data(), ankle)) {
			frame.limbs.push_back({ hip, knee, 0.12, 0.2, 1.0, AREA_THIGH });
			frame.limbs.push_back({ knee, ankle, 0.085, 0.05, 0.92, AREA_SHIN });
		}
	}
	Vector3 neck, hips, nipple_l, nipple_r;
	if (joint("neck", neck) && joint("hips", hips)) {
		frame.has_torso = true;
		frame.neck_y = double(neck.y);
		frame.hips_y = double(hips.y);
		if (joint("nipple_l", nipple_l) && joint("nipple_r", nipple_r)) {
			frame.nipple_y = 0.5 * double(nipple_l.y + nipple_r.y);
			frame.nipple_x = 0.5 * (std::abs(double(nipple_l.x)) + std::abs(double(nipple_r.x)));
		} else {
			frame.nipple_y = frame.hips_y + 0.62 * (frame.neck_y - frame.hips_y);
		}
		frame.node_y = frame.nipple_y + 0.5 * (frame.neck_y - 0.06 - frame.nipple_y);
		frame.navel_y = frame.hips_y + 0.1;
	}
	frame.spread = amount;

	// --- the area and its density at every body vertex, blurred over the mesh a little (a soft edge that follows the surface)
	std::vector<int8_t> vertex_area(static_cast<size_t>(vertex_count), static_cast<int8_t>(AREA_NONE));
	std::vector<float> vertex_density(static_cast<size_t>(vertex_count), 0.0f);
	std::vector<Vector3> vertex_along(static_cast<size_t>(vertex_count));
	for (int i = 0; i < vertex_count; i++) {
		const AreaHit hit = area_at(frame, vertices[size_t(i)], normals[size_t(i)]);
		if (hit.area == AREA_NONE) {
			continue;
		}
		vertex_area[size_t(i)] = int8_t(hit.area);
		vertex_density[size_t(i)] = float(hit.share * AREA_DENSITY[hit.area] * area_amount[hit.area] * amount);
		vertex_along[size_t(i)] = hit.along;
	}
	for (int pass = 0; pass < 2; pass++) {
		std::vector<float> sum(static_cast<size_t>(vertex_count), 0.0f), count(static_cast<size_t>(vertex_count), 0.0f);
		for (int t = 0; t + 2 < index_count; t += 3) {
			for (int e = 0; e < 3; e++) {
				const int from = indices[size_t(t + e)], to = indices[size_t(t + (e + 1) % 3)];
				sum[size_t(from)] += vertex_density[size_t(to)];
				count[size_t(from)] += 1.0f;
				sum[size_t(to)] += vertex_density[size_t(from)];
				count[size_t(to)] += 1.0f;
			}
		}
		for (int i = 0; i < vertex_count; i++) {
			if (count[size_t(i)] > 0.0f) {
				vertex_density[size_t(i)] = 0.5f * vertex_density[size_t(i)] + 0.5f * sum[size_t(i)] / count[size_t(i)];
			}
		}
	}

	// --- the follicles: spread by area x density over the triangles (the count is the expected one, capped at max_hairs)
	std::vector<int> triangles;
	std::vector<double> cumulative;
	double expected = 0.0;
	for (int t = 0; t + 2 < index_count; t += 3) {
		const int a = indices[size_t(t)], b = indices[size_t(t + 1)], c = indices[size_t(t + 2)];
		const double density = (double(vertex_density[size_t(a)]) + double(vertex_density[size_t(b)]) + double(vertex_density[size_t(c)])) / 3.0;
		if (density <= 0.0) {
			continue;
		}
		const double area = 0.5 * double((vertices[size_t(b)] - vertices[size_t(a)]).cross(vertices[size_t(c)] - vertices[size_t(a)]).length());
		expected += area * density;
		triangles.push_back(t);
		cumulative.push_back(expected);
	}
	const int hair_target = std::min(max_hairs, int(std::round(expected)));

	std::vector<Vector3> out_vertices, out_normals, out_tangents;
	std::vector<Vector2> out_uvs;
	std::vector<Color> out_colors;
	std::vector<float> out_s;
	std::vector<int> out_bound;
	std::vector<int32_t> out_indices;
	PackedVector3Array roots;
	int area_hairs[AREA_COUNT] = {};
	const int steps_plain = 4, steps_curly = 6;
	const double width_base = Math::clamp(read(p_params, "width", 0.00034), 0.00005, 0.001);
	for (int f = 0; f < hair_target && !triangles.empty(); f++) {
		BodyDice dice(seed * 0x51A7ULL + uint64_t(f) * 0x2545F4914F6CDD1DULL + 0xB0D1ULL);
		const double pick = dice.unit() * expected;
		const int k = int(std::lower_bound(cumulative.begin(), cumulative.end(), pick) - cumulative.begin());
		const int t = triangles[size_t(std::min(k, int(triangles.size()) - 1))];
		const int ia = indices[size_t(t)], ib = indices[size_t(t + 1)], ic = indices[size_t(t + 2)];
		double u = dice.unit(), w = dice.unit();
		if (u + w > 1.0) {
			u = 1.0 - u;
			w = 1.0 - w;
		}
		const double aw = 1.0 - u - w;
		const Vector3 root = vertices[size_t(ia)] * real_t(aw) + vertices[size_t(ib)] * real_t(u) + vertices[size_t(ic)] * real_t(w);
		const Vector3 normal = (normals[size_t(ia)] * real_t(aw) + normals[size_t(ib)] * real_t(u) + normals[size_t(ic)] * real_t(w)).normalized();
		int bound = ia;
		if (u >= aw && u >= w) {
			bound = ib;
		} else if (w >= aw && w >= u) {
			bound = ic;
		}
		BodyArea area = BodyArea(vertex_area[size_t(bound)]);
		if (area == AREA_NONE) {
			// (the blur reached past the area's last vertex: the nearest corner with an area decides)
			for (int corner : { ia, ib, ic }) {
				if (vertex_area[size_t(corner)] != int8_t(AREA_NONE)) {
					area = BodyArea(vertex_area[size_t(corner)]);
					bound = corner;
					break;
				}
			}
			if (area == AREA_NONE) {
				continue;
			}
		}
		area_hairs[area]++;
		roots.push_back(root);
		const double side = root.x >= 0.0f ? 1.0 : -1.0;
		// the growth direction (a field on the skin): the limbs toward the hand / the foot, the chest down and in toward the breastbone, the belly line
		// down, the back down and out; the armpit a tangle
		Vector3 want;
		switch (area) {
			case AREA_UPPER_ARM:
			case AREA_FOREARM:
			case AREA_THIGH:
			case AREA_SHIN:
				want = vertex_along[size_t(bound)] + Vector3(real_t(side * 0.15), 0.0f, 0.0f);
				break;
			case AREA_CHEST:
				// the parting on the upper breastbone: above it the hair grows up and out toward the collar bones, below it down and in toward the line
				// (blended over ~4 cm: a hard switch drew a pale line across the chest, the hairs on each side catching the light differently)
				{
					const double up = smooth(frame.node_y - 0.02, frame.node_y + 0.02, double(root.y));
					want = Vector3(real_t(-side * 0.45), -1.0f, 0.0f).lerp(Vector3(real_t(side * 0.6), 1.0f, 0.0f), real_t(up));
					want += Vector3(real_t(side * 0.8 * up * (1.0 - up) * 4.0), 0.0f, 0.0f);   // (at the parting itself the hair lies sideways, outward)
				}
				break;
			case AREA_BELLY:
				want = Vector3(real_t(-side * 0.25), -1.0f, 0.0f);
				break;
			case AREA_BACK:
				want = Vector3(real_t(side * 0.4), -1.0f, 0.0f);
				break;
			default:
				want = Vector3(real_t(dice.range(-1.0, 1.0)), -0.6f, real_t(dice.range(-1.0, 1.0)));
				break;
		}
		Vector3 along = want - normal * real_t(want.dot(normal));
		if (along.length() < 0.1f) {
			along = Vector3(0.0f, -1.0f, 0.0f) - normal * real_t(-normal.y);
		}
		if (along.length() < 0.1f) {
			along = normal.cross(Vector3(1.0f, 0.0f, 0.0f));
		}
		along = along.normalized();
		const double area_curl = Math::clamp(curl * AREA_CURL[area], 0.0, 1.0);
		const double spread = area == AREA_ARMPIT ? 0.6 : 0.3;
		Vector3 direction = (along + normal * 0.25f + Vector3(real_t(dice.range(-spread, spread)), real_t(dice.range(-spread * 0.5, spread * 0.5)), real_t(dice.range(-spread, spread)))).normalized();
		const double hair_length = length * AREA_LENGTH[area] * dice.range(0.55, 1.35);
		const int steps = area_curl > 0.15 ? steps_curly : steps_plain;
		const double segment = hair_length / double(steps - 1);
		std::vector<Vector3> points;
		points.reserve(size_t(steps));
		Vector3 position = root + normal * 0.0004f;
		points.push_back(position);
		for (int k = 1; k < steps; k++) {
			// a body hair lies along the skin: every step bends it back toward the skin a little (it rests on it), with a little wander
			direction = (direction - normal * real_t(0.18 * direction.dot(normal)) + Vector3(real_t(dice.range(-0.15, 0.15)), real_t(dice.range(-0.08, 0.08)), real_t(dice.range(-0.15, 0.15)))).normalized();
			position += direction * real_t(segment);
			const double above = double((position - root).dot(normal));
			if (above < 0.0006) {
				position += normal * real_t(0.0006 - above);
			}
			points.push_back(position);
		}
		if (area_curl > 0.0) {
			// a coil round the hair's own line, its radius growing from the root
			const std::vector<Vector3> spine = points;
			const double phase = dice.range(0.0, Math_TAU);
			const double turn = (1.2 + 1.8 * area_curl) * dice.range(0.8, 1.2);
			const double radius = area_curl * (0.0006 + 0.18 * hair_length);
			for (int k = 1; k < steps; k++) {
				const Vector3 tangent = (spine[size_t(std::min(k + 1, steps - 1))] - spine[size_t(k - 1)]).normalized();
				Vector3 across = tangent.cross(normal);
				if (across.length() < 1e-4f) {
					across = Vector3(1.0f, 0.0f, 0.0f);
				}
				across = across.normalized();
				const Vector3 lift = across.cross(tangent).normalized();
				const double angle = phase + double(k) * turn;
				const double ramp = std::min(1.0, double(k) / 2.0);
				points[size_t(k)] = spine[size_t(k)] + (across * real_t(std::cos(angle)) + lift * real_t(std::sin(angle) * 0.5)) * real_t(radius * ramp);
			}
		}
		// the ribbon (two vertices a point, like a beard hair)
		const float brightness = float(dice.range(0.3, 0.8));
		const Color colour(brightness, 0.0f, 0.3f, float(Math::clamp(hair_length / 0.012, 0.25, 1.0))); // (blue 0.3: a beard-like hair for the shader; green 0: never thinned by the head hair's density)
		const int first = int(out_vertices.size());
		for (int k = 0; k < steps; k++) {
			const double sv = double(k) / double(steps - 1);
			const Vector3 tangent = (points[size_t(std::min(k + 1, steps - 1))] - points[size_t(std::max(k - 1, 0))]).normalized();
			Vector3 across = tangent.cross(normal);
			if (across.length() < 1e-5f) {
				across = Vector3(1.0f, 0.0f, 0.0f);
			}
			across = across.normalized();
			const Vector3 face = across.cross(tangent).normalized();
			const double width = width_base * (1.0 - 0.55 * std::pow(sv, 1.4));
			for (int e = 0; e < 2; e++) {
				out_vertices.push_back(points[size_t(k)] + across * real_t(width * (e == 0 ? -0.5 : 0.5)));
				out_normals.push_back(face);
				out_tangents.push_back(tangent);
				out_uvs.push_back(Vector2(float(e), float(sv)));
				out_colors.push_back(colour);
				out_s.push_back(float(sv));
				out_bound.push_back(bound);
			}
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

	const int out_count = int(out_vertices.size());
	Dictionary counts;
	int hair_total = 0;
	for (int a = 0; a < AREA_COUNT; a++) {
		counts[AREA_NAMES[a]] = area_hairs[a];
		hair_total += area_hairs[a];
	}
	built["hairs"] = hair_total;
	built["area_hairs"] = counts;
	built["roots"] = roots;
	built["vertex_count"] = out_count;
	if (out_count == 0) {
		return built;
	}

	// --- the arrays (the layout of HumanHair's: CUSTOM0 x -1 = no guide, a static hair)
	PackedVector3Array vertex_array, normal_array;
	PackedVector2Array uv_array, rest_array;
	PackedColorArray color_array;
	PackedFloat32Array tangent_array, custom_array;
	PackedInt32Array index_array;
	vertex_array.resize(out_count);
	normal_array.resize(out_count);
	uv_array.resize(out_count);
	rest_array.resize(out_count);
	color_array.resize(out_count);
	tangent_array.resize(int64_t(out_count) * 4);
	custom_array.resize(int64_t(out_count) * 4);
	for (int i = 0; i < out_count; i++) {
		vertex_array.set(i, out_vertices[size_t(i)]);
		normal_array.set(i, out_normals[size_t(i)]);
		uv_array.set(i, out_uvs[size_t(i)]);
		rest_array.set(i, Vector2(out_vertices[size_t(i)].x + out_vertices[size_t(i)].y, out_vertices[size_t(i)].z + out_vertices[size_t(i)].y));
		color_array.set(i, out_colors[size_t(i)]);
		tangent_array.set(int64_t(i) * 4, float(out_tangents[size_t(i)].x));
		tangent_array.set(int64_t(i) * 4 + 1, float(out_tangents[size_t(i)].y));
		tangent_array.set(int64_t(i) * 4 + 2, float(out_tangents[size_t(i)].z));
		tangent_array.set(int64_t(i) * 4 + 3, 1.0f);
		custom_array.set(int64_t(i) * 4, -1.0f);
		custom_array.set(int64_t(i) * 4 + 1, out_s[size_t(i)]);
		custom_array.set(int64_t(i) * 4 + 2, 0.0f);
		custom_array.set(int64_t(i) * 4 + 3, 0.0f);
	}
	index_array.resize(int64_t(out_indices.size()));
	for (size_t i = 0; i < out_indices.size(); i++) {
		index_array.set(int64_t(i), out_indices[i]);
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
	arrays[Mesh::ARRAY_CUSTOM0] = custom_array;

	// --- the blend shapes: every vertex moves with its bound body vertex (NORMALIZED: full positions, the base normals and tangents)
	Array blend_arrays;
	PackedStringArray blend_names;
	for (size_t s = 0; s < p_body->shape_deltas.size(); s++) {
		const std::vector<Vector3> &delta = p_body->shape_deltas[s];
		PackedVector3Array positions;
		positions.resize(out_count);
		for (int i = 0; i < out_count; i++) {
			positions.set(i, out_vertices[size_t(i)] + delta[size_t(out_bound[size_t(i)])]);
		}
		Array shape;
		shape.resize(Mesh::ARRAY_MAX);
		shape[Mesh::ARRAY_VERTEX] = positions;
		shape[Mesh::ARRAY_NORMAL] = normal_array;
		shape[Mesh::ARRAY_TANGENT] = tangent_array;
		blend_arrays.push_back(shape);
		blend_names.push_back(String(p_body->shape_names[s]));
	}
	built["arrays"] = arrays;
	built["blend_arrays"] = blend_arrays;
	built["blend_names"] = blend_names;
	return built;
}

} // namespace godot
