#pragma once

// PlanetChart (was systems/planet/planet_chart.gd): one picture of (a part of) a planet, drawn from PlanetNoise on background threads, in one of
// the map's layers (what the colours show). `rect` is the part of the map it covers in fractions (u east, v south, the whole planet is (0, 0, 1,
// 1)); `size` is its size in pixels. Poll `finished()`, then take `texture()`. Every layer's rows come from the native crust; the script's own
// pixel colouring (the fallback without the library) is gone with the port.

#include "native_props.h"
#include "planet_clock_native.h"
#include "planet_noise_native.h"

#include <godot_cpp/classes/image_texture.hpp>
#include <godot_cpp/classes/thread.hpp>
#include <godot_cpp/variant/color.hpp>
#include <godot_cpp/variant/packed_byte_array.hpp>
#include <godot_cpp/variant/packed_float32_array.hpp>
#include <godot_cpp/variant/rect2.hpp>
#include <godot_cpp/variant/vector2i.hpp>

#include <atomic>
#include <mutex>
#include <vector>

namespace godot {

class PlanetChart : public RefCounted {
	GDCLASS(PlanetChart, RefCounted)

	Ref<PlanetNoise> noise_;
	double pixel_metres = 0.0; // metres a pixel spans
	std::vector<Ref<Thread>> threads;
	std::vector<PackedByteArray> bands;
	PackedFloat32Array blend; // the seasons' grid at this chart's moment (Temperature)
	std::vector<PackedFloat32Array> ground_bands; // each worker's heights (the map's cache)
	std::vector<PackedByteArray> land_bands; // 1 where the pixel is land (for the coast lines)
	int rows_done = 0;
	std::mutex mutex;
	uint64_t started_usec = 0;
	PackedFloat32Array covers; // the cloud cover of every pixel, from the GPU
	int finishing = 0; // workers that have finished their rows (the last one tidies the picture)
	bool tidied = false; // the picture is finished: smoothed, the coasts drawn
	PackedByteArray picture;
	std::atomic<bool> cancelled{ false }; // a chart nobody wants any more: its workers skip the pixels

	void cloud_cover_on_the_gpu(const Ref<PlanetNoise> &p_noise);
	void tidy();
	Dictionary row_params(double p_lat, int p_row) const;
	PackedFloat32Array ground_of(const PackedVector3Array &p_dirs, bool p_smooth_shape) const;
	PackedVector3Array row_dirs(double p_lat) const;
	static Vector3 direction(double p_lat, double p_lon);
	static Color along(double p_t, const Color *p_colors, const double *p_stops, int p_count);

protected:
	static void _bind_methods();

public:
	enum Layer { TERRAIN, ELEVATION, TEMPERATURE, RAIN, BIOME, PLATES, SLOPE, MEAN_TEMPERATURE, CLOUDS, SATELLITE, ATLAS, CLOUD_MASK }; // CLOUD_MASK is the cloud cover alone
	static constexpr double CALM_PIXEL = 2000.0; // metres a pixel spans above which the Terrain relief is shaded gently
	static constexpr double COARSE_PIXEL = 20.0; // metres a pixel spans above which the map has no fine grain or beds
	static constexpr double SMOOTH_PIXEL = 30.0; // metres a pixel spans above which the map draws the smooth ground

	NP_FIELD(int64_t, workers, 2) // threads a chart is drawn on: every core but one (the main thread), at most 8
	NP_FIELD(Rect2, rect, Rect2(0.0, 0.0, 1.0, 1.0))
	NP_FIELD(Vector2i, size, Vector2i(320, 160))
	NP_FIELD(int64_t, layer, TERRAIN)
	NP_FIELD(Ref<PlanetClock>, clock, Ref<PlanetClock>()) // the moment the temperature layer shows (a copy: the game moves on)
	NP_FIELD(bool, use_gpu, false) // true: the cloud cover of a whole-planet picture is worked out on the GPU when it can be

	PlanetChart();
	~PlanetChart();
	static Array names();
	static Color ramp(int64_t p_which, double p_t);
	static Array scale_labels(int64_t p_which, double p_relief);
	void start(const Ref<PlanetNoise> &p_noise);
	double progress();
	bool finished();
	Ref<ImageTexture> texture();
	void cancel() { cancelled = true; }
	void stop();
	void chart(int64_t p_worker);
};

} // namespace godot

VARIANT_ENUM_CAST(PlanetChart::Layer);
