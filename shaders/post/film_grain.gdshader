shader_type canvas_item;
// Film grain over the picture (graphics setting "Film grain"): a light, moving noise, drawn under the interface.

uniform float strength : hint_range(0.0, 0.2) = 0.05;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

void fragment() {
	float frame_step = floor(TIME * 24.0);
	float grain = hash(floor(FRAGCOORD.xy) + frame_step * vec2(37.0, 17.0));
	COLOR = vec4(vec3(grain), strength);
}
