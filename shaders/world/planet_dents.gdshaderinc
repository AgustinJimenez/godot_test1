// Footprints that dent the sand (task 078, step 2). The player's feet leave stamps (PlanetDents keeps them and puts the 32 nearest into a
// small float texture, three texels each); the ground shader works the dent out where it shades the ground: a depression with a
// rim of pushed-up sand, deeper under the heel and the ball of the foot, that softens and fills as it ages. The ground itself does not
// change (no collision): this is the height the light and the eye see.

uniform sampler2D dent_stamps : filter_nearest; // texel 0: position (planet axes, wrapped to 1024 m) and the clock it was made at;
		// texel 1: the way the foot points (toe) and which foot (+1 right, -1 left); texel 2: the way up
uniform int dent_count = 0;
uniform float dent_now = 0.0; // s, the clock the ages are read against
uniform float dent_life = 240.0; // s, when a print has gone (its depth is down to a tenth after 0.9 of it)
uniform float dent_depth = 0.05; // m under the heel of a new print

// One print in its own frame: q = (across, along) in metres, the toe at +along. Returns the height change (negative: down) and how pressed
// the sand is there (0..1, for darker, damper, smoother sand).
float dent_foot(vec2 q, float age, out float pressed) {
	float life_share = clamp(age / dent_life, 0.0, 1.0);
	float fade = exp(-age / (dent_life * 0.4)); // the depth: the wind fills it
	float soft = 0.004 + 0.02 * life_share; // the edges slump: a new print is crisp, an old one is a soft hollow
	// a sole: the heel and the ball of the foot (with the toes) as two ellipses, the arch where they meet
	float heel = length(vec2(q.x / 0.04, (q.y + 0.085) / 0.055));
	float ball = length(vec2(q.x / 0.062, (q.y - 0.045) / 0.105));
	float outside = (min(heel, ball) - 1.0) * 0.045; // about the metres outside the sole (negative inside)
	float inside = 1.0 - smoothstep(-soft, soft, outside);
	// the weight is on the heel and the ball: the arch is shallower
	float arch = smoothstep(0.045, 0.0, abs(q.y + 0.02)) * (1.0 - smoothstep(0.0, 0.02, -outside - 0.0));
	float pressure = 1.0 - 0.4 * arch;
	// the sand pushed out stands up in a rim just outside
	float rim = exp(-pow((outside - 0.016) / (0.012 + soft), 2.0)) * (1.0 - inside);
	pressed = inside * (1.0 - life_share);
	return (-inside * pressure + 0.25 * rim) * dent_depth * fade;
}

// The height change at planet position `p` from every print near it; `pressed` is the most pressed.
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
		if (dot(d, d) > 0.09) {
			continue;
		}
		float age = dent_now - where.w;
		if (age < 0.0 || age > dent_life * 1.4) {
			continue;
		}
		vec4 toward = texelFetch(dent_stamps, ivec2(i, 1), 0);
		vec3 up = texelFetch(dent_stamps, ivec2(i, 2), 0).xyz;
		vec3 right = cross(toward.xyz, up);
		float one_pressed;
		h += dent_foot(vec2(dot(d, right) * toward.w, dot(d, toward.xyz)), age, one_pressed);
		pressed = max(pressed, one_pressed);
	}
	return h;
}
