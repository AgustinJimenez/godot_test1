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
uniform float mosaic_desat : hint_range(0.0, 1.0) = 0.6; // the fragments are less saturated than the soil painted over them
uniform float mosaic_grain : hint_range(0.0, 1.0) = 0.85; // the fine crumbly grain between and on the fragments
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

float mosaic_hash(vec2 id, float k) {
	return hash3(vec3(mod(id, 4096.0), k + mosaic_seed * 3.7));
}

// One scale: `per_m` fragments to a metre, `present` the share of the cells that hold a fragment.
Mosaic mosaic_layer(vec2 p, float per_m, float present, float k) {
	vec2 q = p * per_m;
	vec2 base = floor(q);
	float best = 1.0e9;
	float second = 1.0e9;
	Mosaic m;
	m.cover = 0.0;
	m.lean = vec2(0.0);
	m.tone = 0.5;
	m.pebble = 0.0;
	m.kind = 0.0;
	m.dir = vec2(0.0);
	for (int j = -1; j <= 1; j++) {
		for (int i = -1; i <= 1; i++) {
			vec2 cell = base + vec2(float(i), float(j));
			vec2 centre = cell + 0.5 + (vec2(mosaic_hash(cell, k + 1.0), mosaic_hash(cell, k + 2.0)) - 0.5) * 0.8;
			float turn = mosaic_hash(cell, k + 3.0) * 6.2831853;
			vec2 d = q - centre;
			vec2 r = vec2(cos(turn) * d.x - sin(turn) * d.y, sin(turn) * d.x + cos(turn) * d.y);
			r.x *= 0.65 + 0.5 * mosaic_hash(cell, k + 4.0); // plates are longer one way
			float metric = mix(length(r), (abs(r.x) + abs(r.y)) * 0.74, mosaic_angular);
			metric *= 0.75 + 0.5 * mosaic_hash(cell, k + 5.0); // some are bigger than their neighbours
			if (metric < best) {
				second = best;
				best = metric;
				m.cover = mosaic_hash(cell, k + 6.0) < present ? 1.0 : 0.0;
				float tilt_turn = mosaic_hash(cell, k + 7.0) * 6.2831853;
				m.lean = vec2(cos(tilt_turn), sin(tilt_turn)) * (0.2 + 0.8 * mosaic_hash(cell, k + 8.0)) * mosaic_tilt
						;
				m.dir = normalize(d + vec2(0.0001));
				m.tone = mosaic_hash(cell, k + 9.0);
				m.pebble = mosaic_hash(cell, k + 10.0) < mosaic_pebbles ? 1.0 : 0.0;
				m.kind = mosaic_hash(cell, k + 11.0);
			} else if (metric < second) {
				second = metric;
			}
		}
	}
	m.border = second - best;
	// the rim of a plate rolls off: its normal leans outward there (the vector from the centre is not kept: the border's slope is enough)
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
