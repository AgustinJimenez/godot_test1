// The noise and the field of loose stones the ground shader and its shell layers share (planet_ground, planet_shells).

float hash3(vec3 p) {
	p = fract(p * 0.3183099 + vec3(0.1, 0.2, 0.3));
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

// Value noise that repeats every `period` cells (so the position can be wrapped to a small number).
float noise3(vec3 p, float period) {
	vec3 i = floor(p);
	vec3 f = smoothstep(0.0, 1.0, fract(p));
	vec3 a = mod(i, period);
	vec3 b = mod(i + 1.0, period);
	return mix(mix(mix(hash3(a), hash3(vec3(b.x, a.y, a.z)), f.x),
			mix(hash3(vec3(a.x, b.y, a.z)), hash3(vec3(b.x, b.y, a.z)), f.x), f.y),
			mix(mix(hash3(vec3(a.x, a.y, b.z)), hash3(vec3(b.x, a.y, b.z)), f.x),
			mix(hash3(vec3(a.x, b.y, b.z)), hash3(b), f.x), f.y), f.z);
}

float fbm3(vec3 p, float period) {
	float sum = 0.0;
	float amp = 0.5;
	for (int i = 0; i < 3; i++) {
		sum += noise3(p, period) * amp;
		p = p * 2.0 + vec3(17.3, 9.1, 5.7);
		period *= 2.0;
		amp *= 0.5;
	}
	return sum;
}

// A field of loose stones in the planet's own coordinates: one stone to every cell of 1/`scale` metres, each at its own
// place, size, height and shade. Only the 2 x 2 x 2 cells nearest to the point are looked at (a stone's dome is smaller than
// half a cell and its centre is kept near the middle of its cell, so no other cell can cover the point). Out: `h` the
// height of the stone under the point (0 between stones, 1 at the top of the tallest), `lean` the way the surface
// tilts there (planet axes, a slope: the normal leans by it), `shade` that stone's own tone (0..1), `crevice` how
// much the point lies in the dark gap hugging a stone (0 far from any, 1 touching one). `period` makes the field repeat
// over the noise's wrapped distance (1024 m) so the planet's position can stay small.
void stones(vec3 p, float scale, float period, float size, float angular, float flaky, out float h, out vec3 lean,
		out float shade, out float crevice) {
	vec3 q = p * scale;
	vec3 base = floor(q);
	vec3 toward = vec3(fract(q.x) < 0.5 ? -1.0 : 1.0, fract(q.y) < 0.5 ? -1.0 : 1.0, fract(q.z) < 0.5 ? -1.0 : 1.0);
	h = 0.0;
	lean = vec3(0.0);
	shade = 0.5;
	float nearest = 4.0;
	for (int i = 0; i < 2; i++) {
		for (int j = 0; j < 2; j++) {
			for (int k = 0; k < 2; k++) {
				vec3 c = base + vec3(float(i), float(j), float(k)) * toward;
				vec3 w = mod(c, period);
				vec3 centre = c + 0.3 + 0.4 * vec3(hash3(w + 1.7), hash3(w + 4.1), hash3(w + 8.3));
				float radius = size * (0.4 + 0.6 * hash3(w + 11.9)) * step(0.15, hash3(w + 3.3)); // some cells hold no stone
				vec3 d = q - centre;
				d.y *= 1.0 + 2.2 * flaky; // flaky rock breaks into plates: flat stones
				float metric = mix(length(d), (abs(d.x) + abs(d.y) + abs(d.z)) * 0.62, angular); // round, or edged like a crystal
				float d2 = metric * metric / max(radius * radius, 0.0001);
				nearest = min(nearest, d2);
				float tall = 0.5 + 0.5 * hash3(w + 2.9);
				float height = max(1.0 - d2, 0.0) * tall;
				if (height > h) {
					h = height;
					lean = mix(d / radius, sign(d) * 0.62 * metric / max(radius, 0.0001) * 1.5, angular) * 1.6 * tall;
					shade = hash3(w + 5.5);
				}
			}
		}
	}
	crevice = smoothstep(1.6, 1.0, nearest) * (1.0 - smoothstep(0.0, 0.15, h));
}

// The height (metres) of the crumbly ground at `p` for the parallax march: only the two coarser sizes of fragments (the finest are
// under a centimetre and would not show in the parallax), each from where it stands out of the soil.
float crumb_height(vec3 p, float size_mid, float size_big, float cover_mid, float cover_big) {
	float h_mid;
	float h_big;
	vec3 lean;
	float tone;
	float gap;
	stones(p + 53.0, 11.0, 1024.0 * 11.0, size_mid, 0.5, 0.4, h_mid, lean, tone, gap);
	stones(p + 66.0, 4.2, 1024.0 * 4.2, size_big, 0.5, 0.4, h_big, lean, tone, gap);
	return max(smoothstep(0.0, 0.1, h_mid) * h_mid * cover_mid * 0.012, smoothstep(0.0, 0.1, h_big) * h_big * cover_big * 0.03);
}

