#include "plant_mesh_native.h"

#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/color.hpp>
#include <godot_cpp/variant/packed_color_array.hpp>
#include <godot_cpp/variant/packed_vector2_array.hpp>
#include <godot_cpp/variant/packed_vector3_array.hpp>
#include <godot_cpp/variant/basis.hpp>
#include <godot_cpp/variant/transform3d.hpp>
#include <godot_cpp/variant/vector2.hpp>
#include <godot_cpp/variant/vector3.hpp>

#include <algorithm>
#include <cmath>
#include <cstring>
#include <array>
#include <map>
#include <mutex>
#include <unordered_map>
#include <vector>

using namespace godot;

namespace {

const double PI_D = 3.14159265358979323846;
const double TAU_D = 2.0 * PI_D;
const double GOLDEN_ANGLE = 2.39996323;
const double LEAF_SWAY = 0.45;
const double NEEDLE_SWAY = 0.35;
const int BUDGET = 12000;
const int MARGIN = 150;
const int CAP_TOP = 1;
const int CAP_BOTTOM = 2;

const Vector3 UP(0, 1, 0);
const Vector3 DOWN(0, -1, 0);
const Vector3 RIGHT(1, 0, 0);
const Vector3 FORWARD(0, 0, -1);

// PCG32: the dice of one plant (a plant is always the same for a seed)
struct Rng {
	uint64_t state = 0;
	uint64_t inc = 1442695040888963407ULL;

	void seed(uint64_t p_seed) {
		state = 0;
		next();
		state += p_seed;
		next();
	}
	uint32_t next() {
		uint64_t old = state;
		state = old * 6364136223846793005ULL + inc;
		uint32_t xor_shifted = (uint32_t)(((old >> 18u) ^ old) >> 27u);
		uint32_t rot = (uint32_t)(old >> 59u);
		return (xor_shifted >> rot) | (xor_shifted << ((-(int32_t)rot) & 31));
	}
	double randf() { return (double)(next() >> 8) / 16777216.0; }
	double range(double p_from, double p_to) { return p_from + (p_to - p_from) * randf(); }
	int randi() { return (int)(next() >> 1); }
};

double lerpd(double a, double b, double t) { return a + (b - a) * t; }
double clampd(double v, double lo, double hi) { return v < lo ? lo : (v > hi ? hi : v); }

Color with_alpha(Color p_color, double p_alpha) {
	p_color.a = (float)p_alpha;
	return p_color;
}
Color still(Color p_color) { return with_alpha(p_color, 0.0); }
Color mix(const Color &a, const Color &b, double t) { return a.lerp(b, (float)t); }

// Everything the grower reads of a TreeGenome
struct Genome {
	double height = 8, girth = 0.3, taper = 0.6, lean = 0, trunk_part = 0.3, column = -1, root_flare = 0;
	bool leader = false, marked_bark = false, avoid = false, children_planar = false, carry_on = true;
	bool tips_only = false, compound = false, frosted = false;
	int stems = 1, flutes = 0, roots = 0, trunk_sides = 14, limbs = 4, depth = 3, foliage = 0;
	double stem_spread = 0.25, flute_depth = 0, trunk_bend = 0, trunk_lumps = 0, root_reach = 1;
	double trunk_wobble = 0.05, bark_rings = 0, bark_rough = 1, trunk_dark = 0.25;
	double crown = 2, aspect = 1, droop = 0, nodes_spacing = 0, nodes_from = 0, limb_angle = 50;
	double limb_length = 1, limb_thickness = 0.7, twist = 0, twig_radius = 1, child_radius = 0.6;
	double child_length_a = 1.25, child_length_b = 0.5, children_from = 0.3, children_to = 0.85;
	double child_forward = 0.4, child_side = 0.9, child_up = 0.25, bury = 0.4;
	int rings[3] = { 6, 5, 3 }, sides[3] = { 11, 8, 5 }, sides_real[3] = { 12, 10, 6 }, children[3] = { 4, 4, 0 };
	double curve[3] = { 0.5, 0.8, 1.2 }, wander[3] = { 0.06, 0.08, 0.1 }, lift[3] = { 0.08, 0.05, 0 };
	double sag[3] = { 0, 0.04, 0.1 }, droop_sag[3] = { 0, 0.14, 0.3 }, sway[3] = { 0.16, 0.2, 0.22 };
	double tip_radius[3] = { 0.4, 0.25, 0.05 }, child_length[3] = { 0.55, 0.5, 0 };
	int leaf_shape = 0, leaf_lobes = 0, leaf_edge = 0, leaf_pattern = 0;
	double leaf_aspect = 1.8, leaf_size = 0.2, needle_size = 0.45;
	int frond_parts = 9, fronds = 14, petals = 5, blossom_kind = 0;
	double frond_length = 3, frond_arch = 0.5, frond_droop = 0.5, leaflet = 0.22, rib_width = 0.012;
	double flower_size = 0.05, flower_cup = 0.4, blossom_size = 0.07, blossom_density = 0.5;
	double foliage_mass = 0, mass_size = 1, leaf_density = 1;
	Color flower = Color(0, 0, 0, 0), flower_centre = Color(0.9f, 0.68f, 0.1f), blossom = Color(0, 0, 0, 0);
	Color bark = Color(0.33f, 0.23f, 0.15f), leaf = Color(0.26f, 0.5f, 0.18f), leaf_tip = Color(0.4f, 0.6f, 0.25f);

	static double num(const Dictionary &d, const char *key, double def) {
		Variant v = d.get(String(key), def);
		return (double)v;
	}
	static int whole(const Dictionary &d, const char *key, int def) {
		Variant v = d.get(String(key), def);
		return (int)v;
	}
	static bool flag(const Dictionary &d, const char *key, bool def) {
		Variant v = d.get(String(key), def);
		return (bool)v;
	}
	static Color colour(const Dictionary &d, const char *key, Color def) {
		Variant v = d.get(String(key), def);
		return (Color)v;
	}
	static void ints(const Dictionary &d, const char *key, int *out) {
		Array a = d.get(String(key), Array());
		for (int i = 0; i < 3 && i < a.size(); i++) {
			out[i] = (int)a[i];
		}
	}
	static void nums(const Dictionary &d, const char *key, double *out) {
		Array a = d.get(String(key), Array());
		for (int i = 0; i < 3 && i < a.size(); i++) {
			out[i] = (double)a[i];
		}
	}

	void read(const Dictionary &d) {
		height = num(d, "height", height);
		girth = num(d, "girth", girth);
		taper = num(d, "taper", taper);
		lean = num(d, "lean", lean);
		trunk_part = num(d, "trunk_part", trunk_part);
		column = num(d, "column", column);
		root_flare = num(d, "root_flare", root_flare);
		leader = flag(d, "leader", leader);
		marked_bark = flag(d, "marked_bark", marked_bark);
		avoid = flag(d, "avoid", avoid);
		children_planar = flag(d, "children_planar", children_planar);
		carry_on = flag(d, "carry_on", carry_on);
		tips_only = flag(d, "tips_only", tips_only);
		compound = flag(d, "compound", compound);
		frosted = flag(d, "frosted", frosted);
		stems = whole(d, "stems", stems);
		flutes = whole(d, "flutes", flutes);
		roots = whole(d, "roots", roots);
		trunk_sides = whole(d, "trunk_sides", trunk_sides);
		limbs = whole(d, "limbs", limbs);
		depth = whole(d, "depth", depth);
		foliage = whole(d, "foliage", foliage);
		stem_spread = num(d, "stem_spread", stem_spread);
		flute_depth = num(d, "flute_depth", flute_depth);
		trunk_bend = num(d, "trunk_bend", trunk_bend);
		trunk_lumps = num(d, "trunk_lumps", trunk_lumps);
		root_reach = num(d, "root_reach", root_reach);
		trunk_wobble = num(d, "trunk_wobble", trunk_wobble);
		bark_rings = num(d, "bark_rings", bark_rings);
		bark_rough = num(d, "bark_rough", bark_rough);
		trunk_dark = num(d, "trunk_dark", trunk_dark);
		crown = num(d, "crown", crown);
		aspect = num(d, "aspect", aspect);
		droop = num(d, "droop", droop);
		nodes_spacing = num(d, "nodes_spacing", nodes_spacing);
		nodes_from = num(d, "nodes_from", nodes_from);
		limb_angle = num(d, "limb_angle", limb_angle);
		limb_length = num(d, "limb_length", limb_length);
		limb_thickness = num(d, "limb_thickness", limb_thickness);
		twist = num(d, "twist", twist);
		twig_radius = num(d, "twig_radius", twig_radius);
		child_radius = num(d, "child_radius", child_radius);
		child_length_a = num(d, "child_length_a", child_length_a);
		child_length_b = num(d, "child_length_b", child_length_b);
		children_from = num(d, "children_from", children_from);
		children_to = num(d, "children_to", children_to);
		child_forward = num(d, "child_forward", child_forward);
		child_side = num(d, "child_side", child_side);
		child_up = num(d, "child_up", child_up);
		bury = num(d, "bury", bury);
		ints(d, "rings", rings);
		ints(d, "sides", sides);
		ints(d, "sides_real", sides_real);
		ints(d, "children", children);
		nums(d, "curve", curve);
		nums(d, "wander", wander);
		nums(d, "lift", lift);
		nums(d, "sag", sag);
		nums(d, "droop_sag", droop_sag);
		nums(d, "sway", sway);
		nums(d, "tip_radius", tip_radius);
		nums(d, "child_length", child_length);
		leaf_shape = whole(d, "leaf_shape", leaf_shape);
		leaf_lobes = whole(d, "leaf_lobes", leaf_lobes);
		leaf_edge = whole(d, "leaf_edge", leaf_edge);
		leaf_pattern = whole(d, "leaf_pattern", leaf_pattern);
		leaf_aspect = num(d, "leaf_aspect", leaf_aspect);
		leaf_size = num(d, "leaf_size", leaf_size);
		needle_size = num(d, "needle_size", needle_size);
		frond_parts = whole(d, "frond_parts", frond_parts);
		fronds = whole(d, "fronds", fronds);
		petals = whole(d, "petals", petals);
		blossom_kind = whole(d, "blossom_kind", blossom_kind);
		frond_length = num(d, "frond_length", frond_length);
		frond_arch = num(d, "frond_arch", frond_arch);
		frond_droop = num(d, "frond_droop", frond_droop);
		leaflet = num(d, "leaflet", leaflet);
		rib_width = num(d, "rib_width", rib_width);
		flower_size = num(d, "flower_size", flower_size);
		flower_cup = num(d, "flower_cup", flower_cup);
		blossom_size = num(d, "blossom_size", blossom_size);
		blossom_density = num(d, "blossom_density", blossom_density);
		foliage_mass = num(d, "foliage_mass", foliage_mass);
		mass_size = num(d, "mass_size", mass_size);
		leaf_density = num(d, "leaf_density", leaf_density);
		flower = colour(d, "flower", flower);
		flower_centre = colour(d, "flower_centre", flower_centre);
		blossom = colour(d, "blossom", blossom);
		bark = colour(d, "bark", bark);
		leaf = colour(d, "leaf", leaf);
		leaf_tip = colour(d, "leaf_tip", leaf_tip);
	}
};

enum Foliage { BLADE = 0, NEEDLE = 1, FROND = 2 };
enum LeafShape { OVAL = 0, LOBED = 1, PALMATE = 2, HEART = 3, LANCEOLATE = 4, DIAMOND = 5 };
enum LeafEdge { SMOOTH = 0, SERRATED = 1, WAVY = 2 };
enum LeafPattern { ALTERNATE = 0, OPPOSITE = 1, SPIRAL = 2 };
enum Bloom { SINGLE = 0, RACEME = 1, UMBEL = 2 };

// What MeshBuilder collects: flat-shaded triangles (three own vertices each) with a colour per vertex
struct Ico {
	std::vector<Vector3> points;
	std::vector<std::array<int, 3>> faces;
};

// An icosahedron split `level` times (level 1 = 80 facets, 2 = 320, 3 = 1280), built once and shared
const Ico &icosphere(int level) {
	static std::mutex lock;
	static std::map<int, Ico> cache;
	std::lock_guard<std::mutex> guard(lock);
	auto found = cache.find(level);
	if (found != cache.end()) {
		return found->second;
	}
	Ico ico;
	const double t = (1.0 + std::sqrt(5.0)) * 0.5;
	const double base[12][3] = { { -1, t, 0 }, { 1, t, 0 }, { -1, -t, 0 }, { 1, -t, 0 }, { 0, -1, t }, { 0, 1, t }, { 0, -1, -t },
		{ 0, 1, -t }, { t, 0, -1 }, { t, 0, 1 }, { -t, 0, -1 }, { -t, 0, 1 } };
	for (auto &point : base) {
		ico.points.push_back(Vector3((real_t)point[0], (real_t)point[1], (real_t)point[2]).normalized());
	}
	const int faces[20][3] = { { 0, 11, 5 }, { 0, 5, 1 }, { 0, 1, 7 }, { 0, 7, 10 }, { 0, 10, 11 }, { 1, 5, 9 }, { 5, 11, 4 }, { 11, 10, 2 },
		{ 10, 7, 6 }, { 7, 1, 8 }, { 3, 9, 4 }, { 3, 4, 2 }, { 3, 2, 6 }, { 3, 6, 8 }, { 3, 8, 9 }, { 4, 9, 5 }, { 2, 4, 11 }, { 6, 2, 10 },
		{ 8, 6, 7 }, { 9, 8, 1 } };
	for (auto &face : faces) {
		ico.faces.push_back({ face[0], face[1], face[2] });
	}
	for (int split = 0; split < level; split++) {
		std::map<std::pair<int, int>, int> midpoints;
		std::vector<std::array<int, 3>> next;
		for (const auto &face : ico.faces) {
			int mids[3];
			for (int edge = 0; edge < 3; edge++) {
				int a = face[edge], b = face[(edge + 1) % 3];
				std::pair<int, int> key(std::min(a, b), std::max(a, b));
				auto at = midpoints.find(key);
				if (at == midpoints.end()) {
					at = midpoints.emplace(key, (int)ico.points.size()).first;
					ico.points.push_back(((ico.points[a] + ico.points[b]) * (real_t)0.5).normalized());
				}
				mids[edge] = at->second;
			}
			next.push_back({ face[0], mids[0], mids[2] });
			next.push_back({ face[1], mids[1], mids[0] });
			next.push_back({ face[2], mids[2], mids[1] });
			next.push_back({ mids[0], mids[1], mids[2] });
		}
		ico.faces = next;
	}
	return cache.emplace(level, std::move(ico)).first->second;
}

struct MeshData {
	Transform3D xf; // applied to everything added (a placed part)
	bool moved = false;
	bool detailed = false;
	bool leafless = false;
	bool leaf_cards = true;
	std::vector<Vector3> vertices, normals;
	std::vector<Color> colors;
	std::vector<Vector2> uvs, uv2s;
	bool has_uv = false;

	int triangle_count() const { return (int)vertices.size() / 3; }
	void reset() {
		vertices.clear();
		normals.clear();
		colors.clear();
		uvs.clear();
		uv2s.clear();
		has_uv = false;
	}

	// the corners come counter clockwise seen from outside; Godot wants clockwise, so b and c swap
	void tri(const Vector3 &a, const Vector3 &b, const Vector3 &c, const Color &ca, const Color &cb,
			const Color &cc) {
		const Vector3 pa = moved ? xf.xform(a) : a, pb = moved ? xf.xform(b) : b, pc = moved ? xf.xform(c) : c;
		Vector3 normal = (pb - pa).cross(pc - pa).normalized();
		vertices.push_back(pa);
		vertices.push_back(pc);
		vertices.push_back(pb);
		normals.push_back(normal);
		normals.push_back(normal);
		normals.push_back(normal);
		colors.push_back(ca);
		colors.push_back(cc);
		colors.push_back(cb);
		uvs.push_back(Vector2());
		uvs.push_back(Vector2());
		uvs.push_back(Vector2());
		uv2s.push_back(Vector2());
		uv2s.push_back(Vector2());
		uv2s.push_back(Vector2());
	}
	void tri(const Vector3 &a, const Vector3 &b, const Vector3 &c, const Color &col) { tri(a, b, c, col, col, col); }
	void tri_uv(const Vector3 &a, const Vector3 &b, const Vector3 &c, const Color &ca, const Color &cb,
			const Color &cc, const Vector2 &ua, const Vector2 &ub, const Vector2 &uc, const Vector2 &dice) {
		tri(a, b, c, ca, cb, cc);
		size_t at = vertices.size() - 3;
		uvs[at] = ua;
		uvs[at + 1] = uc;
		uvs[at + 2] = ub;
		uv2s[at] = dice;
		uv2s[at + 1] = dice;
		uv2s[at + 2] = dice;
		has_uv = true;
	}

	void place(const Transform3D &p_xf) {
		xf = p_xf;
		moved = true;
	}
	void unplace() {
		xf = Transform3D();
		moved = false;
	}

	// A lumpy ball: an icosahedron split once or twice, each point pushed in or out
	void blob(const Vector3 &center, const Vector3 &radius, const Color &low, const Color &high, Rng &rng, double lumpiness) {
		const Ico &ico = icosphere(detailed ? 2 : 1);
		struct Wave {
			Vector3 axis;
			double frequency, phase, amplitude;
		};
		std::vector<Wave> waves;
		if (detailed) {
			for (int w = 0; w < 5; w++) {
				Vector3 axis((real_t)rng.range(-1.0, 1.0), (real_t)rng.range(-1.0, 1.0), (real_t)rng.range(-1.0, 1.0));
				double frequency = rng.range(1.5, 4.5);
				double phase = rng.randf() * TAU_D;
				double amplitude = rng.range(0.4, 1.0) * lumpiness;
				waves.push_back({ axis.normalized(), frequency, phase, amplitude });
			}
		}
		std::vector<Vector3> shape(ico.points.size());
		for (size_t i = 0; i < ico.points.size(); i++) {
			const Vector3 &unit = ico.points[i];
			double bulge = 0.0;
			for (const Wave &wave : waves) {
				bulge += wave.amplitude * std::sin(unit.dot(wave.axis) * wave.frequency + wave.phase);
			}
			double factor = detailed ? bulge + rng.range(-lumpiness, lumpiness) * 0.12 : rng.range(-lumpiness, lumpiness);
			shape[i] = unit * (real_t)(1.0 + factor);
		}
		for (const auto &face : ico.faces) {
			Vector3 corners[3];
			Color colors[3];
			for (int k = 0; k < 3; k++) {
				const Vector3 &local = shape[face[k]];
				corners[k] = center + Vector3(local.x * radius.x, local.y * radius.y, local.z * radius.z);
				colors[k] = low.lerp(high, (float)clampd(local.y * 0.5 + 0.5, 0.0, 1.0));
			}
			tri(corners[0], corners[1], corners[2], colors[0], colors[1], colors[2]);
		}
	}

	// A boulder: the lumpy ball cut by flat planes, banded in tone (MeshBuilder.add_rock). The UV marks it as stone.
	void rock(const Vector3 &center, const Vector3 &radius, const Color &low, const Color &high, Rng &rng, int cuts) {
		const Ico &ico = icosphere(detailed ? 3 : 2);
		std::vector<std::array<double, 4>> planes;
		for (int cut = 0; cut < cuts; cut++) {
			Vector3 normal((real_t)rng.range(-1.0, 1.0), (real_t)rng.range(-0.5, 0.8), (real_t)rng.range(-1.0, 1.0));
			normal = normal.normalized();
			planes.push_back({ (double)normal.x, (double)normal.y, (double)normal.z, rng.range(0.74, 0.95) });
		}
		struct Bulge {
			Vector3 axis;
			double frequency, phase;
		};
		std::vector<Bulge> bulges;
		for (int w = 0; w < 3; w++) {
			Vector3 axis((real_t)rng.range(-1.0, 1.0), (real_t)rng.range(-1.0, 1.0), (real_t)rng.range(-1.0, 1.0));
			double frequency = rng.range(1.2, 3.0);
			double phase = rng.randf() * TAU_D;
			bulges.push_back({ axis.normalized(), frequency, phase });
		}
		double band_phase = rng.randf() * TAU_D;
		std::vector<Vector3> shape(ico.points.size());
		for (size_t i = 0; i < ico.points.size(); i++) {
			const Vector3 &unit = ico.points[i];
			double reach = 1.0;
			for (const auto &plane : planes) {
				double facing = unit.x * plane[0] + unit.y * plane[1] + unit.z * plane[2];
				if (facing > 0.01) {
					reach = std::min(reach, plane[3] / facing);
				}
			}
			for (const Bulge &bulge : bulges) {
				reach *= 1.0 + 0.05 * std::sin(unit.dot(bulge.axis) * bulge.frequency + bulge.phase);
			}
			shape[i] = unit * (real_t)(reach * (1.0 + rng.range(-0.012, 0.012)));
		}
		for (const auto &face : ico.faces) {
			Vector3 corners[3];
			Color colors[3];
			for (int k = 0; k < 3; k++) {
				const Vector3 &local = shape[face[k]];
				corners[k] = center + Vector3(local.x * radius.x, local.y * radius.y, local.z * radius.z);
				double band = 0.5 + 0.5 * std::sin(local.y * 9.0 + local.x * 3.0 + band_phase);
				Color tone = low.lerp(high, (float)clampd(local.y * 0.5 + 0.5, 0.0, 1.0));
				float scale = (float)(0.93 + 0.1 * band);
				colors[k] = Color(tone.r * scale, tone.g * scale, tone.b * scale, tone.a * scale);
			}
			tri_uv(corners[0], corners[1], corners[2], colors[0], colors[1], colors[2], Vector2(-0.25f, 0), Vector2(-0.25f, 0),
					Vector2(-0.25f, 0), Vector2());
		}
	}

	void frustum(const Vector3 &base, double height, double r0, double r1, int sides, const Color &bottom,
			const Color &top, int caps, Rng *rng = nullptr, double jitter = 0.0) {
		if (detailed && sides >= 5 && sides < 12) {
			sides *= 2;
		}
		std::vector<Vector3> bottom_ring(sides), top_ring(sides);
		for (int i = 0; i < sides; i++) {
			double angle = TAU_D * i / sides;
			double wobble0 = 1.0, wobble1 = 1.0, lift = 0.0;
			if (rng != nullptr) {
				wobble0 += rng->range(-jitter, jitter);
				wobble1 += rng->range(-jitter, jitter);
				lift = rng->range(-jitter, jitter) * height * 0.15;
			}
			bottom_ring[i] = base + Vector3((real_t)(cos(angle) * r0 * wobble0), 0, (real_t)(sin(angle) * r0 * wobble0));
			top_ring[i] = base + Vector3((real_t)(cos(angle) * r1 * wobble1), (real_t)(height + lift), (real_t)(sin(angle) * r1 * wobble1));
		}
		Vector3 apex = base + Vector3(0, (real_t)height, 0);
		for (int i = 0; i < sides; i++) {
			int next = (i + 1) % sides;
			if (r1 <= 0.0001) {
				tri(bottom_ring[i], apex, bottom_ring[next], bottom, top, bottom);
			} else {
				tri(bottom_ring[i], top_ring[i], bottom_ring[next], bottom, top, bottom);
				tri(bottom_ring[next], top_ring[i], top_ring[next], bottom, top, top);
			}
			if ((caps & CAP_TOP) && r1 > 0.0001) {
				tri(apex, top_ring[next], top_ring[i], top);
			}
			if (caps & CAP_BOTTOM) {
				tri(base, bottom_ring[next], bottom_ring[i], bottom);
			}
		}
	}

	// One continuous tube through ring centres (see PlantTreeBuilders.tube)
	void tube(const std::vector<Vector3> &centres, const std::vector<double> &radii,
			const std::vector<Color> &colors_in, int sides, Rng &rng, double wobble, int caps,
			bool refine, int flutes, const std::vector<double> &flute_depths) {
		if (refine && detailed && sides >= 5 && sides < 12) {
			sides *= 2;
		}
		int count = (int)centres.size();
		std::vector<std::vector<Vector3>> rings;
		Vector3 side;
		Vector3 last_tangent;
		for (int ring = 0; ring < count; ring++) {
			Vector3 tangent = (centres[std::min(ring + 1, count - 1)] - centres[std::max(ring - 1, 0)]).normalized();
			if (ring == 0) {
				Vector3 reference = std::abs(tangent.x) < 0.8 ? RIGHT : FORWARD;
				side = (reference - tangent * tangent.dot(reference)).normalized();
			} else {
				Vector3 turn = last_tangent.cross(tangent);
				if (turn.length_squared() > 0.000001) {
					side = side.rotated(turn.normalized(), last_tangent.angle_to(tangent));
				}
				side = (side - tangent * tangent.dot(side)).normalized();
			}
			last_tangent = tangent;
			Vector3 across = side.cross(tangent);
			std::vector<Vector3> points(sides);
			for (int i = 0; i < sides; i++) {
				double angle = TAU_D * i / sides;
				double jitter = 1.0 + rng.range(-wobble, wobble);
				if (flutes > 0 && !flute_depths.empty()) {
					double depth = flute_depths[std::min(ring, (int)flute_depths.size() - 1)];
					jitter *= 1.0 + depth * cos(flutes * angle + ring * 0.12);
				}
				points[i] = centres[ring] + (side * (real_t)cos(angle) + across * (real_t)sin(angle)) * (real_t)(radii[ring] * jitter);
			}
			rings.push_back(points);
		}
		// the bark's coordinates (see flora_wind.gdshader): UV.x = -(1 + the way round, 0..1), UV.y = metres
		// along the tube, UV2.x = its radius there. Every triangle has its own corners, so the seam closes.
		std::vector<double> along(count, 0.0);
		for (int ring = 1; ring < count; ring++) {
			along[ring] = along[ring - 1] + (centres[ring] - centres[ring - 1]).length();
		}
		auto bark = [&](int ring, double round_) { return Vector2((real_t)(-1.0 - round_), (real_t)along[ring]); };
		auto girth = [&](int ring) { return Vector2((real_t)radii[ring], 0.0f); };
		for (int ring = 0; ring < count - 1; ring++) {
			for (int i = 0; i < sides; i++) {
				int next = (i + 1) % sides;
				double u0 = (double)i / sides, u1 = (double)(i + 1) / sides;
				const Color &low = colors_in[ring];
				const Color &high = colors_in[ring + 1];
				tri(rings[ring][i], rings[ring + 1][i], rings[ring][next], low, high, low);
				set_uv(bark(ring, u0), bark(ring + 1, u0), bark(ring, u1), girth(ring), girth(ring + 1), girth(ring));
				tri(rings[ring][next], rings[ring + 1][i], rings[ring + 1][next], low, high, high);
				set_uv(bark(ring, u1), bark(ring + 1, u0), bark(ring + 1, u1), girth(ring), girth(ring + 1),
						girth(ring + 1));
			}
		}
		for (int i = 0; i < sides; i++) {
			int next = (i + 1) % sides;
			double u0 = (double)i / sides, u1 = (double)(i + 1) / sides;
			if (caps & CAP_TOP) {
				tri(centres[count - 1], rings[count - 1][next], rings[count - 1][i], colors_in[count - 1]);
				set_uv(bark(count - 1, 0.5), bark(count - 1, u1), bark(count - 1, u0), girth(count - 1),
						girth(count - 1), girth(count - 1));
			}
			if (caps & CAP_BOTTOM) {
				tri(centres[0], rings[0][i], rings[0][next], colors_in[0]);
				set_uv(bark(0, 0.5), bark(0, u0), bark(0, u1), girth(0), girth(0), girth(0));
			}
		}
	}

	// the UVs of the triangle just added, given for its a, b, c corners (the vertices are a, c, b)
	void set_uv(const Vector2 &ua, const Vector2 &ub, const Vector2 &uc, const Vector2 &va, const Vector2 &vb,
			const Vector2 &vc) {
		size_t at = vertices.size() - 3;
		uvs[at] = ua;
		uvs[at + 1] = uc;
		uvs[at + 2] = ub;
		uv2s[at] = va;
		uv2s[at + 1] = vc;
		uv2s[at + 2] = vb;
		has_uv = true;
	}
};

// The outline of one leaf (PlantLeafShapes.outline_for): [stalk end, right side..., tip, left side...]
double leaf_width(int shape, double along, int per_side) {
	switch (shape) {
		case LOBED: {
			double lobe = 0.5 + 0.5 * cos(PI_D * (per_side + 1) * along);
			return sin(PI_D * pow(along, 0.85)) * lerpd(0.5, 1.0, lobe);
		}
		case HEART:
			return sin(PI_D * pow(along, 0.55)) * (1.0 + 0.2 * (1.0 - along));
		case DIAMOND:
			return along < 0.42 ? along / 0.42 : (1.0 - along) / 0.58;
		case LANCEOLATE:
			return pow(sin(PI_D * pow(along, 0.85)), 0.8);
		default:
			return sin(PI_D * pow(along, 0.78));
	}
}

double tooth(int index, double edge) { return (edge >= 1.0 || index % 2 == 1) ? 1.0 : edge; }

Vector2 polar(const Vector2 &centre, double angle_deg, double distance, double squeeze) {
	double angle = angle_deg * PI_D / 180.0;
	return Vector2((real_t)(centre.x + sin(angle) * distance * squeeze), (real_t)(centre.y + cos(angle) * distance));
}

std::vector<Vector2> palmate(double aspect) {
	Vector2 centre(0.0f, 0.5f);
	double squeeze = 1.0 / aspect;
	const double right[5][2] = { { 112, 0.26 }, { 74, 0.4 }, { 55, 0.3 }, { 36, 0.47 }, { 18, 0.3 } };
	std::vector<Vector2> points;
	points.push_back(Vector2(0, 0));
	for (int i = 0; i < 5; i++) {
		points.push_back(polar(centre, right[i][0], right[i][1], squeeze));
	}
	points.push_back(Vector2(0, 1));
	for (int i = 4; i >= 0; i--) {
		points.push_back(polar(centre, -right[i][0], right[i][1], squeeze));
	}
	return points;
}

std::vector<Vector2> leaf_outline(int shape, double aspect, int lobes, int edge_kind, bool detailed) {
	if (shape == PALMATE) {
		return palmate(aspect);
	}
	bool simple = shape == OVAL || shape == DIAMOND;
	int per_side = simple ? 2 : 3;
	if (detailed) {
		per_side += 1;
	}
	if (shape == LOBED) {
		per_side = 2 * std::max(lobes, 1) + 1;
	}
	double edge = 1.0;
	bool toothed = edge_kind != SMOOTH;
	if (detailed && toothed && shape != LOBED) {
		per_side += 2;
		edge = edge_kind == SERRATED ? 0.8 : 0.92;
	}
	double half = 0.5 / aspect;
	std::vector<Vector2> points;
	points.push_back(Vector2(0, 0));
	for (int i = 0; i < per_side; i++) {
		double along = (double)(i + 1) / (per_side + 1);
		points.push_back(Vector2((real_t)(half * leaf_width(shape, along, per_side) * tooth(i, edge)), (real_t)along));
	}
	points.push_back(Vector2(0, 1));
	for (int i = 0; i < per_side; i++) {
		double along = (double)(per_side - i) / (per_side + 1);
		double t = tooth(per_side - 1 - i, edge);
		points.push_back(Vector2((real_t)(-half * leaf_width(shape, along, per_side) * t), (real_t)along));
	}
	return points;
}

// A cluster of leaves as one card; the plant shader draws the leaves on it
void add_leaf_card(MeshData &b, const Vector3 &base, const Vector3 &axis, const Vector3 &normal, double length,
		const Color &base_color, const Color &tip_color, double dice) {
	Vector3 right = axis.cross(normal).normalized();
	real_t half = (real_t)(length * 0.5);
	Vector3 a = base - right * half * 0.8f;
	Vector3 bb = base + right * half * 0.8f;
	Vector3 c = base + axis * (real_t)length + right * half;
	Vector3 d = base + axis * (real_t)length - right * half;
	Vector2 mark((real_t)dice, (real_t)(2.0 + dice));
	b.tri_uv(a, bb, c, base_color, base_color, tip_color, Vector2(0.1f, 0), Vector2(0.9f, 0), Vector2(1, 1), mark);
	b.tri_uv(a, c, d, base_color, tip_color, tip_color, Vector2(0.1f, 0), Vector2(1, 1), Vector2(0, 1), mark);
}

// One leaf as a fan of triangles round a centre point a little above it (PlantLeafShapes.add_leaf)
void add_leaf(MeshData &b, const std::vector<Vector2> &outline, const Vector3 &base, const Vector3 &axis,
		const Vector3 &normal, double length, double fold, double curl, const Color &base_color,
		const Color &tip_color, double asym, double skew, double width, const Vector2 &dice) {
	Vector3 right = axis.cross(normal).normalized();
	size_t n = outline.size();
	std::vector<Vector3> corners(n);
	std::vector<Color> colors(n);
	for (size_t i = 0; i < n; i++) {
		const Vector2 &point = outline[i];
		double sign = point.x > 0 ? 1.0 : (point.x < 0 ? -1.0 : 0.0);
		double across = point.x * width * (1.0 + asym * sign) + skew * point.y * point.y;
		corners[i] = base + axis * (real_t)(point.y * length) + right * (real_t)(across * length) +
				normal * (real_t)(curl * point.y * point.y * length);
		colors[i] = mix(base_color, tip_color, point.y);
	}
	for (size_t i = 0; i < n; i++) {
		if (outline[i].x == 0.0f) {
			colors[i] = colors[i].lightened(0.22f);
		} else if (i % 2 == 1) {
			colors[i] = colors[i].lightened(0.14f);
		} else {
			colors[i] = colors[i].darkened(0.16f);
		}
	}
	Vector3 centre = base + axis * (real_t)(0.45 * length) + normal * (real_t)(fold * length);
	Color centre_color = mix(base_color, tip_color, 0.35).lightened(0.2f);
	double widest = 0.001;
	for (const Vector2 &p : outline) {
		widest = std::max(widest, (double)std::abs(p.x));
	}
	std::vector<Vector2> uvs(n);
	for (size_t i = 0; i < n; i++) {
		uvs[i] = Vector2((real_t)(0.5 + 0.5 * outline[i].x / widest), outline[i].y);
	}
	Vector2 centre_uv(0.5f, 0.45f);
	for (size_t i = 0; i < n; i++) {
		size_t next = (i + 1) % n;
		b.tri_uv(centre, corners[i], corners[next], centre_color, colors[i], colors[next], centre_uv, uvs[i],
				uvs[next], dice);
	}
}

Vector3 rotate_about(const Vector3 &v, const Vector3 &axis, double angle) { return v.rotated(axis, (real_t)angle); }

struct Grower {
	Genome *g;
	MeshData *b;
	Rng *rng;
	bool capped = false;
	double thrift = 1.0;
	int budget = BUDGET;
	int lod = 0;
	bool fine = false;
	bool cards = false; // the realistic look's leaves as cards and strips drawn by the shader (every level of detail)
	int depth = 3;
	double height = 8;
	double trunk_length = 2;
	Vector3 tilt;
	std::vector<Vector3> solid_points;
	std::vector<double> solid_radii;
	std::vector<int> solid_ids;
	int next_id = 0;
	int parent_id = -1;
	Vector3 origin;
	std::vector<Vector2> outline;
	double leaf_length = 0.3;
	double needle_length = 0.5;

	double rf() { return rng->randf(); }
	double rr(double a, double c) { return rng->range(a, c); }

	void grow() {
		if (g->stems <= 1 || g->leader) {
			grow_stem(Vector3());
			return;
		}
		double h = g->height, girth = g->girth, crown = g->crown;
		double phase = rf() * TAU_D;
		for (int stem = 0; stem < g->stems; stem++) {
			double size = 1.0 - 0.3 * stem / g->stems * rr(0.6, 1.2);
			g->height = h * size;
			g->girth = girth * size * 0.8;
			g->crown = crown * (0.6 + 0.4 * size);
			double yaw = phase + TAU_D * stem / g->stems + rr(-0.3, 0.3);
			Vector3 out((real_t)cos(yaw), 0, (real_t)sin(yaw));
			origin = out * (real_t)(girth * 0.8);
			grow_stem(out * (real_t)(g->stem_spread * g->height));
		}
		g->height = h;
		g->girth = girth;
		g->crown = crown;
		origin = Vector3();
	}

	void grow_stem(const Vector3 &lean_to) {
		height = g->height * rr(0.9, 1.1);
		tilt = lean_to;
		trunk_length = g->leader ? height : height * g->trunk_part;
		if (g->lean > 0.0) {
			tilt += Vector3((real_t)rr(-1, 1), 0, (real_t)rr(-1, 1)).normalized() * (real_t)(g->lean * height);
		}
		outline = leaf_outline(g->leaf_shape, g->leaf_aspect, g->leaf_lobes, g->leaf_edge, fine);
		double bigger = 1.0 + 0.8 * lod;
		double leaf_basis = 2.0 * pow(std::max(g->crown, 0.2) / 2.0, 0.55);
		leaf_basis *= pow(std::max(g->crown / 3.5, 1.0), 0.6);
		leaf_length = leaf_basis * g->leaf_size * (fine || cards ? 1.7 : 2.5) * bigger;
		double stout = pow(std::max(g->girth / 0.4, 1.0), 0.75);
		double needle = clampd(leaf_basis * g->needle_size, 0.6, 1.1) * stout;
		needle_length = needle * (fine ? 1.0 : 1.2) * bigger;
		trunk();
		if (g->foliage == FROND) {
			fronds();
		} else if (g->leader) {
			whorls();
		} else {
			limbs();
		}
	}

	bool full() {
		if (b->triangle_count() < budget - MARGIN) {
			return false;
		}
		capped = true;
		return true;
	}

	Vector3 axis_at(double y) const {
		double along = y / trunk_length;
		return origin + Vector3((real_t)(tilt.x * along * along), (real_t)y, (real_t)(tilt.z * along * along));
	}

	double trunk_radius(double along) const {
		double flare = 1.0 + 2.0 * g->root_flare * pow(1.0 - along, 6.0);
		if (g->leader && g->column >= 0.0) {
			return g->girth * lerpd(1.0, g->column, pow(along, 0.9)) * flare;
		}
		if (g->leader) {
			return (g->girth * pow(1.0 - along, 0.85) + 0.02) * flare;
		}
		return lerpd(g->girth, g->girth * g->taper, along) * flare;
	}

	void trunk() {
		if (g->foliage == FROND && trunk_length < 0.5) {
			return;
		}
		int rings = (g->leader ? 7 : 5) - lod;
		bool ringed = g->bark_rings > 0.0 && lod == 0;
		if (ringed) {
			rings = std::max(rings, std::min((int)(trunk_length / (g->bark_rings * 0.5)), 40));
		}
		std::vector<Vector3> centres;
		std::vector<double> radii;
		std::vector<Color> colors;
		if (g->trunk_bend > 0.0 || g->trunk_lumps > 0.0 || g->flutes > 0) {
			rings = std::max(rings, 12 - 3 * lod);
		}
		double bend_phase = rf() * TAU_D;
		double lump_phase = rf() * TAU_D;
		std::vector<double> flute_depths;
		for (int index = 0; index < rings; index++) {
			double along = (double)index / (rings - 1);
			Vector3 centre = axis_at(trunk_length * along);
			if (g->trunk_bend > 0.0) {
				double sway_by = g->girth * 2.0 * g->trunk_bend * sin(along * PI_D * 1.6 + bend_phase) * along;
				centre += Vector3((real_t)sway_by, 0, (real_t)(sway_by * 0.6 * cos(along * 5.0 + bend_phase)));
			}
			centres.push_back(centre);
			double lumps = 1.0;
			if (g->trunk_lumps > 0.0) {
				lumps += g->trunk_lumps * (0.14 * sin(along * TAU_D * 2.1 + lump_phase) + 0.1 * sin(along * TAU_D * 4.3 + bend_phase));
			}
			flute_depths.push_back(g->flute_depth * (1.0 - 0.6 * along));
			radii.push_back(trunk_radius(along) * lumps * (ringed ? 1.0 + 0.08 * (index % 2) : 1.0));
			colors.push_back(still(g->bark.darkened((float)(g->trunk_dark * (1.0 - along) + ((ringed && index % 2 == 1) ? 0.12 : 0.0)))));
		}
		if (!g->leader) {
			double top_radius = g->girth * g->taper;
			Vector3 top = centres.back();
			const double dome[2][2] = { { 0.5, 0.8 }, { 0.95, 0.3 } };
			for (int i = 0; i < 2; i++) {
				centres.push_back(top + Vector3(0, (real_t)(top_radius * dome[i][0]), 0));
				radii.push_back(top_radius * dome[i][1]);
				colors.push_back(colors.back());
			}
		}
		int trunk_sides = g->trunk_sides - 5 * lod;
		int flutes = lod == 0 ? g->flutes : 0;
		if (flutes > 0) {
			trunk_sides = std::max(trunk_sides, flutes * 4);
		}
		b->tube(centres, radii, colors, trunk_sides, *rng, g->trunk_wobble * g->bark_rough, CAP_TOP, false, flutes,
				flute_depths);
		roots();
		if (g->marked_bark && !g->leader && lod == 0) {
			int marks = (int)(trunk_length / 0.8);
			for (int mark = 0; mark < marks; mark++) {
				double at = mark * 0.8 + 0.4;
				double radius = trunk_radius(at / trunk_length) * 1.04;
				Color patch = still(Color(0.12f, 0.12f, 0.1f));
				b->frustum(axis_at(at), 0.12, radius, radius * 0.99, g->trunk_sides, patch, patch, 0);
			}
		}
	}

	void roots() {
		if (g->roots <= 0 || lod > 0) {
			return;
		}
		double phase = rf() * TAU_D;
		for (int index = 0; index < g->roots; index++) {
			double yaw = phase + TAU_D * index / g->roots + rr(-0.3, 0.3);
			Vector3 out((real_t)cos(yaw), 0, (real_t)sin(yaw));
			Vector3 side(-out.z, 0, out.x);
			double reach = g->girth * (1.6 + 2.2 * g->root_reach * rr(0.6, 1.2));
			double thick = g->girth * rr(0.3, 0.55);
			double rise = g->girth * rr(0.5, 1.2);
			double wander = rr(-0.5, 0.5);
			std::vector<Vector3> centres;
			std::vector<double> radii;
			std::vector<Color> colors;
			const int parts = 6;
			for (int step = 0; step < parts; step++) {
				double t = (double)step / (parts - 1);
				double distance = g->girth * (0.5 + 1.0 * g->root_flare) + reach * t;
				double h = rise * pow(1.0 - t, 2.2) - 0.12 * t;
				centres.push_back(origin + out * (real_t)distance + side * (real_t)(wander * reach * t * t) + Vector3(0, (real_t)h, 0));
				radii.push_back(thick * lerpd(1.0, 0.18, pow(t, 0.8)) * (1.0 + 0.5 * (1.0 - t) * (1.0 - t)));
				colors.push_back(still(g->bark.darkened((float)(0.12 + 0.1 * t))));
			}
			b->tube(centres, radii, colors, 6, *rng, 0.08, CAP_TOP, false, 0, std::vector<double>());
		}
	}

	void limbs() {
		Vector3 top = axis_at(trunk_length);
		double crown_height = (height - trunk_length) * 0.5;
		Vector3 centre = top + Vector3(0, (real_t)(crown_height * 0.7), 0);
		double radius_h = g->crown * 1.8;
		double radius_v = std::max(crown_height * 0.85, g->crown * g->aspect);
		double limb_radius = g->girth * g->taper * g->limb_thickness;
		double phase = rf() * TAU_D;
		int count = std::max(g->limbs - lod, 3);
		for (int index = 0; index < count; index++) {
			double yaw = phase + index * GOLDEN_ANGLE;
			double pitch = g->limb_angle * rr(0.85, 1.15) * PI_D / 180.0;
			Vector3 dir((real_t)(sin(pitch) * cos(yaw)), (real_t)cos(pitch), (real_t)(sin(pitch) * sin(yaw)));
			Vector3 start = top + Vector3(0, (real_t)(-limb_radius * 2.0 + index * limb_radius * 0.6), 0);
			start -= dir * (real_t)(limb_radius * 0.5);
			double length = clampd(radius_h * 0.85 / std::max(sin(pitch), 0.35), radius_h * 0.6, radius_h * 1.3);
			length = std::min(length, (centre.y + radius_v - start.y) / std::max(cos(pitch), 0.2));
			length *= g->limb_length;
			branch(start, dir, length, limb_radius, 0, 0.0, false);
		}
	}

	void fronds() {
		bool low = g->height < 1.0;
		Vector3 top = axis_at(trunk_length) + Vector3(0, low ? 0.0f : 0.05f, 0);
		if (low) {
			top.y = 0;
		}
		int count = std::max(g->fronds - 3 * lod, 5);
		// the realistic look: a grass tuft is a real tuft, many thin blades, each bending in more places
		bool tuft = fine && low && g->leaflet < 0.02;
		if (tuft) {
			count = std::min(count * 2, 40);
		}
		double phase = rf() * TAU_D;
		for (int index = 0; index < count; index++) {
			double yaw = phase + index * GOLDEN_ANGLE;
			Vector3 out((real_t)cos(yaw), 0, (real_t)sin(yaw));
			Vector3 side(-out.z, 0, out.x);
			double length = g->frond_length * rr(0.85, 1.1);
			double steep = pow(rf(), 1.5);
			if (g->flower.a > 0.0f) {
				steep = lerpd(0.55, 0.95, rf());
			}
			int parts = std::max(g->frond_parts - 3 * lod, 2);
			if (tuft) {
				parts = std::max(parts, 6);
				length *= rr(0.55, 1.0); // blades of all lengths
			}
			std::vector<Vector3> points;
			for (int step = 0; step <= parts; step++) {
				double t = (double)step / parts;
				double reach = length * t * (1.0 - 0.6 * steep);
				double rise = length * (0.9 * steep * t + 0.5 * g->frond_arch * sin(PI_D * t) - g->frond_droop * t * t);
				Vector3 spot = top + out * (real_t)reach + Vector3(0, (real_t)rise, 0);
				if (low) {
					spot.y = std::max(spot.y, (real_t)0.01);
				}
				points.push_back(spot);
			}
			frond(points, side);
		}
	}

	void frond(const std::vector<Vector3> &points, const Vector3 &side) {
		if (b->leafless || full()) {
			return;
		}
		double length = (points.back() - points.front()).length();
		double rib = length * g->rib_width * (fine && g->leaflet < 0.02 && g->height < 1.5 ? 0.5 : 1.0);
		Color dark = g->leaf.darkened(0.35f);
		Color tone = mix(g->leaf, g->leaf.lightened(0.12f), rf());
		int segments = (int)points.size() - 1;
		bool low_plant = g->height < 1.5;
		// the realistic look: a tall frond's leaflets are a strip along the rib, drawn on it by the shader
		// (UV2.y 4 + rows / 100: a pinnate strip, see flora_wind.gdshader), not a triangle for each leaflet
		bool strip = cards && !low_plant && g->leaflet >= 0.02;
		double rows = clampd(length / 0.08, 10.0, 80.0);
		double pin_dice = rf();
		for (int index = 0; index < segments; index++) {
			double t = (double)index / segments;
			double sway = 0.35 + 0.5 * t;
			const Vector3 &a = points[index];
			const Vector3 &c = points[index + 1];
			Vector3 tangent = (c - a).normalized();
			Color base = with_alpha(dark, sway);
			Color tip = with_alpha(dark, std::min(sway + 0.1, 1.0));
			double narrow = g->flower.a > 0.0f ? 0.4 : 0.9;
			Vector3 wide_a = side * (real_t)(rib * (1.0 - narrow * t));
			Vector3 wide_b = side * (real_t)(rib * (1.0 - narrow * (t + 1.0 / segments)));
			b->tri(a - wide_a, a + wide_a, c + wide_b, base, base, tip);
			b->tri(a - wide_a, c + wide_b, c - wide_b, base, tip, tip);
			if (strip) {
				double t2 = t + 1.0 / segments;
				double size_a = length * g->leaflet * pow(sin(PI_D * clampd(t, 0.05, 0.98)), 0.7) * 1.15;
				double size_c = length * g->leaflet * pow(sin(PI_D * clampd(t2, 0.05, 0.98)), 0.7) * 1.15;
				Color from_colour = with_alpha(tone.darkened(0.2f), sway);
				Color tip_colour = with_alpha(mix(g->leaf_tip, tone, 0.3), std::min(sway + LEAF_SWAY, 1.0));
				Vector2 mark((real_t)pin_dice, (real_t)(4.0 + rows * 0.01));
				for (int s = 0; s < 2; s++) {
					double sign_side = s == 0 ? -1.0 : 1.0;
					Vector3 dir = (side * (real_t)(sign_side * 0.9) + tangent * 0.5f + DOWN * 0.45f).normalized();
					Vector3 out_a = a + dir * (real_t)size_a;
					Vector3 out_c = c + dir * (real_t)size_c;
					b->tri_uv(a, c, out_c, from_colour, from_colour, tip_colour, Vector2(0, (real_t)t),
							Vector2(0, (real_t)t2), Vector2(1, (real_t)t2), mark);
					b->tri_uv(a, out_c, out_a, from_colour, tip_colour, tip_colour, Vector2(0, (real_t)t),
							Vector2(1, (real_t)t2), Vector2(1, (real_t)t), mark);
				}
				continue;
			}
			int leaflets = g->leaflet >= 0.02 ? (fine ? 5 : 3) - lod : 0;
			for (int leaf_index = 0; leaf_index < leaflets; leaf_index++) {
				double u = (leaf_index + 0.5) / leaflets;
				Vector3 at = a.lerp(c, (real_t)u);
				double shape = pow(sin(PI_D * clampd(t + u / segments, 0.05, 0.98)), 0.7);
				double size = length * g->leaflet * shape * rr(0.85, 1.1);
				double step_len = (c - a).length() / leaflets;
				for (int s = 0; s < 2; s++) {
					double sign_side = s == 0 ? -1.0 : 1.0;
					Vector3 dir = (side * (real_t)(sign_side * 0.9) + tangent * 0.5f + DOWN * 0.45f).normalized();
					Color from_colour = with_alpha(tone.darkened(0.2f), sway);
					Color tip_colour = with_alpha(mix(g->leaf_tip, tone, 0.3), std::min(sway + LEAF_SWAY, 1.0));
					if (fine && low_plant && !outline.empty()) {
						Vector3 up = (UP - dir * dir.dot(UP)).normalized();
						add_leaf(*b, outline, at, dir, up, size * 1.25, 0.08, -0.06, from_colour, tip_colour, 0.0, 0.0,
								rr(0.9, 1.2), Vector2((real_t)rf(), (real_t)rf()));
						continue;
					}
					b->tri(at, at + tangent * (real_t)step_len, at + dir * (real_t)size + tangent * (real_t)(step_len * 0.5),
							from_colour, from_colour, tip_colour);
				}
			}
		}
		if (g->flower.a > 0.0f) {
			bloom(points.back(), UP, g->flower_size, g->flower, g->flower_centre, g->petals, g->flower_cup, 0.9);
		}
	}

	void bloom(const Vector3 &at, const Vector3 &normal, double size, const Color &colour, const Color &centre,
			int petals, double cup, double sway) {
		if (full()) {
			return;
		}
		Vector3 u = normal.cross(UP);
		if (u.length_squared() < 0.01f) {
			u = normal.cross(RIGHT);
		}
		u = u.normalized();
		Vector3 v = normal.cross(u);
		Color inner = with_alpha(colour.darkened(0.12f), sway);
		Color outer = with_alpha(colour.lightened(0.12f), std::min(sway + 0.2, 1.0));
		Color middle = with_alpha(centre, sway);
		Vector3 heart = at + normal * (real_t)(size * 0.1);
		for (int index = 0; index < petals; index++) {
			double angle = TAU_D * index / petals;
			double next = TAU_D * (index + 1) / petals;
			Vector3 dir = u * (real_t)cos(angle) + v * (real_t)sin(angle);
			Vector3 side = v * (real_t)cos(angle) - u * (real_t)sin(angle);
			Vector3 base = at + dir * (real_t)(size * lerpd(0.2, 0.1, cup));
			Vector3 tip = at + dir * (real_t)(size * lerpd(1.0, 0.7, cup)) + normal * (real_t)(size * lerpd(0.35, 1.0, cup));
			b->tri(base + side * (real_t)(size * 0.24), base - side * (real_t)(size * 0.24), tip, inner, inner, outer);
			if (fine) {
				b->tri(heart, at + dir * (real_t)(size * 0.2),
						at + (u * (real_t)cos(next) + v * (real_t)sin(next)) * (real_t)(size * 0.2), middle, middle, middle);
			}
		}
	}

	void mass(const Vector3 &at, double sway) {
		if (g->foliage_mass <= 0.0 || (lod > 0 && !cards) || full() || rf() > g->foliage_mass) {
			return;
		}
		double size = leaf_length * g->mass_size * rr(1.4, 2.2);
		Color tone = mix(g->leaf, g->leaf_tip, rf() * 0.5).darkened((float)rr(0.0, 0.2));
		Color low = with_alpha(tone.darkened(0.3f), sway);
		Color high = with_alpha(tone, std::min(sway + LEAF_SWAY, 1.0));
		Color middle = with_alpha(tone.darkened(0.12f), std::min(sway + 0.2, 1.0));
		if (cards) {
			Vector3 heart = at + Vector3(0, (real_t)(size * 0.2), 0);
			double turn = rf() * TAU_D;
			for (int card = 0; card < 3; card++) {
				double around = turn + TAU_D * card / 3.0;
				Vector3 flat((real_t)cos(around), 0, (real_t)sin(around));
				Vector3 tilt_dir = (flat * 0.75f + UP * 0.55f).normalized();
				Vector3 facing = card != 1 ? UP.cross(flat).normalized() : flat.cross(UP).normalized();
				add_leaf_card(*b, heart - tilt_dir * (real_t)(size * 0.7), tilt_dir, facing, size * 1.5, low, high, rf());
			}
			return;
		}
		Vector3 centre = at + Vector3(0, (real_t)(size * 0.25), 0);
		Vector3 axes[3] = { RIGHT, UP * 0.35f, Vector3(0, 0, 1) };
		Vector3 ends[3][2];
		for (int axis = 0; axis < 3; axis++) {
			for (int s = 0; s < 2; s++) {
				double sign_side = s == 0 ? 1.0 : -1.0;
				Vector3 jitter((real_t)rr(-0.35, 0.35), (real_t)rr(-0.2, 0.2), (real_t)rr(-0.35, 0.35));
				ends[axis][s] = centre + (axes[axis] * (real_t)sign_side + jitter) * (real_t)size;
			}
		}
		for (int sx = 0; sx < 2; sx++) {
			for (int sy = 0; sy < 2; sy++) {
				for (int sz = 0; sz < 2; sz++) {
					const Vector3 &cx = ends[0][sx];
					const Vector3 &cy = ends[1][sy];
					const Vector3 &cz = ends[2][sz];
					bool flip = (sx + sy + sz) % 2 == 1;
					const Color &a_color = sy == 0 ? high : low;
					if (flip) {
						b->tri(cy, cx, cz, a_color, middle, middle);
					} else {
						b->tri(cy, cz, cx, a_color, middle, middle);
					}
				}
			}
		}
	}

	Vector3 outward(const Vector3 &tangent, double azimuth) const {
		Vector3 side = tangent.cross(UP);
		if (side.length_squared() < 0.0001f) {
			side = tangent.cross(RIGHT);
		}
		return rotate_about(side.normalized(), tangent, azimuth);
	}

	static Vector3 point_along(const std::vector<Vector3> &points, double along) {
		double scaled = along * (points.size() - 1);
		int index = std::min((int)scaled, (int)points.size() - 2);
		return points[index].lerp(points[index + 1], (real_t)(scaled - index));
	}
	static Vector3 tangent_along(const std::vector<Vector3> &tangents, double along) {
		double scaled = along * (tangents.size() - 1);
		int index = std::min((int)scaled, (int)tangents.size() - 2);
		return tangents[index].lerp(tangents[index + 1], (real_t)(scaled - index)).normalized();
	}

	void blossoms(const std::vector<Vector3> &points, const std::vector<Vector3> &tangents, double sway) {
		if (g->blossom.a <= 0.0f || rf() > g->blossom_density) {
			return;
		}
		double size = g->blossom_size * rr(0.8, 1.2);
		Vector3 tip = points.back();
		Vector3 tangent = tangents.back();
		Color colour = mix(g->blossom, g->blossom.lightened(0.15f), rf());
		double bloom_sway = std::min(sway + 0.3, 1.0);
		if (g->blossom_kind == RACEME) {
			Vector3 hang = (tangent * 0.35f + DOWN * 0.65f).normalized();
			double length = size * 8.0;
			int count = fine ? 6 : 4;
			Color green = with_alpha(g->leaf.darkened(0.2f), sway);
			Color green_tip = with_alpha(green, std::min(sway + 0.3, 1.0));
			Vector3 side = outward(hang, rf() * TAU_D) * (real_t)(size * 0.07);
			b->tri(tip - side, tip + side, tip + hang * (real_t)length, green, green, green_tip);
			for (int index = 0; index < count; index++) {
				double t = (index + 0.5) / count;
				Vector3 out = outward(hang, index * GOLDEN_ANGLE);
				bloom(tip + hang * (real_t)(length * t) + out * (real_t)(size * 0.5), (out * 0.9f + UP * 0.2f).normalized(),
						size * (1.0 - 0.4 * t), colour, g->flower_centre, g->petals, g->flower_cup, bloom_sway);
			}
		} else if (g->blossom_kind == UMBEL) {
			Vector3 middle = tip + (tangent * 0.3f + UP * 0.5f).normalized() * (real_t)(size * 1.4);
			for (int index = 0; index < 5; index++) {
				Vector3 out = outward(UP, index * GOLDEN_ANGLE * 2.0);
				bloom(middle + out * (real_t)(size * 1.1), (out * 0.6f + UP).normalized(), size * 0.9, colour,
						g->flower_centre, g->petals, g->flower_cup, bloom_sway);
			}
		} else {
			for (int index = 0; index < 3; index++) {
				Vector3 at = point_along(points, 0.4 + 0.3 * index);
				Vector3 out = outward(tangent, rf() * TAU_D);
				bloom(at + out * (real_t)(size * 0.4), (out * 0.6f + UP * 0.6f).normalized(), size, colour,
						g->flower_centre, g->petals, g->flower_cup, bloom_sway);
			}
		}
	}

	void whorls() {
		double first = height * g->nodes_from;
		double last = height * 0.94;
		double spacing = std::max(g->nodes_spacing, 0.1) * (1.0 + 0.8 * lod) / thrift;
		int tiers = std::max((int)((last - first) / spacing), 5);
		double phase = rf() * TAU_D;
		for (int tier = 0; tier < tiers; tier++) {
			double along = (double)tier / (tiers - 1);
			double y = lerpd(first, last, pow(along, 0.92));
			double reach = lerpd(g->crown, g->crown * 0.1, pow(along, 0.9)) * rr(0.94, 1.06);
			int count = g->limbs + (along < 0.6 ? 1 : 0) + (fine ? 1 : 0) - lod;
			count = std::max((int)std::lround(count * thrift), 3);
			phase += 1.9;
			for (int index = 0; index < count; index++) {
				double yaw = phase + TAU_D * index / count + rr(-0.2, 0.2);
				Vector3 out((real_t)cos(yaw), 0, (real_t)sin(yaw));
				double below = lerpd(-0.1, 0.55, g->droop) * (1.0 - 0.7 * along);
				Vector3 dir = (out * (real_t)cos(below) + DOWN * (real_t)sin(below)).normalized();
				double radius = trunk_radius(y / trunk_length) * 0.45;
				Vector3 start = axis_at(y) - dir * (real_t)(radius * 0.5);
				branch(start, dir, reach, radius, 0, 0.0, false);
			}
		}
		if (g->foliage == NEEDLE) {
			Vector3 top = axis_at(height);
			for (int index = 0; index < 4; index++) {
				double yaw = TAU_D * index / 4.0 + rf() * 0.5;
				Vector3 out((real_t)cos(yaw), 0, (real_t)sin(yaw));
				spray(top - Vector3(0, 0.1f, 0), (out * 0.5f + UP * 0.8f).normalized(), needle_length * 0.9, 0.55);
			}
		}
	}

	Vector3 steer_clear(const Vector3 &spot, const Vector3 &heading, double radius, int my_id, int parent) {
		Vector3 push;
		for (size_t index = 0; index < solid_points.size(); index++) {
			int id = solid_ids[index];
			if (id == my_id || id == parent) {
				continue;
			}
			Vector3 away = spot - solid_points[index];
			double wanted = radius + solid_radii[index] + 0.1;
			double distance = away.length();
			if (distance < wanted && distance > 0.001) {
				push += away / (real_t)distance * (real_t)((wanted - distance) / wanted);
			}
		}
		if (push == Vector3()) {
			return heading;
		}
		return (heading + push * 1.5f).normalized();
	}

	void branch(const Vector3 &start, const Vector3 &dir, double length, double radius, int level, double sway,
			bool continues) {
		if (full()) {
			return;
		}
		int my_id = next_id++;
		int parent = parent_id;
		int rings = std::max(g->rings[level] - (level < 2 ? 1 : 0) * lod, 2);
		std::vector<Vector3> points = { start };
		std::vector<Vector3> tangents = { dir };
		Vector3 heading = dir;
		double arc = g->curve[level];
		Vector3 bend_axis = outward(dir, rf() * TAU_D);
		if (level == 0 && g->limb_angle > 65.0) {
			bend_axis = (bend_axis * 0.3f + UP).normalized();
		}
		double bend = arc * rr(0.35, 1.0);
		if (rf() < 0.5) {
			bend = -bend;
		}
		double wave_phase = rf() * TAU_D;
		double wave_count = rr(1.0, 2.2);
		double ground = radius * 0.7;
		for (int ring = 0; ring < rings - 1; ring++) {
			if (arc > 0.0) {
				double turn = bend / (rings - 1);
				if (g->twist > 0.0) {
					double wave = sin(wave_phase + wave_count * TAU_D * ring / (rings - 1));
					turn *= (1.0 - g->twist) + g->twist * 2.0 * wave;
				}
				heading = rotate_about(heading, bend_axis, turn);
				if (g->twist > 0.0) {
					bend_axis = rotate_about(bend_axis, heading, g->twist * 0.3);
				}
			}
			Vector3 wander((real_t)rr(-1, 1), (real_t)rr(-0.4, 0.6), (real_t)rr(-1, 1));
			double sagging = g->sag[level] + g->droop * g->droop_sag[level];
			heading = (heading + wander * (real_t)g->wander[level] + UP * (real_t)g->lift[level] + DOWN * (real_t)sagging).normalized();
			Vector3 next = points[ring] + heading * (real_t)(length / (rings - 1));
			if (g->avoid && level < 2) {
				double here = lerpd(radius, radius * g->tip_radius[level], (double)(ring + 1) / (rings - 1));
				if (ring >= 1) {
					heading = steer_clear(next, heading, here, my_id, parent);
					next = points[ring] + heading * (real_t)(length / (rings - 1));
				}
				solid_points.push_back(next);
				solid_radii.push_back(here);
				solid_ids.push_back(my_id);
			}
			if (next.y < ground && level < 2) {
				next.y = (real_t)ground;
				heading = Vector3(heading.x, std::max(heading.y, (real_t)0), heading.z).normalized();
			}
			points.push_back(next);
			tangents.push_back(heading);
		}
		std::vector<double> radii;
		std::vector<Color> colors;
		for (int ring = 0; ring < rings; ring++) {
			double along = (double)ring / (rings - 1);
			radii.push_back(lerpd(radius, radius * g->tip_radius[level], along));
			Color bark = g->bark.lightened((float)(0.04 * level)).darkened((float)(0.12 * (1.0 - along)));
			colors.push_back(Color(bark.r, bark.g, bark.b, (float)(sway + g->sway[level] * along)));
		}
		int sides_level = continues ? level - 1 : level;
		int sides = fine ? g->sides_real[sides_level] : g->sides[sides_level];
		sides = std::max(sides - 3 * lod, 3);
		bool last_level = level == depth - 1;
		int closed = (last_level || !g->carry_on) ? CAP_TOP : 0;
		b->tube(points, radii, colors, sides, *rng, 0.0, closed, false, 0, std::vector<double>());
		double tip_sway = sway + g->sway[level];
		if (g->foliage == NEEDLE && (last_level || !g->tips_only)) {
			Vector3 tip_tangent = tangents.back();
			if (g->tips_only) {
				tip_tangent = (tip_tangent * 0.35f + UP * 0.9f).normalized();
			}
			spray(points.back(), tip_tangent, needle_length * (level == 0 ? 1.0 : 0.8), tip_sway);
			if (level == 0 && !g->tips_only) {
				spray(point_along(points, 0.55), tangent_along(tangents, 0.55), needle_length * 0.8,
						sway + g->sway[0] * 0.55);
			}
		}
		if (last_level) {
			if (g->foliage == BLADE) {
				leaves_along(points, tangents, sway, level);
			}
			return;
		}
		parent_id = my_id;
		children(points, tangents, length, radius, level, sway);
		parent_id = parent;
	}

	void children(const std::vector<Vector3> &points, const std::vector<Vector3> &tangents, double length,
			double radius, int level, double sway) {
		int total = std::max(g->children[level] - lod, std::min(g->children[level], 2));
		if (g->crown > 3.5 && !(g->avoid && level == 1)) {
			total += std::min((int)(length / 3.5), 4);
		}
		total = std::max((int)std::lround(total * thrift), std::min(total, 2));
		int spread = total - (g->carry_on ? 1 : 0);
		for (int index = 0; index < total; index++) {
			bool leader = g->carry_on && index == total - 1;
			double f = 1.0;
			if (!leader) {
				f = g->children_from + (g->children_to - g->children_from) * index / (double)std::max(spread - 1, 1);
			}
			Vector3 at = point_along(points, f);
			Vector3 tangent = tangent_along(tangents, f);
			Vector3 out = outward(tangent, index * GOLDEN_ANGLE + level * 1.3);
			if (g->children_planar) {
				out = tangent.cross(UP).normalized() * (index % 2 == 0 ? 1.0f : -1.0f);
			}
			double local_radius = lerpd(radius, radius * g->tip_radius[level], f);
			double child_sway = sway + g->sway[level] * f;
			if (leader) {
				Vector3 on = (tangent * 0.95f + out * 0.25f + UP * 0.05f).normalized();
				branch(at, on, length * 0.5, local_radius, level + 1, child_sway, true);
				continue;
			}
			Vector3 child_dir = (tangent * (real_t)g->child_forward + out * (real_t)g->child_side + UP * (real_t)g->child_up).normalized();
			double child_length = length * g->child_length[level] * (g->child_length_a - g->child_length_b * f);
			double buried = local_radius * g->bury;
			branch(at - child_dir * (real_t)buried, child_dir, child_length + buried,
					local_radius * g->child_radius * (level == 1 ? g->twig_radius : 1.0), level + 1, child_sway, false);
		}
	}

	void leaves_along(const std::vector<Vector3> &points, const std::vector<Vector3> &tangents, double sway, int level) {
		blossoms(points, tangents, sway);
		mass(points.back(), sway);
		int nodes = std::max((int)std::lround((fine ? 5 : (4 - lod)) * thrift), 2);
		if (g->crown > 3.5) {
			nodes += 1;
		}
		if (g->leaf_density < 1.0) {
			if (rf() > g->leaf_density) {
				return;
			}
			nodes = std::max((int)std::lround(nodes * g->leaf_density), 2);
		}
		double gain = g->sway[level];
		for (int node = 0; node < nodes; node++) {
			double along = 0.3 + 0.65 * node / (double)(nodes - 1);
			Vector3 at = point_along(points, along);
			Vector3 tangent = tangent_along(tangents, along);
			double here = sway + gain * along;
			switch (g->leaf_pattern) {
				case OPPOSITE:
					leaf(at, tangent, 0.0, here, 0.7);
					leaf(at, tangent, PI_D, here, 0.7);
					break;
				case SPIRAL:
					leaf(at, tangent, node * GOLDEN_ANGLE, here, 0.7);
					break;
				default:
					leaf(at, tangent, PI_D * (node % 2), here, 0.7);
			}
		}
		leaf(points.back(), tangents.back(), 0.0, sway + gain, 0.0);
	}

	void leaf(const Vector3 &at, const Vector3 &tangent, double azimuth, double sway, double spread) {
		if (b->leafless || full()) {
			return;
		}
		Vector3 out = outward(tangent, azimuth);
		Vector3 axis = (tangent * 0.6f + out * (real_t)spread + UP * 0.15f).normalized();
		Vector3 normal = UP - axis * axis.dot(UP);
		normal = normal.length_squared() < 0.01f ? out : normal.normalized();
		normal = normal * 0.8f + out * 0.2f;
		normal = (normal - axis * axis.dot(normal)).normalized();
		Color tone = mix(g->leaf, g->leaf.lightened(0.14f), rf());
		tone = tone.darkened((float)rr(0.0, 0.18));
		Color base_color = with_alpha(tone.darkened(0.3f), sway);
		Color tip_color = with_alpha(mix(g->leaf_tip, tone, 0.4), std::min(sway + LEAF_SWAY, 1.0));
		double curl = fine ? -0.12 : 0.0;
		double share = clampd(g->leaf_aspect * 0.5, 0.5, 2.0);
		double size = leaf_length * lerpd(0.6, 1.5, pow(rf(), 1.2));
		if (g->compound) {
			feather(at, axis, normal, size * 1.6, base_color, tip_color);
			return;
		}
		if (cards && !g->compound) {
			add_leaf_card(*b, at, axis, normal, size * 1.35, base_color, tip_color, rf());
			return;
		}
		add_leaf(*b, outline, at, axis, normal, size, 0.1, curl, base_color, tip_color, rr(-0.2, 0.2),
				rr(-0.14, 0.14) * share, rr(0.8, 1.2), Vector2((real_t)rf(), (real_t)rf()));
	}

	void feather(const Vector3 &at, const Vector3 &axis, const Vector3 &normal, double length,
			const Color &base_color, const Color &tip_color) {
		Vector3 across = axis.cross(normal).normalized();
		if (cards) {
			// realistic: the leaflets of a feather leaf as one strip each side of its stalk, drawn by the shader
			Vector3 stalk_to = at + axis * (real_t)length;
			double rows = clampd(length / 0.045, 6.0, 20.0);
			Vector2 mark((real_t)rf(), (real_t)(4.0 + rows * 0.01));
			for (int s = 0; s < 2; s++) {
				Vector3 way = (across * (real_t)(s == 0 ? -0.9 : 0.9) + axis * 0.45f + normal * 0.15f).normalized();
				Vector3 out_a = at + way * (real_t)(length * 0.26);
				Vector3 out_c = stalk_to + way * (real_t)(length * 0.1);
				b->tri_uv(at, stalk_to, out_c, base_color, tip_color, tip_color, Vector2(0, 0), Vector2(0, 1),
						Vector2(1, 1), mark);
				b->tri_uv(at, out_c, out_a, base_color, tip_color, base_color, Vector2(0, 0), Vector2(1, 1),
						Vector2(1, 0), mark);
			}
			return;
		}
		int pairs = fine ? 4 : 3;
		Vector3 stalk_end = at + axis * (real_t)length;
		Vector3 stalk = across * (real_t)(length * 0.02);
		b->tri(at - stalk, at + stalk, stalk_end, base_color, base_color, tip_color);
		double leaflet = 0;
		for (int index = 0; index < pairs; index++) {
			double t = (index + 0.6) / pairs;
			Vector3 on = at + axis * (real_t)(length * t);
			leaflet = length * 0.3 * (1.0 - 0.45 * t);
			Color color = mix(base_color, tip_color, t);
			for (int s = 0; s < 2; s++) {
				double sign_side = s == 0 ? -1.0 : 1.0;
				Vector3 way = (across * (real_t)(sign_side * 0.9) + axis * 0.45f + normal * 0.15f).normalized();
				if (fine) {
					Vector3 up = (normal - way * way.dot(normal)).normalized();
					add_leaf(*b, outline, on, way, up, leaflet * 1.5, 0.1, -0.1, color, tip_color, rr(-0.15, 0.15), 0.0,
							rr(0.9, 1.3), Vector2((real_t)rf(), (real_t)rf()));
					continue;
				}
				Vector3 reach = on + way * (real_t)leaflet;
				b->tri(on, on + axis * (real_t)(leaflet * 0.5), reach, color, color, tip_color);
			}
		}
		double wide = length * 0.07;
		b->tri(stalk_end - across * (real_t)wide, stalk_end + across * (real_t)wide,
				stalk_end + axis * (real_t)(length * 0.22), tip_color, tip_color, tip_color);
	}

	void spray(const Vector3 &base, const Vector3 &axis, double length, double sway) {
		if (b->leafless || full()) {
			return;
		}
		int count = fine ? 11 : (9 - 3 * lod);
		Vector3 side = axis.cross(UP);
		if (side.length_squared() < 0.0001f) {
			side = axis.cross(RIGHT);
		}
		side = side.normalized();
		Vector3 up = side.cross(axis).normalized();
		Color tone = mix(g->leaf, g->leaf.lightened(0.1f), rf());
		Color tip_color = g->frosted ? Color(0.93f, 0.95f, 0.98f) : mix(g->leaf_tip, tone, 0.3);
		Color base_color = with_alpha(tone.darkened(0.25f), sway);
		tip_color.a = (float)std::min(sway + NEEDLE_SWAY, 1.0);
		if (cards) {
			// realistic: three feathery branchlets (the shader draws the needles on a strip along each, UV2.y
			// 6 + rows / 100), the one along the spray and one turned each way, the outer ones a little shorter
			double dice = rf();
			Vector2 mark((real_t)dice, (real_t)(6.0 + 14.0 * 0.01));
			for (int k = -1; k <= 1; k++) {
				double turn = k * 0.6 + rr(-0.1, 0.1);
				double lift = rr(-0.05, 0.3);
				Vector3 dir = (axis * (real_t)cos(turn) + side * (real_t)sin(turn) + up * (real_t)lift).normalized();
				double reach = length * rr(0.85, 1.1) * (k == 0 ? 1.0 : 0.82);
				Vector3 across = dir.cross(up).normalized() * (real_t)(reach * 0.34);
				Vector3 tip = base + dir * (real_t)reach + DOWN * (real_t)(reach * 0.08);
				for (int s = 0; s < 2; s++) {
					Vector3 spread = across * (real_t)(s == 0 ? -1.0 : 1.0);
					Vector3 out_base = base + spread * 0.5f;
					Vector3 out_tip = tip + spread * 0.55f;
					b->tri_uv(base, tip, out_tip, base_color, tip_color, tip_color, Vector2(0, 0), Vector2(0, 1),
							Vector2(1, 1), mark);
					b->tri_uv(base, out_tip, out_base, base_color, tip_color, base_color, Vector2(0, 0), Vector2(1, 1),
							Vector2(1, 0), mark);
				}
			}
			return;
		}
		double width = length * 0.1;
		for (int index = 0; index < count; index++) {
			double fan = ((double)index / (count - 1) - 0.5) * 2.0;
			double angle = fan * 0.95;
			double lift = rr(-0.12, 0.28);
			Vector3 dir = (axis * (real_t)cos(angle) + side * (real_t)sin(angle) + up * (real_t)lift).normalized();
			double needle = length * rr(0.75, 1.15) * (1.0 - 0.25 * std::abs(fan));
			Vector3 near_point = base + dir * (real_t)(needle * 0.12);
			Vector3 sideways = dir.cross(up).normalized() * (real_t)width;
			b->tri(near_point - sideways, near_point + sideways, base + dir * (real_t)needle, base_color, base_color,
					tip_color);
		}
	}
};

// MeshBuilder._smoothed_normals: the vertex normals of the realistic look
struct CellKey {
	int x, y, z;
	bool operator==(const CellKey &o) const { return x == o.x && y == o.y && z == o.z; }
};
struct CellHash {
	size_t operator()(const CellKey &k) const {
		return (size_t)(k.x * 73856093) ^ (size_t)(k.y * 19349663) ^ (size_t)(k.z * 83492791);
	}
};

std::vector<Vector3> smoothed_normals(const MeshData &m) {
	const float SMOOTH_ANGLE = 0.5f;
	size_t count = m.vertices.size();
	std::unordered_map<CellKey, std::vector<int>, CellHash> cells;
	cells.reserve(count);
	std::vector<CellKey> keys(count);
	for (size_t i = 0; i < count; i++) {
		keys[i] = { (int)std::lround(m.vertices[i].x * 100.0), (int)std::lround(m.vertices[i].y * 100.0),
			(int)std::lround(m.vertices[i].z * 100.0) };
		cells[keys[i]].push_back((int)i);
	}
	std::vector<Vector3> smooth(count);
	for (size_t i = 0; i < count; i++) {
		Vector3 total;
		for (int other : cells[keys[i]]) {
			if (m.normals[other].dot(m.normals[i]) > SMOOTH_ANGLE) {
				total += m.normals[other];
			}
		}
		smooth[i] = total.length_squared() > 0.0001f ? total.normalized() : m.normals[i];
	}
	return smooth;
}

} // namespace

void PlantMeshNative::_bind_methods() {
	ClassDB::bind_method(D_METHOD("grow", "genome", "seed", "detailed", "leafless", "lod", "leaf_cards"),
			&PlantMeshNative::grow);
	ClassDB::bind_method(D_METHOD("scenery", "kind", "variant", "detailed"), &PlantMeshNative::scenery);
	ClassDB::bind_method(D_METHOD("far_tree", "species", "seed"), &PlantMeshNative::far_tree);
	ClassDB::bind_method(D_METHOD("mushroom", "species", "seed", "detailed"), &PlantMeshNative::mushroom);
}

namespace {

// The arrays of a finished mesh: vertices, the smoothed normals, colours and (for leaves) UVs
Dictionary package(const MeshData &mesh, bool capped) {
	size_t count = mesh.vertices.size();
	PackedVector3Array vertices, normals;
	PackedColorArray colors;
	PackedVector2Array uvs, uv2s;
	vertices.resize(count);
	normals.resize(count);
	colors.resize(count);
	std::vector<Vector3> smooth = smoothed_normals(mesh);
	for (size_t i = 0; i < count; i++) {
		vertices[i] = mesh.vertices[i];
		normals[i] = smooth[i];
		colors[i] = mesh.colors[i];
	}
	if (mesh.has_uv) {
		uvs.resize(count);
		uv2s.resize(count);
		for (size_t i = 0; i < count; i++) {
			uvs[i] = mesh.uvs[i];
			uv2s[i] = mesh.uv2s[i];
		}
	}
	Dictionary result;
	result["vertices"] = vertices;
	result["normals"] = normals;
	result["colors"] = colors;
	result["uvs"] = uvs;
	result["uv2s"] = uv2s;
	result["capped"] = capped;
	result["triangles"] = (int)(count / 3);
	return result;
}

const int KIND_ROCK = 5, KIND_STUMP = 10, KIND_LOG = 14, KIND_SPIRE = 15, KIND_PEBBLES = 16, KIND_LITTER = 17, KIND_TWIGS = 18;
const Color BARK(0.33f, 0.23f, 0.15f);
const Color BARK_DARK(0.22f, 0.15f, 0.1f);

Color scaled(const Color &c, double k) { return Color((float)(c.r * k), (float)(c.g * k), (float)(c.b * k), c.a); }

} // namespace

// The scenery that is not a plant (FloraMeshes._build): rocks, pebbles, stumps, logs, spires, fallen leaves and sticks
Dictionary PlantMeshNative::scenery(int p_kind, int p_variant, bool p_detailed) const {
	Rng rng;
	rng.seed((uint64_t)((int64_t)p_kind * 7919 + (int64_t)p_variant * 104729 + 17));
	MeshData m;
	m.detailed = p_detailed;
	switch (p_kind) {
		case KIND_ROCK: {
			double tone = rng.randf();
			Color stone = Color(0.33f, 0.32f, 0.31f).lerp(Color(0.47f, 0.44f, 0.4f), (float)tone);
			if (p_variant == 5) {
				stone = Color(0.52f, 0.38f, 0.3f);
			}
			Color low = still(stone.darkened(0.25f)), high = still(stone.lightened(0.1f));
			double stretch = rng.range(0.9, 1.15);
			m.rock(Vector3(0, 0.25f, 0), Vector3(1.0f, 0.85f, 0.85f) * (real_t)stretch, low, high, rng, 6 + p_variant % 3);
			if (p_variant % 2 == 1) {
				m.rock(Vector3(0.7f, 0.1f, 0.4f), Vector3(0.5f, 0.4f, 0.45f), low, high, rng, 5);
			}
			break;
		}
		case KIND_PEBBLES: {
			const Color tones[4] = { Color(0.5f, 0.48f, 0.45f), Color(0.38f, 0.36f, 0.35f), Color(0.6f, 0.55f, 0.47f), Color(0.45f, 0.37f, 0.3f) };
			Color stone = tones[p_variant % 4];
			int count = 3 + p_variant % 3;
			for (int index = 0; index < count; index++) {
				double size = rng.range(0.07, 0.17);
				double x = rng.range(-0.4, 0.4), z = rng.range(-0.4, 0.4);
				Vector3 at((real_t)x, (real_t)(size * 0.3), (real_t)z);
				double shade = rng.range(0.85, 1.1);
				m.blob(at, Vector3((real_t)size, (real_t)(size * 0.6), (real_t)(size * 0.85)), still(scaled(stone.darkened(0.2f), shade)),
						still(scaled(stone.lightened(0.08f), shade)), rng, 0.25);
			}
			break;
		}
		case KIND_STUMP: {
			double height = rng.range(0.5, 0.9);
			m.frustum(Vector3(), height, 0.42, 0.34, 7, still(BARK_DARK), still(BARK), CAP_TOP, &rng, 0.1);
			break;
		}
		case KIND_LOG: {
			double length = rng.range(2.5, 4.5);
			Color wood(0.4f, 0.3f, 0.22f);
			m.place(Transform3D(Basis(Vector3(0, 0, 1), (real_t)(PI_D * 0.5)), Vector3((real_t)(-length * 0.5), 0.3f, 0)));
			m.frustum(Vector3(), length, 0.3, 0.26, 7, still(wood), still(wood.lightened(0.08f)), CAP_TOP | CAP_BOTTOM, &rng, 0.06);
			m.unplace();
			break;
		}
		case KIND_SPIRE: {
			Color stone = Color(0.42f, 0.4f, 0.4f).lerp(Color(0.6f, 0.55f, 0.5f), (float)(p_variant / 3.0));
			double height = rng.range(4.0, 8.0);
			double r0 = rng.range(1.0, 1.6), r1 = rng.range(0.1, 0.35);
			m.frustum(Vector3(), height, r0, r1, 5, still(stone.darkened(0.25f)), still(stone.lightened(0.1f)), 0, &rng, 0.22);
			if (p_variant != 1) {
				m.frustum(Vector3(1.1f, 0, 0.5f), height * 0.5, 0.8, 0.12, 5, still(stone.darkened(0.2f)), still(stone), 0, &rng, 0.2);
			}
			break;
		}
		case KIND_LITTER: {
			const Color tones[5] = { Color(0.55f, 0.36f, 0.14f), Color(0.42f, 0.3f, 0.14f), Color(0.62f, 0.45f, 0.16f), Color(0.34f, 0.4f, 0.14f),
				Color(0.5f, 0.22f, 0.1f) };
			Color tone = tones[p_variant % 5];
			const int shapes[4] = { OVAL, LOBED, HEART, LANCEOLATE };
			double aspect = rng.range(1.5, 2.2);
			std::vector<Vector2> outline = leaf_outline(shapes[p_variant % 4], aspect, 2, SMOOTH, true);
			int count = 12 + p_variant * 2;
			for (int index = 0; index < count; index++) {
				double angle = rng.randf() * TAU_D;
				double reach = 0.55 * std::sqrt(rng.randf());
				double yaw = rng.randf() * TAU_D;
				Vector3 axis((real_t)std::cos(yaw), (real_t)rng.range(0.0, 0.18), (real_t)std::sin(yaw));
				axis = axis.normalized();
				Vector3 normal = (UP - axis * axis.dot(UP)).normalized();
				double shade = rng.range(0.7, 1.15);
				Color colour = scaled(tone.lerp(Color(0.3f, 0.2f, 0.1f), (float)(rng.randf() * 0.5)), shade);
				colour.a = 0.0f;
				double length = rng.range(0.11, 0.24);
				double width = rng.range(0.9, 1.2);
				Vector2 dice((real_t)rng.randf(), (real_t)rng.randf());
				add_leaf(m, outline, Vector3((real_t)(std::cos(angle) * reach), (real_t)(0.012 + 0.006 * index), (real_t)(std::sin(angle) * reach)), axis,
						normal, length, 0.04, 0.05, colour.darkened(0.2f), colour, 0.0, 0.0, width, dice);
			}
			break;
		}
		case KIND_TWIGS: {
			Color wood = Color(0.36f, 0.28f, 0.2f).lerp(Color(0.5f, 0.44f, 0.38f), (float)(p_variant / 4.0));
			int count = 3 + p_variant % 3;
			for (int index = 0; index < count; index++) {
				double length = rng.range(0.35, 1.1);
				double radius = rng.range(0.012, 0.03);
				double yaw = rng.randf() * TAU_D;
				double tilt = rng.range(0.0, 0.2);
				double x = rng.range(-0.35, 0.35), z = rng.range(-0.35, 0.35);
				Vector3 at((real_t)x, (real_t)(radius * 0.8 + 0.02 * index), (real_t)z);
				Basis lie = Basis(UP, (real_t)yaw) * Basis(Vector3(0, 0, 1), (real_t)(-PI_D * 0.5 + tilt));
				m.place(Transform3D(lie, at));
				double shade = rng.range(0.85, 1.1);
				m.frustum(Vector3(), length, radius, radius * 0.45, 5, still(scaled(wood.darkened(0.15f), shade)), still(scaled(wood, shade)), CAP_BOTTOM, &rng, 0.08);
				if (index == 0) {
					m.place(Transform3D(lie * Basis(FORWARD, 0.6f), at + lie.xform(Vector3(0, (real_t)(length * 0.5), 0))));
					m.frustum(Vector3(), length * 0.5, radius * 0.6, radius * 0.25, 4, still(wood.darkened(0.1f)), still(wood), 0, &rng, 0.08);
				}
			}
			m.unplace();
			break;
		}
		default:
			break;
	}
	return package(m, false);
}

// The cheap horizon tree: one cone, or a trunk under a crown of four lumps (PlantTreeBuilders.far)
Dictionary PlantMeshNative::far_tree(const Dictionary &p_species, int64_t p_seed) const {
	Rng rng;
	rng.seed((uint64_t)p_seed);
	MeshData m;
	bool conifer = (bool)p_species.get("conifer", false);
	Color leaf = p_species.get("leaf", Color(0.26f, 0.5f, 0.18f));
	Color leaf_tip = p_species.get("leaf_tip", Color(0.4f, 0.6f, 0.25f));
	Color bark = p_species.get("bark", BARK);
	double height = p_species.get("height", 8.0), crown = p_species.get("crown", 2.0), aspect = p_species.get("aspect", 1.0);
	double bare = p_species.get("bare", 0.3), girth = p_species.get("girth", 0.3);
	if (conifer) {
		Color green = leaf.lerp(leaf_tip, 0.3f);
		double tall = height * rng.range(0.9, 1.1);
		m.frustum(Vector3(0, 0.8f, 0), tall, crown * 0.95, 0.0, 5, still(green.darkened(0.1f)), still(green.lightened(0.1f)), CAP_BOTTOM, &rng, 0.1);
		return package(m, false);
	}
	double trunk = height * bare;
	m.frustum(Vector3(), trunk, girth, girth * 0.6, 4, still(bark.darkened(0.3f)), still(bark), 0);
	double size = crown * 1.3;
	Vector3 middle(0, (real_t)(trunk + (height - trunk) * 0.55), 0);
	for (int lump = 0; lump < 4; lump++) {
		Vector3 offset((real_t)rng.range(-1.0, 1.0), (real_t)rng.range(-0.55, 0.65), (real_t)rng.range(-1.0, 1.0));
		double radius = size * rng.range(0.5, 0.72);
		double tone = rng.range(0.0, 0.18);
		m.blob(middle + Vector3((real_t)(offset.x * size * 0.55), (real_t)(offset.y * size * 0.45 * aspect), (real_t)(offset.z * size * 0.55)),
				Vector3((real_t)radius, (real_t)(radius * aspect * 0.8), (real_t)radius), still(leaf.darkened((float)(0.3 - tone))),
				still(leaf_tip.darkened((float)(tone * 0.5))), rng, 0.3);
	}
	return package(m, false);
}

// A clump of mushrooms (PlantGroundBuilders): each cap beside an earlier one, no two caps cutting into each other
Dictionary PlantMeshNative::mushroom(const Dictionary &p_species, int64_t p_seed, bool p_detailed) const {
	Rng rng;
	rng.seed((uint64_t)p_seed);
	MeshData m;
	m.detailed = p_detailed;
	double height0 = p_species.get("height", 0.3), crown = p_species.get("crown", 0.6), droop = p_species.get("droop", 0.3);
	int count = p_species.get("count", 3);
	Color accent = p_species.get("accent", Color(0.8f, 0.2f, 0.2f));
	struct Spot {
		double x, z, height, radius;
	};
	std::vector<Spot> spots;
	for (int index = 0; index < count; index++) {
		double height = height0 * rng.range(0.7, 1.2);
		double radius = height * crown;
		double x = 0.0, z = 0.0;
		if (index > 0) {
			bool found = false;
			for (int attempt = 0; attempt < 24 && !found; attempt++) {
				const Spot &beside = spots[rng.randi() % spots.size()];
				double angle = rng.randf() * TAU_D;
				double distance = radius + beside.radius + rng.range(0.04, 0.1);
				x = beside.x + std::cos(angle) * distance;
				z = beside.z + std::sin(angle) * distance;
				found = true;
				for (const Spot &other : spots) {
					if (std::sqrt((x - other.x) * (x - other.x) + (z - other.z) * (z - other.z)) < radius + other.radius + 0.03) {
						found = false;
						break;
					}
				}
			}
			if (!found) {
				continue;
			}
		}
		spots.push_back({ x, z, height, radius });
	}
	for (const Spot &spot : spots) {
		Vector3 at((real_t)spot.x, 0, (real_t)spot.z);
		m.frustum(at, spot.height, 0.035, 0.03, 5, still(Color(0.9f, 0.88f, 0.8f)), still(Color(0.92f, 0.9f, 0.84f)), 0);
		m.frustum(at + Vector3(0, (real_t)spot.height, 0), spot.height * lerpd(0.3, 0.9, droop), spot.height * crown, 0.02, 7,
				still(accent.darkened(0.15f)), still(accent), 0, &rng, 0.05);
	}
	return package(m, false);
}

Dictionary PlantMeshNative::grow(const Dictionary &p_genome, int64_t p_seed, bool p_detailed, bool p_leafless,
		int p_lod, bool p_leaf_cards) const {
	Genome genome;
	genome.read(p_genome);
	MeshData mesh;
	mesh.detailed = p_detailed;
	mesh.leafless = p_leafless;
	mesh.leaf_cards = p_leaf_cards;
	Rng rng;
	rng.seed((uint64_t)p_seed);
	uint64_t start = rng.state;
	bool capped = false;
	const double thrifts[] = { 1.0, 0.94, 0.88, 0.82, 0.76, 0.7, 0.6, 0.5, 0.4, 0.3, 0.2, 0.12 };
	for (double thrift : thrifts) {
		mesh.reset();
		rng.state = start;
		Genome g = genome; // a clump changes the numbers while it grows
		Grower grower;
		grower.g = &g;
		grower.b = &mesh;
		grower.rng = &rng;
		grower.lod = p_lod;
		grower.fine = p_detailed && p_lod == 0;
		grower.cards = p_detailed && p_leaf_cards;
		grower.depth = g.depth;
		grower.thrift = thrift;
		grower.budget = (int)clampd(1500.0 + 2000.0 * g.height, 1500, BUDGET);
		grower.grow();
		capped = grower.capped;
		if (!capped) {
			break;
		}
	}
	return package(mesh, capped);
}
