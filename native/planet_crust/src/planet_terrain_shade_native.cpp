#include "planet_terrain_shade_native.h"

#include <godot_cpp/classes/image.hpp>
#include <godot_cpp/classes/os.hpp>
#include <godot_cpp/classes/rendering_server.hpp>
#include <godot_cpp/variant/packed_vector3_array.hpp>
#include <godot_cpp/variant/utility_functions.hpp>

#include <algorithm>
#include <cmath>

using namespace godot;

void PlanetTerrainShade::_bind_methods() {
	ClassDB::bind_method(D_METHOD("bake_run"), &PlanetTerrainShade::bake_run);
}

void PlanetTerrainShade::setup(const Ref<PlanetNoise> &p_noise, double p_radius) {
	noise = p_noise;
	radius = p_radius;
}

// The thread: the heights of the square's pixels (the planet's own ground height, the sea held at 0), then from each pixel's ground a march toward the
// star over them: how much of the star the ground there sees (the ground rising above the ray shades it, softly: the star has a disc).
void PlanetTerrainShade::bake_run() {
	const int64_t count = (int64_t)SIZE * SIZE;
	PackedVector3Array dirs;
	dirs.resize(count);
	Vector3 *out = dirs.ptrw();
	for (int j = 0; j < SIZE; j++) {
		double y = ((double)(j + 0.5) / SIZE * 2.0 - 1.0) * job_tan;
		for (int i = 0; i < SIZE; i++) {
			double x = ((double)(i + 0.5) / SIZE * 2.0 - 1.0) * job_tan;
			out[(int64_t)j * SIZE + i] = (job_c + job_e1 * x + job_e2 * y).normalized();
		}
	}
	PackedFloat32Array heights = noise->heights_of(dirs);
	float *h = heights.ptrw();
	double highest = 0.0;
	for (int64_t k = 0; k < count; k++) {
		h[k] = std::max(h[k], 0.0f);
		highest = std::max(highest, (double)h[k]);
	}
	const Vector3 c = job_c, e1 = job_e1, e2 = job_e2, sun = job_sun;
	const double tan_half = job_tan, R = radius;
	auto ground_at = [&](double fx, double fy) {
		fx = CLAMP(fx, 0.0, (double)SIZE - 1.001);
		fy = CLAMP(fy, 0.0, (double)SIZE - 1.001);
		int ix = (int)fx, iy = (int)fy;
		double ax = fx - ix, ay = fy - iy;
		const float *p = h + (int64_t)iy * SIZE + ix;
		return (double)(p[0] * (1.0 - ax) * (1.0 - ay) + p[1] * ax * (1.0 - ay) + p[SIZE] * (1.0 - ax) * ay + p[SIZE + 1] * ax * ay);
	};
	PackedByteArray shade;
	shade.resize(count);
	uint8_t *sp = shade.ptrw();
	for (int64_t k = 0; k < count; k++) {
		Vector3 d0 = out[k];
		if (d0.dot(sun) <= 0.0) {
			sp[k] = 255; // (the star is below the horizon there: night)
			continue;
		}
		Vector3 start = d0 * (R + h[k]);
		double vis = 1.0;
		double t = 40.0;
		for (int step = 0; step < 48; step++) {
			Vector3 p = start + sun * t;
			double r = p.length();
			double height = r - R;
			if (height > highest + 5.0) {
				break;
			}
			Vector3 d = p / r;
			double cz = d.dot(c);
			if (cz < 0.2) {
				break;
			}
			double u = d.dot(e1) / cz / tan_half * 0.5 + 0.5;
			double v = d.dot(e2) / cz / tan_half * 0.5 + 0.5;
			if (u < 0.0 || v < 0.0 || u > 1.0 || v > 1.0) {
				break;
			}
			double ground = ground_at(u * SIZE - 0.5, v * SIZE - 0.5);
			double kk = 2.0 + t * 0.006; // (the pixels are 35 m; the star's disc widens a shadow's edge with the distance)
			double x = CLAMP((ground - height - kk) / (2.0 * kk), 0.0, 1.0);
			vis = std::min(vis, 1.0 - x * x * (3.0 - 2.0 * x));
			if (vis < 0.02) {
				break;
			}
			t += std::max(15.0, t * 0.17);
		}
		sp[k] = (uint8_t)(CLAMP(vis, 0.0, 1.0) * 255.0 + 0.5);
	}
	result = shade;
	result_ready = true;
}

void PlanetTerrainShade::publish() {
	Ref<Image> image = Image::create_from_data(SIZE, SIZE, false, Image::FORMAT_R8, result);
	texture = ImageTexture::create_from_image(image);
	RenderingServer *rs = RenderingServer::get_singleton();
	rs->global_shader_parameter_set("terrain_shade_map", texture);
	rs->global_shader_parameter_set("terrain_shade_c", job_c);
	rs->global_shader_parameter_set("terrain_shade_e1", job_e1);
	rs->global_shader_parameter_set("terrain_shade_e2", job_e2);
	bool off = OS::get_singleton()->get_environment("NO_TERRAIN_SHADE") != "";
	rs->global_shader_parameter_set("terrain_shade", Color((float)job_tan, off ? 0.0f : 1.0f, 0.0f, 0.0f));
	shown_c = job_c;
	shown_sun = job_sun;
	shown_tan = job_tan;
	shown = true;
	result_ready = false;
	result = PackedByteArray();
}

void PlanetTerrainShade::update(const Vector3 &p_dir, const Vector3 &p_sun) {
	if (noise.is_null() || radius <= 1.0) {
		return;
	}
	if (working && worker.is_valid() && !worker->is_alive()) {
		worker->wait_to_finish();
		working = false;
		if (result_ready) {
			publish();
		}
	}
	if (working) {
		return;
	}
	Vector3 here = p_dir.normalized();
	Vector3 sun = p_sun.normalized();
	// the next picture when none is shown, the player is more than a quarter of the half side from the middle, or the star has moved a fifth of a degree
	if (shown) {
		double away = shown_c.angle_to(here) / std::max(shown_tan, 1.0e-6);
		if (away < 0.25 && shown_sun.angle_to(sun) < 0.0035) {
			return;
		}
	}
	double half = std::min(HALF_SIDE, radius * 0.7);
	job_tan = half / radius;
	job_c = here;
	job_sun = sun;
	Vector3 up = std::abs(here.y) < 0.95 ? Vector3(0, 1, 0) : Vector3(1, 0, 0);
	job_e1 = here.cross(up).normalized();
	job_e2 = here.cross(job_e1).normalized();
	result_ready = false;
	if (worker.is_null()) {
		worker.instantiate();
	}
	working = true;
	worker->start(Callable(this, "bake_run"));
}

void PlanetTerrainShade::stop() {
	if (working && worker.is_valid()) {
		worker->wait_to_finish();
		working = false;
	}
}

void PlanetTerrainShade::clear() {
	stop();
	shown = false;
}
