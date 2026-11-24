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
uniform float tip_lightening : hint_range(0.0, 1.0) = 0.04;     // the tips are this much lighter than the roots
uniform float density : hint_range(0.2, 1.0) = 1.0;             // share of the locks that are drawn
uniform vec3 tip_color : source_color = vec3(0.8, 0.2, 0.45);    // the dyed ends
uniform float tip_mix : hint_range(0.0, 1.0) = 0.0;             // how much of the ends are dyed (0 = none)
uniform vec3 stubble_skin : source_color = vec3(0.75, 0.52, 0.42);   // skin tone seen through shaved hair (the scalp layer is part skin)
uniform float scalp_layer : hint_range(0.0, 1.0) = 1.0;      // the solid base layer under the hair (0 = none: only the hairs are drawn)
uniform float strands = 14.0;
uniform bool single_hairs = false;                              // strands mode: each ribbon IS one hair (no strand lanes inside it)                                   // strands across one lock
uniform float wet : hint_range(0.0, 1.0) = 0.0;                // wet or oily hair: darker, with thin, bright, sharp highlights
uniform float wrap_k : hint_range(0.05, 1.0) = 0.25;               // how much the side of a lock turned away from the sun is darker (0.25: flat, the old grey room; 0.6-1.0: a lock shades the one under it)
uniform float sun_gain = 0.15;                                 // how much the sun lights the strands (a grey room tuned it low; a real sun-lit scene wants more, so the shadow between locks shows)
uniform float shine : hint_range(0.0, 1.0) = 0.25;              // strength of the two highlights
uniform float shift_primary = -0.08;                            // how far each highlight is slid along the normal
uniform float shift_secondary = 0.22;
uniform float exponent_primary = 55.0;                          // how tight each highlight is
uniform float exponent_secondary = 35.0;
uniform vec3 wind = vec3(0.0);                                  // wind in model space, metres of bend at the tip
uniform float wind_speed = 1.6;
uniform sampler2D sim_tex : filter_nearest;   // the hair simulation (HairSim): one row per guide strand, one pixel per point: its offset from the rest place, in model space
uniform bool use_sim = false;
instance uniform float lod_fade : hint_range(0.0, 1.0) = 1.0;   // the level-of-detail cross-fade: each hair has a random number (COLOR.g) and is drawn while it is below this value, so the old level thins out as the new one thickens (no pop)
instance uniform vec3 sway = vec3(0.0);                          // inertia swing in model space, metres at the tip (one per character: HairSway writes it on the mesh instance)

varying vec2 rest_pos;       // the rest-pose place (UV2: x + y, z + y), for the cap's noise: stays on the hair when the head moves
varying vec3 hair_tangent;     // view space, for light()
varying float strand_shift;    // per-strand random highlight shift
varying float lock_rough;   // a second per-lock random number: some locks are glossier, some duller
varying float lock_rand;   // one random number per guide lock (all the hairs of a lock share it): clumps of hair differ in brightness and shine
varying float cap_flag;        // 1 on the scalp cap (no strands there, so no highlight)

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

// smooth value noise: no square cells, so the hairline edge is fine and ragged instead of stepped
float value_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

void vertex() {
	rest_pos = UV2;
	lock_rough = CUSTOM0.x >= 0.0 ? hash(vec2(floor(CUSTOM0.x + 0.5), 29.0)) : 0.5;
	lock_rand = CUSTOM0.x >= 0.0 ? hash(vec2(floor(CUSTOM0.x + 0.5), 11.0)) : 0.5;
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
		float n = 0.6 * value_noise(rest_pos * 420.0) + 0.4 * value_noise(rest_pos * 1100.0 + 7.0);
		// a solid hair-coloured layer under the locks (no skin or sky between them: short hair left pale, see-through patches over the ears and temples); only the very edge of the hairline fades
		alpha = clamp((COLOR.a - 0.5) * 2.0 * 4.0 - 0.5 * n + 0.35, 0.0, 1.0) * clamp(scalp_layer * 1.0, 0.0, 1.0);   // (the layer's own strength: 0 off, 1 solid under the hair)   // COLOR.a: 0.5 on the hairline, up = above it
		color = hair_color * 0.45 * 0.95 * mix(1.0, 0.55, wet);              // darker than the hair on top, so a thin spot reads as depth in the hair, not as a pale patch
		// where the hair is cut short (COLOR.g from the builder): lighter, with some skin through it, broken up by noise, like stubble
		// clippered stubble: dark follicle dots on skin, denser and darker where the hair is a little longer (the fade), not a flat grey wash
		float dots = smoothstep(0.42, 0.72, value_noise(rest_pos * 2600.0));
		float fade_in = clamp(COLOR.g * 1.3, 0.0, 1.0);
		vec3 stubble = mix(stubble_skin * 0.22, hair_color * 0.5, mix(0.82, 1.0, dots) * mix(1.0, 0.8, fade_in * fade_in));   // (mostly hair colour with a little skin between the dots: bright skin-coloured dots read as orange pimples once the cap covers the whole scalp)
		color = mix(color, stubble, clamp(COLOR.g * 1.3, 0.0, 1.0));
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
		alpha *= step(COLOR.g, density) * step(COLOR.g, lod_fade);
		color = mix(color, color * (1.0 + 1.6 * tip_lightening), smoothstep(0.3, 1.0, UV.y));
		color = mix(color, tip_color, tip_mix * smoothstep(0.5, 0.85, UV.y));       // ombre: dyed ends
		color *= (0.7 + 0.6 * COLOR.r) * (0.85 + 0.3 * random_a);
		color *= vec3(1.0 + 0.1 * (random_b - 0.5), 1.0, 1.0 - 0.14 * (random_b - 0.5));   // each strand a little warmer or cooler: dyed and natural hair is never one flat colour
		// clumps: the hairs of one lock are lighter or darker, warmer or cooler together, so the head reads as locks, not one even fuzz
		float streak = smoothstep(0.78, 1.0, lock_rand);   // about one lock in five is a sun-lit, golden streak (the reference game hair has them: lighter, warmer locks between darker ones)
		color *= (0.6 + 0.7 * lock_rand) * vec3(1.0 + 0.09 * (lock_rand - 0.5), 1.0, 1.0 - 0.18 * (lock_rand - 0.5));
		color *= mix(vec3(1.0), vec3(1.4, 1.28, 1.05), streak);
		if (COLOR.b > 0.1) {
			// a beard hair (blue 0.3): short and packed, so the look comes from depth: dark in the thicket near the skin, lit at the tips, and clumps (patches of a few mm) that are darker or lighter
			float clump = value_noise(rest_pos * 160.0) * 0.6 + value_noise(rest_pos * 520.0) * 0.4;
			color *= mix(0.45, 1.2, clump) * mix(0.3, 1.0, smoothstep(0.0, 0.85, UV.y));
			float streak_b = smoothstep(0.55, 0.9, value_noise(rest_pos * vec2(60.0, 240.0) + 3.0));   // (lighter streaks that run along the beard: a few mm wide, tens of mm long, like the light/dark bands of a groomed beard)
			color *= mix(1.0, 1.45, streak_b * smoothstep(0.3, 0.9, UV.y));
		}
		color *= mix(0.45, 1.0, smoothstep(0.0, 0.4, UV.y));       // roots are in the shade of the hair above them
		color *= mix(1.0, 0.55, wet);   // wet hair is darker
		// bright colours go lemon-yellow once the strand and tip multipliers push linear channels past 1: pull them toward grey as they get brighter
		float luma = dot(color, vec3(0.3, 0.59, 0.11));
		color = mix(color, vec3(luma), clamp(luma * 1.2, 0.0, 0.45));
		strand_shift = (lock_rand - 0.5) * 0.3 + (value_noise(rest_pos * 22.0) - 0.5) * 0.5 + (random_a - 0.5) * 0.45 * (1.0 - 0.85 * wet) + (hash(vec2(floor(UV.y * 22.0), id)) - 0.5) * 0.2;   // (a small spread: neighbouring strands catch the light together, so the highlight is a broad sheet that follows the head, broken at the locks)   // (a wide spread: parallel strands catch the light at different places, so the highlight is a sparkle of strands, not one band)
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
	vec3 h = (LIGHT + VIEW) / max(length(LIGHT + VIEW), 0.05);   // (not normalize(): a light straight behind the strand makes LIGHT + VIEW a null vector, and the NaN showed as a white stripe)
	// Kajiya-Kay diffuse (the sine of the angle between strand and light), wrapped so the back of the head is not black
	float t_dot_l = dot(t, LIGHT);
	float diffuse_kk = sqrt(max(0.0, 1.0 - t_dot_l * t_dot_l));
	float wrapped = clamp(dot(n, LIGHT) * wrap_k + (1.0 - wrap_k), 0.0, 1.0);   // (a flatter wrap: a lock that sticks up toward the light must not turn a lot lighter than the hair behind it)
	float diffuse = cap_flag > 0.5 ? wrapped * 0.7 : mix(wrapped, diffuse_kk, 0.4); // (the cap has no strands: its tangent is arbitrary, so no strand diffuse there either)
	DIFFUSE_LIGHT += LIGHT_COLOR * ATTENUATION * diffuse * sun_gain;   // no ALBEDO here: the engine multiplies the diffuse light by albedo itself after the light loop
	if (cap_flag < 0.5) { // (the scalp cap has no strands: its tangent is arbitrary, so a highlight on it is a grey patch, seen over the ear)
		// two highlights: the tangent slid along the normal, then 1 - dot^2 under a power
		vec3 t1 = t + n * (shift_primary + strand_shift);
		t1 = t1 / max(length(t1), 0.2);   // (not normalize(): when the strand lies against the normal the shifted tangent is a null vector and normalize gives NaN, which showed as a white stripe)
		vec3 t2 = t + n * (shift_secondary + strand_shift);
		t2 = t2 / max(length(t2), 0.2);
		float d1 = dot(t1, h);
		float d2 = dot(t2, h);
		float rough_k = mix(1.25, 0.8, lock_rough) * (1.0 + 1.8 * wet);   // (wet: much tighter highlights)   // roughness variation per lock: a smaller exponent is a wider, duller highlight
		float spec1 = pow(sqrt(max(0.0, 1.0 - d1 * d1)), exponent_primary * rough_k);
		float spec2 = pow(sqrt(max(0.0, 1.0 - d2 * d2)), exponent_secondary * rough_k);
		float lit = smoothstep(-0.3, 0.6, dot(n, LIGHT));   // (a wide ramp: a narrow one drew a hard-edged lit patch on the head where the normal crosses it)
		float dark = 1.0 - smoothstep(0.05, 0.35, dot(ALBEDO, vec3(0.3, 0.59, 0.11)));   // dark hair has a whiter, stronger highlight (a black strand shows only its shine)
		vec3 highlight = (mix(vec3(0.75, 0.6, 0.4), ALBEDO * 4.0, 0.97 - 0.75 * (1.0 - smoothstep(0.004, 0.04, dot(ALBEDO, vec3(0.3, 0.59, 0.11))))) * spec1 * 0.5 * (0.3 + 0.18 * dark) + ALBEDO * 1.3 * spec2 * 0.35 + vec3(0.6, 0.48, 0.32) * spec2 * 0.08 * (1.0 - smoothstep(0.004, 0.04, dot(ALBEDO, vec3(0.3, 0.59, 0.11))))) * shine;   // the first highlight is half tinted by the hair colour
		// back-lit glow (the "TT" lobe of Marschner et al.): light that comes through the strand toward the viewer
		float through = pow(clamp(dot(-LIGHT, VIEW), 0.0, 1.0), 5.0);
		DIFFUSE_LIGHT += LIGHT_COLOR * ATTENUATION * through * 0.07 * (0.4 + 0.6 * dot(ALBEDO, vec3(0.3, 0.59, 0.11)) * 4.0);
		// the highlights layer: the sun-lit golden locks (see the colour streaks) also shine warmer and stronger
		float golden = smoothstep(0.78, 1.0, lock_rand);
		highlight *= mix(vec3(1.0), vec3(1.2, 1.08, 0.85), golden);
		highlight *= 1.0 + 2.5 * wet;
		highlight = mix(highlight, vec3(dot(highlight, vec3(0.34))) * vec3(1.0, 0.97, 0.93), wet);   // (the shine of wet hair is near white, not the warm khaki of dry brown hair)
		vec3 glint = highlight * LIGHT_COLOR * ATTENUATION * lit;
		if (any(isnan(glint)) || any(isinf(glint))) {
			glint = vec3(0.0);   // (a NaN from the strand maths showed as a white stripe)
		}
		float glint_cap = (0.001 + 0.06 * dot(ALBEDO, vec3(0.3, 0.59, 0.11)) + 0.006 * dark) * (1.0 + 9.0 * wet);   // (wet hair: long bright highlights along the strands, much more than the dry cap allows)
		float glint_max = max(max(glint.r, glint.g), max(glint.b, 1e-6));
		SPECULAR_LIGHT += max(glint, vec3(0.0)) * min(1.0, glint_cap / glint_max);   // scaled, not clamped per channel: clamping a brown glint turned it into grey
	}
}
