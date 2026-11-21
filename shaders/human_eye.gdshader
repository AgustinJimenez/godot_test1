shader_type spatial;
// Procedural eyeball for the base humans (assets/models/humans/*_eyes.glb: two plain spheres).
//
// There is no texture: the iris, pupil and sclera are drawn from the direction on the sphere, with the eye looking along +Z
// (the front of the body in Godot). So the iris colour (one per eye if wanted), its size, the pupil, the sclera tint and the veins
// are plain shader parameters.

uniform vec3 iris_color : source_color = vec3(0.32, 0.2, 0.1);   // the eye on the +X side (the character's left)
uniform vec3 iris_color_other : source_color = vec3(0.32, 0.2, 0.1);   // the eye on the -X side
uniform bool different_eyes = false;   // false: both eyes use iris_color
uniform vec3 sclera_color : source_color = vec3(0.9, 0.88, 0.85);
uniform float sclera_tint : hint_range(0.0, 1.0) = 0.0;   // 0 = white, 1 = clearly yellowed
uniform float iris_radius_deg = 26.0;   // angle of the iris edge from the gaze axis
uniform float pupil_size : hint_range(0.15, 0.7) = 0.38;   // pupil radius as a share of the iris radius
uniform float vein_amount : hint_range(0.0, 1.0) = 0.25;

varying vec3 obj_normal;
varying float side;   // +1 for the +X eye, -1 for the -X eye

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

void vertex() {
	obj_normal = NORMAL;
	side = sign(VERTEX.x);
}

void fragment() {
	vec3 n = normalize(obj_normal);
	float theta = degrees(acos(clamp(n.z, -1.0, 1.0)));   // 0 at the front of the eye
	float phi = atan(n.y, n.x);
	float t = theta / iris_radius_deg;                    // 0 at the pupil centre, 1 at the iris edge

	// Iris: fibres radiating from the pupil, a lighter ring around it, a dark ring at the outer edge.
	float fibres = 0.55 + 0.45 * noise(vec2(phi * 18.0, t * 3.0)) * noise(vec2(phi * 40.0, t * 6.0) + 7.0);
	vec3 base_iris = (different_eyes && side < 0.0) ? iris_color_other : iris_color;
	vec3 inner = mix(base_iris, vec3(0.75, 0.6, 0.25), 0.3);
	vec3 iris = mix(inner, base_iris, smoothstep(0.25, 0.8, t)) * fibres;
	iris *= 1.0 - 0.7 * smoothstep(0.82, 1.0, t);          // limbal ring

	// Pupil.
	float pupil = 1.0 - smoothstep(pupil_size - 0.03, pupil_size + 0.03, t * 1.0);
	vec3 col = iris * (1.0 - pupil);

	// Sclera: off-white, a few faint veins, darker toward the sides where the lids shade it.
	float veins = smoothstep(0.55, 0.9, noise(vec2(phi * 9.0, theta * 0.35)) * noise(vec2(phi * 23.0, theta * 0.5) + 3.0) * 2.2);
	vec3 sclera_base = mix(sclera_color, sclera_color * vec3(1.0, 0.88, 0.6), sclera_tint);
	vec3 sclera = sclera_base * (1.0 - 0.18 * smoothstep(40.0, 90.0, theta)) - vec3(0.0, 0.18, 0.18) * veins * vein_amount * smoothstep(30.0, 70.0, theta);

	float in_iris = 1.0 - smoothstep(0.97, 1.0, t);
	vec3 albedo = mix(sclera, col, in_iris);

	ALBEDO = albedo;
	ROUGHNESS = mix(0.12, 0.05, in_iris);
	SPECULAR = 0.9;
	CLEARCOAT = 1.0;
	CLEARCOAT_ROUGHNESS = 0.03;
}
