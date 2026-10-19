// The clouds of a planet as a layer of real volume, marched through and lit by the star: shared by
// the sky (planet_sky.gdshader, seen from under and in the layer) and the shell round the planet
// (planet_clouds.gdshader, seen from in and above the layer, from the ground to orbit), so both draw
// the same clouds. Positions are metres from the planet's centre, in the world's axes.

global uniform mat4 planet_from_world;
uniform sampler2D cover_map : filter_linear, repeat_enable, hint_default_black;
uniform float cloud_steps_max = 16.0; // the most samples a ray takes (the graphics setting)
uniform float clouds_off = 0.0; // 1: the debug switch has the clouds hidden
uniform float cloud_floor = 450.0; // m above the planet's radius where the layer begins
uniform float cloud_depth = 700.0; // m thick
uniform vec3 cloud_drift = vec3(0.0); // m, in the planet's frame: where the wind has carried them
uniform float cloud_dark = 0.0; // 0 white .. 1 storm grey
uniform float cloud_least = 0.0; // the cover is at least this (a forced overcast weather)
uniform vec3 star_tint = vec3(1.0); // the star's light against the Sun's
uniform float cloud_sun = 1.35; // the light energy of the unobscured star
uniform float cloud_path = 0.11; // the sun's path through this planet's air against the Earth's

float hash3(vec3 p) {
	p = fract(p * 0.3183099 + vec3(0.71, 0.113, 0.419));
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

float value_noise(vec3 p) {
	vec3 i = floor(p);
	vec3 f = smoothstep(0.0, 1.0, fract(p));
	return mix(mix(mix(hash3(i), hash3(i + vec3(1, 0, 0)), f.x),
			mix(hash3(i + vec3(0, 1, 0)), hash3(i + vec3(1, 1, 0)), f.x), f.y),
			mix(mix(hash3(i + vec3(0, 0, 1)), hash3(i + vec3(1, 0, 1)), f.x),
			mix(hash3(i + vec3(0, 1, 1)), hash3(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}

// how much of a noise layer whose features are `wavelength` metres across a pixel `px` metres wide
// can show: a layer finer than the pixels is only its average (it would be a speckle)
float resolved(float wavelength, float px) {
	return smoothstep(px * 6.0, px * 24.0, wavelength); // (a dozen pixels across to show)
}

// how much cloud there is at `q` (planet frame, from its centre) `h` of the way up the layer:
// the cover picture of the planet's weather says where the sky is full, the noise shapes the
// billows, the layer is flat below and rounded on top. The billows are layers of noise of fixed
// sizes, from 4.5 km down to 100 m, the same clouds near and far: `px` is the width of a pixel at
// this distance, and the layers smaller than that fade to their average (from orbit only the big
// billows are left; the scale of the noise never changes with the distance, which bent it into rings)
float cloud_density(vec3 q, float h, float px) {
	vec3 d = normalize(q);
	vec2 uv = vec2(atan(d.z, d.x) / TAU + 0.5, 0.5 - asin(clamp(d.y, -1.0, 1.0)) / PI);
	float cover = max(textureLod(cover_map, uv, 0.0).r, cloud_least);
	vec3 p = (q + cloud_drift) * 0.0022; // one unit is some 450 m
	float shape = mix(0.5, value_noise(p * 0.1 + 11.0), resolved(4500.0, px)) * 0.2;
	shape += mix(0.5, value_noise(p * 0.25 + 23.0), resolved(1800.0, px)) * 0.15;
	shape += mix(0.5, value_noise(p), resolved(450.0, px)) * 0.4;
	shape += mix(0.5, value_noise(p * 2.1 + 7.0), resolved(214.0, px)) * 0.15;
	shape += mix(0.5, value_noise(p * 4.3 + 3.0), resolved(105.0, px)) * 0.1;
	float profile = smoothstep(0.0, 0.1, h) * (1.0 - smoothstep(0.55, 1.0, h));
	float body = shape - (1.0 - cover) * 0.75 - 0.12;
	float ragged = resolved(50.0, px);
	if (ragged > 0.01) {
		body -= (1.0 - value_noise(p * 9.0 + 13.0)) * 0.12 * (0.3 + h) * ragged; // the ragged edges
	}
	// the edges are crisp near and soft far: from orbit the cover picture itself is the edge, and a steep
	// edge would cut it into hard white blobs
	float gain = mix(3.2, 1.0, smoothstep(5.0, 150.0, px));
	return clamp(body * gain, 0.0, 1.0) * profile;
}

float henyey_greenstein(float mu, float g) {
	return (1.0 - g * g) / pow(1.0 + g * g - 2.0 * g * mu, 1.5);
}

// the star's light at a cloud where the star stands `height` above the horizon (the sine of its
// elevation): white high up, orange and red low down (the air it crosses), gone at night
vec3 cloud_sun_light(float height) {
	float h = max(height, -0.02);
	float mass = 1.0 / (h + 0.50572 * pow(96.07995 - degrees(acos(h)), -1.6364)); // Kasten-Young
	vec3 tau = vec3(0.074, 0.136, 0.293) * mass * cloud_path;
	return cloud_sun * star_tint * exp(-tau) * smoothstep(-0.14, -0.02, height);
}

// the light of the sky on a cloud, blue by day, a trace of starlight at night
vec3 cloud_sky_light(float height) {
	return vec3(0.28, 0.42, 0.7) * smoothstep(-0.2, 0.3, height) + vec3(0.012, 0.015, 0.03);
}

// the clouds seen along `dir` from `origin`: rgb is the light they send (faded into the haze with
// distance), a how much of what is behind them still shows. `t_limit` is how far the way is free
// (the ground of the scene, for the shell).
vec4 cloud_march(vec3 origin, vec3 dir, vec3 sun, float radius, float t_limit) {
	vec4 none = vec4(0.0, 0.0, 0.0, 1.0);
	if (clouds_off > 0.5) {
		return none;
	}
	float r0 = radius + cloud_floor;
	float r1 = r0 + cloud_depth;
	float rc = length(origin);
	float b = dot(origin, dir);
	// how far the horizon of the layer's floor is: the fades below are for a view from the ground,
	// and from high up the whole cap of the planet in sight has to keep its clouds
	float horizon = sqrt(max(rc * rc - r0 * r0, 0.0));
	float disc1 = b * b - (rc * rc - r1 * r1);
	if (disc1 <= 0.0) {
		return none;
	}
	float disc0 = b * b - (rc * rc - r0 * r0);
	float t_out1 = -b + sqrt(disc1);
	float t0 = 0.0;
	float t1 = t_out1;
	if (rc > r1) { // above the layer: it begins where the ray comes in
		t0 = -b - sqrt(disc1);
		if (disc0 > 0.0 && -b - sqrt(disc0) > t0) {
			t1 = -b - sqrt(disc0); // looking down: the way ends at the layer's floor
		}
	} else if (rc >= r0) { // in the layer
		if (disc0 > 0.0 && -b - sqrt(disc0) > 0.0) {
			t1 = -b - sqrt(disc0);
		}
	} else { // under the layer: it begins where the ray reaches its floor
		t0 = -b + sqrt(max(disc0, 0.0));
	}
	// the planet itself ends the way
	float disc_ground = b * b - (rc * rc - radius * radius);
	if (disc_ground > 0.0 && -b - sqrt(disc_ground) > 0.0) {
		t1 = min(t1, -b - sqrt(disc_ground));
	}
	t1 = min(min(t1, t_limit), t0 + 12000.0);
	if (t0 > 40000.0 + horizon || t1 <= t0 || t_out1 < 0.0) {
		return none;
	}
	mat3 rot = mat3(planet_from_world);
	// clear sky along the whole stretch: nothing to march through
	float seen_cover = 0.0;
	for (int k = 0; k < 3; k++) {
		vec3 d = normalize(rot * (origin + dir * mix(t0, t1, float(k) * 0.5)));
		vec2 uv = vec2(atan(d.z, d.x) / TAU + 0.5, 0.5 - asin(clamp(d.y, -1.0, 1.0)) / PI);
		seen_cover = max(seen_cover, textureLod(cover_map, uv, 0.0).r);
	}
	if (max(seen_cover, cloud_least) < 0.04) {
		return none;
	}
	const int STEPS = 16;
	int steps = int(clamp((t1 - t0) / 70.0, 4.0, min(float(STEPS), cloud_steps_max))); // short ways need fewer
	float step_len = (t1 - t0) / float(steps);
	const float PIXEL = 0.0011; // the width of a pixel at a metre's distance (60 degrees, 1080 lines)
	float sigma = 0.022 * (1.0 + cloud_dark * 0.8);
	float light_step = cloud_depth * 0.25;
	float mu = dot(dir, sun);
	float phase = mix(henyey_greenstein(mu, 0.55), henyey_greenstein(mu, -0.25), 0.4) * 0.5;
	float jitter = hash3(dir * 3331.0);
	vec3 col = vec3(0.0);
	float seen = 1.0;
	for (int i = 0; i < STEPS; i++) {
		if (i >= steps) {
			break;
		}
		float t = t0 + (float(i) + jitter) * step_len;
		vec3 p = origin + dir * t;
		float h = (length(p) - r0) / cloud_depth;
		if (h < 0.0 || h > 1.0) {
			continue;
		}
		// the far end of the way thins out (a hard end to the march would show as an edge)
		float density = cloud_density(rot * p, h, t * PIXEL) * (1.0 - smoothstep(5000.0 + horizon, 11000.0 + horizon, t));
		if (density < 0.004) {
			continue;
		}
		float depth_to_sun = 0.0;
		for (int j = 0; j < 2; j++) {
			vec3 pl = p + sun * (float(j) + 0.5) * light_step;
			depth_to_sun += cloud_density(rot * pl, (length(pl) - r0) / cloud_depth, max(t * PIXEL, 20.0)) * light_step;
		}
		float direct = mix(exp(-depth_to_sun * sigma), exp(-depth_to_sun * sigma * 0.25), 0.35);
		float height = dot(normalize(p), sun);
		vec3 lit = cloud_sun_light(height) * direct * (0.45 + phase) * (1.0 - cloud_dark * 0.55);
		vec3 shade = cloud_sky_light(height) * mix(0.55, 1.0, h);
		float opacity = 1.0 - exp(-density * sigma * step_len);
		col += seen * opacity * (lit + shade);
		seen *= 1.0 - opacity;
		if (seen < 0.02) {
			break;
		}
	}
	// far clouds melt into the air: along the way there is little of it high up
	float mid = t0 + (t1 - t0) * 0.5;
	float air_there = exp(-max(length(origin + dir * mid) - radius, 0.0) / 2500.0);
	float air_path = mid;
	if (rc > r1) {
		air_path = min(mid, 9000.0); // above the layer, only the lower air is between
	}
	float haze = exp(-air_path / 9000.0 * air_there);
	return vec4(col * haze, seen + (1.0 - haze) * (1.0 - seen));
}
