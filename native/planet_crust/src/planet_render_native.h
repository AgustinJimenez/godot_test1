#pragma once

// PlanetCloudGpu and PlanetSunGlow (were systems/planet/planet_cloud_gpu.gd and planet_sun_glow.gd): the cloud cover of a whole map picture worked
// out on the GPU (a compute shader on a local rendering device, on a thread of its own), and the glow round the sun with a few lens-flare ghosts
// (a compositor effect that adds them to the frame before tone mapping).

#include "native_props.h"
#include "planet_clock_native.h"
#include "planet_noise_native.h"

#include <godot_cpp/classes/compositor_effect.hpp>
#include <godot_cpp/classes/mutex.hpp>
#include <godot_cpp/classes/ref.hpp>
#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/classes/render_data.hpp>
#include <godot_cpp/classes/rendering_device.hpp>
#include <godot_cpp/classes/semaphore.hpp>
#include <godot_cpp/classes/thread.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/color.hpp>
#include <godot_cpp/variant/packed_float32_array.hpp>
#include <godot_cpp/variant/rid.hpp>
#include <godot_cpp/variant/vector3.hpp>

namespace godot {

class PlanetCloudGpu : public RefCounted {
	GDCLASS(PlanetCloudGpu, RefCounted)

	static PackedFloat32Array compute(const Array &p_job);

protected:
	static void _bind_methods();

public:
	static void warm_up();
	static void stop();
	static bool available();
	static PackedFloat32Array cover(const Ref<PlanetNoise> &p_noise, const Ref<PlanetClock> &p_clock, int64_t p_width, int64_t p_height,
			const PackedFloat32Array &p_macros);
	void run(); // (the GPU thread)
};

class PlanetSunGlow : public CompositorEffect {
	GDCLASS(PlanetSunGlow, CompositorEffect)

	RenderingDevice *device = nullptr;
	RID shader, pipeline, sampler;

protected:
	static void _bind_methods();

public:
	NP_FIELD(Vector3, sun_direction, Vector3(0, 1, 0)) // towards the sun, world axes
	NP_FIELD(Color, tint, Color(1, 1, 1, 1)) // the sun's colour
	NP_FIELD(double, strength, 0.0)

	PlanetSunGlow();
	~PlanetSunGlow();
	void build();
	void _render_callback(int32_t p_effect_callback_type, RenderData *p_render_data) override;
};

} // namespace godot
