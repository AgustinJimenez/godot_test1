// The clouds' shadow on what lies under them (the ground of the tiles and of the voxels, the water): the same layer the sky and the shell
// draw (planet_cloud_march.gdshaderinc), asked where the ray from the point to the star crosses it.
// cloud_shadow = (strength 0..1, cloud darkness, least cover, 0), cloud_layer = (planet radius, layer floor, depth, 0), cloud_centre = the
// planet's centre in the world, cloud_sun_world = toward the star. PlanetAtmosphere publishes them.
global uniform sampler2D cloud_cover_map : filter_linear, repeat_enable;
global uniform vec4 cloud_shadow;
global uniform vec4 cloud_layer;
global uniform vec3 cloud_centre;
global uniform vec3 cloud_sun_world;
global uniform vec3 cloud_drift_planet;
global uniform mat4 planet_from_world;

float cloud_shadow_hash(vec3 p) {
	p = fract(p * 0.3183099 + vec3(0.71, 0.113, 0.419));
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

float cloud_shadow_noise(vec3 p) {
	vec3 i = floor(p);
	vec3 f = smoothstep(0.0, 1.0, fract(p));
	return mix(mix(mix(cloud_shadow_hash(i), cloud_shadow_hash(i + vec3(1, 0, 0)), f.x),
			mix(cloud_shadow_hash(i + vec3(0, 1, 0)), cloud_shadow_hash(i + vec3(1, 1, 0)), f.x), f.y),
			mix(mix(cloud_shadow_hash(i + vec3(0, 0, 1)), cloud_shadow_hash(i + vec3(1, 0, 1)), f.x),
			mix(cloud_shadow_hash(i + vec3(0, 1, 1)), cloud_shadow_hash(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}

// How much of the star's light the clouds take from the point `from_centre` (world axes, metres from the
// planet's centre): the ray to the star crosses the middle of the layer, and the cloud there (the cloud
// density of planet_cloud_march.gdshaderinc, the coarse octaves) shades the ground under it.
float cloud_shade_at(vec3 from_centre) {
	vec3 sun = normalize(cloud_sun_world);
	float r_mid = cloud_layer.x + cloud_layer.y + cloud_layer.z * 0.35;
	float b = dot(from_centre, sun);
	float c = dot(from_centre, from_centre) - r_mid * r_mid;
	float disc = b * b - c;
	if (disc <= 0.0 || length(from_centre) > r_mid) {
		return 0.0;
	}
	vec3 hit = from_centre + sun * (-b + sqrt(disc));
	vec3 q = mat3(planet_from_world) * hit;
	vec3 d = normalize(q);
	vec2 uv = vec2(atan(d.z, d.x) / TAU + 0.5, 0.5 - asin(clamp(d.y, -1.0, 1.0)) / PI);
	float cover = max(textureLod(cloud_cover_map, uv, 0.0).r, cloud_shadow.z);
	vec3 p = (q + cloud_drift_planet) * 0.0022;
	// the same layers of noise as the clouds themselves (planet_cloud_march.gdshaderinc)
	float shape = cloud_shadow_noise(p * 0.1 + 11.0) * 0.2 + cloud_shadow_noise(p * 0.25 + 23.0) * 0.15
			+ cloud_shadow_noise(p) * 0.4 + cloud_shadow_noise(p * 2.1 + 7.0) * 0.15
			+ cloud_shadow_noise(p * 4.3 + 3.0) * 0.1;
	float body = shape - (1.0 - cover) * 0.75 - 0.12;
	return clamp(body * 3.2, 0.0, 1.0);
}

// What is left of a surface's colour at `from_centre` (world axes, metres from the planet's centre) under the clouds: 1 in the open. The
// direct light is the part the cloud takes: the sky's light stays.
float cloud_shade_keep(vec3 from_centre) {
	if (cloud_shadow.x <= 0.01) {
		return 1.0;
	}
	float sun_up = clamp(dot(normalize(from_centre), normalize(cloud_sun_world)) * 4.0, 0.0, 1.0);
	float shade = cloud_shade_at(from_centre) * cloud_shadow.x * sun_up * (1.0 - cloud_shadow.z); // (a full overcast already dims the sun itself)
	return 1.0 - shade * (0.5 + 0.2 * cloud_shadow.y);
}
