shader_type spatial;
render_mode cull_disabled;
// Head hair for the base humans (the HumanHair native class builds the mesh): locks of hair as flat tapered ribbons, plus a thin cap over
// the scalp. The strands are drawn here, so the colour is a parameter. The mesh's vertex colour carries per-lock data:
//   red = random brightness, green = random 0..1 (a lock is drawn when green <= density), blue = 1 on the scalp cap, alpha = the cap's
//   fade toward the hairline. TANGENT runs along the strand (root to tip). UV on a lock: x across the ribbon, y from the root (0) to the tip (1).
//
// Lighting is Kajiya-Kay with two shifted highlights (Scheuermann, "Practical Real-Time Hair Rendering and Shading", GDC 2004): the strand
// tangent stands in for the normal, a white highlight sits on the lit side and a coloured one on the far side, each nudged along the normal
// by a per-strand random shift so the shine breaks up. Motion is done in the vertex stage: wind bends each lock more toward its tip, and
// `sway` (the head's inertia, from the native HairSway spring) swings the whole lot.

uniform vec3 hair_color : source_color = vec3(0.13, 0.08, 0.045);
uniform float tip_lightening : hint_range(0.0, 1.0) = 0.15;     // the tips are this much lighter than the roots
uniform float density : hint_range(0.2, 1.0) = 1.0;             // share of the locks that are drawn
uniform vec3 tip_color : source_color = vec3(0.8, 0.2, 0.45);    // the dyed ends
uniform float tip_mix : hint_range(0.0, 1.0) = 0.0;             // how much of the ends are dyed (0 = none)
uniform float strands = 14.0;
uniform bool single_hairs = false;                              // strands mode: each ribbon IS one hair (no strand lanes inside it)                                   // strands across one lock
uniform float shine : hint_range(0.0, 1.0) = 0.4;               // strength of the two highlights
uniform float shift_primary = -0.08;                            // how far each highlight is slid along the normal
uniform float shift_secondary = 0.22;
uniform float exponent_primary = 90.0;                          // how tight each highlight is
uniform float exponent_secondary = 28.0;
uniform vec3 wind = vec3(0.0);                                  // wind in model space, metres of bend at the tip
uniform float wind_speed = 1.6;
uniform sampler2D sim_tex : filter_nearest;   // the hair simulation (HairSim): one row per guide strand, one pixel per point: its offset from the rest place, in model space
uniform bool use_sim = false;
instance uniform vec3 sway = vec3(0.0);                          // inertia swing in model space, metres at the tip (one per character: HairSway writes it on the mesh instance)

varying vec2 rest_pos;       // the rest-pose place (UV2: x + y, z + y), for the cap's noise: stays on the hair when the head moves
varying vec3 hair_tangent;     // view space, for light()
varying float strand_shift;    // per-strand random highlight shift
varying float cap_flag;        // 1 on the scalp cap (no strands there, so no highlight)

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void vertex() {
	rest_pos = UV2;
	cap_flag = COLOR.b > 0.5 ? 1.0 : 0.0;
	// how loose this vertex is: 0 at the root, 1 at the tip; the scalp cap does not move
	float loose = COLOR.b > 0.5 ? 0.0 : pow(clamp(UV.y, 0.0, 1.0), 1.4);
	float phase = COLOR.r * 6.2831 + UV2.x * 9.0 + UV2.y * 7.0;
	float gust = 0.55 + 0.45 * sin(TIME * wind_speed * 0.37 + (UV2.x - UV2.y) * 4.0);
	vec3 flutter = vec3(sin(TIME * wind_speed + phase), 0.35 * sin(TIME * wind_speed * 1.3 + phase * 1.7), cos(TIME * wind_speed * 0.8 + phase));
	VERTEX += (wind * gust + wind * 0.25 * flutter + (use_sim ? vec3(0.0) : sway)) * loose;
	if (use_sim && CUSTOM0.x >= 0.0) {
		// the simulated guide this hair follows: its offset at this point of the strand (between two points)
		int guide = int(CUSTOM0.x + 0.5);
		float kf = CUSTOM0.y;
		int k0 = int(floor(kf));
		int k1 = min(k0 + 1, textureSize(sim_tex, 0).x - 1);
		vec3 d0 = texelFetch(sim_tex, ivec2(k0, guide), 0).rgb;
		vec3 d1 = texelFetch(sim_tex, ivec2(k1, guide), 0).rgb;
		VERTEX += mix(d0, d1, kf - float(k0));
	}
	hair_tangent = normalize((MODELVIEW_MATRIX * vec4(TANGENT, 0.0)).xyz);
}

void fragment() {
	vec3 color = hair_color;
	float alpha;
	if (COLOR.b > 0.5) {
		// The scalp cap: dark, ragged at the hairline.
		float n = hash(floor(rest_pos * 350.0));
		alpha = COLOR.a * 1.25 - 0.1 - 0.4 * n;
		if (single_hairs) {
			alpha = clamp(COLOR.a * 4.0, 0.0, 1.0);   // strand hair: a solid hair-coloured layer under the strands (no skin between them), only the very edge of the hairline fades
			color = hair_color * 0.45;                // darker than the strands on top, so a thin spot reads as depth in the hair, not as a pale patch
		}
		color *= 0.7;
		strand_shift = 0.0;
	} else {
		float across = single_hairs ? 0.5 : UV.x * strands;
		float id = floor(across);
		float lane = fract(across);
		float random_a = hash(vec2(id, 3.0));
		float random_b = hash(vec2(id, 7.0));
		// strands: lines of random width, with a body between them so the lock reads as a mass
		float strand = 1.0 - smoothstep(0.15 + 0.3 * random_a, 0.5, abs(lane - 0.5));
		float cut = mix(0.6, 1.0, random_b);                       // ragged tips: each strand stops somewhere
		float tip = 1.0 - smoothstep(cut - 0.1, cut, UV.y);
		float edge = smoothstep(0.0, 0.12, UV.x) * smoothstep(0.0, 0.12, 1.0 - UV.x);
		alpha = clamp(0.42 + 0.7 * strand, 0.0, 1.0) * tip * edge * 1.3;
		if (single_hairs) {
			// one hair: a soft line across the ribbon, fading out at its tip; the lock-level ragged cut is not needed
			alpha = 1.0;   // opaque across the whole ribbon: the geometry (width, taper) sets the thickness; a soft edge + the scissor left only the middle 40% of a hair-thin ribbon
		}
		alpha *= step(COLOR.g, density);
		color = mix(color, color * (1.0 + 1.6 * tip_lightening), smoothstep(0.3, 1.0, UV.y));
		color = mix(color, tip_color, tip_mix * smoothstep(0.5, 0.85, UV.y));       // ombre: dyed ends
		color *= (0.7 + 0.6 * COLOR.r) * (0.85 + 0.3 * random_a);
		color *= mix(0.45, 1.0, smoothstep(0.0, 0.4, UV.y));       // roots are in the shade of the hair above them
		// bright colours go lemon-yellow once the strand and tip multipliers push linear channels past 1: pull them toward grey as they get brighter
		float luma = dot(color, vec3(0.3, 0.59, 0.11));
		color = mix(color, vec3(luma), clamp(luma * 1.2, 0.0, 0.45));
		strand_shift = (random_a - 0.5) * 0.35 + (hash(vec2(floor(UV.y * 22.0), id)) - 0.5) * 0.25;
	}
	ALBEDO = color;
	ALPHA = alpha;
	ALPHA_SCISSOR_THRESHOLD = 0.45;
	ROUGHNESS = 0.7;
	SPECULAR = 0.0;      // the highlights come from light() below
	METALLIC = 0.0;
}

void light() {
	vec3 t = normalize(hair_tangent);
	vec3 n = normalize(NORMAL);
	vec3 h = normalize(LIGHT + VIEW);
	// Kajiya-Kay diffuse (the sine of the angle between strand and light), wrapped so the back of the head is not black
	float t_dot_l = dot(t, LIGHT);
	float diffuse_kk = sqrt(max(0.0, 1.0 - t_dot_l * t_dot_l));
	float wrapped = clamp(dot(n, LIGHT) * 0.5 + 0.5, 0.0, 1.0);
	float diffuse = cap_flag > 0.5 ? wrapped * 0.7 : mix(wrapped, diffuse_kk, 0.4); // (the cap has no strands: its tangent is arbitrary, so no strand diffuse there either)
	DIFFUSE_LIGHT += LIGHT_COLOR * ATTENUATION * diffuse * 0.15;   // no ALBEDO here: the engine multiplies the diffuse light by albedo itself after the light loop
	if (cap_flag < 0.5) { // (the scalp cap has no strands: its tangent is arbitrary, so a highlight on it is a grey patch, seen over the ear)
		// two highlights: the tangent slid along the normal, then 1 - dot^2 under a power
		vec3 t1 = normalize(t + n * (shift_primary + strand_shift));
		vec3 t2 = normalize(t + n * (shift_secondary + strand_shift));
		float d1 = dot(t1, h);
		float d2 = dot(t2, h);
		float spec1 = pow(sqrt(max(0.0, 1.0 - d1 * d1)), exponent_primary);
		float spec2 = pow(sqrt(max(0.0, 1.0 - d2 * d2)), exponent_secondary);
		float lit = smoothstep(-0.05, 0.25, dot(n, LIGHT));
		vec3 highlight = (mix(vec3(0.8), ALBEDO * 4.0, 0.5) * spec1 * 0.2 + ALBEDO * 1.3 * spec2 * 0.28) * shine;   // the first highlight is half tinted by the hair colour
		// back-lit glow (the "TT" lobe of Marschner et al.): light that comes through the strand toward the viewer
		float through = pow(clamp(dot(-LIGHT, VIEW), 0.0, 1.0), 5.0);
		DIFFUSE_LIGHT += LIGHT_COLOR * ATTENUATION * through * 0.25;
		SPECULAR_LIGHT += min(highlight, vec3(0.3)) * LIGHT_COLOR * ATTENUATION * lit;   // clamped: a highlight must not burn out
	}
}
