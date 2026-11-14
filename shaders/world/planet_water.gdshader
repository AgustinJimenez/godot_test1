shader_type spatial;
render_mode blend_mix, depth_draw_always, cull_disabled, specular_schlick_ggx;
// Planet water (water_lowpoly with smooth lit normals at every look): faceted water: the surface is rolled by a few sine waves in world space and lit per facet.
// Colour goes from shallow to deep with the depth under the surface, foam shows where the water
// meets the ground.

uniform vec4 shallow_color : source_color = vec4(0.22, 0.62, 0.66, 0.55);
uniform vec4 deep_color : source_color = vec4(0.02, 0.16, 0.32, 0.96);
uniform vec4 foam_color : source_color = vec4(0.95, 0.98, 1.0, 1.0);
uniform float wave_height = 0.8;
uniform float thickness_bias = 0.0;
uniform float cut_beyond = 0.0; // metres: past this the surface is not drawn (0: always), dithered over its last fifth; the voxel sea's coarse levels of detail cut the shallows into rows and bricks, the far sea sphere under it has none
uniform float wave_speed = 0.8;
uniform float depth_fade = 5.0;
uniform float foam_width = 0.55;
uniform sampler2D depth_texture : hint_depth_texture, repeat_disable, filter_nearest;
uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_linear_mipmap;
// realistic: how fast the water swallows each colour per metre (red goes first, so deep water is
// blue-green), how far the waves bend the picture of the bed, and the width of the shore foam
uniform vec3 absorption = vec3(0.42, 0.11, 0.06);
uniform float refraction_strength = 0.05;
global uniform float realism;

varying vec3 world_pos;

// no sin(): its precision on the GPU turns value noise into hard-edged blocks
float ripple_hash(vec2 p) {
	vec3 q = fract(vec3(p.xyx) * 0.1031);
	q += dot(q, q.yzx + 33.33);
	return fract((q.x + q.y) * q.z);
}

float ripple_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = smoothstep(0.0, 1.0, fract(p));
	return mix(mix(ripple_hash(i), ripple_hash(i + vec2(1.0, 0.0)), f.x),
			mix(ripple_hash(i + vec2(0.0, 1.0)), ripple_hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

// the slope of two drifting layers of noise: ripples that do not repeat
vec2 ripples(vec2 p, float t) {
	// (the value noise's grid is rotated off the axes, a different way for each layer: grid-aligned it laid rows over the sea)
	vec2 a = mat2(vec2(0.8, 0.6), vec2(-0.6, 0.8)) * p * 0.9 + vec2(t * 0.35, t * 0.2);
	vec2 b = mat2(vec2(0.5, -0.866), vec2(0.866, 0.5)) * p * 2.3 - vec2(t * 0.5, -t * 0.3);
	float e = 0.15;
	vec2 slope_a = vec2(ripple_noise(a + vec2(e, 0.0)) - ripple_noise(a), ripple_noise(a + vec2(0.0, e)) - ripple_noise(a)) / e;
	vec2 slope_b = vec2(ripple_noise(b + vec2(e, 0.0)) - ripple_noise(b), ripple_noise(b + vec2(0.0, e)) - ripple_noise(b)) / e;
	return slope_a * 0.09 + slope_b * 0.05;
}

// a wave with a sharp crest and a broad trough (what a Gerstner wave's circling water makes), not a plain sine; and its slope
float crest_sine(float x) {
	return 2.0 * pow(0.5 + 0.5 * sin(x), 1.4) - 1.0;
}
float crest_sine_d(float x) {
	return 1.4 * pow(0.5 + 0.5 * sin(x) + 0.0001, 0.4) * cos(x);
}

// the four swells run in directions that are not the axes (axis-aligned sines laid a grid of rows over the sea)
const vec2 WAVE_K0 = vec2(0.30, 0.08);
const vec2 WAVE_K1 = vec2(-0.07, 0.22);
const vec2 WAVE_K2 = vec2(0.43, 0.37);
const vec2 WAVE_K3 = vec2(0.95, -0.4);
const vec2 WAVE_K4 = vec2(0.17, -0.19); // (two long swells more, of other lengths and ways: two or four swells cross in a regular lattice)
const vec2 WAVE_K5 = vec2(-0.11, -0.045);

// the places the six swells are read at wander over the sea (a slow noise, tens of metres): six plane waves in fixed directions line their crests up
// into a regular lattice of bright cells in the sun's glitter; wandering phases break it up. (the slope below ignores the warp's own slope: it is small)
vec2 sea_warp(vec2 p) {
	return (vec2(ripple_noise(p * 0.006 + vec2(3.1, 7.7)), ripple_noise(p * 0.006 + vec2(19.3, 2.9))) * 2.0 - 1.0) * 35.0;
}

// the two short swells as drifting noise, not as plane waves: two sines in fixed directions cross in a regular lattice of cells (a grid of glints in the sun's
// path); noise at the same sizes (about 6-12 m) has no regular lattice
float short_swell(vec2 p, float t) {
	vec2 a = mat2(vec2(0.8, 0.6), vec2(-0.6, 0.8)) * p * 0.085 + vec2(t * 0.45, t * 0.3);
	vec2 b = mat2(vec2(0.28, -0.96), vec2(0.96, 0.28)) * p * 0.16 - vec2(t * 0.6, -t * 0.35);
	return ripple_noise(a) * 0.7 + ripple_noise(b) * 0.35 - 0.525;
}

vec2 short_swell_slope(vec2 p, float t) {
	const float e = 0.4;
	return vec2(short_swell(p + vec2(e, 0.0), t) - short_swell(p - vec2(e, 0.0), t), short_swell(p + vec2(0.0, e), t) - short_swell(p - vec2(0.0, e), t)) / (2.0 * e);
}

float waves(vec2 p, float t) {
	p += sea_warp(p);
	float w = crest_sine(dot(p, WAVE_K0) + t * 1.3) * 0.5;
	w += crest_sine(dot(p, WAVE_K1) - t * 1.1) * 0.5;
	w += short_swell(p, t) * 0.8;
	w += crest_sine(dot(p, WAVE_K4) + t * 0.9) * 0.4;
	w += crest_sine(dot(p, WAVE_K5) - t * 0.7) * 0.4;
	return w;
}

// the slope of waves() along x and z (for the smooth, realistic normal)
vec2 wave_slope(vec2 p, float t, float short_gain, float foot) {
	p += sea_warp(p);
	// a swell of wavelength L is drawn only while a pixel covers well under L of the sea (foot: metres a pixel covers, along the view): wider and it aliases into
	// rows and rings (the moire of the far glitter); the roughness takes what it leaves out
	float k0 = 1.0 - smoothstep(0.08, 0.35, foot * length(WAVE_K0) / 6.2832);
	float k1 = 1.0 - smoothstep(0.08, 0.35, foot * length(WAVE_K1) / 6.2832);
	float k4 = 1.0 - smoothstep(0.08, 0.35, foot * length(WAVE_K4) / 6.2832);
	float k5 = 1.0 - smoothstep(0.08, 0.35, foot * length(WAVE_K5) / 6.2832);
	vec2 s = WAVE_K0 * crest_sine_d(dot(p, WAVE_K0) + t * 1.3) * 0.5 * k0;
	s += WAVE_K1 * crest_sine_d(dot(p, WAVE_K1) - t * 1.1) * 0.5 * k1;
	// the two short swells come and go over the sea (a steady crossing of two swells is a regular lattice of diamonds)
	s += short_gain * 1.1 * short_swell_slope(p, t);
	s += WAVE_K4 * crest_sine_d(dot(p, WAVE_K4) + t * 0.9) * 0.4 * k4;
	s += WAVE_K5 * crest_sine_d(dot(p, WAVE_K5) - t * 0.7) * 0.4 * k5;
	return s;
}

// vertex colour red = how much of the waves this water gets: the open sea is 1 (a plane with no
// vertex colour is white), small lakes ask for less so a pond does not roll like the ocean.
varying float roll;

// the sea also asks a map of the ground around the player: a pond in a basin or a shallow bay rolls
// little, the wide deep sea fully. roll_area = x and z of the map's corner and its width (0: no map).
uniform sampler2D roll_map : filter_linear, repeat_disable;
uniform vec3 roll_area = vec3(0.0);

float map_roll(vec2 p) {
	if (roll_area.z <= 0.0) {
		return 1.0;
	}
	vec2 uv = (p - roll_area.xy) / roll_area.z;
	if (uv.x < 0.0 || uv.y < 0.0 || uv.x > 1.0 || uv.y > 1.0) {
		return 1.0;
	}
	// (the map is a window round the player: the shallow bay's calm fades back into the open sea's roll toward the window's edge, or the edge shows as a straight line in the sea)
	float inside = min(min(uv.x, uv.y), min(1.0 - uv.x, 1.0 - uv.y));
	return mix(1.0, textureLod(roll_map, uv, 0.0).r, smoothstep(0.0, 0.2, inside));
}

global uniform vec3 cloud_sun_world; // toward the star
#include "res://shaders/world/planet_haze.gdshaderinc" // the haze by height (FOG)

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	// (the swell moves the mesh up and down: where the sea is shallow that cuts polygon holes in the water and lays patches of it over the sand, so it dies out well before the shore)
	roll = COLOR.r * smoothstep(0.45, 0.95, map_roll(world_pos.xz));
	// the geometry swells only near: far off the vertices are tens or hundreds of metres apart and a swell of 6-28 m sampled that coarsely
	// aliases into a moire of rows (the far sea mesh and the coarse water blocks); the normals carry the swell there
	float near_swell = 1.0 - smoothstep(60.0, 300.0, length((MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).xyz));
	VERTEX.y += waves(world_pos.xz, TIME * wave_speed) * wave_height * roll * near_swell;
}

// view-space z of the scene behind the water at a screen position
float scene_z(vec2 uv, mat4 inv_projection) {
	float d = texture(depth_texture, uv).r;
	if (d < 1.0e-6) {
		return -1.0e6; // nothing drawn behind (the far sea past the seabed's range): infinitely deep, not the 0/0 of the far plane (it read as no water at all: a light patch with straight edges)
	}
	vec4 p = inv_projection * vec4(uv * 2.0 - 1.0, d, 1.0);
	return p.z / p.w;
}

// What the water mirrors of the land: a short march in screen space along the reflected ray, against the
// depth of the scene drawn before the water. Returns the colour (rgb) and how sure the hit is (a); the
// sky is mirrored by the environment's own reflection, this adds the hills, trees and shores.
vec4 mirror_of_the_land(vec3 view_pos, vec3 normal, mat4 projection, mat4 inv_projection, vec3 up_view, float jitter) {
	vec3 ray = reflect(normalize(view_pos), normal);
	if (ray.z > -0.02 && ray.y < 0.0) {
		return vec4(0.0);
	}
	if (dot(ray, up_view) < 0.02) {
		return vec4(0.0); // (a ray that does not rise only meets the sea bed, seen through the water: not a reflection)
	}
	float stride = max(length(view_pos) * 0.02, 1.5) * (0.6 + 0.8 * jitter); // (jittered start: the fixed steps made a lattice of hits and misses)
	vec3 at = view_pos;
	for (int i = 0; i < 28; i++) {
		at += ray * stride;
		stride *= 1.22;
		vec4 clip = projection * vec4(at, 1.0);
		if (clip.w <= 0.0) {
			return vec4(0.0);
		}
		vec2 uv = clip.xy / clip.w * 0.5 + 0.5;
		if (uv.x < 0.0 || uv.x > 1.0 || uv.y < 0.0 || uv.y > 1.0) {
			return vec4(0.0);
		}
		float scene = scene_z(uv, inv_projection);
		float gap = at.z - scene; // view z is negative ahead: the ray is behind the scene when gap < 0
		if (gap < 0.0 && gap > -stride * 3.0) {
			float edge = 1.0 - smoothstep(0.35, 0.5, max(abs(uv.x - 0.5), abs(uv.y - 0.5)));
			return vec4(textureLod(screen_texture, uv, 0.0).rgb, edge * (1.0 - float(i) / 40.0));
		}
	}
	return vec4(0.0);
}

void fragment() {
	if (cut_beyond > 0.0) {
		float into = (length(VERTEX) - cut_beyond * 0.8) / (cut_beyond * 0.2);
		float dither = fract(52.9829189 * fract(dot(FRAGCOORD.xy, vec2(0.06711056, 0.00583715))));
		if (into > dither) {
			discard;
		}
	}
	FOG = planet_haze(mat3(INV_VIEW_MATRIX) * VERTEX, cloud_sun_world);
	vec3 flat_normal = normalize(cross(dFdx(VERTEX), dFdy(VERTEX)));
	if (dot(flat_normal, VIEW) < 0.0) {
		flat_normal = -flat_normal;
	}
	// realistic: smooth waves with fine ripples on top
	// far away the fine ripples (smaller than a pixel) would only alias into a speckle of sun glints:
	// they fade out with the distance, then the long waves, so the glint is one soft patch
	float away = length(VERTEX);
	float foot = max(length(dFdx(world_pos.xz)), length(dFdy(world_pos.xz))); // metres of sea one pixel covers (long at grazing angles)
	float fine_keep = 1.0 - smoothstep(10.0, 160.0, away); // (the ripples are a few pixels across by 160 m on this 20 km planet; any further they aliased into white glints)
	float long_keep = 1.0 - 0.7 * smoothstep(80.0, 600.0, away); // (kept far out: the long waves are what a far sea glitters on; roughness filters them)
	float short_gain = (0.25 + 1.5 * ripple_noise(world_pos.xz * 0.012 + vec2(TIME * 0.02, -TIME * 0.015))) * (1.0 - 1.0 * smoothstep(30.0, 250.0, away)); // (far off the short swells are a few pixels wide: regular rows of glints)
	vec2 slope = wave_slope(world_pos.xz, TIME * wave_speed, short_gain, foot) * wave_height * 1.1 * roll * long_keep;
	slope += ripples(world_pos.xz, TIME) * mix(0.35, 1.0, roll) * fine_keep;
	vec3 smooth_normal = normalize((VIEW_MATRIX * vec4(-slope.x, 1.0, -slope.y, 0.0)).xyz);
	NORMAL = normalize(mix(flat_normal, smooth_normal, 1.0)); // planet water: smooth glint, no facet squares
	{
		// a wave that leans toward the eye would mirror what lies under the horizon: the dark ground half of the sky (a regular row of dark ovals over the sea);
		// real water mirrors other waves and the haze there. Tip such a normal up until the mirrored ray just clears the horizon.
		vec3 up_eye = mat3(VIEW_MATRIX) * vec3(0.0, 1.0, 0.0); // (the sky the water mirrors is read in world axes: its horizon is the world's, not the planet's at the eye)
		for (int tip = 0; tip < 5; tip++) { // (one push was not enough where the wave leans far toward the eye: the dark ovals stayed)
			float mirrored = dot(reflect(-VIEW, NORMAL), up_eye);
			if (mirrored >= 0.09) {
				break;
			}
			NORMAL = normalize(NORMAL + up_eye * (0.09 - mirrored) * 2.0);
		}
	}
	float behind = scene_z(SCREEN_UV, INV_PROJECTION_MATRIX);
	float thickness = max(VERTEX.z - behind, 0.0) + thickness_bias; // (the far sea's sphere sits a little under the sea's level: it adds that back, so the two match at the hand-over)
	float t = clamp(thickness / depth_fade, 0.0, 1.0);
	vec4 color = mix(shallow_color, deep_color, sqrt(t));

	// foam at the shore: the edge breathes in and out with the swell and is torn by noise
	float swell = 0.5 + 0.5 * sin(TIME * 1.4 + world_pos.x * 0.17 + world_pos.z * 0.13);
	float torn = ripple_noise(world_pos.xz * 1.7 + vec2(TIME * 0.2, -TIME * 0.15));
	float edge = foam_width * mix(1.0, 0.45 + 1.1 * swell, realism) * mix(1.0, 0.55 + 0.9 * torn, realism);
	float foam = 1.0 - smoothstep(0.0, edge, thickness);
	// foam on the wave crests of open water, in streaks that drift
	float crest = smoothstep(0.45, 0.95, waves(world_pos.xz, TIME * wave_speed)) * roll * roll;
	float streaks = smoothstep(0.55, 0.8, ripple_noise(world_pos.xz * 2.6 + vec2(TIME * 0.3, TIME * 0.1)));
	foam = max(foam, crest * streaks * 0.8 * realism * fine_keep); // (a fine pattern: it aliased into white dots on the far sea)

	// realistic: the bed seen through the water, bent by the waves, tinted by what the water absorbs
	vec2 uv = SCREEN_UV + NORMAL.xz * refraction_strength * min(thickness, 1.0);
	if (VERTEX.z - scene_z(uv, INV_PROJECTION_MATRIX) < 0.0) {
		uv = SCREEN_UV; // something in front of the water: do not drag it into the bed
	}
	vec3 bed = textureLod(screen_texture, uv, 0.0).rgb;
	vec3 transmit = exp(-thickness * absorption);
	vec3 body = mix(shallow_color.rgb, deep_color.rgb, sqrt(t));
	float see = (transmit.r + transmit.g + transmit.b) / 3.0;
	// grazing angles reflect instead of letting the bed through
	float fresnel = 0.02 + 0.98 * pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 5.0); // (Schlick, water's F0 of 2 %: UE5 SingleLayerWater)

	vec3 low_albedo = mix(color.rgb, foam_color.rgb, foam * 0.85);
	vec3 real_albedo = mix(body * (1.0 - see * 0.85), foam_color.rgb, foam * 0.9);
	ALBEDO = mix(low_albedo, real_albedo, realism);
	EMISSION = bed * transmit * (1.0 - foam) * (1.0 - fresnel * 0.7) * realism;
	if (realism > 0.5 && away < 700.0) { // (far off the marched mirror only lays a dither of hits over the sea: the sky reflection is enough)
		vec3 up_view = normalize(mat3(VIEW_MATRIX) * normalize(haze_eye));
		float jitter = fract(52.9829189 * fract(dot(FRAGCOORD.xy, vec2(0.06711056, 0.00583715))));
		vec4 mirror = mirror_of_the_land(VERTEX, NORMAL, PROJECTION_MATRIX, INV_PROJECTION_MATRIX, up_view, jitter);
		float grazing = 0.08 + 0.92 * fresnel; // water mirrors little looking straight down
		EMISSION = mix(EMISSION, mirror.rgb, mirror.a * grazing * (1.0 - foam) * 0.85 * (1.0 - smoothstep(250.0, 700.0, away)));
	}
	if (realism > 0.5) {
		// the sun's light through the waves: looking toward the star, a crest thin enough to pass light glows green-turquoise (a wave
		// seen against the low sun), and the shallows scatter a bright blue-green of the bed's own light back up
		float sun_len = length(cloud_sun_world);
		if (sun_len > 0.5) {
			vec3 sun_view = (VIEW_MATRIX * vec4(cloud_sun_world / sun_len, 0.0)).xyz;
			vec3 up_view = normalize(mat3(VIEW_MATRIX) * normalize(haze_eye));
			float sun_up = clamp(dot(sun_view, up_view) * 4.0, 0.0, 1.0); // (no glow with the star under the horizon)
			float against = clamp(dot(sun_view, -VIEW), 0.0, 1.0);
			float facing_away = clamp(dot(smooth_normal, sun_view) * -1.0 + 0.5, 0.0, 1.0); // (the slope that leans away from the star: its back is lit through)
			float glow_keep = 1.0 - smoothstep(0.6, 3.0, foot); // (a crest the size of a pixel or less lit one pixel in a few: far off the glow was diamonds of turquoise along the sun path)
				float crest_thin = mix(0.35, smoothstep(0.2, 0.9, waves(world_pos.xz, TIME * wave_speed)) * roll, glow_keep);
			vec3 glow_tint = vec3(0.04, 0.5, 0.35);
			EMISSION += glow_tint * pow(against, 3.0) * facing_away * (0.25 + crest_thin) * sun_up * (1.0 - foam) * (1.0 - smoothstep(300.0, 1500.0, away)) * (0.15 + 0.85 * glow_keep) * 0.35;
			float shallow_lit = (1.0 - t) * smoothstep(0.0, 1.0, thickness) * sun_up;
			EMISSION += vec3(0.02, 0.2, 0.2) * shallow_lit * (1.0 - foam) * 0.25;
		}
	}
	float low_alpha = clamp(mix(color.a, 1.0, foam), 0.0, 1.0);
	ALPHA = mix(low_alpha, 1.0, realism);
	ROUGHNESS = mix(mix(0.08, 0.025, realism) + 0.22 * smoothstep(25.0, 800.0, away) + 0.12 * smoothstep(1.0, 12.0, foot), 0.6, foam); // (the waves too small to see still tilt the surface: a far sea glitters in a wide path, not a mirror)
	SPECULAR = mix(0.7, 1.0, realism) * (1.0 - 0.3 * smoothstep(250.0, 1300.0, away)); // (far water is never brighter than the sky it mirrors)
	METALLIC = 0.0;
}
