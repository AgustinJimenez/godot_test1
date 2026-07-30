shader_type spatial;
render_mode diffuse_lambert;

// Wallpaper pattern: either a real seamless texture (use_texture = true) or
// a procedural fallback of low-contrast horizontal rows of rightward
// chevrons with a dashed separator row between each. Both were modeled
// after cropping and zooming into an actual Backrooms reference asset's
// wall texture (see docs/tooling_research.md's "VHS/camcorder liminal-horror
// look" entry): close up, the wallpaper isn't a bold diamond lattice but a
// barely-visible ">>>" weave with a dashed tick-mark row between each
// chevron row. Either way, a red wainscoting stripe, white baseboard, and
// vertical panel seams are drawn on top.
//
// Flat walls (use_world_uv = true) pattern off world-space position rather
// than mesh UV: CSGBox3D normalizes each face's UV to 0-1 regardless of the
// face's actual size, so a 36m x 2.4m wall face would squash the pattern
// into flat horizontal stripes (15x too wide) if driven by UV directly.
// World position makes tile_scale/texture_scale consistent on any box size.
// Curved surfaces (pillars, use_world_uv = false) keep the original
// UV-driven path instead, since CSGCylinder3D's circumferential UV already
// wraps proportionally to the real surface length.
//
// The trim bands always key off world Y so they line up across every wall
// regardless of that wall's UV scale, as long as the level's floor sits at
// world Y 0 (true for every room in backrooms_level0.tscn).

uniform vec3 base_color : source_color = vec3(0.72, 0.63, 0.28);
uniform vec3 pattern_color : source_color = vec3(0.66, 0.57, 0.24);
uniform float tile_scale = 10.0;
uniform float chevron_flatness = 2.4;
uniform float dash_count = 5.0;
uniform float dash_duty = 0.5;
uniform bool use_world_uv = true;
uniform bool use_texture = false;
uniform sampler2D pattern_texture : source_color, filter_linear_mipmap, repeat_enable;
uniform float texture_scale = 1.0;
uniform vec3 texture_tint = vec3(1.0, 1.0, 1.0);
uniform vec3 seam_color : source_color = vec3(0.05, 0.04, 0.03);
uniform float seam_spacing = 1.4;
uniform float seam_width = 0.012;
uniform float roughness_value : hint_range(0.0, 1.0) = 0.85;
uniform vec3 baseboard_color : source_color = vec3(0.92, 0.9, 0.85);
uniform vec3 wainscoting_color : source_color = vec3(0.5, 0.11, 0.07);
uniform float baseboard_height = 0.08;
uniform float wainscoting_height = 0.16;

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 pattern_uv = use_world_uv ? vec2(world_pos.x + world_pos.z, world_pos.y) : UV;

	vec3 color;
	if (use_texture) {
		color = texture(pattern_texture, pattern_uv / texture_scale).rgb * texture_tint;
	} else {
		vec2 uv = pattern_uv * tile_scale;
		uv.y *= chevron_flatness;
		vec2 grid = fract(uv) - 0.5;
		float arm_offset = (0.5 - grid.x) * 0.5;
		float chevron_dist = abs(abs(grid.y) - arm_offset);
		float chevron = smoothstep(0.1, 0.04, chevron_dist);
		color = mix(base_color, pattern_color, chevron);

		// Thin dashed tick-mark row along the boundary between chevron rows.
		float row_edge_dist = 0.5 - abs(grid.y);
		float dash_band = smoothstep(0.08, 0.0, row_edge_dist);
		float dash_x = fract(uv.x * dash_count);
		float dash_mask = step(dash_x, dash_duty);
		float dash_line = dash_band * dash_mask;
		color = mix(color, pattern_color, dash_line);
	}

	if (use_world_uv) {
		float seam_coord = pattern_uv.x / seam_spacing;
		float dist_to_seam = abs(fract(seam_coord + 0.5) - 0.5);
		float seam = smoothstep(seam_width, 0.0, dist_to_seam);
		color = mix(color, seam_color, seam);
	}

	float floor_height = world_pos.y;
	float baseboard = smoothstep(baseboard_height + 0.01, baseboard_height - 0.01, floor_height);
	float wainscoting = smoothstep(baseboard_height - 0.01, baseboard_height + 0.01, floor_height)
			* smoothstep(wainscoting_height + 0.01, wainscoting_height - 0.01, floor_height);
	color = mix(color, wainscoting_color, wainscoting);
	color = mix(color, baseboard_color, baseboard);

	ALBEDO = color;
	ROUGHNESS = roughness_value;
}
