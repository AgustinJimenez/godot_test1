shader_type canvas_item;
render_mode blend_disabled; // the height is written in alpha: no blending
// Procedural fine soil (clods, grain, dust, crumbs, pebbles, twigs), drawn once into a tile (SoilBaker): colour in rgb,
// height in alpha. The same model as tools/bark/soil_gen.py (SoilFits.KEYS, 16 numbers), made to tile. The colour: the
// sand colour, with red lumps where a coarse noise is high and on the pebbles.

uniform float p[16];
uniform float tile_cm = 100.0;
uniform vec3 sand_colour = vec3(0.55, 0.43, 0.30);
uniform vec3 red_colour = vec3(0.62, 0.27, 0.18);
uniform float red_share = 0.25; // how much of the ground the red lumps cover
uniform vec2 height_range = vec2(0.0, 1.0);
uniform float seed = 1.0;

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
	return mix(mix(hashw(i.x, i.y, s, n), hashw(i.x + 1.0, i.y, s, n), f.x),
			mix(hashw(i.x, i.y + 1.0, s, n), hashw(i.x + 1.0, i.y + 1.0, s, n), f.x), f.y);
}

float soil(vec2 at, float s, out float pebble_id) {
	float h = 0.5 + p[1] * (vnoise(at, p[0], s + 1.0) - 0.5) + p[3] * (vnoise(at, max(p[2], 0.7), s + 2.0) - 0.5);
	h += p[5] * (vnoise(at, max(p[4], 0.7), s + 3.0) - 0.5);
	h += p[15] * (abs(vnoise(at, max(p[14], 1.0), s + 4.0) - 0.5) * 2.0 - 0.5);
	float n = max(floor(tile_cm / p[6] + 0.5), 1.0);
	vec2 u = at / tile_cm * n;
	vec2 iu = floor(u);
	float best = 0.0;
	pebble_id = 0.0;
	for (int oy = -1; oy <= 1; oy++) {
		for (int ox = -1; ox <= 1; ox++) {
			float cx = iu.x + float(ox);
			float cy = iu.y + float(oy);
			if (hashw(cx, cy, s + 11.0, n) < p[7]) {
				vec2 k = vec2(cx + 0.2 + 0.6 * hashw(cx, cy, s + 13.0, n), cy + 0.2 + 0.6 * hashw(cx, cy, s + 15.0, n));
				float r = p[8] * (0.5 + hashw(cx, cy, s + 17.0, n));
				float d = length(u - k);
				float v = 1.0 - smoothstep(r * 0.5, r, d);
				if (v > best) {
					best = v;
					pebble_id = hashw(cx, cy, s + 19.0, n);
				}
			}
		}
	}
	h += p[9] * best;
	return h;
}

float norm(float h) {
	return clamp((h - height_range.x) / max(height_range.y - height_range.x, 0.001), 0.0, 1.0);
}

void fragment() {
	vec2 at = UV * tile_cm;
	float pid;
	float h = norm(soil(at, seed, pid));
	// red lumps: where a coarse noise is high, and the pebbles that are red ones
	float lump = vnoise(at, 6.0, seed + 31.0) * 0.7 + vnoise(at, 2.5, seed + 33.0) * 0.3;
	float edge = 0.6 - 0.9 * (red_share - 0.19); // (the value noise spreads about 0.5 +- 0.12: the threshold for the share)
	float red = smoothstep(edge - 0.04, edge + 0.04, lump);
	vec3 colour = mix(sand_colour, red_colour, red);
	// the tone follows the coarse noise and the height only a little (the finest height cells would show as pixels)
	colour *= 0.55 + 0.9 * (0.5 * vnoise(at, 4.0, seed + 35.0) + 0.5 * vnoise(at, 1.8, seed + 37.0));
	colour *= 0.8 + 0.4 * smoothstep(0.2, 0.9, h);
	COLOR = vec4(clamp(colour, 0.0, 1.0), h);
}
