shader_type spatial;
render_mode unshaded, wireframe, blend_mix, depth_draw_never, cull_disabled;

uniform vec4 wire_color : source_color = vec4(0.0, 1.0, 0.95, 0.9);


void fragment() {
	ALBEDO = wire_color.rgb;
	ALPHA = wire_color.a;
}
