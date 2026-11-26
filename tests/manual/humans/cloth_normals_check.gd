extends SceneTree
## GPU regression: normal direction must survive small triangles (task 103).
## Run with the Vulkan renderer, not --headless (which has no RenderingDevice).

var _failed: bool = false


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var rd: RenderingDevice = RenderingServer.create_local_rendering_device()
	if rd == null:
		push_error("CLOTH_NORMALS_CHECK FAIL: RenderingDevice required")
		quit(1)
		return
	var file: RDShaderFile = load("res://addons/godot_gpu_cloth/shaders/compute/cloth_output.glsl")
	var shader: RID = rd.shader_create_from_spirv(file.get_spirv())
	var pipeline: RID = rd.compute_pipeline_create(shader)
	# Same facing, different triangle areas; also an actual degenerate triangle.
	var direction := Vector3(0.3, -0.4, 0.5).normalized()
	var normals := PackedFloat32Array()
	for scale: float in [1.0, 0.0001, 0.000001, 0.00000001, 0.0]:
		var n: Vector3 = direction * scale
		normals.append_array(PackedFloat32Array([n.x, n.y, n.z, 0.0]))
	var count: int = normals.size() / 4
	var positions := PackedByteArray()
	positions.resize(count * 16)
	var counts := PackedInt32Array()
	var offsets := PackedInt32Array()
	for i in count:
		counts.append(1)
		offsets.append(i)
	var buffers: Array[RID] = [
		rd.storage_buffer_create(positions.size(), positions),
		rd.storage_buffer_create(normals.to_byte_array().size(), normals.to_byte_array()),
		rd.storage_buffer_create(counts.to_byte_array().size(), counts.to_byte_array()),
		rd.storage_buffer_create(offsets.to_byte_array().size(), offsets.to_byte_array()),
		rd.storage_buffer_create(offsets.to_byte_array().size(), offsets.to_byte_array()),
	]
	var format := RDTextureFormat.new()
	format.width = count
	format.height = 1
	format.format = RenderingDevice.DATA_FORMAT_R32G32B32A32_SFLOAT
	format.usage_bits = RenderingDevice.TEXTURE_USAGE_STORAGE_BIT \
		| RenderingDevice.TEXTURE_USAGE_CAN_COPY_FROM_BIT
	var textures: Array[RID] = [
		rd.texture_create(format, RDTextureView.new()),
		rd.texture_create(format, RDTextureView.new()),
	]
	var uniforms: Array[RDUniform] = []
	for i in buffers.size() + textures.size():
		var uniform := RDUniform.new()
		uniform.binding = i
		uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER if i < 5 \
			else RenderingDevice.UNIFORM_TYPE_IMAGE
		uniform.add_id(buffers[i] if i < 5 else textures[i - 5])
		uniforms.append(uniform)
	var uniform_set: RID = rd.uniform_set_create(uniforms, shader, 0)
	var push := PackedByteArray()
	push.resize(16)
	push.encode_u32(0, count)
	push.encode_u32(4, count)
	var list: int = rd.compute_list_begin()
	rd.compute_list_bind_compute_pipeline(list, pipeline)
	rd.compute_list_bind_uniform_set(list, uniform_set, 0)
	rd.compute_list_set_push_constant(list, push, push.size())
	rd.compute_list_dispatch(list, 1, 1, 1)
	rd.compute_list_end()
	rd.submit()
	rd.sync()
	var output: PackedFloat32Array = rd.texture_get_data(textures[1], 0).to_float32_array()
	for i in count:
		var actual := Vector3(output[i * 4], output[i * 4 + 1], output[i * 4 + 2])
		var expected: Vector3 = direction if i < count - 1 else Vector3.UP
		if not actual.is_finite() or actual.distance_to(expected) > 0.0001:
			_failed = true
			print("CLOTH_NORMALS_CHECK FAIL sample ", i, " got ", actual, " expected ", expected)
	# Free dependencies before their buffers/textures, matching the solver's ownership.
	rd.free_rid(uniform_set)
	rd.free_rid(pipeline)
	rd.free_rid(shader)
	for rid: RID in buffers + textures:
		rd.free_rid(rid)
	rd.free()
	if not _failed:
		print("CLOTH_NORMALS_CHECK PASS: area-independent normals, degenerate fallback")
	quit(1 if _failed else 0)
