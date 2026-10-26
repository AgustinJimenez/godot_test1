#include "planet_chart_native.h"

#include "planet_log_native.h"
#include "planet_render_native.h"

#include <godot_cpp/classes/image.hpp>
#include <godot_cpp/classes/os.hpp>
#include <godot_cpp/classes/time.hpp>

#include <algorithm>
#include <cmath>

using namespace godot;

static const double TAU_D = 6.283185307179586476925286766559;
static const double PI_D = 3.14159265358979323846;

void PlanetChart::_bind_methods() {
	BIND_ENUM_CONSTANT(TERRAIN);
	BIND_ENUM_CONSTANT(ELEVATION);
	BIND_ENUM_CONSTANT(TEMPERATURE);
	BIND_ENUM_CONSTANT(RAIN);
	BIND_ENUM_CONSTANT(BIOME);
	BIND_ENUM_CONSTANT(PLATES);
	BIND_ENUM_CONSTANT(SLOPE);
	BIND_ENUM_CONSTANT(MEAN_TEMPERATURE);
	BIND_ENUM_CONSTANT(CLOUDS);
	BIND_ENUM_CONSTANT(SATELLITE);
	BIND_ENUM_CONSTANT(ATLAS);
	BIND_ENUM_CONSTANT(CLOUD_MASK);
	NP_BIND(PlanetChart, Variant::INT, workers)
	NP_BIND(PlanetChart, Variant::RECT2, rect)
	NP_BIND(PlanetChart, Variant::VECTOR2I, size)
	NP_BIND(PlanetChart, Variant::INT, layer)
	NP_BIND_OBJ(PlanetChart, clock, "PlanetClock")
	NP_BIND(PlanetChart, Variant::BOOL, use_gpu)
	ClassDB::bind_static_method("PlanetChart", D_METHOD("names"), &PlanetChart::names);
	ClassDB::bind_static_method("PlanetChart", D_METHOD("ramp", "which", "t"), &PlanetChart::ramp);
	ClassDB::bind_static_method("PlanetChart", D_METHOD("scale_labels", "which", "relief"), &PlanetChart::scale_labels);
	ClassDB::bind_method(D_METHOD("start", "noise"), &PlanetChart::start);
	ClassDB::bind_method(D_METHOD("progress"), &PlanetChart::progress);
	ClassDB::bind_method(D_METHOD("finished"), &PlanetChart::finished);
	ClassDB::bind_method(D_METHOD("texture"), &PlanetChart::texture);
	ClassDB::bind_method(D_METHOD("cancel"), &PlanetChart::cancel);
	ClassDB::bind_method(D_METHOD("stop"), &PlanetChart::stop);
	ClassDB::bind_method(D_METHOD("chart", "worker"), &PlanetChart::chart);
}

PlanetChart::PlanetChart() {
	workers = CLAMP((int64_t)OS::get_singleton()->get_processor_count() - 1, (int64_t)2, (int64_t)8);
}

PlanetChart::~PlanetChart() {
	// (a chart dropped while its threads still run: they hold the Callable's reference, so they finish first)
}

Array PlanetChart::names() {
	Array list;
	for (const char *name : { "Terrain", "Elevation", "Temperature", "Rain", "Biome", "Plates", "Slope", "Mean temp", "Clouds", "Satellite", "Atlas" }) {
		list.append(String(name));
	}
	return list;
}

Color PlanetChart::along(double p_t, const Color *p_colors, const double *p_stops, int p_count) {
	for (int index = 0; index < p_count - 1; index++) {
		if (p_t <= p_stops[index + 1]) {
			double span = p_stops[index + 1] - p_stops[index];
			return p_colors[index].lerp(p_colors[index + 1], (float)((p_t - p_stops[index]) / std::max(span, 0.0001)));
		}
	}
	return p_colors[p_count - 1];
}

// The colour of `t` (0..1) along a layer's scale (the legend and the picture use the same).
Color PlanetChart::ramp(int64_t p_which, double p_t) {
	double t = CLAMP(p_t, 0.0, 1.0);
	switch (p_which) {
		case ELEVATION: { // sea floor to peaks
			static const Color colors[6] = { Color(0.05f, 0.12f, 0.4f), Color(0.3f, 0.6f, 0.85f), Color(0.25f, 0.55f, 0.25f), Color(0.85f, 0.8f, 0.35f), Color(0.6f, 0.4f, 0.25f), Color(1, 1, 1) };
			static const double stops[6] = { 0.0, 0.33, 0.36, 0.55, 0.8, 1.0 };
			return along(t, colors, stops, 6);
		}
		case TEMPERATURE:
		case MEAN_TEMPERATURE: { // -30 .. 45 C: purple, blue, green (5), yellow (20), orange (30), red, dark red (45)
			static const Color colors[7] = { Color(0.35f, 0.2f, 0.75f), Color(0.25f, 0.6f, 1.0f), Color(0.45f, 0.85f, 0.6f), Color(1.0f, 0.9f, 0.25f), Color(0.98f, 0.5f, 0.1f), Color(0.8f, 0.12f, 0.08f), Color(0.4f, 0.04f, 0.02f) };
			static const double stops[7] = { 0.0, 0.2, 0.46, 0.67, 0.8, 0.92, 1.0 };
			return along(t, colors, stops, 7);
		}
		case RAIN: {
			static const Color colors[4] = { Color(0.95f, 0.85f, 0.6f), Color(0.8f, 0.9f, 0.7f), Color(0.4f, 0.75f, 0.85f), Color(0.1f, 0.3f, 0.8f) };
			static const double stops[4] = { 0.0, 0.3, 0.65, 1.0 };
			return along(t, colors, stops, 4);
		}
		case SLOPE: {
			static const Color colors[3] = { Color(0.95f, 0.95f, 0.9f), Color(0.75f, 0.6f, 0.35f), Color(0.3f, 0.15f, 0.1f) };
			static const double stops[3] = { 0.0, 0.4, 1.0 };
			return along(t, colors, stops, 3);
		}
	}
	return Color(1, 1, 1, 1);
}

// The two ends of a layer's scale as text.
Array PlanetChart::scale_labels(int64_t p_which, double p_relief) {
	Array labels;
	switch (p_which) {
		case ELEVATION:
			labels.append(vformat("%d m deep", (int64_t)(p_relief * 0.35)));
			labels.append(vformat("%d m", (int64_t)p_relief));
			break;
		case TEMPERATURE:
		case MEAN_TEMPERATURE:
			labels.append(String::utf8("-30 \xC2\xB0""C"));
			labels.append(String::utf8("45 \xC2\xB0""C"));
			break;
		case RAIN:
			labels.append("dry");
			labels.append("wet");
			break;
		case SLOPE:
			labels.append("flat");
			labels.append("steep");
			break;
	}
	return labels;
}

Vector3 PlanetChart::direction(double p_lat, double p_lon) {
	return Vector3(std::cos(p_lat) * std::cos(p_lon), std::sin(p_lat), std::cos(p_lat) * std::sin(p_lon));
}

void PlanetChart::start(const Ref<PlanetNoise> &p_noise) {
	noise_ = p_noise;
	started_usec = Time::get_singleton()->get_ticks_usec();
	cloud_cover_on_the_gpu(p_noise);
	PlanetChartProfile::take(); // (a new picture starts its own account)
	if (noise_->get_native()->has_method("profile_take")) {
		noise_->get_native()->call("profile_take");
	}
	bands.assign(workers, PackedByteArray());
	land_bands.assign(workers, PackedByteArray());
	ground_bands.assign(workers, PackedFloat32Array());
	if ((layer == TEMPERATURE || layer == CLOUDS || layer == SATELLITE || layer == CLOUD_MASK) && clock.is_valid()) {
		blend = p_noise->get_climate()->get_seasons()->blended(clock->year_share());
	}
	for (int64_t worker = 0; worker < workers; worker++) {
		Ref<Thread> thread;
		thread.instantiate();
		thread->start(Callable(this, "chart").bind(worker), Thread::PRIORITY_HIGH); // (over the world's builders)
		threads.push_back(thread);
	}
}

// The cloud layers of a whole-planet picture: the cover of every pixel from the GPU, when the ground's heights are known already and there is a
// GPU to compute on.
void PlanetChart::cloud_cover_on_the_gpu(const Ref<PlanetNoise> &p_noise) {
	Dictionary heights = p_noise->get_map_heights();
	if (!use_gpu || clock.is_null() || rect != Rect2(0.0, 0.0, 1.0, 1.0) || !(layer == CLOUDS || layer == SATELLITE || layer == CLOUD_MASK) ||
			OS::get_singleton()->has_environment("PLANET_NO_GPU") || !heights.has(size) || !PlanetCloudGpu::available()) {
		return;
	}
	int64_t mark = Time::get_singleton()->get_ticks_usec();
	covers = PlanetCloudGpu::cover(p_noise, clock, size.x, size.y, heights[size]);
	PlanetChartProfile::lap("cloud cover on the GPU", mark);
}

// 0..1
double PlanetChart::progress() {
	int done;
	{
		std::lock_guard<std::mutex> lock(mutex);
		done = rows_done;
	}
	return (double)done / (double)size.y;
}

bool PlanetChart::finished() {
	bool is_tidied;
	{
		std::lock_guard<std::mutex> lock(mutex);
		is_tidied = tidied;
	}
	return is_tidied && progress() >= 1.0;
}

// The finished picture (joins the threads). Null while it is not done.
Ref<ImageTexture> PlanetChart::texture() {
	if (!finished()) {
		return Ref<ImageTexture>();
	}
	for (Ref<Thread> &thread : threads) {
		thread->wait_to_finish();
	}
	threads.clear();
	int64_t mark = Time::get_singleton()->get_ticks_usec();
	Ref<Image> image = Image::create_from_data(size.x, size.y, false, Image::FORMAT_RGB8, picture);
	Ref<ImageTexture> made = ImageTexture::create_from_image(image);
	PlanetChartProfile::lap("image and texture (main thread)", mark);
	Array all_names = names();
	String title = layer < all_names.size() ? (String)all_names[layer] : String("Cloud mask");
	PlanetChartProfile::report(vformat("%s %dx%d%s", title, size.x, size.y, rect == Rect2(0.0, 0.0, 1.0, 1.0) ? "" : " (a part)"),
			(double)(Time::get_singleton()->get_ticks_usec() - started_usec) / 1000.0, noise_->get_native().ptr());
	return made;
}

// The last worker to finish its rows tidies the picture on its own thread (the main thread only makes the image): the bands are joined, lone dots
// taken out, a data layer smoothed and the coasts drawn, the heights kept for the next layer.
void PlanetChart::tidy() {
	int64_t mark = Time::get_singleton()->get_ticks_usec();
	PackedByteArray all;
	for (const PackedByteArray &band : bands) {
		PackedByteArray copy = band;
		all.append_array(copy);
	}
	mark = PlanetChartProfile::lap("join the bands", mark);
	Ref<PlanetCrustNative> crust = noise_->get_native();
	bool tidy_it = layer != PLATES && layer != CLOUD_MASK;
	if (!cancelled && tidy_it) {
		all = crust->despeckle(all, size.x, size.y); // (lone dots are grain)
		mark = PlanetChartProfile::lap("despeckle", mark);
	}
	bool full_map = rect == Rect2(0.0, 0.0, 1.0, 1.0) && pixel_metres > SMOOTH_PIXEL;
	Dictionary map_heights = noise_->get_map_heights();
	if (!cancelled && full_map && !map_heights.has(size)) {
		PackedFloat32Array heights;
		for (const PackedFloat32Array &band : ground_bands) {
			PackedFloat32Array copy = band;
			heights.append_array(copy);
		}
		if (heights.size() == (int64_t)size.x * size.y) {
			map_heights[size] = heights;
		}
		mark = PlanetChartProfile::lap("keep the heights", mark);
	}
	bool far_view = pixel_metres > CALM_PIXEL * 50.0; // (kilometres a pixel: Elevation is grain too)
	// (flat colours: a blur, coast lines)
	if (!cancelled && layer == ATLAS) {
		int atlas_passes = pixel_metres > 2000.0 ? 4 : 1; // (close in the hatching must stay)
		for (int pass_number = 0; pass_number < atlas_passes; pass_number++) {
			all = crust->smooth_rgb(all, size.x, size.y);
		}
		PackedByteArray atlas_land;
		for (const PackedByteArray &band : land_bands) {
			PackedByteArray copy = band;
			atlas_land.append_array(copy);
		}
		if (atlas_land.size() >= (int64_t)size.x * size.y) {
			all = crust->coast_lines(all, atlas_land, size.x, size.y);
		}
		mark = PlanetChartProfile::lap("atlas blur and coasts", mark);
	}
	bool smoothed = layer == TEMPERATURE || layer == MEAN_TEMPERATURE || layer == RAIN || layer == CLOUDS;
	if (!cancelled && (smoothed || (layer == ELEVATION && far_view))) {
		// (a data layer is a smooth gradient: the grain of the small pixels is averaged away, and a thin dark line follows the coasts)
		int passes = (layer == TEMPERATURE || layer == MEAN_TEMPERATURE) ? 8 : 3;
		for (int pass_number = 0; pass_number < passes; pass_number++) {
			all = crust->smooth_rgb(all, size.x, size.y);
		}
		PackedByteArray land_all;
		for (const PackedByteArray &band : land_bands) {
			PackedByteArray copy = band;
			land_all.append_array(copy);
		}
		if (land_all.size() >= (int64_t)size.x * size.y) {
			all = crust->coast_lines(all, land_all, size.x, size.y);
		}
		mark = PlanetChartProfile::lap("smooth and coasts", mark);
	}
	std::lock_guard<std::mutex> lock(mutex);
	picture = all;
	tidied = true;
}

// Waits for the threads (the game ends).
void PlanetChart::stop() {
	for (Ref<Thread> &thread : threads) {
		thread->wait_to_finish();
	}
	threads.clear();
}

// One worker's share: a band of rows, as RGB bytes.
void PlanetChart::chart(int64_t p_worker) {
	int from_row = (int)(p_worker * size.y / workers);
	int to_row = (int)((p_worker + 1) * size.y / workers);
	PackedByteArray bytes;
	PackedByteArray land;
	Ref<PlanetCrustNative> crust = noise_->get_native();
	Ref<PlanetSettings> settings = noise_->get_settings();
	double step_lon = rect.size.x * TAU_D / (double)size.x;
	double step_lat = rect.size.y * PI_D / (double)size.y;
	bool needs_slope = layer == TERRAIN || layer == ELEVATION || layer == BIOME || layer == SLOPE || layer == SATELLITE || layer == ATLAS;
	// a pixel wider than a few tens of metres would only alias the hills and gullies into grain: the smooth ground is drawn (shaded like an
	// illustration); closer in, the real ground
	bool smooth_ground = step_lon * settings->get_radius() > SMOOTH_PIXEL;
	// the relief of a pixel of many kilometres is shaded gently (steeper looks like grain)
	double calm = CLAMP(std::sqrt(CALM_PIXEL / (step_lon * settings->get_radius())), 0.5, 1.0);
	pixel_metres = step_lon * settings->get_radius();
	PackedFloat32Array above; // the heights of the row before (the point a pixel north)
	// the whole planet's pictures share their heights: a layer drawn after another reads them
	bool whole = rect == Rect2(0.0, 0.0, 1.0, 1.0) && smooth_ground;
	PackedFloat32Array cached;
	if (whole) {
		Dictionary heights = noise_->get_map_heights();
		cached = heights.get(size, PackedFloat32Array());
	}
	bool use_cache = cached.size() == (int64_t)size.x * size.y;
	if (p_worker == 0 && whole) {
		PlanetMapLog::line(vformat("  heights of the whole planet %dx%d: %s", size.x, size.y, use_cache ? "from the cache" : "computed"));
	}
	PackedFloat32Array recorded;
	int64_t mark = Time::get_singleton()->get_ticks_usec();
	for (int row = from_row; row < to_row; row++) {
		if (cancelled) {
			land.resize(land.size() + size.x);
			bytes.resize(bytes.size() + (int64_t)size.x * 3);
			{
				std::lock_guard<std::mutex> lock(mutex);
				rows_done += 1;
			}
			above = PackedFloat32Array(); // the next row is not beside this one
			continue;
		}
		double v = rect.position.y + ((double)row + 0.5) / (double)size.y * rect.size.y;
		double lat = (0.5 - v) * PI_D;
		// the heights of the whole row (and the points east and north of it) in one go: the native crust answers many at once much faster
		mark = Time::get_singleton()->get_ticks_usec();
		PackedVector3Array dirs = row_dirs(lat);
		mark = PlanetChartProfile::lap("pixel directions", mark);
		PackedFloat32Array grounds;
		if (use_cache) {
			grounds = cached.slice((int64_t)row * size.x, (int64_t)(row + 1) * size.x);
			mark = PlanetChartProfile::lap("heights from the cache", mark);
		} else {
			grounds = ground_of(dirs, smooth_ground);
			mark = PlanetChartProfile::lap("heights (the ground)", mark);
		}
		PackedFloat32Array east_grounds = grounds;
		PackedFloat32Array north_grounds = grounds;
		if (use_cache) {
			east_grounds = grounds.slice(1);
			east_grounds.append(grounds[0]); // (the map wraps east-west)
			int64_t previous = (int64_t)std::max(row - 1, 0) * size.x;
			north_grounds = cached.slice(previous, previous + size.x);
		} else if (needs_slope) {
			// the point a pixel east is the next pixel of the row, the one a pixel north is the same pixel of the row before (kept from the last
			// turn): only the row's last pixel and the first row of a thread need points of their own
			double u_end = rect.position.x + rect.size.x + 0.5 / (double)size.x * rect.size.x;
			PackedVector3Array last_east;
			last_east.append(direction(lat, u_end * TAU_D - PI_D));
			east_grounds = grounds.slice(1);
			east_grounds.append_array(ground_of(last_east, smooth_ground));
			if (above.is_empty()) {
				above = ground_of(row_dirs(lat + step_lat), smooth_ground);
			}
			north_grounds = above;
			above = grounds;
			mark = PlanetChartProfile::lap("heights east and north", mark);
		}
		PackedFloat32Array macros = grounds;
		if (whole && !use_cache) {
			recorded.append_array(grounds);
		}
		if (smooth_ground) {
			// (the broad ground of a far view is the ground itself)
		} else if (layer == TEMPERATURE || layer == MEAN_TEMPERATURE || layer == CLOUDS || layer == SATELLITE || layer == ATLAS || layer == CLOUD_MASK) {
			macros = ground_of(dirs, true);
			mark = PlanetChartProfile::lap("heights (the broad ground)", mark);
		}
		land.append_array(crust->land_of(grounds));
		mark = PlanetChartProfile::lap("land mask", mark);
		if (layer == TERRAIN) {
			bytes.append_array(crust->terrain_row(dirs, grounds, east_grounds, north_grounds, step_lon, calm));
		} else {
			bytes.append_array(crust->data_row((int)layer, dirs, grounds, macros, east_grounds, north_grounds, step_lon, row_params(lat, row)));
		}
		mark = PlanetChartProfile::lap("native row colours", mark);
		std::lock_guard<std::mutex> lock(mutex);
		rows_done += 1;
	}
	bool last;
	{
		std::lock_guard<std::mutex> lock(mutex);
		bands[p_worker] = bytes;
		land_bands[p_worker] = land;
		ground_bands[p_worker] = recorded;
		finishing += 1;
		last = finishing == workers;
	}
	if (last) {
		tidy();
	}
}

// The directions of the pixels of one row (latitude `lat`).
PackedVector3Array PlanetChart::row_dirs(double p_lat) const {
	return noise_->get_native()->row_dirs(p_lat, rect.position.x, rect.size.x / (double)size.x, size.x);
}

// What the native row needs besides the heights (the seasons' grid now, the sun's longitude, and how clear the sky is on this row's latitude).
Dictionary PlanetChart::row_params(double p_lat, int p_row) const {
	Dictionary params;
	if (clock.is_null() || blend.is_empty()) {
		return params;
	}
	Vector3 sun = clock->sun_in_body();
	params["grid"] = blend;
	params["gw"] = PlanetSeasons::WIDTH;
	params["gh"] = PlanetSeasons::HEIGHT;
	params["sun_lon"] = std::atan2(sun.z, sun.x);
	params["decl"] = clock->declination();
	params["days"] = clock->absolute_days();
	params["clear"] = CLAMP(clock->day_length(p_lat) * 2.0 + 0.3, 0.3, 1.0);
	if (!covers.is_empty()) {
		PackedFloat32Array all_covers = covers;
		params["covers"] = all_covers.slice((int64_t)p_row * size.x, (int64_t)(p_row + 1) * size.x); // (from the GPU)
	}
	return params;
}

// The ground at many directions: its smooth shape (without the hills and gullies) for a far view.
PackedFloat32Array PlanetChart::ground_of(const PackedVector3Array &p_dirs, bool p_smooth_shape) const {
	if (!p_smooth_shape) {
		return noise_->heights_of(p_dirs);
	}
	return noise_->macro_heights_of(p_dirs, pixel_metres);
}
