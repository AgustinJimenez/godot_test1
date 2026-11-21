shader_type spatial;
// Plain knit cotton for the base underwear (assets/models/humans/*_underwear.glb).
//
// The pattern is drawn in the model's own space (not from UVs, which are the skin's layout), blended from
// three directions so it has no seams. The mesh's vertex colour (red = near the waistband, green = near another
// hem, baked in tools/blender/make_underwear.py) is not used by this plain version.

uniform vec3 body_color : source_color = vec3(0.5, 0.49, 0.47);
uniform float stitches_per_metre = 140.0;
uniform float bump_depth = 0.0004; // metres: how far a stitch ridge rises above the gap
uniform float sheen = 0.18;

varying vec3 obj_pos;
varying vec3 obj_normal;

// Height of one knit stitch (a column of "V"s): 0 in the gap between stitches, 1 on the stitch ridge.
float stitch(vec2 p) {
	vec2 cell = p * stitches_per_metre;
	float across = abs(fract(cell.x) - 0.5) * 2.0;
	float along = fract(cell.y * 0.8 + across * 0.35);
	float ridge = smoothstep(0.0, 0.45, along) * (1.0 - smoothstep(0.55, 1.0, along));
	return ridge * (1.0 - 0.45 * across);
}

float hash(vec2 p) {
	return fract(sin(dot(floor(p), vec2(127.1, 311.7))) * 43758.5453);
}

void vertex() {
	obj_pos = VERTEX;
	obj_normal = NORMAL;
}

void fragment() {
	vec3 weights = pow(abs(obj_normal), vec3(4.0));
	weights /= weights.x + weights.y + weights.z;
	vec2 px = obj_pos.yz;
	vec2 py = obj_pos.xz;
	vec2 pz = obj_pos.xy;
	float knit = stitch(px) * weights.x + stitch(py) * weights.y + stitch(pz) * weights.z;
	// How many stitches fit in one pixel: when the weave is finer than the screen can show it fades to plain
	// colour instead of shimmering.
	float cells_per_pixel = length(fwidth(obj_pos)) * stitches_per_metre;
	float detail = (1.0 - smoothstep(0.18, 0.5, cells_per_pixel)) * (1.0 - smoothstep(2.0, 4.5, length(VERTEX)));

	float height = knit * detail;
	// Slight per-stitch colour variation so the weave is not perfectly regular.
	float variation = hash(obj_pos.xy * stitches_per_metre + obj_pos.yz * stitches_per_metre * 1.7) - 0.5;
	vec3 base = body_color;
	base *= 0.86 + 0.14 * height + 0.06 * variation * detail;

	// Bump: the screen-space slope of the stitch height turned into a small tilt of the normal.
	float h = height * bump_depth;
	vec3 dpdx = dFdx(VERTEX);
	vec3 dpdy = dFdy(VERTEX);
	vec3 r1 = cross(dpdy, NORMAL);
	vec3 r2 = cross(NORMAL, dpdx);
	float det = dot(dpdx, r1);
	vec3 grad = sign(det) * (dFdx(h) * r1 + dFdy(h) * r2);
	NORMAL = normalize(abs(det) * NORMAL - grad);

	ALBEDO = base;
	ROUGHNESS = 0.88;
	SPECULAR = 0.25;
	RIM = sheen;
	RIM_TINT = 0.6;
}
