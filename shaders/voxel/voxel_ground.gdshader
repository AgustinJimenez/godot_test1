// Ground colours for the voxel planet (task 096). The mesh has no per-vertex colours, so the
// colour comes from what a vertex knows: its height above the sea level of the planet (its
// distance from the planet's centre, which is the world origin, minus the radius; the model matrix
// is in absolute world coordinates in the double precision engine, float precision there is 0.5 m
// at Earth size) and the slope (the normal against the radial direction). Crude on purpose: sand by the
// sea, grass, bare soil, rock on slopes, snow high up.
shader_type spatial;

uniform float radius = 6371000.0; // the planet's radius (m), set by script
uniform float snow_line = 2200.0;

varying vec3 world_pos;
varying vec3 world_normal;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
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
	col = mix(col, rock, smoothstep(0.18, 0.4, slope + (n - 0.5) * 0.15));
	col = mix(col, snow, smoothstep(snow_line, snow_line + 300.0, height + n * 150.0) * (1.0 - smoothstep(0.3, 0.6, slope)));
	ALBEDO = col;
	ROUGHNESS = 0.92;
}
