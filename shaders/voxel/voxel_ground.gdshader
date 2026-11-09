// Ground colours for the voxel planet (task 096). The mesh has no per-vertex colours, so the
// colour comes from what a vertex knows: its height above the sea level of the planet (its
// distance from the planet's centre, which is the world origin, minus the radius; the model matrix
// is in absolute world coordinates in the double precision engine, float precision there is 0.5 m
// at Earth size) and the slope (the normal against the radial direction). Crude on purpose: sand by the
// sea, grass, bare soil, rock on slopes, snow high up.
shader_type spatial;

uniform float radius = 6371000.0; // the planet's radius (m), set by script
uniform float snow_line = 2200.0;
uniform sampler2D colour_map : source_color, filter_linear, repeat_enable; // the planet's colours by direction (script)
uniform bool use_map = false;
uniform mat4 world_to_planet = mat4(1.0); // the terrain's own space (the planet's) from the world's, set by script

varying vec3 world_pos;
varying vec3 world_normal;
varying vec3 lab_pos; // the world's own position and normal (the game's flat world, near the player)
varying vec3 lab_normal;

// The near ground's scans (the planet ground shader's): placed by the lab's anchor, which holds
// still when the planet is turned under the player (planet_lab publishes these globals).
global uniform mat4 anchor_from_world;
global uniform vec3 anchor_wrap;
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

void vertex() {
	vec4 abs_pos = MODEL_MATRIX * vec4(VERTEX, 1.0);
	world_pos = (world_to_planet * abs_pos).xyz;
	lab_pos = abs_pos.xyz;
	lab_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	world_normal = normalize((world_to_planet * MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	float height = length(world_pos) - radius;
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
		col = texture(colour_map, map_uv).rgb * (0.82 + 0.36 * n) * 1.7; // (1.7: matched to the tiles' look, measured on the same spot)
	}
	col = mix(col, rock, smoothstep(0.18, 0.4, slope + (n - 0.5) * 0.15));
	col = mix(col, snow, smoothstep(snow_line, snow_line + 300.0, height + n * 150.0) * (1.0 - smoothstep(0.3, 0.6, slope)));
	float rough = 0.92;
	float fade = (1.0 - smoothstep(10.0, 32.0, length(VERTEX))) * detail_strength;
	if (detail_on && fade > 0.01) { // the soil's scan: green ground is forest earth, reddish is red soil, the rest gravel
		vec3 near_anchor = (anchor_from_world * vec4(lab_pos, 1.0)).xyz;
		vec3 on_planet = near_anchor + anchor_wrap;
		vec3 facing = normalize(mat3(anchor_from_world) * lab_normal);
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
		col *= mix(vec3(1.0), ratio * mix(0.55, 1.0, ao), fade);
		vec3 tilt_world = transpose(mat3(anchor_from_world)) * tilt;
		NORMAL = normalize(NORMAL + (VIEW_MATRIX * vec4(tilt_world, 0.0)).xyz * 0.9 * fade);
		rough = mix(rough, clamp(rough_sum, 0.3, 1.0), fade);
	}
	ALBEDO = col;
	ROUGHNESS = rough;
}
