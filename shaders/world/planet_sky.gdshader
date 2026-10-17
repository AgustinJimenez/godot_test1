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

// the clouds: a layer of real volume, marched through, lit by the sun
global uniform mat4 planet_from_world;
uniform sampler2D cover_map : filter_linear, repeat_enable, hint_default_black;
uniform float cloud_on = 0.0; // 0 none .. 1 (the layer fades out as the viewer climbs through it)
uniform float cloud_floor = 450.0; // m above the planet's radius where the layer begins
uniform float cloud_depth = 700.0; // m thick
uniform vec3 cloud_drift = vec3(0.0); // m, in the planet's frame: where the wind has carried them
uniform vec3 cloud_ambient = vec3(0.2); // the light of the sky on them
uniform float cloud_dark = 0.0; // 0 white .. 1 storm grey
uniform float cloud_least = 0.0; // the cover is at least this (a forced overcast weather)

const vec3 BETA_R = vec3(5.8e-6, 13.5e-6, 33.1e-6);
const float BETA_M = 21e-6;
const float SCALE_R = 8000.0;
const float SCALE_M = 1200.0;

float hash3(vec3 p) {
	p = fract(p * 0.3183099 + vec3(0.71, 0.113, 0.419));
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

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

float value_noise(vec3 p) {
	vec3 i = floor(p);
	vec3 f = smoothstep(0.0, 1.0, fract(p));
	return mix(mix(mix(hash3(i), hash3(i + vec3(1, 0, 0)), f.x),
			mix(hash3(i + vec3(0, 1, 0)), hash3(i + vec3(1, 1, 0)), f.x), f.y),
			mix(mix(hash3(i + vec3(0, 0, 1)), hash3(i + vec3(1, 0, 1)), f.x),
			mix(hash3(i + vec3(0, 1, 1)), hash3(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}

// how much cloud there is at `q` (planet frame, from its centre) `h` of the way up the layer:
// the cover picture of the planet's weather says where the sky is full, the noise shapes the
// billows, the layer is flat below and rounded on top
float cloud_density(vec3 q, float h) {
	vec3 d = normalize(q);
	vec2 uv = vec2(atan(d.z, d.x) / TAU + 0.5, 0.5 - asin(clamp(d.y, -1.0, 1.0)) / PI);
	float cover = max(textureLod(cover_map, uv, 0.0).r, cloud_least);
	vec3 p = (q + cloud_drift) * 0.0022; // one unit is some 450 m
	float shape = value_noise(p) * 0.55 + value_noise(p * 2.1 + 7.0) * 0.3
			+ value_noise(p * 4.3 + 3.0) * 0.15;
	float profile = smoothstep(0.0, 0.1, h) * (1.0 - smoothstep(0.55, 1.0, h));
	float body = shape - (1.0 - cover) * 0.75 - 0.12;
	body -= (1.0 - value_noise(p * 9.0 + 13.0)) * 0.12 * (0.3 + h); // the ragged edges
	return clamp(body * 3.2, 0.0, 1.0) * profile;
}

float henyey_greenstein(float mu, float g) {
	return (1.0 - g * g) / pow(1.0 + g * g - 2.0 * g * mu, 1.5);
}

// the clouds seen along `dir` from `origin` (from the planet's centre): rgb is the light they send
// (already faded into the haze with distance), a how much of what is behind them still shows
vec4 clouds(vec3 origin, vec3 dir, vec3 sun, vec3 sun_light, float radius) {
	float r0 = radius + cloud_floor;
	float r1 = r0 + cloud_depth;
	float rc = length(origin);
	float b = dot(origin, dir);
	if (b < 0.0 && b * b - (rc * rc - radius * radius) > 0.0) {
		return vec4(0.0, 0.0, 0.0, 1.0); // the planet is in the way
	}
	float disc1 = b * b - (rc * rc - r1 * r1);
	if (disc1 <= 0.0 || rc > r1) {
		return vec4(0.0, 0.0, 0.0, 1.0);
	}
	float t0 = 0.0;
	if (rc < r0) {
		float disc0 = b * b - (rc * rc - r0 * r0);
		t0 = -b + sqrt(max(disc0, 0.0));
	}
	float t1 = min(-b + sqrt(disc1), t0 + 9000.0);
	if (t0 > 30000.0 || t1 <= t0) {
		return vec4(0.0, 0.0, 0.0, 1.0);
	}
	mat3 rot = mat3(planet_from_world);
	const int STEPS = 20;
	float step_len = (t1 - t0) / float(STEPS);
	float sigma = 0.022 * (1.0 + cloud_dark * 0.8);
	float light_step = cloud_depth * 0.18;
	float mu = dot(dir, sun);
	float phase = mix(henyey_greenstein(mu, 0.55), henyey_greenstein(mu, -0.25), 0.4) * 0.5;
	float jitter = hash3(dir * 3331.0);
	vec3 col = vec3(0.0);
	float seen = 1.0;
	for (int i = 0; i < STEPS; i++) {
		float t = t0 + (float(i) + jitter) * step_len;
		vec3 p = origin + dir * t;
		float h = (length(p) - r0) / cloud_depth;
		if (h < 0.0 || h > 1.0) {
			continue;
		}
		float density = cloud_density(rot * p, h);
		if (density < 0.004) {
			continue;
		}
		float depth_to_sun = 0.0;
		for (int j = 0; j < 3; j++) {
			vec3 pl = p + sun * (float(j) + 0.5) * light_step;
			depth_to_sun += cloud_density(rot * pl, (length(pl) - r0) / cloud_depth) * light_step;
		}
		float direct = mix(exp(-depth_to_sun * sigma), exp(-depth_to_sun * sigma * 0.25), 0.35);
		vec3 lit = sun_light * direct * (0.25 + phase) * (1.0 - cloud_dark * 0.55);
		vec3 shade = cloud_ambient * mix(0.55, 1.0, h);
		float opacity = 1.0 - exp(-density * sigma * step_len);
		col += seen * opacity * (lit + shade);
		seen *= 1.0 - opacity;
		if (seen < 0.02) {
			break;
		}
	}
	float haze = exp(-(t0 + (t1 - t0) * 0.5) / 9000.0); // far clouds melt into the air
	return vec4(col * haze, seen + (1.0 - haze) * (1.0 - seen));
}

void sky() {
	vec3 dir = normalize(EYEDIR);
	vec3 origin = POSITION - planet_centre;
	float radius = planet_radius;
	float top = planet_radius + atmosphere_top;
	vec3 sun = normalize(sun_toward);
	vec3 col = intensity * scatter(origin, dir, sun, radius, top);

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
		vec3 sun_light = LIGHT0_ENABLED ? LIGHT0_COLOR * LIGHT0_ENERGY : vec3(0.0);
		vec4 cloud = clouds(origin, dir, sun, sun_light, radius);
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
