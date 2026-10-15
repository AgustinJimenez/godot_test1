shader_type spatial;
render_mode specular_schlick_ggx;
// The ground, in two looks that blend with `realism` (0 low-poly .. 1 realistic).
// Low-poly: a flat colour per facet and flat shading. Realistic: smooth normals, the smooth
// per-vertex palette, and procedural detail on top (patches of grass, soil and rock, strata on
// the steep faces, a fine grain and a bumpy surface), blended by slope. The weather (rain, snow,
// autumn) is applied in both.

global uniform float ground_wetness;
global uniform float snow_cover;
global uniform float autumn;
global uniform float realism;

varying vec3 smooth_color;
varying vec3 world_pos;
varying vec3 world_normal;

float cell_hash(vec2 p) {
	return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

// smooth 0..1 noise: the cell corners blended, so colours drift instead of jumping
float smooth_noise(vec2 p) {
	vec2 cell = floor(p);
	vec2 f = smoothstep(0.0, 1.0, fract(p));
	return mix(mix(cell_hash(cell), cell_hash(cell + vec2(1.0, 0.0)), f.x),
			mix(cell_hash(cell + vec2(0.0, 1.0)), cell_hash(cell + vec2(1.0, 1.0)), f.x), f.y);
}

float fbm(vec2 p) {
	float sum = 0.0;
	float amp = 0.5;
	for (int i = 0; i < 4; i++) {
		sum += smooth_noise(p) * amp;
		p = p * 2.03 + vec2(17.3, 9.1);
		amp *= 0.5;
	}
	return sum;
}

void vertex() {
	smooth_color = CUSTOM0.rgb;
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec3 flat_normal = normalize(cross(dFdx(VERTEX), dFdy(VERTEX)));
	if (dot(flat_normal, VIEW) < 0.0) {
		flat_normal = -flat_normal; // the facet normal always faces the camera
	}
	vec3 base = mix(COLOR.rgb, smooth_color, realism);
	vec3 paint = pow(base, vec3(2.2)); // the palette is written in sRGB
	// autumn: whatever is green turns yellow, orange and brown
	float leafy = smoothstep(0.0, 0.08, paint.g - max(paint.r, paint.b));
	float which = smooth_noise(world_pos.xz * 0.035);
	vec3 turned = mix(vec3(paint.g * 1.6, paint.g * 1.0, paint.g * 0.2),
			vec3(paint.g * 1.3, paint.g * 0.38, paint.g * 0.1), which);
	paint = mix(paint, turned, autumn * leafy);

	vec3 view_normal = flat_normal;
	float up = (INV_VIEW_MATRIX * vec4(flat_normal, 0.0)).y;
	float rough = 0.95;
	if (realism > 0.001) {
		float slope = 1.0 - clamp(world_normal.y, 0.0, 1.0);
		float patch = fbm(world_pos.xz * 0.28);
		float mid = fbm(world_pos.xz * 1.9 + 31.0);
		float grain = smooth_noise(world_pos.xz * 11.0);
		// colour variation at three scales
		vec3 detail = paint * mix(0.72, 1.28, patch) * mix(0.88, 1.12, mid) * (0.92 + 0.16 * grain);
		// bare soil shows through the green in patches
		float greenish = smoothstep(0.0, 0.07, paint.g - max(paint.r, paint.b));
		detail = mix(detail, vec3(0.23, 0.16, 0.1) * mix(0.8, 1.3, mid),
				greenish * smoothstep(0.62, 0.8, patch) * (1.0 - slope * 2.0) * 0.55);
		// strata on the steep faces: layers of rock
		float strata = sin(world_pos.y * 2.6 + patch * 4.0) * 0.5 + 0.5;
		detail *= mix(1.0, mix(0.8, 1.12, strata), smoothstep(0.25, 0.55, slope));
		paint = mix(paint, detail, realism);
		// a bumpy surface: the slope of the fine noise tilts the normal
		vec2 e = vec2(0.12, 0.0);
		float height_here = fbm(world_pos.xz * 3.1) * 0.6 + grain * 0.4;
		float dx = fbm((world_pos.xz + e.xy) * 3.1) * 0.6 + smooth_noise((world_pos.xz + e.xy) * 11.0) * 0.4 - height_here;
		float dz = fbm((world_pos.xz + e.yx) * 3.1) * 0.6 + smooth_noise((world_pos.xz + e.yx) * 11.0) * 0.4 - height_here;
		vec3 bump_world = vec3(-dx, 0.0, -dz) * (1.6 + slope * 4.0);
		vec3 bumpy = normalize(NORMAL + (VIEW_MATRIX * vec4(bump_world, 0.0)).xyz);
		view_normal = normalize(mix(flat_normal, bumpy, realism));
		up = mix(up, world_normal.y + (dx + dz) * 0.2, realism);
		rough = mix(0.95, 0.85 - patch * 0.15, realism);
	}
	float snow = snow_cover * smoothstep(0.45, 0.8, up);
	vec3 col = paint * (1.0 - ground_wetness * 0.3);
	col = mix(col, vec3(0.8, 0.84, 0.9), snow);
	NORMAL = view_normal;
	ALBEDO = col;
	ROUGHNESS = mix(mix(rough, 0.42, ground_wetness), 0.7, snow);
	SPECULAR = mix(0.3, 0.6, ground_wetness);
}
