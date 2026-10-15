shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled, specular_schlick_ggx;
// Faceted water: the surface is rolled by a few sine waves in world space and lit per facet.
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
global uniform float realism;

varying vec3 world_pos;

float ripple_hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
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

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	VERTEX.y += waves(world_pos.xz, TIME * wave_speed) * wave_height;
}

void fragment() {
	vec3 flat_normal = normalize(cross(dFdx(VERTEX), dFdy(VERTEX)));
	if (dot(flat_normal, VIEW) < 0.0) {
		flat_normal = -flat_normal;
	}
	// realistic: smooth waves with fine ripples on top
	vec2 slope = wave_slope(world_pos.xz, TIME * wave_speed) * wave_height * 1.1;
	slope += ripples(world_pos.xz, TIME);
	vec3 smooth_normal = normalize((VIEW_MATRIX * vec4(-slope.x, 1.0, -slope.y, 0.0)).xyz);
	NORMAL = normalize(mix(flat_normal, smooth_normal, realism));
	float depth = texture(depth_texture, SCREEN_UV).r;
	vec3 ndc = vec3(SCREEN_UV * 2.0 - 1.0, depth);
	vec4 scene = INV_PROJECTION_MATRIX * vec4(ndc, 1.0);
	scene.xyz /= scene.w;
	float thickness = max(VERTEX.z - scene.z, 0.0);
	float t = clamp(thickness / depth_fade, 0.0, 1.0);
	vec4 color = mix(shallow_color, deep_color, sqrt(t));
	float foam = 1.0 - smoothstep(0.0, foam_width, thickness);
	ALBEDO = mix(color.rgb, foam_color.rgb, foam * 0.85);
	ALPHA = clamp(mix(color.a, 1.0, foam), 0.0, 1.0);
	ROUGHNESS = mix(mix(0.08, 0.025, realism), 0.6, foam);
	SPECULAR = mix(0.7, 1.0, realism);
	METALLIC = 0.0;
}
