class_name PlanetSunGlow
extends CompositorEffect
## The glow round the sun and a few lens-flare ghosts (task 081, step 3): a compute shader
## (shaders/compute/planet_sun_glow.glsl) adds them to the frame before tone mapping, only where the
## sun is not behind a hill (the depth picture says). Set `sun_direction` (towards the sun, world
## axes), `tint` (the sun's colour) and `strength` every frame.

var sun_direction := Vector3.UP
var tint := Color.WHITE
var strength := 0.0

var _device: RenderingDevice
var _shader: RID
var _pipeline: RID
var _sampler: RID


func _init() -> void:
	effect_callback_type = EFFECT_CALLBACK_TYPE_POST_TRANSPARENT
	needs_motion_vectors = false
	RenderingServer.call_on_render_thread(_build)


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE and _device != null:
		for rid in [_sampler, _pipeline, _shader]:
			if rid.is_valid():
				_device.free_rid(rid)


func _build() -> void:
	_device = RenderingServer.get_rendering_device()
	if _device == null:
		return
	var file := load("res://shaders/compute/planet_sun_glow.glsl") as RDShaderFile
	var spirv := file.get_spirv()
	if spirv.compile_error_compute != "":
		push_warning("sun glow shader: " + spirv.compile_error_compute)
		return
	_shader = _device.shader_create_from_spirv(spirv)
	_pipeline = _device.compute_pipeline_create(_shader)
	var state := RDSamplerState.new()
	state.min_filter = RenderingDevice.SAMPLER_FILTER_NEAREST
	state.mag_filter = RenderingDevice.SAMPLER_FILTER_NEAREST
	_sampler = _device.sampler_create(state)


func _render_callback(_type: int, data: RenderData) -> void:
	if not _pipeline.is_valid() or strength <= 0.0:
		return
	var buffers := data.get_render_scene_buffers() as RenderSceneBuffersRD
	var scene := data.get_render_scene_data()
	if buffers == null or scene == null:
		return
	var size := buffers.get_internal_size()
	var camera := scene.get_cam_transform()
	var in_view := camera.affine_inverse().basis * sun_direction
	var behind := in_view.z >= 0.0
	var clip := scene.get_cam_projection() * Vector4(in_view.x, in_view.y, in_view.z, 1.0)
	var pixel := Vector2(size) * 0.5
	if clip.w > 0.0:
		pixel = Vector2((clip.x / clip.w * 0.5 + 0.5) * size.x, (0.5 + clip.y / clip.w * 0.5) * size.y)
	var push := PackedFloat32Array([pixel.x, pixel.y, size.x, size.y,
			tint.r, tint.g, tint.b, 0.0 if behind else strength])
	for view in buffers.get_view_count():
		var colour := RDUniform.new()
		colour.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
		colour.binding = 0
		colour.add_id(buffers.get_color_layer(view))
		var depth := RDUniform.new()
		depth.uniform_type = RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE
		depth.binding = 1
		depth.add_id(_sampler)
		depth.add_id(buffers.get_depth_layer(view))
		var uniform_set := UniformSetCacheRD.get_cache(_shader, 0, [colour, depth])
		var list := _device.compute_list_begin()
		_device.compute_list_bind_compute_pipeline(list, _pipeline)
		_device.compute_list_bind_uniform_set(list, uniform_set, 0)
		_device.compute_list_set_push_constant(list, push.to_byte_array(), push.size() * 4)
		_device.compute_list_dispatch(list, (size.x + 7) / 8, (size.y + 7) / 8, 1)
		_device.compute_list_end()
