// The haze of a planet's low air on what is seen through it (the ground, the plants, the far trees, the water): written to FOG by the
// materials, in place of the environment's fog, which has one density for the whole view. The haze is thick near the ground and thins with
// the height above the planet (haze_air.y is the height over which it falls to 37 %), so a view down from a hill or from the air crosses only
// the layer, and a far peak stands clearer than the plain under it. Summed along the line from the eye to the point in two stretches (a
// long line dips toward the planet in its middle). Toward the star the haze takes the star's light.
// haze_air = (density at the ground per metre, the height scale in metres, 0, the planet's radius), haze_colour = the haze's own colour,
// haze_sun = the light the haze adds looking straight at the star, haze_eye = the eye from the planet's centre (world axes, metres).
// PlanetAtmosphere publishes them. Nothing here reads a world position: the engine built with double precision draws relative to the camera,
// and a position in a shader is not the world's there; the line from the eye to the point (the view's VERTEX turned to the world's axes) is.
global uniform vec4 haze_air;
global uniform vec4 haze_colour;
global uniform vec4 haze_sun;
global uniform vec3 haze_eye;

// the mean of exp(-h / scale) along a stretch whose ends are `a` and `b` metres high
float haze_stretch(float a, float b, float scale) {
	a = max(a, -scale);
	b = max(b, -scale);
	float from = exp(-a / scale);
	float rise = (b - a) / scale;
	if (abs(rise) < 0.01) {
		return from;
	}
	return (from - exp(-b / scale)) / rise;
}

// FOG for the point at the end of `line` (from the eye to it, world axes, metres): rgb the haze's colour there, a how much of it covers
// the point. `sun_toward` is the way to the star.
vec4 planet_haze(vec3 line, vec3 sun_toward) {
	if (haze_air.x <= 0.0) {
		return vec4(0.0);
	}
	float far = length(line);
	float h_eye = length(haze_eye) - haze_air.w;
	float h_at = length(haze_eye + line) - haze_air.w;
	float h_mid = length(haze_eye + line * 0.5) - haze_air.w;
	float thickness = haze_air.x * far * 0.5 * (haze_stretch(h_eye, h_mid, haze_air.y) + haze_stretch(h_mid, h_at, haze_air.y));
	float amount = 1.0 - exp(-thickness);
	float sun_len = length(sun_toward);
	float toward = sun_len > 0.001 ? max(dot(line / max(far, 0.001), sun_toward / sun_len), 0.0) : 0.0;
	// away from the star the haze is the sky's blue (Rayleigh); toward it the star's light, not that blue
	vec3 away_tint = mix(vec3(0.9, 0.97, 1.12), vec3(1.0), smoothstep(-0.2, 0.6, sun_len > 0.001 ? dot(line / max(far, 0.001), sun_toward / sun_len) : 1.0));
	// the haze's forward scattering (Mie): a wide glow round the star and a tight bright core in it (two lobes, like a Henyey-Greenstein
	// phase of a haze with large grains), and it needs a long line to build: a short line through the haze barely carries the core
	float lobe = 0.6 * pow(toward, 5.0) + 0.6 * pow(toward, 24.0) * smoothstep(0.0, 0.5, amount);
	return vec4(haze_colour.rgb * away_tint + haze_sun.rgb * lobe, amount);
}
