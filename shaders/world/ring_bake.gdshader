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
	return hash2(mod(ix, per.x), mod(iy, per.y), s);
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
	float fine = vnoise(at, p[12], p[12], s + 8.0) - 0.5;
	return 0.5 + p[3] * band + p[8] * fib + p[11] * blotch + p[13] * fine;
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
	COLOR = vec4(clamp(colour, 0.0, 1.0), h);
}
