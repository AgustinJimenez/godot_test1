extends Node3D
## Compare the new native sea-level and tile auxiliary arrays with the script reference.


func _ready() -> void:
	var settings := PlanetSettings.new()
	settings.crust_samples = 700
	settings.water_layer = 100.0
	settings.drainage_cells = 0
	settings.species_count = 12
	var noise := PlanetNoise.new(settings)
	if noise.native == null:
		print("GENERATION_NATIVE_CHECK FAIL native crust missing")
		get_tree().quit(1)
		return
	var spots := PackedVector3Array()
	for index in settings.crust_samples:
		var y := 1.0 - 2.0 * (float(index) + 0.5) / float(settings.crust_samples)
		var ring := sqrt(1.0 - y * y)
		var angle := float(index) * 2.399963
		spots.append(Vector3(cos(angle) * ring, y, sin(angle) * ring))
	var samples: PackedFloat32Array = noise.native.call(&"tectonic_heights", spots)
	samples.sort()
	var low := samples[0]
	var high := samples[samples.size() - 1]
	for step in 40:
		var level := (low + high) * 0.5
		var depth := 0.0
		for value in samples:
			if value < level:
				depth -= noise._shore(value - level) * noise.relief
		depth /= float(samples.size())
		if depth < settings.water_layer:
			low = level
		else:
			high = level
	var expected_sea := (low + high) * 0.5
	var good := absf(noise._sea - expected_sea) < 0.00001
	var dry_sea: float = noise.native.call(&"find_sea_level", settings.crust_samples,
			settings.ocean_fraction, 0.0, noise.relief)
	good = good and absf(dry_sea - samples[int(settings.ocean_fraction * samples.size())]) < 0.00001
	var cells := 8
	var side := cells + 3
	var positions := PackedVector3Array()
	var heights := PackedFloat32Array()
	for row in side:
		for column in side:
			positions.append(Vector3(column, row * 0.2, row))
			heights.append(float(row * side + column) * 0.1)
	var low_native: float = noise.native.call(&"tile_min_height", heights, cells)
	good = good and is_equal_approx(low_native, heights[side + 1])
	var made: Dictionary = noise.native.call(&"tile_occluder", positions, cells, 2.0)
	var vertices: PackedVector3Array = made["vertices"]
	var indices: PackedInt32Array = made["indices"]
	good = good and vertices.size() == 81 and indices.size() == 384
	good = good and vertices[0].is_equal_approx(positions[side + 1] + Vector3.DOWN * 4.0)
	good = good and vertices[80].is_equal_approx(positions[9 * side + 9] + Vector3.DOWN * 4.0)
	good = good and indices.slice(0, 6) == PackedInt32Array([0, 9, 1, 1, 9, 10])
	var season_native: RefCounted = ClassDB.instantiate(&"PlanetSeasonsNative")
	var grounds := PackedFloat32Array()
	grounds.resize(PlanetSeasons.WIDTH * PlanetSeasons.HEIGHT)
	for index in grounds.size():
		grounds[index] = -1.0 if (index % PlanetSeasons.WIDTH) < 31 else 1.0
	# (the script reference of the dry land and the currents is gone with the port to C++: they are checked for shape)
	var marked: PackedByteArray = season_native.call(&"mark_sea", grounds,
			PlanetSeasons.WIDTH, PlanetSeasons.HEIGHT, PlanetSeasons.dry())
	good = good and marked.size() == grounds.size() and marked[0] == 1 and marked[grounds.size() - 1] >= 2
	var picture := PackedFloat32Array()
	picture.resize(grounds.size())
	picture.fill(20.0)
	var corrected: Dictionary = season_native.call(&"add_currents", marked,
			[picture.duplicate(), picture.duplicate()], picture.duplicate(),
			PlanetSeasons.WIDTH, PlanetSeasons.HEIGHT, PlanetSeasons.currents())
	good = good and (corrected["mean"] as PackedFloat32Array).size() == grounds.size()
	var blend: PackedFloat32Array = season_native.call(&"blend",
			PackedFloat32Array([1.0, 3.0]), PackedFloat32Array([3.0, 7.0]), 0.25)
	good = good and blend == PackedFloat32Array([1.5, 4.0])
	var clock := PlanetClock.new()
	clock.axial_tilt = deg_to_rad(23.4)
	clock.eccentricity = 0.017
	clock.perihelion_share = 0.32
	clock.insolation = 1.25
	var lights: PackedFloat32Array = season_native.call(&"light_grid", 48, 48,
			{"tilt": clock.axial_tilt, "eccentricity": clock.eccentricity,
			"perihelion": clock.perihelion_share, "insolation": clock.insolation,
			"greenhouse": 1.1})
	var light_gap := 0.0
	for moment in 48:
		clock.set_year_share((float(moment) + 0.5) / 48.0)
		for row in 48:
			var lat := (0.5 - (float(row) + 0.5) / 48.0) * PI
			light_gap = maxf(light_gap, absf(lights[moment * 48 + row] -
					clock.daily_light(lat) * clock.light_now() * 1.1))
	good = good and light_gap < 0.000001
	var map_native: RefCounted = ClassDB.instantiate(&"PlanetMapNative")
	var small := PackedFloat32Array([-1, -1, 1, 1, -1, -1, 1, 1])
	var regions: Array = map_native.call(&"regions", small, 4, 2, 0.0, 6)
	good = good and regions.size() == 2 and regions[0]["sea"] and not regions[1]["sea"]
	good = good and is_equal_approx(regions[0]["area"], 4.0 * cos(PI / 4.0))
	var wrap := PackedFloat32Array([-1, 1, 1, -1, -1, 1, 1, -1])
	var wrapped: Array = map_native.call(&"regions", wrap, 4, 2, 0.0, 6)
	good = good and wrapped.size() == 2 and wrapped[0]["sea"]
	var labels := PlanetMapLabels.new()
	labels.build(noise)
	good = good and not labels.items.is_empty() and labels.items.size() <= 12
	for label in labels.items:
		good = good and label["uv"].x >= 0.0 and label["uv"].x <= 1.0
		good = good and label["uv"].y >= 0.0 and label["uv"].y <= 1.0
	print(("GENERATION_NATIVE_CHECK %s sea_gap=%.8f light_gap=%.8f min=%.2f "
			+ "occluder=%d/%d regions=%d") % [
			"PASS" if good else "FAIL", absf(noise._sea - expected_sea), light_gap,
			low_native, vertices.size(), indices.size(), regions.size()])
	get_tree().quit(0 if good else 1)
