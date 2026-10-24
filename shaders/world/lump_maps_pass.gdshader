shader_type canvas_item;
render_mode blend_disabled;
// The boulder's other material maps, derived from its baked colour (rgb) and height (alpha). Every relation was measured on the
// photograph's own maps (tools/bark): the normal map follows the height gradient (correlation 0.89 to 0.91, scale 20), roughness is a
// function of the colour's red channel (correlation 0.997), ambient occlusion follows the multi-scale cavity of the height (0.72).

uniform sampler2D baked : filter_linear, repeat_enable;
uniform int mode = 0; // 0 normal (OpenGL), 1 ambient occlusion, 2 roughness, 3 the packed ARM map (ao, roughness, 0)
uniform float texel = 0.0009765625;
uniform float normal_scale = 20.2;
const float RADII[5] = float[5](1.5, 3.0, 6.0, 12.0, 24.0);
const float W_CAV[5] = float[5](-5.7978, 1.3898, -0.3779, -0.1797, 0.1535);
const float W_NEG[5] = float[5](20.9312, -3.1205, 2.4958, 0.1829, 0.3182);
const float AO_BIAS = 0.9473;

float height_at(vec2 uv) {
	return texture(baked, uv).a;
}

float ring_mean(vec2 uv, float radius_px) {
	float sum = height_at(uv);
	for (int i = 0; i < 12; i++) {
		float a = 6.2831853 * (float(i) + 0.5 * float(i % 2)) / 12.0;
		float r = radius_px * (i % 2 == 0 ? 1.0 : 0.55);
		sum += height_at(uv + vec2(cos(a), sin(a)) * r * texel);
	}
	return sum / 13.0;
}

float occlusion(vec2 uv) {
	float h = height_at(uv);
	float ao = AO_BIAS;
	for (int i = 0; i < 5; i++) {
		float cavity = h - ring_mean(uv, RADII[i]);
		ao += W_CAV[i] * cavity + W_NEG[i] * min(cavity, 0.0);
	}
	return clamp(ao, 0.0, 1.0);
}

float roughness(vec2 uv) {
	float red = texture(baked, uv).r;
	return clamp(-0.266 * red * red - 0.438 * red + 1.039, 0.0, 1.0);
}

void fragment() {
	vec2 uv = UV;
	vec3 result = vec3(0.0);
	if (mode == 0) {
		float gx = (height_at(uv + vec2(texel, -texel)) + 2.0 * height_at(uv + vec2(texel, 0.0)) + height_at(uv + vec2(texel, texel))
				- height_at(uv + vec2(-texel, -texel)) - 2.0 * height_at(uv + vec2(-texel, 0.0)) - height_at(uv + vec2(-texel, texel))) / 8.0;
		float gy = (height_at(uv + vec2(-texel, texel)) + 2.0 * height_at(uv + vec2(0.0, texel)) + height_at(uv + vec2(texel, texel))
				- height_at(uv + vec2(-texel, -texel)) - 2.0 * height_at(uv + vec2(0.0, -texel)) - height_at(uv + vec2(texel, -texel))) / 8.0;
		vec3 n = normalize(vec3(-normal_scale * gx, normal_scale * gy, 1.0));
		result = n * 0.5 + 0.5;
	} else if (mode == 1) {
		result = vec3(occlusion(uv));
	} else if (mode == 2) {
		result = vec3(roughness(uv));
	} else {
		result = vec3(occlusion(uv), roughness(uv), 0.0);
	}
	COLOR = vec4(clamp(result, 0.0, 1.0), 1.0);
}
