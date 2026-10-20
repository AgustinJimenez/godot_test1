shader_type spatial;
render_mode specular_schlick_ggx;
// The small stones lying on the ground (PlanetTurf gravel): flat shaded facets in the colour each instance carries (the soil's reds, dark
// greys), with a soft low frequency variation across the stone and a slightly lighter edge where two facets meet. No fine noise: the old plant
// shader's rock paint drew a blocky pixel pattern on them.

varying vec3 stone_colour;
varying vec3 stone_pos;

void vertex() {
	stone_colour = COLOR.rgb; // (the instance colour times the mesh's: white)
	stone_pos = VERTEX;
}

float hash31(vec3 p) {
	p = fract(p * 0.3183099 + vec3(0.1, 0.2, 0.3));
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

float soft_noise(vec3 p) {
	vec3 i = floor(p);
	vec3 f = smoothstep(0.0, 1.0, fract(p));
	return mix(mix(mix(hash31(i), hash31(i + vec3(1, 0, 0)), f.x), mix(hash31(i + vec3(0, 1, 0)), hash31(i + vec3(1, 1, 0)), f.x), f.y),
			mix(mix(hash31(i + vec3(0, 0, 1)), hash31(i + vec3(1, 0, 1)), f.x), mix(hash31(i + vec3(0, 1, 1)), hash31(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}

void fragment() {
	vec3 base = pow(stone_colour, vec3(2.2));
	float variation = soft_noise(stone_pos * 1.6 + stone_colour * 7.0);
	ALBEDO = base * (0.8 + 0.4 * variation);
	ROUGHNESS = 0.9;
	SPECULAR = 0.25;
	// flat facets: the normal of the triangle, not the mesh's smoothed one
	vec3 flat_normal = normalize(cross(dFdx(VERTEX), dFdy(VERTEX)));
	if (dot(flat_normal, VIEW) < 0.0) {
		flat_normal = -flat_normal;
	}
	NORMAL = flat_normal;
}
