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
global uniform mat4 planet_from_world;
global uniform mat4 world_from_planet;
// the detail noise is read near the player, where numbers stay small (a float cannot hold a planet's
// 6 million metres to better than half a metre): the position from the anchor, the anchor wrapped
// to the noise's period, and the way up with the phase of the anchor's distance from the centre
global uniform mat4 anchor_from_world;
global uniform vec3 anchor_wrap;
global uniform vec3 anchor_up;
global uniform float anchor_phase;

uniform float flat_look : hint_range(0.0, 1.0) = 0.0; // 1: each quad one flat colour (the low-poly look)
uniform float detail_strength : hint_range(0.0, 1.0) = 0.8;
uniform float detail_range = 260.0; // m: the detail is gone by twice this

varying vec3 smooth_color;
varying vec3 world_pos;
varying vec3 world_normal;

float hash3(vec3 p) {
	p = fract(p * 0.3183099 + vec3(0.1, 0.2, 0.3));
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

// Value noise that repeats every `period` cells (so the position can be wrapped to a small number).
float noise3(vec3 p, float period) {
	vec3 i = floor(p);
	vec3 f = smoothstep(0.0, 1.0, fract(p));
	vec3 a = mod(i, period);
	vec3 b = mod(i + 1.0, period);
	return mix(mix(mix(hash3(a), hash3(vec3(b.x, a.y, a.z)), f.x),
			mix(hash3(vec3(a.x, b.y, a.z)), hash3(vec3(b.x, b.y, a.z)), f.x), f.y),
			mix(mix(hash3(vec3(a.x, a.y, b.z)), hash3(vec3(b.x, a.y, b.z)), f.x),
			mix(hash3(vec3(a.x, b.y, b.z)), hash3(b), f.x), f.y), f.z);
}

float fbm3(vec3 p, float period) {
	float sum = 0.0;
	float amp = 0.5;
	for (int i = 0; i < 3; i++) {
		sum += noise3(p, period) * amp;
		p = p * 2.0 + vec3(17.3, 9.1, 5.7);
		period *= 2.0;
		amp *= 0.5;
	}
	return sum;
}

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

void vertex() {
	smooth_color = CUSTOM0.rgb;
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
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

	vec3 view_normal = normalize(mix(flat_normal, normalize(NORMAL), far));
	float up = (INV_VIEW_MATRIX * vec4(flat_normal, 0.0)).y;
	float rough = 0.95;
	float near = 1.0 - smoothstep(detail_range, detail_range * 2.0, length(VERTEX));
	float strength = detail_strength * near;
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
	NORMAL = mix(view_normal, normalize(mix(view_normal, normalize(NORMAL), 0.8)), puddle);
	ALBEDO = col;
	ROUGHNESS = mix(mix(mix(rough, 0.35, ground_wetness), 0.04, puddle), 0.7, snow);
	SPECULAR = mix(0.3, 0.7, max(ground_wetness, puddle));
}
