shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled, specular_schlick_ggx;
// A planet's river: a ribbon whose UV.x runs across it (0 bank .. 1 bank) and UV.y along it in
// metres from the source. The surface streams downstream (ripples stretched along the flow that
// drift with the time), is clear and shallow toward the banks and darker over the middle, with foam
// along the banks and where it runs over shallows.

uniform vec4 shallow_color : source_color = vec4(0.28, 0.58, 0.6, 0.45);
uniform vec4 deep_color : source_color = vec4(0.06, 0.24, 0.32, 0.9);
uniform vec4 foam_color : source_color = vec4(0.93, 0.97, 1.0, 1.0);
uniform float flow_speed = 1.6; // m/s the ripples travel
uniform float depth_fade = 2.5;
uniform sampler2D depth_texture : hint_depth_texture, repeat_disable, filter_nearest;

varying vec3 world_pos;

float hash2(vec2 p) {
	vec3 q = fract(vec3(p.xyx) * 0.1031);
	q += dot(q, q.yzx + 33.33);
	return fract((q.x + q.y) * q.z);
}

float value_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = smoothstep(0.0, 1.0, fract(p));
	return mix(mix(hash2(i), hash2(i + vec2(1.0, 0.0)), f.x),
			mix(hash2(i + vec2(0.0, 1.0)), hash2(i + vec2(1.0, 1.0)), f.x), f.y);
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

float scene_z(vec2 uv, mat4 inv_projection) {
	float d = texture(depth_texture, uv).r;
	vec4 p = inv_projection * vec4(uv * 2.0 - 1.0, d, 1.0);
	return p.z / p.w;
}

void fragment() {
	float across = abs(UV.x * 2.0 - 1.0); // 0 in the middle, 1 at the bank
	// ripples stretched along the flow, sliding downstream
	vec2 flow = vec2(UV.x * 7.0, UV.y * 0.5 - TIME * flow_speed * 0.5);
	float n = value_noise(flow);
	float e = 0.12;
	vec2 slope = vec2(value_noise(flow + vec2(e, 0.0)) - n, value_noise(flow + vec2(0.0, e)) - n) / e;
	slope += vec2(value_noise(flow * 2.3 + 7.0) - 0.5, 0.0) * 0.6;
	vec3 view_normal = normalize((VIEW_MATRIX * vec4(-slope.x * 0.12, 1.0, -slope.y * 0.05, 0.0)).xyz);
	NORMAL = view_normal;

	float behind = scene_z(SCREEN_UV, INV_PROJECTION_MATRIX);
	float thickness = max(VERTEX.z - behind, 0.0);
	float depth_mix = clamp(thickness / depth_fade, 0.0, 1.0);
	// clear toward the banks, darker over the channel
	float middle = 1.0 - smoothstep(0.35, 1.0, across);
	vec4 color = mix(shallow_color, deep_color, sqrt(depth_mix) * (0.35 + 0.65 * middle));

	// foam: along the banks, in streaks, and where the water is thin
	float streak = value_noise(vec2(UV.x * 5.0, UV.y * 0.25 - TIME * flow_speed * 0.25));
	float bank_foam = smoothstep(0.72, 0.96, across) * (0.45 + 0.55 * streak);
	float shallow_foam = (1.0 - smoothstep(0.0, 0.35, thickness)) * 0.8;
	float foam = clamp(max(bank_foam, shallow_foam), 0.0, 1.0);

	ALBEDO = mix(color.rgb, foam_color.rgb, foam);
	ALPHA = clamp(mix(color.a, 1.0, foam) * (1.0 - smoothstep(0.88, 1.0, across) * 0.5), 0.0, 1.0);
	ROUGHNESS = mix(0.07, 0.6, foam);
	SPECULAR = 0.7;
	METALLIC = 0.0;
}
