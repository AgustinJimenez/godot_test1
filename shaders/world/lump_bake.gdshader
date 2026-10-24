shader_type canvas_item;
render_mode blend_disabled; // the height is written in alpha: no blending
// Procedural rock face (smooth lumps, creased valleys, rubble in the creases), drawn once into a tile (LumpBaker):
// colour in rgb, height in alpha. The same model as tools/bark/lump_gen.py (the reference the 18 numbers were fitted
// with, LumpFits.KEYS), made to tile: every scale is a whole number of repeats in the tile and the hashes wrap.

uniform float p[18];
uniform float tile_cm = 200.0;
uniform vec3 ramp[8];
uniform vec2 height_range = vec2(0.0, 1.0);
uniform float seed = 1.0;
uniform vec3 light_colour = vec3(0.6, 0.5, 0.4); // the rock's light colour
uniform vec3 dark_colour = vec3(0.2, 0.17, 0.14); // its stains (the dark patches in the hollows)
uniform float dark_share = 0.0; // how much of the surface is stained (0: none)
uniform float guide[256]; // the photograph's height as a 16 x 16 picture (row by row), steering the lumps
uniform float rim_lobes = 0.0; // height of smooth rimmed lobes (rock boulders in the photograph); 0: none
uniform float wiggle_cracks = 0.0; // depth of a few long wiggly cracks (the mottled rock); 0: none
uniform float bp[51]; // the boulder's hand-set numbers (BoulderParams in GDScript lists them, with their ranges)
#define B_COVER bp[0]
#define B_RADIUS bp[1]
#define B_RADIUS_VAR bp[2]
#define B_SQUASH bp[3]
#define B_WARP_BIG bp[4]
#define B_WARP_SMALL bp[5]
#define B_LEVEL bp[6]
#define B_EDGE_W bp[7]
#define B_RIM bp[8]
#define B_PLATEAU bp[9]
#define B_RIM_VARY bp[10]
#define B_SWELL bp[11]
#define B_SNAKE bp[12]
#define B_SNAKE_W bp[13]
#define B_PIT_COVER bp[14]
#define B_PIT_DEPTH bp[15]
#define B_CRUMB bp[16]
#define B_FINE bp[17]
#define B_FINE_SIZE bp[18]
#define B_CREASE bp[19]
#define B_GAIN bp[20]
#define B_CONTRAST bp[21]
#define B_SPECKS bp[22]
#define B_GRAIN bp[23]
#define B_EDGE_DETAIL bp[24]
#define B_EDGE_SCALLOP bp[25]
#define B_EDGE_SOFT bp[26]
#define B_SPECK_COVER bp[27]
#define B_SPECK_DEPTH bp[28]
#define B_FEATURES bp[29]
#define B_FEAT_GAIN bp[30]
#define B_FEAT_SOFT bp[31]
#define B_EDGE_LAYER bp[32]
#define B_COLOUR_SWELL bp[33]
#define B_LOBE_TINT bp[34]
#define B_EDGE_DARK bp[35]
#define B_COLOUR_DETAIL bp[36]
#define B_FINE_COLOUR bp[39]
#define B_FINE_HEIGHT bp[40]
#define B_FINE_CM bp[41]
#define B_LIP_COVER bp[44]
#define B_LIP_DEPTH bp[45]
#define B_LIP_CM bp[46]
#define B_PIT_IRREGULAR bp[48]
#define B_CRACK_COLOUR bp[49]
#define B_CRACK_DEPTH bp[50]
uniform sampler2D crack_tex : filter_nearest; // the thin cracks (BoulderCracks.bin), strength 0..1 per texel
uniform sampler2D swell_colour_tex : filter_linear, repeat_enable; // the photograph's colour on a coarse grid (boulder_colour.bin), without the lobe tones
uniform sampler2D edge_tex : filter_nearest; // the sharp edge points drawn as step profiles (BoulderEdges), height offsets in the normalised height
uniform sampler2D lobe_tex : filter_nearest; // the lobes traced from the photograph (BoulderFeatures): a row each, 2 header texels then the outline
uniform sampler2D speck_tex : filter_nearest; // its small pits and bumps: x, y, radius, depth (tile units)
uniform int n_lobes = 0;
uniform int n_specks = 0;
uniform sampler2D swell_tex : filter_nearest; // the photograph minus the traced lobes, on a coarse grid (BoulderFeatures.swell)
uniform int n_swell = 0;
uniform float guide_mix = 0.0; // 0: the lumps' own noise (fully procedural); 1: the guide's

float fract1(float x) {
	return x - floor(x);
}

float hash2(float ix, float iy, float s) {
	return fract1(sin(ix * 127.1 + iy * 311.7 + s * 74.7) * 43758.5453);
}

float hashw(float ix, float iy, float s, float per) {
	// (not mod(): the GPU divides as x * (1 / y), so mod(75.0, 75.0) can come out 75 and the noise breaks at the tile edge)
	return hash2(ix - per * floor(ix / per + 0.001), iy - per * floor(iy / per + 0.001), s);
}

float vnoise(vec2 at, float scale, float s) {
	float n = max(floor(tile_cm / scale + 0.5), 1.0);
	vec2 q = at / tile_cm * n;
	vec2 i = floor(q);
	vec2 f = q - i;
	f = f * f * (3.0 - 2.0 * f);
	float a = hashw(i.x, i.y, s, n);
	float b = hashw(i.x + 1.0, i.y, s, n);
	float c = hashw(i.x, i.y + 1.0, s, n);
	float d = hashw(i.x + 1.0, i.y + 1.0, s, n);
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

// signed distance (cm) from a point to the outline of lobe `row` (negative inside)
float lobe_sd(vec2 pos, int row) {
	float best = 1e9;
	bool inside = false;
	vec2 a = texelFetch(lobe_tex, ivec2(2 + 47, row), 0).xy * tile_cm;
	for (int k = 0; k < 48; k++) {
		vec2 b = texelFetch(lobe_tex, ivec2(2 + k, row), 0).xy * tile_cm;
		vec2 e = b - a;
		vec2 w = pos - a;
		float t = clamp(dot(w, e) / max(dot(e, e), 1e-6), 0.0, 1.0);
		best = min(best, length(w - e * t));
		if ((a.y > pos.y) != (b.y > pos.y) && pos.x < (b.x - a.x) * (pos.y - a.y) / (b.y - a.y) + a.x) {
			inside = !inside;
		}
		a = b;
	}
	return inside ? -best : best;
}

// the coarse swell read smoothly (Catmull-Rom over 4 x 4 cells, wrapping: the photograph tiles)
float swell_at(vec2 at) {
	vec2 g = at / tile_cm * float(n_swell) - 0.5;
	vec2 i = floor(g);
	vec2 f = g - i;
	vec4 wx = vec4(-0.5 * f.x * f.x * f.x + f.x * f.x - 0.5 * f.x, 1.5 * f.x * f.x * f.x - 2.5 * f.x * f.x + 1.0,
			-1.5 * f.x * f.x * f.x + 2.0 * f.x * f.x + 0.5 * f.x, 0.5 * f.x * f.x * f.x - 0.5 * f.x * f.x);
	vec4 wy = vec4(-0.5 * f.y * f.y * f.y + f.y * f.y - 0.5 * f.y, 1.5 * f.y * f.y * f.y - 2.5 * f.y * f.y + 1.0,
			-1.5 * f.y * f.y * f.y + 2.0 * f.y * f.y + 0.5 * f.y, 0.5 * f.y * f.y * f.y - 0.5 * f.y * f.y);
	float sum = 0.0;
	for (int j = 0; j < 4; j++) {
		for (int k = 0; k < 4; k++) {
			int px = int(mod(i.x + float(k) - 1.0, float(n_swell)));
			int py = int(mod(i.y + float(j) - 1.0, float(n_swell)));
			sum += texelFetch(swell_tex, ivec2(px, py), 0).r * wx[k] * wy[j];
		}
	}
	return sum;
}

// The finest scales (about 1 cm and 0.5 cm, 6 and 3 px of the 1024 tile) which the stored layout has no data for: the photograph has
// 24 to 48 % of its energy there and a bake without them looks low resolution. Warped value noise (the warp breaks the grid, so no
// axis-aligned marks) plus a per-pixel hash. Roughly zero-mean, about unit spread.
float micro_texture(vec2 at, float s) {
	vec2 w = at + 0.45 * B_FINE_CM * vec2(vnoise(at, 1.7 * B_FINE_CM, s + 511.0) - 0.5, vnoise(at, 1.9 * B_FINE_CM, s + 513.0) - 0.5) * 2.0;
	float n = (vnoise(w, 1.1 * B_FINE_CM, s + 501.0) - 0.5) * 1.0 + (vnoise(w, 0.55 * B_FINE_CM, s + 503.0) - 0.5) * 0.9;
	float grain = fract(sin(dot(floor(at / tile_cm * 1024.0), vec2(12.9898, 78.233))) * 43758.5453) - 0.5;
	return (n + 0.35 * grain) * 2.2;
}

float guide_at(vec2 at) {
	vec2 g = at / tile_cm * 16.0 - 0.5;
	vec2 i = floor(g);
	vec2 f = g - i;
	f = f * f * (3.0 - 2.0 * f);
	int x0 = int(mod(i.x, 16.0));
	int y0 = int(mod(i.y, 16.0));
	int x1 = (x0 + 1) % 16;
	int y1 = (y0 + 1) % 16;
	return mix(mix(guide[y0 * 16 + x0], guide[y0 * 16 + x1], f.x), mix(guide[y1 * 16 + x0], guide[y1 * 16 + x1], f.x), f.y);
}

float lumps(vec2 at, float s, out float tone, out float in_crease, out float fragment) {
	float lump_cm = p[0];
	float warp_cm = p[2];
	float crease_cm = p[4];
	vec2 w = at + p[3] * warp_cm * vec2(vnoise(at, warp_cm, s + 1.0) - 0.5, vnoise(at + vec2(7.0, 0.0), warp_cm, s + 2.0) - 0.5);
	float l = (vnoise(w, lump_cm, s + 3.0) + 0.5 * vnoise(w, lump_cm * 0.5, s + 4.0)) / 1.5;
	vec2 c = at + p[7] * crease_cm * vec2(vnoise(at, crease_cm, s + 5.0) - 0.5, vnoise(at + vec2(3.0, 0.0), crease_cm, s + 6.0) - 0.5);
	float line = abs(vnoise(c, crease_cm, s + 7.0) - 0.5) * 2.0;
	float crease = 1.0 - smoothstep(0.0, p[5] * 2.0, line);
	vec2 guide_p = at;
	if (rim_lobes > 0.0) { // (the 16 x 16 guide leaves a faint grid of bands: look it up through a warp)
		guide_p += 12.0 * vec2(vnoise(at, 24.0, s + 361.0) - 0.5, vnoise(at, 24.0, s + 363.0) - 0.5) * 2.0;
	}
	l = mix(l, guide_at(guide_p), guide_mix);
	float h = 0.5 + p[1] * (l - 0.5) - p[6] * crease * (rim_lobes > 0.0 ? B_CREASE : 1.0); // (the boulder's creases ran in straight bands)
	if (rim_lobes > 0.0 && B_FEATURES > 0.5 && n_swell > 0) { // the traced copy: the height is the photograph's own coarse swell
		l = swell_at(at);
		h = height_range.x + l * (height_range.y - height_range.x) - p[6] * crease * B_CREASE;
	}
	tone = l;
	in_crease = crease;
	// rubble: sharp fragments inside and next to the creases
	float rn = max(floor(tile_cm / p[8] + 0.5), 1.0);
	vec2 u = at / tile_cm * rn;
	vec2 iu = floor(u);
	float best = 1e9;
	float best_id = 0.0;
	vec2 best_dd = vec2(0.0);
	vec2 best_tilt = vec2(0.0);
	for (int oy = -1; oy <= 1; oy++) {
		for (int ox = -1; ox <= 1; ox++) {
			float gx = iu.x + float(ox);
			float gy = iu.y + float(oy);
			vec2 f = vec2(gx + hashw(gx, gy, s + 11.0, rn), gy + hashw(gx, gy, s + 13.0, rn));
			vec2 dd = u - f;
			float d = dot(dd, dd);
			if (d < best) {
				best = d;
				best_id = hashw(gx, gy, s + 15.0, rn);
				best_dd = dd;
				best_tilt = vec2(hashw(gx, gy, s + 17.0, rn), hashw(gx, gy, s + 19.0, rn)) - 0.5;
			}
		}
	}
	float reach = smoothstep(1.0 - p[10], 1.0, crease) * clamp(p[6] * 6.0, 0.0, 1.0); // (no rubble along a crease the height does not have)
	// each fragment is tilted and bevelled at its edge (angular stones, not flat mosaic tiles)
	h += p[9] * ((best_id - 0.5) + 1.2 * dot(best_dd, best_tilt) - 0.35 * smoothstep(0.3, 0.75, sqrt(best))) * reach;
	fragment = best_id * reach;
	h += p[12] * (vnoise(at, max(p[11], 1.6), s + 17.0) - 0.5);
	float mid = max(p[13], 2.0);
	h += p[14] * (0.5 * vnoise(w, mid, s + 19.0) + 0.5 * vnoise(vec2(w.y + 5.0, w.x), mid, s + 21.0) - 0.5);
	if (rim_lobes > 0.0) {
		float lobe_on = B_FEATURES > 0.5 ? 0.0 : 1.0; // (with the traced features the procedural lobes, ridge and pits are off)
		// the boulder's rounded plates: lobes of different sizes whose falloffs ADD, so neighbours merge into chains and branches; the
		// outline is warped hard (nothing round), the rim is where the sum crosses a level, strong in some places and gone in others
		float ln = max(floor(tile_cm / 40.0 + 0.5), 1.0);
		float cs = tile_cm / ln;
		vec2 lat = at + B_WARP_BIG * vec2(vnoise(at, 17.0, s + 321.0) - 0.5, vnoise(at, 17.0, s + 323.0) - 0.5) * 2.0
				+ B_WARP_SMALL * vec2(vnoise(at, 6.0, s + 325.0) - 0.5, vnoise(at, 6.0, s + 327.0) - 0.5) * 2.0;
		// the border's own complexity: the outline is moved again at 2.5 and 1 cm, and the lobe field is scalloped by a noise
		lat += B_EDGE_DETAIL * (vec2(vnoise(at, 2.5, s + 381.0) - 0.5, vnoise(at, 2.5, s + 383.0) - 0.5)
				+ 0.5 * vec2(vnoise(at, 1.0, s + 385.0) - 0.5, vnoise(at, 1.0, s + 387.0) - 0.5)) * 2.0;
		vec2 lc = floor(lat / cs);
		float field = 0.0;
		for (int oy = -1; oy <= 1; oy++) {
			for (int ox = -1; ox <= 1; ox++) {
				float cx = lc.x + float(ox);
				float cy = lc.y + float(oy);
				if (hashw(cx, cy, s + 301.0, ln) < B_COVER) {
					vec2 centre = vec2(cx + 0.15 + 0.7 * hashw(cx, cy, s + 303.0, ln), cy + 0.15 + 0.7 * hashw(cx, cy, s + 305.0, ln)) * cs;
					float radius = cs * (B_RADIUS + B_RADIUS_VAR * hashw(cx, cy, s + 307.0, ln) * hashw(cx, cy, s + 331.0, ln));
					float squash = B_SQUASH + 0.8 * hashw(cx, cy, s + 309.0, ln);
					float turn = 6.2832 * hashw(cx, cy, s + 333.0, ln);
					vec2 d = lat - centre;
					d = vec2(cos(turn) * d.x + sin(turn) * d.y, -sin(turn) * d.x + cos(turn) * d.y) / vec2(1.0, squash);
					float q = clamp(1.0 - dot(d, d) / (radius * radius), 0.0, 1.0);
					field += q * q;
				}
			}
		}
		field += B_EDGE_SCALLOP * ((vnoise(at, 6.0, s + 389.0) - 0.5) + 0.5 * (vnoise(at, 2.8, s + 391.0) - 0.5));
		float edge = (field - B_LEVEL) / B_EDGE_W;
		// slow soft swells over the whole face (the photograph's big soft shading), and a few long snaking ridges: a thin band round an
		// iso-line of a slow warped noise, kept only where another slow noise is high
		h += lobe_on * rim_lobes * B_SWELL * ((vnoise(lat, 38.0, s + 371.0) - 0.5) + 0.6 * (vnoise(lat, 17.0, s + 373.0) - 0.5));
		float snake_d = abs(vnoise(lat, 62.0, s + 375.0) - 0.5) / B_SNAKE_W;
		h += lobe_on * rim_lobes * B_SNAKE * exp(-snake_d * snake_d) * smoothstep(0.5, 0.68, vnoise(at, 85.0, s + 377.0));
		float rim_strength = (1.0 - B_RIM_VARY) + B_RIM_VARY * smoothstep(0.3, 0.7, vnoise(at, 28.0, s + 335.0));
		h += lobe_on * rim_lobes * B_RIM * (B_PLATEAU * smoothstep(B_LEVEL - B_EDGE_SOFT, B_LEVEL + B_EDGE_SOFT, field) + rim_strength * exp(-edge * edge));
		// small pits and bumps on the plates and in between, a few cm across
		float pn = max(floor(tile_cm / 7.0 + 0.5), 1.0);
		vec2 pu = at / tile_cm * pn;
		vec2 pi_ = floor(pu);
		for (int oy = -1; oy <= 1; oy++) {
			for (int ox = -1; ox <= 1; ox++) {
				float gx = pi_.x + float(ox);
				float gy = pi_.y + float(oy);
				if (hashw(gx, gy, s + 341.0, pn) < B_PIT_COVER * lobe_on) {
					vec2 pc = vec2(gx + hashw(gx, gy, s + 343.0, pn), gy + hashw(gx, gy, s + 345.0, pn));
					float pr = (0.08 + 0.14 * hashw(gx, gy, s + 347.0, pn)) * 1.0;
					float pd = length(pu - pc) / pr;
					float sign_ = hashw(gx, gy, s + 349.0, pn) < 0.6 ? -1.0 : 0.5;
					h += sign_ * rim_lobes * B_PIT_DEPTH * (0.4 * (1.0 - smoothstep(0.3, 1.0, pd)) - 0.1 * exp(-pow((pd - 1.05) / 0.12, 2.0)));
				}
			}
		}
		// many tiny sharp pits and bumps (5 mm to 1 cm): the photograph has ten times more very steep pixels than smooth noise gives
		float kn = max(floor(tile_cm / 2.2 + 0.5), 1.0);
		vec2 ku = at / tile_cm * kn;
		vec2 ki = floor(ku);
		for (int oy = -1; oy <= 1; oy++) {
			for (int ox = -1; ox <= 1; ox++) {
				float gx = ki.x + float(ox);
				float gy = ki.y + float(oy);
				if (hashw(gx, gy, s + 441.0, kn) < B_SPECK_COVER * lobe_on) {
					vec2 kc = vec2(gx + hashw(gx, gy, s + 443.0, kn), gy + hashw(gx, gy, s + 445.0, kn));
					float kr = 0.12 + 0.2 * hashw(gx, gy, s + 447.0, kn);
					float kd = length(ku - kc) / kr;
					float up = hashw(gx, gy, s + 449.0, kn) < 0.3 ? 0.6 : -1.0;
					h += up * B_SPECK_DEPTH * (1.0 - smoothstep(0.55, 1.0, kd));
				}
			}
		}
		if (B_FEATURES > 0.5) {
			h += B_EDGE_LAYER * texelFetch(edge_tex, ivec2(clamp(floor(at / tile_cm * 1024.0), vec2(0.0), vec2(1023.0))), 0).r * (height_range.y - height_range.x);
			for (int i = 0; i < n_lobes; i++) {
				vec4 box = texelFetch(lobe_tex, ivec2(1, i), 0);
				vec2 low = box.xy * tile_cm - vec2(B_FEAT_SOFT * 3.0);
				vec2 high = box.zw * tile_cm + vec2(B_FEAT_SOFT * 3.0);
				if (at.x < low.x || at.y < low.y || at.x > high.x || at.y > high.y) {
					continue;
				}
				float step_h = texelFetch(lobe_tex, ivec2(0, i), 0).z;
				h += step_h * (height_range.y - height_range.x) * B_FEAT_GAIN * (1.0 - smoothstep(-B_FEAT_SOFT, B_FEAT_SOFT, lobe_sd(at, i)));
			}
			for (int i = 0; i < n_specks; i++) {
				vec4 sp = texelFetch(speck_tex, ivec2(i, 0), 0);
				float reach = max(sp.z * tile_cm * 1.3, 0.35);
				// irregular outline: the photograph's pits are not round, a warp of the distance breaks the clean disc
				vec2 off = at - sp.xy * tile_cm;
				off += reach * B_PIT_IRREGULAR * vec2(vnoise(at, 0.8, s + 701.0) - 0.5, vnoise(at, 0.8, s + 703.0) - 0.5) * 2.0;
				float dd = length(off) / reach;
				if (dd < 1.0) {
					h += sp.w * (height_range.y - height_range.x) * B_FEAT_GAIN * (1.0 - smoothstep(0.4, 1.0, dd));
				}
			}
		}
		// a crumbly patch (the pale band in the photograph): rough at 1-4 cm where a slow noise is high
		float crumb = smoothstep(0.5, 0.7, vnoise(at, 45.0, s + 351.0));
		h += lobe_on * crumb * rim_lobes * B_CRUMB * ((vnoise(at, 3.5, s + 353.0) - 0.5) + 0.7 * (vnoise(at, 1.6, s + 355.0) - 0.5));
	}
	// a network of straight cracks: the edges of a coarse Voronoi
	float vn = max(floor(tile_cm / p[15] + 0.5), 1.0);
	vec2 vu = at / tile_cm * vn;
	vec2 vi = floor(vu);
	float e1 = 1e9;
	float e2 = 1e9;
	for (int oy = -1; oy <= 1; oy++) {
		for (int ox = -1; ox <= 1; ox++) {
			float gx = vi.x + float(ox);
			float gy = vi.y + float(oy);
			vec2 f = vec2(gx + 0.15 + 0.7 * hashw(gx, gy, s + 31.0, vn), gy + 0.15 + 0.7 * hashw(gx, gy, s + 33.0, vn));
			float d = length(vu - f);
			if (d < e1) {
				e2 = e1;
				e1 = d;
			} else if (d < e2) {
				e2 = d;
			}
		}
	}
	h -= p[17] * 0.35 * (1.0 - smoothstep(0.0, p[16] * 0.22, e2 - e1)) * smoothstep(0.35, 0.7, vnoise(at, 70.0, s + 201.0)); // (a few thin cracks, not a polygon net)
	if (wiggle_cracks > 0.0) {
		// a few long wiggly cracks: the edges of a warped Voronoi, kept only where a slow noise is high (not a net)
		float wn = max(floor(tile_cm / 45.0 + 0.5), 1.0);
		vec2 wat = at + 4.0 * vec2(vnoise(at, 9.0, s + 401.0) - 0.5, vnoise(at, 9.0, s + 403.0) - 0.5) * 2.0
				+ 1.2 * vec2(vnoise(at, 3.0, s + 405.0) - 0.5, vnoise(at, 3.0, s + 407.0) - 0.5) * 2.0;
		vec2 wu = wat / tile_cm * wn;
		vec2 wi = floor(wu);
		float w1 = 1e9;
		float w2 = 1e9;
		for (int oy = -1; oy <= 1; oy++) {
			for (int ox = -1; ox <= 1; ox++) {
				float gx = wi.x + float(ox);
				float gy = wi.y + float(oy);
				vec2 f = vec2(gx + 0.15 + 0.7 * hashw(gx, gy, s + 411.0, wn), gy + 0.15 + 0.7 * hashw(gx, gy, s + 413.0, wn));
				float d = length(wu - f);
				if (d < w1) {
					w2 = w1;
					w1 = d;
				} else if (d < w2) {
					w2 = d;
				}
			}
		}
		float keep = smoothstep(0.6, 0.72, vnoise(at, 55.0, s + 415.0));
		h -= wiggle_cracks * (1.0 - smoothstep(0.0, 0.05, w2 - w1)) * keep;
	}
	// fine relief at 1-5 cm (not finer: parallax turns pixel noise into a mosaic): weathering
	float fine_k = rim_lobes > 0.0 ? B_FINE_SIZE : 1.0; // (the boulder photograph's bumps are about twice as wide and stronger)
	float fr = (vnoise(at, 4.5 * fine_k, s + 111.0) - 0.5) * 0.5 + (vnoise(at, 2.2 * fine_k, s + 113.0) - 0.5) * 0.4 + (vnoise(at, 1.2 * fine_k, s + 115.0) - 0.5) * 0.3;
	h += (rim_lobes > 0.0 ? B_FINE : 0.045) * fr;
	if (rim_lobes > 0.0 && B_FEATURES > 0.5) {
		h += B_FINE_HEIGHT * micro_texture(at, s);
		h -= B_CRACK_DEPTH * texelFetch(crack_tex, ivec2(clamp(floor(at / tile_cm * 1024.0), vec2(0.0), vec2(1023.0))), 0).r;
		// rare crisp pits with a sharp lip (the photograph's height is very peaky at 1 px: kurtosis 39, a few extreme features on a calm ground)
		float cell_cm = B_LIP_CM * 3.0;
		float cn = max(floor(tile_cm / cell_cm + 0.5), 1.0);
		vec2 cu = at / tile_cm * cn;
		vec2 ci = floor(cu);
		for (int oy = -1; oy <= 1; oy++) {
			for (int ox = -1; ox <= 1; ox++) {
				float gx = ci.x + float(ox);
				float gy = ci.y + float(oy);
				if (hashw(gx, gy, s + 601.0, cn) < B_LIP_COVER) {
					vec2 pc = vec2(gx + hashw(gx, gy, s + 603.0, cn), gy + hashw(gx, gy, s + 605.0, cn));
					float pr = 0.12 + 0.2 * hashw(gx, gy, s + 607.0, cn);
					vec2 jitter = pr * B_PIT_IRREGULAR * vec2(vnoise(at, 0.5, s + 711.0) - 0.5, vnoise(at, 0.5, s + 713.0) - 0.5) * 2.0;
					float d = length(cu - pc + jitter) / pr;
					float depth = B_LIP_DEPTH * (0.4 + 0.6 * hashw(gx, gy, s + 609.0, cn));
					h += depth * (-(1.0 - smoothstep(0.7, 1.0, d)) + 0.35 * exp(-pow((d - 1.1) / 0.12, 2.0)));
				}
			}
		}
	}
	return h;
}

float norm(float h) {
	return clamp((h - height_range.x) / max(height_range.y - height_range.x, 0.001), 0.0, 1.0);
}

void fragment() {
	vec2 at = UV * tile_cm;
	float tone;
	float in_crease;
	float fragment;
	float h = norm(lumps(at, seed, tone, in_crease, fragment));
	float t = h * 7.0;
	int i0 = int(floor(t));
	int i1 = min(i0 + 1, 7);
	vec3 colour = mix(ramp[i0], ramp[i1], t - float(i0));
	colour = mix(colour, ramp[3], 0.7); // (the photograph's colour does not follow its height: near the mean)
	// staining: coarse patches that settle in the low parts; the colour is the photograph's light and dark
	float patch = vnoise(at, 9.0, seed + 41.0) * 0.5 + vnoise(at, 3.5, seed + 43.0) * 0.3 + vnoise(at, 1.6, seed + 45.0) * 0.2;
	float stain = smoothstep(-0.06, 0.06, patch + 0.35 * (0.5 - h) - (0.85 - 0.7 * dark_share));
	float stained = step(0.001, dark_share);
	colour = mix(colour, mix(light_colour, dark_colour, stain) * 1.25, stained);
	// each lump its own tone, the creases dark, the rubble lighter and varied fragment by fragment
	colour *= mix(1.0, 0.7, clamp(p[6] * 4.0, 0.0, 1.0)) * (0.7 + 0.6 * tone); // (a creased face is darker)
	colour *= 1.0 - 0.55 * in_crease * clamp(p[6] * 2.0, 0.0, 1.0); // (no crease in the height: none in the colour)
	colour = mix(colour, ramp[7] * (0.8 + 0.8 * fragment), 0.5 * smoothstep(0.05, 0.4, fragment) * clamp(p[9] * 5.0, 0.0, 1.0));
	// real rock grain at every size: five octaves from 8 cm to the pixel, pitting, pale mineral specks
	vec3 colour_before_grain = colour; // (the grain, pits and flecks below are the fine detail the coarse colour grid lacks)
	float rg = 0.0;
	rg += 1.0 * (vnoise(at, 8.0, seed + 91.0) - 0.5);
	rg += 0.8 * (vnoise(at, 3.0, seed + 93.0) - 0.5);
	rg += 0.7 * (vnoise(at, 1.2, seed + 95.0) - 0.5);
	rg += 0.6 * (vnoise(at, 0.9, seed + 97.0) - 0.5);
	rg += 0.4 * (vnoise(at, 0.5, seed + 99.0) - 0.5);
	float pit = smoothstep(0.72, 0.84, vnoise(at, 1.3, seed + 101.0));
	float mineral = smoothstep(0.82, 0.92, vnoise(at, 2.4, seed + 103.0));
	colour *= clamp(0.88 + 0.4 * rg * (rim_lobes > 0.0 ? B_GRAIN : 1.0), 0.5, 1.5);
	// crisp small detail that survives zoom: speckles and flecks from a warped noise (the warp breaks the grid alignment of the
	// cells), plus a per-pixel grain; the dark ones are pits and mineral grains, the pale ones quartz flecks
	vec2 warped = at + 0.55 * vec2(vnoise(at, 1.7, seed + 151.0) - 0.5, vnoise(at, 1.9, seed + 153.0) - 0.5) * 2.0;
	float fleck_d = smoothstep(0.74, 0.8, vnoise(warped, 0.55, seed + 155.0)) * smoothstep(0.4, 0.62, vnoise(at, 7.0, seed + 157.0));
	float fleck_p = smoothstep(0.78, 0.83, vnoise(warped, 0.45, seed + 159.0)) * smoothstep(0.55, 0.75, vnoise(at, 5.0, seed + 161.0));
	float pixel_grain = fract(sin(dot(floor(UV * 1024.0), vec2(12.9898, 78.233))) * 43758.5453) - 0.5;
	float busy = rim_lobes > 0.0 ? B_SPECKS : 1.0; // (the boulder photograph is smooth and pale with few dark specks)
	colour = mix(colour, colour * 0.5, 0.6 * fleck_d * busy);
	colour = mix(colour, vec3(0.86, 0.83, 0.77), 0.4 * fleck_p);
	colour *= 1.0 + 0.2 * pixel_grain;
	colour = mix(colour, colour * 0.55, 0.5 * pit * busy);
	colour = mix(colour, vec3(0.85, 0.82, 0.76), 0.1 * mineral);
	vec3 fine_detail = colour / max(colour_before_grain, vec3(0.02));
	if (rim_lobes > 0.0) {
		colour = (colour - 0.5) * B_CONTRAST + 0.5; // (less contrast, lighter and warmer: the photograph is tan, 168 155 140 on average)
		colour *= vec3(1.0, 0.992, 0.975) * B_GAIN;
	}
	if (rim_lobes > 0.0 && B_FEATURES > 0.5 && n_swell > 0) {
		// the photograph's own colour at the coarse scale, with the procedural grain and specks on top as a ratio to the mean tone
		vec3 base = texture(swell_colour_tex, at / tile_cm).rgb;
		colour = mix(colour, base * pow(fine_detail, vec3(B_COLOUR_DETAIL)), B_COLOUR_SWELL);
		// each lobe has its own tone (measured inside against just outside its border)
		for (int i = 0; i < n_lobes; i++) {
			vec4 box = texelFetch(lobe_tex, ivec2(1, i), 0);
			vec2 low = box.xy * tile_cm - vec2(B_FEAT_SOFT * 3.0);
			vec2 high = box.zw * tile_cm + vec2(B_FEAT_SOFT * 3.0);
			if (at.x < low.x || at.y < low.y || at.x > high.x || at.y > high.y) {
				continue;
			}
			float inside = 1.0 - smoothstep(-B_FEAT_SOFT, B_FEAT_SOFT, lobe_sd(at, i));
			colour *= mix(vec3(1.0), texelFetch(lobe_tex, ivec2(50, i), 0).rgb, inside * B_LOBE_TINT);
		}
		// the dark line along the downhill side of every sharp edge (cavity), a light one on the uphill side
		float edge_value = texelFetch(edge_tex, ivec2(clamp(floor(at / tile_cm * 1024.0), vec2(0.0), vec2(1023.0))), 0).r;
		colour *= 1.0 + clamp(B_EDGE_DARK * edge_value * 3.0, -0.3, 0.2);
		colour *= 1.0 + B_FINE_COLOUR * micro_texture(at, seed + 7.0);
		float crack = texelFetch(crack_tex, ivec2(clamp(floor(at / tile_cm * 1024.0), vec2(0.0), vec2(1023.0))), 0).r;
		colour *= 1.0 - B_CRACK_COLOUR * crack;
	}
	COLOR = vec4(clamp(colour, 0.0, 1.0), h);
}
