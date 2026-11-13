// Ground colours for the voxel planet (task 096). The mesh has no per-vertex colours, so the
// colour comes from what a vertex knows: its height above the sea level of the planet (its
// distance from the planet's centre, which is the world origin, minus the radius; the model matrix
// is in absolute world coordinates in the double precision engine, float precision there is 0.5 m
// at Earth size) and the slope (the normal against the radial direction). Crude on purpose: sand by the
// sea, grass, bare soil, rock on slopes, snow high up.
shader_type spatial;
render_mode cull_disabled; // (a crack between two LODs shows the back of the surface, ground-coloured, instead of the black inside of the planet)

uniform float planet_radius = 6371000.0; // the planet's radius (m), set by script
uniform float snow_line = 2200.0;
uniform sampler2D colour_map : source_color, filter_linear, repeat_enable; // the planet's colours by direction (script)
uniform bool use_map = false;
uniform sampler2D window_map : source_color, filter_linear, repeat_disable; // the colours round the walker, a finer map of a square of the planet (script)
uniform bool use_window = false;
uniform vec3 window_c = vec3(0.0, 1.0, 0.0); // the window's middle (a direction) and its axes
uniform vec3 window_e1 = vec3(1.0, 0.0, 0.0);
uniform vec3 window_e2 = vec3(0.0, 0.0, 1.0);
uniform float window_half = 0.0001; // half its side, as an angle (radians)
uniform int debug_mode = 0; // a tool: 1 the height in 100 m steps, 2 the slope, 3 the map's colour, 4 the light-free albedo
// (the planet's own space from the world's is the global planet_from_world: the terrain gives every block a copy of this material, made when the
// block is, so a uniform set later by script never reaches the blocks that are there already)

varying vec3 world_pos;
varying vec3 world_normal;
varying vec3 lab_pos; // the world's own position and normal (the game's flat world, near the player)
varying vec3 lab_normal;

// The near ground's scans (the planet ground shader's): placed by the lab's anchor, which holds
// still when the planet is turned under the player (planet_lab publishes these globals).
global uniform mat4 anchor_from_world;
global uniform vec3 anchor_wrap;
global uniform vec3 anchor_up;
uniform sampler2D cliff_c : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D cliff_n : filter_linear_mipmap_anisotropic, repeat_enable;
uniform float cliff_scale = 0.33; // tiles a metre
uniform bool detail_on = false; // set by the lab's helper (the globals above only exist there)
uniform float detail_strength : hint_range(0.0, 1.0) = 0.85;
uniform sampler2D scan_gravel_c : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D scan_gravel_n : filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D scan_red_c : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D scan_red_n : filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D scan_leaf_c : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D scan_leaf_n : filter_linear_mipmap_anisotropic, repeat_enable;
uniform float scan_scale = 0.7; // tiles a metre
uniform vec3 scan_leaf_mean = vec3(0.1943, 0.1288, 0.0655);
uniform vec3 scan_gravel_mean = vec3(0.1452, 0.1181, 0.0898);
uniform vec3 scan_red_mean = vec3(0.3041, 0.2007, 0.1305);

#include "res://shaders/world/planet_cloud_shade.gdshaderinc" // the clouds' shadow (the lab publishes its globals)
#include "res://shaders/world/planet_stones.gdshaderinc" // hash3, noise3, fbm3 (the tiles' ground shares them)
#include "res://shaders/world/planet_sand.gdshaderinc" // the sand's ripples and swell

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}

vec4 unrepeated(sampler2D map, vec2 uv) {
	vec4 first = texture(map, uv);
	vec4 second = texture(map, uv * vec2(0.71, 0.77) + vec2(0.37, 0.61));
	return mix(first, second, smoothstep(0.3, 0.7, vnoise(uv * 0.23 + 3.1)));
}

// One scan on the three planes (planet_ground.gdshader): the colour over the scan's own mean, its
// occlusion, the lean its relief gives the normal (planet axes) and its roughness.
void scan_triplanar(sampler2D scan_c, sampler2D scan_n, vec3 at, vec3 facing, float scale, vec3 mean, out vec3 ratio,
		out float ao, out vec3 tilt, out float rough) {
	vec3 w = pow(abs(facing), vec3(4.0));
	w /= w.x + w.y + w.z;
	vec2 uv_x = at.yz * scale;
	vec2 uv_y = at.xz * scale;
	vec2 uv_z = at.xy * scale;
	vec4 cx = unrepeated(scan_c, uv_x);
	vec4 cy = unrepeated(scan_c, uv_y);
	vec4 cz = unrepeated(scan_c, uv_z);
	vec4 nx = texture(scan_n, uv_x);
	vec4 ny = texture(scan_n, uv_y);
	vec4 nz = texture(scan_n, uv_z);
	ratio = clamp((cx.rgb * w.x + cy.rgb * w.y + cz.rgb * w.z) / mean, vec3(0.2), vec3(3.0));
	ao = cx.a * w.x + cy.a * w.y + cz.a * w.z;
	vec2 tx = nx.xy * 2.0 - 1.0;
	vec2 ty = ny.xy * 2.0 - 1.0;
	vec2 tz = nz.xy * 2.0 - 1.0;
	tilt = vec3(0.0, tx.x, tx.y) * w.x + vec3(ty.x, 0.0, ty.y) * w.y + vec3(tz.x, tz.y, 0.0) * w.z;
	rough = nx.b * w.x + ny.b * w.y + nz.b * w.z;
}

#include "res://shaders/world/planet_haze.gdshaderinc" // the haze by height (FOG)

void vertex() {
	vec4 abs_pos = MODEL_MATRIX * vec4(VERTEX, 1.0);
	world_pos = (planet_from_world * abs_pos).xyz;
	lab_pos = abs_pos.xyz;
	lab_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	world_normal = normalize((planet_from_world * MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	FOG = planet_haze(mat3(INV_VIEW_MATRIX) * VERTEX, cloud_sun_world);
	float height = length(world_pos) - planet_radius;
	vec2 xz = world_pos.xz;
	float slope = 1.0 - clamp(dot(normalize(world_normal), normalize(world_pos)), 0.0, 1.0); // 0 flat, 1 a wall
	float n = vnoise(xz * 0.015) * 0.6 + vnoise(xz * 0.11) * 0.3 + vnoise(xz * 0.9) * 0.1;
	vec3 sand = vec3(0.76, 0.69, 0.5);
	vec3 grass = mix(vec3(0.24, 0.38, 0.14), vec3(0.34, 0.45, 0.2), n);
	vec3 soil = mix(vec3(0.38, 0.28, 0.18), vec3(0.5, 0.4, 0.28), n);
	vec3 rock = mix(vec3(0.34, 0.32, 0.3), vec3(0.5, 0.47, 0.43), n);
	vec3 snow = vec3(0.92, 0.94, 0.97);
	vec3 col = mix(sand, grass, smoothstep(2.0, 12.0, height));
	col = mix(col, soil, smoothstep(0.45, 0.75, n) * smoothstep(12.0, 40.0, height) * 0.7);
	if (use_map) { // the planet's own colour of the place, with the shader's grain over it
		vec3 up_dir = normalize(world_pos);
		vec2 map_uv = vec2(atan(up_dir.z, up_dir.x) / TAU + 0.5, 0.5 - asin(clamp(up_dir.y, -1.0, 1.0)) / PI);
		col = texture(colour_map, map_uv).rgb * (0.82 + 0.36 * n) * 1.25; // (1.25: between the flat ground (1.7 matched it) and the sun-facing slopes, which clip to white above that)
		if (use_window && dot(up_dir, window_c) > 0.0) { // the finer map round the walker, fading into the coarse one at its edge
			vec2 q = vec2(dot(up_dir, window_e1), dot(up_dir, window_e2)) / window_half;
			float inside = 1.0 - smoothstep(0.75, 1.0, max(abs(q.x), abs(q.y)));
			if (inside > 0.0) {
				col = mix(col, texture(window_map, q * 0.5 + 0.5).rgb * (0.82 + 0.36 * n) * 1.25, inside);
			}
		}
	}
	// (with the planet's own colours the rock is only for cliffs: a grassy hillside of 35 degrees stays green)
	col = mix(col, rock, use_map ? smoothstep(0.42, 0.7, slope + (n - 0.5) * 0.15) : smoothstep(0.18, 0.4, slope + (n - 0.5) * 0.15));
	col = mix(col, snow, smoothstep(snow_line, snow_line + 300.0, height + n * 150.0) * (1.0 - smoothstep(0.3, 0.6, slope)));
	float rough = 0.92;
	float fade = (1.0 - smoothstep(10.0, 32.0, length(VERTEX))) * detail_strength;
	vec3 on_planet = vec3(0.0);
	vec3 facing = vec3(0.0, 1.0, 0.0);
	if (detail_on) {
		on_planet = (anchor_from_world * vec4(lab_pos, 1.0)).xyz + anchor_wrap;
		facing = normalize(mat3(anchor_from_world) * lab_normal);
	}
	// sand: golden, dry ground that is not steep (the tiles' rule from the paint): it has ripples, not the gravel's scan
	float sand_ground = smoothstep(0.0, 0.1, col.r - col.b) * (1.0 - smoothstep(0.0, 0.05, col.g - col.r + 0.02))
			* smoothstep(0.3, 0.55, 1.0 - slope) * (1.0 - smoothstep(0.0, 0.08, col.g - max(col.r, col.b)));
	float scan_fade = fade * (1.0 - 0.95 * sand_ground);
	if (detail_on && fade > 0.01) { // the soil's scan: green ground is forest earth, reddish is red soil, the rest gravel
		float w_leaf = smoothstep(0.0, 0.08, col.g - max(col.r, col.b));
		float w_red = smoothstep(0.03, 0.12, col.r - col.g) * (1.0 - w_leaf);
		float w_gravel = 1.0 - w_leaf - w_red;
		vec3 ratio = vec3(0.0);
		vec3 tilt = vec3(0.0);
		float ao = 0.0;
		float rough_sum = 0.0;
		vec3 r;
		vec3 t;
		float a;
		float ro;
		if (w_gravel > 0.02) {
			scan_triplanar(scan_gravel_c, scan_gravel_n, on_planet, facing, scan_scale, scan_gravel_mean, r, a, t, ro);
			ratio += r * w_gravel; tilt += t * w_gravel; ao += a * w_gravel; rough_sum += ro * w_gravel;
		}
		if (w_red > 0.02) {
			scan_triplanar(scan_red_c, scan_red_n, on_planet, facing, scan_scale, scan_red_mean, r, a, t, ro);
			ratio += r * w_red; tilt += t * w_red; ao += a * w_red; rough_sum += ro * w_red;
		}
		if (w_leaf > 0.02) {
			scan_triplanar(scan_leaf_c, scan_leaf_n, on_planet, facing, scan_scale, scan_leaf_mean, r, a, t, ro);
			ratio += r * w_leaf; tilt += t * w_leaf; ao += a * w_leaf; rough_sum += ro * w_leaf;
		}
		col *= mix(vec3(1.0), ratio * mix(0.55, 1.0, ao), scan_fade);
		col *= mix(1.0, mix(0.88, 1.12, fbm3(on_planet * 0.171875, 176.0)), fade); // (soft patches of lighter and darker ground, 6 m across)
		vec3 tilt_world = transpose(mat3(anchor_from_world)) * tilt;
		NORMAL = normalize(NORMAL + (VIEW_MATRIX * vec4(tilt_world, 0.0)).xyz * 0.9 * scan_fade);
		rough = mix(rough, clamp(rough_sum, 0.3, 1.0), scan_fade);
	}
	if (detail_on && sand_ground > 0.01) { // the wind's ripples (planet_sand) on the dune sand
		float ripple_fade = sand_ground * sand_ripples * (1.0 - smoothstep(12.0, 45.0, length(VERTEX)));
		float sand_h;
		vec3 sand_tilt = transpose(mat3(anchor_from_world)) * sand_ripple_tilt(on_planet, normalize(anchor_up), sand_h);
		NORMAL = normalize(NORMAL + (VIEW_MATRIX * vec4(sand_tilt, 0.0)).xyz * ripple_fade);
		col *= mix(1.0, mix(0.93, 1.06, sand_h), ripple_fade);
		rough = mix(rough, 0.7, ripple_fade);
	}
	{
		// the steep faces are cliff: slabs with their strata level (planet_ground.gdshader: the texture drawn on two vertical planes
		// of the place's own frame, u along the face, v up), its colour kept as the detail over the rock's own
		float cliff_w = smoothstep(0.45, 0.7, slope) * (1.0 - smoothstep(60.0, 140.0, length(VERTEX))) * detail_strength;
		if (detail_on && cliff_w > 0.01) {
			vec3 up_local = normalize(anchor_up);
			vec3 side_ref = abs(up_local.y) < 0.9 ? vec3(0.0, 1.0, 0.0) : vec3(1.0, 0.0, 0.0);
			vec3 right_local = normalize(cross(side_ref, up_local));
			vec3 forward_local = cross(up_local, right_local);
			vec3 spot = vec3(dot(on_planet, right_local), dot(on_planet, up_local), dot(on_planet, forward_local));
			vec2 across = vec2(abs(dot(facing, forward_local)), abs(dot(facing, right_local)));
			vec2 plane_weight = pow(across, vec2(4.0));
			plane_weight /= max(plane_weight.x + plane_weight.y, 0.0001);
			vec2 uv_a = vec2(spot.x, spot.y) * cliff_scale;
			vec2 uv_b = vec2(spot.z, spot.y) * cliff_scale;
			vec4 col_a = unrepeated(cliff_c, uv_a);
			vec4 col_b = unrepeated(cliff_c, uv_b);
			vec4 nor_a = unrepeated(cliff_n, uv_a);
			vec4 nor_b = unrepeated(cliff_n, uv_b);
			vec3 cliff_colour = col_a.rgb * plane_weight.x + col_b.rgb * plane_weight.y;
			float cliff_ao = col_a.a * plane_weight.x + col_b.a * plane_weight.y;
			vec2 tilt_a = nor_a.xy * 2.0 - 1.0;
			vec2 tilt_b = nor_b.xy * 2.0 - 1.0;
			vec3 tilt_planet = (right_local * tilt_a.x + up_local * tilt_a.y) * plane_weight.x
					+ (forward_local * tilt_b.x + up_local * tilt_b.y) * plane_weight.y;
			vec3 cliff_ratio = clamp(cliff_colour / vec3(0.5716, 0.1905, 0.0373), vec3(0.4), vec3(1.5));
			cliff_ratio = mix(vec3(dot(cliff_ratio, vec3(0.33))), cliff_ratio, 0.4);
			col *= mix(vec3(1.0), cliff_ratio * mix(0.5, 1.0, cliff_ao), cliff_w);
			NORMAL = normalize(NORMAL + (VIEW_MATRIX * vec4(transpose(mat3(anchor_from_world)) * tilt_planet * 1.1, 0.0)).xyz * cliff_w);
		}
	}
	if (detail_on) { // (the lab: the clouds are there)
		col *= cloud_shade_keep(haze_eye + mat3(INV_VIEW_MATRIX) * VERTEX);
	}
	ALBEDO = col;
	if (debug_mode > 0) { // tools: emit flags, unlit (the albedo is lit and tone mapped, hard to read)
		ALBEDO = vec3(0.0);
		if (debug_mode == 1) { // R: above the snow line, G: slope past the rock threshold, B: above the sea
			EMISSION = vec3(height + n * 150.0 > snow_line ? 1.0 : 0.0, slope > 0.3 ? 1.0 : 0.0, height > 0.0 ? 1.0 : 0.0);
		} else if (debug_mode == 2) { // R: height over 400 m, G: height over 800 m, B: height over 1600 m
			EMISSION = vec3(height > 400.0 ? 1.0 : 0.0, height > 800.0 ? 1.0 : 0.0, height > 1600.0 ? 1.0 : 0.0);
		} else if (debug_mode == 3) { // the map's colour alone
			vec3 d = normalize(world_pos);
			EMISSION = texture(colour_map, vec2(atan(d.z, d.x) / TAU + 0.5, 0.5 - asin(clamp(d.y, -1.0, 1.0)) / PI)).rgb * 2.0;
		} else { // the colour before the lighting
			EMISSION = col;
		}
	}
	ROUGHNESS = rough;
}
