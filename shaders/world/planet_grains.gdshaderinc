// Grains (task 078): the loose mineral grains every ground is made of, as three sizes of round grains (2 mm, 4 mm, 1.6 cm) that
// each have their own tone and a little dome that catches the light, with a dark gap round them. Their tones come from the
// ground's own materials (its base colour, how pale the rock is, how much iron): pale quartz, the ground's own tone, dark mineral,
// red iron grains. Needs hash3 (planet_stones.gdshaderinc) before it. The sizes divide 1024 m (the planet's coordinates wrap).
// Only where the grain is bigger than about a pixel (by distance, not by angle: an angle-dependent fade crawls as the eye moves);
// beyond that the ground's colour stands for them.

uniform float sand_grain : hint_range(0.0, 1.0) = 0.8; // how strongly the grains show (0: none)

// `paint` with the grains worked in at planet position `p`; `tilt` is the tilt they give the light (planet axes, along the ground).
// `dist` the metres to the eye, `up` the way up, `pale` 0..1 how pale the rock, `iron` 0..1 how much iron, `amount` 0..1 how much.
vec3 grains(vec3 p, float dist, vec3 up, vec3 paint, float pale, float iron, float amount, out vec3 tilt) {
	tilt = vec3(0.0);
	float size[3] = float[3](1.0 / 512.0, 1.0 / 256.0, 1.0 / 64.0);
	float cover[3] = float[3](0.8, 0.6, 0.12); // how much of the ground each size takes
	vec3 quartz = vec3(0.72, 0.64, 0.5);
	vec3 mineral = vec3(0.2, 0.16, 0.13);
	vec3 rust = vec3(0.5, 0.17, 0.08);
	for (int g = 0; g < 3; g++) {
		float seen = smoothstep(0.4, 1.4, size[g] / (max(dist, 0.05) * 0.0015));
		if (seen < 0.01) {
			continue;
		}
		vec3 q = p / size[g];
		vec3 cell = floor(q);
		vec3 id = mod(cell, 1024.0 / size[g]) + float(g) * 31.0;
		vec3 jitter = (vec3(hash3(id + 1.7), hash3(id + 4.1), hash3(id + 8.3)) - 0.5) * 0.5;
		vec3 off = fract(q) - 0.5 - jitter;
		off -= up * dot(off, up); // (across the ground: the cell is cut by the surface)
		float radius = 0.2 + 0.18 * hash3(id + 2.9);
		float r = length(off);
		float on = smoothstep(radius, radius * 0.6, r) * step(hash3(id + 6.1), cover[g]);
		float pick = hash3(id);
		float dark_odds = 0.07 * (1.3 - pale);
		float rust_odds = 0.03 + 0.25 * iron;
		vec3 tone = paint * (0.8 + 0.4 * hash3(id + 3.3)); // the ground's own tone
		if (pick < 0.35) {
			tone = mix(paint, quartz, 0.3 + 0.3 * pale);
		} else if (pick > 1.0 - dark_odds) {
			tone = mix(paint * 0.6, mineral, 0.5);
		} else if (pick > 1.0 - dark_odds - rust_odds) {
			tone = mix(paint, rust, 0.5 + 0.4 * iron);
		}
		float k = amount * seen;
		paint = mix(paint, tone, on * k);
		float gap = smoothstep(radius * 1.6, radius, r) * (1.0 - on); // dark between the grains
		paint *= 1.0 - 0.12 * gap * k;
		tilt += -off / max(radius, 0.05) * 0.5 * on * k * (g == 2 ? 1.0 : 0.6);
	}
	return paint;
}
