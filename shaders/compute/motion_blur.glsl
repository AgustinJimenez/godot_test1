#[compute]
#version 450

// Motion blur (graphics setting "Motion blur"): the picture is smeared along each pixel's velocity (from the engine's velocity buffer, which
// holds the camera's and the objects' motion since the last frame). Run by components/motion_blur_effect.gd after the transparent pass.

layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;

layout(rgba16f, set = 0, binding = 0) uniform image2D color_image; // written
layout(set = 0, binding = 1) uniform sampler2D source_image; // a copy of the colour, read
layout(set = 0, binding = 2) uniform sampler2D velocity_image;

layout(push_constant, std430) uniform Params {
	vec2 raster_size;
	float strength; // how much of the frame's motion is smeared
	float samples;
} params;

void main() {
	ivec2 pixel = ivec2(gl_GlobalInvocationID.xy);
	ivec2 size = ivec2(params.raster_size);
	if (pixel.x >= size.x || pixel.y >= size.y) {
		return;
	}
	vec2 uv = (vec2(pixel) + 0.5) / params.raster_size;
	vec2 velocity = textureLod(velocity_image, uv, 0.0).xy * params.strength;
	float reach = length(velocity);
	if (reach < 0.0004) {
		return; // (not moving: the pixel stays as it is)
	}
	const float MAX_REACH = 0.05; // (a fraction of the screen: a fast turn must not smear the whole picture)
	if (reach > MAX_REACH) {
		velocity *= MAX_REACH / reach;
	}
	int count = max(int(params.samples), 2);
	vec4 sum = vec4(0.0);
	for (int i = 0; i < count; i++) {
		float t = float(i) / float(count - 1) - 0.5;
		sum += textureLod(source_image, uv + velocity * t, 0.0);
	}
	imageStore(color_image, pixel, sum / float(count));
}
