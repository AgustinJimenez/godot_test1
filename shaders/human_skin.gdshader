shader_type spatial;
// Skin for the base humans (the same look as the plain material it replaces) with a darker scalp: under the hair the skin is
// the colour of the hair roots, so a gap between hairs shows a dark scalp, not pale skin. The scalp amount per vertex comes
// from HumanHair (mesh meta "hair_scalp_weight"), uploaded as a small texture: the vertex shader reads it by VERTEX_ID.
// Nothing is drawn over the head: this is only the skin's own colour.

uniform vec3 skin_color : source_color = vec3(0.6, 0.4, 0.32);
uniform vec3 scalp_color : source_color = vec3(0.15, 0.09, 0.06);   // the colour of the hair roots
uniform float scalp_amount : hint_range(0.0, 1.0) = 1.0;
uniform float roughness_value : hint_range(0.0, 1.0) = 0.55;
uniform float sss_strength : hint_range(0.0, 1.0) = 0.2;
uniform sampler2D scalp_tex : filter_nearest;
uniform int scalp_width = 1024;
uniform bool has_scalp = false;
uniform sampler2D skin_tex : source_color, filter_linear_mipmap, repeat_disable;   // an optional skin diffuse map (MakeHuman UV layout)
uniform bool has_skin_tex = false;
uniform sampler2D skin_spec : hint_default_white, filter_linear_mipmap, repeat_disable;   // an optional specular map (MakeHuman): bright = shinier skin (oily forehead, lips), dark = matte
uniform bool has_skin_spec = false;
uniform sampler2D skin_normal : hint_normal, filter_linear_mipmap, repeat_disable;       // an optional tangent normal map (pores, wrinkles)
uniform bool has_skin_normal = false;
uniform float normal_strength : hint_range(0.0, 2.0) = 1.0;
// Procedural skin detail (when there is no normal map): the low-poly body shows its triangles as faint diagonal bands in a plain colour (the forehead, the neck: Mach bands between
// the planes of a 13k-vertex mesh); fine pores in the normal and a slow blotchy tone break them up and make the skin read as skin. Worked out in UV space (the MakeHuman layout), so
// it does not slide when the body is posed. Both fade out with the distance (a pixel covering many pores would alias).
uniform float pore_strength : hint_range(0.0, 1.0) = 0.35;     // the depth of the pores in the normal
uniform float pore_scale = 2600.0;                              // pores per UV unit (the head is about a quarter of the UV square: ~1 mm pores)
uniform float tone_variation : hint_range(0.0, 0.3) = 0.06;     // slow blotchy variation of the skin colour (redness, shade)

varying float scalp;
varying vec3 local_pos;
uniform bool has_lips = false;
uniform vec3 lip_info = vec3(0.0, 0.0, 1.0);   // lip centre height, z in front of which the lips are, face scale (from HumanHair, mesh meta "hair_mouth")
uniform vec3 lip_color : source_color = vec3(0.62, 0.27, 0.25);

float hash21(vec2 p) {
	vec3 q = fract(vec3(p.xyx) * vec3(0.1031, 0.1030, 0.0973));
	q += dot(q, q.yzx + 33.33);
	return fract((q.x + q.y) * q.z);
}

float value_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash21(i), hash21(i + vec2(1.0, 0.0)), u.x), mix(hash21(i + vec2(0.0, 1.0)), hash21(i + vec2(1.0, 1.0)), u.x), u.y);
}

// two octaves of pores: small bumps and a few larger pits
float pore_height(vec2 p) {
	return value_noise(p) * 0.65 + value_noise(p * 2.3 + 17.0) * 0.35;
}

void vertex() {
	local_pos = VERTEX;
	scalp = 0.0;
	if (has_scalp) {
		scalp = texelFetch(scalp_tex, ivec2(VERTEX_ID % scalp_width, VERTEX_ID / scalp_width), 0).r;
	}
}

void fragment() {
	vec3 base = skin_color;
	if (has_skin_tex) {
		base = texture(skin_tex, UV).rgb;
	}
	// slow tone variation (blotchy redness and shade), faded out with the distance
	vec2 tone_p = UV * 140.0;
	float tone_fade = 1.0 - smoothstep(0.5, 2.0, length(fwidth(tone_p)));
	float tone = (value_noise(tone_p) * 0.6 + value_noise(tone_p * 2.7 + 5.0) * 0.4) - 0.5;
	base *= 1.0 + tone_variation * tone * 2.0 * tone_fade;
	base.r *= 1.0 + tone_variation * 0.8 * tone * tone_fade;   // (a little more red where it is darker: blood under the skin)
	if (has_lips && local_pos.z > lip_info.y) {
		// the lips: an ellipse around the mouth, a soft edge, redder and a little darker than the skin (the body has no lip colour of its own)
		vec2 q = vec2(abs(local_pos.x) / (0.034 * lip_info.z), (local_pos.y - lip_info.x) / ((local_pos.y > lip_info.x ? 0.0135 : 0.0105) * lip_info.z));
		float lip = 1.0 - smoothstep(0.7, 1.0, length(q));
		base = mix(base, lip_color * mix(0.8, 1.15, value_noise(UV * 900.0)), lip * 0.8);
	}
	ALBEDO = mix(base, scalp_color, clamp(scalp * scalp_amount, 0.0, 1.0));
	float scalp_here = clamp(scalp * scalp_amount, 0.0, 1.0);
	float rough = roughness_value;
	if (has_skin_spec) {
		rough = mix(0.85, 0.35, texture(skin_spec, UV).r);   // (MakeHuman spec maps are mostly mid-grey: 0.5 gives the old roughness of 0.6)
	}
	if (has_skin_normal) {
		NORMAL_MAP = texture(skin_normal, UV).rgb;
		NORMAL_MAP_DEPTH = normal_strength;
	} else if (pore_strength > 0.0) {
		vec2 p = UV * pore_scale;
		float footprint = length(fwidth(p));
		float fade = 1.0 - smoothstep(0.6, 1.8, footprint);   // (more than a pore per pixel: it would only shimmer)
		float e = 0.45;
		float h = pore_height(p);
		float hx = pore_height(p + vec2(e, 0.0));
		float hy = pore_height(p + vec2(0.0, e));
		vec3 bump = normalize(vec3(-(hx - h) * 1.6, -(hy - h) * 1.6, 1.0));
		NORMAL_MAP = mix(vec3(0.5, 0.5, 1.0), bump * 0.5 + 0.5, fade);
		NORMAL_MAP_DEPTH = pore_strength;
		rough = clamp(rough + (h - 0.5) * 0.12 * fade, 0.0, 1.0);   // (pores are a little rougher than the skin between them)
	}
	ROUGHNESS = mix(rough, 1.0, scalp_here);   // the scalp is matte: seen at a grazing angle through a gap in the hair, a glossy skin showed up as a white speck
	SPECULAR = mix(0.5, 0.0, scalp_here);
	SSS_STRENGTH = sss_strength * (1.0 - scalp_here);
}
