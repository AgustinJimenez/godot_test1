shader_type spatial;
render_mode cull_disabled, unshaded;
// Birds and butterflies: two wings that flap. The vertex colour is the paint; wing tips (the
// vertices far from the body along local X) move up and down.

uniform float flap_speed = 9.0;
uniform float flap_size = 0.5;

void vertex() {
	float phase = float(INSTANCE_ID) * 1.7;
	float tip = abs(VERTEX.x);
	VERTEX.y += sin(TIME * flap_speed + phase) * tip * flap_size;
}

void fragment() {
	ALBEDO = pow(COLOR.rgb, vec3(2.2));
}
