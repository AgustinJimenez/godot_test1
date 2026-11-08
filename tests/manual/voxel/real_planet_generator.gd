## Voxel generator for the REAL planet (task 096): the signed distance to the ground is
## |p| - (radius + PlanetNoise height of the direction of p), asked in bulk from the native
## `PlanetNoise.heights_of`. Meant for the engine with the voxel module built in
## (`E:\Godot\double\src\bin\godot.windows.editor.double.x86_64.exe`). Solid is negative.
extends VoxelGeneratorScript

## Farther from the surface than this (m) no ground height can change the sign, so the block is
## filled without asking the planet (the highest peak is about 9 km).
const RELIEF_MARGIN := 12000.0

var radius := 6371000.0
## PlanetNoise (a native class, so not typed here: the file parses without it)
var noise: Object = null
var blocks_done := 0
var blocks_asked := 0
var msec_asking := 0

var _lock := Mutex.new()


func _get_used_channels_mask() -> int:
	return 1 << VoxelBuffer.CHANNEL_SDF


func _generate_block(out_buffer: VoxelBuffer, origin_in_voxels: Vector3i, lod: int) -> void:
	var size := out_buffer.get_size()
	var step := float(1 << lod)
	var origin := Vector3(origin_in_voxels)
	var half_diagonal := size.length() * step * 0.5
	var centre := origin + Vector3(size) * step * 0.5
	var centre_dist := centre.length() - radius
	if absf(centre_dist) > RELIEF_MARGIN + half_diagonal:
		out_buffer.fill_f(centre_dist / step, VoxelBuffer.CHANNEL_SDF)
		return
	var dirs := PackedVector3Array()
	var lens := PackedFloat64Array()
	dirs.resize(size.x * size.y * size.z)
	lens.resize(size.x * size.y * size.z)
	var i := 0
	for z in size.z:
		for x in size.x:
			for y in size.y:
				var p := origin + Vector3(x, y, z) * step
				var length := p.length()
				lens[i] = length
				dirs[i] = p / length if length > 0.0 else Vector3.UP
				i += 1
	var started := Time.get_ticks_msec()
	var heights: PackedFloat32Array = noise.call("heights_of", dirs)
	var spent := Time.get_ticks_msec() - started
	i = 0
	for z in size.z:
		for x in size.x:
			for y in size.y:
				var sdf := (lens[i] - (radius + heights[i])) / step
				out_buffer.set_voxel_f(sdf, x, y, z, VoxelBuffer.CHANNEL_SDF)
				i += 1
	_lock.lock()
	blocks_asked += 1
	msec_asking += spent
	_lock.unlock()
