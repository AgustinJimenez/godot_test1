class_name PlanetCloudGpu
extends RefCounted
## The cloud cover of a whole map picture worked out on the GPU (a compute shader, shaders/compute/planet_cloud_cover.glsl):
## the same maths and the same noise as the native crust's `cloud_field`, one thread a pixel. An experiment: `cover` answers an
## empty array where there is no GPU to compute on, and the chart then uses the CPU.

static var _device: RenderingDevice
static var _shader: RID
static var _pipeline: RID
static var _tried := false


static func available() -> bool:
	_open()
	return _device != null


static func _open() -> void:
	if _tried:
		return
	_tried = true
	_device = RenderingServer.create_local_rendering_device()
	if _device == null:
		return
	var file := load("res://shaders/compute/planet_cloud_cover.glsl") as RDShaderFile
	if file == null:
		_device = null
		return
	var spirv := file.get_spirv()
	if spirv.compile_error_compute != "":
		push_warning("cloud cover shader: " + spirv.compile_error_compute)
		_device = null
		return
	_shader = _device.shader_create_from_spirv(spirv)
	_pipeline = _device.compute_pipeline_create(_shader)


## The cover (0..1) of every pixel of a `width` x `height` picture of the whole planet at `clock`'s moment, row after row from
## the north; `macros` is the ground height of each pixel (its sign says land or sea).
static func cover(noise: PlanetNoise, clock: PlanetClock, width: int, height: int,
		macros: PackedFloat32Array) -> PackedFloat32Array:
	_open()
	if _device == null or macros.size() != width * height:
		return PackedFloat32Array()
	var weather: Dictionary = noise.weather.config()
	var now_grid := noise.climate.seasons.blended(clock.year_share())
	var mean_grid := noise.climate.seasons.mean
	var rain := noise.climate.rain_grid()
	var days := clock.absolute_days()
	var shear := 2.5
	var first := fposmod(days, shear)
	var second := fposmod(days + shear * 0.5, shear)
	var floats := PackedFloat32Array()
	floats.resize(32)
	floats[0] = clock.declination()
	floats[1] = weather["belt_shift"]
	floats[2] = weather["belt_power"]
	floats[3] = weather["storm_shift"]
	floats[4] = weather["storm_power"]
	floats[5] = weather["sink_shift"]
	floats[6] = weather["sink_power"]
	floats[7] = weather["pool_break"]
	floats[8] = weather["wind_k"]
	floats[9] = 0.5 + 0.5 * sin(days * 0.45)
	floats[10] = first
	floats[11] = second
	floats[12] = 1.0 - absf(2.0 * first / shear - 1.0)
	floats[13] = shear
	var ints := PackedInt32Array()
	ints.resize(32)
	# the noises in the order the shader reads them: pool, warp, big a, big b, small
	var slot := 0
	for key: String in ["pool", "warp", "big_a", "big_b", "small"]:
		var config: Array = weather[key] # [seed, frequency, octaves, fractal type]
		ints[slot * 2] = int(config[0])
		ints[slot * 2 + 1] = int(config[2])
		floats[24 + slot] = float(config[1])
		slot += 1
	ints[20] = width
	ints[21] = height
	ints[22] = PlanetSeasons.WIDTH
	ints[23] = PlanetSeasons.HEIGHT
	ints[24] = PlanetClimate.WIDTH
	ints[25] = PlanetClimate.HEIGHT
	ints[26] = 1 if mean_grid.size() >= PlanetSeasons.WIDTH * PlanetSeasons.HEIGHT else 0
	var buffers: Array[RID] = []
	var out_bytes := PackedFloat32Array()
	out_bytes.resize(width * height)
	var uniforms: Array[RDUniform] = []
	var sources: Array = [out_bytes, macros, now_grid, mean_grid, rain, floats, ints]
	for binding in sources.size():
		var data: PackedByteArray = sources[binding].to_byte_array()
		if data.is_empty():
			data.resize(4)
		var buffer := _device.storage_buffer_create(data.size(), data)
		buffers.append(buffer)
		var uniform := RDUniform.new()
		uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
		uniform.binding = binding
		uniform.add_id(buffer)
		uniforms.append(uniform)
	var set := _device.uniform_set_create(uniforms, _shader, 0)
	var list := _device.compute_list_begin()
	_device.compute_list_bind_compute_pipeline(list, _pipeline)
	_device.compute_list_bind_uniform_set(list, set, 0)
	_device.compute_list_dispatch(list, (width + 7) / 8, (height + 7) / 8, 1)
	_device.compute_list_end()
	_device.submit()
	_device.sync()
	var result := _device.buffer_get_data(buffers[0]).to_float32_array()
	_device.free_rid(set)
	for buffer in buffers:
		_device.free_rid(buffer)
	return result
