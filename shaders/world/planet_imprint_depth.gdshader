shader_type spatial;
render_mode unshaded, cull_disabled, depth_test_disabled, depth_draw_never, shadows_disabled;
// PlanetImprinter: a flat quad over the whole view of the small camera that looks UP at the underside of whatever touches the sand. It
// writes how far from the camera (0 .. slab) the first surface is, as a grey level: 1 where there is nothing within the slab.

uniform sampler2D depth_tex : hint_depth_texture, filter_nearest;
uniform float slab = 0.1;

vec3 to_linear(vec3 srgb) {
	return mix(pow((srgb + 0.055) / 1.055, vec3(2.4)), srgb / 12.92, lessThan(srgb, vec3(0.04045)));
}

void vertex() {
	POSITION = vec4(VERTEX.xy, 1.0, 1.0);
}

void fragment() {
	float depth = textureLod(depth_tex, SCREEN_UV, 0.0).x;
	vec4 view = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, depth, 1.0);
	view.xyz /= view.w;
	float level = clamp(-view.z / slab, 0.0, 1.0);
	ALBEDO = to_linear(vec3(level)); // (the output is encoded as sRGB again: the byte read back is the level)
	ALPHA = 1.0;
}
