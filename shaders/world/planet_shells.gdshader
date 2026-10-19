shader_type spatial;
render_mode specular_schlick_ggx;
// One shell layer of the near ground: a copy of the ground mesh lifted `level` of the stones' greatest height along its normals, drawn only
// where a stone is tall enough to reach it. A stack of these (PlanetShells) makes the loose stones of the ground real relief: they
// have a silhouette, hide the ground behind them, and are darker in the gaps between them. The stones are the ones the ground shader
// paints (the same field, in the planet's own coordinates).

#include "res://shaders/world/planet_stones.gdshaderinc"

global uniform mat4 anchor_from_world;
global uniform vec3 anchor_wrap;
global uniform vec3 anchor_up;
global uniform float ground_detail;
global uniform float snow_cover;

uniform float level : hint_range(0.0, 1.0) = 0.5; // 0 the ground .. 1 the top of the tallest stone
uniform float top = 0.06; // m: how tall the tallest stone stands
uniform float reach = 7.0; // m: beyond this the shells are gone (a stone is under a pixel)

varying vec3 world_pos;
varying vec3 soil;
varying float iron;

void vertex() {
	soil = CUSTOM0.rgb;
	iron = COLOR.a;
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	VERTEX += NORMAL * level * top;
}

void fragment() {
	float dist = length(VERTEX);
	float dither = fract(sin(dot(FRAGCOORD.xy, vec2(12.9898, 78.233))) * 43758.5453);
	if (dist > reach || dist > reach * (0.75 + 0.25 * dither) || ground_detail < 0.5) {
		discard;
	}
	vec3 on_planet = (anchor_from_world * vec4(world_pos, 1.0)).xyz + anchor_wrap;
	vec3 paint = pow(soil, vec3(2.2));
	float bare = 1.0 - smoothstep(0.0, 0.08, paint.g - max(paint.r, paint.b));
	float crumbly = mix(0.45, 1.0, iron) * bare * (1.0 - snow_cover);
	if (crumbly < 0.05) {
		discard;
	}
	float zone_big = noise3(on_planet * 0.0625 + 3.0, 64.0);
	float zone_mid = noise3(on_planet * 0.3125 + 9.0, 320.0);
	vec3 nudge = vec3(noise3(on_planet * 1.875, 1920.0), noise3(on_planet * 1.875 + 7.1, 1920.0), noise3(on_planet * 1.875 + 3.3, 1920.0));
	vec3 crumb_at = on_planet + (nudge - 0.5) * 0.09;
	float size_mid = 0.95 * mix(0.55, 1.05, zone_big);
	float size_big = 0.95 * mix(0.7, 1.05, zone_mid);
	float cover_mid = crumbly * mix(0.45, 1.0, zone_big);
	float cover_big = crumbly * mix(0.12, 1.0, 1.0 - zone_big);
	float height = 2.0 * crumb_height(crumb_at, size_mid, size_big, cover_mid, cover_big);
	if (height < level * top || level > 0.999) {
		discard;
	}
	// a stone's colour: the soil's own, each its own tone; the lower layers (the gaps and the feet of the stones) darker
	float tone = noise3(on_planet * 33.0, 33792.0);
	float lift = mix(0.5, 1.1, level) * (0.7 + 0.6 * tone);
	vec3 colour = paint * vec3(1.4, 0.72, 0.5) * mix(vec3(1.0), vec3(1.0), iron) * lift;
	colour = mix(paint * lift, colour, iron * 0.55);
	ALBEDO = colour;
	ROUGHNESS = 0.85;
	// the sides of a stone face the light unevenly: tilt the normal by the slope of the height
	float ahead = 2.0 * crumb_height(crumb_at + vec3(0.004, 0.0, 0.0), size_mid, size_big, cover_mid, cover_big);
	float aside = 2.0 * crumb_height(crumb_at + vec3(0.0, 0.0, 0.004), size_mid, size_big, cover_mid, cover_big);
	vec3 lean = -vec3(ahead - height, 0.0, aside - height) * 60.0;
	vec3 lean_world = (inverse(anchor_from_world) * vec4(lean, 0.0)).xyz;
	NORMAL = normalize(NORMAL + (VIEW_MATRIX * vec4(lean_world, 0.0)).xyz);
}
