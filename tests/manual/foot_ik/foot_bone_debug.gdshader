shader_type spatial;
render_mode unshaded;

uniform int left_foot_bone = -1;
uniform int left_toe_bone = -1;
uniform int right_foot_bone = -1;
uniform int right_toe_bone = -1;
uniform vec3 debug_color : source_color = vec3(0.1, 1.0, 0.05);
uniform float influence_threshold : hint_range(0.0, 1.0) = 0.35;

varying float foot_influence;

void vertex() {
	foot_influence = 0.0;
	for (int index = 0; index < 4; index++) {
		int bone = int(BONE_INDICES[index]);
		if (
				bone == left_foot_bone
				|| bone == left_toe_bone
				|| bone == right_foot_bone
				|| bone == right_toe_bone
		) {
			foot_influence += BONE_WEIGHTS[index];
		}
	}
	// Avoid depth flicker where this second pass sits on the original skin.
	VERTEX += NORMAL * 0.001;
}

void fragment() {
	if (foot_influence < influence_threshold) {
		discard;
	}
	ALBEDO = debug_color;
	EMISSION = debug_color * 0.65;
}
