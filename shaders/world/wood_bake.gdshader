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
	// the colour is painted as wood, not from the ripple height: long gentle grain lines along the board, fine pores,
	// a tone per board and slow waves; the height (the fitted relief) only shades it a little
	float board_cm = whole(p[0]);
	float row = floor(at.y / board_cm);
	float board_tone = hash2(row, 0.0, seed + 91.0) - 0.5;
	float wave = (vnoise(at, 40.0, 14.0, seed + 93.0) - 0.5) * 3.0;
	// cathedral arches: the grain lines bend in a broad hump around two centres on each board (where the tree's rings
	// came near the surface), so the stripes close into arches like the photographed oak
	float arch = 0.0;
	for (int k = 0; k < 2; k++) {
		float cx = hash2(row, float(k), seed + 111.0) * tile_cm;
		float dx = abs(at.x - cx);
		dx = min(dx, tile_cm - dx);
		float width = 9.0 + 13.0 * hash2(row, float(k), seed + 113.0);
		float lift = (hash2(row, float(k), seed + 115.0) - 0.5) * 2.0 * board_cm * 0.38;
		arch += lift * exp(-(dx * dx) / (width * width));
	}
	float lines = vnoise(vec2(at.x * 0.18, at.y + wave + arch), 160.0, 0.55, seed + 95.0) - 0.5;
	float lines2 = vnoise(vec2(at.x * 0.35, at.y + 0.6 * wave), 90.0, 0.3, seed + 97.0) - 0.5;
	float pores = smoothstep(0.78, 0.95, vnoise(at, 3.2, 0.3, seed + 99.0));
	float local_row = fract(at.y / board_cm);
	float seam = 1.0 - smoothstep(0.0, 0.02, min(local_row, 1.0 - local_row));
	float ring = vnoise(at, 7.0, 1.6, seed + 103.0) - 0.5;
	float cloud = vnoise(at, 36.0, 10.0, seed + 101.0) - 0.5;
	float tone = 1.0 + 0.28 * board_tone + 0.2 * lines + 0.14 * lines2 + 0.16 * cloud;
	vec3 colour = ramp[4] * tone * (0.9 + 0.2 * h);
	colour *= 1.0 + 0.2 * ring;
	colour = mix(colour, ramp[1] * 0.75, 0.35 * pores);
	// crisp fine grain: thin dark lines along the board at 0.2-0.5 cm, bent by the slow wave, and pore dashes
	float fine1 = vnoise(vec2(at.x * 0.1, at.y + wave * 0.7 + arch), 120.0, 0.28, seed + 105.0) - 0.5;
	float fine2 = vnoise(vec2(at.x * 0.06, at.y + wave * 0.5 + arch), 200.0, 0.17, seed + 107.0) - 0.5;
	float line_hard = smoothstep(0.1, 0.22, abs(fine1)) - 0.5;
	colour *= 1.0 - 0.16 * line_hard + 0.22 * fine1 + 0.18 * fine2;
	float dash = smoothstep(0.82, 0.95, vnoise(at, 1.8, 0.2, seed + 109.0));
	colour = mix(colour, colour * 0.6, 0.45 * dash);
	// a few knots: dark oval cores with ring lines round them, one candidate per 40 cm cell, on about a third of the cells
	float knot = 0.0;
	float knot_ring = 0.0;
	vec2 kc = floor(at / 40.0);
	for (int oy = -1; oy <= 1; oy++) {
		for (int ox = -1; ox <= 1; ox++) {
			vec2 cell = kc + vec2(float(ox), float(oy));
			float chance = hash2(cell.x, cell.y, seed + 121.0);
			if (chance < 0.34) {
				vec2 centre = (cell + vec2(0.2 + 0.6 * hash2(cell.x, cell.y, seed + 123.0), 0.2 + 0.6 * hash2(cell.x, cell.y, seed + 125.0))) * 40.0;
				vec2 d = (at - centre) / vec2(2.3, 1.0);
				float r = length(d);
				float size = 0.9 + 1.1 * hash2(cell.x, cell.y, seed + 127.0);
				knot = max(knot, 1.0 - smoothstep(size * 0.5, size * 0.9, r));
				knot_ring = max(knot_ring, (1.0 - smoothstep(size * 2.2, size * 7.0, r)) * (0.5 + 0.5 * sin(r * 3.1)));
			}
		}
	}
	colour *= 1.0 - 0.5 * knot - 0.07 * knot_ring;
	colour *= 1.0 - 0.45 * seam;
	COLOR = vec4(clamp(colour, 0.0, 1.0), h);
}
