#include "planet_render_native.h"

#include <godot_cpp/classes/display_server.hpp>
#include <godot_cpp/classes/os.hpp>
#include <godot_cpp/classes/rd_sampler_state.hpp>
#include <godot_cpp/classes/rd_shader_file.hpp>
#include <godot_cpp/classes/rd_shader_spirv.hpp>
#include <godot_cpp/classes/rd_uniform.hpp>
#include <godot_cpp/classes/render_scene_buffers_rd.hpp>
#include <godot_cpp/classes/render_scene_data.hpp>
#include <godot_cpp/classes/rendering_server.hpp>
#include <godot_cpp/classes/resource_loader.hpp>
#include <godot_cpp/classes/uniform_set_cache_rd.hpp>
#include <godot_cpp/variant/projection.hpp>
#include <godot_cpp/variant/typed_array.hpp>
#include <godot_cpp/variant/utility_functions.hpp>
#include <godot_cpp/variant/vector4.hpp>

#include <cmath>
#include <mutex>

using namespace godot;

// ---- PlanetCloudGpu ----

static std::mutex gpu_lock;
static Ref<Thread> gpu_thread;
static Ref<PlanetCloudGpu> gpu_runner;
static bool gpu_ready = false;
static bool gpu_stopping = false;
static Ref<Semaphore> gpu_wake, gpu_done;
static RenderingDevice *gpu_device = nullptr;
// (engine types must not be built before the library is initialised: a static of them would crash the load)
struct GpuState {
	Array job; // the buffers of the work to do (empty: none)
	PackedFloat32Array result;
	RID shader, pipeline;
};
static GpuState *gpu() {
	static GpuState *state = new GpuState();
	return state;
}

void PlanetCloudGpu::_bind_methods() {
	ClassDB::bind_method(D_METHOD("run"), &PlanetCloudGpu::run);
	ClassDB::bind_static_method("PlanetCloudGpu", D_METHOD("warm_up"), &PlanetCloudGpu::warm_up);
	ClassDB::bind_static_method("PlanetCloudGpu", D_METHOD("stop"), &PlanetCloudGpu::stop);
	ClassDB::bind_static_method("PlanetCloudGpu", D_METHOD("available"), &PlanetCloudGpu::available);
	ClassDB::bind_static_method("PlanetCloudGpu", D_METHOD("cover", "noise", "clock", "width", "height", "macros"), &PlanetCloudGpu::cover);
}

// Starts getting the GPU ready on a thread of its own, which then does all the GPU's work (a local rendering device belongs to the thread that
// made it; the shader takes about 3 s to compile: the map would freeze for that long the first time it asked). Safe to call again; `available`
// says when it is done (and a GPU is there).
void PlanetCloudGpu::warm_up() {
	std::lock_guard<std::mutex> lock(gpu_lock);
	bool start = gpu_thread.is_null() && !OS::get_singleton()->has_environment("PLANET_NO_GPU") && DisplayServer::get_singleton()->get_name() != "headless";
	if (start) {
		gpu_stopping = false;
		if (gpu_wake.is_null()) {
			gpu_wake.instantiate();
			gpu_done.instantiate();
		}
		gpu_runner.instantiate();
		gpu_thread.instantiate();
		gpu_thread->start(Callable(gpu_runner.ptr(), "run"), Thread::PRIORITY_LOW);
	}
}

// Ends the GPU thread (the game ends).
void PlanetCloudGpu::stop() {
	Ref<Thread> thread;
	{
		std::lock_guard<std::mutex> lock(gpu_lock);
		thread = gpu_thread;
		gpu_stopping = true;
	}
	if (thread.is_valid()) {
		gpu_wake->post();
		thread->wait_to_finish();
		std::lock_guard<std::mutex> lock(gpu_lock);
		gpu_thread.unref();
		gpu_runner.unref();
		gpu_ready = false;
	}
}

// True once the compute shader is ready to run.
bool PlanetCloudGpu::available() {
	std::lock_guard<std::mutex> lock(gpu_lock);
	return gpu_ready;
}

void PlanetCloudGpu::run() {
	gpu_device = RenderingServer::get_singleton()->create_local_rendering_device();
	if (gpu_device == nullptr) {
		return;
	}
	Ref<RDShaderFile> file = ResourceLoader::get_singleton()->load("res://shaders/compute/planet_cloud_cover.glsl");
	if (file.is_null()) {
		return;
	}
	Ref<RDShaderSPIRV> spirv = file->get_spirv();
	String error = spirv->get_stage_compile_error(RenderingDevice::SHADER_STAGE_COMPUTE);
	if (error != "") {
		UtilityFunctions::push_warning("cloud cover shader: " + error);
		return;
	}
	gpu()->shader = gpu_device->shader_create_from_spirv(spirv);
	gpu()->pipeline = gpu_device->compute_pipeline_create(gpu()->shader);
	{
		std::lock_guard<std::mutex> lock(gpu_lock);
		gpu_ready = true;
	}
	while (true) {
		gpu_wake->wait();
		if (gpu_stopping) {
			break;
		}
		Array job;
		{
			std::lock_guard<std::mutex> lock(gpu_lock);
			job = gpu()->job;
			gpu()->job = Array();
		}
		gpu()->result = !job.is_empty() ? compute(job) : PackedFloat32Array();
		gpu_done->post();
	}
}

// One job on the GPU thread: `job` = [width, height, the buffers in the order the shader reads them].
PackedFloat32Array PlanetCloudGpu::compute(const Array &p_job) {
	int64_t width = p_job[0];
	int64_t height = p_job[1];
	TypedArray<RID> buffers;
	TypedArray<RDUniform> uniforms;
	Array sources = p_job[2];
	for (int binding = 0; binding < sources.size(); binding++) {
		PackedByteArray data;
		Variant source = sources[binding];
		if (source.get_type() == Variant::PACKED_FLOAT32_ARRAY) {
			data = PackedFloat32Array(source).to_byte_array();
		} else {
			data = PackedInt32Array(source).to_byte_array();
		}
		if (data.is_empty()) {
			data.resize(4);
		}
		RID buffer = gpu_device->storage_buffer_create(data.size(), data);
		buffers.append(buffer);
		Ref<RDUniform> uniform;
		uniform.instantiate();
		uniform->set_uniform_type(RenderingDevice::UNIFORM_TYPE_STORAGE_BUFFER);
		uniform->set_binding(binding);
		uniform->add_id(buffer);
		uniforms.append(uniform);
	}
	RID uniform_set = gpu_device->uniform_set_create(uniforms, gpu()->shader, 0);
	int64_t list = gpu_device->compute_list_begin();
	gpu_device->compute_list_bind_compute_pipeline(list, gpu()->pipeline);
	gpu_device->compute_list_bind_uniform_set(list, uniform_set, 0);
	gpu_device->compute_list_dispatch(list, (width + 7) / 8, (height + 7) / 8, 1);
	gpu_device->compute_list_end();
	gpu_device->submit();
	gpu_device->sync();
	PackedFloat32Array result = gpu_device->buffer_get_data(buffers[0]).to_float32_array();
	gpu_device->free_rid(uniform_set);
	for (int i = 0; i < buffers.size(); i++) {
		gpu_device->free_rid(buffers[i]);
	}
	return result;
}

// The cover (0..1) of every pixel of a `width` x `height` picture of the whole planet at `clock`'s moment, row after row from the north;
// `macros` is the ground height of each pixel (its sign says land or sea).
PackedFloat32Array PlanetCloudGpu::cover(const Ref<PlanetNoise> &p_noise, const Ref<PlanetClock> &p_clock, int64_t p_width, int64_t p_height,
		const PackedFloat32Array &p_macros) {
	if (!available() || p_macros.size() != p_width * p_height) {
		return PackedFloat32Array();
	}
	Dictionary weather = p_noise->get_weather()->config();
	Ref<PlanetSeasons> seasons = p_noise->get_climate()->get_seasons();
	PackedFloat32Array now_grid = seasons->blended(p_clock->year_share());
	PackedFloat32Array mean_grid = seasons->get_mean();
	PackedFloat32Array rain = p_noise->get_climate()->rain_grid();
	double days = p_clock->absolute_days();
	double shear = 2.5;
	double first = std::fmod(days, shear);
	if (first < 0.0) {
		first += shear;
	}
	double second = std::fmod(days + shear * 0.5, shear);
	if (second < 0.0) {
		second += shear;
	}
	PackedFloat32Array floats;
	floats.resize(32);
	floats.fill(0.0f);
	floats[0] = p_clock->declination();
	floats[1] = (double)weather["belt_shift"];
	floats[2] = (double)weather["belt_power"];
	floats[3] = (double)weather["storm_shift"];
	floats[4] = (double)weather["storm_power"];
	floats[5] = (double)weather["sink_shift"];
	floats[6] = (double)weather["sink_power"];
	floats[7] = (double)weather["pool_break"];
	floats[8] = (double)weather["wind_k"];
	floats[9] = 0.5 + 0.5 * std::sin(days * 0.45);
	floats[10] = first;
	floats[11] = second;
	floats[12] = 1.0 - std::abs(2.0 * first / shear - 1.0);
	floats[13] = shear;
	PackedInt32Array ints;
	ints.resize(32);
	ints.fill(0);
	// the noises in the order the shader reads them: pool, warp, big a, big b, small
	int slot = 0;
	for (const char *key : { "pool", "warp", "big_a", "big_b", "small" }) {
		Array config = weather[key]; // [seed, frequency, octaves, fractal type]
		ints[slot * 2] = (int)(int64_t)config[0];
		ints[slot * 2 + 1] = (int)(int64_t)config[2];
		floats[24 + slot] = (double)config[1];
		slot += 1;
	}
	ints[20] = (int)p_width;
	ints[21] = (int)p_height;
	ints[22] = PlanetSeasons::WIDTH;
	ints[23] = PlanetSeasons::HEIGHT;
	ints[24] = PlanetClimate::WIDTH;
	ints[25] = PlanetClimate::HEIGHT;
	ints[26] = mean_grid.size() >= PlanetSeasons::WIDTH * PlanetSeasons::HEIGHT ? 1 : 0;
	PackedFloat32Array out_bytes;
	out_bytes.resize(p_width * p_height);
	Array buffers;
	buffers.append(out_bytes);
	buffers.append(p_macros);
	buffers.append(now_grid);
	buffers.append(mean_grid);
	buffers.append(rain);
	buffers.append(floats);
	buffers.append(ints);
	Array job;
	job.append(p_width);
	job.append(p_height);
	job.append(buffers);
	{
		std::lock_guard<std::mutex> lock(gpu_lock);
		gpu()->job = job;
	}
	gpu_wake->post();
	gpu_done->wait(); // (the GPU thread does the work; a few hundred ms)
	return gpu()->result;
}

// ---- PlanetSunGlow ----

void PlanetSunGlow::_bind_methods() {
	NP_BIND(PlanetSunGlow, Variant::VECTOR3, sun_direction)
	NP_BIND(PlanetSunGlow, Variant::COLOR, tint)
	NP_BIND(PlanetSunGlow, Variant::FLOAT, strength)
	ClassDB::bind_method(D_METHOD("build"), &PlanetSunGlow::build);
}

PlanetSunGlow::PlanetSunGlow() {
	set_effect_callback_type(EFFECT_CALLBACK_TYPE_POST_TRANSPARENT);
	set_needs_motion_vectors(false);
	RenderingServer::get_singleton()->call_on_render_thread(Callable(this, "build"));
}

PlanetSunGlow::~PlanetSunGlow() {
	if (device != nullptr) {
		for (RID rid : { sampler, pipeline, shader }) {
			if (rid.is_valid()) {
				device->free_rid(rid);
			}
		}
	}
}

void PlanetSunGlow::build() {
	device = RenderingServer::get_singleton()->get_rendering_device();
	if (device == nullptr) {
		return;
	}
	Ref<RDShaderFile> file = ResourceLoader::get_singleton()->load("res://shaders/compute/planet_sun_glow.glsl");
	Ref<RDShaderSPIRV> spirv = file->get_spirv();
	String error = spirv->get_stage_compile_error(RenderingDevice::SHADER_STAGE_COMPUTE);
	if (error != "") {
		UtilityFunctions::push_warning("sun glow shader: " + error);
		return;
	}
	shader = device->shader_create_from_spirv(spirv);
	pipeline = device->compute_pipeline_create(shader);
	Ref<RDSamplerState> state;
	state.instantiate();
	state->set_min_filter(RenderingDevice::SAMPLER_FILTER_NEAREST);
	state->set_mag_filter(RenderingDevice::SAMPLER_FILTER_NEAREST);
	sampler = device->sampler_create(state);
}

void PlanetSunGlow::_render_callback(int32_t, RenderData *p_render_data) {
	if (!pipeline.is_valid() || strength <= 0.0) {
		return;
	}
	Ref<RenderSceneBuffersRD> buffers = p_render_data->get_render_scene_buffers();
	RenderSceneData *scene = p_render_data->get_render_scene_data();
	if (buffers.is_null() || scene == nullptr) {
		return;
	}
	Vector2i size = buffers->get_internal_size();
	Transform3D camera = scene->get_cam_transform();
	Vector3 in_view = camera.affine_inverse().basis.xform(sun_direction);
	bool behind = in_view.z >= 0.0;
	Vector4 clip = scene->get_cam_projection().xform(Vector4(in_view.x, in_view.y, in_view.z, 1.0));
	Vector2 pixel = Vector2(size) * 0.5;
	if (clip.w > 0.0) {
		pixel = Vector2((clip.x / clip.w * 0.5 + 0.5) * size.x, (0.5 + clip.y / clip.w * 0.5) * size.y);
	}
	PackedFloat32Array push;
	push.append(pixel.x);
	push.append(pixel.y);
	push.append(size.x);
	push.append(size.y);
	push.append(tint.r);
	push.append(tint.g);
	push.append(tint.b);
	push.append(behind ? 0.0 : strength);
	for (int view = 0; view < buffers->get_view_count(); view++) {
		Ref<RDUniform> colour;
		colour.instantiate();
		colour->set_uniform_type(RenderingDevice::UNIFORM_TYPE_IMAGE);
		colour->set_binding(0);
		colour->add_id(buffers->get_color_layer(view));
		Ref<RDUniform> depth;
		depth.instantiate();
		depth->set_uniform_type(RenderingDevice::UNIFORM_TYPE_SAMPLER_WITH_TEXTURE);
		depth->set_binding(1);
		depth->add_id(sampler);
		depth->add_id(buffers->get_depth_layer(view));
		TypedArray<RDUniform> uniforms;
		uniforms.append(colour);
		uniforms.append(depth);
		RID uniform_set = UniformSetCacheRD::get_cache(shader, 0, uniforms);
		int64_t list = device->compute_list_begin();
		device->compute_list_bind_compute_pipeline(list, pipeline);
		device->compute_list_bind_uniform_set(list, uniform_set, 0);
		device->compute_list_set_push_constant(list, push.to_byte_array(), push.size() * 4);
		device->compute_list_dispatch(list, (size.x + 7) / 8, (size.y + 7) / 8, 1);
		device->compute_list_end();
	}
}
