shader_type canvas_item;
render_mode blend_disabled; // the height is written in alpha: no blending
// Procedural oak boards, drawn once into a tile (WoodBaker): colour in rgb, height in alpha. The same model as
// tools/bark/wood_gen.py (the reference the 20 numbers were fitted with, WoodFits.KEYS), made to tile: every
// scale is a whole number of repeats in the tile and the cell hashes wrap round the tile.

uniform float p[20];
uniform float tile_cm = 120.0;
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
	return hash2(mod(ix, per.x), mod(iy, per.y), s);
}

float whole(float scale) {
	return tile_cm / max(floor(tile_cm / scale + 0.5), 1.0);
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

float wood(vec2 at, float s) {
	float board = whole(p[0]);
	float rows = tile_cm / board;
	float row_f = at.y / board;
	float row = floor(row_f);
	float jit = (hashw(row, 0.0, s + 1.0, vec2(rows, 1.0)) - 0.5) * p[1];
	float local = row_f - row - jit;
	float seam = (local > -0.5 && local < 1.5) ? 1.0 - smoothstep(0.0, p[2], min(local, 1.0 - local) * 2.0) : 0.0;
	float id_row = floor(row_f - jit);
	float tone = (hashw(id_row, 0.0, s + 3.0, vec2(rows, 1.0)) - 0.5) * p[4];
	float shift = hashw(id_row, 0.0, s + 5.0, vec2(rows, 1.0)) * 1000.0;
	// knots
	float kn = whole(p[10]);
	vec2 kper = vec2(tile_cm / kn);
	vec2 kc = floor(at / kn);
	float bend = 0.0;
	float ring = 0.0;
	for (int oy = -1; oy <= 1; oy++) {
		for (int ox = -1; ox <= 1; ox++) {
			float cx = kc.x + float(ox);
			float cy = kc.y + float(oy);
			if (hashw(cx, cy, s + 11.0, kper) < p[11]) {
				vec2 k = vec2((cx + 0.2 + 0.6 * hashw(cx, cy, s + 13.0, kper)) * kn,
						(cy + 0.2 + 0.6 * hashw(cx, cy, s + 15.0, kper)) * kn);
				vec2 d = vec2((at.x - k.x) / 2.2, at.y - k.y);
				float dist = length(d);
				float r = kn * 0.28;
				float w = 1.0 - smoothstep(0.0, r, dist);
				bend += w * 6.0;
				ring += w * sin(dist / r * p[12] * 3.14159);
			}
		}
	}
	float grain_cm = tile_cm / max(floor(tile_cm / p[5] + 0.5), 1.0);
	float wob = (vnoise(at, p[7], p[7] * 0.5, s + 21.0) - 0.5) * p[8] * grain_cm * 4.0;
	float u = (at.y + wob + bend + shift) / grain_cm;
	float line = abs(fract1(u) - 0.5) * 2.0;
	float grain = (pow(line, p[9]) - 0.4) * p[6];
	float swell = p[16] * (vnoise(at, p[17], p[17] * 0.4, s + 31.0) - 0.5);
	float fine = p[14] * (vnoise(at, p[15], p[15] * 0.5, s + 41.0) - 0.5);
	float pores = p[18] * (vnoise(at, p[19], p[19] * 3.0, s + 51.0) - 0.5);
	float h = 0.5 + tone + grain + swell + fine + pores + p[13] * ring * 0.2;
	return h * (1.0 - p[3] * seam);
}

float norm(float h) {
	return clamp((h - height_range.x) / max(height_range.y - height_range.x, 0.001), 0.0, 1.0);
}

void fragment() {
	vec2 at = UV * tile_cm;
	float h = norm(wood(at, seed));
	// the grain lines are small steps of height: show them as light and dark (brightness follows how far a point
	// sits above its neighbours across the board), over the boards' own tones
	float around = 0.5 * (norm(wood(at + vec2(0.0, 0.5), seed)) + norm(wood(at - vec2(0.0, 0.5), seed)));
	float line = h - around;
	float t = h * 7.0;
	int i0 = int(floor(t));
	int i1 = min(i0 + 1, 7);
	vec3 colour = mix(ramp[i0], ramp[i1], t - float(i0));
	colour *= clamp(1.0 + 5.0 * line, 0.55, 1.45);
	COLOR = vec4(clamp(colour, 0.0, 1.0), h);
}
