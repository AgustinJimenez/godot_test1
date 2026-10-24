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
const float W_CAV[5] = float[5](0.8282, -3.0277, 0.2367, 0.0662, 0.1667);
const float W_NEG[5] = float[5](-2.9735, 7.9815, -1.5221, -0.5613, 0.4294);
const float W_EDGE[3] = float[3](0.552, 1.4408, -0.8888); // the edge layer value, its negative part, its positive part
const float W_LOBE[6] = float[6](0.0117, -0.0668, -0.0624, -0.0043, -0.0117, 0.0053); // inside, outside at 2, 5, 12 px
const float AO_BIAS = 1.0013;
const float AO_MEAN = 0.9291;
const float AO_GAIN = 1.87; // the fit shrinks the spread (0.019 against the photograph's 0.035): put it back
uniform sampler2D edge_tex : filter_nearest; // the edge layer (LumpBaker._edge_texture)
uniform sampler2D crack_tex : filter_nearest; // the thin cracks (LumpBaker._crack_texture)
uniform float w_crack = 0.17; // the occlusion a crack adds (the photograph's cracks: -0.048 against their surroundings)
uniform sampler2D lobe_tex : filter_nearest; // the traced lobes (row: header, box, 48 outline points in tile units)
uniform int n_lobes = 0;
uniform float tile_px = 1024.0;

float height_at(vec2 uv) {
	return texture(baked, fract(uv)).a; // (the tile wraps)
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

// signed distance (px) from a point (px) to the outline of lobe `row`, negative inside
float lobe_distance(vec2 pos, int row) {
	float best = 1e9;
	bool inside = false;
	vec2 a = texelFetch(lobe_tex, ivec2(2 + 47, row), 0).xy * tile_px;
	for (int k = 0; k < 48; k++) {
		vec2 b = texelFetch(lobe_tex, ivec2(2 + k, row), 0).xy * tile_px;
		vec2 e = b - a;
		vec2 w = pos - a;
		float t = clamp(dot(w, e) / max(dot(e, e), 1e-6), 0.0, 1.0);
		best = min(best, length(w - e * t));
		if ((a.y > pos.y) != (b.y > pos.y) && pos.x < (b.x - a.x) * (pos.y - a.y) / (b.y - a.y) + a.x) {
			inside = !inside;
		}
		a = b;
	}
	return inside ? -best : best;
}

float occlusion(vec2 uv) {
	float h = height_at(uv);
	float ao = AO_BIAS;
	for (int i = 0; i < 5; i++) {
		float cavity = h - ring_mean(uv, RADII[i]);
		ao += W_CAV[i] * cavity + W_NEG[i] * min(cavity, 0.0);
	}
	float edge = texelFetch(edge_tex, ivec2(clamp(floor(uv * tile_px), vec2(0.0), vec2(tile_px - 1.0))), 0).r;
	ao += W_EDGE[0] * edge + W_EDGE[1] * min(edge, 0.0) + W_EDGE[2] * max(edge, 0.0);
	float sd = 1e9;
	for (int i = 0; i < n_lobes; i++) {
		float d = lobe_distance(uv * tile_px, i);
		if (abs(d) < abs(sd)) {
			sd = d;
		}
	}
	if (n_lobes > 0) {
		float inside = max(-sd, 0.0);
		float outside = max(sd, 0.0);
		ao += W_LOBE[0] * exp(-pow(inside / 2.0, 2.0)) + W_LOBE[1] * exp(-pow(outside / 2.0, 2.0));
		ao += W_LOBE[2] * exp(-pow(inside / 5.0, 2.0)) + W_LOBE[3] * exp(-pow(outside / 5.0, 2.0));
		ao += W_LOBE[4] * exp(-pow(inside / 12.0, 2.0)) + W_LOBE[5] * exp(-pow(outside / 12.0, 2.0));
	}
	float crack = texelFetch(crack_tex, ivec2(clamp(floor(uv * tile_px), vec2(0.0), vec2(tile_px - 1.0))), 0).r;
	return clamp(AO_MEAN + AO_GAIN * (ao - AO_MEAN) - w_crack * crack, 0.0, 1.0);
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
