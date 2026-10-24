shader_type canvas_item;
// One square of the comparison: the colour as it is (mode 0), or a height shown lit from the upper left
// (mode 1: the height is the texture's alpha, mode 2: its red channel), stretched by height_range.

uniform sampler2D tex : filter_linear;
uniform int mode = 0;
uniform vec2 height_range = vec2(0.0, 1.0);
uniform float strength = 14.0;

float height_at(vec2 uv) {
	vec4 t = texture(tex, uv);
	float h = mode == 1 ? t.a : t.r;
	return (h - height_range.x) / max(height_range.y - height_range.x, 0.0001);
}

void fragment() {
	if (mode == 0) {
		COLOR = vec4(texture(tex, UV).rgb, 1.0);
	} else {
		vec2 px = 1.0 / vec2(textureSize(tex, 0));
		float dx = (height_at(UV + vec2(px.x, 0.0)) - height_at(UV - vec2(px.x, 0.0))) * 0.5;
		float dy = (height_at(UV + vec2(0.0, px.y)) - height_at(UV - vec2(0.0, px.y))) * 0.5;
		float shade = clamp(0.5 - strength * 2.0 * (dx + dy), 0.0, 1.0);
		COLOR = vec4(vec3(shade), 1.0);
	}
}
