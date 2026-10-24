shader_type canvas_item;
render_mode blend_disabled; // the height is written in alpha: no blending
// Procedural plated bark (pine), drawn once into a tile (PlateBaker): colour in rgb, height in alpha. The same model
// as tools/bark/plate_gen.py (the reference the 14 numbers were fitted with, PlateFits.KEYS), made to tile: the
// cells are a whole number per tile and every hash wraps round the tile.

uniform float p[14];
uniform float tile_cm = 200.0;
uniform vec3 ramp[8];
uniform vec2 height_range = vec2(0.0, 1.0);
uniform float seed = 1.0;
uniform float flat_rock = 0.0; // 0..1: a rock's flat-lit colour (pitted rock) instead of the height ramp
uniform float guide[256]; // the photograph's height as a 16 x 16 picture (row by row), steering each plate's tone
uniform float guide_mix = 0.0; // 0: all the plates' own tones (fully procedural); 1: the guide's
uniform vec3 palette[3]; // the photograph's main colours, brightest first
uniform vec3 palette_shares = vec3(0.34, 0.33, 0.33);
uniform float palette_mix = 0.0; // 0: the ramp by height alone; 1: each plate takes one of the palette colours

float fract1(float x) {
	return x - floor(x);
}

float hash2(float ix, float iy, float s) {
	return fract1(sin(ix * 127.1 + iy * 311.7 + s * 74.7) * 43758.5453);
}

float hashw(float ix, float iy, float s, vec2 per) {
	return hash2(mod(ix, per.x), mod(iy, per.y), s);
}

float vnoise(vec2 at, float scale, float s) {
	float n = max(floor(tile_cm / scale + 0.5), 1.0);
	vec2 per = vec2(n);
	vec2 q = at / tile_cm * n;
	vec2 i = floor(q);
	vec2 f = q - i;
	f = f * f * (3.0 - 2.0 * f);
	float a = hashw(i.x, i.y, s, per);
	float b = hashw(i.x + 1.0, i.y, s, per);
	float c = hashw(i.x, i.y + 1.0, s, per);
	float d = hashw(i.x + 1.0, i.y + 1.0, s, per);
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

float plates(vec2 at, float s, out float dice, out float rim) {
	float cell = p[0];
	float stretch = p[1];
	float nu = max(floor(tile_cm / cell + 0.5), 1.0);
	float nv = max(floor(tile_cm / (cell * stretch) + 0.5), 1.0);
	cell = tile_cm / nu;
	float cell_v = tile_cm / nv;
	float st = cell_v / cell;
	vec2 per = vec2(nu, nv);
	float wx = at.x + cell * p[4] * 2.0 * (vnoise(at, p[3], s + 1.0) - 0.5);
	float wy = at.y + cell * p[4] * 2.0 * (vnoise(at + vec2(9.0, 0.0), p[3], s + 2.0) - 0.5);
	wx += cell * p[13] * 2.0 * (vnoise(at, p[12], s + 3.0) - 0.5);
	float u = wx / cell;
	float v = wy / cell_v;
	float iu = floor(u);
	float iv = floor(v);
	float d1 = 1e9;
	float d2 = 1e9;
	vec2 best_id = vec2(0.0);
	vec2 best_d = vec2(0.0);
	vec2 best_f = vec2(0.0);
	for (int oy = -1; oy <= 1; oy++) {
		for (int ox = -1; ox <= 1; ox++) {
			float cx = iu + float(ox);
			float cy = iv + float(oy);
			float fx = cx + 0.5 + (hashw(cx, cy, s + 5.0, per) - 0.5) * p[2];
			float fy = cy + 0.5 + (hashw(cx, cy, s + 7.0, per) - 0.5) * p[2];
			vec2 dd = vec2(u - fx, (v - fy) * st * 0.6);
			float d = length(dd);
			if (d < d1) {
				d2 = d1;
				d1 = d;
				best_id = vec2(cx, cy);
				best_d = dd;
				best_f = vec2(fx, fy);
			} else if (d < d2) {
				d2 = d;
			}
		}
	}
	float edge = d2 - d1;
	rim = 1.0 - smoothstep(0.0, p[7] * 0.14, edge);
	dice = hashw(best_id.x, best_id.y, s + 19.0, per);
	float crack = 1.0 - smoothstep(0.0, p[5] * 0.22, edge);
	float lipf = smoothstep(0.0, p[7] * 0.12, edge); // (a sharp lip: a step, not a ramp)
	vec2 centre = mod(vec2(best_f.x * cell, best_f.y * cell_v) / tile_cm, 1.0);
	int gi = clamp(int(centre.y * 16.0), 0, 15);
	int gj = clamp(int(centre.x * 16.0), 0, 15);
	float z = 0.7 + p[8] * (hashw(best_id.x, best_id.y, s + 11.0, per) - 0.5);
	z = mix(z, 0.35 + 0.7 * guide[gi * 16 + gj], guide_mix);
	z += p[9] * (best_d.x * (hashw(best_id.x, best_id.y, s + 13.0, per) - 0.5)
			+ best_d.y * (hashw(best_id.x, best_id.y, s + 15.0, per) - 0.5));
	z += p[11] * (vnoise(at, max(p[10], 1.6), s + 17.0) - 0.5); // (finer cells made the parallax a mosaic)
	// each plate is not flat: a soft dome, pitting and weathering at 1-6 cm (not finer: parallax turns pixel noise into a mosaic)
	float dome = 1.0 - clamp(length(best_d) * 0.9, 0.0, 1.0);
	float weather = (vnoise(at, 5.0, s + 121.0) - 0.5) * 0.5 + (vnoise(at, 2.4, s + 123.0) - 0.5) * 0.4 + (vnoise(at, 1.3, s + 125.0) - 0.5) * 0.25;
	z += 0.06 * dome + 0.07 * weather;
	return z * (0.55 + 0.45 * lipf) * (1.0 - p[6] * crack);
}

float norm(float h) {
	return clamp((h - height_range.x) / max(height_range.y - height_range.x, 0.001), 0.0, 1.0);
}

void fragment() {
	vec2 at = UV * tile_cm;
	float dice;
	float rim;
	float h = norm(plates(at, seed, dice, rim));
	float t = h * 7.0;
	int i0 = int(floor(t));
	int i1 = min(i0 + 1, 7);
	vec3 colour = mix(ramp[i0], ramp[i1], t - float(i0));
	vec3 plate_colour = dice < palette_shares.x ? palette[0]
			: (dice < palette_shares.x + palette_shares.y ? palette[1] : palette[2]);
	plate_colour = mix(palette[2], plate_colour, smoothstep(0.05, 0.45, h));
	colour = mix(colour, plate_colour * (0.75 + 0.5 * h), palette_mix);
	// flat-lit rock plates: the colour stays near the photograph's (the height only tints a little), a grain and soft mottling,
	// and only the cracks are dark
	vec3 base = ramp[5] * vec3(1.18, 1.0, 0.9);
	float g_a = vnoise(at, 2.4, seed + 141.0) - 0.5;
	float g_b = vnoise(at, 5.0, seed + 141.0 + 7.0) - 0.5;
	float g_c = vnoise(at, 9.0, seed + 141.0 + 13.0) - 0.5;
	colour = mix(colour, base * (1.0 + 0.12 * g_a + 0.26 * g_b + 0.3 * g_c), flat_rock);
	// crisp small detail that survives zoom (warped noise: no grid alignment) on the flat-lit rock: dark pits and mineral grains,
	// grey and pale lichen flecks, and a per-pixel grain
	vec2 warped = at + 0.5 * vec2(vnoise(at, 1.6, seed + 151.0) - 0.5, vnoise(at, 1.8, seed + 153.0) - 0.5) * 2.0;
	float pit = smoothstep(0.74, 0.8, vnoise(warped, 0.6, seed + 155.0)) * smoothstep(0.35, 0.6, vnoise(at, 8.0, seed + 157.0));
	float grey = smoothstep(0.7, 0.76, vnoise(warped, 1.0, seed + 159.0)) * smoothstep(0.45, 0.7, vnoise(at, 6.0, seed + 161.0));
	float yellow = smoothstep(0.84, 0.88, vnoise(warped, 0.5, seed + 163.0));
	float pixel_grain = fract(sin(dot(floor(UV * 1024.0), vec2(12.9898, 78.233))) * 43758.5453) - 0.5;
	colour = mix(colour, colour * 0.45, 0.7 * pit * flat_rock);
	colour = mix(colour, vec3(0.62, 0.6, 0.6), 0.5 * grey * flat_rock);
	colour = mix(colour, vec3(0.78, 0.78, 0.4), 0.55 * yellow * flat_rock);
	colour *= 1.0 + 0.16 * pixel_grain * flat_rock;
	colour *= 1.0 - mix(0.7, 0.5, flat_rock) * rim; // the shadow where one plate meets the next
	COLOR = vec4(clamp(colour, 0.0, 1.0), clamp(0.5 + (h - 0.5) * 2.0, 0.0, 1.0)); // (a deeper relief than the fitted height)
}
