// Packed fragments: the look of a red laterite crust seen from above, a mosaic of angular plates of every size from crumbs to hand-sized slabs,
// nearly one colour but each its own tone and its own tilt to the light, thin dark gaps, a few grey and pale pebbles. Three scales are laid
// one over the other (the small ones fill the ground, the larger ones cover only part of it). Every number is a uniform (the ground lab
// has a slider for each). Needs hash3 (planet_stones.gdshaderinc) before it.

uniform bool mosaic_on = true;
uniform float mosaic_strength : hint_range(0.0, 1.0) = 0.9;
uniform float mosaic_big_per_m = 15.0; // plates of the large kind to a metre
uniform float mosaic_mid_per_m = 42.0;
uniform float mosaic_small_per_m = 150.0;
uniform float mosaic_big_cover : hint_range(0.0, 1.0) = 0.13; // how much of the ground the large plates hold
uniform float mosaic_mid_cover : hint_range(0.0, 1.0) = 0.42;
uniform float mosaic_angular : hint_range(0.0, 1.0) = 0.8; // round crumbs .. sharp plates
uniform float mosaic_gap : hint_range(0.0, 1.0) = 0.75; // how dark the gaps between fragments
uniform float mosaic_tilt : hint_range(0.0, 2.0) = 1.4; // how far each plate leans (how much light and shade it takes)
uniform float mosaic_tone : hint_range(0.0, 1.0) = 0.7; // how different the fragments are from each other
uniform float mosaic_pebbles : hint_range(0.0, 0.5) = 0.11; // the share that are grey or pale pebbles
uniform float mosaic_size_var : hint_range(0.0, 1.0) = 0.7; // how different the fragments of one scale are in size (and how the sizes shift from patch to patch)
uniform float mosaic_shape_var : hint_range(0.0, 1.0) = 0.7; // how different their shapes are: round, diamond, square; stubby or long
uniform float mosaic_desat : hint_range(0.0, 1.0) = 0.6; // the fragments are less saturated than the soil painted over them
uniform float mosaic_grain : hint_range(0.0, 1.0) = 0.85; // the fine crumbly grain between and on the fragments
uniform float mosaic_height = 0.03; // m: how far the tallest plates stand out of the soil (the parallax depth)
uniform float mosaic_shadow : hint_range(0.0, 1.0) = 0.6; // how dark a plate shadow on its neighbours (soft self-shadowing)
uniform float mosaic_side_dark : hint_range(0.0, 1.0) = 0.35; // stylized depth shade; high values make gaps look like bright speckle on a dark field
uniform int mosaic_pom_min_steps : hint_range(2, 12) = 3; // parallax samples looking straight down (Tatarchuk: n = min + (max - min)(1 - V.N))
uniform int mosaic_pom_max_steps : hint_range(3, 32) = 20; // and at a grazing angle
uniform float mosaic_seed = 1.0;

struct Mosaic {
	float cover; // 1 inside a fragment of this scale (0: the ground under shows)
	float border; // distance to the next fragment (cell units, 0 on the gap)
	vec2 lean; // the way its surface tilts the light (2D, along the ground's own axes)
	float tone; // 0..1 its own tone
	float pebble; // 0 soil fragment .. 1 a grey or pale pebble
	float kind;
	vec2 dir; // from the fragment's centre to the point (its rim leans outward)
};

// A random convex polygon round the origin as a "metric": 1 on its outline. `seed` makes its corner count (3 to 8, `sides_var` how much
// the count varies from the usual 5) and the length of every side (each side is a line at its own turn and its own distance).
float mosaic_polygon(vec2 r, float seed, float sides_var) {
	int corners = 5 + int(floor((fract(seed * 91.7) - 0.5) * 6.99 * sides_var + 0.5));
	corners = clamp(corners, 3, 8);
	float turn0 = fract(seed * 17.3) * 6.2831853;
	float worst = 0.0;
	for (int k = 0; k < 8; k++) {
		if (k >= corners) {
			break;
		}
		float jitter = fract(sin(seed * 91.7 + float(k) * 13.3) * 4375.5);
		float angle = turn0 + (float(k) + (jitter - 0.5) * 0.9 * sides_var) * 6.2831853 / float(corners);
		float reach = 0.55 + 0.9 * mix(0.5, fract(sin(seed * 47.3 + float(k) * 7.7) * 1234.5), sides_var); // the side's distance: long or short
		worst = max(worst, dot(r, vec2(cos(angle), sin(angle))) / reach);
	}
	return worst;
}

float mosaic_hash(vec2 id, float k) {
	return hash3(vec3(mod(id, 4096.0), k + mosaic_seed * 3.7));
}

// One scale: `per_m` fragments to a metre, `present` the share of the cells that hold a fragment. The search for the nearest fragment
// reads only what the distance needs (five numbers a cell); the rest is read once for the one that won.
Mosaic mosaic_layer(vec2 p, float per_m, float present, float k) {
	vec2 q = p * per_m;
	vec2 base = floor(q);
	float best = 1.0e9;
	float second = 1.0e9;
	vec2 best_cell = base;
	vec2 best_d = vec2(0.0);
	// patch to patch the sizes drift: where this noise is high the fragments of the scale are larger (the cells keep their place, they only
	// count for more or less of the distance)
	float patch_noise = noise3(vec3(p * 0.9, k * 0.31 + mosaic_seed), 4096.0);
	float zone = exp((patch_noise - 0.5) * 0.9 * mosaic_size_var);
	for (int j = -1; j <= 1; j++) {
		for (int i = -1; i <= 1; i++) {
			vec2 cell = base + vec2(float(i), float(j));
			vec3 a = vec3(mosaic_hash(cell, k + 1.0), mosaic_hash(cell, k + 2.0), mosaic_hash(cell, k + 3.0));
			vec2 centre = cell + 0.5 + (a.xy - 0.5) * 0.8;
			float turn = a.z * 6.2831853;
			vec2 d = q - centre;
			vec2 r = vec2(cos(turn) * d.x - sin(turn) * d.y, sin(turn) * d.x + cos(turn) * d.y);
			vec3 b = vec3(mosaic_hash(cell, k + 4.0), mosaic_hash(cell, k + 5.0), mosaic_hash(cell, k + 13.0));
			r.x *= mix(0.8, 0.35 + 1.25 * b.x, mosaic_shape_var); // stubby or long, each its own
			float angular = clamp(mosaic_angular + (b.y - 0.5) * 1.6 * mosaic_shape_var, 0.0, 1.0); // some round, some sharp
			float polygon = max(mosaic_polygon(r, b.z * 0.9 + 0.05 * b.y, mosaic_shape_var) * 0.85, length(r) * 0.8); // its own corners and sides, never reaching past a circle (a fragment cut off by a missing neighbour showed as a straight edge)
			float metric = mix(length(r), polygon, angular);
			metric *= exp((fract(b.x * 7.31 + b.y * 3.7) - 0.5) * 1.5 * mosaic_size_var) * zone; // (kept in range: a fragment larger than the 3 x 3 cells searched would be cut off straight) // sizes spread over a wide range
			if (metric < best) {
				second = best;
				best = metric;
				best_cell = cell;
				best_d = d;
			} else if (metric < second) {
				second = metric;
			}
		}
	}
	Mosaic m;
	float present_here = clamp(present * mix(1.0, 0.4 + 1.2 * patch_noise, mosaic_size_var), 0.0, 1.0);
	m.cover = mosaic_hash(best_cell, k + 6.0) < present_here ? 1.0 : 0.0;
	float tilt_turn = mosaic_hash(best_cell, k + 7.0) * 6.2831853;
	m.lean = vec2(cos(tilt_turn), sin(tilt_turn)) * (0.2 + 0.8 * mosaic_hash(best_cell, k + 8.0)) * mosaic_tilt;
	m.tone = mosaic_hash(best_cell, k + 9.0);
	m.pebble = mosaic_hash(best_cell, k + 10.0) < mosaic_pebbles ? 1.0 : 0.0;
	m.kind = fract(m.tone * 13.7 + 0.3);
	m.dir = normalize(best_d + vec2(0.0001));
	m.border = second - best;
	return m;
}

// The colour (a multiplier on the soil's own), the occlusion and the normal lean (along the ground's axes) of the three scales laid over
// each other, and out `pebble_colour`/`pebble_weight` for the grey and pale pebbles. `fade` 0..1 the share of the finer scales kept
// (they are under a pixel far away).
void mosaic_surface(vec2 p, vec3 soil, vec3 fade, out vec3 colour, out float ao, out vec2 lean) {
	colour = vec3(1.0);
	ao = 1.0;
	lean = vec2(0.0);
	float scale_k[3] = float[3](0.0, 20.0, 40.0);
	float per_m[3] = float[3](mosaic_small_per_m, mosaic_mid_per_m, mosaic_big_per_m);
	float cover_of[3] = float[3](1.0, mosaic_mid_cover, mosaic_big_cover);
	float fade_of[3] = float[3](fade.x, fade.y, fade.z);
	colour = vec3(1.0);
	for (int s = 0; s < 3; s++) {
		if (fade_of[s] < 0.02) {
			continue;
		}
		Mosaic m = mosaic_layer(p, per_m[s], cover_of[s], scale_k[s]);
		float inside = m.cover * fade_of[s];
		float rim = smoothstep(0.0, 0.14, m.border);
		// the gap between fragments is dark, narrower on the large plates
		float dark = 1.0 - mosaic_gap * (1.0 - rim) * (s == 0 ? 0.75 : 1.0);
		float toned = mix(1.0, 0.55 + 0.9 * m.tone, mosaic_tone);
		vec3 fragment = vec3(toned) * dark;
		fragment = mix(fragment, vec3(dot(fragment, vec3(0.33))), 0.0);
		if (m.pebble > 0.5 && s < 2) {
			// a pebble: grey, pale or a dark crystal, not the soil's red
			vec3 pebble_grey = m.kind < 0.55 ? vec3(0.09, 0.085, 0.08) : (m.kind < 0.85 ? vec3(0.17, 0.16, 0.14) : vec3(0.36, 0.33, 0.27));
			fragment = pebble_grey / max(soil, vec3(0.05)) * dark * (0.7 + 0.6 * m.tone);
		}
		colour = mix(colour, fragment, inside);
		// the soil itself between: a fine grain (small bright and dark crumbs) over everything at this scale
		colour *= 1.0 + mosaic_grain * (mosaic_hash(floor(p * per_m[s] * 4.0), scale_k[s] + 12.0) - 0.5) * 0.7 * fade_of[s];
		ao = mix(ao, mix(1.0 - mosaic_gap * 0.5, 1.0, rim), inside);
		float edge_lean = (1.0 - smoothstep(0.0, 0.4, m.border)) * 0.9;
		lean = mix(lean, m.lean * 0.55 + m.dir * edge_lean, inside);
	}
	float tone_now = dot(colour, vec3(0.33));
	colour = mix(colour, vec3(tone_now), 0.0);
}

// How high the fragments stand at `p` (0 the soil .. 1 the tallest large plate), for the parallax march: the large and the medium plates (the
// crumbs are too low to matter), each its own height, rolled off at the rim.
float mosaic_height_at(vec2 p, float fade_mid) {
	Mosaic big = mosaic_layer(p, mosaic_big_per_m, mosaic_big_cover, 40.0);
	float h = big.cover * smoothstep(0.0, 0.3, big.border) * (0.45 + 0.55 * big.tone);
	if (fade_mid > 0.001) {
		Mosaic mid = mosaic_layer(p, mosaic_mid_per_m, mosaic_mid_cover, 20.0);
		h = max(h, mid.cover * smoothstep(0.0, 0.3, mid.border) * (0.15 + 0.3 * mid.tone) * fade_mid); // (fading smoothly: a plate dropping out at once drew a ring)
	}
	return h;
}
