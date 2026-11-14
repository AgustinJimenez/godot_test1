// The long shadows of hills and mountains on whatever stands on the ground: PlanetTerrainShade marches from every pixel of a picture of the ground
// round the player toward the star (on the CPU, again when the star or the player has moved), and here a surface reads the answer: one
// texture read. The sun's own shadow map reaches 150-250 m; this reaches the 14 km of the picture.
// 1 where the star is seen, 0 in the shadow.
// terrain_shade = (tan of the half side of the picture, strength 0..1, 0, 0)
#ifndef PLANET_FROM_WORLD_DECLARED
#define PLANET_FROM_WORLD_DECLARED
global uniform mat4 planet_from_world;
#endif
global uniform sampler2D terrain_shade_map : filter_linear, repeat_disable;
global uniform vec3 terrain_shade_c;
global uniform vec3 terrain_shade_e1;
global uniform vec3 terrain_shade_e2;
global uniform vec4 terrain_shade;

// `from_centre`: the point's place from the planet's centre, world axes, metres (haze_eye + mat3(INV_VIEW_MATRIX) * VERTEX)
float terrain_light(vec3 from_centre) {
	if (terrain_shade.y <= 0.0) {
		return 1.0;
	}
	vec3 d = normalize(mat3(planet_from_world) * from_centre);
	float cz = dot(d, terrain_shade_c);
	if (cz < 0.2) {
		return 1.0;
	}
	vec2 uv = vec2(dot(d, terrain_shade_e1), dot(d, terrain_shade_e2)) / cz / terrain_shade.x * 0.5 + 0.5;
	float edge = min(min(uv.x, uv.y), min(1.0 - uv.x, 1.0 - uv.y));
	if (edge <= 0.0) {
		return 1.0;
	}
	return mix(1.0, textureLod(terrain_shade_map, uv, 0.0).r, terrain_shade.y * smoothstep(0.0, 0.06, edge)); // (the shadows fade out toward the picture's edge)
}
