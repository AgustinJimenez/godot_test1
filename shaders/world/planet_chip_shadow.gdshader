shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled;
// The dark soft patch round the foot of each small stone (the same instances as planet_chip.gdshader, a flat square each): the contact shadow
// that makes a stone sit in the ground. It lies flat on the ground (not tilted with the stone), at the soil's level: the parallax sinks the soil
// below the mesh near the camera, so the patch is pushed down the same way (the ground shader's fade by distance) and the ground's written depth
// hides it where a plate stands over it.

global uniform mat4 anchor_from_world;
global uniform vec3 anchor_up;

uniform float ground_sink = 0.04; // m, the parallax depth of the soil near the camera
uniform float mosaic_range = 6.0; // m, where that depth has faded out (the ground's mosaic_range)
uniform float shadow_strength : hint_range(0.0, 1.0) = 0.75;
uniform float spread = 1.35; // the patch's half width, in stone radii

varying vec2 patch_at;

void vertex() {
	patch_at = VERTEX.xz;
	vec3 origin = MODEL_MATRIX[3].xyz;
	float radius = 0.5 * (length(MODEL_MATRIX[0].xyz) + length(MODEL_MATRIX[2].xyz));
	float near_ground = pow(1.0 - smoothstep(0.4, mosaic_range, length((VIEW_MATRIX * vec4(origin, 1.0)).xyz)), 1.5);
	vec3 up = normalize(transpose(mat3(anchor_from_world)) * normalize(anchor_up));
	vec3 reference = abs(up.y) < 0.9 ? vec3(0.0, 1.0, 0.0) : vec3(1.0, 0.0, 0.0);
	vec3 side = normalize(cross(reference, up));
	vec3 front = cross(up, side);
	vec3 world = origin + (side * VERTEX.x + front * VERTEX.z) * radius * spread - up * ground_sink * near_ground + up * 0.002;
	POSITION = PROJECTION_MATRIX * VIEW_MATRIX * vec4(world, 1.0);
}

void fragment() {
	float edge = length(patch_at);
	ALBEDO = vec3(0.0);
	ALPHA = shadow_strength * pow(1.0 - smoothstep(0.25, 1.0, edge), 1.6);
}
