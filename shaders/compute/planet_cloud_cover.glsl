#[compute]
#version 450

// The planet's cloud cover for every pixel of a map picture, on the GPU: the same maths as PlanetCrustNative::cloud_field
// (and PlanetWeather.cloud_cells), with FastNoiseLite's OpenSimplex2S 3D noise and its fractal ported line by line so the
// pattern is the CPU's. One thread per pixel; the result is the cover (0..1) of that pixel.

layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;

layout(set = 0, binding = 0, std430) restrict writeonly buffer OutBuffer {
	float cover[];
};
layout(set = 0, binding = 1, std430) restrict readonly buffer MacroBuffer {
	float macro_height[]; // the ground (m) of every pixel: its sign says land or sea
};
layout(set = 0, binding = 2, std430) restrict readonly buffer NowBuffer {
	float now_grid[]; // the temperature grid at this moment (gw x gh)
};
layout(set = 0, binding = 3, std430) restrict readonly buffer MeanBuffer {
	float mean_grid[]; // the year's mean temperature grid (gw x gh)
};
layout(set = 0, binding = 4, std430) restrict readonly buffer RainBuffer {
	float rain_grid[]; // the rain (cw x ch)
};
layout(set = 0, binding = 5, std430) restrict readonly buffer FloatParams {
	float p[];
};
layout(set = 0, binding = 6, std430) restrict readonly buffer IntParams {
	int q[];
};

const float PI = 3.14159265358979;
const float TAU = 6.28318530717959;
const uint PRIME_X = 501125321u;
const uint PRIME_Y = 1136930381u;
const uint PRIME_Z = 1720413743u;

const float GRADIENTS[256] = float[256](
	0.0, 1.0, 1.0, 0.0, 0.0, -1.0, 1.0, 0.0, 0.0, 1.0, -1.0, 0.0, 0.0, -1.0, -1.0, 0.0,
	1.0, 0.0, 1.0, 0.0, -1.0, 0.0, 1.0, 0.0, 1.0, 0.0, -1.0, 0.0, -1.0, 0.0, -1.0, 0.0,
	1.0, 1.0, 0.0, 0.0, -1.0, 1.0, 0.0, 0.0, 1.0, -1.0, 0.0, 0.0, -1.0, -1.0, 0.0, 0.0,
	0.0, 1.0, 1.0, 0.0, 0.0, -1.0, 1.0, 0.0, 0.0, 1.0, -1.0, 0.0, 0.0, -1.0, -1.0, 0.0,
	1.0, 0.0, 1.0, 0.0, -1.0, 0.0, 1.0, 0.0, 1.0, 0.0, -1.0, 0.0, -1.0, 0.0, -1.0, 0.0,
	1.0, 1.0, 0.0, 0.0, -1.0, 1.0, 0.0, 0.0, 1.0, -1.0, 0.0, 0.0, -1.0, -1.0, 0.0, 0.0,
	0.0, 1.0, 1.0, 0.0, 0.0, -1.0, 1.0, 0.0, 0.0, 1.0, -1.0, 0.0, 0.0, -1.0, -1.0, 0.0,
	1.0, 0.0, 1.0, 0.0, -1.0, 0.0, 1.0, 0.0, 1.0, 0.0, -1.0, 0.0, -1.0, 0.0, -1.0, 0.0,
	1.0, 1.0, 0.0, 0.0, -1.0, 1.0, 0.0, 0.0, 1.0, -1.0, 0.0, 0.0, -1.0, -1.0, 0.0, 0.0,
	0.0, 1.0, 1.0, 0.0, 0.0, -1.0, 1.0, 0.0, 0.0, 1.0, -1.0, 0.0, 0.0, -1.0, -1.0, 0.0,
	1.0, 0.0, 1.0, 0.0, -1.0, 0.0, 1.0, 0.0, 1.0, 0.0, -1.0, 0.0, -1.0, 0.0, -1.0, 0.0,
	1.0, 1.0, 0.0, 0.0, -1.0, 1.0, 0.0, 0.0, 1.0, -1.0, 0.0, 0.0, -1.0, -1.0, 0.0, 0.0,
	0.0, 1.0, 1.0, 0.0, 0.0, -1.0, 1.0, 0.0, 0.0, 1.0, -1.0, 0.0, 0.0, -1.0, -1.0, 0.0,
	1.0, 0.0, 1.0, 0.0, -1.0, 0.0, 1.0, 0.0, 1.0, 0.0, -1.0, 0.0, -1.0, 0.0, -1.0, 0.0,
	1.0, 1.0, 0.0, 0.0, -1.0, 1.0, 0.0, 0.0, 1.0, -1.0, 0.0, 0.0, -1.0, -1.0, 0.0, 0.0,
	1.0, 1.0, 0.0, 0.0, 0.0, -1.0, 1.0, 0.0, -1.0, 1.0, 0.0, 0.0, 0.0, -1.0, -1.0, 0.0
);

float grad_coord(uint seed, uint xp, uint yp, uint zp, vec3 d) {
	uint h = (seed ^ xp ^ yp ^ zp) * 0x27d4eb2du;
	int hash = int(h);
	hash ^= hash >> 15;
	hash &= 63 << 2;
	return d.x * GRADIENTS[hash] + d.y * GRADIENTS[hash | 1] + d.z * GRADIENTS[hash | 2];
}

float quartic(float a) {
	return (a * a) * (a * a);
}

// FastNoiseLite::SingleOpenSimplex2S (3D)
float open_simplex_2s(int seed_in, vec3 pos) {
	int fi = int(floor(pos.x));
	int fj = int(floor(pos.y));
	int fk = int(floor(pos.z));
	float xi = pos.x - float(fi);
	float yi = pos.y - float(fj);
	float zi = pos.z - float(fk);
	uint i = uint(fi) * PRIME_X;
	uint j = uint(fj) * PRIME_Y;
	uint k = uint(fk) * PRIME_Z;
	uint seed = uint(seed_in);
	uint seed2 = uint(seed_in + 1293373);

	int xn = int(-0.5 - xi);
	int yn = int(-0.5 - yi);
	int zn = int(-0.5 - zi);
	uint xm = uint(xn);
	uint ym = uint(yn);
	uint zm = uint(zn);

	float x0 = xi + float(xn);
	float y0 = yi + float(yn);
	float z0 = zi + float(zn);
	float a0 = 0.75 - x0 * x0 - y0 * y0 - z0 * z0;
	float value = quartic(a0) * grad_coord(seed, i + (xm & PRIME_X), j + (ym & PRIME_Y), k + (zm & PRIME_Z), vec3(x0, y0, z0));

	float x1 = xi - 0.5;
	float y1 = yi - 0.5;
	float z1 = zi - 0.5;
	float a1 = 0.75 - x1 * x1 - y1 * y1 - z1 * z1;
	value += quartic(a1) * grad_coord(seed2, i + PRIME_X, j + PRIME_Y, k + PRIME_Z, vec3(x1, y1, z1));

	int xs = xn | 1;
	int ys = yn | 1;
	int zs = zn | 1;
	float xa0 = float(xs << 1) * x1;
	float ya0 = float(ys << 1) * y1;
	float za0 = float(zs << 1) * z1;
	float xa1 = float(-2 - (xn << 2)) * x1 - 1.0;
	float ya1 = float(-2 - (yn << 2)) * y1 - 1.0;
	float za1 = float(-2 - (zn << 2)) * z1 - 1.0;

	bool skip5 = false;
	float a2 = xa0 + a0;
	if (a2 > 0.0) {
		value += quartic(a2) * grad_coord(seed, i + (~xm & PRIME_X), j + (ym & PRIME_Y), k + (zm & PRIME_Z), vec3(x0 - float(xs), y0, z0));
	} else {
		float a3 = ya0 + za0 + a0;
		if (a3 > 0.0) {
			value += quartic(a3) * grad_coord(seed, i + (xm & PRIME_X), j + (~ym & PRIME_Y), k + (~zm & PRIME_Z), vec3(x0, y0 - float(ys), z0 - float(zs)));
		}
		float a4 = xa1 + a1;
		if (a4 > 0.0) {
			value += quartic(a4) * grad_coord(seed2, i + (xm & (PRIME_X * 2u)), j + PRIME_Y, k + PRIME_Z, vec3(float(xs) + x1, y1, z1));
			skip5 = true;
		}
	}

	bool skip9 = false;
	float a6 = ya0 + a0;
	if (a6 > 0.0) {
		value += quartic(a6) * grad_coord(seed, i + (xm & PRIME_X), j + (~ym & PRIME_Y), k + (zm & PRIME_Z), vec3(x0, y0 - float(ys), z0));
	} else {
		float a7 = xa0 + za0 + a0;
		if (a7 > 0.0) {
			value += quartic(a7) * grad_coord(seed, i + (~xm & PRIME_X), j + (ym & PRIME_Y), k + (~zm & PRIME_Z), vec3(x0 - float(xs), y0, z0 - float(zs)));
		}
		float a8 = ya1 + a1;
		if (a8 > 0.0) {
			value += quartic(a8) * grad_coord(seed2, i + PRIME_X, j + (ym & (PRIME_Y << 1)), k + PRIME_Z, vec3(x1, float(ys) + y1, z1));
			skip9 = true;
		}
	}

	bool skip_d = false;
	float a_a = za0 + a0;
	if (a_a > 0.0) {
		value += quartic(a_a) * grad_coord(seed, i + (xm & PRIME_X), j + (ym & PRIME_Y), k + (~zm & PRIME_Z), vec3(x0, y0, z0 - float(zs)));
	} else {
		float a_b = xa0 + ya0 + a0;
		if (a_b > 0.0) {
			value += quartic(a_b) * grad_coord(seed, i + (~xm & PRIME_X), j + (~ym & PRIME_Y), k + (zm & PRIME_Z), vec3(x0 - float(xs), y0 - float(ys), z0));
		}
		float a_c = za1 + a1;
		if (a_c > 0.0) {
			value += quartic(a_c) * grad_coord(seed2, i + PRIME_X, j + PRIME_Y, k + (zm & (PRIME_Z << 1)), vec3(x1, y1, float(zs) + z1));
			skip_d = true;
		}
	}

	if (!skip5) {
		float a5 = ya1 + za1 + a1;
		if (a5 > 0.0) {
			value += quartic(a5) * grad_coord(seed2, i + PRIME_X, j + (ym & (PRIME_Y << 1)), k + (zm & (PRIME_Z << 1)), vec3(x1, float(ys) + y1, float(zs) + z1));
		}
	}
	if (!skip9) {
		float a9 = xa1 + za1 + a1;
		if (a9 > 0.0) {
			value += quartic(a9) * grad_coord(seed2, i + (xm & (PRIME_X * 2u)), j + PRIME_Y, k + (zm & (PRIME_Z << 1)), vec3(float(xs) + x1, y1, float(zs) + z1));
		}
	}
	if (!skip_d) {
		float a_d = xa1 + ya1 + a1;
		if (a_d > 0.0) {
			value += quartic(a_d) * grad_coord(seed2, i + (xm & (PRIME_X << 1)), j + (ym & (PRIME_Y << 1)), k + PRIME_Z, vec3(float(xs) + x1, float(ys) + y1, z1));
		}
	}
	return value * 9.046026385208288;
}

// A configured FastNoiseLite (OpenSimplex2S, fBm, lacunarity 2, gain 0.5) at a point; `slot` indexes the noises in `p`/`q`
float noise(int slot, vec3 pos) {
	int seed = q[slot * 2];
	int octaves = q[slot * 2 + 1];
	float frequency = p[24 + slot];
	pos *= frequency;
	float r = (pos.x + pos.y + pos.z) * (2.0 / 3.0); // the rotation of the default 3D transform
	pos = vec3(r) - pos;
	float bounding_sum = 1.0;
	float amp_step = 0.5;
	for (int octave = 1; octave < octaves; octave++) {
		bounding_sum += amp_step;
		amp_step *= 0.5;
	}
	float amp = 1.0 / bounding_sum;
	float sum = 0.0;
	for (int octave = 0; octave < octaves; octave++) {
		sum += open_simplex_2s(seed + octave, pos) * amp;
		pos *= 2.0;
		amp *= 0.5;
	}
	return sum;
}

float smooth_step(float from, float to, float x) {
	float t = clamp((x - from) / (to - from), 0.0, 1.0);
	return t * t * (3.0 - 2.0 * t);
}

float read_grid(int which, int width, int height, float lat, float lon) {
	float fx = (lon + PI) / TAU * float(width) - 0.5;
	float fy = (0.5 - lat / PI) * float(height) - 0.5;
	int x0 = int(floor(fx));
	int y0 = int(floor(fy));
	float tx = fx - float(x0);
	float ty = fy - float(y0);
	float value = 0.0;
	for (int dy = 0; dy < 2; dy++) {
		for (int dx = 0; dx < 2; dx++) {
			float w = (dx == 1 ? tx : 1.0 - tx) * (dy == 1 ? ty : 1.0 - ty);
			int row = clamp(y0 + dy, 0, height - 1);
			int column = ((x0 + dx) % width + width) % width;
			int at = row * width + column;
			float cell = which == 0 ? now_grid[at] : (which == 1 ? mean_grid[at] : rain_grid[at]);
			value += cell * w;
		}
	}
	return value;
}

void main() {
	int width = q[20];
	int height = q[21];
	uvec2 id = gl_GlobalInvocationID.xy;
	if (int(id.x) >= width || int(id.y) >= height) {
		return;
	}
	int gw = q[22];
	int gh = q[23];
	int cw = q[24];
	int ch = q[25];
	bool have_mean = q[26] == 1;
	float decl = p[0];
	float belt_shift = p[1];
	float belt_power = p[2];
	float storm_shift = p[3];
	float storm_power = p[4];
	float sink_shift = p[5];
	float sink_power = p[6];
	float pool_break = p[7];
	float wind_k = p[8];
	float morph = p[9];
	float first = p[10];
	float second = p[11];
	float weight = p[12];
	float shear = p[13];

	int index = int(id.y) * width + int(id.x);
	float lat_pixel = (0.5 - (float(id.y) + 0.5) / float(height)) * PI;
	float lon_pixel = ((float(id.x) + 0.5) / float(width)) * TAU - PI;
	vec3 dir = vec3(cos(lat_pixel) * cos(lon_pixel), sin(lat_pixel), cos(lat_pixel) * sin(lon_pixel));
	float macro = macro_height[index];

	float lat = asin(clamp(dir.y, -1.0, 1.0));
	float lon = atan(dir.z, dir.x);
	float degrees = read_grid(0, gw, gh, lat, lon);
	float wet = clamp(read_grid(2, cw, ch, lat, lon) / 1.2, 0.0, 1.0);
	float moisture = macro < 0.0 ? 0.25 + 0.75 * smooth_step(-30.0, 30.0, degrees) : wet * (0.25 + 0.75 * smooth_step(-30.0, 25.0, degrees));
	float south = lat < 0.0 ? -1.0 : 1.0;
	float pool_here = noise(0, dir);
	float pools = 0.5 + 0.5 * pool_here;
	float low = 1.0 - 0.65 * pool_break;
	float high = 1.0 + 0.4 * pool_break;
	float pools_factor = low + (high - low) * smooth_step(0.2, 0.8, pools);
	float trade_x = (lat - 0.4 * decl - belt_shift) / 0.17;
	float trade = 0.75 * belt_power * pools_factor * exp(-trade_x * trade_x);
	float lean = 0.12 * sin(atan(dir.z, dir.x) * 2.0 + pool_here * 3.0);
	float storm_lat = south * (0.87 + lean + storm_shift) + 0.3 * decl;
	float storm_x = (lat - storm_lat) / 0.2;
	float storms = 0.55 * storm_power * exp(-storm_x * storm_x);
	float high_lat = south * (0.48 + sink_shift) + 0.3 * decl;
	float sink_x = (lat - high_lat) / 0.15;
	float sinking = sink_power * exp(-sink_x * sink_x);
	float ready = 0.06 + 0.3 * moisture + 0.8 * trade * moisture;
	ready += 0.9 * storms * (0.5 + 0.5 * moisture) + 0.2 * wet * moisture;
	ready += 0.25 * smooth_step(0.9, 1.4, abs(lat));
	if (macro >= 0.0 && have_mean) {
		float tropics = exp(-(lat / 0.6) * (lat / 0.6));
		float anomaly = degrees - read_grid(1, gw, gh, lat, lon);
		ready += tropics * (0.5 * smooth_step(0.0, 8.0, anomaly) * (0.3 + wet) - 0.2 * smooth_step(0.0, 8.0, -anomaly));
	}
	float lo = 1.0 - 0.4 * pool_break;
	float hi = 1.0 + 0.3 * pool_break;
	ready *= lo + (hi - lo) * smooth_step(0.25, 0.75, pools);
	ready = clamp(ready * (1.0 - 0.65 * sinking), 0.0, 1.0);

	float pattern = 0.0;
	for (int turn = 0; turn < 2; turn++) {
		float drift = turn == 0 ? first : second;
		float shift = -cos(lat * wind_k) * 0.035 * TAU * drift;
		float carried_lon = atan(dir.z, dir.x) - shift;
		vec3 carried = vec3(cos(lat) * cos(carried_lon), dir.y, cos(lat) * sin(carried_lon));
		float bend_x = noise(1, carried);
		float bend_y = noise(1, vec3(carried.z + 7.3, carried.x - 3.1, carried.y + 1.7));
		carried = normalize(carried + vec3(bend_x, bend_y, bend_x - bend_y) * 0.45);
		float a = noise(2, carried);
		float b = noise(3, carried);
		float big = a + (b - a) * morph;
		float clumps = noise(4, carried);
		float share = turn == 0 ? weight : 1.0 - weight;
		pattern += clamp(0.5 + 0.5 * (0.75 * big + 0.35 * clumps), 0.0, 1.0) * share;
	}
	float threshold = 0.97 - ready * 0.8;
	cover[index] = smooth_step(threshold - 0.12, threshold + 0.12, pattern);
}
