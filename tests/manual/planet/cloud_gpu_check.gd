## GPU experiment: the cloud cover of the whole Earth on the GPU against the CPU cloud mask (run
## with a window: godot --path . -s tests/manual/planet/cloud_gpu_check.gd)
extends SceneTree
func _init() -> void:
	var settings := PlanetSettings.earth()
	settings.world_seed = 8
	var noise := PlanetNoise.new(settings)
	var clock := PlanetClock.new()
	clock.day_seconds = settings.day_seconds
	clock.year_days = settings.year_days
	clock.axial_tilt = deg_to_rad(settings.axial_tilt)
	PlanetCloudGpu.warm_up()
	while not PlanetCloudGpu.available():
		OS.delay_msec(50)
	print("gpu available: ", PlanetCloudGpu.available())
	var size := Vector2i(2048, 1024)
	# the CPU's cloud mask picture (and its heights: the macro the GPU needs)
	var chart := PlanetChart.new()
	chart.layer = PlanetChart.Layer.CLOUD_MASK
	chart.size = size
	chart.clock = clock
	var t0 := Time.get_ticks_msec()
	chart.start(noise)
	while not chart.finished():
		OS.delay_msec(5)
	var cpu_image := chart.texture().get_image()
	print("cpu cloud mask: ", Time.get_ticks_msec() - t0, " ms")
	var macros: PackedFloat32Array = noise.map_heights.get(size, PackedFloat32Array())
	print("macros ", macros.size())
	for run in 3:
		var t1 := Time.get_ticks_msec()
		var gpu := PlanetCloudGpu.cover(noise, clock, size.x, size.y, macros)
		print("gpu run ", run, ": ", Time.get_ticks_msec() - t1, " ms, ", gpu.size(), " pixels")
		if run == 2 and gpu.size() == size.x * size.y:
			var diff := 0.0
			var worst := 0.0
			var big := 0
			var bytes := cpu_image.get_data()
			var image := Image.create(size.x, size.y, false, Image.FORMAT_RGB8)
			for index in gpu.size():
				var d := absf(float(bytes[index * 3]) / 255.0 - gpu[index])
				diff += d
				worst = maxf(worst, d)
				if d > 0.1:
					big += 1
				var v := gpu[index]
				image.set_pixel(index % size.x, index / size.x, Color(v, v, v))
			print(("mean difference %.4f, worst %.3f, pixels off by more than 0.1: %d of %d")
					% [diff / gpu.size(), worst, big, gpu.size()])
			image.save_png("E:/Temp/claude/scratch/gpu_cover.png")
			cpu_image.save_png("E:/Temp/claude/scratch/cpu_cover.png")
	quit()
