shader_type spatial;
render_mode blend_premul_alpha, unshaded, cull_disabled, depth_draw_never, depth_test_disabled, fog_disabled;
// The clouds seen from in and above their layer, from a little over the ground to orbit: a sphere
// round the planet whose every pixel marches the layer of clouds along the ray from the camera
// (the same march as the sky's, planet_cloud_march.gdshaderinc), stopping at the ground of the
// scene. Under the layer the sky draws the clouds and this fades out.

#include "res://shaders/world/planet_cloud_march.gdshaderinc"

uniform sampler2D scene_depth : hint_depth_texture, repeat_disable, filter_nearest;
uniform vec3 planet_centre = vec3(0.0, -20000.0, 0.0); // world space
uniform float planet_radius = 20000.0;
uniform vec3 sun_toward = vec3(0.0, 1.0, 0.0); // unit vector from the planet to the star
uniform float fade = 1.0; // 0 under the layer .. 1 in and above it

varying vec3 world_position;

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec3 eye = (INV_VIEW_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	vec3 dir = normalize(world_position - eye);
	// how far the scene is along this ray: the clouds do not draw over what is nearer
	float depth = texture(scene_depth, SCREEN_UV).r;
	float limit = 1.0e9;
	if (depth > 0.0) {
		vec4 view = INV_PROJECTION_MATRIX * vec4(vec3(SCREEN_UV * 2.0 - 1.0, depth), 1.0);
		limit = length(view.xyz / view.w);
	}
	vec4 cloud = cloud_march(eye - planet_centre, dir, normalize(sun_toward), planet_radius, limit);
	ALBEDO = cloud.rgb * fade;
	ALPHA = (1.0 - cloud.a) * fade;
}
