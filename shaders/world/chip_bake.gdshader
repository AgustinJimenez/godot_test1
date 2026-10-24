shader_type canvas_item;
render_mode blend_disabled; // the height is written in alpha: no blending
// Procedural gravel (angular chips of three sizes on grit), drawn once into a tile (ChipBaker): colour in rgb, height in
// alpha. The same model as tools/bark/chip_gen.py (the reference the 14 numbers were fitted with, ChipFits.KEYS), made to
// tile: every cell grid is a whole number per tile and the hashes wrap.

uniform float p[14];
uniform float tile_cm = 100.0;
uniform vec3 ramp[8];
uniform vec2 height_range = vec2(0.0, 1.0);
uniform float seed = 1.0;

float fract1(float x) {
	return x - floor(x);
}

float hash2(float ix, float iy, float s) {
	return fract1(sin(ix * 127.1 + iy * 311.7 + s * 74.7) * 43758.5453);
}

float hashw(float ix, float iy, float s, float per) {
	return hash2(ix - per * floor(ix / per + 0.001), iy - per * floor(iy / per + 0.001), s); // (not mod(): the GPU divides as x * (1 / y) and mod(75.0, 75.0) can come out 75)
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

// the chip under `at` in one size class: x its height (-1: none), y a tone for its colour
vec2 chips(vec2 at, float cell_cm, float cover, float s) {
	float n = max(floor(tile_cm / cell_cm + 0.5), 1.0);
	vec2 uv = at / tile_cm * n;
	vec2 base = floor(uv);
	float d1 = 1e9;
	float d2 = 1e9;
	vec2 cell = vec2(0.0);
	vec2 dd = vec2(0.0);
	for (int oy = -1; oy <= 1; oy++) {
		for (int ox = -1; ox <= 1; ox++) {
			float cx = base.x + float(ox);
			float cy = base.y + float(oy);
			vec2 f = vec2(cx + 0.5 + (hashw(cx, cy, s + 1.0, n) - 0.5) * p[7],
					cy + 0.5 + (hashw(cx, cy, s + 2.0, n) - 0.5) * p[7]);
			vec2 d = uv - f;
			float dist = length(d);
			if (dist < d1) {
				d2 = d1;
				d1 = dist;
				cell = vec2(cx, cy);
				dd = d;
			} else if (dist < d2) {
				d2 = dist;
			}
		}
	}
	if (hashw(cell.x, cell.y, s + 3.0, n) > cover || smoothstep(0.0, p[6], d2 - d1) < 0.5) {
		return vec2(-1.0, 0.0);
	}
	float z = 0.6 + p[9] * (hashw(cell.x, cell.y, s + 4.0, n) - 0.5);
	z += p[8] * (dd.x * (hashw(cell.x, cell.y, s + 5.0, n) - 0.5) + dd.y * (hashw(cell.x, cell.y, s + 6.0, n) - 0.5));
	return vec2(z, hashw(cell.x, cell.y, s + 7.0, n));
}

float gravel(vec2 at, float s, out float tone) {
	float h = 0.25 + p[10] * (vnoise(at, p[11], s + 1.0) - 0.5) + p[13] * (vnoise(at, max(p[12], 1.6), s + 2.0) - 0.5);
	tone = 0.5;
	vec2 c = chips(at, max(p[4], 2.0), p[5], s + 10.0);
	if (c.x > 0.0) {
		h = max(h, 0.3 + 0.3 * c.x);
		tone = c.y;
	}
	c = chips(at, p[2], p[3], s + 20.0);
	if (c.x > 0.0) {
		h = max(h, 0.45 + 0.3 * c.x);
		tone = c.y;
	}
	c = chips(at, p[0], p[1], s + 30.0);
	if (c.x > 0.0) {
		h = max(h, 0.6 + 0.3 * c.x);
		tone = c.y;
	}
	return h;
}

float norm(float h) {
	return clamp((h - height_range.x) / max(height_range.y - height_range.x, 0.001), 0.0, 1.0);
}

void fragment() {
	vec2 at = UV * tile_cm;
	float tone;
	float h = norm(gravel(at, seed, tone));
	float t = h * 7.0;
	int i0 = int(floor(t));
	int i1 = min(i0 + 1, 7);
	vec3 colour = mix(ramp[i0], ramp[i1], t - float(i0));
	// the ramp by height is nearly flat for gravel: the grit takes the dark end, each chip its own tone from the light end
	float chip = tone == 0.5 ? 0.0 : 1.0;
	vec3 grit = ramp[1] * (0.9 + 0.3 * h);
	vec3 stone = mix(ramp[3], ramp[7], tone) * (0.8 + 0.4 * h);
	// the ground between the chips is sandy earth with grains, darker debris and a few pale specks; the chips grey-brown with grain
	float sand = vnoise(at, 0.7, seed + 51.0) - 0.5;
	float sand2 = vnoise(at, 1.6, seed + 53.0) - 0.5;
	float sand3 = vnoise(at, 0.35, seed + 59.0) - 0.5;
	float patch = vnoise(at, 24.0, seed + 55.0) - 0.5;
	float debris = smoothstep(0.62, 0.8, vnoise(at, 5.0, seed + 57.0));
	vec3 earth = ramp[5] * (0.95 + 0.5 * patch + 0.3 * sand2 + 0.22 * sand + 0.18 * sand3);
	earth = mix(earth, ramp[0] * 0.6, 0.55 * debris);
	// the stones are cool grey, purple-grey and dark, each its own tone, with a shaded edge where it meets the earth
	vec3 stone_cool = mix(vec3(0.17, 0.17, 0.2), vec3(0.5, 0.48, 0.5), tone);
	float t1;
	float t2;
	float around = 0.25 * (norm(gravel(at + vec2(0.5, 0.0), seed, t1)) + norm(gravel(at - vec2(0.5, 0.0), seed, t2))
			+ norm(gravel(at + vec2(0.0, 0.5), seed, t1)) + norm(gravel(at - vec2(0.0, 0.5), seed, t2)));
	float edge_shade = clamp(1.0 + 1.5 * (h - around), 0.6, 1.08);
	vec3 stone_final = stone_cool * edge_shade * (0.9 + 0.25 * sand + 0.2 * sand2 + 0.2 * sand3);
	// crisp grit in the earth: dark grains, pale specks and a per-pixel grain (warped noise: not grid-aligned)
	vec2 warped = at + 0.5 * vec2(vnoise(at, 1.6, seed + 151.0) - 0.5, vnoise(at, 1.8, seed + 153.0) - 0.5) * 2.0;
	float earth_grit = smoothstep(0.8, 0.85, vnoise(warped, 0.5, seed + 155.0));
	float speck = smoothstep(0.82, 0.87, vnoise(warped, 0.42, seed + 157.0));
	float pixel_grain = fract(sin(dot(floor(UV * 1024.0), vec2(12.9898, 78.233))) * 43758.5453) - 0.5;
	earth = mix(earth, earth * 0.38, 0.7 * earth_grit);
	earth = mix(earth, vec3(0.8, 0.76, 0.68), 0.22 * speck);
	earth *= (1.0 + 0.22 * pixel_grain) * 1.35;
	stone_final *= 1.0 + 0.14 * pixel_grain;
	colour = mix(earth, stone_final, chip);
	// crumbly relief in the earth between the stones (warped noise from 1 cm up: no grid, no mosaic in the parallax march)
	float crumbs = (vnoise(warped, 1.0, seed + 171.0) - 0.5) * 0.6 + (vnoise(warped, 2.2, seed + 173.0) - 0.5) * 0.4;
	h = clamp(h + 0.07 * crumbs * (1.0 - chip), 0.0, 1.0);
	COLOR = vec4(clamp(colour, 0.0, 1.0), h);
}
