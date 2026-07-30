shader_type spatial;
render_mode diffuse_lambert;

// Drop-ceiling tile pattern: either a real tileable texture (use_texture =
// true) or a procedural grid-line fallback, using screen-space derivatives
// (fwidth) so line width stays crisp at any distance instead of aliasing
// like a plain UV threshold would.
//
// Patterns off world-space XZ position rather than mesh UV (use_world_uv =
// true) so tile_size/texture_scale mean real meters consistently: CSGBox3D
// normalizes each face's UV to 0-1 regardless of the face's actual size, so
// a non-square ceiling (the side room's 6x8m one, say) would stretch the
// tiles into rectangles if driven by UV directly.

uniform vec3 tile_color : source_color = vec3(0.78, 0.74, 0.58);
uniform vec3 grid_line_color : source_color = vec3(0.5, 0.47, 0.36);
uniform float tile_size = 0.6;
uniform bool use_world_uv = true;
uniform bool use_texture = false;
uniform sampler2D pattern_texture : source_color, filter_linear_mipmap, repeat_enable;
uniform float texture_scale = 2.4;
uniform float roughness_value : hint_range(0.0, 1.0) = 0.9;

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 pattern_uv = use_world_uv ? world_pos.xz : UV;

	if (use_texture) {
		ALBEDO = texture(pattern_texture, pattern_uv / texture_scale).rgb;
	} else {
		vec2 uv = pattern_uv / tile_size;
		vec2 grid = abs(fract(uv - 0.5) - 0.5) / fwidth(uv);
		float line = 1.0 - clamp(min(grid.x, grid.y), 0.0, 1.0);
		ALBEDO = mix(tile_color, grid_line_color, line);
	}
	ROUGHNESS = roughness_value;
}
