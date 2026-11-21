class_name MotionBlurEffect
extends CompositorEffect
## Motion blur as a compositor effect (graphics setting "Motion blur"): a compute shader smears the picture along the engine's velocity buffer,
## after the transparent pass (shaders/compute/motion_blur.glsl). GraphicsLook puts one on the scene's WorldEnvironment when the setting is on.

const SHADER_PATH := "res://shaders/compute/motion_blur.glsl"
const COPY_SHADER_PATH := "res://shaders/compute/motion_blur_copy.glsl"

## How much of the frame's motion is smeared (1 = the whole of it).
var strength := 0.5
var samples := 10.0

var _device: RenderingDevice
var _shader: RID
var _pipeline: RID
var _copy_shader: RID
var _copy_pipeline: RID
var _sampler: RID


func _init() -> void:
	effect_callback_type = EFFECT_CALLBACK_TYPE_POST_TRANSPARENT
	needs_motion_vectors = true # (the velocity buffer is made even without TAA)
	RenderingServer.call_on_render_thread(_make_compute)


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE and _device != null:
		if _sampler.is_valid():
			_device.free_rid(_sampler)
		if _shader.is_valid():
			_device.free_rid(_shader) # (the pipeline goes with it)
		if _copy_shader.is_valid():
			_device.free_rid(_copy_shader)


func _make_compute() -> void:
	_device = RenderingServer.get_rendering_device()
	if _device == null:
		return
	var file := load(SHADER_PATH) as RDShaderFile
	if file == null:
		push_warning("MotionBlurEffect: %s did not load" % SHADER_PATH)
		return
	_shader = _device.shader_create_from_spirv(file.get_spirv())
	if not _shader.is_valid():
		return
	_pipeline = _device.compute_pipeline_create(_shader)
	var copy_file := load(COPY_SHADER_PATH) as RDShaderFile
	if copy_file != null:
		_copy_shader = _device.shader_create_from_spirv(copy_file.get_spirv())
		_copy_pipeline = _device.compute_pipeline_create(_copy_shader)
	var state := RDSamplerState.new()
	state.min_filter = RenderingDevice.SAMPLER_FILTER_LINEAR
	state.mag_filter = RenderingDevice.SAMPLER_FILTER_LINEAR
	state.repeat_u = RenderingDevice.SAMPLER_REPEAT_MODE_CLAMP_TO_EDGE
	state.repeat_v = RenderingDevice.SAMPLER_REPEAT_MODE_CLAMP_TO_EDGE
	_sampler = _device.sampler_create(state)


func _render_callback(_callback_type: int, render_data: RenderData) -> void:
	if _device == null or not _pipeline.is_valid() or not _copy_pipeline.is_valid() or not enabled:
		return
	var buffers := render_data.get_render_scene_buffers() as RenderSceneBuffersRD
	if buffers == null:
		return
	var size := buffers.get_internal_size()
	if size.x <= 0 or size.y <= 0:
		return
	var usage := RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT | RenderingDevice.TEXTURE_USAGE_STORAGE_BIT
	buffers.create_texture(&"motion_blur", &"copy", RenderingDevice.DATA_FORMAT_R16G16B16A16_SFLOAT, usage,
			RenderingDevice.TEXTURE_SAMPLES_1, size, 1, 1, false, false)
	var constants := PackedFloat32Array([float(size.x), float(size.y), strength, samples]).to_byte_array()
	var groups := Vector2i((size.x - 1) / 8 + 1, (size.y - 1) / 8 + 1)
	for view in buffers.get_view_count():
		var colour := buffers.get_color_layer(view)
		var velocity := buffers.get_velocity_layer(view)
		var copy := buffers.get_texture_slice(&"motion_blur", &"copy", view, 0, 1, 1)
		if not colour.is_valid() or not velocity.is_valid() or not copy.is_valid():
			continue
		# step 1: the copy of the colour
		var from := RDUniform.new()
		from.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
		from.binding = 0
		from.add_id(colour)
		var to := RDUniform.new()
		to.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
		to.binding = 1
		to.add_id(copy)
		var copy_set := UniformSetCacheRD.get_cache(_copy_shader, 0, [from, to])
		var copy_constants := PackedFloat32Array([float(size.x), float(size.y), 0.0, 0.0]).to_byte_array()
		var copy_list := _device.compute_list_begin()
		_device.compute_list_bind_compute_pipeline(copy_list, _copy_pipeline)
		_device.compute_list_bind_uniform_set(copy_list, copy_set, 0)
		_device.compute_list_set_push_constant(copy_list, copy_constants, copy_constants.size())
		_device.compute_list_dispatch(copy_list, groups.x, groups.y, 1)
		_device.compute_list_end()
		# step 2: the blur, reading the copy
		var image := RDUniform.new()
		image.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
		image.binding = 0
		image.add_id(colour)
		var source := RDUniform.new()
		source.uniform_type = RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE
		source.binding = 1
		source.add_id(_sampler)
		source.add_id(copy)
		var motion := RDUniform.new()
		motion.uniform_type = RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE
		motion.binding = 2
		motion.add_id(_sampler)
		motion.add_id(velocity)
		var uniform_set := UniformSetCacheRD.get_cache(_shader, 0, [image, source, motion])
		var list := _device.compute_list_begin()
		_device.compute_list_bind_compute_pipeline(list, _pipeline)
		_device.compute_list_bind_uniform_set(list, uniform_set, 0)
		_device.compute_list_set_push_constant(list, constants, constants.size())
		_device.compute_list_dispatch(list, groups.x, groups.y, 1)
		_device.compute_list_end()
