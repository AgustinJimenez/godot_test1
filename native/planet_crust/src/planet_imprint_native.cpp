#include "planet_imprint_native.h"

#include <godot_cpp/core/class_db.hpp>

#include <algorithm>
#include <cmath>
#include <vector>

using namespace godot;

void PlanetImprintNative::_bind_methods() {
	ClassDB::bind_method(D_METHOD("profile_of", "levels", "tile", "nothing", "reach", "span"), &PlanetImprintNative::profile_of);
	ClassDB::bind_method(D_METHOD("sole_profile", "side", "tile", "span"), &PlanetImprintNative::sole_profile);
	ClassDB::bind_method(D_METHOD("bleed", "rgba", "width", "height", "passes"), &PlanetImprintNative::bleed);
}

// The lowest point is the level the lowest few percent of the pixels reach (a stray pixel does not count); anything lower
// than that is left out.
PackedByteArray PlanetImprintNative::profile_of(const PackedByteArray &p_levels, int p_tile, int p_nothing, int p_reach, double p_span) const {
	const int count = p_tile * p_tile;
	if (p_levels.size() < count * 4) {
		return PackedByteArray();
	}
	const uint8_t *levels = p_levels.ptr();
	std::vector<int> histogram(256, 0);
	int touching = 0;
	for (int index = 0; index < count; index++) {
		const int level = levels[index * 4];
		if (level < p_nothing) {
			touching++;
			histogram[level]++;
		}
	}
	if (touching < 40) {
		return PackedByteArray();
	}
	int lowest = 0, below = 0;
	const int wanted = std::max(4, touching / 33);
	while (lowest < 255 && below + histogram[lowest] < wanted) {
		below += histogram[lowest];
		lowest++;
	}
	if (lowest > p_reach) { // (a foot in the air, a stone high up: no print)
		return PackedByteArray();
	}
	PackedByteArray profile;
	profile.resize(count);
	uint8_t *out = profile.ptrw();
	for (int index = 0; index < count; index++) {
		const int level = levels[index * 4];
		out[index] = 0;
		if (level < p_nothing && level >= lowest - 3) {
			const double depth = std::min(std::max(1.0 - (double)(level - lowest) / p_span, 0.0), 1.0);
			out[index] = (uint8_t)(int)(depth * 255.0);
		}
	}
	return profile;
}

// A heel, a narrow arch, the ball and five toes, in the picture's frame (x across, y down the page is backward).
PackedByteArray PlanetImprintNative::sole_profile(double p_side, int p_tile, double p_span) const {
	const double key = p_side < 0.0 ? -1.0 : 1.0;
	const double toes[5][3] = { { 0.032, 0.125, 0.017 }, { 0.012, 0.133, 0.0125 }, { -0.006, 0.13, 0.0115 }, { -0.022, 0.123, 0.0105 },
		{ -0.036, 0.113, 0.0095 } }; // (across, along, radius)
	PackedByteArray bytes;
	bytes.resize(p_tile * p_tile);
	uint8_t *out = bytes.ptrw();
	for (int row = 0; row < p_tile; row++) {
		const double along = (0.5 - ((double)row + 0.5) / p_tile) * p_span;
		for (int column = 0; column < p_tile; column++) {
			const double across = (((double)column + 0.5) / p_tile - 0.5) * p_span * key;
			const double heel = std::hypot(across / 0.036, (along + 0.09) / 0.048);
			const double ball = std::hypot((across - 0.004) / 0.05, (along - 0.04) / 0.065);
			const double arch = std::hypot((across + 0.012) / 0.022, (along + 0.02) / 0.06);
			double depth = 0.0;
			if (heel < 1.0) {
				depth = 1.0;
			}
			if (ball < 1.0) {
				depth = 1.0;
			}
			if (arch < 1.0) {
				depth = std::max(depth, 0.35);
			}
			for (const auto &toe : toes) {
				if (std::hypot(across - toe[0], along - toe[1]) < toe[2]) {
					depth = std::max(depth, 0.8);
				}
			}
			out[row * p_tile + column] = (uint8_t)(int)(depth * 255.0);
		}
	}
	return bytes;
}

// Gives the see-through texels (alpha 0) of an RGBA8 picture the colour of the nearest solid ones, `p_passes` texels deep, so the
// filtering of an impostor atlas does not pull a dark fringe round the tree. Returns the picture's bytes.
PackedByteArray PlanetImprintNative::bleed(const PackedByteArray &p_rgba, int p_width, int p_height, int p_passes) const {
	PackedByteArray out = p_rgba;
	if (out.size() < p_width * p_height * 4) {
		return out;
	}
	uint8_t *pixels = out.ptrw();
	std::vector<uint8_t> solid((size_t)p_width * p_height);
	for (int index = 0; index < p_width * p_height; index++) {
		solid[index] = pixels[index * 4 + 3] > 0 ? 1 : 0;
	}
	const int dx[4] = { -1, 1, 0, 0 }, dy[4] = { 0, 0, -1, 1 };
	for (int pass = 0; pass < p_passes; pass++) {
		std::vector<uint8_t> grown = solid;
		for (int y = 0; y < p_height; y++) {
			for (int x = 0; x < p_width; x++) {
				const int index = y * p_width + x;
				if (solid[index]) {
					continue;
				}
				int sum[3] = { 0, 0, 0 }, count = 0;
				for (int side = 0; side < 4; side++) {
					const int nx = x + dx[side], ny = y + dy[side];
					if (nx < 0 || ny < 0 || nx >= p_width || ny >= p_height || !solid[ny * p_width + nx]) {
						continue;
					}
					for (int channel = 0; channel < 3; channel++) {
						sum[channel] += pixels[(ny * p_width + nx) * 4 + channel];
					}
					count++;
				}
				if (count > 0) {
					for (int channel = 0; channel < 3; channel++) {
						pixels[index * 4 + channel] = (uint8_t)(sum[channel] / count);
					}
					grown[index] = 1;
				}
			}
		}
		solid = grown;
	}
	return out;
}
