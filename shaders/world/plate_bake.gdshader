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

float plates(vec2 at, float s, out float dice) {
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
			} else if (d < d2) {
				d2 = d;
			}
		}
	}
	float edge = d2 - d1;
	dice = hashw(best_id.x, best_id.y, s + 19.0, per);
	float crack = 1.0 - smoothstep(0.0, p[5], edge);
	float lipf = smoothstep(0.0, p[7], edge);
	float z = 0.7 + p[8] * (hashw(best_id.x, best_id.y, s + 11.0, per) - 0.5);
	z += p[9] * (best_d.x * (hashw(best_id.x, best_id.y, s + 13.0, per) - 0.5)
			+ best_d.y * (hashw(best_id.x, best_id.y, s + 15.0, per) - 0.5));
	z += p[11] * (vnoise(at, p[10], s + 17.0) - 0.5);
	return z * (0.7 + 0.3 * lipf) * (1.0 - p[6] * crack);
}

float norm(float h) {
	return clamp((h - height_range.x) / max(height_range.y - height_range.x, 0.001), 0.0, 1.0);
}

void fragment() {
	vec2 at = UV * tile_cm;
	float dice;
	float h = norm(plates(at, seed, dice));
	float t = h * 7.0;
	int i0 = int(floor(t));
	int i1 = min(i0 + 1, 7);
	vec3 colour = mix(ramp[i0], ramp[i1], t - float(i0));
	vec3 plate_colour = dice < palette_shares.x ? palette[0]
			: (dice < palette_shares.x + palette_shares.y ? palette[1] : palette[2]);
	plate_colour = mix(palette[2], plate_colour, smoothstep(0.05, 0.45, h));
	colour = mix(colour, plate_colour * (0.75 + 0.5 * h), palette_mix);
	COLOR = vec4(clamp(colour, 0.0, 1.0), h);
}
