shader_type canvas_item;
// Bakes the heights of the packed plates (planet_mosaic.gdshaderinc) into a picture: one pixel is one spot of the ground, the window is
// `bake_window` = (corner x, corner y, size) in the ground's own metres. The ground shader then reads the picture in its parallax march
// (mosaic_height_now) instead of working the pattern out at every step. Red: the large plates, green: the medium ones.

#include "res://shaders/world/planet_stones.gdshaderinc"
#include "res://shaders/world/planet_mosaic.gdshaderinc"

uniform vec4 bake_window = vec4(0.0, 0.0, 10.0, 0.0);

void fragment() {
	vec2 p = bake_window.xy + UV * bake_window.z;
	COLOR = vec4(mosaic_height_terms(p), 0.0, 1.0);
}
