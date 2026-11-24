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

varying float scalp;

void vertex() {
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
	ALBEDO = mix(base, scalp_color, clamp(scalp * scalp_amount, 0.0, 1.0));
	float scalp_here = clamp(scalp * scalp_amount, 0.0, 1.0);
	float rough = roughness_value;
	if (has_skin_spec) {
		rough = mix(0.85, 0.35, texture(skin_spec, UV).r);   // (MakeHuman spec maps are mostly mid-grey: 0.5 gives the old roughness of 0.6)
	}
	if (has_skin_normal) {
		NORMAL_MAP = texture(skin_normal, UV).rgb;
		NORMAL_MAP_DEPTH = normal_strength;
	}
	ROUGHNESS = mix(rough, 1.0, scalp_here);   // the scalp is matte: seen at a grazing angle through a gap in the hair, a glossy skin showed up as a white speck
	SPECULAR = mix(0.5, 0.0, scalp_here);
	SSS_STRENGTH = sss_strength * (1.0 - scalp_here);
}
