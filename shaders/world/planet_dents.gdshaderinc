// Prints that dent the sand (task 078, step 2 and 4). Whatever touches the sand leaves a PROFILE: a small picture (PlanetImprinter takes
// it from the touching mesh itself, PlanetDents keeps it) of how deep each spot is pressed. PlanetDents puts the 32 nearest into one
// atlas (8 x 4 pictures) and into a small float texture of poses; the ground shader works the dent out where it shades the ground: a
// depression with a rim of pushed-up sand that softens and fills as it ages. The ground itself does not change (no collision): this is the
// height the light and the eye see.

uniform sampler2D dent_stamps : filter_nearest; // texel 0: position (planet axes, wrapped to 1024 m) and the clock it was made at;
		// texel 1: the way the toe points; texel 2: the way up
uniform sampler2D dent_atlas : filter_linear_mipmap; // 8 x 4 profiles, 0.8 m square each, 255 the deepest
uniform int dent_count = 0;
uniform float dent_now = 0.0; // s, the clock the ages are read against
uniform float dent_life = 240.0; // s, when a print has gone (its depth is down to a tenth after 0.9 of it)
uniform float dent_depth = 0.05; // m under the deepest spot of a new print

const float DENT_SPAN = 0.8; // m across a profile
const vec2 DENT_GRID = vec2(8.0, 4.0);

// The profile `slot` at q = (across, along) metres from the print's middle, `lod` blurring it (an old print is a soft one).
float dent_profile(int slot, vec2 q, float lod) {
	vec2 inside = clamp(vec2(q.x, -q.y) / DENT_SPAN + 0.5, 0.004, 0.996);
	return textureLod(dent_atlas, (vec2(float(slot % 8), float(slot / 8)) + inside) / DENT_GRID, lod).r;
}

// The height change at planet position `p` from every print near it (negative: down); `pressed` is the most pressed (0..1: darker,
// damper, smoother sand).
float dent_height(vec3 p, out float pressed) {
	float h = 0.0;
	pressed = 0.0;
	for (int i = 0; i < 32; i++) {
		if (i >= dent_count) {
			break;
		}
		vec4 where = texelFetch(dent_stamps, ivec2(i, 0), 0);
		vec3 d = p - where.xyz;
		d -= 1024.0 * round(d / 1024.0); // (the planet's coordinates wrap every 1024 m)
		if (dot(d, d) > 0.35) {
			continue;
		}
		float age = dent_now - where.w;
		if (age < 0.0 || age > dent_life * 1.4) {
			continue;
		}
		vec3 toward = texelFetch(dent_stamps, ivec2(i, 1), 0).xyz;
		vec3 up = texelFetch(dent_stamps, ivec2(i, 2), 0).xyz;
		vec2 q = vec2(dot(d, cross(up, toward)), dot(d, toward));
		if (abs(q.x) > 0.39 || abs(q.y) > 0.39) {
			continue;
		}
		float life_share = clamp(age / dent_life, 0.0, 1.0);
		float lod = 1.0 + life_share * 3.0; // the edges slump: a new print is crisp, an old one is a soft hollow
		float fade = exp(-age / (dent_life * 0.4)); // the depth: the wind fills it
		float here = dent_profile(i, q, lod);
		float ring = 0.25 * (dent_profile(i, q + vec2(0.02, 0.0), lod) + dent_profile(i, q - vec2(0.02, 0.0), lod)
				+ dent_profile(i, q + vec2(0.0, 0.02), lod) + dent_profile(i, q - vec2(0.0, 0.02), lod));
		float rim = max(ring - here, 0.0) * (1.0 - smoothstep(0.0, 0.5, here)); // the sand pushed out stands up beside the print
		float change = (-here + 0.45 * rim) * dent_depth * fade;
		h = abs(change) > abs(h) ? change : h;
		pressed = max(pressed, here * (1.0 - life_share));
	}
	return h;
}
