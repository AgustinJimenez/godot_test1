## Times every map layer of the Earth (seed 8) with the chart profile on: godot --headless --path . -s tests/manual/planet/chart_times.gd (PLANET_CHART_PROFILE=1 prints each picture's parts)
extends SceneTree
func _init() -> void:
	var settings := PlanetSettings.earth()
	settings.world_seed = 8
	var t0 := Time.get_ticks_msec()
	var noise := PlanetNoise.new(settings)
	print("noise built ", Time.get_ticks_msec() - t0, " ms")
	var clock := PlanetClock.new()
	clock.day_seconds = settings.day_seconds
	clock.year_days = settings.year_days
	clock.axial_tilt = deg_to_rad(settings.axial_tilt)
	for dims: Vector2i in [Vector2i(2048, 1024)]:
		for layer in [0, 1, 8, 9, 10, 11, 2]:
			var chart := PlanetChart.new()
			chart.layer = layer
			chart.size = dims
			chart.clock = clock
			var start := Time.get_ticks_msec()
			chart.start(noise)
			while not chart.finished():
				OS.delay_msec(5)
			var tex := chart.texture()
			var name: String = PlanetChart.Layer.keys()[layer]
			print("%dx%d %-16s %6d ms" % [dims.x, dims.y, name, Time.get_ticks_msec() - start])
	quit()
