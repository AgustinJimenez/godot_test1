shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled, specular_schlick_ggx;
// A river: clear water that shows the bed, ripples running along the current (the vertex colour
// holds the flow direction), pale streaks where it speeds up and foam at the banks.

uniform vec4 shallow_color : source_color = vec4(0.28, 0.62, 0.62, 0.5);
uniform vec4 deep_color : source_color = vec4(0.06, 0.28, 0.4, 0.92);
uniform vec4 foam_color : source_color = vec4(0.95, 0.98, 1.0, 1.0);
uniform float depth_fade = 1.6;
uniform sampler2D depth_texture : hint_depth_texture, repeat_disable, filter_nearest;

global uniform float realism;

varying vec3 world_pos;
varying vec2 flow;
varying float fall;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	flow = (COLOR.rg - 0.5) * 2.0;
	fall = COLOR.b;
	VERTEX.y += sin(dot(world_pos.xz, flow) * 0.9 - TIME * 2.6) * 0.03;
}

void fragment() {
	vec3 flat_normal = normalize(cross(dFdx(VERTEX), dFdy(VERTEX)));
	if (dot(flat_normal, VIEW) < 0.0) {
		flat_normal = -flat_normal;
	}
	vec2 ripple_slope = vec2(cos(dot(world_pos.xz, flow) * 1.7 - TIME * 3.2), 0.0) * 0.1;
	vec3 ripple_normal = normalize((VIEW_MATRIX * vec4(-ripple_slope.x * flow.x, 1.0, -ripple_slope.x * flow.y, 0.0)).xyz);
	NORMAL = normalize(mix(flat_normal, ripple_normal, realism));
	float depth = texture(depth_texture, SCREEN_UV).r;
	vec3 ndc = vec3(SCREEN_UV * 2.0 - 1.0, depth);
	vec4 scene = INV_PROJECTION_MATRIX * vec4(ndc, 1.0);
	scene.xyz /= scene.w;
	float thickness = max(VERTEX.z - scene.z, 0.0);
	float t = clamp(thickness / depth_fade, 0.0, 1.0);
	vec4 color = mix(shallow_color, deep_color, sqrt(t));
	// ripples travelling with the current
	float along = dot(world_pos.xz, flow);
	float across = dot(world_pos.xz, vec2(-flow.y, flow.x));
	float speed = 3.2 + fall * 9.0; // the current runs faster down a drop
	float ripple = sin(along * (1.7 + fall * 1.5) - TIME * speed + sin(across * 0.9) * 1.5);
	float streak = smoothstep(0.82 - fall * 0.5, 1.0, ripple);
	float foam = 1.0 - smoothstep(0.0, 0.35, thickness);
	ALBEDO = mix(color.rgb, foam_color.rgb, clamp(foam * 0.8 + streak * 0.35 + fall * 0.55, 0.0, 1.0));
	ALPHA = clamp(mix(color.a, 1.0, foam), 0.0, 1.0);
	ROUGHNESS = mix(0.1, 0.03, realism);
	SPECULAR = mix(0.6, 1.0, realism);
}
