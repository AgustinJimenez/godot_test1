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
var msec_heights := 0 # time spent asking the planet (all threads)
## Voxels between the planet's height samples (1: every voxel, exact; 2-4: interpolated)
var lattice := 2
## Turns a world direction into the planet's own direction (the identity: the same). The walking
## test turns the planet so that its chosen spawn is at +Y, where the player's "up" is.
var frame := Basis.IDENTITY
var msec_asking := 0 # time spent filling the voxels (all threads)

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
	var heights := _interpolated_heights(origin, size, step)
	var started := Time.get_ticks_msec()
	var i := 0
	for z in size.z:
		for x in size.x:
			for y in size.y:
				var p := origin + Vector3(x, y, z) * step
				var sdf := (p.length() - (radius + heights[i])) / step
				out_buffer.set_voxel_f(sdf, x, y, z, VoxelBuffer.CHANNEL_SDF)
				i += 1
	var spent := Time.get_ticks_msec() - started
	_lock.lock()
	blocks_asked += 1
	msec_asking += spent
	_lock.unlock()


## The planet's ground height (m) for every voxel of the block, in the order of the loops of
## `_generate_block` (z, x, y). The planet is asked every `lattice` voxels along each axis and the
## voxels between are interpolated (`lattice` 1 asks for every voxel: exact).
func _interpolated_heights(origin: Vector3, size: Vector3i, step: float) -> PackedFloat32Array:
	var s := lattice
	var mx := (size.x - 1) / s + 2
	var my := (size.y - 1) / s + 2
	var mz := (size.z - 1) / s + 2
	var dirs := PackedVector3Array()
	dirs.resize(mx * my * mz)
	var n := 0
	for kz in mz:
		for kx in mx:
			for ky in my:
				dirs[n] = (frame * (origin + Vector3(kx, ky, kz) * (s * step))).normalized()
				n += 1
	var asked := Time.get_ticks_msec()
	var lattice_heights: PackedFloat32Array = noise.call("heights_of", dirs)
	_lock.lock()
	msec_heights += Time.get_ticks_msec() - asked
	_lock.unlock()
	# along y
	var h1 := PackedFloat32Array()
	h1.resize(mz * mx * size.y)
	for column in mz * mx:
		for y in size.y:
			var j := y / s
			var t := float(y % s) / s
			var base := column * my + j
			h1[column * size.y + y] = lerpf(lattice_heights[base], lattice_heights[base + 1], t)
	# along x
	var h2 := PackedFloat32Array()
	h2.resize(mz * size.x * size.y)
	for kz in mz:
		for x in size.x:
			var j := x / s
			var t := float(x % s) / s
			var from := (kz * mx + j) * size.y
			var to := (kz * size.x + x) * size.y
			for y in size.y:
				h2[to + y] = lerpf(h1[from + y], h1[from + size.y + y], t)
	# along z
	var h3 := PackedFloat32Array()
	h3.resize(size.z * size.x * size.y)
	var plane := size.x * size.y
	for z in size.z:
		var j := z / s
		var t := float(z % s) / s
		var from := j * plane
		var to := z * plane
		for k in plane:
			h3[to + k] = lerpf(h2[from + k], h2[from + plane + k], t)
	return h3
