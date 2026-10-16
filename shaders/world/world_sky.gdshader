shader_type sky;
// The sky, in two looks that blend with `realism`. Low-poly: a colour gradient set from outside
// (day, dusk, night, storm) with a sun disc and glow. Realistic: single-scattering atmosphere (the
// blue of the day, the red of the sunset, the haze at the horizon) and soft layered clouds that
// follow the weather. Both have the stars and the moon at night.

global uniform float realism;
global uniform vec2 wind_direction;

uniform vec3 top_color : source_color = vec3(0.25, 0.47, 0.86);
uniform vec3 horizon_color : source_color = vec3(0.66, 0.78, 0.92);
uniform vec3 ground_color : source_color = vec3(0.6, 0.65, 0.7);
uniform float night = 0.0;
uniform float overcast = 0.0;
uniform float cloud_cover = 0.3;
uniform float cloud_dark = 0.0;
uniform vec3 moon_direction = vec3(0.0, 0.7, -0.7);
uniform float moon_lit = 1.0; // 0 new .. 1 full: the share of the moon's face the sun lights
uniform vec3 sun_toward = vec3(0.0, 1.0, 0.0); // unit vector from the ground to the sun

float hash3(vec3 p) {
	p = fract(p * 0.3183099 + vec3(0.71, 0.113, 0.419));
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

// no sin(): its precision on the GPU turns this noise into hard-edged blocks in the clouds
float hash2(vec2 p) {
	vec3 q = fract(vec3(p.xyx) * 0.1031);
	q += dot(q, q.yzx + 33.33);
	return fract((q.x + q.y) * q.z);
}

float noise2(vec2 p) {
	vec2 i = floor(p);
	vec2 f = smoothstep(0.0, 1.0, fract(p));
	return mix(mix(hash2(i), hash2(i + vec2(1.0, 0.0)), f.x),
			mix(hash2(i + vec2(0.0, 1.0)), hash2(i + vec2(1.0, 1.0)), f.x), f.y);
}

float fbm2(vec2 p) {
	float sum = 0.0;
	float amp = 0.5;
	for (int i = 0; i < 5; i++) {
		sum += noise2(p) * amp;
		p = p * 2.07 + vec2(11.3, 5.7);
		amp *= 0.5;
	}
	return sum;
}

// Rayleigh and Mie single scattering through a spherical atmosphere (a few steps each).
vec3 scatter(vec3 dir, vec3 sun) {
	const float earth = 6371000.0;
	const float top = 6471000.0;
	const vec3 beta_r = vec3(5.8e-6, 13.5e-6, 33.1e-6);
	const float beta_m = 21e-6;
	const float scale_r = 8000.0;
	const float scale_m = 1200.0;
	vec3 origin = vec3(0.0, earth + 200.0, 0.0);
	// the distance along the view ray to the top of the atmosphere
	float b = dot(origin, dir);
	float c = dot(origin, origin) - top * top;
	float far = -b + sqrt(max(b * b - c, 0.0));
	// the ground blocks rays that point down
	float c_ground = dot(origin, origin) - earth * earth;
	float disc = b * b - c_ground;
	if (disc > 0.0 && dir.y < 0.0) {
		far = min(far, max(-b - sqrt(disc), 0.0));
	}
	const int steps = 12;
	float step_len = far / float(steps);
	float mu = dot(dir, sun);
	float phase_r = 3.0 / (16.0 * PI) * (1.0 + mu * mu);
	float g = 0.76;
	float phase_m = 3.0 / (8.0 * PI) * ((1.0 - g * g) * (1.0 + mu * mu))
			/ ((2.0 + g * g) * pow(1.0 + g * g - 2.0 * g * mu, 1.5));
	vec3 sum_r = vec3(0.0);
	vec3 sum_m = vec3(0.0);
	float depth_r = 0.0;
	float depth_m = 0.0;
	for (int i = 0; i < steps; i++) {
		vec3 p = origin + dir * (float(i) + 0.5) * step_len;
		float h = length(p) - earth;
		float hr = exp(-h / scale_r) * step_len;
		float hm = exp(-h / scale_m) * step_len;
		depth_r += hr;
		depth_m += hm;
		// light reaching this point from the sun
		float bs = dot(p, sun);
		float cs = dot(p, p) - top * top;
		float sun_far = -bs + sqrt(max(bs * bs - cs, 0.0));
		float sun_step = sun_far / 4.0;
		float sun_r = 0.0;
		float sun_m = 0.0;
		bool blocked = false;
		for (int j = 0; j < 4; j++) {
			vec3 q = p + sun * (float(j) + 0.5) * sun_step;
			float hq = length(q) - earth;
			if (hq < 0.0) {
				blocked = true;
				break;
			}
			sun_r += exp(-hq / scale_r) * sun_step;
			sun_m += exp(-hq / scale_m) * sun_step;
		}
		if (!blocked) {
			vec3 tau = beta_r * (depth_r + sun_r) + beta_m * 1.1 * (depth_m + sun_m);
			vec3 attenuation = exp(-tau);
			sum_r += attenuation * hr;
			sum_m += attenuation * hm;
		}
	}
	return 22.0 * (sum_r * beta_r * phase_r + sum_m * beta_m * phase_m);
}

void sky() {
	vec3 dir = normalize(EYEDIR);
	float up = dir.y;
	vec3 col = mix(horizon_color, top_color, pow(clamp(up, 0.0, 1.0), 0.45));
	col = mix(col, ground_color, smoothstep(0.0, -0.12, up));
	float clear = 1.0 - overcast;
	vec3 sun_dir = normalize(sun_toward);
	float night_k = night;
	if (realism > 0.001) {
		vec3 air = scatter(vec3(dir.x, max(dir.y, -0.02), dir.z), sun_dir);
		// the sky below the horizon fades to the haze colour
		air = mix(air, air * 0.6 + ground_color * 0.2, smoothstep(0.0, -0.1, up));
		// near the horizon the real sky is pale: scattering a second time greys the colour away
		float haze = pow(1.0 - clamp(up, 0.0, 1.0), 5.0) * smoothstep(0.05, 0.4, sun_dir.y);
		air = mix(air, vec3(dot(air, vec3(0.33))) * vec3(0.92, 1.0, 1.08), haze * 0.75);
		// clouds: a layer of noise projected on the sky, thicker where the weather says so
		if (up > 0.01) {
			vec2 p = dir.xz / (up + 0.18) * 1.6 + wind_direction * TIME * 0.012;
			float density = fbm2(p) * 1.15 - (1.0 - cloud_cover) * 0.85;
			float body = smoothstep(0.0, 0.35, density);
			vec2 toward_sun = sun_dir.xz / max(sun_dir.y, 0.2) * 0.07;
			float shade = clamp((density - (fbm2(p + toward_sun) * 1.15
					- (1.0 - cloud_cover) * 0.85)) * 6.0 + 0.55, 0.15, 1.0);
			vec3 lit = vec3(1.0, 0.96, 0.9) * mix(0.55, 1.15, shade) * clamp(sun_dir.y * 1.6 + 0.25, 0.1, 1.0);
			vec3 grey = vec3(0.28, 0.3, 0.34) * clamp(sun_dir.y + 0.3, 0.1, 1.0);
			vec3 cloud_col = mix(lit, grey, clamp(cloud_dark, 0.0, 1.0));
			air = mix(air, cloud_col + air * 0.25, body * smoothstep(0.01, 0.12, up));
		}
		col = mix(col, air, realism);
	}
	if (LIGHT0_ENABLED) {
		float sun = max(dot(dir, sun_dir), 0.0);
		float disc = smoothstep(0.9993, 0.9998, sun);
		float glow = pow(sun, 48.0) * 0.45 + pow(sun, 6.0) * 0.12;
		col += LIGHT0_COLOR * (disc * 8.0 + glow * (1.0 - realism * 0.6)) * LIGHT0_ENERGY * clear;
	}
	if (night_k > 0.01 && up > -0.02) {
		// stars: a few bright cells on a grid over the sky, twinkling a little
		vec3 cell = floor(dir * 140.0);
		float star = step(0.9985, hash3(cell)) * smoothstep(0.42, 0.05, length(fract(dir * 140.0) - 0.5));
		float twinkle = 0.65 + 0.35 * sin(TIME * 2.5 + hash3(cell + 7.0) * 40.0);
		col += vec3(0.9, 0.95, 1.0) * star * twinkle * night_k * clear * smoothstep(0.0, 0.2, up);
		// the moon: a pale disc and a soft halo
		vec3 moon_axis = normalize(moon_direction);
		float moon = max(dot(dir, moon_axis), 0.0);
		// the phase: the disc is a sphere lit from one side (toward the sun); a point of the disc
		// is lit if its normal faces the light, which is at the angle the sun stands from the moon
		vec3 offset = dir - moon_axis * dot(dir, moon_axis);
		vec3 toward_sun = sun_toward - moon_axis * dot(sun_toward, moon_axis);
		float across = length(offset) / 0.04;
		float along = dot(offset, normalize(toward_sun + 0.0001)) / 0.04;
		float depth = sqrt(max(1.0 - across * across, 0.0));
		float cos_light = 2.0 * moon_lit - 1.0; // 1 full (the sun is behind us), -1 new
		float lit = smoothstep(-0.08, 0.08, along * sqrt(max(1.0 - cos_light * cos_light, 0.0)) + depth * cos_light);
		col += vec3(0.85, 0.9, 1.0) * smoothstep(0.9990, 0.9994, moon) * night_k * clear * 1.4 * (0.04 + 0.96 * lit);
		col += vec3(0.25, 0.3, 0.45) * pow(moon, 90.0) * night_k * clear * moon_lit;
	}
	COLOR = col;
}
