shader_type canvas_item;
render_mode blend_disabled; // the height is written in alpha: no blending
// The procedural bark, drawn once into a tile (BarkBaker): colour in rgb, height in alpha. The same flake
// model as tools/bark/procedural_bark.py (the reference the numbers were fitted with), made to tile: every
// scale is rounded to a whole number of repeats in the tile, and the random choices of a cell are
// hashed from the cell wrapped round the tile. The 37 numbers are the fit of one photographed bark
// (bark_fits.gd, made by tools/bark/export_fit.py); the order is BarkFits.KEYS.

uniform float p[37];
uniform float tile_cm = 100.0;
uniform vec2 height_range = vec2(0.0, 1.0);
uniform vec3 ramp[8];
uniform vec3 mean_colour = vec3(0.5, 0.45, 0.4);
uniform vec3 shading = vec3(0.4, 0.05, 0.2); // cavity gain, mottle, flake tone spread
uniform float seed = 1.0;
uniform vec3 alpha_map = vec3(1.0, 0.5, 0.5); // the stored height: scale about the generator's mean, moved to the photograph's mean (the shading reads it)

float fract1(float x) {
	return x - floor(x);
}

float hash2(float ix, float iy, float s) {
	return fract1(sin(ix * 127.1 + iy * 311.7 + s * 74.7) * 43758.5453);
}

// a lattice wrapped round a tile of `per` cells
float hashw(float ix, float iy, float s, vec2 per) {
	return hash2(mod(ix, per.x), mod(iy, per.y), s);
}

// value noise with `scale_x` x `scale_y` cm cells, tiling over the tile
float vnoise(vec2 at_cm, float scale_x, float scale_y, float s) {
	vec2 per = vec2(max(floor(tile_cm / scale_x + 0.5), 1.0), max(floor(tile_cm / scale_y + 0.5), 1.0));
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

float whole(float scale) {
	return tile_cm / max(floor(tile_cm / scale + 0.5), 1.0);
}

vec2 flakes(vec2 at, float s) {
	float cw = whole(p[0]);
	float rows = max(floor(tile_cm / (cw * p[1]) + 0.5), 1.0);
	float ch = tile_cm / rows;
	vec2 per = vec2(tile_cm / cw, rows);
	float ix = floor(at.x / cw);
	float iy = floor(at.y / ch);
	float rag_cm = p[14];
	float bite_u = vnoise(at, rag_cm, rag_cm * 1.8, s + 41.0) - 0.5;
	float bite_v = vnoise(at + vec2(17.3, 0.0), rag_cm, rag_cm * 1.8, s + 43.0) - 0.5;
	float best = 0.0;
	float tone = 0.5;
	for (int oy = -2; oy <= 2; oy++) {
		for (int ox = -1; ox <= 1; ox++) {
			float cx = ix + float(ox);
			float cy = iy + float(oy);
			float h0 = hashw(cx, cy, s, per);
			float h1 = hashw(cx, cy, s + 5.3, per);
			float h2 = hashw(cx, cy, s + 10.6, per);
			float h3 = hashw(cx, cy, s + 15.9, per);
			float h4 = hashw(cx, cy, s + 21.2, per);
			vec2 centre = vec2((cx + 0.5 + (h0 - 0.5) * p[5]) * cw, (cy + 0.5 + (h1 - 0.5) * p[5]) * ch);
			float size = 0.55 + p[4] * h2 * h2;
			float half_l = min(ch * p[2] * size, 2.0 * ch);
			float half_w = min(cw * p[3] * size, cw);
			float turn = (h3 - 0.5) * p[6];
			vec2 d = at - centre;
			float rx = d.x * cos(turn) + d.y * sin(turn);
			float ry = -d.x * sin(turn) + d.y * cos(turn);
			float u = rx / half_w + bite_u * p[13] * 4.0;
			float v = ry / half_l + bite_v * p[13] * 2.0;
			float av = clamp(abs(v), 0.0, 1.0);
			float half = (1.0 - p[19]) * (1.0 - pow(av, p[7])) + p[19] * (1.0 - pow(av, 8.0));
			if (abs(v) < 1.0 && abs(u) < half) {
				float dd = 1.0 - abs(u) / max(half, 0.001);
				float rim = smoothstep(0.0, p[8], dd);
				float value = h4 * p[9] + (p[10] + p[11] * dd + p[12] * v) * rim;
				if (value > best) {
					best = value;
					tone = h2;
				}
			}
		}
	}
	return vec2(best, tone);
}

float cuts(vec2 at, float s) {
	float groove_cm = whole(p[20]);
	float lanes = tile_cm / groove_cm;
	float lane_u = at.x / groove_cm + (vnoise(at, 9.0, 30.0, s + 51.0) - 0.5) * 1.2;
	float lane = floor(lane_u);
	float f = lane_u - lane;
	float open_n = vnoise(vec2(mod(lane, lanes) * groove_cm, at.y), groove_cm, groove_cm * 10.0, s + 53.0);
	float open_ = 1.0 - smoothstep(p[22] - 0.05, p[22] + 0.05, open_n);
	float groove = (1.0 - smoothstep(0.0, p[21], min(f, 1.0 - f) * 2.0)) * open_;
	float split_cm = whole(p[23]);
	float rows = tile_cm / split_cm;
	float split_v = at.y / split_cm + (vnoise(at, 7.0, 20.0, s + 55.0) - 0.5) * 0.6;
	float row = floor(split_v);
	float fv = split_v - row;
	float columns = max(floor(tile_cm / (groove_cm * 0.8) + 0.5), 1.0);
	float column = floor(at.x / (tile_cm / columns));
	float on = 1.0 - smoothstep(p[25] - 0.03, p[25] + 0.03, hashw(column, row, s + 57.0, vec2(columns, rows)));
	float split = (1.0 - smoothstep(0.0, p[24], min(fv, 1.0 - fv) * 2.0)) * on;
	return 1.0 - p[26] * max(groove, split);
}

float fibres(vec2 at, float s) {
	float fc = whole(p[33]);
	float lanes = tile_cm / fc;
	float fs = whole(p[34]);
	float rows = tile_cm / fs;
	float u = at.x / fc + (vnoise(at, 7.0, 40.0, s + 81.0) - 0.5) * 0.8;
	float lane = floor(u);
	float f = u - lane;
	float profile = pow(sin(3.14159265 * f), 0.7);
	float piece = floor(at.y / fs + hashw(lane, 0.0, s + 83.0, vec2(lanes, 1.0)));
	vec2 per = vec2(lanes, rows);
	float present = hashw(lane, piece, s + 85.0, per) >= p[35] ? 1.0 : 0.0;
	float tone = hashw(lane, piece, s + 87.0, per);
	return present * profile * (1.0 - p[36] + p[36] * tone);
}

vec2 bark(vec2 at, float s) {
	float wx = (vnoise(at, p[16], p[16], s + 11.0) - 0.5) * 2.0;
	float wy = (vnoise(at + vec2(31.7, 0.0), p[16], p[16], s + 13.0) - 0.5) * 2.0;
	vec2 w = at + vec2(wx * p[15], wy * p[15] * 1.5);
	vec2 fl = flakes(w, s);
	float cover = 1.0 - smoothstep(p[30] - 0.08, p[30] + 0.08, vnoise(at, 18.0, 40.0, s + 71.0));
	float base = p[27] * (vnoise(at, p[28], p[28] * p[29], s + 73.0) + 0.5 * vnoise(at, p[28] * 0.4, p[28] * 0.4 * p[29], s + 75.0));
	float h = base + p[31] * fl.x * cuts(w, s) * cover + p[32] * fibres(at, s);
	float fine = vnoise(at, p[18], p[18] * 2.0, s + 29.0);
	return vec2(h + (fine - 0.5) * p[17] * (h > 0.05 ? 1.0 : 0.0), fl.y);
}

float norm(float h) {
	return clamp((h - height_range.x) / max(height_range.y - height_range.x, 0.001), 0.0, 1.0);
}

void fragment() {
	vec2 at = UV * tile_cm;
	vec2 b = bark(at, seed);
	float h = norm(b.x);
	// how far the point sits below its surroundings (4 neighbours 2 cm away)
	float around = 0.25 * (norm(bark(at + vec2(2.0, 0.0), seed).x) + norm(bark(at - vec2(2.0, 0.0), seed).x)
			+ norm(bark(at + vec2(0.0, 2.0), seed).x) + norm(bark(at - vec2(0.0, 2.0), seed).x));
	float cavity = h - around;
	float mottle = vnoise(at, 14.0, 28.0, seed + 61.0) - 0.5;
	float tone = (b.y - 0.5) * 2.0;
	float light = (1.0 + shading.x * cavity * 6.0) * (1.0 + shading.y * mottle * 6.0) * (1.0 + shading.z * tone);
	light *= mix(0.3, 1.0, smoothstep(0.0, 0.5, h)); // the gaps and low parts between the flakes are dark
	float t = h * 7.0;
	int i0 = int(floor(t));
	int i1 = min(i0 + 1, 7);
	vec3 ramp_colour = mix(ramp[i0], ramp[i1], t - float(i0));
	COLOR = vec4(clamp(ramp_colour * light, 0.0, 1.0), clamp(alpha_map.z + (h - alpha_map.y) * alpha_map.x, 0.0, 1.0));
}
