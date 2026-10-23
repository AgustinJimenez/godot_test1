shader_type canvas_item;
render_mode blend_disabled;
// From a baked procedural tile (colour in rgb, height in alpha) the two maps the ground shader reads for a scan:
// mode 0: colour in rgb, ambient occlusion (from the height: low parts are dark) in alpha;
// mode 1: the normal (OpenGL, y up) in rg, the roughness in b. The tile repeats, so the neighbours wrap round.

uniform sampler2D tile : filter_linear, repeat_enable;
uniform int mode = 0;
uniform float normal_strength = 6.0;
uniform float roughness = 0.92;
uniform float ao_depth = 0.55;

void fragment() {
	vec4 t = texture(tile, UV);
	if (mode == 0) {
		float ao = mix(1.0 - ao_depth, 1.0, smoothstep(0.1, 0.7, t.a));
		COLOR = vec4(t.rgb, ao);
	} else {
		vec2 px = 1.0 / vec2(textureSize(tile, 0));
		float dx = texture(tile, UV + vec2(px.x, 0.0)).a - texture(tile, UV - vec2(px.x, 0.0)).a;
		float dy = texture(tile, UV + vec2(0.0, px.y)).a - texture(tile, UV - vec2(0.0, px.y)).a;
		vec3 n = normalize(vec3(-dx * normal_strength, dy * normal_strength, 1.0));
		COLOR = vec4(n.xy * 0.5 + 0.5, roughness, 1.0);
	}
}
