#ifndef EROSION_NOISE_H
#define EROSION_NOISE_H

// An eroded-looking noise: ridged gradient noise whose every octave is warped and damped by the slope
// the coarser octaves have built (after Giliam de Carpentier's Jordan turbulence and Inigo Quilez's
// derivative fbm). Steep ground keeps sharp ridges; the finer octaves fade where the ground is already
// steep, so the valleys between ridges are smoother and branch the way drainage does. Everything is a
// pure function of the point, so tiles and maps agree.

#include <cmath>
#include <cstdint>

namespace erosion_noise {

struct Vec {
	double x, y, z;
};

inline Vec operator+(const Vec &a, const Vec &b) { return { a.x + b.x, a.y + b.y, a.z + b.z }; }
inline Vec operator-(const Vec &a, const Vec &b) { return { a.x - b.x, a.y - b.y, a.z - b.z }; }
inline Vec operator*(const Vec &a, double s) { return { a.x * s, a.y * s, a.z * s }; }
inline Vec operator-(const Vec &a) { return { -a.x, -a.y, -a.z }; }
inline double dot(const Vec &a, const Vec &b) { return a.x * b.x + a.y * b.y + a.z * b.z; }

inline uint32_t hash(int32_t x, int32_t y, int32_t z, uint32_t seed) {
	uint32_t h = seed ^ ((uint32_t)x * 0x8da6b343u) ^ ((uint32_t)y * 0xd8163841u) ^ ((uint32_t)z * 0xcb1ab31fu);
	h ^= h >> 13;
	h *= 0x85ebca6bu;
	h ^= h >> 16;
	h *= 0xc2b2ae35u;
	h ^= h >> 15;
	return h;
}

inline Vec gradient_at(int32_t x, int32_t y, int32_t z, uint32_t seed) {
	static const double table[12][3] = { { 1, 1, 0 }, { -1, 1, 0 }, { 1, -1, 0 }, { -1, -1, 0 }, { 1, 0, 1 }, { -1, 0, 1 },
		{ 1, 0, -1 }, { -1, 0, -1 }, { 0, 1, 1 }, { 0, -1, 1 }, { 0, 1, -1 }, { 0, -1, -1 } };
	const double *g = table[hash(x, y, z, seed) % 12];
	return { g[0], g[1], g[2] };
}

struct Sample {
	double value; // about -1..1
	Vec grad; // d value / d (x, y, z)
};

// Gradient (Perlin) noise with its analytic derivative (Inigo Quilez's "noised" for 3D).
inline Sample noise(double x, double y, double z, uint32_t seed) {
	const double fx = std::floor(x), fy = std::floor(y), fz = std::floor(z);
	const int32_t ix = (int32_t)fx, iy = (int32_t)fy, iz = (int32_t)fz;
	const Vec w = { x - fx, y - fy, z - fz };
	const Vec u = { w.x * w.x * w.x * (w.x * (w.x * 6.0 - 15.0) + 10.0), w.y * w.y * w.y * (w.y * (w.y * 6.0 - 15.0) + 10.0),
		w.z * w.z * w.z * (w.z * (w.z * 6.0 - 15.0) + 10.0) };
	const Vec du = { 30.0 * w.x * w.x * (w.x * (w.x - 2.0) + 1.0), 30.0 * w.y * w.y * (w.y * (w.y - 2.0) + 1.0),
		30.0 * w.z * w.z * (w.z * (w.z - 2.0) + 1.0) };
	const Vec ga = gradient_at(ix, iy, iz, seed), gb = gradient_at(ix + 1, iy, iz, seed);
	const Vec gc = gradient_at(ix, iy + 1, iz, seed), gd = gradient_at(ix + 1, iy + 1, iz, seed);
	const Vec ge = gradient_at(ix, iy, iz + 1, seed), gf = gradient_at(ix + 1, iy, iz + 1, seed);
	const Vec gg = gradient_at(ix, iy + 1, iz + 1, seed), gh = gradient_at(ix + 1, iy + 1, iz + 1, seed);
	const double va = dot(ga, w), vb = dot(gb, { w.x - 1.0, w.y, w.z }), vc = dot(gc, { w.x, w.y - 1.0, w.z });
	const double vd = dot(gd, { w.x - 1.0, w.y - 1.0, w.z }), ve = dot(ge, { w.x, w.y, w.z - 1.0 });
	const double vf = dot(gf, { w.x - 1.0, w.y, w.z - 1.0 }), vg = dot(gg, { w.x, w.y - 1.0, w.z - 1.0 });
	const double vh = dot(gh, { w.x - 1.0, w.y - 1.0, w.z - 1.0 });
	const double k1 = va - vb - vc + vd, k2 = va - vc - ve + vg, k3 = va - vb - ve + vf;
	const double k4 = -va + vb + vc - vd + ve - vf - vg + vh;
	Sample result;
	result.value = va + u.x * (vb - va) + u.y * (vc - va) + u.z * (ve - va) + u.x * u.y * k1 + u.y * u.z * k2 + u.z * u.x * k3 +
			k4 * u.x * u.y * u.z;
	const Vec base = ga + (gb - ga) * u.x + (gc - ga) * u.y + (ge - ga) * u.z + (ga - gb - gc + gd) * (u.x * u.y) +
			(ga - gc - ge + gg) * (u.y * u.z) + (ga - gb - ge + gf) * (u.z * u.x) + (-ga + gb + gc - gd + ge - gf - gg + gh) * (u.x * u.y * u.z);
	const Vec slope = { (vb - va) + u.y * k1 + u.z * k3 + u.y * u.z * k4, (vc - va) + u.z * k2 + u.x * k1 + u.z * u.x * k4,
		(ve - va) + u.x * k3 + u.y * k2 + u.x * u.y * k4 };
	result.grad = { base.x + du.x * slope.x, base.y + du.y * slope.y, base.z + du.z * slope.z };
	return result;
}

// The eroded noise at `p` (metres): about -0.5..0.5, the first octave `wavelength` metres across. Octaves
// finer than three pixels (`pixel` > 0) are left out.
inline double fbm(const Vec &p, double wavelength, int octaves, double pixel, uint32_t seed, const Vec &slope = { 0, 0, 0 }) {
	const double warp0 = 0.4, warp = 0.3, damp0 = 1.0, damp = 0.8, damp_scale = 0.9, gain = 0.5;
	double frequency = 1.0 / wavelength;
	double amp = 1.0, total_amp = 0.0, sum = 0.0;
	// the ground's own slope (in the first octave's lattice units) is what the first octave's ridges stand on:
	// the gullies are strongest where it is steep and follow its direction
	// (a very steep coarse slope is capped: it moves the finer octaves' lookup points by lattice units, and the
	// ground that changes slope quickly then changes shape quickly too: a wall)
	const double slope_size = std::sqrt(dot(slope, slope));
	const Vec capped = slope_size > 1.5 ? slope * (1.5 / slope_size) : slope;
	Vec warp_sum = capped * 0.5, damp_sum = capped;
	double damped = 1.0;
	for (int octave = 0; octave < octaves; octave++) {
		if (octave > 0 && pixel > 0.0 && wavelength / (double)(1 << octave) < pixel * 3.0) {
			// the octaves left out stand in as their average (measured: about 0.5 of their amplitude, the damping included), so
			// a coarse tile and a fine one agree on the height, not only on the shape (without this
			// the height jumped by tens of metres where two sizes of tile meet: a wall)
			double left_out = 0.0, left_amp = amp;
			for (int rest = octave; rest < octaves; rest++, left_amp *= gain) {
				left_out += left_amp;
			}
			sum += left_out * 0.5;
			total_amp += left_out;
			break;
		}
		const Vec at = p * frequency + warp_sum * (octave == 0 ? 0.0 : 1.0) + Vec{ octave * 17.3, octave * 31.7, octave * 7.9 };
		const Sample n = noise(at.x, at.y, at.z, seed);
		// a crest where the noise crosses zero, rounded: |n| has a cusp there (a knife edge: the slope flips by
		// more than 1 m/m within a couple of metres, and the warped finer octaves made walls of it), the smooth
		// absolute value sqrt(n^2 + e^2) has a rounded top a few tens of metres across and is |n| away from it
		const double rounding = 0.3;
		const double rounded = std::sqrt(n.value * n.value + rounding * rounding);
		const double ridge = 1.0 - (rounded - rounding) * 1.4;
		// which side of the crest the point is on: +1 / -1 far from it, passing smoothly through 0 at it
		const double slope_sign = -n.value / rounded;
		const Vec ridge_grad = n.grad * (slope_sign * 1.4);
		sum += damped * amp * ridge;
		total_amp += amp;
		warp_sum = warp_sum + ridge_grad * (octave == 0 ? warp0 : warp) * amp;
		damp_sum = damp_sum + ridge_grad * (octave == 0 ? damp0 : damp) * amp;
		frequency *= 2.0;
		amp *= gain;
		damped = 1.0 - damp_scale / (1.0 + dot(damp_sum, damp_sum));
		if (damped < 0.05) {
			damped = 0.05;
		}
	}
	return total_amp > 0.0 ? sum / total_amp - 0.6 : 0.0;
}

} // namespace erosion_noise

#endif
