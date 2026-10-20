shader_type spatial;
render_mode specular_schlick_ggx;
// A planet's ground: the flat world's low-poly ground (a flat colour per facet) with detail laid
// over it that belongs to the planet and not to the screen or to the tile: 3D noise read at the
// point's position on the planet, found from the world position through `planet_from_world` (the
// planet is turned under the player every few tens of metres, see PlanetFrame; the pattern must not
// swim when that happens, and must continue over the seams between tiles). Patches of soil and
// rock tone, a fine grain, layers of rock that run level round the whole planet (they follow the
// distance from its centre), a bumpy surface on the steep faces, all fading out with distance so
// the far ground costs next to nothing. The weather (rain, snow, autumn) works as in the flat world.

global uniform float ground_wetness;
global uniform float snow_cover;
global uniform float rain_fall;
global uniform float autumn;
global uniform float realism;
// the clouds' shadow on the ground (the same layer the sky and the shell draw, planet_cloud_march.gdshaderinc):
// cloud_shadow = (strength 0..1, cloud darkness, least cover, 0), cloud_layer = (planet radius, layer floor,
// depth, 0), cloud_centre = the planet's centre in the world, cloud_sun_world = toward the star
global uniform sampler2D cloud_cover_map : filter_linear, repeat_enable;
global uniform vec4 cloud_shadow;
global uniform vec4 cloud_layer;
global uniform vec3 cloud_centre;
global uniform vec3 cloud_sun_world;
global uniform vec3 cloud_drift_planet;
global uniform float ground_detail; // 0 plain .. 3 finest (GraphicsSettings: Low 1, Medium 1, High 2, Ultra 3)
global uniform mat4 planet_from_world;
global uniform mat4 world_from_planet;
// the detail noise is read near the player, where numbers stay small (a float cannot hold a planet's
// 6 million metres to better than half a metre): the position from the anchor, the anchor wrapped
// to the noise's period, and the way up with the phase of the anchor's distance from the centre
global uniform mat4 anchor_from_world;
global uniform vec3 anchor_wrap;
global uniform vec3 anchor_up;
global uniform float anchor_phase;

uniform sampler2D rock_map : filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D soil_map : filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D sand_map : filter_linear_mipmap_anisotropic, repeat_enable;
// scans of real ground (ambientCG, CC0; scripts/make_scan_textures.py): colour + occlusion, and normal + roughness. They give the near
// ground the detail of a photograph (the soil's own colour is kept: the scan only says how it varies)
uniform sampler2D scan_gravel_c : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D scan_gravel_n : filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D scan_red_c : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D scan_red_n : filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D scan_leaf_c : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D scan_leaf_n : filter_linear_mipmap_anisotropic, repeat_enable;
// the procedural cliff (scripts/make_cliff_textures.py): stacked sandstone slabs, on the steep faces, its strata level
uniform sampler2D cliff_c : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D cliff_n : filter_linear_mipmap_anisotropic, repeat_enable;
uniform float cliff_scale = 0.33; // tiles a metre
uniform float scan_strength : hint_range(0.0, 1.0) = 0.85;
uniform float scan_scale = 0.7; // tiles a metre
uniform float flat_look : hint_range(0.0, 1.0) = 0.0; // 1: each quad one flat colour (the low-poly look)
uniform float detail_strength : hint_range(0.0, 1.0) = 0.8;
uniform float detail_range = 260.0; // m: the detail is gone by twice this

varying vec3 smooth_color;
varying vec3 world_pos;
varying vec3 world_normal;
varying vec4 geology; // what the rock of the place breaks into: angular, coarse, pale, flaky (0..1, from the crust)
varying float soil_organic; // 0.5 neutral; above: black earth and peat; below: the ash of cold forests, loess, desert dust
varying float soil_iron; // 0..1: red laterite and red sandstone soil
varying vec3 lie; // where stones lie: how stony the place is (0: clean soil), the soil's depth, river gravel (0..1)

#include "res://shaders/world/planet_stones.gdshaderinc"

float cell_hash(vec2 p) {
	return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

float smooth_noise(vec2 p) {
	vec2 cell = floor(p);
	vec2 f = smoothstep(0.0, 1.0, fract(p));
	return mix(mix(cell_hash(cell), cell_hash(cell + vec2(1.0, 0.0)), f.x),
			mix(cell_hash(cell + vec2(0.0, 1.0)), cell_hash(cell + vec2(1.0, 1.0)), f.x), f.y);
}

// A raindrop's ring on the water: the slope of the surface (x, z) in a 1 m cell, one drop per cell
// at a time, each at its own moment in a cycle.
vec2 ripple(vec2 p, float rate) {
	vec2 cell = floor(p);
	vec2 at = fract(p) - 0.5;
	float seed = cell_hash(cell);
	vec2 centre = (vec2(cell_hash(cell + 3.1), cell_hash(cell + 7.7)) - 0.5) * 0.4;
	float age = fract(TIME * (0.55 + 0.4 * seed) + seed * 7.0);
	vec2 from_centre = at - centre;
	float d = length(from_centre);
	float radius = age * 0.45;
	float width = 0.035;
	float wave = sin((d - radius) / width * 3.14159) * exp(-pow((d - radius) / (width * 2.0), 2.0));
	float live = (1.0 - age) * step(seed, rate);
	return normalize(from_centre + 0.0001) * wave * live;
}

float cloud_shadow_hash(vec3 p) {
	p = fract(p * 0.3183099 + vec3(0.71, 0.113, 0.419));
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

float cloud_shadow_noise(vec3 p) {
	vec3 i = floor(p);
	vec3 f = smoothstep(0.0, 1.0, fract(p));
	return mix(mix(mix(cloud_shadow_hash(i), cloud_shadow_hash(i + vec3(1, 0, 0)), f.x),
			mix(cloud_shadow_hash(i + vec3(0, 1, 0)), cloud_shadow_hash(i + vec3(1, 1, 0)), f.x), f.y),
			mix(mix(cloud_shadow_hash(i + vec3(0, 0, 1)), cloud_shadow_hash(i + vec3(1, 0, 1)), f.x),
			mix(cloud_shadow_hash(i + vec3(0, 1, 1)), cloud_shadow_hash(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}

// How much of the star's light the clouds take from the point `from_centre` (world axes, metres from the
// planet's centre): the ray to the star crosses the middle of the layer, and the cloud there (the cloud
// density of planet_cloud_march.gdshaderinc, the coarse octaves) shades the ground under it.
float cloud_shade_at(vec3 from_centre) {
	vec3 sun = normalize(cloud_sun_world);
	float r_mid = cloud_layer.x + cloud_layer.y + cloud_layer.z * 0.35;
	float b = dot(from_centre, sun);
	float c = dot(from_centre, from_centre) - r_mid * r_mid;
	float disc = b * b - c;
	if (disc <= 0.0 || length(from_centre) > r_mid) {
		return 0.0;
	}
	vec3 hit = from_centre + sun * (-b + sqrt(disc));
	vec3 q = mat3(planet_from_world) * hit;
	vec3 d = normalize(q);
	vec2 uv = vec2(atan(d.z, d.x) / TAU + 0.5, 0.5 - asin(clamp(d.y, -1.0, 1.0)) / PI);
	float cover = max(textureLod(cloud_cover_map, uv, 0.0).r, cloud_shadow.z);
	vec3 p = (q + cloud_drift_planet) * 0.0022;
	// the same layers of noise as the clouds themselves (planet_cloud_march.gdshaderinc)
	float shape = cloud_shadow_noise(p * 0.1 + 11.0) * 0.2 + cloud_shadow_noise(p * 0.25 + 23.0) * 0.15
			+ cloud_shadow_noise(p) * 0.4 + cloud_shadow_noise(p * 2.1 + 7.0) * 0.15
			+ cloud_shadow_noise(p * 4.3 + 3.0) * 0.1;
	float body = shape - (1.0 - cover) * 0.75 - 0.12;
	return clamp(body * 3.2, 0.0, 1.0);
}

// A surface texture (RGB normal, A brightness) projected along the three axes of the planet and blended by
// the way the ground faces: returns the tilt (planet axes) in xyz and the brightness in w.
vec4 triplanar(sampler2D map, vec3 at, vec3 facing, float scale) {
	vec3 w = pow(abs(facing), vec3(4.0));
	w /= w.x + w.y + w.z;
	vec4 sx = texture(map, at.yz * scale);
	vec4 sy = texture(map, at.xz * scale);
	vec4 sz = texture(map, at.xy * scale);
	vec2 nx = sx.xy * 2.0 - 1.0;
	vec2 ny = sy.xy * 2.0 - 1.0;
	vec2 nz = sz.xy * 2.0 - 1.0;
	vec3 tilt = vec3(0.0, nx.x, nx.y) * w.x + vec3(ny.x, 0.0, ny.y) * w.y + vec3(nz.x, nz.y, 0.0) * w.z;
	return vec4(tilt, sx.a * w.x + sy.a * w.y + sz.a * w.z);
}

void vertex() {
	smooth_color = CUSTOM0.rgb;
	geology = CUSTOM1;
	soil_organic = CUSTOM0.a;
	soil_iron = COLOR.a;
	lie = CUSTOM2.rgb;
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

// Twigs and sticks lying on the ground: in each cell of 1/`scale` metres (some have none) a thin rod `length_cells` long, `radius_cells` thick, at
// a random angle. Out: `h` how high the rod stands at the point (0 off it .. 1 along its axis), `lean` the way its round surface tilts the light,
// `tone` its own tone, `halo` how close the point is to a rod (a shadow on the ground beside it).
void sticks(vec3 p, float scale, float period, float length_cells, float radius_cells, out float h, out vec3 lean, out float tone,
		out float halo) {
	vec3 q = p * scale;
	vec3 base = floor(q);
	vec3 toward = vec3(fract(q.x) < 0.5 ? -1.0 : 1.0, fract(q.y) < 0.5 ? -1.0 : 1.0, fract(q.z) < 0.5 ? -1.0 : 1.0);
	h = 0.0;
	lean = vec3(0.0);
	tone = 0.5;
	halo = 0.0;
	for (int i = 0; i < 2; i++) {
		for (int j = 0; j < 2; j++) {
			for (int k = 0; k < 2; k++) {
				vec3 c = base + vec3(float(i), float(j), float(k)) * toward;
				vec3 w = mod(c, period);
				float present = step(0.55, hash3(w + 31.7));
				vec3 centre = c + 0.3 + 0.4 * vec3(hash3(w + 1.1), hash3(w + 4.3), hash3(w + 8.9));
				vec3 dir = normalize(vec3(hash3(w + 21.3) - 0.5, (hash3(w + 23.7) - 0.5) * 0.35, hash3(w + 27.1) - 0.5));
				vec3 d = q - centre;
				float half_length = length_cells * (0.5 + 0.5 * hash3(w + 13.3)) * 0.5;
				float along = clamp(dot(d, dir), -half_length, half_length);
				vec3 perp = d - dir * along;
				float ratio = length(perp) / (radius_cells * (0.7 + 0.6 * hash3(w + 6.1)));
				halo = max(halo, present * smoothstep(2.6, 1.0, ratio));
				float height = max(1.0 - ratio * ratio, 0.0) * present;
				if (height > h) {
					h = height;
					lean = perp / max(length(perp), 0.0001) * ratio * 0.9;
					tone = hash3(w + 5.9);
				}
			}
		}
	}
}

// Fallen leaves, flat on the ground: in each cell of 1/`scale` metres a leaf (some have none) pointed at both ends, at a random angle, on the
// plane of `across` and `up` (the ground's own axes). Returns x: 1 inside a leaf, y: its tone (0..1), z: its midrib (0..1); the lower leaves are
// covered by the ones with the larger dice.
vec3 leaf_litter(vec3 p, vec3 ground_up, float scale) {
	vec3 right = abs(ground_up.z) < 0.9 ? normalize(cross(ground_up, vec3(0.0, 0.0, 1.0))) : normalize(cross(ground_up, vec3(1.0, 0.0, 0.0)));
	vec3 forward = cross(ground_up, right);
	vec2 q = vec2(dot(p, right), dot(p, forward)) * scale;
	vec2 base = floor(q);
	float best = -1.0;
	vec3 result = vec3(0.0);
	for (int j = -1; j <= 1; j++) {
		for (int i = -1; i <= 1; i++) {
			vec2 c = base + vec2(float(i), float(j));
			vec3 w = vec3(mod(c, 1024.0 * scale), 7.7);
			float dice = hash3(w + 3.1);
			if (hash3(w + 17.3) < 0.38 || dice <= best) { // some cells have no leaf
				continue;
			}
			vec2 centre = c + 0.5 + (vec2(hash3(w + 1.9), hash3(w + 5.3)) - 0.5) * 0.7;
			float angle = hash3(w + vec3(9.7, 2.3, 5.1)) * 6.2831853;
			vec2 axis = vec2(cos(angle), sin(angle));
			vec2 d = q - centre;
			float u = dot(d, axis) / (0.36 + 0.2 * hash3(w + vec3(11.1, 3.7, 1.3))); // along the leaf, -1 stalk .. 1 tip
			float v = dot(d, vec2(-axis.y, axis.x)) / (0.2 + 0.1 * hash3(w + vec3(13.9, 6.1, 2.2)));
			if (abs(u) < 1.0) {
				float half_width = pow(max(1.0 - u * u, 0.0), 0.75) * (u < 0.0 ? 0.8 : 1.0);
				if (abs(v) < half_width) {
					best = dice;
					result = vec3(1.0, hash3(w + 15.1), 1.0 - smoothstep(0.0, 0.16, abs(v)));
				}
			}
		}
	}
	return result;
}

#include "res://shaders/world/planet_cliff.gdshaderinc"

// A texture sampled so that its repeat does not show: a second look at it, at another scale and place, blended in by a slow noise
// (the two share no repeat distance, so neither shows through). `uv` in tiles.
vec4 unrepeated(sampler2D map, vec2 uv) {
	vec4 first = texture(map, uv);
	vec2 turned = uv * vec2(0.71, 0.77) + vec2(0.37, 0.61); // (not turned: the slabs stay level and the normal map's directions stay true)
	vec4 second = texture(map, turned);
	float mixture = smoothstep(0.3, 0.7, smooth_noise(uv * 0.23 + 3.1));
	return mix(first, second, mixture);
}

// One scan on the three planes, as the detail it adds: out `ratio` the colour over the scan's own mean (1: the soil's colour), `ao`
// its occlusion, `tilt` the way its relief leans the normal (planet axes), `rough` its roughness.
void scan_triplanar(sampler2D colour_map, sampler2D normal_map, vec3 at, vec3 facing, float scale, vec3 mean, out vec3 ratio,
		out float ao, out vec3 tilt, out float rough) {
	vec3 w = pow(abs(facing), vec3(4.0));
	w /= w.x + w.y + w.z;
	vec2 uv_x = at.yz * scale;
	vec2 uv_y = at.xz * scale;
	vec2 uv_z = at.xy * scale;
	vec4 cx = unrepeated(colour_map, uv_x);
	vec4 cy = unrepeated(colour_map, uv_y);
	vec4 cz = unrepeated(colour_map, uv_z);
	vec4 nx = texture(normal_map, uv_x);
	vec4 ny = texture(normal_map, uv_y);
	vec4 nz = texture(normal_map, uv_z);
	vec3 colour = cx.rgb * w.x + cy.rgb * w.y + cz.rgb * w.z;
	ratio = clamp(colour / mean, vec3(0.2), vec3(3.0));
	ao = cx.a * w.x + cy.a * w.y + cz.a * w.z;
	vec2 tx = nx.xy * 2.0 - 1.0;
	vec2 ty = ny.xy * 2.0 - 1.0;
	vec2 tz = nz.xy * 2.0 - 1.0;
	tilt = vec3(0.0, tx.x, tx.y) * w.x + vec3(ty.x, 0.0, ty.y) * w.y + vec3(tz.x, tz.y, 0.0) * w.z;
	rough = nx.b * w.x + ny.b * w.y + nz.b * w.z;
}

void fragment() {
	vec3 flat_normal = normalize(cross(dFdx(VERTEX), dFdy(VERTEX)));
	if (dot(flat_normal, VIEW) < 0.0) {
		flat_normal = -flat_normal;
	}
	// the far ground is shaded smooth (the facets of coarse tiles would not match the fine ones
	// at the seams between them); the near ground keeps its facets
	float far = smoothstep(90.0, 320.0, length(VERTEX));
	vec3 base = mix(COLOR.rgb, smooth_color, max(max(realism, far), 1.0 - flat_look));
	vec3 paint = pow(base, vec3(2.2));
	float leafy = smoothstep(0.0, 0.08, paint.g - max(paint.r, paint.b));
	float which = smooth_noise(world_pos.xz * 0.035);
	vec3 turned = mix(vec3(paint.g * 1.6, paint.g * 1.0, paint.g * 0.2),
			vec3(paint.g * 1.3, paint.g * 0.38, paint.g * 0.1), which);
	paint = mix(paint, turned, autumn * leafy);

	// the kind of soil: black earth and peat darker, the ash of cold forests, loess and desert dust paler, laterite and red
	// sandstone soil red with iron (the crust's numbers); grass and snow hide it
	float bare_soil = 1.0 - smoothstep(0.0, 0.08, paint.g - max(paint.r, paint.b)) * 0.9;
	float organic = (soil_organic - 0.5) * 2.0;
	paint *= 1.0 - 0.45 * max(organic, 0.0) * bare_soil;
	paint = mix(paint, paint * 0.6 + vec3(0.2, 0.19, 0.16), max(-organic, 0.0) * 0.55 * bare_soil);
	paint = mix(paint, paint * vec3(1.4, 0.72, 0.5), soil_iron * 0.55 * bare_soil);

	vec3 view_normal = normalize(mix(flat_normal, normalize(NORMAL), far));
	float up = (INV_VIEW_MATRIX * vec4(flat_normal, 0.0)).y;
	float rough = 0.95;
	float near = 1.0 - smoothstep(detail_range, detail_range * 2.0, length(VERTEX));
	float level = ground_detail;
	float reach = 1.0 + 0.4 * step(2.5, level);
	near = 1.0 - smoothstep(detail_range * reach, detail_range * reach * 2.0, length(VERTEX));
	float strength = detail_strength * near * step(0.5, level);
	float ao = 1.0;
	float sparkle = 0.0;
	if (strength > 0.001) {
		vec3 near_anchor = (anchor_from_world * vec4(world_pos, 1.0)).xyz;
		vec3 on_planet = near_anchor + anchor_wrap; // the planet position, to the noise's period
		float slope = 1.0 - clamp(world_normal.y, 0.0, 1.0);
		float patch = fbm3(on_planet * 0.171875, 176.0);
		float mid = fbm3(on_planet * 1.296875 + 31.0, 1328.0);
		float grain = noise3(on_planet * 7.0, 7168.0);
		vec3 detail = paint * mix(0.78, 1.22, patch) * mix(0.9, 1.1, mid) * (0.94 + 0.12 * grain);
		// bare soil shows through the green in patches
		float greenish = smoothstep(0.0, 0.07, paint.g - max(paint.r, paint.b));
		detail = mix(detail, vec3(0.23, 0.16, 0.1) * mix(0.8, 1.3, mid),
				greenish * smoothstep(0.64, 0.82, patch) * (1.0 - slope * 2.0) * 0.5);
		// layers of rock on the steep faces, level round the planet (distance from its centre)
		float rise = dot(anchor_up, near_anchor);
		float strata = sin(anchor_phase + rise * 1.86 + patch * 9.3) * 0.5 + 0.5;
		float rocky = smoothstep(0.22, 0.5, slope);
		detail *= mix(1.0, mix(0.78, 1.14, strata), rocky);
		paint = mix(paint, detail, strength);
		// a bumpy surface: the slope of the fine noise tilts the normal, more on steep ground
		vec2 e = vec2(0.15, 0.0);
		float here = fbm3(on_planet * 2.703125, 2768.0);
		float dx = fbm3((on_planet + e.xyy) * 2.703125, 2768.0) - here;
		float dy = fbm3((on_planet + e.yxy) * 2.703125, 2768.0) - here;
		float dz = fbm3((on_planet + e.yyx) * 2.703125, 2768.0) - here;
		vec3 bump_planet = -vec3(dx, dy, dz) * (0.8 + slope * 5.0) * strength;
		vec3 bump_world = (world_from_planet * vec4(bump_planet, 0.0)).xyz;
		vec3 bumpy = normalize(NORMAL + (VIEW_MATRIX * vec4(bump_world, 0.0)).xyz);
		view_normal = normalize(mix(view_normal, bumpy, strength));
		rough = mix(0.95, 0.88 - patch * 0.1, strength);
		// the steep faces are cliff: slabs with their strata level (the texture is drawn on two vertical planes of the place's own frame:
		// u along the face, v up), its colour kept as the detail over the rock's own (the crust's colour for the place)
		float cliff_w = smoothstep(0.35, 0.6, slope) * (1.0 - smoothstep(60.0, 140.0, length(VERTEX))) * scan_strength;
		if (cliff_w > 0.01) {
			vec3 up_local = normalize(anchor_up);
			vec3 side_ref = abs(up_local.y) < 0.9 ? vec3(0.0, 1.0, 0.0) : vec3(1.0, 0.0, 0.0);
			vec3 right_local = normalize(cross(side_ref, up_local));
			vec3 forward_local = cross(up_local, right_local);
			vec3 spot = vec3(dot(on_planet, right_local), dot(on_planet, up_local), dot(on_planet, forward_local));
			vec3 facing_cliff = normalize(mat3(anchor_from_world) * world_normal);
			vec2 across = vec2(abs(dot(facing_cliff, forward_local)), abs(dot(facing_cliff, right_local))); // (a face looking along forward is drawn on the plane of right and up)
			vec2 plane_weight = pow(across, vec2(4.0));
			plane_weight /= max(plane_weight.x + plane_weight.y, 0.0001);
			vec2 uv_a = vec2(spot.x, spot.y) * cliff_scale;
			vec2 uv_b = vec2(spot.z, spot.y) * cliff_scale;
			vec3 cliff_colour;
			float cliff_ao;
			vec3 tilt_planet;
			vec3 cliff_mean = vec3(0.5716, 0.1905, 0.0373);
			if (cliff_procedural) {
				// computed here, in metres along the face and up it, on the planes the face looks along
				vec3 colour_a = vec3(0.0);
				vec3 colour_b = vec3(0.0);
				float ao_a = 1.0;
				float ao_b = 1.0;
				vec2 tilt_a = vec2(0.0);
				vec2 tilt_b = vec2(0.0);
				if (plane_weight.x > 0.02) {
					cliff_surface(vec2(spot.x, spot.y), colour_a, ao_a, tilt_a);
				}
				if (plane_weight.y > 0.02) {
					cliff_surface(vec2(spot.z, spot.y), colour_b, ao_b, tilt_b);
				}
				cliff_colour = colour_a * plane_weight.x + colour_b * plane_weight.y;
				cliff_ao = ao_a * plane_weight.x + ao_b * plane_weight.y;
				tilt_planet = (right_local * tilt_a.x + up_local * tilt_a.y) * plane_weight.x
						+ (forward_local * tilt_b.x + up_local * tilt_b.y) * plane_weight.y;
			} else {
				vec4 col_a = unrepeated(cliff_c, uv_a);
				vec4 col_b = unrepeated(cliff_c, uv_b);
				vec4 nor_a = unrepeated(cliff_n, uv_a);
				vec4 nor_b = unrepeated(cliff_n, uv_b);
				cliff_colour = col_a.rgb * plane_weight.x + col_b.rgb * plane_weight.y;
				cliff_ao = col_a.a * plane_weight.x + col_b.a * plane_weight.y;
				vec2 tilt_a = nor_a.xy * 2.0 - 1.0;
				vec2 tilt_b = nor_b.xy * 2.0 - 1.0;
				tilt_planet = (right_local * tilt_a.x + up_local * tilt_a.y) * plane_weight.x
						+ (forward_local * tilt_b.x + up_local * tilt_b.y) * plane_weight.y;
			}
			vec3 cliff_ratio = clamp(cliff_colour / vec3(0.5716, 0.1905, 0.0373), vec3(0.25), vec3(2.2));
			float luma = dot(cliff_ratio, vec3(0.33));
			cliff_ratio = mix(vec3(luma), cliff_ratio, cliff_procedural ? cliff_hue : 0.55); // (the hue is the rock's own: the slabs bring the light and the shadow)
			paint *= mix(vec3(1.0), cliff_ratio * mix(0.5, 1.0, cliff_ao), cliff_w);
			vec3 cliff_world = (world_from_planet * vec4(tilt_planet * 1.1, 0.0)).xyz;
			view_normal = normalize(view_normal + (VIEW_MATRIX * vec4(cliff_world, 0.0)).xyz * cliff_w);
		}
		// crumbly gravel: bare soil that breaks into angular fragments (laterite and red sandstone soil the most): chips a few centimetres
		// and a hand across and chunks, each its own tone and its own tilt to the light, pale chips and a few dark pebbles among them, a
		// dark gap round each. Three sizes, near the walker only (a fragment is under a pixel beyond a few tens of metres); grass and snow
		// hide it. The patterns change over the ground at three scales (a few metres, tens of metres, hundreds) so no stretch of it repeats:
		// which size dominates, how thick it lies, how pale and how grey, and the hue of the soil; and each fragment is nudged off the grid.
		// Near the eye it has depth (parallax occlusion mapping: the view ray is marched into the height of the chunks, so they hide the
		// soil behind them and shift with the view) and the chunks shade each other from the sun
		float crumb_dist = length(VERTEX);
		float crumb_bare = (1.0 - smoothstep(0.0, 0.08, paint.g - max(paint.r, paint.b))) * (1.0 - snow_cover)
				* (1.0 - smoothstep(0.0, 0.1, paint.r - paint.b) * (1.0 - smoothstep(-0.03, 0.0, paint.g - paint.r)) * 0.7);
		float crumbly = mix(0.45, 1.0, soil_iron) * (1.0 - 0.35 * max((soil_organic - 0.5) * 2.0, 0.0)) * crumb_bare;
		if (crumbly > 0.02 && crumb_dist < 52.0) {
			float zone_big = noise3(on_planet * 0.0625 + 3.0, 64.0); // tens of metres: which size dominates, how thick
			float zone_mid = noise3(on_planet * 0.3125 + 9.0, 320.0); // a few metres: how pale, how grey, how dense the fine
			float zone_far = noise3(on_planet * 0.015625 + 21.0, 16.0); // hundreds of metres: the hue of the soil
			paint *= mix(vec3(0.93, 0.99, 1.05), vec3(1.12, 0.98, 0.82), zone_far);
			// the scans: which one the soil is (red iron soil, dark forest earth, otherwise grey gravel), near the walker only
			float scan_fade = (1.0 - smoothstep(10.0, 32.0, crumb_dist)) * scan_strength * crumb_bare;
			if (scan_fade > 0.01) {
				vec3 facing_scan = normalize(mat3(anchor_from_world) * world_normal);
				float w_red = smoothstep(0.25, 0.75, soil_iron);
				float w_leaf = smoothstep(0.5, 0.75, soil_organic) * (1.0 - w_red);
				float w_gravel = 1.0 - w_red - w_leaf;
				vec3 ratio_sum = vec3(0.0);
				vec3 tilt_sum = vec3(0.0);
				float ao_sum = 0.0;
				float rough_sum = 0.0;
				vec3 ratio;
				float ao_one;
				vec3 tilt;
				float rough_one;
				if (w_gravel > 0.02) {
					scan_triplanar(scan_gravel_c, scan_gravel_n, on_planet, facing_scan, scan_scale, vec3(0.1452, 0.1181, 0.0898), ratio, ao_one, tilt, rough_one);
					ratio_sum += ratio * w_gravel; tilt_sum += tilt * w_gravel; ao_sum += ao_one * w_gravel; rough_sum += rough_one * w_gravel;
				}
				if (w_red > 0.02) {
					scan_triplanar(scan_red_c, scan_red_n, on_planet, facing_scan, scan_scale, vec3(0.3041, 0.2007, 0.1305), ratio, ao_one, tilt, rough_one);
					ratio_sum += ratio * w_red; tilt_sum += tilt * w_red; ao_sum += ao_one * w_red; rough_sum += rough_one * w_red;
				}
				if (w_leaf > 0.02) {
					scan_triplanar(scan_leaf_c, scan_leaf_n, on_planet, facing_scan, scan_scale, vec3(0.1943, 0.1288, 0.0655), ratio, ao_one, tilt, rough_one);
					ratio_sum += ratio * w_leaf; tilt_sum += tilt * w_leaf; ao_sum += ao_one * w_leaf; rough_sum += rough_one * w_leaf;
				}
				paint *= mix(vec3(1.0), ratio_sum * mix(0.55, 1.0, ao_sum), scan_fade);
				vec3 scan_world = (world_from_planet * vec4(tilt_sum * 0.9, 0.0)).xyz;
				view_normal = normalize(view_normal + (VIEW_MATRIX * vec4(scan_world, 0.0)).xyz * scan_fade);
				rough = mix(rough, clamp(rough_sum, 0.3, 1.0), scan_fade);
			}
			vec3 nudge = vec3(noise3(on_planet * 1.875, 1920.0), noise3(on_planet * 1.875 + 7.1, 1920.0), noise3(on_planet * 1.875 + 3.3, 1920.0));
			vec3 crumb_at = on_planet + (nudge - 0.5) * 0.09; // (fragments are moved off their grid a little)
			float size_fine = 0.95 * mix(0.6, 1.05, zone_mid);
			float size_mid = 0.95 * mix(0.55, 1.05, zone_big);
			float size_big = 0.95 * mix(0.7, 1.05, zone_mid);
			float cover_fine = crumbly * mix(0.55, 1.0, zone_mid);
			float cover_mid = crumbly * mix(0.45, 1.0, zone_big);
			float cover_big = crumbly * mix(0.12, 1.0, 1.0 - zone_big);
			vec3 hit = crumb_at;
			float hit_height = 0.0;
			float shadow = 0.0;
			float parallax_fade = 1.0 - smoothstep(3.0, 7.0, crumb_dist);
			vec3 facing_anchor = normalize(mat3(anchor_from_world) * world_normal);
			if (parallax_fade > 0.02) {
				// the view ray into the height of the chunks (the surface is the top, 3 cm above the soil)
				vec3 ray = normalize(mat3(anchor_from_world) * (INV_VIEW_MATRIX * vec4(normalize(VERTEX), 0.0)).xyz);
				float slant = max(dot(-ray, facing_anchor), 0.12);
				// a linear search down the ray (each pixel starts a little differently, so the steps do not show as bands), then four
				// halvings of the step the ray went in at (the ground it hits is found, not guessed from the two nearest steps)
				const int STEPS = 8;
				const float TOTAL = 0.03;
				float jitter = fract(sin(dot(FRAGCOORD.xy, vec2(12.9898, 78.233))) * 43758.5453);
				float last_travel = 0.0;
				float found = -1.0;
				float bracket_low = 0.0;
				float bracket_high = 0.0;
				for (int i = 1; i <= STEPS; i++) {
					float depth = TOTAL * (float(i) - 1.0 + jitter) / float(STEPS - 1);
					float travel = depth / slant;
					vec3 at = crumb_at + ray * travel;
					float height_here = crumb_height(at, size_mid, size_big, cover_mid, cover_big);
					if (depth >= TOTAL - height_here) {
						bracket_low = last_travel;
						bracket_high = travel;
						found = travel;
						break;
					}
					last_travel = travel;
				}
				if (found >= 0.0) {
					for (int k = 0; k < 4; k++) {
						float middle = 0.5 * (bracket_low + bracket_high);
						float depth_middle = middle * slant;
						if (depth_middle >= TOTAL - crumb_height(crumb_at + ray * middle, size_mid, size_big, cover_mid, cover_big)) {
							bracket_high = middle;
						} else {
							bracket_low = middle;
						}
					}
					hit = mix(crumb_at, crumb_at + ray * bracket_high, parallax_fade);
				}
				// the sun: the chunks the ray from the hit towards the sun passes through shade it
				vec3 sun_anchor = normalize(mat3(anchor_from_world) * normalize(cloud_sun_world));
				float sun_up = dot(sun_anchor, facing_anchor);
				if (sun_up > 0.1) {
					vec3 along = (sun_anchor - facing_anchor * sun_up) / sun_up; // the ground travelled for each unit risen
					float own = crumb_height(hit, size_mid, size_big, cover_mid, cover_big);
					for (int k = 1; k <= 3; k++) {
						float rise = 0.008 * float(k);
						float blocking = crumb_height(hit + along * rise, size_mid, size_big, cover_mid, cover_big);
						shadow = max(shadow, smoothstep(0.0, 0.006, blocking - (own + rise)));
					}
				}
			}
			for (int crumb_class = 0; crumb_class < 3; crumb_class++) {
				float crumb_scale = crumb_class == 0 ? 30.0 : (crumb_class == 1 ? 11.0 : 4.2); // cells a metre
				float crumb_fade = 1.0 - smoothstep(crumb_class == 0 ? 7.0 : (crumb_class == 1 ? 16.0 : 28.0),
						crumb_class == 0 ? 13.0 : (crumb_class == 1 ? 30.0 : 52.0), crumb_dist);
				if (crumb_fade < 0.01) {
					continue;
				}
				float c_h;
				vec3 c_lean;
				float c_tone;
				float c_gap;
				float class_size = crumb_class == 0 ? size_fine : (crumb_class == 1 ? size_mid : size_big);
				float class_cover = crumb_class == 0 ? cover_fine : (crumb_class == 1 ? cover_mid : cover_big);
				stones(hit + 40.0 + float(crumb_class) * 13.0, crumb_scale, 1024.0 * crumb_scale, class_size, 0.5, 0.4, c_h, c_lean,
						c_tone, c_gap);
				float c_cover = smoothstep(0.0, 0.1, c_h) * class_cover * crumb_fade;
				// the fragments are the soil's own colour, darker or lighter, and among them stones of other kinds (what the rocks of the place and
				// the rivers brought): grey granite, pale limestone and white quartz, dark basalt and shale, ochre sandstone; more of the pale
				// ones where the rock of the place is pale, of the dark ones where it is dark
				float lighter = 0.62 + 0.85 * c_tone + 0.2 * c_h + (zone_mid - 0.5) * 0.35;
				vec3 fragment = paint * lighter;
				float kind_dice = fract(c_tone * 7.31 + zone_big * 3.0);
				float other = (crumb_class == 2 ? 0.2 : 1.0) * (0.05 + 0.12 * zone_mid + 0.05 * float(crumb_class)); // how many are of another kind
				float is_other = smoothstep(other, other * 0.7, fract(c_tone * 3.77 + 0.31));
				vec3 granite = vec3(0.17, 0.165, 0.16) * (0.7 + 0.7 * c_tone);
				vec3 limestone = vec3(0.34, 0.3, 0.24) * (0.8 + 0.5 * c_tone);
				vec3 quartz = vec3(0.42, 0.4, 0.37) * (0.8 + 0.4 * c_tone);
				vec3 basalt = vec3(0.04, 0.04, 0.042) * (0.8 + 0.6 * c_tone);
				vec3 ochre = vec3(0.34, 0.2, 0.06) * (0.8 + 0.5 * c_tone);
				float pale_rock = geology.z;
				vec3 stone = kind_dice < 0.3 ? granite : (kind_dice < 0.3 + 0.35 * pale_rock ? limestone : (kind_dice < 0.7 ? basalt : (kind_dice < 0.86 ? ochre : quartz)));
				fragment = mix(fragment, stone, is_other * 0.92);
				fragment = mix(fragment, vec3(0.5, 0.36, 0.26) * (0.8 + 0.5 * c_tone), smoothstep(0.1, 0.0, c_tone) * 0.75 * (crumb_class == 2 ? 0.0 : 1.0)); // pale chips
				paint = mix(paint, fragment, c_cover);
				paint *= 1.0 - c_gap * class_cover * crumb_fade * 0.8; // the dark gap hugging each fragment
				vec3 c_world = (world_from_planet * vec4(c_lean, 0.0)).xyz;
				view_normal = normalize(view_normal + (VIEW_MATRIX * vec4(c_world, 0.0)).xyz * c_cover * (crumb_class == 2 ? 1.3 : 1.0) * strength);
				rough = mix(rough, 0.82, c_cover * strength);
			}
			paint *= 1.0 - 0.55 * shadow * parallax_fade;
			// wood and litter: twigs, bark chips and fallen leaves, thicker on the dark soil of forests (organic matter) and in patches
			float forest_floor = smoothstep(0.42, 0.68, soil_organic) * 0.8 + 0.2;
			float litter_zone = smoothstep(0.25, 0.75, noise3(on_planet * 0.1875 + 13.0, 192.0)) * (0.35 + 0.65 * forest_floor);
			float litter_fade = 1.0 - smoothstep(14.0, 30.0, crumb_dist);
			if (litter_zone > 0.02 && litter_fade > 0.01) {
				float st_h;
				vec3 st_lean;
				float st_tone;
				float st_halo;
				sticks(hit + 77.0, 3.2, 1024.0 * 3.2, 0.8, 0.045, st_h, st_lean, st_tone, st_halo); // twigs a quarter of a metre long
				float stick_cover = smoothstep(0.0, 0.2, st_h) * litter_zone * litter_fade * crumbly;
				vec3 wood = paint * vec3(0.3, 0.24, 0.2) * (0.6 + 0.9 * st_tone);
				paint *= 1.0 - st_halo * litter_zone * litter_fade * crumbly * 0.3;
				paint = mix(paint, wood, stick_cover);
				vec3 stick_world = (world_from_planet * vec4(st_lean, 0.0)).xyz;
				view_normal = normalize(view_normal + (VIEW_MATRIX * vec4(stick_world, 0.0)).xyz * stick_cover * 1.4 * strength);
				sticks(hit + 91.0, 14.0, 1024.0 * 14.0, 0.55, 0.16, st_h, st_lean, st_tone, st_halo); // bark chips and small sticks
				float chip_cover = smoothstep(0.0, 0.2, st_h) * litter_zone * litter_fade * crumbly * (1.0 - smoothstep(8.0, 16.0, crumb_dist));
				paint = mix(paint, paint * vec3(0.32, 0.25, 0.2) * (0.6 + 0.9 * st_tone), chip_cover);
				float leaf_fade = litter_fade * (0.3 + 0.7 * forest_floor);
				vec3 leaves = leaf_litter(hit + 53.0, normalize(anchor_up), 9.0);
				float leaf_cover = leaves.x * litter_zone * leaf_fade * mix(0.6, 1.0, crumbly);
				float palette = fract(leaves.y * 5.3);
				// dead leaves of a few kinds: dark brown, rust, olive, pale straw; the leaf's own tone and a lighter midrib
				vec3 leaf_tint = palette < 0.3 ? vec3(0.2, 0.15, 0.1) : (palette < 0.55 ? vec3(0.7, 0.28, 0.12) : (palette < 0.8 ? vec3(0.3, 0.34, 0.1) : vec3(1.8, 1.35, 0.7)));
				leaf_tint *= 0.75 + 0.5 * leaves.y;
				leaf_tint = mix(leaf_tint, leaf_tint * 1.6 + 0.08, leaves.z * 0.5);
				paint = mix(paint, paint * leaf_tint, clamp(leaf_cover * 1.2, 0.0, 0.97));
			}
		}
		if (level > 1.5) {
			// the finer ground (High and up): a bump a hand wide, crevices that are darker, ripples
			// in the sand, glints in the snow; all fade out within a few tens of metres
			float fine = 1.0 - smoothstep(28.0, 60.0, length(VERTEX));
			float micro_here = fbm3(on_planet * 14.0625, 14400.0);
			float mx = fbm3((on_planet + vec3(0.04, 0.0, 0.0)) * 14.0625, 14400.0) - micro_here;
			float my = fbm3((on_planet + vec3(0.0, 0.04, 0.0)) * 14.0625, 14400.0) - micro_here;
			float mz = fbm3((on_planet + vec3(0.0, 0.0, 0.04)) * 14.0625, 14400.0) - micro_here;
			vec3 micro_planet = -vec3(mx, my, mz) * (1.4 + slope * 3.0) * fine * strength;
			vec3 micro_world = (world_from_planet * vec4(micro_planet, 0.0)).xyz;
			view_normal = normalize(view_normal + (VIEW_MATRIX * vec4(micro_world, 0.0)).xyz);
			// meadows: patches of yellowing grass, darker clumps and a sprinkle of flowers (the
			// grass is one green to the map; a real meadow is many)
			float meadow = smoothstep(0.02, 0.1, paint.g - max(paint.r, paint.b)) * (1.0 - slope * 2.5);
			if (meadow > 0.01) {
				float dry_patch = fbm3(on_planet * 0.045 + 71.0, 1152.0);
				paint = mix(paint, paint * vec3(1.35, 1.1, 0.55), smoothstep(0.55, 0.78, dry_patch) * meadow * 0.7);
				float clump = fbm3(on_planet * 0.6 + 17.0, 15360.0);
				paint *= mix(1.0, 0.8 + 0.4 * clump, meadow * 0.6);
				vec3 cell = floor(on_planet * 4.0);
				float patch_k = smoothstep(0.45, 0.7, fbm3(on_planet * 0.09 + 5.0, 2304.0)); // flowers grow in drifts
				float bloom = step(1.0 - 0.12 * patch_k - 0.012, hash3(cell + 3.0));
				vec3 inside = fract(on_planet * 4.0) - 0.5; // (a little ball in the cell: round on any slope)
				vec3 jitter = vec3(hash3(cell), hash3(cell + 9.0), hash3(cell + 13.0)) - 0.5;
				float petal = smoothstep(0.3, 0.16, length(inside + jitter * 0.3));
				float pick = hash3(cell + 5.0);
				vec3 flower = pick < 0.4 ? vec3(0.85, 0.82, 0.75) : (pick < 0.7 ? vec3(0.9, 0.7, 0.1) : vec3(0.45, 0.25, 0.6));
				paint = mix(paint, pow(flower, vec3(2.2)), bloom * petal * meadow * fine * 0.9);
			}
			// real surface detail: rock on the steep faces, sand on pale level ground, soil elsewhere
			float surface_fade = 1.0 - smoothstep(30.0, 70.0, length(VERTEX));
			if (surface_fade > 0.01) {
				vec3 facing = mat3(anchor_from_world) * world_normal;
				float on_sand = smoothstep(0.0, 0.1, paint.r - paint.b) * (1.0 - smoothstep(-0.03, 0.0, paint.g - paint.r));
				float w_rock = smoothstep(0.2, 0.45, slope + (1.0 - lie.y) * 0.25 * (1.0 - snow_cover)); // thin soil shows the rock
				float w_sand = on_sand * (1.0 - w_rock);
				float w_soil = 1.0 - w_rock - w_sand;
				vec4 surface = vec4(0.0, 0.0, 0.0, 0.0);
				if (w_rock > 0.01) {
					surface += triplanar(rock_map, on_planet, facing, 0.31) * w_rock;
				}
				if (w_sand > 0.01) {
					surface += triplanar(sand_map, on_planet, facing, 0.7) * w_sand;
				}
				if (w_soil > 0.01) {
					surface += triplanar(soil_map, on_planet, facing, 0.5) * w_soil;
				}
				float amount = surface_fade * strength * (1.0 - snow_cover * 0.7);
				vec3 tilt_world = (world_from_planet * vec4(surface.xyz * 0.9, 0.0)).xyz;
				view_normal = normalize(view_normal + (VIEW_MATRIX * vec4(tilt_world, 0.0)).xyz * amount);
				paint *= mix(1.0, 0.45 + surface.w * 1.1, amount);
			}
			// loose stones of three sizes (grit, pebbles, cobbles) lying in the soil: each stone has its own shade, its own
			// dome that tilts the light, and a dark gap hugging it, so the ground has depth and grain and is not one
			// painted colour. Grass hides them; sand has only its grit; the coarse sizes thicken in some patches
			// and on slopes and fade out with distance (their size is under a pixel beyond it)
			float green_here = smoothstep(0.0, 0.09, paint.g - max(paint.r, paint.b));
			float cover_open = (1.0 - green_here * 0.97) * (1.0 - snow_cover);
			float dist = length(VERTEX);
			float sand_here = smoothstep(0.0, 0.1, paint.r - paint.b) * (1.0 - smoothstep(-0.03, 0.0, paint.g - paint.r));
			vec3 stone_leans = vec3(0.0);
			float stone_ao = 1.0;
			vec3 stone_paint = paint;
			float gravel_amount = 0.0;
			for (int size_class = 0; size_class < 3; size_class++) {
				float scale = size_class == 0 ? 14.0 : (size_class == 1 ? 4.5 : 1.6); // cells a metre
				float reach_here = size_class == 0 ? 24.0 : (size_class == 1 ? 55.0 : 90.0);
				float fade = 1.0 - smoothstep(reach_here * 0.5, reach_here, dist);
				if (fade < 0.01) {
					continue;
				}
				// coarse rock (granite) breaks into cobbles, fine rock (sandstone, shale) into grit and flakes
				float stony = lie.x; // the place's own odds of stones: whole regions have none
				float odds = size_class == 0 ? 0.1 + 0.9 * stony : (size_class == 1 ? smoothstep(0.1, 0.6, stony) : smoothstep(0.35, 0.9, stony));
				float coverage = size_class == 0 ? 0.9 * (1.15 - 0.35 * geology.y)
						: smoothstep(0.2, 0.5, mid + slope * 0.7 + (size_class == 2 ? 0.0 : 0.2));
				if (size_class == 1) {
					coverage *= (1.0 - sand_here) * (0.5 + geology.y);
				} else if (size_class == 2) {
					coverage *= (1.0 - sand_here) * smoothstep(0.42, 0.8, patch + slope) * (0.1 + 1.5 * geology.y * geology.y);
				}
				coverage *= cover_open * fade * odds;
				if (coverage < 0.01) {
					continue;
				}
				float sh;
				vec3 ln;
				float tone;
				float gap;
				stones(on_planet, scale, 1024.0 * scale, 0.46, mix(geology.x, 0.1, lie.z * 0.85), geology.w * (1.0 - lie.z * 0.8),
						sh, ln, tone, gap); // (river gravel is rounded and not flat)
				float on_top = smoothstep(0.0, 0.12, sh) * coverage;
				// a stone's colour: pale quartz, dark basalt, or the ground's own tone lightened and greyed
				// pale rock (limestone, granite) gives pale stones, basalt and shale dark ones; each stone a little lighter or
				// darker, a few much (quartz, a dark cobble); the ground's own hue is kept in part
				float lightness = clamp(geology.z + (tone - 0.5) * 0.7, 0.0, 1.0);
				vec3 hue = clamp(paint / max(dot(paint, vec3(0.33)), 0.02), vec3(0.5), vec3(1.8));
				vec3 own = mix(vec3(0.04), vec3(0.6), lightness) * mix(vec3(1.0), hue, 0.5 * (1.0 - green_here));
				own = mix(own, vec3(0.62, 0.6, 0.56), smoothstep(0.93, 1.0, tone) * 0.8);
				own = mix(own, vec3(0.06, 0.055, 0.06), smoothstep(0.07, 0.0, tone) * 0.8);
				own *= 0.8 + 0.4 * sh;
				stone_paint = mix(stone_paint, own, on_top);
				// between the stones the soil is darker and damper, darkest hugging them
				stone_paint *= 1.0 - gap * coverage * 0.35;
				stone_leans += ln * on_top * (size_class == 0 ? 0.5 : 0.9);
				stone_ao *= 1.0 - coverage * (gap * 0.3 + (1.0 - smoothstep(0.0, 0.3, sh)) * 0.1);
				gravel_amount = max(gravel_amount, on_top);
			}
			paint = mix(paint, stone_paint, strength);
			vec3 stone_world = (world_from_planet * vec4(stone_leans, 0.0)).xyz;
			view_normal = normalize(view_normal + (VIEW_MATRIX * vec4(stone_world, 0.0)).xyz * strength);
			rough = mix(rough, 0.78, gravel_amount * strength);
			// crevices and the hollows between stones are darker (the low parts of the bump)
			ao = mix(1.0, mix(0.7, 1.0, smoothstep(0.25, 0.7, here)), strength * (0.5 + slope));
			ao *= mix(1.0, stone_ao, strength);
			// sand: the wind lays ripples, a few centimetres high, a few metres apart
			float sandy = smoothstep(0.0, 0.1, paint.r - paint.b) * (1.0 - smoothstep(0.0, 0.05, paint.g - paint.r + 0.02))
					* smoothstep(0.7, 0.95, world_normal.y);
			float ripple_phase = (on_planet.x + on_planet.z * 0.6) * 6.283185 * 300.0 / 1024.0 + patch * 5.0;
			float ripples = sin(ripple_phase) * 0.5 + 0.5;
			vec3 across = (VIEW_MATRIX * vec4(0.7, 0.0, 0.42, 0.0)).xyz;
			view_normal = normalize(view_normal + across * (ripples - 0.5) * 0.35 * sandy * fine);
			paint *= mix(1.0, mix(0.94, 1.05, ripples), sandy * fine);
			// glints: the snow has crystals that catch the sun
			sparkle = step(0.985, hash3(floor(on_planet * 90.0))) * fine;
		}
		if (level > 2.5) {
			// the finest (Ultra): a second, finer bump
			float fine2 = 1.0 - smoothstep(10.0, 24.0, length(VERTEX));
			float f_here = fbm3(on_planet * 31.25, 32000.0);
			float fx = fbm3((on_planet + vec3(0.02, 0.0, 0.0)) * 31.25, 32000.0) - f_here;
			float fz = fbm3((on_planet + vec3(0.0, 0.0, 0.02)) * 31.25, 32000.0) - f_here;
			vec3 f_planet = -vec3(fx, 0.0, fz) * 2.2 * fine2 * strength;
			vec3 f_world = (world_from_planet * vec4(f_planet, 0.0)).xyz;
			view_normal = normalize(view_normal + (VIEW_MATRIX * vec4(f_world, 0.0)).xyz);
		}
	}
	// snow settles unevenly: more on level ground, thinner and broken at the edges and on slopes
	float broken = smooth_noise(world_pos.xz * 0.9) * 0.6 + smooth_noise(world_pos.xz * 4.1) * 0.4;
	float snow = snow_cover * smoothstep(0.5, 0.85, up + (broken - 0.5) * 0.5 * (1.0 - snow_cover * 0.6));
	// rain: the ground goes dark and glossy everywhere, and water stands in the low level patches
	float low_patch = smooth_noise(world_pos.xz * 0.11) * 0.65 + smooth_noise(world_pos.xz * 0.43) * 0.35;
	float puddle = ground_wetness * smoothstep(0.52, 0.66, low_patch) * smoothstep(0.88, 0.97, up);
	puddle *= 1.0 - snow;
	vec3 col = paint * (1.0 - ground_wetness * 0.35);
	col = mix(col, col * 0.55, puddle);
	col = mix(col, vec3(0.8, 0.84, 0.9), snow);
	if (puddle > 0.01 && rain_fall > 0.01) {
		// the drops make rings on the standing water
		vec2 slope = ripple(world_pos.xz * 1.0, rain_fall) + ripple(world_pos.xz * 1.7 + 11.0, rain_fall);
		vec3 tilt = (VIEW_MATRIX * vec4(slope.x, 0.0, slope.y, 0.0)).xyz * 0.35 * puddle;
		view_normal = normalize(view_normal + tilt);
	}
	if (cloud_shadow.x > 0.01) {
		// the ground under a cloud is darker (the direct light is the part the cloud takes: the sky's light stays)
		float sun_up = clamp(dot(normalize(world_pos - cloud_centre), normalize(cloud_sun_world)) * 4.0, 0.0, 1.0);
		float shade = cloud_shade_at(world_pos - cloud_centre) * cloud_shadow.x * sun_up
				* (1.0 - cloud_shadow.z); // (a full overcast already dims the sun itself)
		col *= 1.0 - shade * (0.5 + 0.2 * cloud_shadow.y);
	}
	NORMAL = mix(view_normal, normalize(mix(view_normal, normalize(NORMAL), 0.8)), puddle);
	ALBEDO = col;
	ROUGHNESS = mix(mix(mix(rough, 0.35, ground_wetness), 0.04, puddle), 0.7, snow);
	ROUGHNESS = mix(ROUGHNESS, 0.18, snow * sparkle);
	AO = ao;
	AO_LIGHT_AFFECT = 0.5;
	SPECULAR = mix(0.3, 0.7, max(ground_wetness, puddle));
}
