shader_type spatial;
render_mode cull_disabled, depth_prepass_alpha;
// A far tree as a picture (task 081, step 1; PlanetImpostors bakes the atlas): the tree drawn from VIEWS evenly spaced angles round it at three
// heights of the eye (0, 35 and 65 degrees above the horizon: the rows), side by side, and one more picture from straight above (after the
// last column of the first row). Each instance is a quad that faces the eye, upright about the tree's own up axis, and shows the pictures nearest
// the viewing angle and height, blended; the quad is as big as the picture (metres), so the mesh's size is the tree's.

uniform sampler2D atlas : source_color, filter_linear_mipmap, repeat_disable;
uniform float views = 8.0;
uniform float rows = 3.0;
uniform float tint = 0.58;
uniform float middle = 0.0; // metres: how high the card's centre is above the tree's foot (it leans about its centre)

const float ELEV_1 = 0.6109; // 35 degrees (the rows of the atlas)
const float ELEV_2 = 1.1345; // 65 degrees

varying float phase;
varying float row_t; // 0 .. 2 between the three rows, 2 .. 3 on to the picture from above
varying vec3 lit_normal;

global uniform vec3 cloud_sun_world; // toward the star
#include "res://shaders/world/planet_haze.gdshaderinc" // the haze by height (FOG)

void vertex() {
	mat4 m = MODEL_MATRIX;
	vec3 origin = m[3].xyz;
	float scale = length(m[1].xyz);
	vec3 up = m[1].xyz / scale;
	vec3 along = normalize(m[0].xyz);
	vec3 across = cross(along, up);
	vec3 to_camera = INV_VIEW_MATRIX[3].xyz - origin;
	vec3 view_dir = normalize(to_camera);
	float elevation = asin(clamp(dot(view_dir, up), 0.0, 1.0));
	vec3 flat_to = to_camera - up * dot(to_camera, up);
	flat_to = length(flat_to) > 0.001 ? normalize(flat_to) : along;
	vec3 right = cross(up, flat_to);
	phase = fract(atan(dot(flat_to, across), dot(flat_to, along)) / TAU) * views;
	if (elevation < ELEV_1) {
		row_t = elevation / ELEV_1;
	} else if (elevation < ELEV_2) {
		row_t = 1.0 + (elevation - ELEV_1) / (ELEV_2 - ELEV_1);
	} else {
		row_t = 2.0 + (elevation - ELEV_2) / (1.5708 - ELEV_2);
	}
	lit_normal = normalize(mix(up, flat_to, 0.55));
	// the card faces the eye: its up is the tree's up turned to lie across the line of sight (straight up when the eye is level)
	vec3 top = normalize(cross(view_dir, right));
	vec3 world = origin + up * middle * scale + top * (VERTEX.y - middle) * scale + right * VERTEX.x * scale;
	POSITION = PROJECTION_MATRIX * VIEW_MATRIX * vec4(world, 1.0);
}

vec4 picture(float column, float row, vec2 uv) {
	return texture(atlas, vec2((column + uv.x) / (views + 1.0), (row + uv.y) / rows));
}

void fragment() {
	FOG = planet_haze(mat3(INV_VIEW_MATRIX) * VERTEX, cloud_sun_world);
	float first = floor(phase);
	float next = mod(first + 1.0, views);
	float blend = phase - first;
	float row = min(floor(row_t), rows - 1.0);
	float between = row_t - row;
	float row_up = min(row + 1.0, rows - 1.0);
	vec4 low = mix(picture(first, row, UV), picture(next, row, UV), blend);
	vec4 high = mix(picture(first, row_up, UV), picture(next, row_up, UV), blend);
	vec4 above = picture(views, 0.0, UV); // (the picture from above is in the first row only)
	vec4 colour = mix(low, mix(high, above, step(rows - 1.5, row)), between);
	ALBEDO = colour.rgb * tint; // (the picture was lit once when baked, the scene lights it again)
	ALPHA = colour.a;
	ALPHA_SCISSOR_THRESHOLD = 0.5;
	ROUGHNESS = 1.0;
	NORMAL = normalize((VIEW_MATRIX * vec4(lit_normal, 0.0)).xyz);
}
