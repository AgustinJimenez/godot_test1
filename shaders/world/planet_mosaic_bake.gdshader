shader_type canvas_item;
// Bakes the heights of the packed plates (planet_mosaic.gdshaderinc) into a picture (PlanetGroundBake): a rectangle of the picture is
// the ground's world texels `bake_rect` = (corner x, corner y, width, height), one pixel a texel of `bake_texel` metres, in the march's
// own coordinates. The ground shader then reads the picture in its parallax march (mosaic_height_now) instead of working the pattern
// out at every step. Red: the large plates, green: the medium ones.

#include "res://shaders/world/planet_stones.gdshaderinc"
#include "res://shaders/world/planet_mosaic.gdshaderinc"

uniform vec4 bake_rect = vec4(0.0, 0.0, 1.0, 1.0);
uniform float bake_texel = 0.006;

void fragment() {
	vec2 p = (bake_rect.xy + UV * bake_rect.zw) * bake_texel;
	COLOR = vec4(mosaic_height_terms(p), 0.0, 1.0);
}
