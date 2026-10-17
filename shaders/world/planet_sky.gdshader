shader_type sky;
// A planet's sky, from the physics of its air (PlanetAir has the same maths on the CPU): single
// scattering of the star's light through a spherical atmosphere seen from where the camera really
// is, above the planet's surface. Molecules scatter blue most (a blue day sky, a red low sun, the
// pale haze at the horizon); haze scatters forward round the sun. Rays that leave the atmosphere
// without meeting air see nothing: space is black, with the stars, the moon and the sun. From
// orbit the air shows as the thin bright rim round the planet. The stars and the moon are seen
// wherever the sky is dark enough, so they fade out in the daylight by themselves.

uniform vec3 planet_centre = vec3(0.0, -20000.0, 0.0); // world space
uniform float planet_radius = 20000.0;
uniform float atmosphere_top = 60000.0; // height of the air above the surface, m
uniform float intensity = 22.0;
uniform float air_scale = 1.0; // the planet's radius over the Earth's: the air shrinks with it
uniform vec3 sun_toward = vec3(0.0, 1.0, 0.0); // unit vector from the camera to the sun
uniform vec3 moon_direction = vec3(0.0, -1.0, 0.0);
uniform float moon_lit = 1.0; // 0 new .. 1 full
uniform float star_k = 1.0; // 0 .. 1: how many stars are shown (cloud and glare take them away)

#include "res://shaders/world/planet_cloud_march.gdshaderinc"
uniform float cloud_on = 0.0; // 0 none .. 1 (the shell round the planet draws them from the layer upward)

const vec3 BETA_R = vec3(5.8e-6, 13.5e-6, 33.1e-6);
const float BETA_M = 21e-6;
const float SCALE_R = 8000.0;
const float SCALE_M = 1200.0;

// distance from `origin` along `dir` to the sphere of radius `r` (the far side), or -1 if missed
float far_hit(vec3 origin, vec3 dir, float r) {
	float b = dot(origin, dir);
	float c = dot(origin, origin) - r * r;
	float disc = b * b - c;
	return disc < 0.0 ? -1.0 : -b + sqrt(disc);
}

vec3 scatter(vec3 origin, vec3 dir, vec3 sun, float radius, float top) {
	float b = dot(origin, dir);
	float c_top = dot(origin, origin) - top * top;
	float disc_top = b * b - c_top;
	if (disc_top <= 0.0) {
		return vec3(0.0); // the ray misses the air altogether
	}
	float t_near = max(-b - sqrt(disc_top), 0.0); // 0 inside the air
	float t_far = -b + sqrt(disc_top);
	float c_ground = dot(origin, origin) - radius * radius;
	float disc_ground = b * b - c_ground;
	if (disc_ground > 0.0 && (-b - sqrt(disc_ground)) > 0.0) {
		t_far = min(t_far, -b - sqrt(disc_ground)); // the ground ends the ray
	}
	if (t_far <= t_near) {
		return vec3(0.0);
	}
	const int STEPS = 14;
	float step_len = (t_far - t_near) / float(STEPS);
	float mu = dot(dir, sun);
	float phase_r = 3.0 / (16.0 * PI) * (1.0 + mu * mu);
	float g = 0.76;
	float phase_m = 3.0 / (8.0 * PI) * ((1.0 - g * g) * (1.0 + mu * mu))
			/ ((2.0 + g * g) * pow(1.0 + g * g - 2.0 * g * mu, 1.5));
	vec3 sum_r = vec3(0.0);
	vec3 sum_m = vec3(0.0);
	float depth_r = 0.0;
	float depth_m = 0.0;
	for (int i = 0; i < STEPS; i++) {
		vec3 p = origin + dir * (t_near + (float(i) + 0.5) * step_len);
		float h = length(p) - radius;
		float hr = exp(-h / (SCALE_R * air_scale)) * step_len;
		float hm = exp(-h / (SCALE_M * air_scale)) * step_len;
		depth_r += hr;
		depth_m += hm;
		// the light reaching this point from the sun (blocked if the planet is in the way)
		float bs = dot(p, sun);
		bool blocked = false;
		if (bs < 0.0 && dot(p, p) - bs * bs < radius * radius) {
			blocked = true;
		}
		if (!blocked) {
			float sun_far = max(far_hit(p, sun, top), 0.0);
			float sun_step = sun_far / 5.0;
			float sun_r = 0.0;
			float sun_m = 0.0;
			for (int j = 0; j < 5; j++) {
				vec3 q = p + sun * (float(j) + 0.5) * sun_step;
				float hq = length(q) - radius;
				sun_r += exp(-hq / (SCALE_R * air_scale)) * sun_step;
				sun_m += exp(-hq / (SCALE_M * air_scale)) * sun_step;
			}
			vec3 tau = (BETA_R * (depth_r + sun_r) + BETA_M * 1.1 * (depth_m + sun_m)) / air_scale;
			vec3 attenuation = exp(-tau);
			sum_r += attenuation * hr;
			sum_m += attenuation * hm;
		}
	}
	return (sum_r * BETA_R * phase_r + sum_m * BETA_M * phase_m) / air_scale;
}

void sky() {
	vec3 dir = normalize(EYEDIR);
	vec3 origin = POSITION - planet_centre;
	float radius = planet_radius;
	float top = planet_radius + atmosphere_top;
	vec3 sun = normalize(sun_toward);
	vec3 col = intensity * star_tint * scatter(origin, dir, sun, radius, top);

	// the sun: a bright disc (what the air has not taken from it, the light of the sun on the
	// ground, LIGHT0, is already that) behind the planet's own limb
	bool behind_planet = false;
	{
		float bb = dot(origin, dir);
		if (bb < 0.0 && dot(origin, origin) - bb * bb < radius * radius) {
			behind_planet = true;
		}
	}
	if (LIGHT0_ENABLED && !behind_planet) {
		float s = max(dot(dir, sun), 0.0);
		float disc = smoothstep(0.9993, 0.9998, s);
		float glow = pow(s, 48.0) * 0.12;
		col += LIGHT0_COLOR * (disc * 8.0 + glow) * LIGHT0_ENERGY;
	}

	// the clouds, in front of the sky and the sun and the stars
	float behind_clouds = 1.0;
	if (!AT_CUBEMAP_PASS && cloud_on > 0.01 && !behind_planet) {
		vec4 cloud = cloud_march(origin, dir, sun, radius, 1.0e9);
		col = mix(col, col * cloud.a + cloud.rgb, cloud_on);
		behind_clouds = mix(1.0, cloud.a, cloud_on);
	}

	// stars and the moon, wherever the sky is dark enough to see them
	float luma = dot(col, vec3(0.33));
	float dark = exp(-luma * 14.0) * star_k * behind_clouds;
	if (!behind_planet && dark > 0.01) {
		vec3 cell = floor(dir * 140.0);
		float star = step(0.9985, hash3(cell)) * smoothstep(0.42, 0.05, length(fract(dir * 140.0) - 0.5));
		float twinkle = 0.65 + 0.35 * sin(TIME * 2.5 + hash3(cell + 7.0) * 40.0);
		col += vec3(0.9, 0.95, 1.0) * star * twinkle * dark;
		vec3 moon_axis = normalize(moon_direction);
		float moon = max(dot(dir, moon_axis), 0.0);
		vec3 offset = dir - moon_axis * dot(dir, moon_axis);
		vec3 toward_sun = sun - moon_axis * dot(sun, moon_axis);
		float across = length(offset) / 0.04;
		float along = dot(offset, normalize(toward_sun + 0.0001)) / 0.04;
		float depth = sqrt(max(1.0 - across * across, 0.0));
		float cos_light = 2.0 * moon_lit - 1.0; // 1 full (the sun is behind us), -1 new
		float lit = smoothstep(-0.08, 0.08, along * sqrt(max(1.0 - cos_light * cos_light, 0.0)) + depth * cos_light);
		float seen = exp(-luma * 2.0); // the moon is washed out of a bright sky
		col += vec3(0.85, 0.9, 1.0) * smoothstep(0.9990, 0.9994, moon) * seen * 1.4 * (0.04 + 0.96 * lit);
		col += vec3(0.25, 0.3, 0.45) * pow(moon, 90.0) * dark * moon_lit;
	}
	COLOR = col;
}
