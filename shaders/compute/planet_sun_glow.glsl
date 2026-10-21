#[compute]
#version 450

// The glow round the sun and a few lens-flare ghosts (task 081, step 3), added to the frame before tone mapping. The sun's screen
// position, its colour and how much of it shows (the sky's share of the pixels round it in the depth picture) decide it all.

layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;

layout(rgba16f, set = 0, binding = 0) uniform image2D color_image;
layout(set = 0, binding = 1) uniform sampler2D depth_tex;

layout(push_constant, std430) uniform Params {
	vec2 sun_px; // the sun in pixels
	vec2 size; // the picture in pixels
	vec4 tint; // rgb colour, a strength (0 when the sun is behind the camera or gone)
} params;

float disc(vec2 p, vec2 at, float radius, float soft) {
	return 1.0 - smoothstep(radius - soft, radius + soft, length(p - at));
}

void main() {
	ivec2 pixel = ivec2(gl_GlobalInvocationID.xy);
	if (pixel.x >= int(params.size.x) || pixel.y >= int(params.size.y) || params.tint.a <= 0.0) {
		return;
	}
	float height = params.size.y;
	vec2 here = (vec2(pixel) + 0.5 - 0.5 * params.size) / height; // the picture's height is 1
	vec2 sun = (params.sun_px - 0.5 * params.size) / height;

	// How much of the sun shows: the share of the pixels round it that are sky (the reversed depth is 0 there).
	float seen = 0.0;
	for (int i = 0; i < 9; i++) {
		vec2 tap = params.sun_px + (vec2(float(i % 3), float(i / 3)) - 1.0) * 12.0;
		if (tap.x >= 0.0 && tap.y >= 0.0 && tap.x < params.size.x && tap.y < params.size.y) {
			seen += texture(depth_tex, tap / params.size).x <= 0.00001 ? 1.0 : 0.0;
		}
	}
	seen /= 9.0;
	if (seen <= 0.0) {
		return;
	}

	float r = length(here - sun);
	float glow = 0.9 * exp(-r * 9.0) + 0.16 / (1.0 + r * r * 90.0) + 0.05 * exp(-r * 2.2);
	// ghosts along the line from the sun through the middle of the picture
	vec2 axis = -sun;
	float ghosts = 0.0;
	ghosts += 0.3 * disc(here, sun + axis * 0.55, 0.045, 0.03);
	ghosts += 0.2 * disc(here, sun + axis * 1.0, 0.09, 0.05);
	ghosts += 0.15 * disc(here, sun + axis * 1.45, 0.03, 0.02);
	ghosts += 0.1 * disc(here, sun + axis * 1.9, 0.13, 0.08);
	float edge = 1.0 - smoothstep(0.35, 0.95, length(sun) * 1.6); // flares fade as the sun leaves the picture
	vec3 add = params.tint.rgb * params.tint.a * seen * (glow + ghosts * edge);
	imageStore(color_image, pixel, imageLoad(color_image, pixel) + vec4(add, 0.0));
}
