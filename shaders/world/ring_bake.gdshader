shader_type canvas_item;
render_mode blend_disabled; // the height is written in alpha: no blending
// Procedural ringed trunk (palm), drawn once into a tile (RingBaker): colour in rgb, height in alpha. The same model as
// tools/bark/ring_gen.py (the reference the 14 numbers were fitted with, RingFits.KEYS), made to tile: the rings are a
// whole number per tile and every noise and hash wraps round the tile.

uniform float p[14];
uniform float tile_cm = 130.0;
uniform vec3 ramp[8];
uniform vec2 height_range = vec2(0.0, 1.0);
uniform float seed = 1.0;

float fract1(float x) {
	return x - floor(x);
}

float hash2(float ix, float iy, float s) {
	return fract1(sin(ix * 127.1 + iy * 311.7 + s * 74.7) * 43758.5453);
}

float hashw(float ix, float iy, float s, vec2 per) {
	return hash2(ix - per.x * floor(ix / per.x + 0.001), iy - per.y * floor(iy / per.y + 0.001), s); // (not mod(): the GPU divides as x * (1 / y) and mod(75.0, 75.0) can come out 75)
}

float vnoise(vec2 at, float sx, float sy, float s) {
	vec2 per = vec2(max(floor(tile_cm / sx + 0.5), 1.0), max(floor(tile_cm / sy + 0.5), 1.0));
	vec2 q = at / tile_cm * per;
	vec2 i = floor(q);
	vec2 f = q - i;
	f = f * f * (3.0 - 2.0 * f);
	float a = hashw(i.x, i.y, s, per);
	float b = hashw(i.x + 1.0, i.y, s, per);
	float c = hashw(i.x, i.y + 1.0, s, per);
	float d = hashw(i.x + 1.0, i.y + 1.0, s, per);
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

float rings(vec2 at, float s) {
	float rows = max(floor(tile_cm / p[0] + 0.5), 1.0);
	float ring_cm = tile_cm / rows;
	float y = at.y + p[5] * ring_cm * 2.0 * (vnoise(at, p[4], p[4] * 2.0, s + 1.0) - 0.5);
	float row_f = floor(y / ring_cm);
	vec2 per = vec2(rows, 1.0);
	float centre = (row_f + 0.5 + (hashw(row_f, 0.0, s + 2.0, per) - 0.5) * p[1]) * ring_cm;
	float width = ring_cm * p[2] * (0.6 + 0.8 * hashw(row_f, 0.0, s + 3.0, per));
	float d = y - centre;
	float line = 1.0 - smoothstep(0.0, width * 0.25, abs(d));
	float ramp_d = d > 0.0 ? 1.0 - smoothstep(0.0, ring_cm * 0.4, d) : 0.0;
	float band = line - ramp_d * (0.4 + 1.2 * p[6]);
	float fib = vnoise(at, p[7], p[9], s + 6.0) - 0.5;
	float blotch = vnoise(at, p[10], p[10], s + 7.0) - 0.5;
	float fine = vnoise(at, max(p[12], 1.6), max(p[12], 1.6), s + 8.0) - 0.5; // (finer cells made the parallax a mosaic)
	return 0.5 + p[3] * band + p[8] * 0.4 * fib + p[11] * blotch + p[13] * fine;
}

float norm(float h) {
	return clamp((h - height_range.x) / max(height_range.y - height_range.x, 0.001), 0.0, 1.0);
}

void fragment() {
	vec2 at = UV * tile_cm;
	float h = norm(rings(at, seed));
	float t = h * 7.0;
	int i0 = int(floor(t));
	int i1 = min(i0 + 1, 7);
	vec3 colour = mix(ramp[i0], ramp[i1], t - float(i0));
	// the photographed palm is a grey-tan trunk: darker under each ring, pale streaks, white lichen specks, fine grain
	float tone = 0.8 + 0.4 * h;
	float fine = vnoise(at, 0.9, 0.9, seed + 31.0) - 0.5;
	float fine2 = vnoise(at, 0.45, 0.45, seed + 33.0) - 0.5;
	float streak = vnoise(at, 0.5, 6.0, seed + 35.0) - 0.5;
	float mottle = vnoise(at, 7.0, 18.0, seed + 37.0) - 0.5;
	tone *= 1.0 + 0.22 * fine + 0.18 * fine2 + 0.2 * streak + 0.22 * mottle;
	// round white drops: a jittered grid of small discs (0.9 cm cells), more of them on some rings, slightly stretched along the trunk
	float drops = 0.0;
	vec2 drop_n = max(floor(vec2(tile_cm) / vec2(0.9, 1.3) + 0.5), vec2(1.0));
	vec2 cell_size = vec2(tile_cm) / drop_n; // (a whole number of cells per tile, hashes wrapping: the tile repeats)
	vec2 gc = floor(at / cell_size);
	float density = smoothstep(0.2, 0.7, vnoise(at, 10.0, 24.0, seed + 41.0));
	for (int oy = -1; oy <= 1; oy++) {
		for (int ox = -1; ox <= 1; ox++) {
			vec2 cell = gc + vec2(float(ox), float(oy));
			if (hashw(cell.x, cell.y, seed + 131.0, drop_n) < 0.05 + 0.75 * density * density) {
				vec2 centre = (cell + vec2(hashw(cell.x, cell.y, seed + 133.0, drop_n), hashw(cell.x, cell.y, seed + 135.0, drop_n))) * cell_size;
				float radius = 0.1 + 0.3 * hashw(cell.x, cell.y, seed + 137.0, drop_n);
				vec2 d = (at - centre) / vec2(1.0, 1.4);
				drops = max(drops, 1.0 - smoothstep(radius * 0.7, radius, length(d)));
			}
		}
	}
	float lichen = drops;
	vec3 painted = ramp[4] * tone;
	painted = mix(painted, vec3(0.92, 0.9, 0.84), 0.95 * lichen);
	COLOR = vec4(clamp(painted, 0.0, 1.0), clamp(0.5 + (h - 0.5) * 1.1, 0.0, 1.0)); // (a little deeper than the fitted height)
}
