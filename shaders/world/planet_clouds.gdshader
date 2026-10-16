shader_type spatial;
render_mode blend_mix, unshaded, cull_back, depth_draw_never;
// The clouds seen from space: a thin shell round the planet that reads the cloud cover picture (an
// equirectangular map, the planet's own frame) at each point's own direction, and is lit by the sun:
// white on the day side, dark on the night side, orange at the terminator. It fades out as the viewer
// comes down to the ground (the clouds of the sky are the flat world's own).

uniform sampler2D cover_map : filter_linear, repeat_enable;
uniform vec3 sun_toward = vec3(0.0, 1.0, 0.0); // world space
uniform float fade = 1.0; // 0 near the ground .. 1 from space

varying vec3 object_direction;
varying vec3 world_normal;

void vertex() {
	object_direction = normalize(VERTEX);
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	float lon = atan(object_direction.z, object_direction.x);
	float lat = asin(clamp(object_direction.y, -1.0, 1.0));
	vec2 uv = vec2(lon / 6.2831853 + 0.5, 0.5 - lat / 3.1415927);
	float cover = texture(cover_map, uv).r;
	float day = dot(world_normal, normalize(sun_toward));
	float light = smoothstep(-0.15, 0.35, day);
	vec3 lit = mix(vec3(0.05, 0.06, 0.11), vec3(1.0), light);
	lit = mix(lit, vec3(1.0, 0.62, 0.38), (1.0 - smoothstep(0.0, 0.25, abs(day))) * 0.5 * light);
	ALBEDO = lit;
	ALPHA = cover * 0.95 * fade;
}
