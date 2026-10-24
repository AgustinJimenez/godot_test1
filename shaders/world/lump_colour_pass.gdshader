shader_type canvas_item;
render_mode blend_disabled;
// Second pass of the boulder bake: the colour detail the coarse tone map lacks, derived from the height the first pass made
// (rgb: colour, alpha: height). Cavities are darker and convex tops lighter, at three scales, the way weathering stains settle.
// This is measured on the photograph: its luminance detail correlates 0.35 to 0.37 with the cavity of its own height.

uniform sampler2D first_pass : filter_linear, repeat_enable;
uniform float texel = 0.0009765625; // 1 / size
uniform vec3 gain = vec3(1.2, 1.0, 0.8); // how much each scale (small, medium, large) darkens or lightens the colour
const float RADII_PX[3] = float[3](2.5, 6.0, 12.0);
uniform float strength = 1.0;
uniform float up_scale = 1.0; // how much a convex part brightens, against how much a cavity darkens (the photograph's pits are darker than they are bright)
uniform float small_scale = 1.0; // multiplies the smallest scale's gain (its 2.5 px blobs are what makes the 1.4 to 2.8 cm band too strong)
uniform float clip_level = 1.0; // the cavity (normalised height) beyond which its effect on the colour saturates
uniform float chroma = 0.0; // 0: the cavity changes brightness only; 1: it also pulls the colour toward brown

float ring_mean(vec2 uv, float radius_px) {
	float sum = texture(first_pass, uv).a;
	for (int i = 0; i < 12; i++) {
		float a = 6.2831853 * (float(i) + 0.5 * float(i % 2)) / 12.0;
		float r = radius_px * (i % 2 == 0 ? 1.0 : 0.55);
		sum += texture(first_pass, fract(uv + vec2(cos(a), sin(a)) * r * texel)).a; // (fract: the tile wraps)
	}
	return sum / 13.0;
}

void fragment() {
	vec4 base = texture(first_pass, UV);
	float h = base.a;
	float cavity = 0.0;
	for (int s = 0; s < 3; s++) {
		float c = h - ring_mean(UV, RADII_PX[s]);
		c = c > 0.0 ? c * up_scale : c; // (convex parts brighten less than cavities darken)
		cavity += gain[s] * (s == 0 ? small_scale : 1.0) * (clip_level * tanh(c / clip_level)); // (soft limit: a few pits must not become spikes)
	}
	float k = clamp(1.0 + strength * cavity * 4.0, 0.55, 1.5);
	vec3 colour = base.rgb * k;
	colour = mix(colour, colour * vec3(1.0, 0.94, 0.86), chroma * clamp(-cavity * 6.0, 0.0, 1.0));
	COLOR = vec4(clamp(colour, 0.0, 1.0), h);
}
