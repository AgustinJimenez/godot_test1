#include "planet_drainage_native.h"

#include <godot_cpp/core/class_db.hpp>

#include <algorithm>
#include <cmath>
#include <functional>
#include <queue>
#include <utility>
#include <vector>

using namespace godot;

namespace {
const double PI_VALUE = 3.14159265358979323846;
}

PackedFloat32Array PlanetDrainageNative::sample_grid(const PackedFloat32Array &p_grid, int p_width, int p_height,
		const PackedVector3Array &p_dirs) const {
	PackedFloat32Array out;
	out.resize(p_dirs.size());
	if (p_width <= 0 || p_height <= 0 || p_grid.size() < p_width * p_height) {
		return out;
	}
	const double pi = 3.14159265358979323846;
	for (int index = 0; index < p_dirs.size(); index++) {
		const Vector3 dir = p_dirs[index];
		const double lat = std::asin(std::max(-1.0, std::min(1.0, (double)dir.y)));
		const double lon = std::atan2((double)dir.z, (double)dir.x);
		const double fx = (lon + pi) / (2.0 * pi) * p_width - 0.5;
		const double fy = (0.5 - lat / pi) * p_height - 0.5;
		const int x0 = (int)std::floor(fx);
		const int y0 = (int)std::floor(fy);
		const double tx = fx - x0;
		const double ty = fy - y0;
		double value = 0.0;
		for (int dy = 0; dy < 2; dy++) {
			for (int dx = 0; dx < 2; dx++) {
				const double weight = (dx == 1 ? tx : 1.0 - tx) * (dy == 1 ? ty : 1.0 - ty);
				const int row = std::max(0, std::min(p_height - 1, y0 + dy));
				const int column = (((x0 + dx) % p_width) + p_width) % p_width;
				value += (double)p_grid[row * p_width + column] * weight;
			}
		}
		out.set(index, (float)value);
	}
	return out;
}

void PlanetDrainageNative::_bind_methods() {
	ClassDB::bind_method(D_METHOD("setup", "cells", "radius", "faces"), &PlanetDrainageNative::setup);
	ClassDB::bind_method(D_METHOD("sample_grid", "grid", "width", "height", "dirs"),
			&PlanetDrainageNative::sample_grid);
	ClassDB::bind_method(D_METHOD("cell_dirs"), &PlanetDrainageNative::cell_dirs);
	ClassDB::bind_method(D_METHOD("cell_areas"), &PlanetDrainageNative::cell_areas);
	ClassDB::bind_method(D_METHOD("cell_neighbours"), &PlanetDrainageNative::cell_neighbours);
	ClassDB::bind_method(D_METHOD("cell_of", "dir"), &PlanetDrainageNative::cell_of);
	ClassDB::bind_method(D_METHOD("cells_of", "dirs"), &PlanetDrainageNative::cells_of);
	ClassDB::bind_method(D_METHOD("carve", "heights", "filled", "flow", "receiver", "river_flow", "base_slope", "max_cut"),
			&PlanetDrainageNative::carve);
	ClassDB::bind_method(D_METHOD("river_network", "heights", "filled", "flow", "receiver", "river_flow",
					"base_slope", "samples", "meander", "uplift"),
			&PlanetDrainageNative::river_network);
	ClassDB::bind_method(D_METHOD("solve", "heights", "rain", "sea_level", "exponent", "lake_depth", "lake_cells"),
			&PlanetDrainageNative::solve);
}

// The cell that holds the unit direction (the inverse of the tiles' cube face mapping).
int PlanetDrainageNative::cell_at(const Vector3 &p_dir) const {
	double ax = std::abs((double)p_dir.x);
	double ay = std::abs((double)p_dir.y);
	double az = std::abs((double)p_dir.z);
	int face = 0;
	if (ax >= ay && ax >= az) {
		face = p_dir.x > 0 ? 0 : 1;
	} else if (ay >= az) {
		face = p_dir.y > 0 ? 2 : 3;
	} else {
		face = p_dir.z > 0 ? 4 : 5;
	}
	const Vector3 normal = cube_faces[face * 3];
	const Vector3 u = cube_faces[face * 3 + 1];
	const Vector3 v = cube_faces[face * 3 + 2];
	double along = p_dir.dot(normal);
	double s = std::atan((double)p_dir.dot(u) / along) * 4.0 / PI_VALUE;
	double t = std::atan((double)p_dir.dot(v) / along) * 4.0 / PI_VALUE;
	int i = (int)((s + 1.0) * 0.5 * cells);
	int j = (int)((t + 1.0) * 0.5 * cells);
	i = i < 0 ? 0 : (i > cells - 1 ? cells - 1 : i);
	j = j < 0 ? 0 : (j > cells - 1 ? cells - 1 : j);
	return (face * cells + j) * cells + i;
}

void PlanetDrainageNative::setup(int p_cells, double p_radius, const PackedVector3Array &p_faces) {
	cells = p_cells;
	radius = p_radius;
	cube_faces = p_faces;
	const int count = 6 * cells * cells;
	dirs.resize(count);
	areas.resize(count);
	neighbours.resize(count * 8);
	const double quarter_pi = PI_VALUE * 0.25;
	double total_area = 0.0;
	for (int face = 0; face < 6; face++) {
		const Vector3 normal = cube_faces[face * 3];
		const Vector3 u = cube_faces[face * 3 + 1];
		const Vector3 v = cube_faces[face * 3 + 2];
		for (int j = 0; j < cells; j++) {
			double t = -1.0 + 2.0 * ((double)j + 0.5) / (double)cells;
			double b = std::tan(t * quarter_pi);
			for (int i = 0; i < cells; i++) {
				double s = -1.0 + 2.0 * ((double)i + 0.5) / (double)cells;
				double a = std::tan(s * quarter_pi);
				const int id = (face * cells + j) * cells + i;
				dirs[id] = (normal + u * (real_t)a + v * (real_t)b).normalized();
				// the share of the sphere a cell of the equiangular cube map covers
				double area = (1.0 + a * a) * (1.0 + b * b) / std::pow(1.0 + a * a + b * b, 1.5);
				areas[id] = (float)area;
				total_area += area;
			}
		}
	}
	const double mean = total_area / (double)count;
	for (int id = 0; id < count; id++) {
		areas[id] = (float)((double)areas[id] / mean);
	}
	// the eight neighbours: by index inside a face, by direction across the edges
	static const int steps[8][2] = { { -1, -1 }, { 0, -1 }, { 1, -1 }, { -1, 0 }, { 1, 0 }, { -1, 1 }, { 0, 1 }, { 1, 1 } };
	for (int face = 0; face < 6; face++) {
		const Vector3 normal = cube_faces[face * 3];
		const Vector3 u = cube_faces[face * 3 + 1];
		const Vector3 v = cube_faces[face * 3 + 2];
		for (int j = 0; j < cells; j++) {
			for (int i = 0; i < cells; i++) {
				const int id = (face * cells + j) * cells + i;
				for (int n = 0; n < 8; n++) {
					int ni = i + steps[n][0];
					int nj = j + steps[n][1];
					int found = -1;
					if (ni >= 0 && ni < cells && nj >= 0 && nj < cells) {
						found = (face * cells + nj) * cells + ni;
					} else {
						// off the edge: the cell that holds the point a step beyond this one
						double s = -1.0 + 2.0 * ((double)ni + 0.5) / (double)cells;
						double t = -1.0 + 2.0 * ((double)nj + 0.5) / (double)cells;
						Vector3 beyond = (normal + u * (real_t)std::tan(s * quarter_pi) +
								v * (real_t)std::tan(t * quarter_pi))
												 .normalized();
						found = cell_at(beyond);
						if (found == id) {
							found = -1;
						}
					}
					neighbours[id * 8 + n] = found;
				}
			}
		}
	}
}

PackedInt32Array PlanetDrainageNative::cells_of(const PackedVector3Array &p_dirs) const {
	PackedInt32Array result;
	result.resize(p_dirs.size());
	for (int index = 0; index < p_dirs.size(); index++) {
		result[index] = cell_at(p_dirs[index]);
	}
	return result;
}

// Fills the hollows (Priority-Flood with an epsilon, Barnes 2014: from the sea inward, a cell is
// never lower than the cell it was reached from) and routes the rain down the filled ground, each
// cell sending its water to every lower neighbour in proportion to slope^exponent.
// Returns: filled (m), flow (rain x area passing through), receiver (the main next cell, -1 at
// the sea), lake (1 where the filled ground stands `lake_depth` above the real ground).
Dictionary PlanetDrainageNative::solve(const PackedFloat32Array &p_heights, const PackedFloat32Array &p_rain,
		double p_sea_level, double p_exponent, double p_lake_depth, int p_lake_cells) const {
	const int count = 6 * cells * cells;
	std::vector<double> filled(count, 0.0);
	std::vector<char> closed(count, 0);
	std::vector<int> order;
	order.reserve(count);
	typedef std::pair<double, int> Entry;
	std::priority_queue<Entry, std::vector<Entry>, std::greater<Entry>> queue;
	for (int id = 0; id < count; id++) {
		if ((double)p_heights[id] < p_sea_level) {
			filled[id] = p_heights[id];
			closed[id] = 1;
			queue.push(Entry(filled[id], id));
		}
	}
	const double epsilon = 1.0e-5;
	while (!queue.empty()) {
		Entry top = queue.top();
		queue.pop();
		const int id = top.second;
		order.push_back(id);
		for (int n = 0; n < 8; n++) {
			const int other = neighbours[id * 8 + n];
			if (other < 0 || closed[other]) {
				continue;
			}
			closed[other] = 1;
			double level = (double)p_heights[other];
			filled[other] = level > filled[id] + epsilon ? level : filled[id] + epsilon;
			queue.push(Entry(filled[other], other));
		}
	}
	// the water: from the highest cell down
	std::vector<double> water(count, 0.0);
	for (int id = 0; id < count; id++) {
		if ((double)p_heights[id] >= p_sea_level) {
			water[id] = (double)p_rain[id] * (double)areas[id];
		}
	}
	PackedInt32Array receiver;
	receiver.resize(count);
	for (int id = 0; id < count; id++) {
		receiver[id] = -1;
	}
	for (int at = (int)order.size() - 1; at >= 0; at--) {
		const int id = order[at];
		if ((double)p_heights[id] < p_sea_level) {
			continue; // the sea takes it
		}
		double weights[8];
		double total = 0.0;
		int best = -1;
		double best_weight = 0.0;
		for (int n = 0; n < 8; n++) {
			weights[n] = 0.0;
			const int other = neighbours[id * 8 + n];
			if (other < 0) {
				continue;
			}
			double drop = filled[id] - filled[other];
			if (drop <= 0.0) {
				continue;
			}
			Vector3 gap = dirs[id] - dirs[other];
			double distance = (double)gap.length() * radius;
			double slope = drop / (distance > 1.0 ? distance : 1.0);
			double w = std::pow(slope, p_exponent);
			weights[n] = w;
			total += w;
			if (w > best_weight) {
				best_weight = w;
				best = other;
			}
		}
		receiver[id] = best;
		if (total <= 0.0) {
			continue;
		}
		for (int n = 0; n < 8; n++) {
			if (weights[n] > 0.0) {
				water[neighbours[id * 8 + n]] += water[id] * weights[n] / total;
			}
		}
	}
	PackedFloat32Array filled_out;
	PackedFloat32Array flow_out;
	PackedByteArray lake;
	filled_out.resize(count);
	flow_out.resize(count);
	lake.resize(count);
	// a lake is a hollow that is deep and wide: a pit of a few cells is only the roughness of the ground
	std::vector<char> deep(count, 0);
	for (int id = 0; id < count; id++) {
		filled_out[id] = (float)filled[id];
		flow_out[id] = (float)water[id];
		lake[id] = 0;
		deep[id] = (filled[id] - (double)p_heights[id] > p_lake_depth && (double)p_heights[id] >= p_sea_level) ? 1 : 0;
	}
	std::vector<int> stack;
	std::vector<int> members;
	for (int start = 0; start < count; start++) {
		if (!deep[start]) {
			continue;
		}
		members.clear();
		stack.clear();
		stack.push_back(start);
		deep[start] = 2;
		while (!stack.empty()) {
			const int id = stack.back();
			stack.pop_back();
			members.push_back(id);
			for (int n = 0; n < 8; n++) {
				const int other = neighbours[id * 8 + n];
				if (other >= 0 && deep[other] == 1) {
					deep[other] = 2;
					stack.push_back(other);
				}
			}
		}
		if ((int)members.size() >= p_lake_cells) {
			for (size_t k = 0; k < members.size(); k++) {
				lake[members[k]] = 1;
			}
		}
	}
	Dictionary result;
	result["filled"] = filled_out;
	result["flow"] = flow_out;
	result["receiver"] = receiver;
	result["lake"] = lake;
	return result;
}

PackedFloat32Array PlanetDrainageNative::carve(const PackedFloat32Array &p_heights, const PackedFloat32Array &p_filled,
		const PackedFloat32Array &p_flow, const PackedInt32Array &p_receiver, double p_river_flow,
		double p_base_slope, double p_max_cut) const {
	const int count = 6 * cells * cells;
	std::vector<int> order(count);
	for (int id = 0; id < count; id++) {
		order[id] = id;
	}
	std::sort(order.begin(), order.end(), [&](int a, int b) { return p_filled[a] < p_filled[b]; });
	std::vector<double> bed(count);
	for (int id = 0; id < count; id++) {
		bed[id] = p_heights[id];
	}
	std::vector<float> cut(count, 0.0f);
	for (int at = 0; at < count; at++) {
		const int id = order[at];
		const int down = p_receiver[id];
		if (down < 0 || (double)p_heights[id] < 0.0 || (double)p_flow[id] < p_river_flow) {
			continue;
		}
		Vector3 gap = dirs[id] - dirs[down];
		double distance = (double)gap.length() * radius;
		// more water, a gentler bed: the slope falls with the square root of the flow
		double slope = p_base_slope * std::sqrt(p_river_flow / (double)p_flow[id]);
		double allowed = bed[down] + slope * distance;
		if (allowed < bed[id]) {
			bed[id] = allowed;
		}
		double dug = (double)p_heights[id] - bed[id];
		cut[id] = (float)(dug < 0.0 ? 0.0 : (dug > p_max_cut ? p_max_cut : dug));
	}
	// the valley is wider than the river: a part of the cut goes to the cells beside it
	std::vector<float> wide(cut);
	for (int id = 0; id < count; id++) {
		if (cut[id] <= 0.0f) {
			continue;
		}
		for (int n = 0; n < 8; n++) {
			const int other = neighbours[id * 8 + n];
			if (other >= 0 && (double)p_heights[other] >= 0.0) {
				const float shared = cut[id] * 0.5f;
				if (shared > wide[other]) {
					wide[other] = shared;
				}
			}
		}
	}
	PackedFloat32Array result;
	result.resize(count);
	for (int id = 0; id < count; id++) {
		result[id] = wide[id];
	}
	return result;
}

Dictionary PlanetDrainageNative::river_network(const PackedFloat32Array &p_heights, const PackedFloat32Array &p_filled,
		const PackedFloat32Array &p_flow, const PackedInt32Array &p_receiver, double p_river_flow,
		double p_base_slope, int p_samples, double p_meander, const PackedFloat32Array &p_uplift) const {
	const int count = 6 * cells * cells;
	// the river beds, from the sea inland (as in `carve`)
	std::vector<int> order(count);
	for (int id = 0; id < count; id++) {
		order[id] = id;
	}
	std::sort(order.begin(), order.end(), [&](int a, int b) { return p_filled[a] < p_filled[b]; });
	std::vector<double> bed(count);
	std::vector<char> river(count, 0);
	for (int id = 0; id < count; id++) {
		bed[id] = p_heights[id];
	}
	for (int at = 0; at < count; at++) {
		const int id = order[at];
		const int down = p_receiver[id];
		if (down < 0 || (double)p_heights[id] < 0.0 || (double)p_flow[id] < p_river_flow) {
			continue;
		}
		river[id] = 1;
		Vector3 gap = dirs[id] - dirs[down];
		double distance = (double)gap.length() * radius;
		// the steady state of the stream power law (slope = (uplift / erodibility)^(1/n) * area^(-m/n),
		// with m/n = 1/2): a river climbing a rising range is steeper than one crossing a plain
		double rise = 0.5 + 1.5 * (p_uplift.size() == count ? (double)p_uplift[id] : 0.5);
		double slope = p_base_slope * rise * std::sqrt(p_river_flow / (double)p_flow[id]);
		double allowed = bed[down] + slope * distance;
		if (allowed < bed[id]) {
			bed[id] = allowed;
		}
	}
	// the biggest river cell that flows into each cell: the main stem goes on through it
	std::vector<int> main_up(count, -1);
	for (int id = 0; id < count; id++) {
		if (!river[id]) {
			continue;
		}
		const int down = p_receiver[id];
		if (main_up[down] < 0 || p_flow[id] > p_flow[main_up[down]]) {
			main_up[down] = id;
		}
	}
	auto tangent_at = [&](int node, int toward) -> Vector3 {
		const int up = main_up[node];
		const int down = river[node] ? p_receiver[node] : -1;
		Vector3 t;
		if (up >= 0 && down >= 0) {
			t = dirs[down] - dirs[up];
		} else if (down >= 0) {
			t = dirs[down] - dirs[node];
		} else if (up >= 0) {
			t = dirs[node] - dirs[up];
		} else {
			t = dirs[toward] - dirs[node];
		}
		return t.normalized();
	};
	PackedVector3Array a_out, b_out;
	PackedFloat32Array bed_a, bed_b, flow_a, flow_b;
	std::vector<std::vector<int>> listed(count);
	const int samples = p_samples < 1 ? 1 : p_samples;
	for (int id = 0; id < count; id++) {
		if (!river[id]) {
			continue;
		}
		const int down = p_receiver[id];
		const Vector3 p0 = dirs[id];
		const Vector3 p1 = dirs[down];
		const double length = (double)(p1 - p0).length();
		const Vector3 t0 = tangent_at(id, down) * (real_t)length;
		const Vector3 t1 = (river[down] ? tangent_at(down, down) : (p1 - p0).normalized()) * (real_t)length;
		const double phase = (double)(id % 977) * 0.61;
		Vector3 last = p0;
		double last_bed = bed[id];
		double last_flow = p_flow[id];
		for (int k = 1; k <= samples; k++) {
			const double u = (double)k / (double)samples;
			const double h00 = 2 * u * u * u - 3 * u * u + 1;
			const double h10 = u * u * u - 2 * u * u + u;
			const double h01 = -2 * u * u * u + 3 * u * u;
			const double h11 = u * u * u - u * u;
			Vector3 point = p0 * (real_t)h00 + t0 * (real_t)h10 + p1 * (real_t)h01 + t1 * (real_t)h11;
			point = point.normalized();
			// the meander: a sideways wave that is nothing at the cells and swings between them
			const Vector3 side = point.cross((p1 - p0)).normalized();
			const double swing = std::sin(PI_VALUE * u) * std::sin(2.0 * PI_VALUE * u + phase);
			point = (point + side * (real_t)(swing * p_meander * length)).normalized();
			const double here_bed = bed[id] + (bed[down] - bed[id]) * u;
			const double here_flow = (double)p_flow[id] + ((double)p_flow[down] - (double)p_flow[id]) * u;
			const int piece = a_out.size();
			a_out.append(last);
			b_out.append(point);
			bed_a.append((float)last_bed);
			bed_b.append((float)here_bed);
			flow_a.append((float)last_flow);
			flow_b.append((float)here_flow);
			// the cells the piece belongs to: its middle's cell and the eight round it
			const Vector3 middle = ((last + point) * (real_t)0.5).normalized();
			const int home = cell_at(middle);
			listed[home].push_back(piece);
			for (int n = 0; n < 8; n++) {
				const int other = neighbours[home * 8 + n];
				if (other >= 0) {
					listed[other].push_back(piece);
				}
			}
			last = point;
			last_bed = here_bed;
			last_flow = here_flow;
		}
	}
	PackedInt32Array cell_start;
	PackedInt32Array cell_items;
	cell_start.resize(count + 1);
	int total = 0;
	for (int id = 0; id < count; id++) {
		cell_start[id] = total;
		total += (int)listed[id].size();
	}
	cell_start[count] = total;
	cell_items.resize(total);
	int at = 0;
	for (int id = 0; id < count; id++) {
		for (size_t k = 0; k < listed[id].size(); k++) {
			cell_items[at++] = listed[id][k];
		}
	}
	Dictionary result;
	result["a"] = a_out;
	result["b"] = b_out;
	result["bed_a"] = bed_a;
	result["bed_b"] = bed_b;
	result["flow_a"] = flow_a;
	result["flow_b"] = flow_b;
	result["cell_start"] = cell_start;
	result["cell_items"] = cell_items;
	result["river_flow"] = p_river_flow;
	return result;
}
