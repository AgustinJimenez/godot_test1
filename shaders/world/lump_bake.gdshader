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
uniform float guide_mix = 0.0; // 0: the lumps' own noise (fully procedural); 1: the guide's

float fract1(float x) {
	return x - floor(x);
}

float hash2(float ix, float iy, float s) {
	return fract1(sin(ix * 127.1 + iy * 311.7 + s * 74.7) * 43758.5453);
}

float hashw(float ix, float iy, float s, float per) {
	return hash2(mod(ix, per), mod(iy, per), s);
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
	l = mix(l, guide_at(at), guide_mix);
	float h = 0.5 + p[1] * (l - 0.5) - p[6] * crease;
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
	h += p[14] * (0.5 * vnoise(w, mid, s + 19.0) + 0.5 * vnoise(vec2(w.y * 1.3 + 5.0, w.x * 0.8), mid, s + 21.0) - 0.5);
	if (rim_lobes > 0.0) {
		// smooth lobes with a raised rim, a few per tile (the boulder's rounded plates), one candidate per cell
		float ln = max(floor(tile_cm / 32.0 + 0.5), 1.0);
		float cs = tile_cm / ln;
		vec2 lc = floor(at / cs);
		for (int oy = -1; oy <= 1; oy++) {
			for (int ox = -1; ox <= 1; ox++) {
				float cx = lc.x + float(ox);
				float cy = lc.y + float(oy);
				if (hashw(cx, cy, s + 301.0, ln) < 0.3) {
					vec2 centre = vec2(cx + 0.25 + 0.5 * hashw(cx, cy, s + 303.0, ln), cy + 0.25 + 0.5 * hashw(cx, cy, s + 305.0, ln)) * cs;
					float radius = cs * (0.22 + 0.2 * hashw(cx, cy, s + 307.0, ln));
					vec2 d = (at - centre) / vec2(1.0, 0.55 + 0.6 * hashw(cx, cy, s + 309.0, ln));
					float r = length(d) + 0.5 * radius * (vnoise(at, 7.0, s + 311.0) - 0.5);
					float plateau = 1.0 - smoothstep(radius * 0.8, radius, r);
					float t = (r - radius * 0.92) / (radius * 0.07);
					h += rim_lobes * (0.35 * plateau + exp(-t * t));
				}
			}
		}
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
	// fine relief at 1-5 cm (not finer: parallax turns pixel noise into a mosaic): weathering
	float fr = (vnoise(at, 4.5, s + 111.0) - 0.5) * 0.5 + (vnoise(at, 2.2, s + 113.0) - 0.5) * 0.4 + (vnoise(at, 1.2, s + 115.0) - 0.5) * 0.3;
	h += 0.045 * fr;
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
	float rg = 0.0;
	rg += 1.0 * (vnoise(at, 8.0, seed + 91.0) - 0.5);
	rg += 0.8 * (vnoise(at, 3.0, seed + 93.0) - 0.5);
	rg += 0.7 * (vnoise(at, 1.2, seed + 95.0) - 0.5);
	rg += 0.6 * (vnoise(at, 0.9, seed + 97.0) - 0.5);
	rg += 0.4 * (vnoise(at, 0.5, seed + 99.0) - 0.5);
	float pit = smoothstep(0.72, 0.84, vnoise(at, 1.3, seed + 101.0));
	float mineral = smoothstep(0.82, 0.92, vnoise(at, 2.4, seed + 103.0));
	colour *= clamp(0.88 + 0.4 * rg, 0.5, 1.5);
	// crisp small detail that survives zoom: speckles and flecks from a warped noise (the warp breaks the grid alignment of the
	// cells), plus a per-pixel grain; the dark ones are pits and mineral grains, the pale ones quartz flecks
	vec2 warped = at + 0.55 * vec2(vnoise(at, 1.7, seed + 151.0) - 0.5, vnoise(at, 1.9, seed + 153.0) - 0.5) * 2.0;
	float fleck_d = smoothstep(0.74, 0.8, vnoise(warped, 0.55, seed + 155.0)) * smoothstep(0.4, 0.62, vnoise(at, 7.0, seed + 157.0));
	float fleck_p = smoothstep(0.78, 0.83, vnoise(warped, 0.45, seed + 159.0)) * smoothstep(0.55, 0.75, vnoise(at, 5.0, seed + 161.0));
	float pixel_grain = fract(sin(dot(floor(UV * 1024.0), vec2(12.9898, 78.233))) * 43758.5453) - 0.5;
	colour = mix(colour, colour * 0.5, 0.6 * fleck_d);
	colour = mix(colour, vec3(0.86, 0.83, 0.77), 0.4 * fleck_p);
	colour *= 1.0 + 0.2 * pixel_grain;
	colour = mix(colour, colour * 0.55, 0.5 * pit);
	colour = mix(colour, vec3(0.85, 0.82, 0.76), 0.1 * mineral);
	COLOR = vec4(clamp(colour, 0.0, 1.0), h);
}
