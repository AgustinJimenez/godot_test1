shader_type canvas_item;
render_mode blend_disabled; // the height is written in alpha: no blending
// The procedural rock, drawn once into a tile (RockBaker): colour in rgb, height in alpha. The same model as
// tools/bark/rock_gen.py (the reference the numbers were fitted with), made to tile: every scale is a whole
// number of repeats in the tile, the strata run along a whole-number direction, the random choices of a
// cell are hashed from the cell wrapped round the tile. The 24 numbers are the fit of one photographed rock
// (rock_fits.gd, made by tools/bark/export_rock.py); the order is RockFits.KEYS.

uniform float p[24];
uniform float tile_cm = 200.0;
uniform vec3 ramp[8];
uniform vec3 mean_colour = vec3(0.5, 0.45, 0.4);
uniform vec3 shading = vec3(0.4, 0.05, 0.2); // cavity gain, mottle, unused
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

float vnoise(vec2 at_cm, float scale, float s) {
	float per1 = max(floor(tile_cm / scale + 0.5), 1.0);
	vec2 per = vec2(per1);
	vec2 q = at_cm / tile_cm * per;
	vec2 i = floor(q);
	vec2 f = q - i;
	f = f * f * (3.0 - 2.0 * f);
	float a = hashw(i.x, i.y, s, per);
	float b = hashw(i.x + 1.0, i.y, s, per);
	float c = hashw(i.x, i.y + 1.0, s, per);
	float d = hashw(i.x + 1.0, i.y + 1.0, s, per);
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

float rock(vec2 at, float s) {
	float wx = (vnoise(at, p[19], s + 11.0) - 0.5) * 2.0;
	float wy = (vnoise(at + vec2(31.7, 0.0), p[19], s + 13.0) - 0.5) * 2.0;
	vec2 w = at + vec2(wx, wy) * p[18];
	// blocks and cracks
	float cell = whole(p[0]);
	vec2 per = vec2(tile_cm / cell);
	vec2 q = w / cell;
	vec2 ic = floor(q);
	vec2 fc = q - ic;
	float d1 = 9.0;
	float d2 = 9.0;
	float cid = 0.0;
	vec2 rel = vec2(0.0);
	for (int oy = -1; oy <= 1; oy++) {
		for (int ox = -1; ox <= 1; ox++) {
			float cx = ic.x + float(ox);
			float cy = ic.y + float(oy);
			vec2 a = vec2(float(ox) + 0.5 + (hashw(cx, cy, s, per) - 0.5) * p[1] - fc.x,
					float(oy) + 0.5 + (hashw(cx, cy, s + 3.1, per) - 0.5) * p[1] - fc.y);
			float d = length(a);
			if (d < d1) {
				d2 = d1;
				d1 = d;
				cid = hashw(cx, cy, s + 7.7, per);
				rel = -a;
			} else if (d < d2) {
				d2 = d;
			}
		}
	}
	float edge = smoothstep(0.0, p[2], d2 - d1);
	float cover = 1.0 - smoothstep(p[4] - 0.08, p[4] + 0.08, vnoise(w, 40.0, s + 71.0));
	float cracks = 1.0 - p[3] * (1.0 - edge) * cover;
	float block = p[5] * (cid - 0.5) + p[6] * (rel.x * 0.6 + rel.y * 0.4);
	// strata: the direction is a whole number of repeats across the tile
	float n = floor(tile_cm * cos(p[9]) / p[7] + 0.5);
	float m = floor(tile_cm * sin(p[9]) / p[7] + 0.5);
	float along = (w.x * n + w.y * m) / tile_cm + p[10] * (vnoise(w, 35.0, s + 21.0) - 0.5);
	float strata = p[8] * sin(6.2831853 * along);
	float base = p[11] * (vnoise(w, p[12], s + 31.0) + 0.5 * vnoise(w, p[12] * 0.4, s + 33.0));
	float grain = p[13] * (vnoise(at, p[14], s + 41.0) - 0.5);
	// pits
	float pit = whole(p[15]);
	vec2 pper = vec2(tile_cm / pit);
	vec2 pc = floor(at / pit);
	float pits = 0.0;
	for (int oy = -1; oy <= 1; oy++) {
		for (int ox = -1; ox <= 1; ox++) {
			float cx = pc.x + float(ox);
			float cy = pc.y + float(oy);
			if (hashw(cx, cy, s + 51.0, pper) < p[16]) {
				vec2 a = vec2((cx + 0.2 + 0.6 * hashw(cx, cy, s + 53.0, pper)) * pit - at.x,
						(cy + 0.2 + 0.6 * hashw(cx, cy, s + 55.0, pper)) * pit - at.y);
				float r = pit * (0.12 + 0.2 * hashw(cx, cy, s + 57.0, pper));
				pits = max(pits, 1.0 - smoothstep(0.0, r, length(a)));
			}
		}
	}
	// rubble
	float rub = whole(p[20]);
	vec2 rper = vec2(tile_cm / rub);
	vec2 rq = at / rub;
	vec2 rc = floor(rq);
	vec2 rf = rq - rc;
	float r1 = 9.0;
	float rid = 0.0;
	vec2 rrel = vec2(0.0);
	for (int oy = -1; oy <= 1; oy++) {
		for (int ox = -1; ox <= 1; ox++) {
			float cx = rc.x + float(ox);
			float cy = rc.y + float(oy);
			vec2 a = vec2(float(ox) + 0.5 + (hashw(cx, cy, s + 61.0, rper) - 0.5) * 0.9 - rf.x,
					float(oy) + 0.5 + (hashw(cx, cy, s + 63.0, rper) - 0.5) * 0.9 - rf.y);
			float d = length(a);
			if (d < r1) {
				r1 = d;
				rid = hashw(cx, cy, s + 65.0, rper);
				rrel = -a;
			}
		}
	}
	float rub_mask = 1.0 - smoothstep(p[22] - 0.1, p[22] + 0.1, vnoise(at, 22.0, s + 67.0));
	float near_crack = 1.0 - smoothstep(0.0, p[2] * 4.0, d2 - d1);
	rub_mask = min(max(rub_mask * (1.0 - p[23]), near_crack * cover * p[23] * 2.0), 1.0);
	float rubble = p[21] * ((rid - 0.5) + 0.8 * (rrel.x * 0.7 + rrel.y * 0.5)) * rub_mask;
	return (0.5 + block + base + strata + grain) * cracks - p[17] * pits + rubble;
}

float norm(float h) {
	return clamp((h - height_range.x) / max(height_range.y - height_range.x, 0.001), 0.0, 1.0);
}

void fragment() {
	vec2 at = UV * tile_cm;
	float h = norm(rock(at, seed));
	float around = 0.25 * (norm(rock(at + vec2(2.0, 0.0), seed)) + norm(rock(at - vec2(2.0, 0.0), seed))
			+ norm(rock(at + vec2(0.0, 2.0), seed)) + norm(rock(at - vec2(0.0, 2.0), seed)));
	float cavity = h - around;
	float mottle = vnoise(at, 20.0, seed + 91.0) - 0.5;
	float light = (1.0 + shading.x * cavity * 6.0) * (1.0 + shading.y * mottle * 6.0);
	float t = h * 7.0;
	int i0 = int(floor(t));
	int i1 = min(i0 + 1, 7);
	vec3 ramp_colour = mix(ramp[i0], ramp[i1], t - float(i0));
	COLOR = vec4(clamp(ramp_colour * clamp(light, 0.5, 1.35), 0.0, 1.0), h);
}
