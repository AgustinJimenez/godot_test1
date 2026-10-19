shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled, specular_schlick_ggx;
// Planet water (water_lowpoly with smooth lit normals at every look): faceted water: the surface is rolled by a few sine waves in world space and lit per facet.
// Colour goes from shallow to deep with the depth under the surface, foam shows where the water
// meets the ground.

uniform vec4 shallow_color : source_color = vec4(0.22, 0.62, 0.66, 0.55);
uniform vec4 deep_color : source_color = vec4(0.02, 0.16, 0.32, 0.96);
uniform vec4 foam_color : source_color = vec4(0.95, 0.98, 1.0, 1.0);
uniform float wave_height = 0.28;
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
	vec2 a = p * 0.9 + vec2(t * 0.35, t * 0.2);
	vec2 b = p * 2.3 - vec2(t * 0.5, -t * 0.3);
	float e = 0.15;
	vec2 slope_a = vec2(ripple_noise(a + vec2(e, 0.0)) - ripple_noise(a), ripple_noise(a + vec2(0.0, e)) - ripple_noise(a)) / e;
	vec2 slope_b = vec2(ripple_noise(b + vec2(e, 0.0)) - ripple_noise(b), ripple_noise(b + vec2(0.0, e)) - ripple_noise(b)) / e;
	return slope_a * 0.09 + slope_b * 0.05;
}

float waves(vec2 p, float t) {
	float w = sin(p.x * 0.31 + t * 1.3) * 0.5;
	w += sin(p.y * 0.23 - t * 1.1) * 0.5;
	w += sin((p.x + p.y) * 0.57 + t * 1.9) * 0.25;
	w += sin((p.x - p.y) * 0.9 - t * 2.4) * 0.12;
	return w;
}

// the slope of waves() along x and z (for the smooth, realistic normal)
vec2 wave_slope(vec2 p, float t) {
	float dx = cos(p.x * 0.31 + t * 1.3) * 0.31 * 0.5;
	float dz = cos(p.y * 0.23 - t * 1.1) * 0.23 * 0.5;
	float s = cos((p.x + p.y) * 0.57 + t * 1.9) * 0.57 * 0.25;
	dx += s;
	dz += s;
	float d = cos((p.x - p.y) * 0.9 - t * 2.4) * 0.9 * 0.12;
	dx += d;
	dz -= d;
	return vec2(dx, dz);
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
	return textureLod(roll_map, uv, 0.0).r;
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	roll = COLOR.r * map_roll(world_pos.xz);
	VERTEX.y += waves(world_pos.xz, TIME * wave_speed) * wave_height * roll;
}

// view-space z of the scene behind the water at a screen position
float scene_z(vec2 uv, mat4 inv_projection) {
	float d = texture(depth_texture, uv).r;
	vec4 p = inv_projection * vec4(uv * 2.0 - 1.0, d, 1.0);
	return p.z / p.w;
}

void fragment() {
	vec3 flat_normal = normalize(cross(dFdx(VERTEX), dFdy(VERTEX)));
	if (dot(flat_normal, VIEW) < 0.0) {
		flat_normal = -flat_normal;
	}
	// realistic: smooth waves with fine ripples on top
	// far away the fine ripples (smaller than a pixel) would only alias into a speckle of sun glints:
	// they fade out with the distance, then the long waves, so the glint is one soft patch
	float away = length(VERTEX);
	float fine_keep = 1.0 - smoothstep(40.0, 500.0, away);
	float long_keep = 1.0 - 0.7 * smoothstep(400.0, 4000.0, away);
	vec2 slope = wave_slope(world_pos.xz, TIME * wave_speed) * wave_height * 1.1 * roll * long_keep;
	slope += ripples(world_pos.xz, TIME) * mix(0.35, 1.0, roll) * fine_keep;
	vec3 smooth_normal = normalize((VIEW_MATRIX * vec4(-slope.x, 1.0, -slope.y, 0.0)).xyz);
	NORMAL = normalize(mix(flat_normal, smooth_normal, 0.9)); // planet water: smooth glint, no facet squares
	float behind = scene_z(SCREEN_UV, INV_PROJECTION_MATRIX);
	float thickness = max(VERTEX.z - behind, 0.0);
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
	foam = max(foam, crest * streaks * 0.8 * realism);

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
	float fresnel = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 4.0);

	vec3 low_albedo = mix(color.rgb, foam_color.rgb, foam * 0.85);
	vec3 real_albedo = mix(body * (1.0 - see * 0.85), foam_color.rgb, foam * 0.9);
	ALBEDO = mix(low_albedo, real_albedo, realism);
	EMISSION = bed * transmit * (1.0 - foam) * (1.0 - fresnel * 0.7) * realism;
	float low_alpha = clamp(mix(color.a, 1.0, foam), 0.0, 1.0);
	ALPHA = mix(low_alpha, 1.0, realism);
	ROUGHNESS = mix(mix(0.08, 0.025, realism) + 0.1 * smoothstep(300.0, 5000.0, away), 0.6, foam);
	SPECULAR = mix(0.7, 1.0, realism);
	METALLIC = 0.0;
}
