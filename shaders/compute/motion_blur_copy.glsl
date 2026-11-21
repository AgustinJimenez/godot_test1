#[compute]
#version 450

// The first step of the motion blur: a copy of the colour, so the blur can read the neighbours of a pixel while the colour is written.
// (The engine's colour buffer cannot be the source of a texture copy, so the copy is a compute pass.)

layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;

layout(rgba16f, set = 0, binding = 0) uniform readonly image2D color_image;
layout(rgba16f, set = 0, binding = 1) uniform writeonly image2D copy_image;

layout(push_constant, std430) uniform Params {
	vec2 raster_size;
	vec2 padding;
} params;

void main() {
	ivec2 pixel = ivec2(gl_GlobalInvocationID.xy);
	ivec2 size = ivec2(params.raster_size);
	if (pixel.x >= size.x || pixel.y >= size.y) {
		return;
	}
	imageStore(copy_image, pixel, imageLoad(color_image, pixel));
}
