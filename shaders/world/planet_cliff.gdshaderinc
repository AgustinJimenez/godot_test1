// A procedural cliff: stacked sandstone slabs with terraced lips, cracks, level beds, sandy shelves and painted tone patches, computed in the
// shader from a position on the face (metres along it, metres up), the same recipe as scripts/make_cliff_textures.py but with no image, so
// it never repeats, can change from place to place and every number of it can be moved live (the ground lab has a slider for each).
// Needs hash3 and noise3 (planet_stones.gdshaderinc) before it.

uniform bool cliff_procedural = true; // false: the baked slab pictures (cliff_c, cliff_n)
uniform float cliff_row_height = 0.45; // m: the thickness of a bed of slabs
uniform float cliff_col_width = 1.1; // m: the width of a slab
uniform float cliff_warp = 0.4; // m: how far the edges wander (no border is a ruler line)
uniform float cliff_lip = 0.09; // m: the steep rim of a slab
uniform float cliff_terraces : hint_range(0.0, 1.0) = 0.5; // how much the tops step to whole levels
uniform float cliff_cracks : hint_range(0.0, 1.0) = 0.55; // the share of slabs with a vertical crack
uniform float cliff_sand : hint_range(0.0, 1.0) = 0.5; // sand on the low shelves
uniform float cliff_tone : hint_range(0.0, 1.0) = 0.6; // painted patches of light and dark
uniform float cliff_relief = 1.0; // how strongly the slabs catch the light
uniform float cliff_seed = 3.0; // another layout
uniform float cliff_hue : hint_range(0.0, 1.0) = 0.5; // 0 the rock's own colour .. 1 sandstone orange

float cliff_hash(vec2 id, float k) {
	return hash3(vec3(mod(id, 1024.0), k + cliff_seed * 7.13));
}

// The cells (slabs) round `p`: the distance to the border between the two nearest (0 on it), the nearest one's height, tilt, centre and id.
void cliff_cells(vec2 p, out float border, out float top, out float tilt, out vec2 centre, out vec2 id) {
	float row = cliff_row_height;
	float width = cliff_col_width;
	float row0 = floor(p.y / row);
	float nearest = 1.0e9;
	float second = 1.0e9;
	top = 0.0;
	tilt = 0.0;
	centre = vec2(0.0);
	id = vec2(0.0);
	for (int dy = -1; dy <= 1; dy++) {
		float iy = row0 + float(dy);
		float offset = cliff_hash(vec2(iy, 0.0), 1.0);
		float col0 = floor(p.x / width - offset);
		for (int dx = -1; dx <= 1; dx++) {
			float ix = col0 + float(dx);
			vec2 cell = vec2(ix, iy);
			vec2 c = vec2((ix + offset + 0.25 + 0.5 * cliff_hash(cell, 2.0)) * width, (iy + 0.3 + 0.4 * cliff_hash(cell, 3.0)) * row);
			float d = length(vec2(p.x - c.x, (p.y - c.y) * 3.4)); // the cells are wide and low
			if (d < nearest) {
				second = nearest;
				nearest = d;
				top = 0.3 + 0.7 * cliff_hash(cell, 4.0);
				tilt = (cliff_hash(cell, 5.0) - 0.5) * 0.32 * (p.x - c.x) / width + (cliff_hash(cell, 6.0) - 0.5) * 0.24 * (p.y - c.y) / row;
				centre = c;
				id = cell;
			} else if (d < second) {
				second = d;
			}
		}
	}
	border = second - nearest;
}

// The height (0..1) of the face at `uv`, and out: the gap between slabs, a crack in one, the sand lying there.
float cliff_height(vec2 uv, out float gap, out float crack, out float sand) {
	vec2 warped = uv + vec2(noise3(vec3(uv * 0.85, 1.0 + cliff_seed), 4096.0) - 0.5, (noise3(vec3(uv * 1.3 + 7.0, 2.0 + cliff_seed), 4096.0) - 0.5) * 0.3)
			* 2.0 * cliff_warp;
	float border;
	float top;
	float tilt;
	vec2 centre;
	vec2 id;
	cliff_cells(warped, border, top, tilt, centre, id);
	float lip = smoothstep(0.0, cliff_lip, border);
	float roll = smoothstep(0.0, cliff_lip * 4.5, border);
	float step_top = mix(top, floor(top * 6.0 + 0.5) / 6.0 * 0.5 + top * 0.5, cliff_terraces);
	float height = (0.1 + 0.9 * step_top) * (0.3 + 0.55 * lip + 0.15 * roll) + tilt * 1.2;
	gap = 1.0 - smoothstep(0.0, cliff_lip * 0.55, border);
	// a crack down some slabs: a wandering line at the slab's own place
	float crack_line = centre.x + (cliff_hash(id, 7.0) - 0.5) * 0.7 * cliff_col_width + (noise3(vec3(warped.y * 3.0, cliff_seed, 5.0), 4096.0) - 0.5) * 0.05;
	crack = (cliff_hash(id, 8.0) < cliff_cracks ? 1.0 : 0.0) * (1.0 - smoothstep(0.004, 0.012, abs(warped.x - crack_line)));
	// sand in the low places, patchy
	float low_place = smoothstep(0.6, 0.3, height) * smoothstep(0.25, 0.55, noise3(vec3(uv * 1.1, 11.0 + cliff_seed), 4096.0));
	sand = clamp(low_place * 1.6 * cliff_sand, 0.0, 1.0);
	height = mix(height, 0.22, sand * 0.55) - 0.2 * crack;
	return clamp(height, 0.0, 1.0);
}

// The face at `uv` (metres along, metres up): out `colour` (linear, an orange rock; the caller keeps what hue it wants), `ao`, and `tilt`
// the way the relief leans the normal (x along the face, y up).
void cliff_surface(vec2 uv, out vec3 colour, out float ao, out vec2 tilt) {
	float gap;
	float crack;
	float sand;
	float h = cliff_height(uv, gap, crack, sand);
	float e = 0.012;
	float dummy_a;
	float dummy_b;
	float dummy_c;
	float hx = cliff_height(uv + vec2(e, 0.0), dummy_a, dummy_b, dummy_c);
	float hy = cliff_height(uv + vec2(0.0, e), dummy_a, dummy_b, dummy_c);
	vec2 slope = vec2(hx - h, hy - h) / e;
	tilt = -slope * 0.08 * cliff_relief;
	// the light from above: tops and the lit lips bright, what faces down dark
	float sun = clamp(0.55 + 1.5 * (-slope.y * 0.9 - slope.x * 0.25) * 0.08 * cliff_relief / 4.0 * 6.0, 0.0, 1.4);
	float patches = noise3(vec3(uv * 0.5, 21.0 + cliff_seed), 4096.0);
	float stains = noise3(vec3(uv.x * 2.2, uv.y * 0.35, 31.0 + cliff_seed), 4096.0);
	float blotch = noise3(vec3(uv * 2.6, 41.0 + cliff_seed), 4096.0);
	float t = clamp(0.15 + 0.95 * h + 0.35 * (patches - 0.5) * cliff_tone * 1.7, 0.0, 1.0);
	vec3 low = pow(vec3(0.5, 0.2, 0.08), vec3(2.2));
	vec3 high = pow(vec3(0.98, 0.6, 0.28), vec3(2.2));
	colour = mix(low, high, t) * (0.62 + 0.55 * sun) * (1.0 - cliff_tone * (0.22 * stains + 0.12 * blotch) + 0.08);
	vec3 sand_colour = pow(vec3(0.95, 0.6, 0.3), vec3(2.2)) * (0.75 + 0.35 * sun);
	colour = mix(colour, sand_colour, sand);
	colour *= 1.0 - 0.55 * max(gap, crack * 0.8);
	ao = 1.0 - 0.6 * max(gap, crack) - 0.2 * (1.0 - clamp(h * 1.4, 0.0, 1.0));
}
