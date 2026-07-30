shader_type canvas_item;

// Full-screen camcorder/liminal-horror look: barrel lens distortion,
// chromatic aberration, soft blur, warm desaturated grade, vignette, film
// grain, and scanlines.
// Apply to a full-rect ColorRect on a CanvasLayer above the 3D viewport.

uniform sampler2D screen_texture : hint_screen_texture, filter_linear, repeat_disable;

uniform float barrel_strength : hint_range(0.0, 1.0) = 0.35;
uniform float aberration_strength : hint_range(0.0, 0.05) = 0.006;
uniform float blur_radius : hint_range(0.0, 3.0) = 1.2;
uniform float grain_strength : hint_range(0.0, 0.5) = 0.08;
uniform float vignette_strength : hint_range(0.0, 2.0) = 1.15;
uniform float vignette_softness : hint_range(0.1, 1.5) = 0.5;
uniform vec3 warm_tint = vec3(1.08, 0.97, 0.87);
uniform float desaturation : hint_range(0.0, 1.0) = 0.35;
uniform float exposure : hint_range(0.5, 2.0) = 1.05;
uniform float scanline_strength : hint_range(0.0, 1.0) = 0.12;
uniform float scanline_frequency : hint_range(100.0, 2000.0) = 700.0;

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

vec2 barrel_distort(vec2 uv, float strength) {
	vec2 centered = uv * 2.0 - 1.0;
	float r2 = dot(centered, centered);
	centered *= 1.0 + strength * r2;
	return centered * 0.5 + 0.5;
}

// Soft box blur, sampled per-channel with the chromatic-aberration offset
// baked in so blur and aberration share one set of texture reads.
vec3 sample_soft_rgb(vec2 uv, vec2 aberration_offset, float radius) {
	vec2 texel = (1.0 / vec2(textureSize(screen_texture, 0))) * radius;
	vec2 taps[5] = vec2[](
			vec2(0.0, 0.0), vec2(1.0, 0.0), vec2(-1.0, 0.0),
			vec2(0.0, 1.0), vec2(0.0, -1.0));
	vec3 accum = vec3(0.0);
	float total = 0.0;
	for (int i = 0; i < 5; i++) {
		float w = (i == 0) ? 2.0 : 1.0;
		vec2 o = taps[i] * texel;
		accum.r += texture(screen_texture, clamp(uv + o + aberration_offset, 0.0, 1.0)).r * w;
		accum.g += texture(screen_texture, clamp(uv + o, 0.0, 1.0)).g * w;
		accum.b += texture(screen_texture, clamp(uv + o - aberration_offset, 0.0, 1.0)).b * w;
		total += w;
	}
	return accum / total;
}

void fragment() {
	vec2 uv = barrel_distort(SCREEN_UV, barrel_strength);
	float in_bounds = step(0.0, uv.x) * step(uv.x, 1.0)
			* step(0.0, uv.y) * step(uv.y, 1.0);
	vec2 sample_uv = clamp(uv, 0.0, 1.0);

	vec2 from_center = uv - 0.5;
	vec2 aberration_offset = from_center * aberration_strength;

	vec3 color = sample_soft_rgb(sample_uv, aberration_offset, blur_radius);

	color *= warm_tint * exposure;
	float luma = dot(color, vec3(0.299, 0.587, 0.114));
	color = mix(color, vec3(luma), desaturation);

	float vignette = 1.0 - smoothstep(
			vignette_softness, vignette_softness + 0.6,
			length(from_center) * vignette_strength);
	color *= vignette;

	float scanline = sin(FRAGCOORD.y * scanline_frequency) * 0.5 + 0.5;
	color *= 1.0 - scanline_strength * scanline;

	float grain = (hash12(FRAGCOORD.xy + vec2(TIME * 113.0, TIME * 71.0)) - 0.5)
			* 2.0 * grain_strength;
	color += grain;

	color *= in_bounds;

	COLOR = vec4(clamp(color, 0.0, 1.0), 1.0);
}
