shader_type spatial;
render_mode cull_disabled, blend_mix;
// Eyebrows and eyelashes for the base humans (assets/models/humans/*_brows.glb and *_lashes.glb): thin tapered hair strips and,
// for the brows, a faint base layer. The mesh's vertex colour (tools/blender/make_face_hair.py) carries per-hair data:
//   red   = random brightness of this hair,
//   green = random 0..1; a brow hair is drawn when green <= brow_density,
//   blue  = 1 on the faint base layer under the brow hairs.
// UV: x across a strip, y from its root (0) to its tip (1); on the base layer x runs along the brow and y across it.

uniform bool is_lash = false;
uniform vec3 hair_color : source_color = vec3(0.16, 0.1, 0.06);
uniform float lash_darken : hint_range(0.0, 1.0) = 0.55;   // lashes are drawn this much darker than the brows
uniform float brow_density : hint_range(0.2, 1.0) = 0.8;    // share of the brow hairs that are drawn

void fragment() {
	vec3 color = hair_color;
	float alpha;
	if (COLOR.b > 0.5) {
		// Faint base layer: soft edges, so the brow reads as one shape from a distance.
		float edge = smoothstep(0.0, 0.35, UV.y) * smoothstep(0.0, 0.35, 1.0 - UV.y);
		float ends = smoothstep(0.0, 0.1, UV.x) * (1.0 - smoothstep(0.75, 1.0, UV.x));
		alpha = 0.65 * edge * ends * brow_density;
		color *= 0.9;
	} else {
		// One tapered hair: wide at the root, thin at the tip.
		float half_width = 0.5 * (1.0 - 0.8 * UV.y);
		float across = abs(UV.x - 0.5);
		alpha = 1.0 - smoothstep(half_width * 0.55, half_width, across);
		alpha *= 1.0 - smoothstep(0.88, 1.0, UV.y);
		alpha *= smoothstep(0.0, 0.06, UV.y);
		color *= 0.65 + 0.7 * COLOR.r;
		if (is_lash) {
			color *= (1.0 - lash_darken);
		} else {
			alpha *= step(COLOR.g, brow_density);
		}
	}
	ALBEDO = color;
	ALPHA = alpha;
	ROUGHNESS = 0.55;
	SPECULAR = 0.3;
}
