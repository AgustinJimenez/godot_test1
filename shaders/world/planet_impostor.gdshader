shader_type spatial;
render_mode cull_disabled, depth_prepass_alpha;
// A far tree as a picture (task 081, step 1; PlanetImpostors bakes the atlas): VIEWS pictures of the tree from evenly spaced
// angles round it, side by side. Each instance is a quad that turns about the tree's own up axis to face the camera and shows
// the two pictures nearest the viewing angle, blended; the quad is as big as the picture (metres), so the mesh's size is the
// tree's.

uniform sampler2D atlas : source_color, filter_linear_mipmap, repeat_disable;
uniform float views = 8.0;
uniform float tint = 0.58;

varying float phase;
varying vec3 lit_normal;

void vertex() {
	mat4 m = MODEL_MATRIX;
	vec3 origin = m[3].xyz;
	float scale = length(m[1].xyz);
	vec3 up = m[1].xyz / scale;
	vec3 along = normalize(m[0].xyz);
	vec3 across = cross(along, up);
	vec3 to_camera = INV_VIEW_MATRIX[3].xyz - origin;
	// seen from above, a flat card turned about the up axis would be an edge: lean it toward the eye as the eye climbs
	float elevation = asin(clamp(dot(normalize(to_camera), up), -1.0, 1.0));
	float lean = smoothstep(0.45, 1.25, elevation) * 0.85;
	vec3 flat_to = to_camera - up * dot(to_camera, up);
	flat_to = length(flat_to) > 0.001 ? normalize(flat_to) : along;
	vec3 right = cross(up, flat_to);
	phase = fract(atan(dot(flat_to, across), dot(flat_to, along)) / TAU) * views;
	lit_normal = normalize(mix(up, flat_to, 0.55));
	vec3 top = normalize(mix(up, normalize(to_camera), lean));
	vec3 world = origin + top * VERTEX.y * scale + right * VERTEX.x * scale;
	POSITION = PROJECTION_MATRIX * VIEW_MATRIX * vec4(world, 1.0);
}

void fragment() {
	float first = floor(phase);
	float next = mod(first + 1.0, views);
	float blend = phase - first;
	vec4 a = texture(atlas, vec2((first + UV.x) / views, UV.y));
	vec4 b = texture(atlas, vec2((next + UV.x) / views, UV.y));
	vec4 colour = mix(a, b, blend);
	ALBEDO = colour.rgb * tint; // (the picture was lit once when baked, the scene lights it again)
	ALPHA = colour.a;
	ALPHA_SCISSOR_THRESHOLD = 0.5;
	ROUGHNESS = 1.0;
	NORMAL = normalize((VIEW_MATRIX * vec4(lit_normal, 0.0)).xyz);
}
