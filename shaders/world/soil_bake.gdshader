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
	return hash2(ix - per * floor(ix / per + 0.001), iy - per * floor(iy / per + 0.001), s); // (not mod(): the GPU divides as x * (1 / y) and mod(75.0, 75.0) can come out 75)
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
	// red lumps: a coarse noise made ragged by finer octaves, so the lump edges are broken like crumbled brick
	float ragged = vnoise(at, 1.8, seed + 61.0) * 0.55 + vnoise(at, 0.9, seed + 63.0) * 0.35 + vnoise(at, 0.5, seed + 65.0) * 0.1;
	float lump = vnoise(at, 6.0, seed + 31.0) * 0.55 + vnoise(at, 2.5, seed + 33.0) * 0.25 + (ragged - 0.5) * 0.35 + 0.1;
	float edge = 0.6 - 0.9 * (red_share - 0.19);
	float red = smoothstep(edge - 0.015, edge + 0.015, lump);
	vec3 colour = mix(sand_colour * 0.94, red_colour * 0.92, red);
	// fine detail at every size: sand grains, dark and pale specks, pebbles' own tones
	float g1 = vnoise(at, 0.55, seed + 67.0) - 0.5;
	float g2 = vnoise(at, 1.1, seed + 69.0) - 0.5;
	float g3 = vnoise(at, 1.5, seed + 71.0) - 0.5;
	float g4 = vnoise(at, 4.0, seed + 35.0) - 0.5;
	float dark_speck = smoothstep(0.7, 0.95, vnoise(at, 2.2, seed + 73.0)) * smoothstep(0.55, 0.8, vnoise(at, 1.0, seed + 74.0));
	float pale_speck = smoothstep(0.78, 0.95, vnoise(at, 1.6, seed + 75.0)) * smoothstep(0.55, 0.8, vnoise(at, 0.8, seed + 76.0));
	colour *= mix(vec3(1.04, 0.94, 0.82), vec3(0.98, 0.84, 0.78), red) * (1.3 + 0.28 * g1 + 0.3 * g2 + 0.3 * g3 + 0.4 * g4);
	colour = mix(colour, colour * 0.5, 0.45 * dark_speck);
	colour = mix(colour, vec3(0.8, 0.76, 0.68), 0.6 * pale_speck);
	// crisp small detail that survives zoom (flecks from a warped noise, so they are not grid-aligned) and a per-pixel grain:
	// dark grit, pale quartz, and many small red crumbs
	vec2 warped = at + 0.5 * vec2(vnoise(at, 1.6, seed + 151.0) - 0.5, vnoise(at, 1.8, seed + 153.0) - 0.5) * 2.0;
	float grit = smoothstep(0.8, 0.85, vnoise(warped, 0.45, seed + 155.0));
	float quartz = smoothstep(0.74, 0.8, vnoise(warped, 0.42, seed + 157.0));
	float crumb = smoothstep(0.76, 0.82, vnoise(warped, 0.8, seed + 159.0)) * smoothstep(0.35, 0.65, vnoise(at, 9.0, seed + 161.0));
	float pixel_grain = fract(sin(dot(floor(UV * 1024.0), vec2(12.9898, 78.233))) * 43758.5453) - 0.5;
	colour = mix(colour, colour * 0.45, 0.55 * grit);
	colour = mix(colour, vec3(0.85, 0.82, 0.74), 0.3 * quartz);
	colour = mix(colour, red_colour * 0.88, 0.85 * crumb);
	colour *= 1.0 + 0.24 * pixel_grain;
	colour *= 0.85 + 0.3 * smoothstep(0.2, 0.9, h);
	// the photograph's relief is coarse and rough: broad lumps 4-9 cm with a crumbly rough surface (warped noise, so no contours)
	vec2 warp = at + 1.4 * vec2(vnoise(at, 3.0, seed + 181.0) - 0.5, vnoise(at, 3.4, seed + 183.0) - 0.5);
	float lumpy = vnoise(warp, 6.0, seed + 185.0) * 0.5 + vnoise(warp, 2.6, seed + 187.0) * 0.3 + vnoise(warp, 1.2, seed + 189.0) * 0.2;
	float rough = vnoise(warp, 0.8, seed + 191.0) - 0.5;
	float relief = 0.5 + 0.42 * (lumpy - 0.5) + 0.1 * rough + 0.1 * (h - 0.5);
	COLOR = vec4(clamp(colour, 0.0, 1.0), clamp(relief, 0.0, 1.0));
}
