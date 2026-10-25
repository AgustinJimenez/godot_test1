shader_type canvas_item;
render_mode blend_disabled; // the height is in alpha: kept as it is
// Last pass of a bake: the colour is moved to the photograph's statistics (tools/bark/colour_match.py measures them):
// the mean per channel, how strongly the coarse patches vary (a box of about 3 cm, the mip level `lod`) and the fine detail.

uniform sampler2D src : filter_linear_mipmap, repeat_enable;
uniform float lod = 5.0;
uniform vec3 mean_value = vec3(0.5); // the mean of the bake itself
uniform vec3 mean_gain = vec3(1.0); // photograph's mean / the bake's, per channel
uniform float low_gain = 1.0;
uniform float detail_gain = 1.0;

void fragment() {
	vec4 c = texture(src, UV);
	vec3 b = textureLod(src, UV, lod).rgb;
	vec3 o = mean_value * mean_gain + (b - mean_value) * low_gain + (c.rgb - b) * detail_gain;
	COLOR = vec4(clamp(o, 0.0, 1.0), c.a);
}
