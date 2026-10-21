// Sand (task 078): wind ripples and glitter for the ground shader. Needs hash3 (planet_stones.gdshaderinc) before it.
//
// The ripples are one coherent field of long lines. The ground is cut into cells (2.56 m, so that 1024 m is a whole number of them:
// the planet's coordinates wrap every 1024 m and a pattern may not jump there). Each cell has its own wave (a direction across the
// wind, turned a little, a wavelength and a start), and a point blends the PHASES of the eight cells round it, not their heights: the
// crests run on unbroken from cell to cell and only bend and drift in spacing, as real ripples do, with a fork now and then where
// the spacing drifts far. Each ripple is asymmetric: a gentle windward side (about 9 degrees) and a steep downwind side (about 23).

uniform float sand_ripples : hint_range(0.0, 1.0) = 1.0; // how strong the ripples are (0: none)
uniform float sand_ripple_height = 0.02; // m, crest above trough
uniform float sand_ripple_length = 0.24; // m between crests (each cell 0.85 .. 1.15 of it)
uniform float sand_glitter : hint_range(0.0, 1.0) = 0.6; // the grains that flash in the sun
uniform float sand_swell_height = 0.05; // m: the broad hummocks of the sand between the ripples and the dunes (1-3 m across), crest above hollow
uniform float sand_wind_turn = 0.0; // radians: turns the wind (the lab; the planet's own wind later)

const float SAND_CELL = 2.56;

// The height of the broad, irregular swell of the sand at planet position `p` (metres, about -swell .. +swell): two noises, 1.28 m and
// 0.51 m across (1024 m is a whole number of them, so there is no jump at the wrap), the larger one the stronger.
float sand_swell(vec3 p) {
	float n = noise3(p / 1.28, 800.0) * 0.65 + noise3(p / 0.512 + 5.3, 2000.0) * 0.35;
	return (n - 0.5) * 2.0 * sand_swell_height;
}

// Height 0..1 across one period of a ripple, x in 0..1: a long rise to the crest at 0.72, a short fall.
float sand_rise(float x) {
	return x < 0.72 ? smoothstep(0.0, 0.72, x) : 1.0 - smoothstep(0.72, 1.0, x);
}

// Its slope: d height / d x.
float sand_slope(float x) {
	if (x < 0.72) {
		float t = x / 0.72;
		return 6.0 * t * (1.0 - t) / 0.72;
	}
	float t = (x - 0.72) / 0.28;
	return -6.0 * t * (1.0 - t) / 0.28;
}

// The tilt the ripples give the light at planet position `p` (a vector in the tangent plane, planet axes, to add to the normal
// like the other layers' tilts) and `height` (0..1, for a touch of shade). `up` is the way up. The wind blows along the parallels
// (east-west); the crests run across it.
vec3 sand_ripple_tilt(vec3 p, vec3 up, out float height) {
	vec3 east = cross(vec3(0.0, 1.0, 0.0), up);
	if (length(east) < 0.2) {
		east = cross(vec3(1.0, 0.0, 0.0), up);
	}
	east = normalize(east);
	vec3 north = cross(up, east);
	vec3 scaled = p / SAND_CELL;
	vec3 base = floor(scaled);
	vec3 f = fract(scaled);
	vec3 s = f * f * (3.0 - 2.0 * f); // (eased, so that the spacing does not kink at a cell's edge)
	vec3 ds = 6.0 * f * (1.0 - f) / SAND_CELL;
	float phase = 0.0; // in ripples (whole numbers are crests' places)
	vec3 slope = vec3(0.0); // the change of phase with the ground position
	float amplitude = 0.0;
	for (int i = 0; i < 8; i++) {
		vec3 corner = vec3(mod(float(i), 2.0), mod(floor(float(i) * 0.5), 2.0), floor(float(i) * 0.25));
		vec3 mixing = mix(vec3(1.0) - s, s, corner);
		float w = mixing.x * mixing.y * mixing.z;
		vec3 sign_c = corner * 2.0 - 1.0;
		vec3 dw = sign_c * ds * vec3(mixing.y * mixing.z, mixing.x * mixing.z, mixing.x * mixing.y);
		vec3 cell = base + corner;
		vec3 id = mod(cell, 400.0);
		float h1 = hash3(id + 1.0);
		float h2 = hash3(id + 7.3);
		float h3 = hash3(id + 13.1);
		float turn = (h1 - 0.5) * 0.4 + sand_wind_turn;
		vec3 across = east * cos(turn) + north * sin(turn);
		vec3 wave = across / (sand_ripple_length * (0.85 + 0.3 * h2)); // ripples per metre, along `across`
		float here = dot(p - cell * SAND_CELL, wave) + h3 * 2.0;
		phase += here * w;
		slope += wave * w + dw * here;
		amplitude += sand_ripple_height * (0.7 + 0.6 * h3) * w;
	}
	slope -= up * dot(slope, up); // (along the ground)
	float x = fract(phase);
	height = sand_rise(x);
	return -slope * (sand_slope(x) * amplitude);
}

// The flash of the grains in the sun: two grids of round flakes (2.5 mm and 8 mm), a fifth of the cells with a flake, each its own small
// mirror turned a random way; it shows when that mirror throws the sun at the eye. Fixed to the ground, so it twinkles as the eye
// moves and does not crawl. `h_view` is the half vector (sun + eye) and `n_view` the surface normal, both in view space, `dist` the
// metres to the eye: a grid finer than a pixel is left out (it would only be noise).
float sand_glints(vec3 p, vec3 n_view, vec3 h_view, float dist) {
	float total = 0.0;
	float size[2] = float[2](0.0025, 0.008);
	for (int g = 0; g < 2; g++) {
		float seen = smoothstep(0.35, 1.2, size[g] / (max(dist, 0.05) * 0.0015));
		if (seen < 0.01) {
			continue;
		}
		vec3 cell = floor(p / size[g]);
		vec3 id = mod(cell, 1024.0 / size[g]);
		float here = hash3(id + float(g) * 19.0);
		vec3 off = fract(p / size[g]) - 0.5 - (vec3(hash3(id + 1.3), hash3(id + 2.9), hash3(id + 4.7)) - 0.5) * 0.4;
		if (here > 0.8 && length(off) < 0.32) { // (a round flake, not a square)
			vec3 turned = vec3(hash3(id + 3.1), hash3(id + 5.7), hash3(id + 9.3)) * 2.0 - 1.0;
			vec3 flake = normalize(n_view + turned * 0.7);
			total += pow(max(dot(flake, h_view), 0.0), 700.0) * seen;
		}
	}
	return total;
}
